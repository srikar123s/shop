import 'package:flutter/material.dart';
import 'package:shop/l10n/app_localizations.dart';
import 'package:shop/models/order.dart';

class OrderItemCard extends StatelessWidget {
  const OrderItemCard({
    super.key,
    required this.item,
    this.onEdit,
    this.onDelete,
  });

  final DraftOrderItem item;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context);
    final optionText =
        item.options.entries.map((e) => '${e.key}: ${e.value}').join(' • ');

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              item.itemName,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
            if (optionText.isNotEmpty) const SizedBox(height: 6),
            if (optionText.isNotEmpty) Text(optionText),
            if ((item.description ?? '').isNotEmpty) ...<Widget>[
              const SizedBox(height: 4),
              Text(item.description!),
            ],
            const SizedBox(height: 6),
            Text(
              '${s.t('quantity')}: ${item.quantity.toInt()} ${item.unit}',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            if (item.isOtherItem)
              Padding(
                padding: EdgeInsets.only(top: 4),
                child: Text(
                  s.t('toProcure'),
                  style: TextStyle(
                    color: Colors.red,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            const SizedBox(height: 8),
            Row(
              children: <Widget>[
                OutlinedButton.icon(
                  onPressed: onEdit,
                  icon: const Icon(Icons.edit),
                  label: Text(s.t('edit')),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: onDelete,
                  icon: const Icon(Icons.delete_outline),
                  label: Text(s.t('delete')),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
