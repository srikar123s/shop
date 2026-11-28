const functions = require('firebase-functions/v1');
const admin = require('firebase-admin');
const { MetricServiceClient } = require('@google-cloud/monitoring');
const { evaluateAndManageShopStorage } = require('./storage_manager');
admin.initializeApp();

const monitoringClient = new MetricServiceClient();

const HIGH_PRIORITY_CHANNEL_ID = 'shop_alerts_high_priority_v1';

/**
 * Helper to get current date/time parts in the configured shop timezone.
 */
function getClockInZone(timeZone = 'Asia/Kolkata') {
  const safeZone = typeof timeZone === 'string' && timeZone.trim() ? timeZone.trim() : 'Asia/Kolkata';
  const now = new Date();
  let parts;
  try {
    parts = new Intl.DateTimeFormat('en-US', {
      timeZone: safeZone,
      hour: 'numeric',
      minute: 'numeric',
      hour12: false,
    }).formatToParts(now);
  } catch (_) {
    parts = new Intl.DateTimeFormat('en-US', {
      timeZone: 'Asia/Kolkata',
      hour: 'numeric',
      minute: 'numeric',
      hour12: false,
    }).formatToParts(now);
  }
  const hourPart = parts.find((p) => p.type === 'hour');
  const minPart = parts.find((p) => p.type === 'minute');
  const hour = hourPart ? Number(hourPart.value) % 24 : 0;
  const minute = minPart ? Number(minPart.value) : 0;
  return { hour, minute };
}

/**
 * Processes items in bounded parallel batches so multi-tenant cron jobs
 * complete quickly without hitting Cloud Function timeouts or overwhelming connections.
 */
async function runInChunks(items, concurrency, worker) {
  const safeConcurrency = Math.max(1, concurrency);
  for (let i = 0; i < items.length; i += safeConcurrency) {
    const chunk = items.slice(i, i + safeConcurrency);
    await Promise.allSettled(chunk.map((item) => worker(item)));
  }
}

/**
 * Triggered whenever a device requests a cloud broadcast notification in Firestore:
 * shops/{shopCode}/outbound_notifications/{docId}
 * Sends high-priority push message to all devices subscribed to `shop_${shopCode}_alerts`.
 */
exports.onOutboundNotification = functions.firestore
  .document('shops/{shopCode}/outbound_notifications/{notifId}')
  .onCreate(async (snap, context) => {
    const data = snap.data() || {};
    const rawShopCode = context.params.shopCode || '';
    const cleanShopCode = rawShopCode.trim().toLowerCase().replace(/[^a-zA-Z0-9-_.~%]/g, '_');
    const topic = data.target_topic || `shop_${cleanShopCode}_alerts`;

    const title = data.title || 'Shop Alert';
    const body = data.body || '';
    const payloadData = {
      title: String(title),
      body: String(body),
      sender_device_id: String(data.sender_device_id || ''),
    };
    if (data.data && typeof data.data === 'object') {
      for (const [k, v] of Object.entries(data.data)) {
        payloadData[k] = String(v);
      }
    }

    const message = {
      topic: topic,
      notification: {
        title: title,
        body: body,
      },
      data: payloadData,
      android: {
        priority: 'high',
        notification: {
          channelId: HIGH_PRIORITY_CHANNEL_ID,
          priority: 'max',
          defaultSound: true,
          defaultVibrateTimings: true,
          visibility: 'public',
        },
      },
    };

    try {
      const response = await admin.messaging().send(message);
      console.log(`[FCM] Successfully dispatched alert to topic "${topic}": ${response}`);
      return snap.ref.update({
        dispatched: true,
        dispatchedAt: admin.firestore.FieldValue.serverTimestamp(),
        messageId: response,
      });
    } catch (error) {
      console.error(`[FCM] Error dispatching to topic "${topic}":`, error);
      return snap.ref.update({
        error: String(error),
      });
    }
  });

/**
 * Automatic Multi-Device Order Push:
 * Whenever ANY device creates a new order in Firestore (`shops/{shopCode}/orders/{orderId}`),
 * dispatches a high-priority FCM alert so closed/locked partner & owner phones ring immediately.
 */
