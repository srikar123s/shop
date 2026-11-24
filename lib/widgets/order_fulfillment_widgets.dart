import 'package:flutter/material.dart';
import 'package:shop/widgets/quantity_selector.dart';

class QtyBadge extends StatelessWidget {
  const QtyBadge({
    super.key,
    required this.label,
    required this.qty,
    required this.unit,
    required this.color,
  });

  final String label;
  final double qty;
  final String unit;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final formattedQty = qty % 1 == 0 ? qty.toInt().toString() : qty.toString();
    return Container(
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
    );
  }
}

class DualFulfillmentWidget extends StatelessWidget {
  const DualFulfillmentWidget({
    super.key,
    required this.ordered,
    required this.given,
    required this.unit,
    required this.onChanged,
  });

  final double ordered;
  final double given;
  final String unit;
  final ValueChanged<double> onChanged;

  String _format(double v) => v % 1 == 0 ? v.toInt().toString() : v.toString();

  @override
  Widget build(BuildContext context) {
    final notGiven = (ordered - given).clamp(0.0, ordered);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // GIVEN Counter Card
              Expanded(
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: given == ordered
                          ? const Color(0xFF0F766E).withValues(alpha: 0.6)
                          : const Color(0xFFCBD5E1),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            given == ordered
                                ? Icons.check_circle_rounded
                                : Icons.check_circle_outline_rounded,
                            size: 14,
                            color: const Color(0xFF0F766E),
                          ),
                          const SizedBox(width: 4),
                          const Text(
                            'GIVEN',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF0F766E),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Center(
                        child: QuantitySelector(
                          value: given,
                          min: 0,
                          max: ordered,
                          onChanged: (val) => onChanged(val),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: Icon(
                  Icons.sync_alt_rounded,
                  size: 18,
                  color: Colors.grey.shade400,
                ),
              ),

              // NOT GIVEN (SHORT) Counter Card
              Expanded(
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                  decoration: BoxDecoration(
                    color:
                        notGiven > 0 ? const Color(0xFFFFF1F2) : Colors.white,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: notGiven > 0
                          ? const Color(0xFFFDA4AF)
                          : const Color(0xFFCBD5E1),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            notGiven > 0
                                ? Icons.warning_amber_rounded
                                : Icons.remove_circle_outline_rounded,
                            size: 14,
                            color: notGiven > 0
                                ? const Color(0xFFE11D48)
                                : Colors.grey.shade600,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            'NOT GIVEN (SHORT)',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: notGiven > 0
                                  ? const Color(0xFFE11D48)
                                  : Colors.grey.shade700,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Center(
                        child: QuantitySelector(
                          value: notGiven,
                          min: 0,
                          max: ordered,
                          onChanged: (newNotGiven) {
                            final newGiven =
                                (ordered - newNotGiven).clamp(0.0, ordered);
                            onChanged(newGiven);
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 10),

          // 1-Tap Quick Adjustment Chips
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                QuickChip(
                  label: 'All Given',
                  icon: Icons.done_all_rounded,
                  isSelected: given == ordered,
                  color: const Color(0xFF0F766E),
                  onTap: () => onChanged(ordered),
                ),
                if (ordered >= 1) ...[
                  const SizedBox(width: 6),
                  QuickChip(
                    label: '1 Short',
                    isSelected: notGiven == 1,
                    color: const Color(0xFFE11D48),
                    onTap: () => onChanged((ordered - 1).clamp(0.0, ordered)),
                  ),
                ],
                if (ordered >= 2) ...[
                  const SizedBox(width: 6),
                  QuickChip(
                    label: '2 Short',
                    isSelected: notGiven == 2,
                    color: const Color(0xFFE11D48),
                    onTap: () => onChanged((ordered - 2).clamp(0.0, ordered)),
                  ),
                ],
                if (ordered >= 5) ...[
                  const SizedBox(width: 6),
                  QuickChip(
                    label: '5 Short',
                    isSelected: notGiven == 5,
                    color: const Color(0xFFE11D48),
                    onTap: () => onChanged((ordered - 5).clamp(0.0, ordered)),
                  ),
                ],
                const SizedBox(width: 6),
                QuickChip(
                  label: 'None Given',
                  isSelected: given == 0,
                  color: Colors.grey.shade700,
                  onTap: () => onChanged(0),
                ),
              ],
            ),
          ),

          // Shortage Alert
          if (notGiven > 0) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFFFEE2E2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(Icons.info_outline_rounded,
                      size: 15, color: Color(0xFFDC2626)),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      '${_format(notGiven)} $unit out of stock (need to procure)',
                      style: const TextStyle(
                        color: Color(0xFF991B1B),
                        fontWeight: FontWeight.w600,
                        fontSize: 11,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class QuickChip extends StatelessWidget {
  const QuickChip({
    super.key,
    required this.label,
    this.icon,
    required this.isSelected,
    required this.color,
    required this.onTap,
  });

  final String label;
  final IconData? icon;
  final bool isSelected;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: isSelected ? color : Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isSelected ? color : const Color(0xFFCBD5E1),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 13, color: isSelected ? Colors.white : color),
                const SizedBox(width: 4),
              ],
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: isSelected ? Colors.white : Colors.grey.shade800,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
