import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shop/l10n/app_localizations.dart';
import 'package:shop/models/order.dart';
import 'package:shop/repositories/order_repository.dart';
import 'package:shop/repositories/customer_repository.dart';
import 'package:shop/repositories/product_repository.dart';
import 'package:shop/screens/product_selection_screen.dart';
import 'package:shop/services/share_service.dart';
import 'package:shop/widgets/large_action_button.dart';
import 'package:shop/widgets/quantity_selector.dart';

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

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final details =
        await widget.orderRepository.getOrderDetails(widget.orderId);
    setState(() {
      _details = details;
      _loading = false;
    });
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

  Future<void> _closeOrder() async {
    if (_details == null || !mounted) return;
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
        titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
        contentPadding: const EdgeInsets.symmetric(horizontal: 20),
        actionsPadding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.orange.shade100,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(Icons.warning_amber_rounded,
                  color: Colors.orange.shade900, size: 24),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Order ${order.formattedOrderId}',
                    style: const TextStyle(
                        fontSize: 17, fontWeight: FontWeight.bold),
                  ),
                  Text(
                    '${unfulfilled.length} item(s) not fully given',
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
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade50,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey.shade300),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Items not given / partially given:',
                        style: TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                      const SizedBox(height: 8),
                      ...unfulfilled.map((item) {
                        final pending =
                            item.quantityOrdered - item.quantityGiven;
                        final ordStr = item.quantityOrdered % 1 == 0
                            ? item.quantityOrdered.toInt().toString()
                            : item.quantityOrdered.toString();
                        final gvnStr = item.quantityGiven % 1 == 0
                            ? item.quantityGiven.toInt().toString()
                            : item.quantityGiven.toString();
                        final pndStr = pending % 1 == 0
                            ? pending.toInt().toString()
                            : pending.toString();
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('• ',
                                  style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: Colors.red)),
                              Expanded(
                                child: Text(
                                  item.itemName,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 13),
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.red.shade50,
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(
                                      color: Colors.red.shade200),
                                ),
                                child: Text(
                                  'Given $gvnStr of $ordStr ($pndStr not given)',
                                  style: TextStyle(
                                      fontSize: 11,
                                      color: Colors.red.shade900,
                                      fontWeight: FontWeight.w700),
                                ),
                              ),
                            ],
                          ),
                        );
                      }),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Theme.of(context)
                        .colorScheme
                        .primaryContainer
                        .withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: Theme.of(context)
                            .colorScheme
                            .primary
                            .withValues(alpha: 0.3)),
                  ),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Delivered Items Value:'),
                          Text(
                            '₹ ${deliveredBreakdown.grandTotal.toStringAsFixed(2)}',
                            style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Colors.teal,
                                fontSize: 14),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Original Ordered Value:'),
                          Text(
                            '₹ ${fullBreakdown.grandTotal.toStringAsFixed(2)}',
                            style: TextStyle(
                                color: Colors.grey.shade700,
                                decoration: TextDecoration.lineThrough,
                                fontSize: 13),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'How would you like to close this order?',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, 'cancel'),
            child: const Text('CANCEL'),
          ),
          const SizedBox(height: 6),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              icon: const Icon(Icons.done_all, size: 18),
              label: Text(
                'Deliver All Remaining Items (₹${fullBreakdown.grandTotal.toStringAsFixed(2)}) & Close',
                textAlign: TextAlign.center,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              onPressed: () => Navigator.pop(context, 'all_given'),
            ),
          ),
          const SizedBox(height: 6),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF0F766E)),
              icon: const Icon(Icons.receipt_long, size: 18),
              label: Text(
                'Adjust Bill for Given Items (₹${deliveredBreakdown.grandTotal.toStringAsFixed(2)}) & Close',
                textAlign: TextAlign.center,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              onPressed: () => Navigator.pop(context, 'delivered_only'),
            ),
          ),
        ],
      ),
    );

    if (!mounted || choice == null || choice == 'cancel') return;

    if (choice == 'delivered_only') {
      await widget.orderRepository.closeOrderWithDeliveredItemsOnly(
        orderId: order.id!,
      );
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${order.formattedOrderId} closed. Bill adjusted to ₹${deliveredBreakdown.grandTotal.toStringAsFixed(2)} with partial items note.',
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
              '${order.formattedOrderId} - ${order.customerNameSnapshot}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            Text(
              DateFormat('dd MMM yyyy, hh:mm a').format(order.createdAt),
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.normal,
                  color: Colors.grey.shade600),
            ),
          ],
        ),
        actions: <Widget>[
          IconButton(
            tooltip: 'Share Order Summary',
            icon: const Icon(Icons.share),
            onPressed: () => ShareService.shareOrderDetails(_details!),
          ),
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
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
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
                  if (order.billBreakdown != null &&
                      (order.billBreakdown!.applyGst ||
                          order.billBreakdown!.otherCharges.isNotEmpty)) ...[
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
                  ],
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
            const SizedBox(height: 16),
            const Text(
              'ITEMS TO FULFILL',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: Colors.grey, letterSpacing: 0.5),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: ListView.builder(
                itemCount: _details!.items.length,
                itemBuilder: (context, index) {
                  final item = _details!.items[index];
                  final localStatus =
                      _statusFromQty(item.quantityOrdered, item.quantityGiven);
                  final options = item.options
                      .map((e) =>
                          '${s.catalog(e.optionName)}: ${s.catalog(e.optionValue)}')
                      .toList();
                  final pending = (item.quantityOrdered - item.quantityGiven)
                      .clamp(0, item.quantityOrdered);
                  final snapshot =
                      jsonDecode(item.productSnapshot) as Map<String, dynamic>;
                  final detailsText =
                      item.description ?? snapshot['description'] as String?;

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
                              _QtyBadge(label: 'Ordered', qty: item.quantityOrdered, unit: item.unit, color: Colors.blue),
                              const SizedBox(width: 8),
                              _QtyBadge(label: 'Given', qty: item.quantityGiven, unit: item.unit, color: Colors.teal),
                              const SizedBox(width: 8),
                              _QtyBadge(label: 'Pending', qty: pending.toDouble(), unit: item.unit, color: pending > 0 ? Colors.deepOrange : Colors.grey),
                            ],
                          ),
                          const SizedBox(height: 10),
                          // Price editing row
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  'Item Total: ₹${(item.unitPrice * item.quantityOrdered).toStringAsFixed(2)}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14,
                                      color: Colors.teal),
                                ),
                              ),
                              const SizedBox(width: 8),
                              SizedBox(
                                width: 120,
                                child: TextField(
                                  controller: TextEditingController(
                                    text: item.unitPrice > 0
                                        ? item.unitPrice.toStringAsFixed(2)
                                        : '',
                                  ),
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
                                ),
                              ),
                            ],
                          ),

                          const SizedBox(height: 12),
                          // Fulfillment Controls
                          Wrap(
                            alignment: WrapAlignment.spaceBetween,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              QuantitySelector(
                                value: item.quantityGiven,
                                min: 0,
                                max: item.quantityOrdered,
                                onChanged: (value) {
                                  setState(() {
                                    _details!.items[index] =
                                        item.copyWith(quantityGiven: value);
                                  });
                                },
                              ),
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  OutlinedButton(
                                    style: OutlinedButton.styleFrom(
                                      visualDensity: VisualDensity.compact,
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 10, vertical: 6),
                                    ),
                                    onPressed: () {
                                      setState(() {
                                        _details!.items[index] =
                                            item.copyWith(quantityGiven: 0);
                                      });
                                    },
                                    child: const Text('None',
                                        style: TextStyle(fontSize: 12)),
                                  ),
                                  const SizedBox(width: 6),
                                  FilledButton.tonal(
                                    style: FilledButton.styleFrom(
                                      visualDensity: VisualDensity.compact,
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 10, vertical: 6),
                                    ),
                                    onPressed: () {
                                      setState(() {
                                        _details!.items[index] = item.copyWith(
                                            quantityGiven:
                                                item.quantityOrdered);
                                      });
                                    },
                                    child: const Text('Give All',
                                        style: TextStyle(fontSize: 12)),
                                  ),
                                ],
                              ),
                            ],
                          ),
                          if (pending > 0)
                            Container(
                              margin: const EdgeInsets.only(top: 10),
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: Colors.red.shade50,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.warning_amber_rounded, size: 16, color: Colors.red.shade700),
                                  const SizedBox(width: 6),
                                  Text(
                                    '${pending % 1 == 0 ? pending.toInt() : pending} ${item.unit} needs procurement / to be given',
                                    style: TextStyle(color: Colors.red.shade700, fontWeight: FontWeight.w700, fontSize: 12),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            Row(
              children: [
                Expanded(
                  flex: 3,
                  child: LargeActionButton(
                    label: _saving ? s.t('saving') : 'SAVE CHANGES',
                    onTap: _saving ? null : _save,
                  ),
                ),
                if (order.status != OrderStatus.completed) ...[
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
            ),
          ],
        ),
      ),
    );
  }
}

class _QtyBadge extends StatelessWidget {
  const _QtyBadge({required this.label, required this.qty, required this.unit, required this.color});

  final String label;
  final double qty;
  final String unit;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final formattedQty = qty % 1 == 0 ? qty.toInt().toString() : qty.toString();
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Column(
          children: [
            Text(label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 10, color: color, fontWeight: FontWeight.w700)),
            const SizedBox(height: 2),
            Text('$formattedQty $unit',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 12, color: color, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }
}

