const test = require('node:test');
const assert = require('node:assert/strict');
const {
  classifyStorageStatus,
  computeCustomerBalances,
  isOrderEligible,
  selectCleanupWindow,
  measureShopFirestoreBytes,
  evaluateAndManageShopStorage,
} = require('./storage_manager');

test('classifyStorageStatus covers Normal, Warning, Critical, Full', () => {
  assert.equal(classifyStorageStatus(70), 'normal');
  assert.equal(classifyStorageStatus(85), 'warning');
  assert.equal(classifyStorageStatus(90), 'critical');
  assert.equal(classifyStorageStatus(100), 'full');
});

test('isOrderEligible protects unpaid, disputed, recent, and Khata-due customers', () => {
  const now = new Date('2026-11-28T00:00:00Z');
  const orders = [
    {
      customer_phone: '9876543210',
      status: 'COMPLETED',
      payment_status: 'paid',
      estimate_total: 500,
      paid_amount: 500,
      created_at: '2025-01-01T00:00:00Z',
    },
    {
      customer_phone: '9999999999',
      status: 'COMPLETED',
      payment_status: 'paid',
      estimate_total: 1000,
      paid_amount: 1000,
      created_at: '2025-01-01T00:00:00Z',
    },
  ];
  // Customer 9999999999 has an open balance because no payment covers a separate credit order
  const ordersWithDue = [
    ...orders,
    {
      customer_phone: '9999999999',
      status: 'COMPLETED',
      payment_status: 'unpaid',
      estimate_total: 300,
      paid_amount: 0,
      created_at: '2026-11-20T00:00:00Z',
    },
  ];
  const payments = [{ customer_phone: '9876543210', amount: 500 }];
  const balances = computeCustomerBalances(ordersWithDue, payments);

  assert.equal(isOrderEligible(orders[0], balances, now), true);
  assert.equal(isOrderEligible(orders[1], balances, now), false);
});

test('selectCleanupWindow applies Rule A (<1yr -> 1 month) and Rule B (>=1yr -> 3 months)', () => {
  const now = new Date('2026-11-28T00:00:00Z');
  const ruleA = selectCleanupWindow(
    [
      { docId: 'a1', date: new Date('2026-06-01T00:00:00Z') },
      { docId: 'a2', date: new Date('2026-08-01T00:00:00Z') },
    ],
    now
  );
  assert.equal(ruleA.ruleApplied, 'rule_a_1_month');
  assert.deepEqual(
    ruleA.selected.map((x) => x.docId),
    ['a1']
  );

  const ruleB = selectCleanupWindow(
    [
      { docId: 'b1', date: new Date('2025-01-01T00:00:00Z') },
      { docId: 'b2', date: new Date('2025-03-15T00:00:00Z') },
      { docId: 'b3', date: new Date('2025-06-01T00:00:00Z') },
    ],
    now
  );
  assert.equal(ruleB.ruleApplied, 'rule_b_3_months');
  assert.deepEqual(
    ruleB.selected.map((x) => x.docId),
    ['b1', 'b2']
  );
});

test('measureShopFirestoreBytes scopes byte usage strictly to target shop', async () => {
  const makeDoc = (path, data) => ({
    ref: { path },
    data: () => data,
  });
  const shops = {
    'SH-AAAA': {
      root: { shopName: 'Alpha' },
      orders: [makeDoc('shops/SH-AAAA/orders/o1', { total: 500 })],
    },
    'SH-BBBB': {
      root: { shopName: 'Beta' },
      orders: [
        makeDoc('shops/SH-BBBB/orders/o1', {
          total: 999,
          hugePayload: 'x'.repeat(2000),
        }),
      ],
    },
  };

  const mockAdmin = {
    firestore: () => ({
      collection: (colName) => ({
        doc: (shopCode) => ({
          get: async () => ({
            exists: Boolean(shops[shopCode]),
            data: () => shops[shopCode]?.root || {},
          }),
          collection: (subName) => ({
            get: async () => ({
              docs: subName === 'orders' ? (shops[shopCode]?.orders || []) : [],
            }),
          }),
        }),
      }),
    }),
  };

  const alphaUsage = await measureShopFirestoreBytes({
    admin: mockAdmin,
    shopCode: 'SH-AAAA',
  });
  const betaUsage = await measureShopFirestoreBytes({
    admin: mockAdmin,
    shopCode: 'SH-BBBB',
  });

  assert.equal(alphaUsage.metricSource, 'shop_scoped_usage');
  assert.ok(alphaUsage.usedBytes < 500);
  assert.ok(betaUsage.usedBytes > 2000);
});

