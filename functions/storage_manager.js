const crypto = require('crypto');
const zlib = require('zlib');

const DEFAULT_QUOTA_BYTES = Number(
  process.env.FIRESTORE_QUOTA_BYTES || 1024 * 1024 * 1024
); // 1 GiB Spark default
const WARNING_THRESHOLD_PCT = 75;
const CLEANUP_THRESHOLD_PCT = 90;
const SIGNIFICANT_GROWTH_PCT = 5;
const LOCK_LEASE_MS = 10 * 60 * 1000; // 10 minutes
const CHECK_INTERVAL_MS = 6 * 60 * 60 * 1000; // 6 hours
const HIGH_PRIORITY_CHANNEL_ID = 'shop_alerts_high_priority_v1';

/**
 * Classifies storage utilization percentage into status level.
 */
function classifyStorageStatus(utilizationPercent) {
  if (utilizationPercent >= 100) return 'full';
  if (utilizationPercent >= CLEANUP_THRESHOLD_PCT) return 'critical';
  if (utilizationPercent >= WARNING_THRESHOLD_PCT) return 'warning';
  return 'normal';
}

/**
 * Computes normalized customer Khata balances from orders + payments so
 * we NEVER archive or delete records belonging to any customer with an
 * outstanding Khata balance.
 */
function computeCustomerBalances(orders, payments) {
  const balances = new Map();
  const add = (key, delta) => {
    if (!key) return;
    balances.set(key, (balances.get(key) || 0) + delta);
  };

  for (const o of orders) {
    const key = getCustomerKey(o);
    const status = String(o.status || '').toUpperCase();
    const notes = String(o.notes || '');
    if (
      status === 'COMPLETED' ||
      status === 'CLOSED' ||
      status === 'PENDING' ||
      status === 'PARTIALLY COMPLETED' ||
      notes.includes('khata_debit')
    ) {
      add(key, Number(o.estimate_total || 0));
    }
  }

  for (const p of payments) {
    const key = getCustomerKey(p);
    add(key, -Number(p.amount || 0));
  }

  return balances;
}

function getCustomerKey(doc) {
  const phone = String(doc.customer_phone || '')
    .replace(/[^0-9]/g, '')
    .replace(/^0+/, '');
  if (phone.length >= 10) return `p:${phone.slice(-10)}`;
  if (phone.length >= 6) return `p:${phone}`;
  if (doc.customer_id !== undefined && doc.customer_id !== null) {
    return `id:${doc.customer_id}`;
  }
  const name = String(doc.customer_name_snapshot || doc.customer_name || '')
    .trim()
    .toLowerCase();
  return name ? `n:${name}` : null;
}

/**
 * Checks if an order is strictly eligible for historical archiving & cleanup.
 */
function isOrderEligible(order, customerBalances, now) {
  if (!order) return false;
  if (order.disputed === true) return false;

  const status = String(order.status || '').toUpperCase();
  if (status !== 'COMPLETED' && status !== 'CLOSED') return false;

  const payStatus = String(order.payment_status || 'unpaid').toLowerCase();
  if (payStatus === 'unpaid' || payStatus === 'partial') return false;

  const total = Number(order.estimate_total || 0);
  const paid = Number(order.paid_amount || 0);
  if (total - paid > 0.01) return false;

  const notes = String(order.notes || '').toLowerCase();
  if (notes.includes('dispute') || notes.includes('unresolved')) return false;

  // Never delete orders belonging to a customer with any non-zero Khata balance
  const custKey = getCustomerKey(order);
  if (custKey && Math.abs(customerBalances.get(custKey) || 0) > 0.01) {
    return false;
  }

  // Never delete records from the most recent month (last 30 days)
  const createdAt = parseDate(order.created_at);
  if (!createdAt) return false;
  const ageDays = (now.getTime() - createdAt.getTime()) / (24 * 60 * 60 * 1000);
  if (ageDays < 30) return false;

  return true;
}

/**
 * Computes delivery partner balances from delivery_transactions.
 */
function computePartnerBalances(deliveryTxs) {
  const balances = new Map();
  for (const tx of deliveryTxs) {
    const pid = String(tx.pc || tx.partner_cloud_id || tx.pn || tx.partner_name || '');
    if (!pid) continue;
    const earned = Number(tx.e ?? tx.earned_amount ?? 0);
    const paid = Number(tx.pa ?? tx.paid_amount ?? 0);
    balances.set(pid, (balances.get(pid) || 0) + (earned - paid));
  }
  return balances;
}

