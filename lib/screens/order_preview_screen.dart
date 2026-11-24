import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shop/database/database_helper.dart';
import 'package:shop/l10n/app_localizations.dart';
import 'package:shop/models/order.dart';
import 'package:shop/repositories/order_repository.dart';
import 'package:shop/services/draft_order_service.dart';
import 'package:shop/services/share_service.dart';
import 'package:shop/services/shop_customization_service.dart';
import 'package:shop/services/top_notification_service.dart';
import 'package:shop/widgets/large_action_button.dart';

class OrderPreviewScreen extends StatefulWidget {
  const OrderPreviewScreen({
    super.key,
    required this.draftOrder,
    required this.orderRepository,
    this.existingOrderId,
  });

  final DraftOrder draftOrder;
  final OrderRepository orderRepository;
  final int? existingOrderId;

  @override
  State<OrderPreviewScreen> createState() => _OrderPreviewScreenState();
}

class _OrderPreviewScreenState extends State<OrderPreviewScreen> {
  bool _saving = false;
  bool _applyGst = false;
  double _gstRate = 18.0;
  final List<OtherCharge> _otherCharges = <OtherCharge>[];
  bool _applyDiscount = false;
  String _discountType = 'flat'; // 'flat' or 'percent'
  double _discountValue = 0.0;
  double _currentCustomerDue = 0.0;
  double _currentCustomerAdvance = 0.0;

  late final TextEditingController _estimateController;
  late final TextEditingController _discountController;
  late final List<TextEditingController> _priceControllers;

  @override
  void initState() {
    super.initState();
    _loadCustomerCredit();
    _applyGst = widget.draftOrder.applyGst;
    _gstRate = widget.draftOrder.gstRate > 0 ? widget.draftOrder.gstRate : 18.0;
    _otherCharges.addAll(widget.draftOrder.otherCharges);
    _applyDiscount = widget.draftOrder.applyDiscount;
    _discountType = widget.draftOrder.discountType;
    _discountValue = widget.draftOrder.discountValue;

    _discountController = TextEditingController(
      text: _discountValue > 0
          ? (_discountValue % 1 == 0
              ? _discountValue.toInt().toString()
              : _discountValue.toString())
          : '',
    );

    final initialTotal =
        const bool.fromEnvironment('STANDALONE_LOCAL', defaultValue: false)
            ? _calculateGrandTotal().roundToDouble()
            : _calculateGrandTotal();

    _estimateController = TextEditingController(
      text: initialTotal % 1 == 0
          ? initialTotal.toInt().toString()
          : initialTotal.toStringAsFixed(2),
    );
    _priceControllers = widget.draftOrder.items.map((item) {
      final p = item.unitPrice ?? 0;
      return TextEditingController(text: p > 0 ? p.toStringAsFixed(2) : '');
    }).toList();
  }

  double _calculateSubtotal() => widget.draftOrder.items.fold<double>(
        0,
        (sum, item) => sum + (item.unitPrice ?? 0) * item.quantity,
      );

  double _calculateDiscountAmount(double subtotal) {
    if (!_applyDiscount || subtotal <= 0) return 0.0;
    final safeSubtotal = subtotal.clamp(0.0, double.infinity);
    final safeDiscountValue = _discountValue.clamp(0.0, double.infinity);
    if (_discountType == 'percent') {
      final safePercent = safeDiscountValue.clamp(0.0, 100.0);
      return (safeSubtotal * safePercent / 100.0).clamp(0.0, safeSubtotal);
    }
    return safeDiscountValue.clamp(0.0, safeSubtotal);
  }

