import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shop/l10n/app_localizations.dart';

import 'package:shop/models/order.dart';
import 'package:shop/repositories/order_repository.dart';
import 'package:shop/services/draft_order_service.dart';
import 'package:shop/services/share_service.dart';
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
  late final TextEditingController _estimateController;
  late final List<TextEditingController> _priceControllers;

  @override
  void initState() {
    super.initState();
    _estimateController = TextEditingController(
      text: _calculateEstimate().toStringAsFixed(2),
    );
    _priceControllers = widget.draftOrder.items.map((item) {
      final p = item.unitPrice ?? 0;
      return TextEditingController(text: p > 0 ? p.toStringAsFixed(2) : '');
    }).toList();
  }

  double _calculateEstimate() => widget.draftOrder.items.fold<double>(
        0,
        (sum, item) => sum + (item.unitPrice ?? 0) * item.quantity,
      );

  void _recalculateEstimate() {
    _estimateController.text = _calculateEstimate().toStringAsFixed(2);
  }

  @override
  void dispose() {
    _estimateController.dispose();
    for (final controller in _priceControllers) {
      controller.dispose();
    }
    super.dispose();
  }


  Future<void> _saveOrder() async {
    setState(() => _saving = true);
    final estimate = double.tryParse(_estimateController.text.trim()) ??
        _calculateEstimate();
    int newOrderId = 0;
    if (widget.existingOrderId == null) {
      newOrderId = await widget.orderRepository.createOrder(
        widget.draftOrder,
        estimateTotal: estimate,
      );
      await DraftOrderService().clearDraft();
    } else {
      newOrderId = widget.existingOrderId!;
      await widget.orderRepository.addItemsToOrder(
        orderId: widget.existingOrderId!,
        items: widget.draftOrder.items,
        estimateTotalAddition: estimate,
      );
    }
    if (!mounted) {
      return;
    }
    setState(() => _saving = false);
    final orderIdFormatted = '#ORD-${newOrderId.toString().padLeft(4, '0')}';
    
    final draft = widget.draftOrder;

    // Immediately navigate back to Home Screen
    Navigator.popUntil(context, (route) => route.isFirst);

    // Trigger top notification after home screen finishes rendering
    WidgetsBinding.instance.addPostFrameCallback((_) {
      TopNotificationService.showTopNotification(
        message: 'Order $orderIdFormatted created successfully!',
        actionLabel: 'SHARE',
        onAction: () {
          ShareService.shareDraftEstimate(draft, totalOverride: estimate);
        },
      );
    });
  }




  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context);
    final currentEstimate = double.tryParse(_estimateController.text.trim()) ?? _calculateEstimate();

    return Scaffold(
      appBar: AppBar(
        title: Text(s.t('orderPreview')),
        actions: <Widget>[
          IconButton(
            tooltip: 'Share Estimate',
            icon: const Icon(Icons.share),
            onPressed: () => ShareService.shareDraftEstimate(
              widget.draftOrder,
              totalOverride: currentEstimate,
            ),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              '${s.t('customerLabel')}: ${widget.draftOrder.customer.name}',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
            Text(
                '${s.t('date')}: ${DateFormat('dd MMM yyyy, hh:mm a').format(DateTime.now())}'),
            const SizedBox(height: 10),
            TextField(
              controller: _estimateController,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Estimated total (editable)',
                prefixText: '₹ ',
                border: OutlineInputBorder(),
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: ListView.builder(
                itemCount: widget.draftOrder.items.length,
                itemBuilder: (context, index) {
                  final item = widget.draftOrder.items[index];
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
                                  style: const TextStyle(
                                      fontSize: 16, fontWeight: FontWeight.w700),
                                ),
                              ),
                              Text(
                                '₹ ${itemTotal.toStringAsFixed(2)}',
                                style: const TextStyle(
                                    fontWeight: FontWeight.w800, color: Colors.green),
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
                                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                  decoration: const InputDecoration(
                                    labelText: 'Price/Unit ₹',
                                    isDense: true,
                                    prefixText: '₹ ',
                                  ),
                                  onChanged: (val) {
                                    final parsed = double.tryParse(val.trim()) ?? 0.0;
                                    setState(() {
                                      widget.draftOrder.items[index] = item.copyWith(unitPrice: parsed);
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
                                s.t('toProcure'),
                                style: const TextStyle(
                                    color: Colors.red,
                                    fontWeight: FontWeight.w700),
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
                  child: OutlinedButton.icon(
                    onPressed: () => ShareService.shareDraftEstimate(
                      widget.draftOrder,
                      totalOverride: currentEstimate,
                    ),
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
