import 'package:flutter/material.dart';
import 'package:shop/l10n/app_localizations.dart';
import 'package:shop/models/product.dart';
import 'package:shop/repositories/product_repository.dart';

class ProductAdminScreen extends StatefulWidget {
  const ProductAdminScreen({
    super.key,
    required this.productRepository,
  });

  final ProductRepository productRepository;

  @override
  State<ProductAdminScreen> createState() => _ProductAdminScreenState();
}

class _ProductAdminScreenState extends State<ProductAdminScreen> {
  List<Product> _products = <Product>[];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final products = await widget.productRepository.getAllProducts();
    setState(() {
      _products = products;
      _loading = false;
    });
  }

  Future<void> _openEditor({Product? product}) async {
    final s = AppLocalizations.of(context);
    final nameCtrl = TextEditingController(text: product?.name ?? '');
    final categoryCtrl = TextEditingController(text: product?.category ?? '');
    final defaultUnitCtrl = TextEditingController(
      text: product?.configuration.defaultUnit ?? '',
    );
    final unitOptionsCtrl = TextEditingController(
      text: product?.configuration.unitOptions.join(', ') ?? '',
    );
    final steps = <ProductStep>[...?product?.configuration.steps];

    final saved = await showDialog<bool>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text(
                product == null ? s.t('addProduct') : s.t('editProduct'),
              ),
              content: SizedBox(
                width: 420,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      TextField(
                        controller: nameCtrl,
                        decoration: InputDecoration(labelText: s.t('name')),
                      ),
                      TextField(
                        controller: categoryCtrl,
                        decoration: InputDecoration(labelText: s.t('category')),
                      ),
                      TextField(
                        controller: defaultUnitCtrl,
                        decoration: InputDecoration(
                          labelText: s.t('defaultUnit'),
                        ),
                      ),
                      TextField(
                        controller: unitOptionsCtrl,
                        decoration: InputDecoration(
                          labelText: s.t('unitOptionsCsv'),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        s.t('steps'),
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 6),
                      ...steps.asMap().entries.map((entry) {
                        final i = entry.key;
                        final step = entry.value;
                        return Card(
                          child: ListTile(
                            title: Text('${step.label} (${step.key})'),
                            subtitle: Text(step.values.join(', ')),
                            trailing: IconButton(
                              onPressed: () {
                                setDialogState(() => steps.removeAt(i));
                              },
                              icon: const Icon(Icons.delete_outline),
                            ),
                            onTap: () async {
                              final edited = await _stepDialog(initial: step);
                              if (edited != null) {
                                setDialogState(() => steps[i] = edited);
                              }
                            },
                          ),
                        );
                      }),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: OutlinedButton.icon(
                          onPressed: () async {
                            final step = await _stepDialog();
                            if (step != null) {
                              setDialogState(() => steps.add(step));
                            }
                          },
                          icon: const Icon(Icons.add),
                          label: Text(s.t('addStep')),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              actions: <Widget>[
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: Text(s.t('cancel')),
                ),
                FilledButton(
                  onPressed: () async {
                    if (nameCtrl.text.trim().isEmpty ||
                        categoryCtrl.text.trim().isEmpty ||
                        steps.isEmpty) {
                      return;
                    }

                    final units = unitOptionsCtrl.text
                        .split(',')
                        .map((e) => e.trim())
                        .where((e) => e.isNotEmpty)
                        .toList();
                    final defaultUnit = defaultUnitCtrl.text.trim();

                    final next = Product(
                      id: product?.id,
                      name: nameCtrl.text.trim(),
                      category: categoryCtrl.text.trim(),
                      isActive: product?.isActive ?? true,
                      configuration: ProductConfiguration(
                        steps: steps,
                        defaultUnit: defaultUnit.isEmpty ? null : defaultUnit,
                        unitOptions: units,
                      ),
                    );

                    await widget.productRepository.upsertProduct(next);
                    if (context.mounted) {
                      Navigator.pop(context, true);
                    }
                  },
                  child: Text(s.t('save')),
                ),
              ],
            );
          },
        );
      },
    );

    if (saved == true) {
      await _load();
    }
  }

  Future<ProductStep?> _stepDialog({ProductStep? initial}) async {
    final s = AppLocalizations.of(context);
    final keyCtrl = TextEditingController(text: initial?.key ?? '');
    final labelCtrl = TextEditingController(text: initial?.label ?? '');
    final valInputCtrl = TextEditingController();
    final values = <String>[...?initial?.values];

    return showDialog<ProductStep>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            void addVal() {
              final v = valInputCtrl.text.trim().replaceAll(',', '');
              if (v.isEmpty) return;
              setDialogState(() {
                if (!values.contains(v)) values.add(v);
                valInputCtrl.clear();
              });
            }

            return AlertDialog(
              title: Text(initial == null ? s.t('addStep') : s.t('edit')),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  TextField(
                    controller: keyCtrl,
                    decoration: InputDecoration(labelText: s.t('stepKey')),
                  ),
                  TextField(
                    controller: labelCtrl,
                    decoration: InputDecoration(labelText: s.t('stepLabel')),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: TextField(
                          controller: valInputCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Add Choice',
                            hintText: 'Type & press ADD',
                          ),
                          onSubmitted: (_) => addVal(),
                        ),
                      ),
                      const SizedBox(width: 8),
                      FilledButton(
                        onPressed: addVal,
                        child: const Text('ADD'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: values
                        .map(
                          (v) => Chip(
                            label: Text(v),
                            onDeleted: () => setDialogState(() => values.remove(v)),
                          ),
                        )
                        .toList(),
                  ),
                ],
              ),
              actions: <Widget>[
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(s.t('cancel')),
                ),
                FilledButton(
                  onPressed: values.isEmpty
                      ? null
                      : () {
                          final key = keyCtrl.text.trim();
                          final label = labelCtrl.text.trim();
                          if (key.isEmpty || label.isEmpty) {
                            return;
                          }
                          Navigator.pop(
                            context,
                            ProductStep(
                              key: key,
                              label: label,
                              type: 'select',
                              values: values,
                            ),
                          );
                        },
                  child: Text(s.t('save')),
                ),
              ],
            );
          },
        );
      },
    );
  }


  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(s.t('productAdmin'))),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openEditor(),
        icon: const Icon(Icons.add),
        label: Text(s.t('addProduct')),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: _products.length,
              itemBuilder: (context, index) {
                final product = _products[index];
                return Card(
                  child: ListTile(
                    title: Text(product.name),
                    subtitle: Text(
                      '${product.category} • ${product.configuration.steps.length} steps',
                    ),
                    trailing: Switch(
                      value: product.isActive,
                      onChanged: (value) async {
                        await widget.productRepository.setProductActive(
                          product.id!,
                          value,
                        );
                        await _load();
                      },
                    ),
                    onTap: () => _openEditor(product: product),
                  ),
                );
              },
            ),
    );
  }
}
