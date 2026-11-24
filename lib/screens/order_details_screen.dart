import 'dart:math' as math;
import 'package:shop/screens/order_packing_slip_screen.dart';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shop/l10n/app_localizations.dart';
import 'package:shop/models/order.dart';
import 'package:shop/repositories/order_repository.dart';
import 'package:shop/repositories/customer_repository.dart';
import 'package:shop/repositories/product_repository.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:shop/database/database_helper.dart';
import 'package:shop/screens/product_selection_screen.dart';
import 'package:shop/services/invoice_pdf_service.dart';
import 'package:shop/services/share_service.dart';
import 'package:shop/services/shop_sync_service.dart';
import 'package:shop/services/shop_customization_service.dart';

import 'package:shop/widgets/large_action_button.dart';
import 'package:shop/widgets/order_fulfillment_widgets.dart';

class OrderDetailsScreen extends StatefulWidget {
  const OrderDetailsScreen({
    super.key,
    required this.orderId,
    required this.orderRepository,
    required this.customerRepository,
    required this.productRepository,
  });

  final int orderId;
  final OrderRepository orderRepository;
  final CustomerRepository customerRepository;
  final ProductRepository productRepository;

  @override
  State<OrderDetailsScreen> createState() => _OrderDetailsScreenState();
}

class _OrderDetailsScreenState extends State<OrderDetailsScreen> {
  OrderDetails? _details;
  bool _loading = true;
  bool _saving = false;
  int? _customerBillNumber;
  final Map<int, TextEditingController> _itemPriceControllers = {};
  final ScrollController _scrollController = ScrollController();
  double _customerAdvanceBalance = 0.0;

