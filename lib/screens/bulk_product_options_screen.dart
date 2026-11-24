import 'package:flutter/material.dart';
import 'package:shop/l10n/app_localizations.dart';
import 'package:shop/models/order.dart';
import 'package:shop/models/product.dart';
import 'package:shop/services/shop_customization_service.dart';
import 'package:shop/widgets/quantity_selector.dart';

/// A compact variant matrix used when one product has several sizes, types,
/// weights, or colours. It returns every non-zero row as an order item.
class BulkProductOptionsScreen extends StatefulWidget {
  const BulkProductOptionsScreen({
    super.key,
    required this.product,
    this.existingItems = const <DraftOrderItem>[],
  });

  final Product product;
  final List<DraftOrderItem> existingItems;

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
  final Map<String, double> _itemQuantities = <String, double>{};
  final Map<String, Map<String, String>> _itemOptions = <String, Map<String, String>>{};
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

    // Restore previously added items and quantities
    if (widget.existingItems.isNotEmpty) {
      for (final item in widget.existingItems) {
        if (item.unit.isNotEmpty) {
          _unit = item.unit;
        }
        final options = Map<String, String>.from(item.options);
        final key = _optionsToKey(options);
        _itemOptions[key] = options;
        _itemQuantities[key] = (_itemQuantities[key] ?? 0) + item.quantity;
        if (item.unitPrice != null && item.unitPrice! > 0) {
          _customPrices[key] = item.unitPrice!;
        }

        // Restore group selection if group is present
        if (_groupIndex != null) {
          final groupKey = _steps[_groupIndex!].key;
          final groupVal = options[groupKey] ??
              options.entries
                  .firstWhere(
                    (e) => _steps[_groupIndex!].values.contains(e.value),
                    orElse: () => const MapEntry('', ''),
                  )
                  .value;
          if (groupVal.isNotEmpty) {
            _selectedGroups.add(groupVal);
            if (_variantIndex >= 0) {
              final variantKey = _steps[_variantIndex].key;
              final variantVal = options[variantKey] ??
                  options.entries
                      .firstWhere(
                        (e) => _steps[_variantIndex].values.contains(e.value),
                        orElse: () => const MapEntry('', ''),
                      )
                      .value;
              if (variantVal.isNotEmpty) {
                _activeGroupVariant[groupVal] = variantVal;
              }
            }
          }
        }

        // Restore prefix options from existing item
        for (final step in _prefixSteps) {
          if (options.containsKey(step.key)) {
            _prefixSelections[step.key] = options[step.key]!;
          }
        }
      }
    }

