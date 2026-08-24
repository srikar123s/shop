import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shop/l10n/app_localizations.dart';
import 'package:shop/app_keys.dart';
import 'package:shop/models/order.dart';
import 'package:shop/repositories/order_repository.dart';
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

  @override
  void initState() {
    super.initState();
    _estimateController = TextEditingController(
      text: _calculateEstimate().toStringAsFixed(2),
    );
  }

  double _calculateEstimate() => widget.draftOrder.items.fold<double>(
        0,
        (sum, item) => sum + (item.unitPrice ?? 0) * item.quantity,
      );

  @override
  void dispose() {
    _estimateController.dispose();
    super.dispose();
  }

  Future<void> _saveOrder() async {
    setState(() => _saving = true);
    final estimate = double.tryParse(_estimateController.text.trim()) ??
        _calculateEstimate();
    if (widget.existingOrderId == null) {
      await widget.orderRepository.createOrder(
        widget.draftOrder,
        estimateTotal: estimate,
      );
    } else {
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
    final s = AppLocalizations.of(context);
    Navigator.popUntil(context, (route) => route.isFirst);
    rootMessengerKey.currentState?.showSnackBar(
      SnackBar(content: Text(s.t('orderSaved'))),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(s.t('orderPreview'))),
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
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: ListView.builder(
                itemCount: widget.draftOrder.items.length,
                itemBuilder: (context, index) {
                  final item = widget.draftOrder.items[index];
                  return Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            '${index + 1}. ${item.itemName}',
                            style: const TextStyle(
                                fontSize: 16, fontWeight: FontWeight.w700),
                          ),
                          ...item.options.entries.map((e) => Text(
                              '${s.catalog(e.key)}: ${s.catalog(e.value)}')),
                          if ((item.description ?? '').isNotEmpty)
                            Text('${s.t('details')}: ${item.description}'),
                          Text(
                              '${s.t('quantity')}: ${item.quantity.toInt()} ${item.unit}'),
                          if (item.isOtherItem)
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
              label: s.t('edit'),
              onTap: () => Navigator.pop(context),
              backgroundColor: Colors.teal,
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
