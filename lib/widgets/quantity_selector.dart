import 'package:flutter/material.dart';

class QuantitySelector extends StatefulWidget {
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
  State<QuantitySelector> createState() => _QuantitySelectorState();
}

class _QuantitySelectorState extends State<QuantitySelector> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: _format(widget.value));
  }

  String _format(double value) =>
      value % 1 == 0 ? value.toInt().toString() : value.toString();

  @override
  void didUpdateWidget(covariant QuantitySelector oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value &&
        _controller.text != _format(widget.value)) {
      _controller.text = _format(widget.value);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _change(double value) {
    final clamped = value.clamp(widget.min, widget.max ?? 9999).toDouble();
    _controller.text = _format(clamped);
    widget.onChanged(clamped);
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        IconButton.filled(
          onPressed: widget.value <= widget.min
              ? null
              : () => _change(widget.value - 1),
          icon: const Icon(Icons.remove),
          iconSize: 22,
        ),
        SizedBox(
          width: 58,
          child: TextField(
            controller: _controller,
            textAlign: TextAlign.center,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            style: const TextStyle(fontWeight: FontWeight.w700),
            onSubmitted: (text) {
              final parsed = double.tryParse(text);
              if (parsed != null) _change(parsed);
            },
            onTapOutside: (_) {
              final parsed = double.tryParse(_controller.text);
              if (parsed != null) _change(parsed);
            },
            decoration: const InputDecoration(
              isDense: true,
              contentPadding: EdgeInsets.symmetric(vertical: 8),
            ),
          ),
        ),
        IconButton.filled(
          onPressed: widget.max != null && widget.value >= widget.max!
              ? null
              : () => _change(widget.value + 1),
          icon: const Icon(Icons.add),
          iconSize: 22,
        ),
      ],
    );
  }
}

class QuantityPresets extends StatelessWidget {
  const QuantityPresets({super.key, required this.onSelected});

  final ValueChanged<double> onSelected;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 6,
      children: <int>[5, 6, 10, 12]
          .map((value) => ActionChip(
                label: Text('$value'),
                visualDensity: VisualDensity.compact,
                onPressed: () => onSelected(value.toDouble()),
              ))
          .toList(),
    );
  }
}
