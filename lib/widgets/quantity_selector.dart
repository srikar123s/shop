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
    if (_controller.text != _format(clamped)) {
      _controller.text = _format(clamped);
    }
    widget.onChanged(clamped);
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        IconButton.filled(
          onPressed: widget.value <= widget.min
              ? null
              : () => _change(widget.value - 1),
          icon: const Icon(Icons.remove),
          iconSize: 20,
        ),
        const SizedBox(width: 4),
        SizedBox(
          width: 64,
          child: TextField(
            controller: _controller,
            textAlign: TextAlign.center,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
            onChanged: (text) {
              final parsed = double.tryParse(text);
              if (parsed != null) {
                final clamped = parsed.clamp(widget.min, widget.max ?? 9999).toDouble();
                widget.onChanged(clamped);
              }
            },
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
              contentPadding: EdgeInsets.symmetric(vertical: 8, horizontal: 4),
              border: OutlineInputBorder(),
            ),
          ),
        ),
        const SizedBox(width: 4),
        IconButton.filled(
          onPressed: widget.max != null && widget.value >= widget.max!
              ? null
              : () => _change(widget.value + 1),
          icon: const Icon(Icons.add),
          iconSize: 20,
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
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <int>[5, 6, 10, 12].map((preset) {
          return Padding(
            padding: const EdgeInsets.only(right: 6),
            child: ActionChip(
              label: Text(
                '$preset',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              backgroundColor: Theme.of(context).colorScheme.primaryContainer,
              labelStyle: TextStyle(
                color: Theme.of(context).colorScheme.onPrimaryContainer,
              ),
              visualDensity: VisualDensity.compact,
              onPressed: () => onSelected(preset.toDouble()),
            ),
          );
        }).toList(),
      ),
    );
  }
}
