import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shop/l10n/app_localizations.dart';
import 'package:shop/models/order.dart';
import 'package:shop/repositories/order_repository.dart';
import 'package:shop/repositories/customer_repository.dart';
import 'package:shop/repositories/product_repository.dart';
import 'package:shop/screens/product_selection_screen.dart';
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
        return Colors.green;
      case ItemStatus.partial:
        return Colors.orange;
      case ItemStatus.notGiven:
        return Colors.red;
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
      SnackBar(content: Text(AppLocalizations.of(context).t('changesSaved'))),
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

    return Scaffold(
      appBar: AppBar(
        title: Text(order.customerNameSnapshot),
        actions: <Widget>[
          IconButton(
            tooltip: 'Add products to this order',
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
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(DateFormat('dd MMM yyyy').format(order.createdAt)),
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
                      .join(' • ');
                  final pending = (item.quantityOrdered - item.quantityGiven)
                      .clamp(0, item.quantityOrdered);
                  final snapshot =
                      jsonDecode(item.productSnapshot) as Map<String, dynamic>;
                  final detailsText =
                      item.description ?? snapshot['description'] as String?;

                  return Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            item.itemName,
                            style: const TextStyle(
                                fontSize: 16, fontWeight: FontWeight.w700),
                          ),
                          if (options.isNotEmpty) Text(options),
                          if ((detailsText ?? '').isNotEmpty)
                            Text(detailsText!),
                          const SizedBox(height: 6),
                          Text(
                              '${s.t('ordered')}: ${item.quantityOrdered.toInt()} ${item.unit}'),
                          Text(
                              '${s.t('givenQty')}: ${item.quantityGiven.toInt()} ${item.unit}'),
                          Text(
                              '${s.t('pendingQty')}: ${pending.toInt()} ${item.unit}'),
                          const SizedBox(height: 8),
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
                            children: <Widget>[
                              OutlinedButton(
                                onPressed: () {
                                  setState(() {
                                    _details!.items[index] =
                                        item.copyWith(quantityGiven: 0);
                                  });
                                },
                                child: Text(s.t('notGiven')),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                itemStatusLabel(localStatus),
                                style: TextStyle(
                                  color: _itemStatusColor(localStatus),
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ],
                          ),
                          if (pending > 0)
                            Text(
                              s.t('toProcure'),
                              style: TextStyle(
                                  color: Colors.red,
                                  fontWeight: FontWeight.w700),
                            ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            LargeActionButton(
              label: _saving ? s.t('saving') : s.t('saveChanges'),
              onTap: _saving ? null : _save,
            ),
          ],
        ),
      ),
    );
  }
}
