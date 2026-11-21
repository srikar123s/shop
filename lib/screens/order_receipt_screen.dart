import 'package:shop/database/database_helper.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shop/models/order.dart';
import 'package:shop/repositories/customer_repository.dart';
import 'package:shop/repositories/order_repository.dart';
import 'package:shop/repositories/product_repository.dart';
import 'package:shop/services/invoice_pdf_service.dart';
import 'package:shop/services/share_service.dart';
import 'package:shop/services/shop_customization_service.dart';

class OrderReceiptScreen extends StatefulWidget {
  const OrderReceiptScreen({
    super.key,
    required this.orderId,
    required this.orderRepository,
    required this.customerRepository,
    required this.productRepository,
    this.customerBillNumber,
  });

  final int orderId;
  final OrderRepository orderRepository;
  final CustomerRepository customerRepository;
  final ProductRepository productRepository;
  final int? customerBillNumber;

  @override
  State<OrderReceiptScreen> createState() => _OrderReceiptScreenState();
}

class _OrderReceiptScreenState extends State<OrderReceiptScreen> {
  OrderDetails? _details;
  bool _loading = true;
  String? _error;
  int? _customerBillNumber;

  @override
  void initState() {
    super.initState();
    _customerBillNumber = widget.customerBillNumber;
    _loadOrder();
  }