function isDeliveryTxEligible(tx, partnerBalances, now) {
  if (!tx) return false;
  const pid = String(tx.pc || tx.partner_cloud_id || tx.pn || tx.partner_name || '');
  if (pid && Math.abs(partnerBalances.get(pid) || 0) > 0.01) {
    return false;
  }
  const createdAt = parseDate(tx.c ?? tx.created_at);
  if (!createdAt) return false;
  const ageDays = (now.getTime() - createdAt.getTime()) / (24 * 60 * 60 * 1000);
  return ageDays >= 30;
}

function parseDate(raw) {
  if (typeof raw === 'number' && Number.isFinite(raw)) {
    return new Date(raw);
  }
  if (typeof raw === 'string' && raw.trim()) {
    const d = new Date(raw);
    if (!Number.isNaN(d.getTime())) return d;
  }
  return null;
}

/**
 * Selects the archive window according to Rule A & Rule B:
 * - Rule A: If oldest eligible record is < 365 days old -> 1 month from oldest.
 * - Rule B: If oldest eligible record is >= 365 days old -> 3 months from oldest.
 * - Never includes records newer than (now - 30 days).
 */
function selectCleanupWindow(eligibleRecords, now) {
  if (!eligibleRecords || eligibleRecords.length === 0) {
    return { ruleApplied: 'none', windowEnd: null, selected: [] };
  }

  const sorted = [...eligibleRecords].sort((a, b) => a.date - b.date);
  const oldestDate = sorted[0].date;
  const ageDays = (now.getTime() - oldestDate.getTime()) / (24 * 60 * 60 * 1000);
  const recentCutoff = new Date(now.getTime() - 30 * 24 * 60 * 60 * 1000);

  const monthsToArchive = ageDays >= 365 ? 3 : 1;
  const ruleApplied = ageDays >= 365 ? 'rule_b_3_months' : 'rule_a_1_month';

  const rawEnd = new Date(oldestDate.getTime());
  rawEnd.setUTCMonth(rawEnd.getUTCMonth() + monthsToArchive);
  const windowEnd = rawEnd < recentCutoff ? rawEnd : recentCutoff;

  const selected = sorted.filter((r) => r.date <= windowEnd);
  return {
    ruleApplied,
    windowStart: oldestDate,
    windowEnd,
    selected,
  };
}

/**
 * Queries actual Firestore database storage usage via GCP Cloud Monitoring API.
 * Falls back to server-side Firestore database document+index measurement if
 * Cloud Monitoring time-series has not populated yet. Never reads SQLite.
 */
async function fetchActualFirestoreStorageBytes({
  admin,
  monitoringClient,
  projectId,
}) {
  // 1. Primary: GCP Cloud Monitoring metric for Firestore storage size
  if (monitoringClient && projectId) {
    try {
      const nowSec = Math.floor(Date.now() / 1000);
      const startSec = nowSec - 24 * 60 * 60; // look back up to 24h for latest point
      const [timeSeries] = await monitoringClient.listTimeSeries({
        name: `projects/${projectId}`,
        filter:
          'metric.type="firestore.googleapis.com/storage/data_and_index_size"',
        interval: {
          startTime: { seconds: startSec },
          endTime: { seconds: nowSec },
        },
        view: 'FULL',
      });

      let latestVal = null;
      let latestEndSec = 0;
      for (const series of timeSeries || []) {
        for (const point of series.points || []) {
          const endSec = Number(point.interval?.endTime?.seconds || 0);
          const val = Number(
            point.value?.int64Value ?? point.value?.doubleValue ?? 0
          );
          if (endSec >= latestEndSec && val > 0) {
            latestEndSec = endSec;
            latestVal = val;
          }
        }
      }
      if (latestVal !== null && latestVal >= 0) {
        return {
          usedBytes: latestVal,
          metricSource: 'gcp_cloud_monitoring',
        };
      }
    } catch (err) {
      console.warn(
        '[StorageMonitor] Cloud Monitoring query unavailable, using Firestore server stats:',
        err.message || err
      );
    }
  }

  // 2. Fallback: Server-side Firestore document + index overhead calculation (not SQLite)
  const db = admin.firestore();
  let totalBytes = 0;
  const collections = await db.listCollections();

  async function measureCollection(colRef) {
    const snap = await colRef.get();
    for (const doc of snap.docs) {
      const jsonSize = Buffer.byteLength(JSON.stringify(doc.data() || {}), 'utf8');
      const pathOverhead = Buffer.byteLength(doc.ref.path, 'utf8') + 64;
      totalBytes += jsonSize + pathOverhead;
      const subCols = await doc.ref.listCollections();
      for (const sub of subCols) {
        await measureCollection(sub);
      }
    }
  }

  for (const col of collections) {
    await measureCollection(col);
  }

  return {
    usedBytes: totalBytes,
    metricSource: 'firestore_server_usage',
  };
}

