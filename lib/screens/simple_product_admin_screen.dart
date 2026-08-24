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
        builder: (context, setDialogState) => AlertDialog(
          title: Text('${step.label} choices'),
          content: SizedBox(
            width: 360,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Expanded(
                      child: TextField(
                        controller: controller,
                        autofocus: true,
                        decoration: const InputDecoration(
                          labelText: 'New choice',
                          hintText: 'Brand A',
                        ),
                        onSubmitted: (_) {
                          final value = controller.text.trim();
                          if (value.isEmpty) return;
                          setDialogState(() {
                            choices.add(value);
                            controller.clear();
                          });
                        },
                      ),
                    ),
                    IconButton(
                      tooltip: 'Add choice',
                      onPressed: () {
                        final value = controller.text.trim();
                        if (value.isEmpty) return;
                        setDialogState(() {
                          choices.add(value);
                          controller.clear();
                        });
                      },
                      icon: const Icon(Icons.add_circle),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                ...choices.asMap().entries.map(
                      (entry) => ListTile(
                        dense: true,
                        title: Text(entry.value),
                        trailing: IconButton(
                          icon: const Icon(Icons.close, size: 18),
                          onPressed: () => setDialogState(
                            () => choices.removeAt(entry.key),
                          ),
                        ),
                      ),
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
              child: const Text('SAVE'),
            ),
          ],
        ),
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
    final steps = <ProductStep>[...?product?.configuration.steps];
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
                    Text(product == null ? 'Add product' : 'Edit product',
                        style: Theme.of(context).textTheme.headlineSmall),
                    const SizedBox(height: 16),
                    TextField(
                        controller: name,
                        autofocus: product == null,
                        decoration: const InputDecoration(
                            labelText: 'Product name',
                            hintText: 'Example: Welding Rod')),
                    const SizedBox(height: 10),
                    TextField(
                      controller: price,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(
                        labelText: 'Base price *',
                        prefixText: '₹ ',
                        hintText: 'Example: 250',
                      ),
                    ),
                    const SizedBox(height: 20),
                    const Text('How is it sold?',
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
                    const SizedBox(height: 20),
                    const Text('What should we ask the customer?',
                        style: TextStyle(fontWeight: FontWeight.w700)),
                    const Text(
                        'Optional — choose only what this product needs.'),
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
                            if (name.text.trim().isEmpty ||
                                parsedPrice == null ||
                                parsedPrice < 0 ||
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
                                      selected: _defaultConversion(selected),
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
