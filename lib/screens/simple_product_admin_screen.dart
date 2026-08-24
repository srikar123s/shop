import 'package:flutter/material.dart';
import 'package:shop/models/product.dart';
import 'package:shop/repositories/product_repository.dart';

class SimpleProductAdminScreen extends StatefulWidget {
  const SimpleProductAdminScreen({super.key, required this.productRepository});

  final ProductRepository productRepository;

  @override
  State<SimpleProductAdminScreen> createState() =>
      _SimpleProductAdminScreenState();
}

class _SimpleProductAdminScreenState extends State<SimpleProductAdminScreen> {
  static const Map<String, String> _questions = <String, String>{
    'brand': 'Brand',
    'colour': 'Colour',
    'size': 'Size',
    'type': 'Type',
    'weight': 'Weight',
    'model': 'Model',
  };
  static const List<String> _units = <String>[
    'Piece',
    'Box',
    'Kg',
    'Litre',
    'Packet',
    'Feet'
  ];
  final TextEditingController _search = TextEditingController();
  List<Product> _products = <Product>[];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final products = await widget.productRepository.getAllProducts();
    if (!mounted) return;
    setState(() {
      _products = products;
      _loading = false;
    });
  }

  double _defaultConversion(String unit) {
    switch (unit.toLowerCase()) {
      case 'packet':
        return 10;
      case 'box':
        return 100;
      default:
        return 1;
    }
  }

  Future<ProductStep?> _editChoices(ProductStep step) async {
    final controller = TextEditingController();
    final choices = <String>[...step.values];
    return showDialog<ProductStep>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          void addChoice() {
            final value = controller.text.trim().replaceAll(',', '');
            if (value.isEmpty) return;
            setDialogState(() {
              if (!choices.contains(value)) {
                choices.add(value);
              }
              controller.clear();
            });
          }

          return AlertDialog(
            title: Text('Configure ${step.label}'),
            content: SizedBox(
              width: 360,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: TextField(
                          controller: controller,
                          autofocus: true,
                          decoration: InputDecoration(
                            labelText: 'Add ${step.label}',
                            hintText: 'Type brand/choice & press ADD',
                          ),
                          onSubmitted: (_) => addChoice(),
                        ),
                      ),
                      const SizedBox(width: 8),
                      FilledButton(
                        onPressed: addChoice,
                        child: const Text('ADD'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  const Text('Added choices:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                  const SizedBox(height: 6),
                  if (choices.isEmpty)
                    const Text('No choices added yet.', style: TextStyle(color: Colors.grey))
                  else
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: choices.asMap().entries.map(
                            (entry) => Chip(
                              label: Text(entry.value),
                              deleteIcon: const Icon(Icons.close, size: 16),
                              onDeleted: () => setDialogState(
                                () => choices.removeAt(entry.key),
                              ),
                            ),
                          ).toList(),
                    ),
                ],
              ),
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('CANCEL'),
              ),
              FilledButton(
                onPressed: choices.isEmpty
                    ? null
                    : () =>
                        Navigator.pop(context, step.copyWith(values: choices)),
                child: const Text('SAVE CHOICES'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _editProduct({Product? product}) async {
    final name = TextEditingController(text: product?.name ?? '');
    final price = TextEditingController(
      text: product == null || product.configuration.basePrice == 0
          ? ''
          : product.configuration.basePrice.toString(),
    );
    var unit = product?.configuration.defaultUnit ?? 'Piece';
    final selectedUnits = <String>{
      ...(product?.configuration.unitOptions ?? <String>[]),
      unit,
    };
    final customConversions = Map<String, double>.from(
      product?.configuration.unitConversions ?? <String, double>{},
    );
    // ensure standard fallback for existing
    for (final u in selectedUnits) {
      customConversions.putIfAbsent(u, () => _defaultConversion(u));
    }
    final steps = <ProductStep>[...?product?.configuration.steps];
    String? priceError;

    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) => SafeArea(
          child: Padding(
            padding: EdgeInsets.fromLTRB(
                20, 8, 20, MediaQuery.of(context).viewInsets.bottom + 20),
            child: SingleChildScrollView(
              child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(product == null ? 'Add Product' : 'Edit Product',
                        style: Theme.of(context).textTheme.headlineSmall),
                    const SizedBox(height: 16),
                    TextField(
                        controller: name,
                        autofocus: product == null,
                        decoration: const InputDecoration(
                            labelText: 'Product Name *',
                            hintText: 'Example: Welding Rod')),
                    const SizedBox(height: 10),
                    TextField(
                      controller: price,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration: InputDecoration(
                        labelText: 'Base Price * (Mandatory)',
                        prefixText: '₹ ',
                        hintText: 'Example: 250',
                        errorText: priceError,
                      ),
                      onChanged: (_) {
                        if (priceError != null) {
                          setSheetState(() => priceError = null);
                        }
                      },
                    ),
                    const SizedBox(height: 20),
                    const Text('Unit & Conversions (pcs, packets, boxes):',
                        style: TextStyle(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: _units.map((value) {
                        return FilterChip(
                          label: Text(value),
                          selected: selectedUnits.contains(value),
                          onSelected: (selected) {
                            setSheetState(() {
                              if (selected) {
                                selectedUnits.add(value);
                                customConversions.putIfAbsent(value, () => _defaultConversion(value));
                              } else if (selectedUnits.length > 1) {
                                selectedUnits.remove(value);
                              }
                              if (!selectedUnits.contains(unit)) {
                                unit = selectedUnits.first;
                              }
                            });
                          },
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 12),
                    ...selectedUnits.map((u) {
                      final factorCtrl = TextEditingController(
                        text: (customConversions[u] ?? _defaultConversion(u))
                            .toString(),
                      );
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Row(
                          children: <Widget>[
                            Expanded(
                              flex: 2,
                              child: Text('1 $u =', style: const TextStyle(fontWeight: FontWeight.w600)),
                            ),
                            Expanded(
                              flex: 3,
                              child: TextField(
                                controller: factorCtrl,
                                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                decoration: const InputDecoration(
                                  isDense: true,
                                  suffixText: 'pcs/base units',
                                ),
                                onChanged: (val) {
                                  final numVal = double.tryParse(val);
                                  if (numVal != null && numVal > 0) {
                                    customConversions[u] = numVal;
                                  }
                                },
                              ),
                            ),
                          ],
                        ),
                      );
                    }),
                    const SizedBox(height: 20),
                    const Text('Product Configurations (Brand, Type, Choice):',
                        style: TextStyle(fontWeight: FontWeight.w700)),
                    const Text(
                        'Tap a configuration button to add choices using the ADD button.'),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: _questions.entries.map((entry) {
                        final selected =
                            steps.any((step) => step.key == entry.key);
                        return FilterChip(
                            label: Text(entry.value),
                            selected: selected,
                            onSelected: (isSelected) async {
                              if (!isSelected) {
                                setSheetState(() => steps.removeWhere(
                                    (step) => step.key == entry.key));
                                return;
                              }
                              final step = await _editChoices(ProductStep(
                                  key: entry.key,
                                  label: entry.value,
                                  type: 'select'));
                              if (step != null) {
                                setSheetState(() => steps.add(step));
                              }
                            });
                      }).toList(),
                    ),
                    if (steps.isNotEmpty) ...<Widget>[
                      const SizedBox(height: 14),
                      ...steps.asMap().entries.map((entry) => Card(
                              child: ListTile(
                            title: Text(entry.value.label),
                            subtitle: Text(entry.value.values.join(' • ')),
                            trailing: const Icon(Icons.edit_outlined),
                            onTap: () async {
                              final step = await _editChoices(entry.value);
                              if (step != null) {
                                setSheetState(() => steps[entry.key] = step);
                              }
                            },
                          ))),
                    ],
                    const SizedBox(height: 20),
                    SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          icon: const Icon(Icons.check),
                          label: const Text('SAVE PRODUCT'),
                          onPressed: () async {
                            final parsedPrice =
                                double.tryParse(price.text.trim());
                            if (parsedPrice == null || parsedPrice <= 0) {
                              setSheetState(() {
                                priceError = 'Base price is required and must be > 0';
                              });
                              return;
                            }
                            if (name.text.trim().isEmpty ||
                                steps.any((step) => step.values.isEmpty)) {
                              return;
                            }
                            await widget.productRepository
                                .upsertProduct(Product(
                              id: product?.id,
                              name: name.text.trim(),
                              category: product?.category ?? 'General',
                              isActive: product?.isActive ?? true,
                              configuration: ProductConfiguration(
                                  steps: steps,
                                  defaultUnit: unit,
                                  unitOptions: selectedUnits.toList(),
                                  basePrice: parsedPrice,
                                  unitConversions: <String, double>{
                                    for (final selected in selectedUnits)
                                      selected: customConversions[selected] ??
                                          _defaultConversion(selected),
                                  }),
                            ));
                            if (context.mounted) Navigator.pop(context, true);
                          },
                        )),
                  ]),
            ),
          ),
        ),
      ),
    );
    if (saved == true) _load();
  }


  @override
  Widget build(BuildContext context) {
    final filter = _search.text.trim().toLowerCase();
    final products = _products
        .where((product) =>
            filter.isEmpty || product.name.toLowerCase().contains(filter))
        .toList();
    return Scaffold(
      appBar: AppBar(title: const Text('Manage products')),
      floatingActionButton: FloatingActionButton.extended(
          onPressed: () => _editProduct(),
          icon: const Icon(Icons.add),
          label: const Text('ADD PRODUCT')),
      body: Column(children: <Widget>[
        Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: SearchBar(
                controller: _search,
                hintText: 'Search products',
                leading: const Icon(Icons.search),
                onChanged: (_) => setState(() {}))),
        Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
                    itemCount: products.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final product = products[index];
                      return Card(
                          child: ListTile(
                        title: Text(product.name),
                        subtitle: Text(product.configuration.steps.isEmpty
                            ? 'Quantity only • ${product.configuration.defaultUnit}'
                            : '${product.configuration.steps.map((step) => step.label).join(' → ')} • ${product.configuration.defaultUnit}'),
                        trailing: Switch(
                            value: product.isActive,
                            onChanged: (value) async {
                              await widget.productRepository
                                  .setProductActive(product.id!, value);
                              await _load();
                            }),
                        onTap: () => _editProduct(product: product),
                      ));
                    },
                  )),
      ]),
    );
  }
}