/**
 * Recursively deletes a Firestore document and all of its subcollections.
 */
async function deleteDocAndSubcollections(db, docRef) {
  const subCols = await docRef.listCollections();
  for (const subCol of subCols) {
    const subSnap = await subCol.get();
    for (const subDoc of subSnap.docs) {
      await deleteDocAndSubcollections(db, subDoc.ref);
    }
  }
  await docRef.delete();
}

/**
 * Evaluates threshold, sends notifications only on crossing or significant growth,
 * runs idempotent locked cleanup (Rules A/B/C), archives & verifies before deletion,
 * and updates Firestore status + audit logs.
 */
async function evaluateAndManageShopStorage({
  admin,
  shopCode,
  monitoringClient = null,
  projectId = process.env.GCLOUD_PROJECT || process.env.GCP_PROJECT,
  quotaBytesOverride = null,
  storageUsageOverride = null,
  now = new Date(),
  jobId = `job_${Date.now()}`,
}) {
  const db = admin.firestore();
  const shopRef = db.collection('shops').doc(shopCode);
  const statusRef = shopRef.collection('system').doc('storage_status');
  const lockRef = shopRef.collection('system').doc('cleanup_lock');

  // Acquire distributed transaction lock to ensure only one device/job runs
  const lockAcquired = await db.runTransaction(async (txn) => {
    const lockSnap = await txn.get(lockRef);
    const lockData = lockSnap.exists ? lockSnap.data() : null;
    const expiresAt = lockData?.expiresAt ? Number(lockData.expiresAt) : 0;
    if (lockData?.status === 'running' && expiresAt > now.getTime()) {
      return false;
    }
    txn.set(lockRef, {
      status: 'running',
      jobId,
      startedAt: now.toISOString(),
      expiresAt: now.getTime() + LOCK_LEASE_MS,
    });
    return true;
  });

  if (!lockAcquired) {
    return { skipped: true, reason: 'cleanup_already_running' };
  }

  try {
    const existingStatusSnap = await statusRef.get();
    const prevStatus = existingStatusSnap.exists ? existingStatusSnap.data() : {};
    const quotaBytes = Number(
      quotaBytesOverride || prevStatus.quotaBytes || DEFAULT_QUOTA_BYTES
    );

    const measure = async () => {
      if (typeof storageUsageOverride === 'function') {
        return await storageUsageOverride();
      }
      if (typeof storageUsageOverride === 'number') {
        return { usedBytes: storageUsageOverride, metricSource: 'override' };
      }
      return await fetchActualFirestoreStorageBytes({
        admin,
        monitoringClient,
        projectId,
      });
    };

    let usage = await measure();
    let usedBytes = usage.usedBytes;
    let pct = quotaBytes > 0 ? (usedBytes / quotaBytes) * 100 : 0;
    const initialBytes = usedBytes;

    let totalArchivedCount = 0;
    let lastArchiveId = prevStatus.lastArchiveAt || null;
    let lastCleanupAt = prevStatus.lastCleanupAt || null;
    let insufficientEligibleData = false;
    let iterations = 0;
    const MAX_ITERATIONS = 6;

    // Rule C loop: repeat cleanup while storage >= 90% and eligible data exists
    while (pct >= CLEANUP_THRESHOLD_PCT && iterations < MAX_ITERATIONS) {
      iterations += 1;

      const [ordersSnap, paymentsSnap, deliveryTxSnap] = await Promise.all([
        shopRef.collection('orders').get(),
        shopRef.collection('payments').get(),
        shopRef.collection('delivery_transactions').get(),
      ]);

      const allOrders = ordersSnap.docs.map((d) => ({
        docId: d.id,
        ref: d.ref,
        collection: 'orders',
        data: d.data(),
        date: parseDate(d.data().created_at),
      }));
      const allPayments = paymentsSnap.docs.map((d) => ({
        docId: d.id,
        ref: d.ref,
        collection: 'payments',
        data: d.data(),
        date: parseDate(d.data().created_at),
      }));
      const allDeliveryTxs = deliveryTxSnap.docs.map((d) => ({
        docId: d.id,
        ref: d.ref,
        collection: 'delivery_transactions',
        data: d.data(),
        date: parseDate(d.data().c ?? d.data().created_at),
      }));

      const customerBalances = computeCustomerBalances(
        allOrders.map((x) => x.data),
        allPayments.map((x) => x.data)
      );
      const partnerBalances = computePartnerBalances(
        allDeliveryTxs.map((x) => x.data)
      );

      const eligible = [];
      for (const o of allOrders) {
        if (isOrderEligible(o.data, customerBalances, now)) {
          eligible.push(o);
        }
      }
      for (const p of allPayments) {
        const custKey = getCustomerKey(p.data);
        const balOk = !custKey || Math.abs(customerBalances.get(custKey) || 0) <= 0.01;
        const ageDays = p.date
          ? (now.getTime() - p.date.getTime()) / (24 * 60 * 60 * 1000)
          : 0;
        if (balOk && ageDays >= 30) {
          eligible.push(p);
        }
      }
      for (const dtx of allDeliveryTxs) {
        if (isDeliveryTxEligible(dtx.data, partnerBalances, now)) {
          eligible.push(dtx);
        }
      }

      const window = selectCleanupWindow(eligible, now);
      if (window.selected.length === 0) {
        insufficientEligibleData = true;
        await shopRef.collection('storage_audit_logs').add({
          action: 'cleanup_skipped_no_eligible_records',
          jobId,
          status: 'warning',
          bytesBefore: usedBytes,
          utilizationPercent: Number(pct.toFixed(2)),
          timestamp: now.toISOString(),
        });
        break;
      }

      // Create and verify dated archive BEFORE deleting any cloud records
      const archiveId = `arch_${now.toISOString().slice(0, 10)}_${Date.now()}`;
      const payloadObj = {
        archiveId,
        shopCode,
        createdAt: now.toISOString(),
        dateRangeStart: window.windowStart.toISOString(),
        dateRangeEnd: window.windowEnd.toISOString(),
        records: window.selected.map((item) => ({
          collection: item.collection,
          docId: item.docId,
          data: item.data,
        })),
      };
      const payloadJson = JSON.stringify(payloadObj);
      const checksum = crypto
        .createHash('sha256')
        .update(payloadJson)
        .digest('hex');
      const compressedBase64 = zlib
        .gzipSync(Buffer.from(payloadJson, 'utf8'))
        .toString('base64');

      const archiveRef = shopRef.collection('storage_archives').doc(archiveId);
      await archiveRef.set({
        archiveId,
        ruleApplied: window.ruleApplied,
        dateRangeStart: window.windowStart.toISOString(),
        dateRangeEnd: window.windowEnd.toISOString(),
        recordCount: window.selected.length,
        archivedDocIds: window.selected.map((x) => `${x.collection}/${x.docId}`),
        checksum,
        compressedGzipBase64: compressedBase64,
        verified: false,
        createdAt: now.toISOString(),
      });

      // Verify archive readability & integrity before deleting source docs
      const verifySnap = await archiveRef.get();
      if (!verifySnap.exists) {
        throw new Error(`Archive verification failed: ${archiveId} not readable`);
      }
      const verifyData = verifySnap.data();
      const restoredBuf = zlib.gunzipSync(
        Buffer.from(verifyData.compressedGzipBase64, 'base64')
      );
      const restoredHash = crypto
        .createHash('sha256')
        .update(restoredBuf)
        .digest('hex');
      const parsedRestore = JSON.parse(restoredBuf.toString('utf8'));
      if (
        restoredHash !== checksum ||
        !Array.isArray(parsedRestore.records) ||
        parsedRestore.records.length !== window.selected.length
      ) {
        throw new Error(`Archive integrity check failed for ${archiveId}`);
      }
      await archiveRef.update({ verified: true });
      lastArchiveId = now.toISOString();

      // Safe to delete verified archived records & explicit subcollections
      for (const item of window.selected) {
        await deleteDocAndSubcollections(db, item.ref);
      }

      totalArchivedCount += window.selected.length;
      lastCleanupAt = now.toISOString();

      // Recheck actual Firestore storage usage (Rule C)
      const afterUsage = await measure();
      const bytesAfter = afterUsage.usedBytes;
      const reclaimed = Math.max(0, usedBytes - bytesAfter);

      await shopRef.collection('storage_audit_logs').add({
        action: 'archive_and_cleanup',
        jobId,
        archiveId,
        ruleApplied: window.ruleApplied,
        status: 'success',
        recordsArchived: window.selected.length,
        recordsDeleted: window.selected.length,
        dateRangeStart: window.windowStart.toISOString(),
        dateRangeEnd: window.windowEnd.toISOString(),
        bytesBefore: usedBytes,
        bytesAfter,
        reclaimedBytes: reclaimed,
        timestamp: now.toISOString(),
      });

      usedBytes = bytesAfter;
      pct = quotaBytes > 0 ? (usedBytes / quotaBytes) * 100 : 0;

      if (reclaimed === 0 && pct >= CLEANUP_THRESHOLD_PCT) {
        // Avoid infinite loop if backend metric hasn't settled in the same tick
        break;
      }
    }

    const remainingBytes = Math.max(0, quotaBytes - usedBytes);
    const statusLevel = classifyStorageStatus(pct);
    const nextCheckAt = new Date(now.getTime() + CHECK_INTERVAL_MS).toISOString();

    // Threshold-crossing & significant-growth notification logic
    const prevPct = Number(prevStatus.utilizationPercent || 0);
    const prevNotifiedPct = Number(prevStatus.lastNotifiedPercent || 0);
    const crossed90 =
      pct >= CLEANUP_THRESHOLD_PCT && prevPct < CLEANUP_THRESHOLD_PCT;
    const significantGrowthAfterCleanup =
      pct >= CLEANUP_THRESHOLD_PCT &&
      prevNotifiedPct >= CLEANUP_THRESHOLD_PCT &&
      pct - prevNotifiedPct >= SIGNIFICANT_GROWTH_PCT;

    let notificationSent = false;
    let lastNotifiedPercent = prevNotifiedPct;
    if (crossed90 || significantGrowthAfterCleanup || insufficientEligibleData) {
      const cleanShop = shopCode
        .trim()
        .toLowerCase()
        .replace(/[^a-zA-Z0-9-_.~%]/g, '_');
      const topic = `shop_${cleanShop}_alerts`;
      const title = insufficientEligibleData
        ? '⚠️ Cloud Storage Critical — Upgrade Recommended'
        : '⚠️ Storage Almost Full!';
      const body = insufficientEligibleData
        ? `Cloud database is at ${pct.toFixed(1)}% with no more eligible old records to archive. Please increase your storage capacity.`
        : 'Storage Almost Full! Your cloud database has reached 90% capacity. Automatic storage management will now identify eligible old records for archiving and cleanup. Please review your backup status.';

      try {
        await admin.messaging().send({
          topic,
          notification: { title, body },
          data: {
            screen: 'storage_management',
            utilization_percent: pct.toFixed(1),
          },
          android: {
            priority: 'high',
            notification: {
              channelId: HIGH_PRIORITY_CHANNEL_ID,
              priority: 'max',
              defaultSound: true,
              visibility: 'public',
            },
          },
        });
        notificationSent = true;
        lastNotifiedPercent = Number(pct.toFixed(2));
      } catch (fcmErr) {
        console.warn('[StorageMonitor] FCM notification error:', fcmErr.message);
      }
    } else if (pct < CLEANUP_THRESHOLD_PCT) {
      lastNotifiedPercent = 0;
    }

    const reclaimedTotal = Math.max(0, initialBytes - usedBytes);
    const statusPayload = {
      quotaBytes,
      usedBytes,
      remainingBytes,
      utilizationPercent: Number(pct.toFixed(2)),
      statusLevel,
      metricSource: usage.metricSource,
      lastCheckAt: now.toISOString(),
      nextCheckAt,
      lastArchiveAt: lastArchiveId,
      lastCleanupAt,
      archivedRecordCount:
        Number(prevStatus.archivedRecordCount || 0) + totalArchivedCount,
      lastReclaimedBytes: reclaimedTotal,
      insufficientEligibleData,
      lastNotifiedPercent,
      updatedAt: now.toISOString(),
    };

    await statusRef.set(statusPayload, { merge: true });
    return {
      skipped: false,
      status: statusPayload,
      archivedNow: totalArchivedCount,
      notificationSent,
    };
  } finally {
    await lockRef.set({
      status: 'idle',
      lastJobId: jobId,
      finishedAt: new Date().toISOString(),
      expiresAt: 0,
    });
  }
}

module.exports = {
  DEFAULT_QUOTA_BYTES,
  WARNING_THRESHOLD_PCT,
  CLEANUP_THRESHOLD_PCT,
  classifyStorageStatus,
  computeCustomerBalances,
  isOrderEligible,
  computePartnerBalances,
  isDeliveryTxEligible,
  selectCleanupWindow,
  fetchActualFirestoreStorageBytes,
  deleteDocAndSubcollections,
  evaluateAndManageShopStorage,
};