exports.onOrderCreated = functions.firestore
  .document('shops/{shopCode}/orders/{orderId}')
  .onCreate(async (snap, context) => {
    const data = snap.data() || {};
    const rawShopCode = context.params.shopCode || '';
    const cleanShopCode = rawShopCode.trim().toLowerCase().replace(/[^a-zA-Z0-9-_.~%]/g, '_');
    const topic = `shop_${cleanShopCode}_alerts`;

    const takenBy = data.taken_by || 'Partner Device';
    const custName = data.customer_name_snapshot || 'Customer';
    const orderNum = data.order_number || data.id;
    const estTotal = Number(data.estimate_total || 0);
    const formattedOrd = orderNum ? `#ORD-${String(orderNum).padStart(4, '0')} ` : '';
    const totalStr = estTotal > 0 ? ` (₹${Math.round(estTotal)})` : '';

    const title = `📋 New Order from ${takenBy}`;
    const body = `${formattedOrd}for ${custName}${totalStr} synced across devices.`;

    const message = {
      topic: topic,
      notification: {
        title: title,
        body: body,
      },
      data: {
        screen: 'pending_orders',
        sender_device_id: String(data.lastUpdatedByDevice || ''),
        order_number: String(orderNum || ''),
      },
      android: {
        priority: 'high',
        notification: {
          channelId: HIGH_PRIORITY_CHANNEL_ID,
          priority: 'max',
          defaultSound: true,
          defaultVibrateTimings: true,
          visibility: 'public',
        },
      },
    };

    try {
      const response = await admin.messaging().send(message);
      console.log(`[FCM] Order created push sent to "${topic}": ${response}`);
    } catch (e) {
      console.error(`[FCM] Order created push failed for "${topic}":`, e);
    }
    return null;
  });

/**
 * Scheduled Cron Function: Runs every 30 minutes.
 * Respects each shop's custom `timezone` and `notification_settings` synced in Firestore.
 */
exports.scheduledShopAlerts = functions.pubsub
  .schedule('*/30 * * * *')
  .timeZone('Asia/Kolkata')
  .onRun(async () => {
    const matchesTime = (hhmm, nowTotal) => {
      if (!hhmm || typeof hhmm !== 'string') return false;
      const parts = hhmm.split(':');
      if (parts.length < 2) return false;
      const h = Number(parts[0]);
      const m = Number(parts[1]);
      if (Number.isNaN(h) || Number.isNaN(m)) return false;
      const targetTotal = h * 60 + m;
      return nowTotal >= targetTotal && nowTotal < targetTotal + 30;
    };

    const shopsSnap = await admin.firestore().collection('shops').get();
    await runInChunks(shopsSnap.docs, 10, async (shopDoc) => {
      const rawShopCode = shopDoc.id || '';
      const cleanShopCode = rawShopCode.trim().toLowerCase().replace(/[^a-zA-Z0-9-_.~%]/g, '_');
      const shopData = shopDoc.data() || {};
      const shopName = shopData.shopName || 'Shop';
      const notifSettings = shopData.notification_settings || {};
      if (notifSettings.enabled === false) return;

      const shopTz = shopData.timezone || notifSettings.timezone || 'Asia/Kolkata';
      const { hour, minute } = getClockInZone(shopTz);
      const nowTotal = hour * 60 + minute;

      const topic = `shop_${cleanShopCode}_alerts`;
      const alertsToSend = [];

      if (notifSettings.pending_enabled !== false) {
        const mode = notifSettings.pending_mode || 'scheduled';
        const pendingTimes = Array.isArray(notifSettings.pending_times)
          ? notifSettings.pending_times
          : ['10:00', '14:00', '19:00'];

        const shouldSendPending =
          (mode === 'hourly' && hour >= 7 && hour <= 21 && minute < 30) ||
          ((mode === 'two_hours' || mode === 'every2hours') &&
            hour >= 8 &&
            hour <= 20 &&
            hour % 2 === 0 &&
            minute < 30) ||
          (mode === 'scheduled' && pendingTimes.some((t) => matchesTime(t, nowTotal)));

        if (shouldSendPending) {
          alertsToSend.push({
            title: `📋 Pending Orders Reminder - ${shopName}`,
            body: 'Review unfulfilled counter orders and close completed customer bills.',
            screen: 'pending_orders',
          });
        }
      }

      if (notifSettings.procure_enabled !== false) {
        const procureTimes = Array.isArray(notifSettings.procure_times)
          ? notifSettings.procure_times
          : ['09:30', '17:30'];
        if (procureTimes.some((t) => matchesTime(t, nowTotal))) {
          alertsToSend.push({
            title: `📦 Procurement Reminder - ${shopName}`,
            body: 'Check short or out-of-stock items required for customer orders.',
            screen: 'procurement',
          });
        }
      }

      if (notifSettings.daily_report_enabled !== false) {
        const reportTime = notifSettings.daily_report_time || '21:00';
        if (matchesTime(reportTime, nowTotal)) {
          alertsToSend.push({
            title: `🌙 Day-End Closing Report - ${shopName}`,
            body: "Check today's total sales, completed orders, and collected udhaar.",
            screen: 'daily_report',
          });
        }
      }

      for (const alert of alertsToSend) {
        const message = {
          topic: topic,
          notification: { title: alert.title, body: alert.body },
          data: { screen: alert.screen },
          android: {
            priority: 'high',
            notification: {
              channelId: HIGH_PRIORITY_CHANNEL_ID,
              priority: 'max',
              defaultSound: true,
              defaultVibrateTimings: true,
              visibility: 'public',
            },
          },
        };
        try {
          await admin.messaging().send(message);
          console.log(`[Cron] Sent "${alert.screen}" alert to shop topic ${topic}`);
        } catch (e) {
          console.error(`[Cron] Failed sending to ${topic}:`, e);
        }
      }
    });
    return null;
  });