  @override
  void dispose() {
    _scrollController.dispose();
    for (final c in _itemPriceControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool silent = false}) async {
    final prevOffset = _scrollController.hasClients ? _scrollController.offset : null;
    if (!silent && _details == null) {
      setState(() => _loading = true);
    }
    final details =
        await widget.orderRepository.getOrderDetails(widget.orderId);
    final seq = await DatabaseHelper.instance.getCustomerBillSequence(widget.orderId);
    double advBalance = 0.0;
    if (details != null) {
      final netBal = await DatabaseHelper.instance.getCustomerKhataBalance(details.order.customerId);
      if (netBal < -0.01) {
        advBalance = -netBal;
      }
    }
    if (!mounted) return;
    setState(() {
      _details = details;
      _customerBillNumber = seq;
      _customerAdvanceBalance = advBalance;
      _loading = false;
    });
    if (prevOffset != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollController.hasClients) {
          _scrollController.jumpTo(prevOffset);
        }
      });
    }
  }

  Color _itemStatusColor(ItemStatus status) {
    switch (status) {
      case ItemStatus.given:
        return Colors.teal;
      case ItemStatus.partial:
        return Colors.orange.shade800;
      case ItemStatus.notGiven:
        return Colors.red.shade700;
    }
  }

  Color _itemStatusBgColor(ItemStatus status) {
    switch (status) {
      case ItemStatus.given:
        return Colors.teal.shade50;
      case ItemStatus.partial:
        return Colors.orange.shade50;
      case ItemStatus.notGiven:
        return Colors.red.shade50;
    }
  }


  String _itemStatusTitle(ItemStatus status) {
    switch (status) {
      case ItemStatus.given:
        return 'DELIVERED';
      case ItemStatus.partial:
        return 'PARTIALLY GIVEN';
      case ItemStatus.notGiven:
        return 'NOT GIVEN';
    }
  }

  ItemStatus _statusFromQty(double ordered, double given) {
    if (given <= 0) return ItemStatus.notGiven;
    if (given >= ordered) return ItemStatus.given;
    return ItemStatus.partial;
  }

  Future<void> _save() async {
    if (_details == null) {
      return;
    }
    setState(() => _saving = true);
    await widget.orderRepository.updateOrderFulfillment(
      orderId: _details!.order.id!,
      items: _details!.items,
    );
    if (!mounted) {
      return;
    }
    setState(() => _saving = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(AppLocalizations.of(context).t('changesSaved')),
        duration: const Duration(seconds: 3),
      ),
    );

    await _load();
  }

    bool _ensureAllItemsPriced({required String actionName}) {
    if (_details == null) return false;
    final unpricedItems =
        _details!.items.where((i) => i.unitPrice <= 0).toList();
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
            const Text('Please enter a valid Price/Unit for each item before proceeding.'),
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

  Future<void> _closeOrder() async {
    if (_details == null || !mounted) return;
    if (!_ensureAllItemsPriced(actionName: 'close order')) return;
    final order = _details!.order;
    final unfulfilled = _details!.items
        .where((i) => i.quantityGiven < i.quantityOrdered)
        .toList();

    if (unfulfilled.isEmpty) {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('Complete ${order.formattedOrderId}?'),
          content: Text(
            'All ${_details!.items.length} item(s) have been delivered. Mark this order as completed?',
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('CANCEL'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('COMPLETE ORDER'),
            ),
          ],
        ),
      );
      if (confirm == true && mounted) {
        await widget.orderRepository.closeOrderWithAllGiven(order.id!);
        await _load();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('${order.formattedOrderId} marked as completed.'),
              backgroundColor: Colors.teal,
            ),
          );
        }
      }
      return;
    }

    final orderedSubtotal = _details!.items.fold<double>(
      0,
      (s, i) => s + (i.unitPrice * i.quantityOrdered),
    );
    final deliveredSubtotal = _details!.items.fold<double>(
      0,
      (s, i) => s + (i.unitPrice * i.quantityGiven),
    );

    final existingBreakdown = order.billBreakdown;
    final deliveredBreakdown = existingBreakdown != null
        ? BillBreakdown.calculate(
            subtotal: deliveredSubtotal,
            applyGst: existingBreakdown.applyGst,
            gstRate: existingBreakdown.gstRate,
            otherCharges: existingBreakdown.otherCharges,
          )
        : BillBreakdown.calculate(subtotal: deliveredSubtotal);

    final fullBreakdown = existingBreakdown != null
        ? BillBreakdown.calculate(
            subtotal: orderedSubtotal,
            applyGst: existingBreakdown.applyGst,
            gstRate: existingBreakdown.gstRate,
            otherCharges: existingBreakdown.otherCharges,
          )
        : BillBreakdown.calculate(subtotal: orderedSubtotal);

        final choice = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.orange.shade100,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(Icons.inventory_2_outlined,
                  color: Colors.orange.shade900, size: 24),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Close ${order.formattedOrderId}',
                    style: const TextStyle(
                        fontSize: 17, fontWeight: FontWeight.bold),
                  ),
                  Text(
                    '${unfulfilled.length} item(s) out of stock',
                    style: TextStyle(
                        fontSize: 12,
                        color: Colors.deepOrange.shade800,
                        fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Customer is billed ONLY for items actually delivered.',
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: Colors.teal.shade900),
            ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFF0FDFA),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFF99F6E4)),
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Delivered Items Bill:',
                          style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
                      Text(
                        '₹ ${deliveredBreakdown.grandTotal.toStringAsFixed(2)}',
                        style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF0F766E)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Original Order Total:',
                          style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                      Text(
                        '₹ ${fullBreakdown.grandTotal.toStringAsFixed(2)}',
                        style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey.shade600,
                            decoration: TextDecoration.lineThrough),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Text(
              '📦 ${unfulfilled.length} out-of-stock item(s) will be added to the Procurement List.',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, 'cancel'),
            child: const Text('CANCEL'),
          ),
          OutlinedButton(
            onPressed: () => Navigator.pop(context, 'all_given'),
            child: Text('Deliver All 100% (₹${fullBreakdown.grandTotal.toStringAsFixed(2)})'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFF0F766E)),
            onPressed: () => Navigator.pop(context, 'delivered_only'),
            child: Text('Close & Bill Delivered (₹${deliveredBreakdown.grandTotal.toStringAsFixed(2)})'),
          ),
        ],
      ),
    );

    if (!mounted || choice == null || choice == 'cancel') return;

    if (choice == 'delivered_only') {
      // First save current item quantities given from the screen
      await widget.orderRepository.updateOrderFulfillment(
        orderId: order.id!,
        items: _details!.items,
      );
      await widget.orderRepository.closeOrderWithDeliveredItemsOnly(
        orderId: order.id!,
      );
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${order.formattedOrderId} closed. Bill adjusted to ₹${deliveredBreakdown.grandTotal.toStringAsFixed(2)} for delivered goods.',
            ),
            backgroundColor: Colors.teal,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } else if (choice == 'all_given') {
      await widget.orderRepository.closeOrderWithAllGiven(order.id!);
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                '${order.formattedOrderId} marked fully delivered & completed.'),
            backgroundColor: Colors.teal,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  Future<void> _navigateToAddProducts() async {
    if (_details == null) return;
    final order = _details!.order;
    final customer =
        await widget.customerRepository.getCustomerById(order.customerId);
    if (!mounted || customer == null) return;
    await Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => ProductSelectionScreen(
          customer: customer,
          productRepository: widget.productRepository,
          orderRepository: widget.orderRepository,
          existingOrderId: order.id,
        ),
      ),
    );
    await _load();
  }

  Future<void> _repeatOrder() async {
    if (_details == null) return;
    final order = _details!.order;
    final customer =
        await widget.customerRepository.getCustomerById(order.customerId);
    if (!mounted || customer == null) return;

    final draftItems = _details!.items.map((item) {
      return DraftOrderItem(
        productId: item.productId,
        itemName: item.itemName,
        quantity: item.quantityOrdered,
        unit: item.unit,
        unitPrice: item.unitPrice > 0 ? item.unitPrice : null,
        description: item.description,
        notes: item.notes,
        isOtherItem: item.isOtherItem,
        options: {
          for (final opt in item.options) opt.optionName: opt.optionValue
        },
      );
    }).toList();

    await Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => ProductSelectionScreen(
          customer: customer,
          productRepository: widget.productRepository,
          orderRepository: widget.orderRepository,
          initialItems: draftItems,
        ),
      ),
    );
  }

  void _showPrintMenu() {
    if (_details == null) return;
    showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.teal.shade50,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.print, color: Color(0xFF0F766E)),
                ),
                title: const Text('Thermal Printer (58mm Roll)',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                subtitle:
                    const Text('Direct print via Bluetooth thermal printer'),
                onTap: () async {
                  Navigator.pop(ctx);
                  if (!_ensureAllItemsPriced(actionName: 'print receipt')) return;
                  await InvoicePdfService.instance.printReceipt(
                    _details!,
                    isThermal58mm: true,
                    customerBillNumber: _customerBillNumber,
                  );
                },
              ),
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.picture_as_pdf, color: Colors.blue),
                ),
                title: const Text('Share PDF Bill',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                subtitle:
                    const Text('Standard format with shop stamp & details'),
                onTap: () async {
                  Navigator.pop(ctx);
                  if (!_ensureAllItemsPriced(actionName: 'share PDF bill')) return;
                  await InvoicePdfService.instance.sharePdf(_details!, customerBillNumber: _customerBillNumber);
                },
              ),
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.orange.shade50,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.local_shipping_outlined,
                      color: Colors.orange),
                ),
                title: const Text('Delivery Challan (No-Price Slip)',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                subtitle: const Text(
                    'Dispatch slip for driver with items & address only'),
                onTap: () async {
                  Navigator.pop(ctx);
                  await InvoicePdfService.instance.sharePdf(
                    _details!,
                    isDeliveryChallan: true,
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showUpiQrDialog() {
    if (_details == null) return;
    final order = _details!.order;
    final shopService = ShopCustomizationService.instance;
    final upiId = shopService.upiId.trim();
    final shopName = shopService.shopName.trim();
    final amountToPay =
        order.dueAmount > 0 ? order.dueAmount : order.estimateTotal;

    if (upiId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please set your UPI ID first in Shop Settings!'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    final upiUri =
        'upi://pay?pa=$upiId&pn=${Uri.encodeComponent(shopName)}&am=${amountToPay.toStringAsFixed(2)}&cu=INR&tn=${Uri.encodeComponent("Bill ${order.formattedOrderId}")}';

    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.qr_code_2, color: Color(0xFF0F766E), size: 28),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'Scan & Pay UPI',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Customer scans to pay ₹${amountToPay.toStringAsFixed(2)}',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
            ),
            const SizedBox(height: 6),
            Text(
              'UPI ID: $upiId',
              style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey.shade300),
              ),
              child: QrImageView(
                data: upiUri,
                version: QrVersions.auto,
                size: 200,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Supports Google Pay, PhonePe, Paytm, BHIM',
              style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF0F766E),
            ),
            onPressed: () {
              Navigator.pop(ctx);
              _showRecordPaymentDialog();
            },
            child: const Text('Record Payment'),
          ),
        ],
      ),
    );
  }

  void _showRecordPaymentDialog() {
    if (_details == null) return;
    final order = _details!.order;
    final total = order.estimateTotal;
    final currentPaid = order.paidAmount;
    final due = order.dueAmount;
    final isRetail = ShopCustomizationService.instance.isPureOfflineMode ||
        const bool.fromEnvironment('STANDALONE_LOCAL');
    final availableModes =
        isRetail ? ['Cash', 'UPI'] : ['Cash', 'UPI', 'Khata / Credit'];

    final amountController = TextEditingController(
      text: due > 0
          ? (due % 1 == 0 ? due.toInt().toString() : due.toStringAsFixed(2))
          : '',
    );
    String selectedMode = order.paymentMode.isNotEmpty && availableModes.contains(order.paymentMode)
        ? order.paymentMode
        : (isRetail ? 'Cash' : 'UPI');

    showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              const Icon(Icons.account_balance_wallet_outlined,
                  color: Color(0xFF0F766E)),
              const SizedBox(width: 8),
              Text(isRetail ? 'Record Payment' : 'Record Payment / Khata',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Total Bill: ₹${total.toStringAsFixed(2)}',
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                  Text('Due: ₹${due.toStringAsFixed(2)}',
                      style: TextStyle(
                          color: due > 0 ? Colors.red.shade700 : Colors.teal,
                          fontWeight: FontWeight.bold)),
                ],
              ),
              const SizedBox(height: 16),
              const Text('Amount Paid Now:',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
              const SizedBox(height: 6),
              TextField(
                controller: amountController,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  prefixText: '₹ ',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                onChanged: (val) => setDialogState(() {}),
              ),
              Builder(
                builder: (context) {
                  final entered =
                      double.tryParse(amountController.text.trim()) ?? 0.0;
                  if (entered > due && due > 0) {
                    final excess = entered - due;
                    return Container(
                      margin: const EdgeInsets.only(top: 8),
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.amber.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.amber.shade400),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.info_outline,
                              size: 16, color: Colors.amber.shade900),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              'Excess ₹${excess.toStringAsFixed(2)} will be credited as advance payment for future bills.',
                              style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.amber.shade900,
                                  fontWeight: FontWeight.bold),
                            ),
                          ),
                        ],
                      ),
                    );
                  }
                  return const SizedBox.shrink();
                },
              ),
              const SizedBox(height: 16),
              const Text('Payment Mode:',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                children: availableModes.map((mode) {
                  final isSelected = selectedMode == mode;
                  return ChoiceChip(
                    label: Text(mode),
                    selected: isSelected,
                    selectedColor: const Color(0xFF0F766E),
                    labelStyle: TextStyle(
                      color: isSelected ? Colors.white : Colors.black87,
                      fontWeight:
                          isSelected ? FontWeight.bold : FontWeight.normal,
                    ),
                    onSelected: (val) {
                      if (val) setDialogState(() => selectedMode = mode);
                    },
                  );
                }).toList(),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF0F766E),
              ),
              onPressed: () async {
                double entered =
                    double.tryParse(amountController.text.trim()) ?? 0.0;
                if (entered <= 0) return;

                if (entered > due && due > 0) {
                  final excess = entered - due;
                  final confirmAdvance = await showDialog<String>(
                    context: ctx,
                    builder: (actx) => AlertDialog(
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16)),
                      title: const Row(
                        children: [
                          Icon(Icons.account_balance_wallet_outlined,
                              color: Color(0xFF0F766E)),
                          SizedBox(width: 8),
                          Text('Advance Payment Notice'),
                        ],
                      ),
                      content: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                              'Order balance due is ₹${due.toStringAsFixed(2)}.'),
                          Text(
                              'Entered payment: ₹${entered.toStringAsFixed(2)}.\n'),
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: Colors.teal.shade50,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.teal.shade200),
                            ),
                            child: Text(
                              'The excess amount of ₹${excess.toStringAsFixed(2)} will be credited as an ADVANCE PAYMENT on the customer\'s account and settled with future bills.',
                              style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF0F766E)),
                            ),
                          ),
                          const SizedBox(height: 12),
                          const Text(
                              'Would you like to accept this advance or cap at the exact due amount?'),
                        ],
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(actx, 'cancel'),
                          child: const Text('Cancel'),
                        ),
                        OutlinedButton(
                          onPressed: () => Navigator.pop(actx, 'cap_due'),
                          child: Text('Cap at ₹${due.toStringAsFixed(2)}'),
                        ),
                        FilledButton(
                          style: FilledButton.styleFrom(
                              backgroundColor: const Color(0xFF0F766E)),
                          onPressed: () => Navigator.pop(actx, 'advance'),
                          child: Text(
                              'Accept ₹${excess.toStringAsFixed(2)} as Advance'),
                        ),
                      ],
                    ),
                  );

                  if (confirmAdvance == null || confirmAdvance == 'cancel') return;
                  if (confirmAdvance == 'cap_due') {
                    entered = due;
                  }
                }

                final newPaid = (currentPaid + entered).clamp(0.0, total);
                await DatabaseHelper.instance.recordOrderPayment(
                  orderId: order.id!,
                  paidAmount: newPaid,
                  paymentMode: selectedMode,
                );

                if (entered > due && due > 0) {
                  final excess = entered - due;
                  await DatabaseHelper.instance.recordCustomerKhataPayment(
                    customerId: order.customerId,
                    amount: excess,
                    paymentMode: selectedMode.toLowerCase(),
                    notes:
                        'Advance payment of ₹${excess.toStringAsFixed(2)} from ${order.formattedOrderId}',
                  );
                }

                if (ctx.mounted) Navigator.pop(ctx);
                await _load();
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                          'Payment of ₹${entered.toStringAsFixed(2)} recorded!'),
                      backgroundColor: const Color(0xFF0F766E),
                    ),
                  );
                }
              },
              child: const Text('Save Payment'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showEditBillDialog(OrderEntity order) async {
    final breakdown = order.billBreakdown ??
        BillBreakdown.calculate(
          subtotal: _details!.items.fold<double>(
            0.0,
            (sum, i) => sum + (i.unitPrice * i.quantityOrdered),
          ),
          grandTotalOverride: order.estimateTotal,
        );

    bool applyDiscount = breakdown.applyDiscount;
    String discountType = breakdown.discountType;
    double discountValue = breakdown.discountValue;
    bool applyGst = breakdown.applyGst;
    double gstRate = breakdown.gstRate > 0 ? breakdown.gstRate : 18.0;
    final otherCharges = List<OtherCharge>.from(breakdown.otherCharges);

    final discountController = TextEditingController(
      text: discountValue > 0
          ? (discountValue % 1 == 0
              ? discountValue.toInt().toString()
              : discountValue.toString())
          : '',
    );
    final gstController = TextEditingController(
      text: gstRate % 1 == 0 ? gstRate.toInt().toString() : gstRate.toString(),
    );

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            final subtotal = _details!.items.fold<double>(
              0.0,
              (sum, i) => sum + (i.unitPrice * i.quantityGiven),
            );

            double discountAmount = 0.0;
            if (applyDiscount && subtotal > 0) {
              final safeDiscountValue = discountValue.clamp(0.0, double.infinity);
              if (discountType == 'percent') {
                final safePercent = safeDiscountValue.clamp(0.0, 100.0);
                discountAmount = (subtotal * safePercent / 100.0).clamp(0.0, subtotal);
              } else {
                discountAmount = safeDiscountValue.clamp(0.0, subtotal);
              }
            }

            final taxable =
                (subtotal - discountAmount).clamp(0.0, double.infinity);
            final gstAmount = applyGst ? (taxable * gstRate / 100.0) : 0.0;
            final otherTotal =
                otherCharges.fold<double>(0.0, (sum, c) => sum + c.amount);
            final previewGrandTotal =
                (taxable + gstAmount + otherTotal).clamp(0.0, double.infinity);

            return Padding(
              padding: EdgeInsets.only(
                left: 20,
                right: 20,
                top: 20,
                bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Edit Bill (Charges & Discount)',
                          style: TextStyle(
                              fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () => Navigator.pop(ctx),
                        ),
                      ],
                    ),
                    const Divider(),
                    const SizedBox(height: 8),

                    // Subtotal Display
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Items Subtotal:',
                            style: TextStyle(fontSize: 14)),
                        Text('₹ ${subtotal.toStringAsFixed(2)}',
                            style: const TextStyle(
                                fontSize: 15, fontWeight: FontWeight.bold)),
                      ],
                    ),
                    const SizedBox(height: 12),

                    // Discount Toggle & Input
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Checkbox(
                              value: applyDiscount,
                              onChanged: (val) {
                                setModalState(() => applyDiscount = val ?? false);
                              },
                            ),
                            const Text('Discount / Offer',
                                style: TextStyle(fontWeight: FontWeight.bold)),
                          ],
                        ),
                        if (applyDiscount && discountAmount > 0)
                          Text(
                            '- ₹ ${discountAmount.toStringAsFixed(2)}',
                            style: TextStyle(
                                color: Colors.green.shade800,
                                fontWeight: FontWeight.bold),
                          ),
                      ],
                    ),
                    if (applyDiscount) ...[
                      Padding(
                        padding: const EdgeInsets.only(left: 12, bottom: 8),
                        child: Row(
                          children: [
                            SegmentedButton<String>(
                              style: SegmentedButton.styleFrom(
                                visualDensity: VisualDensity.compact,
                              ),
                              segments: const [
                                ButtonSegment(
                                    value: 'flat',
                                    label: Text('₹ Flat',
                                        style: TextStyle(fontSize: 12))),
                                ButtonSegment(
                                    value: 'percent',
                                    label: Text('% Off',
                                        style: TextStyle(fontSize: 12))),
                              ],
                              selected: {discountType},
                              onSelectionChanged: (set) {
                                setModalState(() => discountType = set.first);
                              },
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: TextField(
                                controller: discountController,
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                        decimal: true),
                                decoration: InputDecoration(
                                  hintText: discountType == 'flat'
                                      ? 'e.g. 100'
                                      : 'e.g. 5',
                                  prefixText:
                                      discountType == 'flat' ? '₹ ' : null,
                                  suffixText:
                                      discountType == 'percent' ? '%' : null,
                                  isDense: true,
                                  border: const OutlineInputBorder(),
                                  errorText: discountValue < 0
                                      ? 'Cannot be negative'
                                      : (discountType == 'percent' && discountValue > 100
                                          ? 'Cannot exceed 100%'
                                          : (discountType == 'flat' && discountValue > subtotal
                                              ? 'Cannot exceed bill total'
                                              : null)),
                                ),
                                onChanged: (val) {
                                  setModalState(() {
                                    discountValue =
                                        double.tryParse(val.trim()) ?? 0.0;
                                  });
                                },
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],

                    const Divider(height: 20),

                    // GST Toggle & Input
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Checkbox(
                              value: applyGst,
                              onChanged: (val) {
                                setModalState(() => applyGst = val ?? false);
                              },
                            ),
                            const Text('Add GST',
                                style: TextStyle(fontWeight: FontWeight.bold)),
                          ],
                        ),
                        if (applyGst)
                          Text(
                            '+ ₹ ${gstAmount.toStringAsFixed(2)}',
                            style: const TextStyle(
                                color: Colors.teal,
                                fontWeight: FontWeight.bold),
                          ),
                      ],
                    ),
                    if (applyGst) ...[
                      Padding(
                        padding: const EdgeInsets.only(left: 12, bottom: 8),
                        child: Row(
                          children: [
                            const Text('GST Rate: ',
                                style: TextStyle(fontSize: 13)),
                            const SizedBox(width: 8),
                            SizedBox(
                              width: 90,
                              child: TextField(
                                controller: gstController,
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                        decimal: true),
                                decoration: const InputDecoration(
                                  suffixText: '%',
                                  isDense: true,
                                  border: OutlineInputBorder(),
                                ),
                                onChanged: (val) {
                                  setModalState(() {
                                    gstRate =
                                        double.tryParse(val.trim()) ?? 18.0;
                                  });
                                },
                              ),
                            ),
                            const SizedBox(width: 8),
                            Wrap(
                              spacing: 4,
                              children: [5.0, 12.0, 18.0, 28.0].map((r) {
                                final rStr = r % 1 == 0
                                    ? r.toInt().toString()
                                    : r.toString();
                                return ActionChip(
                                  label: Text('$rStr%',
                                      style: const TextStyle(fontSize: 11)),
                                  visualDensity: VisualDensity.compact,
                                  padding: EdgeInsets.zero,
                                  onPressed: () {
                                    setModalState(() {
                                      gstRate = r;
                                      gstController.text = rStr;
                                    });
                                  },
                                );
                              }).toList(),
                            ),
                          ],
                        ),
                      ),
                    ],

                    const Divider(height: 20),

                    // Other Charges
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Other Charges (Transport, etc.):',
                            style: TextStyle(fontWeight: FontWeight.bold)),
                        TextButton.icon(
                          icon: const Icon(Icons.add, size: 16),
                          label: const Text('Add Charge',
                              style: TextStyle(fontSize: 12)),
                          onPressed: () async {
                            final nameCtrl = TextEditingController();
                            final amtCtrl = TextEditingController();
                            final added = await showDialog<bool>(
                              context: ctx,
                              builder: (dCtx) => AlertDialog(
                                title: const Text('Add Other Charge'),
                                content: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    TextField(
                                      controller: nameCtrl,
                                      decoration: const InputDecoration(
                                          labelText:
                                              'Charge Name (e.g. Transport, Labor)'),
                                    ),
                                    const SizedBox(height: 10),
                                    TextField(
                                      controller: amtCtrl,
                                      keyboardType:
                                          const TextInputType.numberWithOptions(
                                              decimal: true),
                                      decoration: const InputDecoration(
                                          labelText: 'Amount ₹'),
                                    ),
                                  ],
                                ),
                                actions: [
                                  TextButton(
                                      onPressed: () => Navigator.pop(dCtx, false),
                                      child: const Text('CANCEL')),
                                  FilledButton(
                                      onPressed: () => Navigator.pop(dCtx, true),
                                      child: const Text('ADD')),
                                ],
                              ),
                            );
                            if (added == true && amtCtrl.text.isNotEmpty) {
                              final amt =
                                  double.tryParse(amtCtrl.text.trim()) ?? 0.0;
                              if (amt > 0) {
                                setModalState(() {
                                  otherCharges.add(OtherCharge(
                                    name: nameCtrl.text.trim().isNotEmpty
                                        ? nameCtrl.text.trim()
                                        : 'Transport',
                                    amount: amt,
                                  ));
                                });
                              }
                            }
                          },
                        ),
                      ],
                    ),
                    for (int i = 0; i < otherCharges.length; i++)
                      ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: Text(otherCharges[i].name),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              '+ ₹ ${otherCharges[i].amount.toStringAsFixed(2)}',
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Colors.teal),
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete_outline,
                                  size: 18, color: Colors.red),
                              onPressed: () {
                                setModalState(() => otherCharges.removeAt(i));
                              },
                            ),
                          ],
                        ),
                      ),

                    const Divider(height: 24),

                    // Grand Total Summary Box
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Theme.of(ctx)
                            .colorScheme
                            .primaryContainer
                            .withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                            color: Theme.of(ctx)
                                .colorScheme
                                .primary
                                .withValues(alpha: 0.3)),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Grand Total:',
                              style: TextStyle(
                                  fontSize: 16, fontWeight: FontWeight.bold)),
                          Text(
                            '₹ ${previewGrandTotal.toStringAsFixed(2)}',
                            style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w900,
                                color: Colors.teal),
                          ),
                        ],
                      ),
                    ),
                    if (_customerAdvanceBalance > 0.01 && previewGrandTotal > 0) ...[
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: const Color(0xFFCCFBF1),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: const Color(0xFF0F766E)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text(
                                  'Advance Credit Deduction:',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12.5,
                                    color: Color(0xFF0F766E),
                                  ),
                                ),
                                Text(
                                  '- ₹ ${math.min(previewGrandTotal, _customerAdvanceBalance).toStringAsFixed(2)}',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13,
                                    color: Color(0xFF0F766E),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '₹ ${math.min(previewGrandTotal, _customerAdvanceBalance).toStringAsFixed(2)} reduced from current bill (Customer advance: ₹ ${_customerAdvanceBalance.toStringAsFixed(2)})',
                              style: const TextStyle(fontSize: 11, color: Color(0xFF115E59), fontWeight: FontWeight.w600),
                            ),
                            const SizedBox(height: 6),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text(
                                  'Net Payable after Advance:',
                                  style: TextStyle(fontWeight: FontWeight.w900, fontSize: 13),
                                ),
                                Text(
                                  '₹ ${(previewGrandTotal - math.min(previewGrandTotal, _customerAdvanceBalance)).clamp(0.0, double.infinity).toStringAsFixed(2)}',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w900,
                                    fontSize: 15,
                                    color: Color(0xFF0F766E),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 16),

                    // Save Button
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFF0F766E),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        onPressed: () async {
                          final updatedBreakdown = BillBreakdown.calculate(
                            subtotal: subtotal,
                            applyDiscount: applyDiscount,
                            discountType: discountType,
                            discountValue: discountValue,
                            applyGst: applyGst,
                            gstRate: gstRate,
                            otherCharges: otherCharges,
                            note: breakdown.note,
                          );

                          await widget.orderRepository.updateOrderBillBreakdown(
                            orderId: order.id!,
                            billBreakdown: updatedBreakdown,
                          );
                          if (ctx.mounted) {
                            Navigator.pop(ctx);
                          }
                          await _load();
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Bill updated successfully!'),
                                backgroundColor: Color(0xFF0F766E),
                              ),
                            );
                          }
                        },
                        child: const Text('SAVE BILL CHANGES',
                            style: TextStyle(fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context);
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_details == null) {
      return Scaffold(body: Center(child: Text(s.t('orderNotFound'))));
    }

    final order = _details!.order;
    final totalItemsCount = _details!.items.length;
    final fullyGivenItems = _details!.items.where((i) => i.quantityGiven >= i.quantityOrdered).length;
    final overallProgress = totalItemsCount > 0 ? (fullyGivenItems / totalItemsCount) : 0.0;

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${_customerBillNumber != null ? "Bill #$_customerBillNumber • " : ""}${order.formattedOrderId} - ${order.customerNameSnapshot}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            if (!ShopCustomizationService.instance.isPureOfflineMode) ...[
              Text(
                'Taken by: ${order.takenBy != null && order.takenBy!.trim().isNotEmpty && order.takenBy!.trim() != 'Store' ? order.takenBy!.trim() : ShopSyncService.instance.currentUserOrDeviceName} • ${DateFormat('dd MMM yyyy, hh:mm a').format(order.createdAt)}',
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: Colors.teal.shade800),
              ),
            ] else ...[
              Text(
                DateFormat('dd MMM yyyy, hh:mm a').format(order.createdAt),
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.normal,
                    color: Colors.grey.shade600),
              ),
            ],
          ],
        ),
        actions: <Widget>[
          IconButton(
            tooltip: 'Order Packing Preview / Slip',
            icon: const Icon(Icons.inventory_2_outlined),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => OrderPackingSlipScreen(
                    details: _details!,
                    customerBillNumber: _customerBillNumber,
                  ),
                ),
              );
            },
          ),
          IconButton(
            tooltip: '1-Tap Repeat Order',
            icon: const Icon(Icons.repeat_rounded),
            onPressed: _repeatOrder,
          ),
          IconButton(
            tooltip: 'Print & PDF Receipts',
            icon: const Icon(Icons.print_outlined),
            onPressed: _showPrintMenu,
          ),
          IconButton(
            tooltip: 'Share Order Summary',
            icon: const Icon(Icons.share),
            onPressed: () {
              if (!_ensureAllItemsPriced(actionName: 'share bill')) return;
              ShareService.shareOrderDetails(_details!, customerBillNumber: _customerBillNumber);
            },
          ),
          if (order.status != OrderStatus.completed &&
              order.status != OrderStatus.closed)
            IconButton(
              tooltip: 'Add products to order',
              icon: const Icon(Icons.playlist_add),
              onPressed: () async {
                final customer = await widget.customerRepository
                    .getCustomerById(order.customerId);
                if (!context.mounted || customer == null) return;
                await Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) => ProductSelectionScreen(
                      customer: customer,
                      productRepository: widget.productRepository,
                      orderRepository: widget.orderRepository,
                      existingOrderId: order.id,
                    ),
                  ),
                );
                await _load();
              },
            ),
        ],
      ),
      body: ListView(
        controller: _scrollController,
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          if (order.status == OrderStatus.completed ||
              order.status == OrderStatus.closed)
            Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFFF0FDF4),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFBBF7D0)),
              ),
              child: const Row(
                children: [
                  Icon(Icons.lock_outline_rounded,
                      color: Color(0xFF15803D), size: 20),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Order is Closed & Recorded in Khata. All editing is locked.',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 12.5,
                        color: Color(0xFF166534),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          // Order Overview Card
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.2)),
            ),

              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.shopping_bag_outlined, size: 20),
                          const SizedBox(width: 8),
                          Text('$fullyGivenItems of $totalItemsCount items fulfilled', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                        ],
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          orderStatusLabel(order.status),
                          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: LinearProgressIndicator(
                      value: overallProgress,
                      minHeight: 8,
                      backgroundColor: Colors.grey.shade300,
                      color: Colors.teal,
                    ),
                  ),
                  if (order.billBreakdown != null) ...[
                    const SizedBox(height: 10),
                    const Divider(height: 1),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(s.t('itemsSubtotal'),
                            style: TextStyle(
                                fontSize: 13, color: Colors.grey.shade700)),
                        Text(
                            '₹ ${order.billBreakdown!.subtotal.toStringAsFixed(2)}',
                            style: const TextStyle(
                                fontWeight: FontWeight.w600, fontSize: 13)),
                      ],
                    ),
                    if (order.billBreakdown!.applyDiscount &&
                        order.billBreakdown!.discountAmount > 0) ...[
                      const SizedBox(height: 4),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Discount (${order.billBreakdown!.discountType == 'percent' ? '${order.billBreakdown!.discountValue % 1 == 0 ? order.billBreakdown!.discountValue.toInt() : order.billBreakdown!.discountValue}%' : 'Flat ₹${order.billBreakdown!.discountValue.toStringAsFixed(0)}'}):',
                            style: TextStyle(
                                fontSize: 13,
                                color: Colors.green.shade800,
                                fontWeight: FontWeight.w600),
                          ),
                          Text(
                            '- ₹ ${order.billBreakdown!.discountAmount.toStringAsFixed(2)}',
                            style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                                color: Colors.green.shade800),
                          ),
                        ],
                      ),
                    ],
                    if (order.billBreakdown!.applyGst) ...[
                      const SizedBox(height: 4),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                              'GST (${order.billBreakdown!.gstRate % 1 == 0 ? order.billBreakdown!.gstRate.toInt() : order.billBreakdown!.gstRate}%):',
                              style: TextStyle(
                                  fontSize: 13, color: Colors.grey.shade700)),
                          Text(
                              '+ ₹ ${order.billBreakdown!.gstAmount.toStringAsFixed(2)}',
                              style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13,
                                  color: Colors.teal)),
                        ],
                      ),
                    ],
                    for (final charge in order.billBreakdown!.otherCharges) ...[
                      const SizedBox(height: 4),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('${charge.name}:',
                              style: TextStyle(
                                  fontSize: 13, color: Colors.grey.shade700)),
                          Text('+ ₹ ${charge.amount.toStringAsFixed(2)}',
                              style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13,
                                  color: Colors.teal)),
                        ],
                      ),
                    ],
                  ],
                  if (order.estimateTotal > 0) ...[
                    const SizedBox(height: 10),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(s.t('grandTotal'),
                            style: const TextStyle(fontWeight: FontWeight.w700)),
                        Text('₹ ${order.estimateTotal.toStringAsFixed(2)}',
                            style: const TextStyle(
                                fontWeight: FontWeight.w900,
                                color: Colors.teal,
                                fontSize: 16)),
                      ],
                    ),

                  if (_customerAdvanceBalance > 0.01 && order.estimateTotal > 0) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: const Color(0xFFCCFBF1).withValues(alpha: 0.6),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xFF0F766E).withValues(alpha: 0.4)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text(
                                'Advance Credit Adjusted:',
                                style: TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF0F766E),
                                ),
                              ),
                              Text(
                                '- ₹ ${math.min(order.estimateTotal, _customerAdvanceBalance).toStringAsFixed(2)}',
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w900,
                                  color: Color(0xFF0F766E),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 3),
                          Text(
                            '₹ ${math.min(order.estimateTotal, _customerAdvanceBalance).toStringAsFixed(2)} reduced from current bill since customer has advance credit of ₹ ${_customerAdvanceBalance.toStringAsFixed(2)}.',
                            style: const TextStyle(
                              fontSize: 11,
                              color: Color(0xFF115E59),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const Divider(height: 12),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text(
                                'Net Due / Payable after Advance:',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w800,
                                  color: Color(0xFF0F172A),
                                ),
                              ),
                              Text(
                                '₹ ${(order.estimateTotal - math.min(order.estimateTotal, _customerAdvanceBalance)).clamp(0.0, double.infinity).toStringAsFixed(2)}',
                                style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w900,
                                  color: Color(0xFF0F766E),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                  ],
                  const SizedBox(height: 6),
                  if (order.status != OrderStatus.completed &&
                      order.status != OrderStatus.closed)
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton.icon(
                        style: TextButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                          foregroundColor: const Color(0xFF0F766E),
                        ),
                        icon: const Icon(Icons.tune, size: 16),
                        label: const Text('Edit Bill (Charges & Discount)',
                            style: TextStyle(
                                fontSize: 12, fontWeight: FontWeight.bold)),
                        onPressed: () => _showEditBillDialog(order),
                      ),
                    ),
                  if (order.billBreakdown?.note != null &&
                      order.billBreakdown!.note!.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.amber.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.amber.shade200),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.info_outline,
                              size: 16, color: Colors.amber.shade900),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              order.billBreakdown!.note!,
                              style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.amber.shade900,
                                  fontWeight: FontWeight.w600),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 10),

            // Payment & Khata Status Card
            Builder(
              builder: (context) {
                final isRetail = ShopCustomizationService.instance.isPureOfflineMode ||
                    const bool.fromEnvironment('STANDALONE_LOCAL');
                return Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: order.isFullyPaid
                        ? Colors.teal.shade50
                        : (order.paidAmount > 0
                            ? Colors.amber.shade50
                            : Colors.red.shade50),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: order.isFullyPaid
                          ? Colors.teal.shade200
                          : (order.paidAmount > 0
                              ? Colors.amber.shade300
                              : Colors.red.shade200),
                    ),
                  ),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              Icon(
                                order.isFullyPaid
                                    ? Icons.check_circle
                                    : (order.paidAmount > 0
                                        ? Icons.timelapse
                                        : Icons.error_outline),
                                size: 18,
                                color: order.isFullyPaid
                                    ? Colors.teal.shade800
                                    : (order.paidAmount > 0
                                        ? Colors.amber.shade900
                                        : Colors.red.shade800),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                order.isFullyPaid
                                    ? 'PAID (${order.paymentMode.toUpperCase()})'
                                    : (order.paidAmount > 0
                                        ? 'PARTIAL (${order.paymentMode.toUpperCase()})'
                                        : (isRetail
                                            ? 'UNPAID (COUNTER)'
                                            : 'UNPAID / UDHAAR (KHATA)')),
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                  color: order.isFullyPaid
                                      ? Colors.teal.shade900
                                      : (order.paidAmount > 0
                                          ? Colors.amber.shade900
                                          : Colors.red.shade900),
                                ),
                              ),
                            ],
                          ),
                          Text(
                            'Paid: ₹${order.paidAmount.toStringAsFixed(2)}',
                            style: const TextStyle(
                                fontWeight: FontWeight.w700, fontSize: 13),
                          ),
                        ],
                      ),
                      if (order.dueAmount > 0.01) ...[
                        const SizedBox(height: 6),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              isRetail ? 'Balance Due:' : 'Balance Due (Udhaar):',
                              style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.red.shade800,
                                  fontWeight: FontWeight.w600),
                            ),
                            Text(
                              '₹ ${order.dueAmount.toStringAsFixed(2)}',
                              style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.red.shade800),
                            ),
                          ],
                        ),
                      ],
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              style: OutlinedButton.styleFrom(
                                visualDensity: VisualDensity.compact,
                                padding: const EdgeInsets.symmetric(vertical: 6),
                              ),
                              icon: const Icon(Icons.qr_code_2, size: 16),
                              label: const Text('UPI QR',
                                  style: TextStyle(fontSize: 12)),
                              onPressed: _showUpiQrDialog,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: FilledButton.tonalIcon(
                              style: FilledButton.styleFrom(
                                visualDensity: VisualDensity.compact,
                                padding: const EdgeInsets.symmetric(vertical: 6),
                              ),
                              icon: const Icon(Icons.payments_outlined, size: 16),
                              label: Text(
                                  isRetail ? 'Record Payment' : 'Pay / Khata',
                                  style: const TextStyle(fontSize: 12)),
                              onPressed: _showRecordPaymentDialog,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              },
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    const Text(
                      'ITEMS TO FULFILL',
                      style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 13,
                          color: Colors.grey,
                          letterSpacing: 0.5),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        foregroundColor: const Color(0xFF0F766E),
                        side: const BorderSide(color: Color(0xFF0F766E), width: 1),
                      ),
                      icon: const Icon(Icons.inventory_2_outlined, size: 14),
                      label: const Text('📦 Packing Slip',
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute<void>(
                            builder: (_) => OrderPackingSlipScreen(
                              details: _details!,
                              customerBillNumber: _customerBillNumber,
                            ),
                          ),
                        );
                      },
                    ),
                  ],
                ),
                if (order.status != OrderStatus.completed &&
                    order.status != OrderStatus.closed)
                  TextButton.icon(
                    style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      foregroundColor: const Color(0xFF0F766E),
                    ),
                    icon: const Icon(Icons.add_circle_outline, size: 16),
                    label: const Text('+ Add Items',
                        style:
                            TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                    onPressed: _navigateToAddProducts,
                  ),
              ],
            ),
            const SizedBox(height: 8),
            ...List.generate(_details!.items.length, (index) {
              final item = _details!.items[index];
              final localStatus =
                  _statusFromQty(item.quantityOrdered, item.quantityGiven);
              final seenOptions = <String>{};
              final options = <String>[];
              for (final e in item.options) {
                final n = s.catalog(e.optionName).trim();
                final v = s.catalog(e.optionValue).trim();
                if (n.isEmpty && v.isEmpty) continue;
                final key =
                    '${e.optionName.toLowerCase().trim()}:${e.optionValue.toLowerCase().trim()}';
                if (seenOptions.add(key)) {
                  options.add('$n: $v');
                }
              }
              final pending = (item.quantityOrdered - item.quantityGiven)
                  .clamp(0, item.quantityOrdered);
              final snapshot =
                  jsonDecode(item.productSnapshot) as Map<String, dynamic>;
              final detailsText =
                  item.description ?? snapshot['description'] as String?;
              final isOrderClosed = order.status == OrderStatus.completed || order.status == OrderStatus.closed;
              final isProcuredShortage = isOrderClosed && item.quantityGiven < item.quantityOrdered && item.procurementStatus == ProcurementStatus.notRequired;

                  return Card(
                    margin: const EdgeInsets.only(bottom: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    elevation: 1.5,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                child: Text(
                                  item.itemName,
                                  style: const TextStyle(
                                      fontSize: 17, fontWeight: FontWeight.bold),
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: _itemStatusBgColor(localStatus),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: _itemStatusColor(localStatus).withValues(alpha: 0.5)),
                                ),
                                child: Text(
                                  _itemStatusTitle(localStatus),
                                  style: TextStyle(
                                    color: _itemStatusColor(localStatus),
                                    fontWeight: FontWeight.w800,
                                    fontSize: 11,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          if (options.isNotEmpty) ...[
                            const SizedBox(height: 6),
                            Wrap(
                              spacing: 6,
                              children: options.map((opt) => Chip(
                                label: Text(opt, style: const TextStyle(fontSize: 11)),
                                visualDensity: VisualDensity.compact,
                                padding: EdgeInsets.zero,
                              )).toList(),
                            ),
                          ],
                          if ((detailsText ?? '').isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text('Details: $detailsText', style: TextStyle(color: Colors.grey.shade700, fontSize: 13)),
                            ),
                          const SizedBox(height: 12),
                          // Metric pills row
                          Row(
                            children: [
                              QtyBadge(label: 'Ordered', qty: item.quantityOrdered, unit: item.unit, color: Colors.blue),
                              const SizedBox(width: 8),
                              QtyBadge(label: 'Given', qty: item.quantityGiven, unit: item.unit, color: Colors.teal),
                              const SizedBox(width: 8),
                              if (isProcuredShortage)
                                QtyBadge(
                                  label: 'Procured (In Stock)',
                                  qty: (item.quantityOrdered - item.quantityGiven).clamp(0, item.quantityOrdered),
                                  unit: item.unit,
                                  color: const Color(0xFF0F766E),
                                )
                              else
                                QtyBadge(
                                  label: item.procurementStatus == ProcurementStatus.toProcure ? 'To Procure' : 'Pending',
                                  qty: pending.toDouble(),
                                  unit: item.unit,
                                  color: pending > 0 ? Colors.deepOrange : Colors.grey,
                                ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          // Price editing row
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  'Item Total: ₹${(item.unitPrice * item.quantityGiven).toStringAsFixed(2)}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14,
                                      color: Colors.teal),
                                ),
                              ),
                              const SizedBox(width: 8),
                              if (order.status == OrderStatus.completed ||
                                  order.status == OrderStatus.closed)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 10, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: Colors.teal.shade50,
                                    borderRadius: BorderRadius.circular(8),
                                    border:
                                        Border.all(color: Colors.teal.shade200),
                                  ),
                                  child: Text(
                                    '₹ ${item.unitPrice.toStringAsFixed(2)} / ${item.unit}',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12,
                                      color: Colors.teal.shade900,
                                    ),
                                  ),
                                )
                              else
                                SizedBox(
                                  width: 120,
                                  child: Builder(
                                    builder: (context) {
                                      final priceCtrl = _itemPriceControllers.putIfAbsent(
                                        item.id ?? index,
                                        () => TextEditingController(
                                          text: item.unitPrice > 0
                                              ? (item.unitPrice % 1 == 0
                                                  ? item.unitPrice.toInt().toString()
                                                  : item.unitPrice.toStringAsFixed(2))
                                              : '',
                                        ),
                                      );
                                      return TextField(
                                        enabled: ShopSyncService.instance.canChangePrice,
                                        controller: priceCtrl,
                                        keyboardType:
                                            const TextInputType.numberWithOptions(
                                                decimal: true),
                                        decoration: const InputDecoration(
                                          isDense: true,
                                          labelText: 'Price/Unit ₹',
                                          prefixText: '₹ ',
                                        ),
                                        onChanged: (val) {
                                          final parsed =
                                              double.tryParse(val.trim()) ?? 0.0;
                                          setState(() {
                                            _details!.items[index] =
                                                item.copyWith(unitPrice: parsed);
                                          });
                                        },
                                      );
                                    },
                                  ),
                                ),
                            ],
                          ),

                          if (order.status != OrderStatus.completed &&
                              order.status != OrderStatus.closed) ...[
                            const SizedBox(height: 12),
                            // Dual-Linked Fulfillment Controls (Given ⇄ Not Given / Short)
                            DualFulfillmentWidget(
                              ordered: item.quantityOrdered,
                              given: item.quantityGiven,
                              unit: item.unit,
                              onChanged: (newGiven) {
                                setState(() {
                                  _details!.items[index] =
                                      item.copyWith(quantityGiven: newGiven);
                                });
                              },
                            ),
                          ],
                        ],
                      ),
                    ),
                  );
                }),
                const SizedBox(height: 16),
              ],
            ),
      bottomNavigationBar: Container(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        decoration: BoxDecoration(
          color: Theme.of(context).scaffoldBackgroundColor,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 6,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: SafeArea(
          child: Row(
            children: [
              if (order.status == OrderStatus.completed ||
                  order.status == OrderStatus.closed) ...[
                Expanded(
                  child: Container(
                    height: 50,
                    decoration: BoxDecoration(
                      color: const Color(0xFF0F766E).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                          color: const Color(0xFF0F766E).withValues(alpha: 0.3)),
                    ),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.lock_rounded,
                            size: 18, color: Color(0xFF0F766E)),
                        SizedBox(width: 8),
                        Text(
                          'ORDER CLOSED & RECORDED IN KHATA (READ-ONLY)',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                            color: Color(0xFF0F766E),
                            letterSpacing: 0.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ] else ...[
                Expanded(
                  flex: 3,
                  child: LargeActionButton(
                    label: _saving ? s.t('saving') : 'SAVE CHANGES',
                    onTap: _saving ? null : _save,
                  ),
                ),
                if (ShopSyncService.instance.canCloseOrders) ...[
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 2,
                    child: SizedBox(
                      height: 52,
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: Colors.deepOrange.shade800,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        icon: const Icon(Icons.check_circle_outline, size: 20),
                        label: const Text(
                          'CLOSE ORDER',
                          style: TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 13),
                        ),
                        onPressed: _saving ? null : _closeOrder,
                      ),
                    ),
                  ),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }
}
