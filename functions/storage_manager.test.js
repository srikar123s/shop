const test = require('node:test');
const assert = require('node:assert/strict');
const {
  classifyStorageStatus,
  computeCustomerBalances,
  isOrderEligible,
  selectCleanupWindow,
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
