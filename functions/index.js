const functions = require('firebase-functions');
const admin = require('firebase-admin');
admin.initializeApp();

/**
 * Triggered whenever a device requests a cloud broadcast notification in Firestore:
 * shops/{shopCode}/outbound_notifications/{docId}
 * Sends high-priority push message to all devices subscribed to `shop_${shopCode}_alerts`.
 */
exports.onOutboundNotification = functions.firestore
  .document('shops/{shopCode}/outbound_notifications/{notifId}')
  .onCreate(async (snap, context) => {
    const data = snap.data();
    const rawShopCode = context.params.shopCode || '';
    const cleanShopCode = rawShopCode.trim().toLowerCase().replace(/[^a-zA-Z0-9-_.~%]/g, '_');
    const topic = data.target_topic || `shop_${cleanShopCode}_alerts`;

    const title = data.title || 'Shop Alert';
    const body = data.body || '';
    const payloadData = {};
    if (data.data) {
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
          channelId: 'shop_order_reminders',
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
 * Scheduled Cron Function: Runs daily at 10:00 AM, 2:00 PM, and 9:00 PM IST (Asia/Kolkata)
 * Scans active shops for pending orders, procurement shortages, and daily closing report.
 */
exports.scheduledShopAlerts = functions.pubsub
  .schedule('0 10,14,21 * * *')
  .timeZone('Asia/Kolkata')
  .onRun(async (context) => {
    const now = new Date();
    const hours = now.getHours(); // 10, 14, 21
    console.log(`[Cron] Checking scheduled shop reminders for hour: ${hours}`);

    const shopsSnap = await admin.firestore().collection('shops').get();
    for (const shopDoc of shopsSnap.docs) {
      const rawShopCode = shopDoc.id || '';
      const cleanShopCode = rawShopCode.trim().toLowerCase().replace(/[^a-zA-Z0-9-_.~%]/g, '_');
      const shopData = shopDoc.data();
      const shopName = shopData.shopName || 'Shop';
      const topic = `shop_${cleanShopCode}_alerts`;

      let title = '';
      let body = '';

      if (hours === 10) {
        title = `🌅 Morning Briefing - ${shopName}`;
        body = `Review pending orders and items needing procurement for today.`;
      } else if (hours === 14) {
        title = `📋 Afternoon Counter Check - ${shopName}`;
        body = `Check open customer orders waiting for delivery or packing.`;
      } else if (hours === 21) {
        title = `🌙 Day-End Closing Report - ${shopName}`;
        body = `Check today's total sales, completed orders, and collected udhaar.`;
      }

      if (title && body) {
        const message = {
          topic: topic,
          notification: { title, body },
          data: { screen: hours === 21 ? 'report' : 'home' },
          android: {
            priority: 'high',
            notification: {
              channelId: 'shop_order_reminders',
              priority: 'max',
              defaultSound: true,
              defaultVibrateTimings: true,
            },
          },
        };
        try {
          await admin.messaging().send(message);
          console.log(`[Cron] Sent ${hours}:00 alert to shop topic ${topic}`);
        } catch (e) {
          console.error(`[Cron] Failed sending to ${topic}:`, e);
        }
      }
    }
    return null;
  });
