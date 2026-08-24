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

class _BulkProductOptionsScreenState extends State<BulkProductOptionsScreen> {
  late final List<ProductStep> _steps;
  late final int _variantIndex;
  int? _groupIndex;
  final Map<String, String> _prefixSelections = <String, String>{};
  final Set<String> _selectedGroups = <String>{};
  final Map<String, double> _variantQuantities = <String, double>{};
  final Map<String, double> _customPrices = <String, double>{};
  final Map<String, String> _activeGroupVariant = <String, String>{};
  late String _unit;

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
    _unit = widget.product.configuration.defaultUnit ??
        (widget.product.configuration.unitOptions.isEmpty
            ? 'Unit'
            : widget.product.configuration.unitOptions.first);
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
      } else {
        _selectedGroups.add(value);
      }
    });
  }

  bool get _canAdd {
    if (_groupIndex != null && _selectedGroups.isEmpty) return false;
    return _prefixSteps
        .every((step) => _prefixSelections.containsKey(step.key));
  }

  double _getVariantPrice(String variantKey, String variantName) {
    if (_customPrices.containsKey(variantKey)) {
      return _customPrices[variantKey]!;
    }
    final configuredVariantPrice =
        widget.product.configuration.variantPrices[variantName] ??
        widget.product.configuration.variantPrices[variantKey];
    final factor = widget.product.configuration.unitConversions[_unit] ?? 1.0;
    if (configuredVariantPrice != null && configuredVariantPrice > 0) {
      return configuredVariantPrice * factor;
    }

    final basePrice = widget.product.configuration.basePrice;
    
    // Auto multiplier for known weight/size variations if basePrice > 0
    double multiplier = 1.0;
    final lower = variantName.toLowerCase().trim();
    if (lower == '4l' || lower == '4 l') {
      multiplier = 4.0;
    } else if (lower == '10l' || lower == '10 l') {
      multiplier = 10.0;
    } else if (lower == '20l' || lower == '20 l') {
      multiplier = 20.0;
    } else if (lower == '500g' || lower == '500 g') {
      multiplier = 5.0;
    } else if (lower == '1kg' || lower == '1 kg') {
      multiplier = 10.0;
    }

    return (basePrice > 0 ? basePrice * multiplier : 0) * factor;
  }


  List<DraftOrderItem> _buildItems() {
    final factor = widget.product.configuration.unitConversions[_unit] ?? 1;
    final items = <DraftOrderItem>[];
    if (_groupIndex != null) {
      for (final group in _selectedGroups) {
        final variants = _steps.isEmpty ? <String>[] : _steps[_variantIndex].values;
        for (final variant in variants) {
          final key = '$group::$variant';
          final quantity = _variantQuantities[key] ?? 0;
          if (quantity <= 0) continue;
          final options = <String, String>{
            ..._prefixSelections,
            _steps[_groupIndex!].key: group,
            _steps[_variantIndex].key: variant,
          };
          final unitPrice = _getVariantPrice(key, variant);
          items.add(DraftOrderItem(
            productId: widget.product.id,
            itemName: widget.product.name,
            options: options,
            quantity: quantity,
            unit: _unit,
            unitPrice: unitPrice > 0 ? unitPrice : null,
            unitFactor: factor,
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
        final unitPrice = _getVariantPrice(variant, variant);
        items.add(DraftOrderItem(
          productId: widget.product.id,
          itemName: widget.product.name,
          options: options,
          quantity: quantity,
          unit: _unit,
          unitPrice: unitPrice > 0 ? unitPrice : null,
          unitFactor: factor,
        ));
      }
    }
    return items;
  }

  Widget _compactPresets(Function(double) onSelected) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [5.0, 6.0, 10.0, 12.0].map((v) {
          final label = v % 1 == 0 ? v.toInt().toString() : v.toString();
          return Padding(
            padding: const EdgeInsets.only(right: 6),
            child: InkWell(
              onTap: () => onSelected(v),
              borderRadius: BorderRadius.circular(6),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '+$label',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
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
                if (widget.product.configuration.unitOptions.isNotEmpty)
                  DropdownButtonFormField<String>(
                    initialValue: _unit,
                    decoration: const InputDecoration(labelText: 'Unit'),
                    items: widget.product.configuration.unitOptions
                        .map((value) => DropdownMenuItem<String>(
                              value: value,
                              child: Text(value),
                            ))
                        .toList(),
                    onChanged: (value) {
                      if (value != null) setState(() => _unit = value);
                    },
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
    final price = _getVariantPrice(key, label);

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Column(
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(label, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                      if (price > 0)
                        Text('₹${price.toStringAsFixed(2)} / $_unit',
                            style: TextStyle(color: Colors.teal.shade800, fontSize: 12, fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
                QuantitySelector(
                  value: quantity,
                  min: 0,
                  onChanged: (value) =>
                      setState(() => _variantQuantities[key] = value),
                ),
              ],
            ),
            const SizedBox(height: 6),
            _compactPresets((val) {
              setState(() {
                _variantQuantities[key] = (_variantQuantities[key] ?? 0) + val;
              });
            }),
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
    final currentVariant = _activeGroupVariant[group] ?? (variants.isNotEmpty ? variants.first : '');
    final currentKey = '$group::$currentVariant';
    final currentQty = _variantQuantities[currentKey] ?? 0;
    final currentPrice = _getVariantPrice(currentKey, currentVariant);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 1.5,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              '${s.catalog(group)} Variants',
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
            ),
            const SizedBox(height: 8),
            // Horizontal row of weight/size chips for this colour
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: variants.map((v) {
                  final key = '$group::$v';
                  final qty = _variantQuantities[key] ?? 0;
                  final isSelected = v == currentVariant;

                  return Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: ChoiceChip(
                      label: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(s.catalog(v)),
                          if (qty > 0) ...[
                            const SizedBox(width: 4),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: isSelected ? Colors.white : Theme.of(context).colorScheme.primary,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                qty % 1 == 0 ? qty.toInt().toString() : qty.toString(),
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: isSelected ? Theme.of(context).colorScheme.primary : Colors.white,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      selected: isSelected,
                      onSelected: (selected) {
                        if (selected) {
                          setState(() {
                            _activeGroupVariant[group] = v;
                          });
                        }
                      },
                    ),
                  );
                }).toList(),
              ),
            ),
            const SizedBox(height: 12),
            // Active Weight Stepper & Details
            if (currentVariant.isNotEmpty)
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${s.catalog(group)} - ${s.catalog(currentVariant)}',
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                              ),
                              if (currentPrice > 0)
                                Text(
                                  '₹${currentPrice.toStringAsFixed(2)} / $_unit',
                                  style: TextStyle(color: Colors.teal.shade800, fontSize: 12, fontWeight: FontWeight.w600),
                                ),
                            ],
                          ),
                        ),
                        QuantitySelector(
                          value: currentQty,
                          min: 0,
                          onChanged: (val) {
                            setState(() {
                              _variantQuantities[currentKey] = val;
                            });
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    _compactPresets((val) {
                      setState(() {
                        _variantQuantities[currentKey] = (_variantQuantities[currentKey] ?? 0) + val;
                      });
                    }),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