/**
 * Scheduled Storage Monitor: Runs every 6 hours to check per-shop Firestore storage
 * and execute automatic cleanup >= 90% in bounded parallel batches.
 */
exports.scheduledStorageMonitor = functions.pubsub
  .schedule('every 6 hours')
  .timeZone('Asia/Kolkata')
  .onRun(async () => {
    const shopsSnap = await admin.firestore().collection('shops').get();
    await runInChunks(shopsSnap.docs, 5, async (shopDoc) => {
      try {
        await evaluateAndManageShopStorage({
          admin,
          shopCode: shopDoc.id,
          monitoringClient,
          jobId: `sched_${Date.now()}_${shopDoc.id}`,
        });
      } catch (err) {
        console.error(`[StorageMonitor] Failed for shop ${shopDoc.id}:`, err);
      }
    });
    return null;
  });

/**
 * On-demand Storage Check Trigger: Activated when the shop owner requests
 * a storage check via shops/{shopCode}/system/storage_check_request.
 * Enforces a 5-minute cooldown between manual checks unless `force: true`.
 */
exports.onStorageCheckRequested = functions.firestore
  .document('shops/{shopCode}/system/storage_check_request')
  .onWrite(async (change, context) => {
    const data = change.after.exists ? change.after.data() : null;
    if (!data || data.status !== 'requested') return null;

    const shopCode = context.params.shopCode;
    try {
      const statusSnap = await admin
        .firestore()
        .collection('shops')
        .doc(shopCode)
        .collection('system')
        .doc('storage_status')
        .get();
      const lastCheckIso = statusSnap.exists ? statusSnap.data()?.lastCheckAt : null;
      const lastCheckMs = lastCheckIso ? Date.parse(lastCheckIso) : 0;
      if (!data.force && Number.isFinite(lastCheckMs) && Date.now() - lastCheckMs < 5 * 60 * 1000) {
        await change.after.ref.set(
          {
            status: 'rate_limited',
            completedAt: new Date().toISOString(),
          },
          { merge: true }
        );
        return null;
      }

      const result = await evaluateAndManageShopStorage({
        admin,
        shopCode,
        monitoringClient,
        jobId: `manual_${Date.now()}_${shopCode}`,
      });
      await change.after.ref.set(
        {
          status: result.skipped ? 'already_running' : 'completed',
          completedAt: new Date().toISOString(),
        },
        { merge: true }
      );
    } catch (err) {
      await change.after.ref.set(
        {
          status: 'error',
          error: String(err),
          completedAt: new Date().toISOString(),
        },
        { merge: true }
      );
    }
    return null;
  });