    // Ensure all prefix steps have an initial side-by-side selection if available
    for (final step in _prefixSteps) {
      if (!_prefixSelections.containsKey(step.key) && step.values.isNotEmpty) {
        _prefixSelections[step.key] = step.values.first;
      }
    }
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
    if (_groupIndex != null && _selectedGroups.isEmpty && _itemQuantities.isEmpty) return false;
    return _prefixSteps
        .every((step) => _prefixSelections.containsKey(step.key));
  }

  String _optionsToKey(Map<String, String> options) {
    if (options.isEmpty) return '';
    final parts = <String>[];
    for (final step in _steps) {
      final val = options[step.key];
      if (val != null && val.isNotEmpty) {
        parts.add('${step.key}=$val');
      }
    }
    final sortedKeys = options.keys.toList()..sort();
    for (final k in sortedKeys) {
      if (!_steps.any((s) => s.key == k)) {
        parts.add('$k=${options[k]}');
      }
    }
    return parts.join('||');
  }

  Map<String, String> _buildCurrentOptions({
    String? group,
    String? variant,
  }) {
    final options = Map<String, String>.from(_prefixSelections);
    if (_groupIndex != null && group != null && group.isNotEmpty) {
      options[_steps[_groupIndex!].key] = group;
    }
    if (_variantIndex >= 0 && variant != null && variant.isNotEmpty) {
      options[_steps[_variantIndex].key] = variant;
    }
    return options;
  }

  void _setQuantity(String key, Map<String, String> options, double val) {
    setState(() {
      if (val <= 0) {
        _itemQuantities.remove(key);
        _itemOptions.remove(key);
      } else {
        _itemQuantities[key] = val;
        _itemOptions[key] = options;
      }
    });
  }

  double _getQuantityForStepValue(String stepKey, String stepValue) {
    double total = 0;
    for (final entry in _itemQuantities.entries) {
      if (entry.value > 0) {
        final options = _itemOptions[entry.key];
        if (options != null && options[stepKey] == stepValue) {
          total += entry.value;
        }
      }
    }
    return total;
  }

  String _buildCombinationKey(Map<String, String> options) {
    final parts = <String>[];
    for (final step in _steps) {
      final val = options[step.key];
      if (val != null && val.isNotEmpty) {
        parts.add(val);
      }
    }
    return parts.join(' • ');
  }

  double _getPriceForOptions(String key, Map<String, String> options) {
    if (_customPrices.containsKey(key)) {
      return _customPrices[key]!;
    }
    final comboKey = _buildCombinationKey(options);
    final factor = widget.product.configuration.unitConversions[_unit] ?? 1.0;
    final variantPrices = widget.product.configuration.variantPrices;

    // 1. Direct key match
    double? configuredPrice = variantPrices[comboKey] ??
        variantPrices[comboKey.toLowerCase()];

    // 2. Check variant step value
    if (configuredPrice == null || configuredPrice <= 0) {
      if (_variantIndex >= 0) {
        final variantVal = options[_steps[_variantIndex].key];
        if (variantVal != null && variantVal.isNotEmpty) {
          configuredPrice = variantPrices[variantVal] ??
              variantPrices[variantVal.toLowerCase()];
        }
      }
    }

    // 3. Check group step value
    if (configuredPrice == null || configuredPrice <= 0) {
      if (_groupIndex != null) {
        final groupVal = options[_steps[_groupIndex!].key];
        if (groupVal != null && groupVal.isNotEmpty) {
          configuredPrice = variantPrices[groupVal] ??
              variantPrices[groupVal.toLowerCase()];
        }
      }
    }

    // 4. Case-insensitive & set-based match across option values
    if (configuredPrice == null || configuredPrice <= 0) {
      final lowerCombo = comboKey.toLowerCase().trim();
      final comboPartsSet = lowerCombo
          .split(RegExp(r'[\+\•\-\:]'))
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toSet();

      for (final entry in variantPrices.entries) {
        final keyLower = entry.key.toLowerCase().trim();
        if (keyLower == lowerCombo && entry.value > 0) {
          configuredPrice = entry.value;
          break;
        }

        final entrySet = keyLower
            .split(RegExp(r'[\+\•\-\:]'))
            .map((s) => s.trim())
            .where((s) => s.isNotEmpty)
            .toSet();

        if (comboPartsSet.isNotEmpty &&
            entrySet.length == comboPartsSet.length &&
            entrySet.containsAll(comboPartsSet) &&
            entry.value > 0) {
          configuredPrice = entry.value;
          break;
        }
      }
    }

    if (configuredPrice != null && configuredPrice > 0) {
      return configuredPrice * factor;
    }

    final basePrice = widget.product.configuration.basePrice;

    // Auto multiplier for known weight/size variations if basePrice > 0
    double multiplier = 1.0;
    final variantVal = _variantIndex >= 0 ? (options[_steps[_variantIndex].key] ?? '') : '';
    final lower = variantVal.toLowerCase().trim();
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

    for (final entry in _itemQuantities.entries) {
      final quantity = entry.value;
      if (quantity <= 0) continue;
      final key = entry.key;
      final options = _itemOptions[key] ?? <String, String>{};
      final unitPrice = _getPriceForOptions(key, options);

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
    return items;
  }

  Widget _compactPresets(Function(double) onSelected) {
    final shortcuts = ShopCustomizationService.instance
        .getShortcutsForProduct(widget.product.id);
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: shortcuts.map((v) {
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
                if (widget.product.configuration.unitOptions.isNotEmpty) ...[
                  const Text(
                    'Unit',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                      color: Color(0xFF1E293B),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: widget.product.configuration.unitOptions.map((value) {
                      final isSelected = _unit == value;
                      return ChoiceChip(
                        label: Text(value),
                        selected: isSelected,
                        selectedColor: const Color(0xFF0F766E),
                        backgroundColor: Colors.grey.shade100,
                        labelStyle: TextStyle(
                          color: isSelected ? Colors.white : const Color(0xFF334155),
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                          fontSize: 13,
                        ),
                        side: BorderSide(
                          color: isSelected ? const Color(0xFF0F766E) : Colors.grey.shade300,
                        ),
                        onSelected: (selected) {
                          if (selected) setState(() => _unit = value);
                        },
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 14),
                ],
                ..._prefixSteps.map(
                  (step) => Padding(
                    padding: const EdgeInsets.only(bottom: 14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          s.catalog(step.label),
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                            color: Color(0xFF1E293B),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: step.values.map((value) {
                            final isSelected = _prefixSelections[step.key] == value;
                            final count = _getQuantityForStepValue(step.key, value);
                            return ChoiceChip(
                              label: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(s.catalog(value)),
                                  if (count > 0) ...[
                                    const SizedBox(width: 5),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: isSelected ? Colors.white : const Color(0xFF0F766E),
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      child: Text(
                                        count % 1 == 0 ? count.toInt().toString() : count.toString(),
                                        style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                          color: isSelected ? const Color(0xFF0F766E) : Colors.white,
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                              selected: isSelected,
                              selectedColor: const Color(0xFF0F766E),
                              backgroundColor: Colors.grey.shade100,
                              labelStyle: TextStyle(
                                color: isSelected ? Colors.white : const Color(0xFF334155),
                                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                                fontSize: 13,
                              ),
                              side: BorderSide(
                                color: isSelected ? const Color(0xFF0F766E) : Colors.grey.shade300,
                              ),
                              onSelected: (selected) {
                                if (selected) {
                                  setState(() => _prefixSelections[step.key] = value);
                                }
                              },
                            );
                          }).toList(),
                        ),
                      ],
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
                        .map((value) {
                          final count = _getQuantityForStepValue(_steps[_groupIndex!].key, value);
                          final isSelected = _selectedGroups.contains(value);
                          return FilterChip(
                            label: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(s.catalog(value)),
                                if (count > 0) ...[
                                  const SizedBox(width: 5),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: isSelected ? Colors.white : const Color(0xFF0F766E),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: Text(
                                      count % 1 == 0 ? count.toInt().toString() : count.toString(),
                                      style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                        color: isSelected ? const Color(0xFF0F766E) : Colors.white,
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                            selected: isSelected,
                            onSelected: (_) => _toggleGroup(value),
                          );
                        })
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
                  onPressed: _canAdd &&
                          (_buildItems().isNotEmpty ||
                              widget.existingItems.isNotEmpty)
                      ? () => Navigator.pop(context, _buildItems())
                      : null,
                  icon: Icon(widget.existingItems.isNotEmpty
                      ? Icons.check_circle_outline
                      : Icons.playlist_add),
                  label: Text(
                    widget.existingItems.isNotEmpty
                        ? (_buildItems().isEmpty
                            ? 'REMOVE FROM CART'
                            : 'UPDATE CART (${_buildItems().length} items)')
                        : '${s.t('addItem')} (${_buildItems().length})',
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _quantityRow(String variantValue, String label, AppLocalizations s) {
    final options = _buildCurrentOptions(variant: variantValue);
    final key = _optionsToKey(options);
    final quantity = _itemQuantities[key] ?? 0;
    final price = _getPriceForOptions(key, options);

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
                      Text(
                        label,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 15),
                      ),
                      if (price > 0)
                        Text('₹${price.toStringAsFixed(2)} / $_unit',
                            style: TextStyle(color: Colors.teal.shade800, fontSize: 12, fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
                QuantitySelector(
                  value: quantity,
                  min: 0,
                  onChanged: (value) => _setQuantity(key, options, value),
                ),
              ],
            ),
            const SizedBox(height: 6),
            _compactPresets((val) {
              _setQuantity(key, options, quantity + val);
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
    final currentOptions = _buildCurrentOptions(group: group, variant: currentVariant);
    final currentKey = _optionsToKey(currentOptions);
    final currentQty = _itemQuantities[currentKey] ?? 0;
    final currentPrice = _getPriceForOptions(currentKey, currentOptions);

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
                  final vOptions = _buildCurrentOptions(group: group, variant: v);
                  final vKey = _optionsToKey(vOptions);
                  final qty = _itemQuantities[vKey] ?? 0;
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
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold, fontSize: 15),
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
                            _setQuantity(currentKey, currentOptions, val);
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    _compactPresets((val) {
                      _setQuantity(currentKey, currentOptions, currentQty + val);
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
