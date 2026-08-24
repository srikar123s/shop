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

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context);
    final stepDone = _step >= _steps.length;
    final unitOptions = widget.product.configuration.unitOptions;
    final breadcrumb = <String>[
      s.catalog(widget.product.name),
      ..._selected.values.map(s.catalog)
    ];

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
              Text(
                s.t('quantity'),
                style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800),
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
                  final item = DraftOrderItem(
                    productId: widget.product.id,
                    itemName: widget.product.name,
                    options: _selected,
                    quantity: _quantity,
                    unit: _unit,
                    unitPrice: widget.product.configuration.basePrice *
                        (widget.product.configuration.unitConversions[_unit] ??
                            1),
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
