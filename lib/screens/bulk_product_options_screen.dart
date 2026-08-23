import 'package:flutter/material.dart';
import 'package:shop/l10n/app_localizations.dart';
import 'package:shop/models/order.dart';
import 'package:shop/models/product.dart';
import 'package:shop/widgets/quantity_selector.dart';

/// A compact variant matrix used when one product has several sizes, types,
/// weights, or colours. It returns every non-zero row as an order item.
class BulkProductOptionsScreen extends StatefulWidget {
  const BulkProductOptionsScreen({
    super.key,
    required this.product,
  });

  final Product product;

  @override
  State<BulkProductOptionsScreen> createState() =>
      _BulkProductOptionsScreenState();
}

class _BulkLine {
  _BulkLine(this.variant);

  String variant;
  double quantity = 0;
}

class _BulkProductOptionsScreenState extends State<BulkProductOptionsScreen> {
  late final List<ProductStep> _steps;
  late final int _variantIndex;
  int? _groupIndex;
  final Map<String, String> _prefixSelections = <String, String>{};
  final Set<String> _selectedGroups = <String>{};
  final Map<String, List<_BulkLine>> _groupLines = <String, List<_BulkLine>>{};
  final Map<String, double> _variantQuantities = <String, double>{};

  @override
  void initState() {
    super.initState();
    _steps = widget.product.configuration.steps;
    _variantIndex = _steps.isEmpty ? -1 : _steps.length - 1;
    final group = _steps.indexWhere(
      (step) =>
          step.key.toLowerCase() == 'colour' ||
          step.key.toLowerCase() == 'color' ||
          step.label.toLowerCase().contains('colour') ||
          step.label.toLowerCase().contains('color'),
    );
    if (group >= 0 && group != _variantIndex) _groupIndex = group;
  }

  List<ProductStep> get _prefixSteps => _steps
      .asMap()
      .entries
      .where((entry) => entry.key != _variantIndex && entry.key != _groupIndex)
      .map((entry) => entry.value)
      .toList();

  String get _variantLabel =>
      _steps.isEmpty ? 'variant' : _steps[_variantIndex].label;

  void _toggleGroup(String value) {
    setState(() {
      if (_selectedGroups.contains(value)) {
        _selectedGroups.remove(value);
        _groupLines.remove(value);
      } else {
        _selectedGroups.add(value);
        _groupLines[value] = <_BulkLine>[
          _BulkLine(_steps[_variantIndex].values.first),
        ];
      }
    });
  }

  bool get _canAdd {
    if (_groupIndex != null && _selectedGroups.isEmpty) return false;
    return _prefixSteps
        .every((step) => _prefixSelections.containsKey(step.key));
  }