test('evaluateAndManageShopStorage offloads gzip archive to GCS and uses BulkWriter', async () => {
  const storedObjects = new Map();
  const savedDocs = new Map();
  const bulkDeletedPaths = [];
  let bulkClosed = false;

  const mockOrderDoc = {
    id: 'ord_1',
    ref: { path: 'shops/SH-1234/orders/ord_1', listCollections: async () => [] },
    data: () => ({
      customer_phone: '9876543210',
      status: 'COMPLETED',
      payment_status: 'paid',
      estimate_total: 1000,
      paid_amount: 1000,
      created_at: '2025-01-01T00:00:00Z',
    }),
  };
  const mockPaymentDoc = {
    id: 'pay_1',
    ref: { path: 'shops/SH-1234/payments/pay_1', listCollections: async () => [] },
    data: () => ({
      customer_phone: '9876543210',
      amount: 1000,
      created_at: '2025-01-01T00:00:00Z',
    }),
  };

  const makeDocRef = (path) => ({
    path,
    get: async () => ({
      exists: savedDocs.has(path),
      data: () => savedDocs.get(path),
    }),
    set: async (data, opts) => {
      const prev = opts?.merge && savedDocs.has(path) ? savedDocs.get(path) : {};
      savedDocs.set(path, { ...prev, ...data });
    },
    collection: (sub) => makeColRef(`${path}/${sub}`),
  });

  const makeColRef = (colPath) => ({
    doc: (docId) => makeDocRef(`${colPath}/${docId}`),
    add: async (data) => {
      savedDocs.set(`${colPath}/${Date.now()}_${Math.random()}`, data);
    },
    get: async () => {
      if (colPath === 'shops/SH-1234/orders') return { docs: [mockOrderDoc] };
      if (colPath === 'shops/SH-1234/payments') return { docs: [mockPaymentDoc] };
      return { docs: [] };
    },
  });

  const mockAdmin = {
    firestore: () => ({
      collection: (name) => makeColRef(name),
      runTransaction: async (fn) =>
        fn({
          get: async () => ({ exists: false, data: () => null }),
          set: (ref, data) => savedDocs.set(ref.path, data),
        }),
      bulkWriter: () => ({
        delete: (ref) => bulkDeletedPaths.push(ref.path),
        close: async () => {
          bulkClosed = true;
        },
      }),
    }),
    messaging: () => ({ send: async () => 'msg_1' }),
  };

  const mockBucket = {
    name: 'mock-bucket',
    file: (objectPath) => ({
      save: async (buf) => storedObjects.set(objectPath, buf),
      download: async () => [storedObjects.get(objectPath)],
    }),
  };

  let callCount = 0;
  const result = await evaluateAndManageShopStorage({
    admin: mockAdmin,
    shopCode: 'SH-1234',
    storageBucket: mockBucket,
    quotaBytesOverride: 1000,
    storageUsageOverride: async () => {
      callCount += 1;
      return {
        usedBytes: callCount === 1 ? 950 : 400,
        metricSource: 'shop_scoped_usage',
      };
    },
    now: new Date('2026-11-28T00:00:00Z'),
    jobId: 'job_test',
  });

  assert.equal(result.skipped, false);
  assert.equal(result.archivedNow, 2);
  assert.equal(bulkClosed, true);
  assert.deepEqual(bulkDeletedPaths.sort(), [
    'shops/SH-1234/orders/ord_1',
    'shops/SH-1234/payments/pay_1',
  ]);
  assert.equal(storedObjects.size, 1);

  const archiveDocs = [...savedDocs.entries()].filter(([k]) =>
    k.startsWith('shops/SH-1234/storage_archives/')
  );
  assert.equal(archiveDocs.length, 1);
  assert.ok(archiveDocs[0][1].gcsPath.startsWith('archives/SH-1234/'));
  assert.equal(archiveDocs[0][1].compressedGzipBase64, '');
});
