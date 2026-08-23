import 'package:flutter/material.dart';

class QuantitySelector extends StatelessWidget {
  const QuantitySelector({
    super.key,
    required this.value,
    required this.onChanged,
    this.min = 0,
    this.max,
  });

  final double value;
  final ValueChanged<double> onChanged;
  final double min;
  final double? max;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        IconButton.filled(
          onPressed: value <= min
              ? null
              : () => onChanged((value - 1).clamp(min, max ?? 9999)),
          icon: const Icon(Icons.remove),
          iconSize: 30,
        ),
        Expanded(
          child: Center(
            child: Text(
              value % 1 == 0 ? value.toInt().toString() : value.toString(),
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
            ),
          ),
        ),
        IconButton.filled(
          onPressed: max != null && value >= max!
              ? null
              : () => onChanged((value + 1).clamp(min, max ?? 9999)),
          icon: const Icon(Icons.add),
          iconSize: 30,
        ),
      ],
    );
  }
}
