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
            Text('${order.formattedOrderId} - ${order.customerNameSnapshot}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            Text(DateFormat('dd MMM yyyy, hh:mm a').format(order.createdAt), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.normal)),
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
                  if (order.estimateTotal > 0) ...[
                    const SizedBox(height: 10),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Estimated Total:', style: TextStyle(fontWeight: FontWeight.w600)),
                        Text('₹ ${order.estimateTotal.toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.w900, color: Colors.teal, fontSize: 16)),
                      ],
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
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Item Total: ₹${(item.unitPrice * item.quantityOrdered).toStringAsFixed(2)}',
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.teal),
                              ),
                              SizedBox(
                                width: 130,
                                child: TextField(
                                  controller: TextEditingController(
                                    text: item.unitPrice > 0 ? item.unitPrice.toStringAsFixed(2) : '',
                                  ),
                                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                  decoration: const InputDecoration(
                                    isDense: true,
                                    labelText: 'Price/Unit ₹',
                                    prefixText: '₹ ',
                                  ),
                                  onChanged: (val) {
                                    final parsed = double.tryParse(val.trim()) ?? 0.0;
                                    setState(() {
                                      _details!.items[index] = item.copyWith(unitPrice: parsed);
                                    });
                                  },
                                ),
                              ),
                            ],
                          ),

                          const SizedBox(height: 12),
                          // Fulfillment Controls

                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
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
                                children: [
                                  OutlinedButton(
                                    style: OutlinedButton.styleFrom(
                                      visualDensity: VisualDensity.compact,
                                      padding: const EdgeInsets.symmetric(horizontal: 10),
                                    ),
                                    onPressed: () {
                                      setState(() {
                                        _details!.items[index] =
                                            item.copyWith(quantityGiven: 0);
                                      });
                                    },
                                    child: const Text('None'),
                                  ),
                                  const SizedBox(width: 6),
                                  FilledButton.tonal(
                                    style: FilledButton.styleFrom(
                                      visualDensity: VisualDensity.compact,
                                      padding: const EdgeInsets.symmetric(horizontal: 10),
                                    ),
                                    onPressed: () {
                                      setState(() {
                                        _details!.items[index] =
                                            item.copyWith(quantityGiven: item.quantityOrdered);
                                      });
                                    },
                                    child: const Text('Give All'),
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
            LargeActionButton(
              label: _saving ? s.t('saving') : 'SAVE CHANGES',
              onTap: _saving ? null : _save,
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
            Text(label, style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.w700)),
            const SizedBox(height: 2),
            Text('$formattedQty $unit', style: TextStyle(fontSize: 13, color: color, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }
}