  bool _ensureAllItemsPriced(String actionName) {
    if (widget.draftOrder.items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Cannot proceed with empty order. Please add items.'),
          backgroundColor: Colors.red,
        ),
      );
      return false;
    }
    final unpricedItems = widget.draftOrder.items
        .where((i) => (i.unitPrice ?? 0.0) <= 0)
        .toList();
    if (unpricedItems.isEmpty) return true;

    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.error_outline, color: Colors.red, size: 24),
            SizedBox(width: 8),
            Expanded(child: Text('Missing Item Prices')),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Cannot $actionName without proper prices. The following item(s) do not have a price set:'),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.red.shade200),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: unpricedItems.map((i) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Text('• ${i.itemName}', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.red.shade900)),
                )).toList(),
              ),
            ),
            const SizedBox(height: 12),
            const Text('Please return and set a valid price for all items before proceeding.'),
          ],
        ),
        actions: [
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFF0F766E)),
            onPressed: () => Navigator.pop(ctx),
            child: const Text('OK'),
          ),
        ],
      ),
    );
    return false;
  }

  double _calculateTaxableSubtotal([double? subtotal]) {
    final s = subtotal ?? _calculateSubtotal();
    final discount = _calculateDiscountAmount(s);
    return (s - discount).clamp(0.0, double.infinity);
  }

  double _calculateGstAmount([double? taxableSubtotal]) {
    final taxable = taxableSubtotal ?? _calculateTaxableSubtotal();
    return _applyGst ? (taxable * _gstRate / 100.0) : 0.0;
  }

  double _calculateOtherChargesTotal() =>
      _otherCharges.fold<double>(0.0, (sum, c) => sum + c.amount);

  double _calculateGrandTotal() {
    final taxable = _calculateTaxableSubtotal();
    final gst = _calculateGstAmount(taxable);
    final other = _calculateOtherChargesTotal();
    return (taxable + gst + other).clamp(0.0, double.infinity);
  }

  void _recalculateEstimate() {
    var total = _calculateGrandTotal();
    // In Retail Mode: automatic price rounding for rapid cash change (e.g. ₹49.50 -> ₹50)
    if (const bool.fromEnvironment('STANDALONE_LOCAL', defaultValue: false)) {
      total = total.roundToDouble();
    }
    _estimateController.text = total % 1 == 0
        ? total.toInt().toString()
        : total.toStringAsFixed(2);
  }

  BillBreakdown _getBillBreakdown([double? totalOverride]) {
    final subtotal = _calculateSubtotal();
    return BillBreakdown.calculate(
      subtotal: subtotal,
      applyGst: _applyGst,
      gstRate: _gstRate,
      otherCharges: List<OtherCharge>.from(_otherCharges),
      applyDiscount: _applyDiscount,
      discountType: _discountType,
      discountValue: _discountValue,
      grandTotalOverride: totalOverride ??
          (double.tryParse(_estimateController.text.trim()) ??
              _calculateGrandTotal()),
    );
  }

  @override
  void dispose() {
    _estimateController.dispose();
    _discountController.dispose();
    for (final controller in _priceControllers) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _showEditGstRateDialog() async {
    final rateCtrl = TextEditingController(
      text: _gstRate % 1 == 0
          ? _gstRate.toInt().toString()
          : _gstRate.toString(),
    );
    final presets = [5, 12, 18, 28];

    try {
      await showDialog<void>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return AlertDialog(
              title: const Text('Change GST %'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Select preset or enter custom GST rate:',
                    style: TextStyle(fontSize: 13, color: Colors.grey),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    children: presets.map((p) {
                      final isSelected =
                          rateCtrl.text.trim() == p.toString();
                      return ChoiceChip(
                        label: Text('$p%'),
                        selected: isSelected,
                        onSelected: (selected) {
                          setDialogState(() {
                            rateCtrl.text = p.toString();
                          });
                        },
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: rateCtrl,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    autofocus: true,
                    decoration: const InputDecoration(
                      labelText: 'GST Percentage',
                      suffixText: '%',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('CANCEL'),
                ),
                FilledButton(
                  onPressed: () {
                    final parsed = double.tryParse(rateCtrl.text.trim());
                    if (parsed == null || parsed < 0) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                            content: Text('Please enter a valid percentage')),
                      );
                      return;
                    }
                    setState(() {
                      _gstRate = parsed;
                      _recalculateEstimate();
                    });
                    Navigator.pop(ctx);
                  },
                  child: const Text('APPLY'),
                ),
              ],
            );
          },
        );
      },
    );
    } finally {
      rateCtrl.dispose();
    }
  }

  Future<void> _showAddOtherChargeDialog() async {
    final nameCtrl = TextEditingController();
    final amountCtrl = TextEditingController();
    final suggestions = [
      'Delivery',
      'Transport',
      'Labor / Coolie',
      'Packaging',
      'Loading'
    ];

    try {
      await showDialog<void>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return AlertDialog(
              title: const Text('Add Other Charge'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Quick Suggestions:',
                        style: TextStyle(fontSize: 12, color: Colors.grey)),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: suggestions.map((s) {
                        return ActionChip(
                          label: Text(s, style: const TextStyle(fontSize: 12)),
                          onPressed: () {
                            setDialogState(() {
                              nameCtrl.text = s;
                            });
                          },
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: nameCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Charge Type / Description',
                        hintText: 'e.g. Delivery, Transport',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: amountCtrl,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(
                        labelText: 'Amount (₹)',
                        prefixText: '₹ ',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('CANCEL'),
                ),
                FilledButton(
                  onPressed: () {
                    final name = nameCtrl.text.trim();
                    final amount =
                        double.tryParse(amountCtrl.text.trim()) ?? 0.0;
                    if (name.isEmpty || amount <= 0) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                            content: Text(
                                'Please enter valid charge name and amount')),
                      );
                      return;
                    }
                    setState(() {
                      _otherCharges.add(OtherCharge(name: name, amount: amount));
                      _recalculateEstimate();
                    });
                    Navigator.pop(ctx);
                  },
                  child: const Text('ADD'),
                ),
              ],
            );
          },
        );
      },
    );
    } finally {
      nameCtrl.dispose();
      amountCtrl.dispose();
    }
  }

  Future<void> _loadCustomerCredit() async {
    final customerId = widget.draftOrder.customer.id;
    if (customerId != null) {
      final status =
          await DatabaseHelper.instance.getCustomerCreditStatus(customerId);
      if (mounted) {
        setState(() {
          _currentCustomerDue =
              (status['balance_due'] as num?)?.toDouble() ?? 0.0;
          _currentCustomerAdvance =
              (status['advance_credit'] as num?)?.toDouble() ?? 0.0;
        });
      }
    }
  }

  void _removeOtherCharge(int index) {
    setState(() {
      _otherCharges.removeAt(index);
      _recalculateEstimate();
    });
  }

  Future<void> _saveOrder() async {
    if (!_ensureAllItemsPriced('place order or share bill')) return;
    final breakdown = _getBillBreakdown();
    final estimate = breakdown.grandTotal;

    // Credit limit check for wholesale mode
    final isWholesale = !ShopCustomizationService.instance.isPureOfflineMode &&
        !const bool.fromEnvironment('STANDALONE_LOCAL', defaultValue: false);
    final customer = widget.draftOrder.customer;
    final limit = customer.creditLimit;

    if (isWholesale && limit > 0 && customer.id != null) {
      final projected = _currentCustomerDue + estimate;
      if (projected > limit) {
        final exceededBy = projected - limit;
        final allow = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: const Row(
              children: [
                Icon(Icons.warning_amber_rounded,
                    color: Colors.amber, size: 28),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Credit Limit Exceeded!',
                    style:
                        TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
                  ),
                ),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Customer "${customer.name}" has a set credit limit of ₹ ${limit.toStringAsFixed(0)}.',
                  style: const TextStyle(fontSize: 14),
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.red.shade200),
                  ),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Current Balance Due:',
                              style: TextStyle(fontSize: 12)),
                          Text('₹ ${_currentCustomerDue.toStringAsFixed(2)}',
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold, fontSize: 12)),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('This Bill Amount:',
                              style: TextStyle(fontSize: 12)),
                          Text('+ ₹ ${estimate.toStringAsFixed(2)}',
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                  color: Colors.blue)),
                        ],
                      ),
                      const Divider(height: 10),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Projected Balance:',
                              style: TextStyle(
                                  fontSize: 12, fontWeight: FontWeight.bold)),
                          Text('₹ ${projected.toStringAsFixed(2)}',
                              style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                  color: Colors.red.shade900)),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Exceeds Limit By:',
                              style:
                                  TextStyle(fontSize: 12, color: Colors.red)),
                          Text('₹ ${exceededBy.toStringAsFixed(2)}',
                              style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                  color: Colors.red.shade900)),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Would you like to authorize this wholesale dispatch, or review/collect payment first?',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Back / Review Bill'),
              ),
              FilledButton(
                style: FilledButton.styleFrom(
                    backgroundColor: Colors.amber.shade900),
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Authorize & Proceed'),
              ),
            ],
          ),
        );
        if (allow != true) {
          return;
        }
      }
    }

    setState(() => _saving = true);

    final updatedDraft = widget.draftOrder.copyWith(
      applyGst: _applyGst,
      gstRate: _gstRate,
      otherCharges: _otherCharges,
      applyDiscount: _applyDiscount,
      discountType: _discountType,
      discountValue: _discountValue,
      estimateTotal: estimate,
    );

    int newOrderId = 0;
    if (widget.existingOrderId == null) {
      newOrderId = await widget.orderRepository.createOrder(
        updatedDraft,
        estimateTotal: estimate,
        billBreakdown: breakdown,
      );
      await DraftOrderService().clearDraft();
    } else {
      newOrderId = widget.existingOrderId!;
      await widget.orderRepository.addItemsToOrder(
        orderId: widget.existingOrderId!,
        items: widget.draftOrder.items,
        estimateTotalAddition: estimate,
        billBreakdown: breakdown,
      );
    }
    if (!mounted) {
      return;
    }
    setState(() => _saving = false);
    final orderIdFormatted = '#ORD-${newOrderId.toString().padLeft(4, '0')}';

    if (widget.existingOrderId != null) {
      // Pop back to OrderDetailsScreen so the user sees the updated order with added items
      Navigator.of(context).pop();
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Items added to $orderIdFormatted successfully!'),
          backgroundColor: const Color(0xFF0F766E),
        ),
      );
      return;
    }

    // Immediately navigate back to Home Screen
    Navigator.popUntil(context, (route) => route.isFirst);

    // Trigger top notification after home screen finishes rendering
    WidgetsBinding.instance.addPostFrameCallback((_) {
      TopNotificationService.showTopNotification(
        message: 'Order $orderIdFormatted created successfully!',
        actionLabel: 'SHARE',
        onAction: () {
          ShareService.shareDraftEstimate(
            updatedDraft,
            totalOverride: estimate,
            billBreakdown: breakdown,
          );
        },
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context);
    final subtotal = _calculateSubtotal();
    final taxable = _calculateTaxableSubtotal(subtotal);
    final gstAmount = _calculateGstAmount(taxable);
    final otherChargesTotal = _calculateOtherChargesTotal();
    final calculatedGrandTotal = _calculateGrandTotal();
    final currentEstimate =
        double.tryParse(_estimateController.text.trim()) ?? calculatedGrandTotal;
    final breakdown = _getBillBreakdown(currentEstimate);

    return Scaffold(
      appBar: AppBar(
        title: Text(s.t('orderPreview')),
        actions: <Widget>[
          IconButton(
            tooltip: 'Share Estimate',
            icon: const Icon(Icons.share),
            onPressed: () {
              if (!_ensureAllItemsPriced('share estimate')) return;
              ShareService.shareDraftEstimate(
                widget.draftOrder,
                totalOverride: currentEstimate,
                billBreakdown: breakdown,
              );
            },
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Row(
                children: [
                  CircleAvatar(
                    backgroundColor:
                        Theme.of(context).colorScheme.primaryContainer,
                    foregroundColor: Theme.of(context).colorScheme.primary,
                    radius: 18,
                    child: Text(
                      widget.draftOrder.customer.name.isNotEmpty
                          ? widget.draftOrder.customer.name[0].toUpperCase()
                          : 'C',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.draftOrder.customer.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 15, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          DateFormat('dd MMM yyyy, hh:mm a')
                              .format(DateTime.now()),
                          style: TextStyle(
                              fontSize: 11, color: Colors.grey.shade600),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            if (_currentCustomerAdvance > 0) ...[
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
                widget.draftOrder.customer.creditLimit > 0) ...[
              const SizedBox(height: 8),
              Builder(
                builder: (context) {
                  final limit = widget.draftOrder.customer.creditLimit;
                  final breakdown = _getBillBreakdown();
                  final estimate = breakdown.grandTotal;
                  final projected = _currentCustomerDue + estimate;
                  final isOver = projected > limit;
                  final diff =
                      isOver ? (projected - limit) : (limit - projected);

                  return Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color:
                          isOver ? Colors.red.shade50 : const Color(0xFFF0FDF4),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isOver
                            ? Colors.red.shade300
                            : const Color(0xFFBBF7D0),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          isOver
                              ? Icons.warning_amber_rounded
                              : Icons.shield_outlined,
                          size: 20,
                          color: isOver
                              ? Colors.red.shade800
                              : const Color(0xFF15803D),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                isOver
                                    ? '⚠️ CREDIT LIMIT EXCEEDED BY ₹ ${diff.toStringAsFixed(2)}'
                                    : '🛡️ Credit Limit: ₹ ${limit.toStringAsFixed(0)} (Safe)',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                  color: isOver
                                      ? Colors.red.shade900
                                      : const Color(0xFF166534),
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                isOver
                                    ? 'Due: ₹${_currentCustomerDue.toStringAsFixed(0)} + Bill: ₹${estimate.toStringAsFixed(0)} = New: ₹${projected.toStringAsFixed(0)} (Limit ₹${limit.toStringAsFixed(0)})'
                                    : 'Current: ₹${_currentCustomerDue.toStringAsFixed(0)} • Remaining after bill: ₹${diff.toStringAsFixed(0)}',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: isOver
                                      ? Colors.red.shade800
                                      : const Color(0xFF15803D),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ],
            const SizedBox(height: 12),
            Expanded(
              child: ListView(
                children: [
                  // Items List Section
                  ...widget.draftOrder.items.asMap().entries.map((entry) {
                    final index = entry.key;
                    final item = entry.value;
                    final itemUnitPrice = item.unitPrice ?? 0;
                    final itemTotal = itemUnitPrice * item.quantity;
                    final priceCtrl = _priceControllers[index];

                    return Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(
                                  child: Text(
                                    '${index + 1}. ${item.itemName}',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w700),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  '₹ ${itemTotal.toStringAsFixed(2)}',
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w800,
                                      color: Colors.teal),
                                ),
                              ],
                            ),
                            ...item.options.entries.map((e) => Text(
                                '${s.catalog(e.key)}: ${s.catalog(e.value)}')),
                            if ((item.description ?? '').isNotEmpty)
                              Text('${s.t('details')}: ${item.description}'),
                            const SizedBox(height: 6),
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                      '${s.t('quantity')}: ${item.quantity % 1 == 0 ? item.quantity.toInt() : item.quantity} ${item.unit}'),
                                ),
                                SizedBox(
                                  width: 120,
                                  child: TextField(
                                    controller: priceCtrl,
                                    keyboardType:
                                        const TextInputType.numberWithOptions(
                                            decimal: true),
                                    decoration: const InputDecoration(
                                      labelText: 'Price/Unit ₹',
                                      isDense: true,
                                      prefixText: '₹ ',
                                    ),
                                    onChanged: (val) {
                                      final parsed =
                                          double.tryParse(val.trim()) ?? 0.0;
                                      setState(() {
                                        widget.draftOrder.items[index] =
                                            widget.draftOrder.items[index]
                                                .copyWith(unitPrice: parsed);
                                        _recalculateEstimate();
                                      });
                                    },
                                  ),
                                ),
                              ],
                            ),
                            if (item.isOtherItem)
                              Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Text(
                                  'Other Item (Custom)',
                                  style: TextStyle(
                                      color: Colors.deepPurple.shade700,
                                      fontWeight: FontWeight.w700),
                                ),
                              ),
                          ],
                        ),
                      ),
                    );
                  }),
                  const SizedBox(height: 8),

                  // Bill Summary Card (GST and Other Charges)
                  Card(
                    color: Theme.of(context)
                        .colorScheme
                        .primaryContainer
                        .withValues(alpha: 0.25),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                      side: BorderSide(
                        color: Theme.of(context)
                            .colorScheme
                            .primary
                            .withValues(alpha: 0.3),
                      ),
                    ),
                    elevation: 1,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Row(
                                children: [
                                  Icon(Icons.receipt_long,
                                      size: 20,
                                      color: Theme.of(context)
                                          .colorScheme
                                          .primary),
                                  const SizedBox(width: 8),
                                  Text(
                                    s.t('billSummary'),
                                    style: TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w800,
                                      color: Theme.of(context)
                                          .colorScheme
                                          .primary,
                                      letterSpacing: 0.5,
                                    ),
                                  ),
                                ],
                              ),
                              Text(
                                '₹ ${subtotal.toStringAsFixed(2)}',
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold, fontSize: 16),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            s.t('itemsSubtotal'),
                            style: TextStyle(
                                fontSize: 12, color: Colors.grey.shade700),
                          ),
                          const Divider(height: 24),

                          // GST Section
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Row(
                                children: [
                                  Checkbox(
                                    value: _applyGst,
                                    onChanged: (val) {
                                      setState(() {
                                        _applyGst = val ?? false;
                                        _recalculateEstimate();
                                      });
                                    },
                                  ),
                                  GestureDetector(
                                    onTap: () {
                                      setState(() {
                                        _applyGst = !_applyGst;
                                        _recalculateEstimate();
                                      });
                                    },
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          s.t('applyGst'),
                                          style: const TextStyle(
                                              fontWeight: FontWeight.w700,
                                              fontSize: 14),
                                        ),
                                        Text(
                                          '(${s.t('optional')})',
                                          style: TextStyle(
                                              fontSize: 11,
                                              color: Colors.grey.shade600),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                              if (_applyGst)
                                Text(
                                  '+ ₹ ${gstAmount.toStringAsFixed(2)}',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 15,
                                    color: Colors.teal,
                                  ),
                                )
                              else
                                Text(
                                  s.t('optional'),
                                  style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey.shade600),
                                ),
                            ],
                          ),
                          if (_applyGst) ...[
                            Padding(
                              padding: const EdgeInsets.only(
                                  left: 48, top: 4, bottom: 8),
                              child: Row(
                                children: [
                                  Text(
                                    '${s.t('gstRate')}: ',
                                    style: TextStyle(
                                        fontSize: 13,
                                        color: Colors.grey.shade800,
                                        fontWeight: FontWeight.w500),
                                  ),
                                  InkWell(
                                    onTap: _showEditGstRateDialog,
                                    borderRadius: BorderRadius.circular(8),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 10, vertical: 5),
                                      decoration: BoxDecoration(
                                        color: Colors.white,
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(
                                            color: Theme.of(context)
                                                .colorScheme
                                                .primary),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Text(
                                            '${_gstRate % 1 == 0 ? _gstRate.toInt() : _gstRate}%',
                                            style: TextStyle(
                                              fontWeight: FontWeight.w800,
                                              color: Theme.of(context)
                                                  .colorScheme
                                                  .primary,
                                              fontSize: 14,
                                            ),
                                          ),
                                          const SizedBox(width: 4),
                                          Icon(
                                            Icons.edit,
                                            size: 13,
                                            color: Theme.of(context)
                                                .colorScheme
                                                .primary,
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    '(${s.t('defaultGstHint')})',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: Colors.grey.shade600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                          const Divider(height: 24),

                          // Discount Section
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Row(
                                children: [
                                  Checkbox(
                                    value: _applyDiscount,
                                    onChanged: (val) {
                                      setState(() {
                                        _applyDiscount = val ?? false;
                                        _recalculateEstimate();
                                      });
                                    },
                                  ),
                                  GestureDetector(
                                    onTap: () {
                                      setState(() {
                                        _applyDiscount = !_applyDiscount;
                                        _recalculateEstimate();
                                      });
                                    },
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        const Text(
                                          'Discount',
                                          style: TextStyle(
                                              fontWeight: FontWeight.w700,
                                              fontSize: 14),
                                        ),
                                        Text(
                                          '(${s.t('optional')})',
                                          style: TextStyle(
                                              fontSize: 11,
                                              color: Colors.grey.shade600),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                              if (_applyDiscount)
                                Text(
                                  '- ₹ ${_calculateDiscountAmount(subtotal).toStringAsFixed(2)}',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 15,
                                    color: Colors.green,
                                  ),
                                )
                              else
                                Text(
                                  s.t('optional'),
                                  style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey.shade600),
                                ),
                            ],
                          ),
                          if (_applyDiscount) ...[
                            Padding(
                              padding: const EdgeInsets.only(
                                  left: 48, top: 4, bottom: 8, right: 8),
                              child: Row(
                                children: [
                                  SegmentedButton<String>(
                                    style: SegmentedButton.styleFrom(
                                      visualDensity: VisualDensity.compact,
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 6),
                                    ),
                                    segments: const [
                                      ButtonSegment(
                                        value: 'flat',
                                        label: Text('₹ Flat',
                                            style: TextStyle(fontSize: 12)),
                                      ),
                                      ButtonSegment(
                                        value: 'percent',
                                        label: Text('% Off',
                                            style: TextStyle(fontSize: 12)),
                                      ),
                                    ],
                                    selected: {_discountType},
                                    onSelectionChanged: (set) {
                                      setState(() {
                                        _discountType = set.first;
                                        _recalculateEstimate();
                                      });
                                    },
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: TextField(
                                      controller: _discountController,
                                      keyboardType: const TextInputType
                                          .numberWithOptions(decimal: true),
                                      decoration: InputDecoration(
                                        hintText: _discountType == 'flat'
                                            ? 'e.g. 100'
                                            : 'e.g. 5',
                                        prefixText: _discountType == 'flat'
                                            ? '₹ '
                                            : null,
                                        suffixText: _discountType == 'percent'
                                            ? '%'
                                            : null,
                                        isDense: true,
                                        contentPadding:
                                            const EdgeInsets.symmetric(
                                                horizontal: 10, vertical: 8),
                                        border: const OutlineInputBorder(),
                                        errorText: _discountValue < 0
                                            ? 'Cannot be negative'
                                            : (_discountType == 'percent' && _discountValue > 100
                                                ? 'Cannot exceed 100%'
                                                : (_discountType == 'flat' && _discountValue > subtotal
                                                    ? 'Cannot exceed bill total'
                                                    : null)),
                                      ),
                                      onChanged: (val) {
                                        setState(() {
                                          _discountValue =
                                              double.tryParse(val.trim()) ??
                                                  0.0;
                                          _recalculateEstimate();
                                        });
                                      },
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                          const Divider(height: 24),

                          // Other Charges Section
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    s.t('otherCharges'),
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w700,
                                        fontSize: 14),
                                  ),
                                  Text(
                                    '(${s.t('optional')})',
                                    style: TextStyle(
                                        fontSize: 11,
                                        color: Colors.grey.shade600),
                                  ),
                                ],
                              ),
                              OutlinedButton.icon(
                                style: OutlinedButton.styleFrom(
                                  visualDensity: VisualDensity.compact,
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 10, vertical: 4),
                                ),
                                icon: const Icon(Icons.add, size: 16),
                                label: Text(s.t('addOtherCharge'),
                                    style: const TextStyle(fontSize: 11)),
                                onPressed: _showAddOtherChargeDialog,
                              ),
                            ],
                          ),
                          if (_otherCharges.isEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 8, bottom: 4),
                              child: Text(
                                s.t('noOtherCharges'),
                                style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey.shade600,
                                    fontStyle: FontStyle.italic),
                              ),
                            )
                          else ...[
                            const SizedBox(height: 8),
                            ..._otherCharges.asMap().entries.map((entry) {
                              final idx = entry.key;
                              final charge = entry.value;
                              return Container(
                                margin: const EdgeInsets.only(bottom: 6),
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 6),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                      color: Colors.grey.shade300),
                                ),
                                child: Row(
                                  children: [
                                    const Icon(Icons.local_shipping_outlined,
                                        size: 16, color: Colors.teal),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        charge.name,
                                        style: const TextStyle(
                                            fontWeight: FontWeight.w600,
                                            fontSize: 13),
                                      ),
                                    ),
                                    Text(
                                      '+ ₹ ${charge.amount.toStringAsFixed(2)}',
                                      style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          color: Colors.teal,
                                          fontSize: 13),
                                    ),
                                    const SizedBox(width: 6),
                                    IconButton(
                                      icon: const Icon(Icons.delete_outline,
                                          size: 18, color: Colors.red),
                                      visualDensity: VisualDensity.compact,
                                      padding: EdgeInsets.zero,
                                      constraints: const BoxConstraints(),
                                      onPressed: () => _removeOtherCharge(idx),
                                    ),
                                  ],
                                ),
                              );
                            }),
                            if (_otherCharges.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    const Text('Total Other Charges:',
                                        style: TextStyle(
                                            fontSize: 12,
                                            color: Colors.grey)),
                                    Text(
                                      '+ ₹ ${otherChargesTotal.toStringAsFixed(2)}',
                                      style: const TextStyle(
                                          fontWeight: FontWeight.w700,
                                          fontSize: 13,
                                          color: Colors.teal),
                                    ),
                                  ],
                                ),
                              ),
                          ],
                          const Divider(height: 24),

                          // Grand Total Section
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                s.t('grandTotal'),
                                style: const TextStyle(
                                    fontWeight: FontWeight.w800, fontSize: 16),
                              ),
                              Text(
                                '₹ ${calculatedGrandTotal.toStringAsFixed(2)}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w900,
                                  fontSize: 22,
                                  color: Colors.teal,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: _estimateController,
                            keyboardType: const TextInputType.numberWithOptions(
                                decimal: true),
                            decoration: const InputDecoration(
                              labelText: 'Total Bill Amount (editable / round-off)',
                              prefixText: '₹ ',
                              isDense: true,
                              border: OutlineInputBorder(),
                            ),
                            onChanged: (_) => setState(() {}),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            ),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {
                      if (!_ensureAllItemsPriced('share estimate')) return;
                      ShareService.shareDraftEstimate(
                        widget.draftOrder,
                        totalOverride: currentEstimate,
                        billBreakdown: breakdown,
                      );
                    },
                    icon: const Icon(Icons.share, size: 18),
                    label: const Text('SHARE ESTIMATE'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.edit, size: 18),
                    label: Text(s.t('edit')),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            LargeActionButton(
              label: _saving ? s.t('saving') : s.t('saveOrder'),
              onTap: _saving ? null : _saveOrder,
            ),
          ],
        ),
      ),
    );
  }
}