  List<DraftOrderItem> _buildItems() {
    final unit = widget.product.configuration.defaultUnit ??
        (widget.product.configuration.unitOptions.isEmpty
            ? 'Unit'
            : widget.product.configuration.unitOptions.first);
    final items = <DraftOrderItem>[];
    if (_groupIndex != null) {
      for (final group in _selectedGroups) {
        for (final line in _groupLines[group] ?? <_BulkLine>[]) {
          if (line.quantity <= 0) continue;
          final options = <String, String>{
            ..._prefixSelections,
            _steps[_groupIndex!].key: group,
            _steps[_variantIndex].key: line.variant,
          };
          items.add(DraftOrderItem(
            productId: widget.product.id,
            itemName: widget.product.name,
            options: options,
            quantity: line.quantity,
            unit: unit,
          ));
        }
      }
    } else {
      for (final variant
          in _steps.isEmpty ? <String>[''] : _steps[_variantIndex].values) {
        final quantity = _variantQuantities[variant] ?? 0;
        if (quantity <= 0) continue;
        final options = <String, String>{..._prefixSelections};
        if (_steps.isNotEmpty) options[_steps[_variantIndex].key] = variant;
        items.add(DraftOrderItem(
          productId: widget.product.id,
          itemName: widget.product.name,
          options: options,
          quantity: quantity,
          unit: unit,
        ));
      }
    }
    return items;
  }

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context);
    final variantValues =
        _steps.isEmpty ? <String>[] : _steps[_variantIndex].values;
    return Scaffold(
      appBar: AppBar(title: Text(s.catalog(widget.product.name))),
      body: Column(
        children: <Widget>[
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              children: <Widget>[
                Text(
                  s.catalog(widget.product.name),
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 12),
                ..._prefixSteps.map(
                  (step) => Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: DropdownButtonFormField<String>(
                      initialValue: _prefixSelections[step.key],
                      decoration:
                          InputDecoration(labelText: s.catalog(step.label)),
                      items: step.values
                          .map((value) => DropdownMenuItem<String>(
                                value: value,
                                child: Text(s.catalog(value)),
                              ))
                          .toList(),
                      onChanged: (value) {
                        if (value != null) {
                          setState(() => _prefixSelections[step.key] = value);
                        }
                      },
                    ),
                  ),
                ),
                if (_groupIndex != null) ...<Widget>[
                  Text(
                    s.catalog(_steps[_groupIndex!].label),
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _steps[_groupIndex!]
                        .values
                        .map((value) => FilterChip(
                              label: Text(s.catalog(value)),
                              selected: _selectedGroups.contains(value),
                              onSelected: (_) => _toggleGroup(value),
                            ))
                        .toList(),
                  ),
                  const SizedBox(height: 12),
                  ..._selectedGroups.map(
                    (group) => _buildGroupCard(group, variantValues, s),
                  ),
                ] else ...<Widget>[
                  Text(
                    _steps.isEmpty ? s.t('quantity') : s.catalog(_variantLabel),
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 6),
                  if (_steps.isEmpty)
                    _quantityRow('', s.t('quantity'), s)
                  else
                    ...variantValues.map(
                      (value) => _quantityRow(value, s.catalog(value), s),
                    ),
                ],
              ],
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _canAdd && _buildItems().isNotEmpty
                      ? () => Navigator.pop(context, _buildItems())
                      : null,
                  icon: const Icon(Icons.playlist_add),
                  label: Text(
                    '${s.t('addItem')} (${_buildItems().length})',
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _quantityRow(String key, String label, AppLocalizations s) {
    final quantity = _variantQuantities[key] ?? 0;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Row(
          children: <Widget>[
            Expanded(
                child: Text(label,
                    style: const TextStyle(fontWeight: FontWeight.w600))),
            SizedBox(
              width: 132,
              child: QuantitySelector(
                value: quantity,
                min: 0,
                onChanged: (value) =>
                    setState(() => _variantQuantities[key] = value),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGroupCard(
    String group,
    List<String> variants,
    AppLocalizations s,
  ) {
    final lines = _groupLines[group] ?? <_BulkLine>[];
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(s.catalog(group),
                style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            ...lines.asMap().entries.map(
                  (entry) => Row(
                    children: <Widget>[
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          initialValue: entry.value.variant,
                          isDense: true,
                          decoration: InputDecoration(
                              labelText: s.catalog(_variantLabel)),
                          items: variants
                              .map((value) => DropdownMenuItem<String>(
                                    value: value,
                                    child: Text(s.catalog(value)),
                                  ))
                              .toList(),
                          onChanged: (value) {
                            if (value != null) {
                              setState(() => entry.value.variant = value);
                            }
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      SizedBox(
                        width: 132,
                        child: QuantitySelector(
                          value: entry.value.quantity,
                          min: 0,
                          onChanged: (value) =>
                              setState(() => entry.value.quantity = value),
                        ),
                      ),
                    ],
                  ),
                ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () =>
                    setState(() => lines.add(_BulkLine(variants.first))),
                icon: const Icon(Icons.add, size: 18),
                label: Text(s.t('anotherVariant')),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
