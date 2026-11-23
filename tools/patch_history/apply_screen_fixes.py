import sys

# 3. Update order_preview_screen.dart
path_prev = r'lib\screens\order_preview_screen.dart'
with open(path_prev, 'r', encoding='utf-8') as f:
    cpv = f.read()

target_advance_state = """  double _discountValue = 0.0;
  double _currentCustomerDue = 0.0;"""

rep_advance_state = """  double _discountValue = 0.0;
  double _currentCustomerDue = 0.0;
  double _currentCustomerAdvance = 0.0;"""

target_advance_load = """      if (mounted) {
        setState(() {
          _currentCustomerDue =
              (status['balance_due'] as num?)?.toDouble() ?? 0.0;
        });
      }"""

rep_advance_load = """      if (mounted) {
        setState(() {
          _currentCustomerDue =
              (status['balance_due'] as num?)?.toDouble() ?? 0.0;
          _currentCustomerAdvance =
              (status['advance_credit'] as num?)?.toDouble() ?? 0.0;
        });
      }"""

target_advance_widget = """            if (!ShopCustomizationService.instance.isPureOfflineMode &&
                !const bool.fromEnvironment('STANDALONE_LOCAL',
                    defaultValue: false) &&
                widget.draftOrder.customer.creditLimit > 0) ...["""

rep_advance_widget = """            if (_currentCustomerAdvance > 0) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: const Color(0xFFECFDF5),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFA7F3D0)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.account_balance_wallet_rounded,
                        size: 20, color: Color(0xFF047857)),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '💳 Advance Credit Available: ₹ ${_currentCustomerAdvance.toStringAsFixed(2)}',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                              color: Color(0xFF065F46),
                            ),
                          ),
                          const SizedBox(height: 2),
                          const Text(
                            'Customer has excess credit with the shop that will auto-settle on their Khata account.',
                            style: TextStyle(
                              fontSize: 11,
                              color: Color(0xFF047857),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
            if (!ShopCustomizationService.instance.isPureOfflineMode &&
                !const bool.fromEnvironment('STANDALONE_LOCAL',
                    defaultValue: false) &&
                widget.draftOrder.customer.creditLimit > 0) ...["""

assert target_advance_state in cpv, "target_advance_state not found"
assert target_advance_load in cpv, "target_advance_load not found"
assert target_advance_widget in cpv, "target_advance_widget not found"

cpv = cpv.replace(target_advance_state, rep_advance_state, 1)
cpv = cpv.replace(target_advance_load, rep_advance_load, 1)
cpv = cpv.replace(target_advance_widget, rep_advance_widget, 1)

with open(path_prev, 'w', encoding='utf-8') as f:
    f.write(cpv)
print("order_preview_screen updated")
