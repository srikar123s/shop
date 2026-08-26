import 'package:flutter/material.dart';
import 'package:shop/l10n/app_localizations.dart';
import 'package:shop/models/order.dart';
import 'package:shop/models/product.dart';
import 'package:shop/widgets/large_action_button.dart';
import 'package:shop/widgets/quantity_selector.dart';

class ProductOptionsScreen extends StatefulWidget {
  const ProductOptionsScreen({
    super.key,
    required this.product,
    this.initial,
  });

  final Product product;
  final DraftOrderItem? initial;

  @override
  State<ProductOptionsScreen> createState() => _ProductOptionsScreenState();
}

class _ProductOptionsScreenState extends State<ProductOptionsScreen> {
  late final Map<String, String> _selected;
  int _step = 0;
  double _quantity = 1;
  late String _unit;

  List<ProductStep> get _steps => widget.product.configuration.steps;

  @override
  void initState() {
    super.initState();
    _selected =
        Map<String, String>.from(widget.initial?.options ?? <String, String>{});
    _quantity = widget.initial?.quantity ?? 1;
    _unit = widget.initial?.unit ??
        widget.product.configuration.defaultUnit ??
        (widget.product.configuration.unitOptions.isNotEmpty
            ? widget.product.configuration.unitOptions.first
            : 'Unit');
  }

  void _nextStep(String value) {
    final step = _steps[_step];
    setState(() {
      _selected[step.key] = value;
      if (_step < _steps.length - 1) {
        _step += 1;
      } else {
        _step = _steps.length;
      }
    });
  }

  double _calculateUnitPrice() {
    final factor = widget.product.configuration.unitConversions[_unit] ?? 1.0;
    final comboKey = _selected.values.where((v) => v.isNotEmpty).join(' • ');
    final variantPrices = widget.product.configuration.variantPrices;

    if (comboKey.isNotEmpty &&
        variantPrices.containsKey(comboKey) &&
        variantPrices[comboKey]! > 0) {
      return variantPrices[comboKey]! * factor;
    }

    // Fallback to checking any option value key in variantPrices
    for (final val in _selected.values) {
      if (variantPrices.containsKey(val) && variantPrices[val]! > 0) {
        return variantPrices[val]! * factor;
      }
    }

    // Fallback to basePrice
    final basePrice = widget.product.configuration.basePrice;
    return basePrice > 0 ? basePrice * factor : 0.0;
  }

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context);
    final stepDone = _step >= _steps.length;
    final unitOptions = widget.product.configuration.unitOptions;
    final breadcrumb = <String>[
      s.catalog(widget.product.name),
      ..._selected.values.map(s.catalog)
    ];
    final calculatedUnitPrice = _calculateUnitPrice();

    return Scaffold(
      appBar: AppBar(title: Text(s.catalog(widget.product.name))),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              breadcrumb.join(' → '),
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            if (!stepDone) ...<Widget>[
              Text(
                s.catalog(_steps[_step].label),
                style:
                    const TextStyle(fontSize: 19, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: GridView.builder(
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    crossAxisSpacing: 10,
                    mainAxisSpacing: 10,
                    childAspectRatio: 2,
                  ),
                  itemCount: _steps[_step].values.length,
                  itemBuilder: (context, i) {
                    final value = _steps[_step].values[i];
                    return FilledButton.tonal(
                      onPressed: () => _nextStep(value),
                      child: Text(s.catalog(value),
                          style: const TextStyle(fontSize: 16)),
                    );
                  },
                ),
              ),
            ] else ...<Widget>[
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    s.t('quantity'),
                    style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800),
                  ),
                  if (calculatedUnitPrice > 0)
                    Text(
                      '₹${calculatedUnitPrice.toStringAsFixed(2)} / $_unit',
                      style: TextStyle(
                          color: Colors.teal.shade800,
                          fontSize: 14,
                          fontWeight: FontWeight.bold),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              QuantitySelector(
                  value: _quantity,
                  onChanged: (v) => setState(() => _quantity = v),
                  min: 1),
              QuantityPresets(
                onSelected: (value) => setState(() => _quantity = value),
              ),
              const SizedBox(height: 16),
              if (unitOptions.isNotEmpty)
                DropdownButtonFormField<String>(
                  initialValue: _unit,
                  decoration: InputDecoration(labelText: s.t('unit')),
                  items: unitOptions
                      .map(
                        (e) => DropdownMenuItem<String>(
                          value: e,
                          child: Text(e),
                        ),
                      )
                      .toList(),
                  onChanged: (value) {
                    if (value != null) {
                      setState(() => _unit = value);
                    }
                  },
                ),
              const Spacer(),
              LargeActionButton(
                label: s.t('addItem'),
                onTap: () {
                  final unitPrice = _calculateUnitPrice();
                  final item = DraftOrderItem(
                    productId: widget.product.id,
                    itemName: widget.product.name,
                    options: _selected,
                    quantity: _quantity,
                    unit: _unit,
                    unitPrice: unitPrice > 0 ? unitPrice : null,
                    unitFactor:
                        widget.product.configuration.unitConversions[_unit] ??
                            1,
                  );
                  Navigator.pop(context, item);
                },
              ),
            ],
          ],
        ),
      ),
    );
  }
}