  Future<void> _loadOrder() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final details =
          await widget.orderRepository.getOrderDetails(widget.orderId);
      _customerBillNumber ??=
          await DatabaseHelper.instance.getCustomerBillSequence(widget.orderId);
      if (!mounted) return;
      setState(() {
        _details = details;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not load bill: $e';
        _loading = false;
      });
    }
  }

  bool _ensureAllItemsPriced(OrderDetails details, {required String actionName}) {
    final unpriced = details.items.where((i) => i.unitPrice <= 0).toList();
    if (unpriced.isEmpty) return true;

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
                children: unpriced.map((i) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Text('• ${i.itemName}', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.red.shade900)),
                )).toList(),
              ),
            ),
            const SizedBox(height: 12),
            const Text('Please return and set a valid price for each item before proceeding.'),
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

  @override
  Widget build(BuildContext context) {
    final currency = NumberFormat.currency(locale: 'en_IN', symbol: '₹ ');
    final s = ShopCustomizationService.instance;
    final isRetail =
        s.isPureOfflineMode || const bool.fromEnvironment('STANDALONE_LOCAL');

    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Order Receipt')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_error != null || _details == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Order Receipt')),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 48, color: Colors.red),
              const SizedBox(height: 12),
              Text(_error ?? 'Bill not found'),
              const SizedBox(height: 12),
              ElevatedButton(onPressed: _loadOrder, child: const Text('Retry')),
            ],
          ),
        ),
      );
    }

    final details = _details!;
    final order = details.order;
    final breakdown = order.billBreakdown;
    final dateStr =
        DateFormat('dd MMM yyyy, hh:mm a').format(order.createdAt);
    final shopName = s.shopName;
    final titleDoc = isRetail ? 'RETAIL CASH RECEIPT' : 'TAX INVOICE';

    // Calculate subtotal and grand total
    double calculatedSubtotal = 0;
    final itemsData = details.items.map((item) {
      final seenOpts = <String>{};
      final distinctOpts = <String>[];
      for (final e in item.options) {
        final k =
            '${e.optionName.trim().toLowerCase()}:${e.optionValue.trim().toLowerCase()}';
        if (e.optionName.trim().isNotEmpty && seenOpts.add(k)) {
          distinctOpts.add('${e.optionName}: ${e.optionValue}');
        }
      }
      final opts = distinctOpts.join(', ');
      final qtyStr = item.quantityOrdered % 1 == 0
          ? item.quantityOrdered.toInt().toString()
          : item.quantityOrdered.toString();
      final price = item.unitPrice;
      final amount = price * item.quantityOrdered;
      calculatedSubtotal += amount;

      return {
        'name': item.itemName,
        'options': opts,
        'qtyStr': '$qtyStr ${item.unit}',
        'price': price,
        'amount': amount,
      };
    }).toList();

    final finalGrandTotal = order.estimateTotal > 0
        ? order.estimateTotal
        : (breakdown?.grandTotal ?? calculatedSubtotal);

    final finalSubtotal = (breakdown?.subtotal ?? 0) > 0
        ? breakdown!.subtotal
        : calculatedSubtotal;

    final paidAmount = order.paidAmount;
    final balanceDue = (finalGrandTotal - paidAmount) > 0.01
        ? (finalGrandTotal - paidAmount)
        : 0.0;

    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9),
      appBar: AppBar(
        title: Text(
          _customerBillNumber != null
              ? 'Bill #$_customerBillNumber • ${order.formattedOrderId}'
              : 'Bill ${order.formattedOrderId}',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            tooltip: 'Share on WhatsApp',
            icon: const Icon(Icons.share_rounded),
            onPressed: () {
              if (!_ensureAllItemsPriced(details, actionName: 'share receipt')) return;
              ShareService.shareOrderDetails(details, customerBillNumber: _customerBillNumber);
            },
          ),
          IconButton(
            tooltip: 'Print Thermal Receipt (58mm)',
            icon: const Icon(Icons.print_outlined),
            onPressed: () {
              if (!_ensureAllItemsPriced(details, actionName: 'print receipt')) return;
              InvoicePdfService.instance.printReceipt(
                details,
                isThermal58mm: true,
                customerBillNumber: _customerBillNumber,
              );
            },
          ),
          IconButton(
            tooltip: 'Download / Share PDF',
            icon: const Icon(Icons.picture_as_pdf_outlined),
            onPressed: () {
              if (!_ensureAllItemsPriced(details, actionName: 'download/share PDF')) return;
              InvoicePdfService.instance.sharePdf(details, customerBillNumber: _customerBillNumber);
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 90),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 550),
            child: Card(
              elevation: 2,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16)),
              clipBehavior: Clip.antiAlias,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Receipt Header Banner (Matching WhatsApp Photo Receipt)
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: const BoxDecoration(
                      color: Color(0xFF0F766E),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Text(
                                '$shopName • $titleDoc',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Text(
                                '🔒 CLOSED BILL',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '${_customerBillNumber != null ? "Bill #$_customerBillNumber  •  " : ""}${order.formattedOrderId}  •  $dateStr',
                          style: const TextStyle(
                            color: Color(0xFFCCFBF1),
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Customer: ${order.customerNameSnapshot}${order.customerPhone != null && order.customerPhone!.isNotEmpty ? " (${order.customerPhone})" : ""}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Table Header
                  Container(
                    margin: const EdgeInsets.fromLTRB(14, 14, 14, 4),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE2E8F0),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Row(
                      children: [
                        Expanded(
                          flex: 5,
                          child: Text(
                            'ITEM & DETAILS',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 11,
                              color: Color(0xFF334155),
                            ),
                          ),
                        ),
                        Expanded(
                          flex: 2,
                          child: Text(
                            'QTY',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 11,
                              color: Color(0xFF334155),
                            ),
                          ),
                        ),
                        Expanded(
                          flex: 2,
                          child: Text(
                            'RATE',
                            textAlign: TextAlign.right,
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 11,
                              color: Color(0xFF334155),
                            ),
                          ),
                        ),
                        Expanded(
                          flex: 3,
                          child: Text(
                            'AMOUNT',
                            textAlign: TextAlign.right,
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 11,
                              color: Color(0xFF334155),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Table Rows
                  ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 4),
                    itemCount: itemsData.length,
                    separatorBuilder: (_, __) =>
                        Divider(height: 1, color: Colors.grey.shade200),
                    itemBuilder: (context, i) {
                      final item = itemsData[i];
                      final name = item['name'] as String;
                      final options = item['options'] as String;
                      final qtyStr = item['qtyStr'] as String;
                      final price = item['price'] as double;
                      final amount = item['amount'] as double;

                      return Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 10),
                        color: i % 2 == 0
                            ? Colors.white
                            : const Color(0xFFF8FAFC),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              flex: 5,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    name,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13,
                                      color: Color(0xFF1E293B),
                                    ),
                                  ),
                                  if (options.isNotEmpty) ...[
                                    const SizedBox(height: 2),
                                    Text(
                                      options,
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: Colors.grey.shade600,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            Expanded(
                              flex: 2,
                              child: Text(
                                qtyStr,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 12,
                                  color: Color(0xFF1E293B),
                                ),
                              ),
                            ),
                            Expanded(
                              flex: 2,
                              child: Text(
                                price > 0
                                    ? '₹${price.toStringAsFixed(2)}'
                                    : '-',
                                textAlign: TextAlign.right,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey.shade700,
                                ),
                              ),
                            ),
                            Expanded(
                              flex: 3,
                              child: Text(
                                amount > 0
                                    ? '₹${amount.toStringAsFixed(2)}'
                                    : '-',
                                textAlign: TextAlign.right,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                  color: Color(0xFF0F766E),
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),

                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 14),
                    child: Divider(thickness: 1.5),
                  ),

                  // Subtotal & Breakdown Section
                  Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 24, vertical: 6),
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('Items Subtotal',
                                style: TextStyle(
                                    fontSize: 13, color: Color(0xFF475569))),
                            Text(
                              currency.format(finalSubtotal),
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold, fontSize: 13),
                            ),
                          ],
                        ),
                        if (breakdown != null) ...[
                          if (breakdown.applyDiscount &&
                              breakdown.discountAmount > 0) ...[
                            const SizedBox(height: 4),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  'Discount (${breakdown.discountType == 'percent' ? '${breakdown.discountValue % 1 == 0 ? breakdown.discountValue.toInt() : breakdown.discountValue}%' : 'Flat ₹${breakdown.discountValue.toStringAsFixed(0)}'}):',
                                  style: TextStyle(
                                      fontSize: 13,
                                      color: Colors.green.shade800,
                                      fontWeight: FontWeight.w600),
                                ),
                                Text(
                                  '- ${currency.format(breakdown.discountAmount)}',
                                  style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13,
                                      color: Colors.green.shade800),
                                ),
                              ],
                            ),
                          ],
                          if (breakdown.applyGst) ...[
                            const SizedBox(height: 4),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  'GST (${breakdown.gstRate % 1 == 0 ? breakdown.gstRate.toInt() : breakdown.gstRate}%):',
                                  style: const TextStyle(
                                      fontSize: 13, color: Color(0xFF475569)),
                                ),
                                Text(
                                  '+ ${currency.format(breakdown.gstAmount)}',
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13,
                                      color: Color(0xFF0F766E)),
                                ),
                              ],
                            ),
                          ],
                          for (final charge in breakdown.otherCharges) ...[
                            const SizedBox(height: 4),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  charge.name,
                                  style: const TextStyle(
                                      fontSize: 13, color: Color(0xFF475569)),
                                ),
                                Text(
                                  '+ ${currency.format(charge.amount)}',
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13,
                                      color: Color(0xFF0F766E)),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ],
                    ),
                  ),

                  // Total Amount Banner
                  Container(
                    margin: const EdgeInsets.fromLTRB(14, 10, 14, 12),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 18, vertical: 14),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0F766E),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'TOTAL AMOUNT:',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.5,
                          ),
                        ),
                        Text(
                          currency.format(finalGrandTotal),
                          style: const TextStyle(
                            color: Color(0xFF5EEAD4),
                            fontSize: 20,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Payment & Khata Status Box
                  Container(
                    margin: const EdgeInsets.fromLTRB(14, 0, 14, 14),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              'Payment Status:',
                              style: TextStyle(fontSize: 12, color: Colors.grey),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: balanceDue <= 0.01
                                    ? Colors.green.shade50
                                    : (paidAmount > 0
                                        ? Colors.orange.shade50
                                        : Colors.red.shade50),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                balanceDue <= 0.01
                                    ? 'PAID IN FULL'
                                    : (paidAmount > 0
                                        ? 'PARTIAL PAYMENT'
                                        : 'UNPAID / UDHAAR (KHATA)'),
                                style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 11,
                                  color: balanceDue <= 0.01
                                      ? Colors.green.shade800
                                      : (paidAmount > 0
                                          ? Colors.orange.shade800
                                          : Colors.red.shade800),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Amount Paid (${order.paymentMode.toUpperCase()}):',
                              style: const TextStyle(
                                  fontSize: 12, color: Colors.grey),
                            ),
                            Text(
                              currency.format(paidAmount),
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                                color: paidAmount > 0
                                    ? Colors.green.shade800
                                    : Colors.black87,
                              ),
                            ),
                          ],
                        ),
                        if (balanceDue > 0.01) ...[
                          const SizedBox(height: 6),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text(
                                'Added to Khata Balance (Due):',
                                style: TextStyle(
                                    fontSize: 12, color: Colors.red),
                              ),
                              Text(
                                currency.format(balanceDue),
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                  color: Color(0xFFBE123C),
                                ),
                              ),
                            ],
                          ),
                        ],
                        if (breakdown?.note != null &&
                            breakdown!.note!.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.amber.shade50,
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: Colors.amber.shade200),
                            ),
                            child: Row(
                              children: [
                                Icon(Icons.info_outline,
                                    size: 15, color: Colors.amber.shade900),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    breakdown.note!,
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: Colors.amber.shade900,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),

                  // Footer note
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                    child: Center(
                      child: Text(
                        'Thank you for your business! • $shopName',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade500,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
      bottomNavigationBar: Container(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 10,
              offset: const Offset(0, -3),
            ),
          ],
        ),
        child: SafeArea(
          child: Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF25D366),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  icon: const Icon(Icons.chat_outlined, size: 18),
                  label: const Text(
                    'Share on WhatsApp',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                  onPressed: () {
                    if (!_ensureAllItemsPriced(details, actionName: 'share receipt')) return;
                    ShareService.shareOrderDetails(details);
                  },
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF0F766E),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  icon: const Icon(Icons.print_outlined, size: 18),
                  label: const Text(
                    'Print (58mm)',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                  onPressed: () {
                    if (!_ensureAllItemsPriced(details, actionName: 'print receipt')) return;
                    InvoicePdfService.instance.printReceipt(
                      details,
                      isThermal58mm: true,
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
