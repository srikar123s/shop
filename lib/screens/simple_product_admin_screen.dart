import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:shop/models/product.dart';
import 'package:shop/repositories/product_repository.dart';
import 'package:shop/services/excel_product_service.dart';

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

  List<String> _generateCombinations(List<ProductStep> steps) {
    if (steps.isEmpty) return <String>[];
    List<List<String>> result = [<String>[]];
    for (final step in steps) {
      if (step.values.isEmpty) continue;
      final List<List<String>> temp = [];
      for (final prefix in result) {
        for (final val in step.values) {
          temp.add([...prefix, val]);
        }
      }
      result = temp;
    }
    return result
        .where((list) => list.isNotEmpty)
        .map((list) => list.join(' • '))
        .toList();
  }

  Future<void> _confirmDeleteProduct(Product product) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text('Delete "${product.name}"?'),
          content: const Text(
            'Are you sure you want to delete this product? This action cannot be undone.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('CANCEL'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Colors.red),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('DELETE'),
            ),
          ],
        );
      },
    );

    if (confirm == true && product.id != null) {
      await widget.productRepository.deleteProduct(product.id!);
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${product.name} deleted'),
            backgroundColor: Colors.red.shade700,
          ),
        );
      }
    }
  }

  Future<void> _confirmDeleteAllProducts() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Delete ALL Products?'),
          content: const Text(
            'Are you sure you want to delete ALL products from the database? This cannot be undone.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('CANCEL'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Colors.red),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('DELETE ALL'),
            ),
          ],
        );
      },
    );

    if (confirm == true) {
      await widget.productRepository.deleteAllProducts();
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('All products deleted.'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _showImportOptions() async {
    showModalBottomSheet<void>(
      context: context,
      builder: (context) {
        return SafeArea(
          child: Wrap(
            children: <Widget>[
              ListTile(
                leading: const Icon(Icons.file_upload_outlined, color: Colors.teal),
                title: const Text('Upload Excel / CSV File'),
                subtitle: const Text('Add products in bulk from .xlsx, .xls, or .csv'),
                onTap: () {
                  Navigator.pop(context);
                  _importProductsFile();
                },
              ),
              ListTile(
                leading: const Icon(Icons.download_outlined, color: Colors.blue),
                title: const Text('Download Sample Excel Template'),
                subtitle: const Text('Get a sample template file with correct columns'),
                onTap: () {
                  Navigator.pop(context);
                  ExcelProductService.shareSampleTemplate();
                },
              ),
              if (_products.isNotEmpty) ...[
                const Divider(),
                ListTile(
                  leading: const Icon(Icons.delete_sweep_outlined, color: Colors.red),
                  title: const Text('Delete All Products'),
                  subtitle: const Text('Clear all products from the catalog'),
                  onTap: () {
                    Navigator.pop(context);
                    _confirmDeleteAllProducts();
                  },
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Future<void> _importProductsFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['xlsx', 'xls', 'csv'],
      );
      if (result == null || result.files.isEmpty || result.files.first.path == null) {
        return;
      }

      final file = File(result.files.first.path!);
      final products = await ExcelProductService.parseProductsFromFile(file);

      if (!mounted) return;

      if (products.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No valid products found in the file. Please check column headers.'),
          ),
        );
        return;
      }

      // Show preview dialog
      final confirm = await showDialog<bool>(
        context: context,
        builder: (context) {
          return AlertDialog(
            title: Text('Import ${products.length} Products?'),
            content: SizedBox(
              width: double.maxFinite,
              height: 260,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Found ${products.length} products in file:',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: ListView.builder(
                      itemCount: products.length,
                      itemBuilder: (context, i) {
                        final p = products[i];
                        return ListTile(
                          dense: true,
                          leading: const Icon(Icons.inventory_2_outlined, size: 20),
                          title: Text(p.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                          subtitle: Text(
                            '${p.category} • Base ₹${p.configuration.basePrice} • ${p.configuration.steps.length} steps • ${p.configuration.variantPrices.length} prices',
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('CANCEL'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: Text('IMPORT ${products.length} PRODUCTS'),
              ),
            ],
          );
        },
      );

      if (confirm == true) {
        setState(() => _loading = true);
        for (final product in products) {
          await widget.productRepository.upsertProduct(product);
        }
        await _load();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Successfully imported ${products.length} products!'),
              backgroundColor: Colors.teal,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error importing file: $e')),
        );
      }
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

    // Normalize unit names to strip duplicates like "Pieces" vs "Piece"
    String? unit = product?.configuration.defaultUnit != null
        ? ExcelProductService.normalizeUnit(product!.configuration.defaultUnit!)
        : null;

    final selectedUnits = <String>{
      for (final u in product?.configuration.unitOptions ?? <String>[])
        ExcelProductService.normalizeUnit(u)
    }.where((u) => _units.contains(u)).toSet();

    final customConversions = <String, double>{};
    if (product != null) {
      product.configuration.unitConversions.forEach((k, v) {
        customConversions[ExcelProductService.normalizeUnit(k)] = v;
      });
    }

    final variantPrices = Map<String, double>.from(
      product?.configuration.variantPrices ?? <String, double>{},
    );

    for (final u in selectedUnits) {
      customConversions.putIfAbsent(u, () => _defaultConversion(u));
    }
    final steps = <ProductStep>[...?product?.configuration.steps];

    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) {
          final combinations = _generateCombinations(steps);

          return SafeArea(
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                  20, 8, 20, MediaQuery.of(context).viewInsets.bottom + 20),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(product == null ? 'Add Product' : 'Edit Product',
                            style: Theme.of(context).textTheme.headlineSmall),
                        if (product != null)
                          IconButton(
                            icon: const Icon(Icons.delete_forever, color: Colors.red),
                            tooltip: 'Delete Product',
                            onPressed: () {
                              Navigator.pop(context);
                              _confirmDeleteProduct(product);
                            },
                          ),
                      ],
                    ),
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
                      decoration: const InputDecoration(
                        labelText: 'Base Price (Optional)',
                        prefixText: '₹ ',
                        hintText: 'Default base rate if combination price not set',
                      ),
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
                                customConversions.putIfAbsent(
                                    value, () => _defaultConversion(value));
                                unit ??= value;
                              } else {
                                selectedUnits.remove(value);
                                if (unit == value) {
                                  unit = selectedUnits.isNotEmpty
                                      ? selectedUnits.first
                                      : null;
                                }
                              }
                            });
                          },
                        );
                      }).toList(),
                    ),
                    if (selectedUnits.isNotEmpty) ...<Widget>[
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
                                child: Text('1 $u =',
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w600)),
                              ),
                              Expanded(
                                flex: 3,
                                child: TextField(
                                  controller: factorCtrl,
                                  keyboardType:
                                      const TextInputType.numberWithOptions(
                                          decimal: true),
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
                    ],
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
                      if (combinations.isNotEmpty) ...<Widget>[
                        const SizedBox(height: 16),
                        const Text(
                          'Set Rate per Final Selected Combination (Optional Override):',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'Set price for the final item added to cart (e.g. UF • 4 inch • Steel):',
                          style: TextStyle(fontSize: 12, color: Colors.grey),
                        ),
                        const SizedBox(height: 8),
                        ...combinations.map((combo) {
                          double? initialVal = variantPrices[combo] ??
                              variantPrices[combo.toLowerCase()];
                          if (initialVal == null || initialVal <= 0) {
                            final comboSet = combo
                                .toLowerCase()
                                .split(RegExp(r'[\+\•\-\:]'))
                                .map((s) => s.trim())
                                .where((s) => s.isNotEmpty)
                                .toSet();
                            for (final entry in variantPrices.entries) {
                              final entrySet = entry.key
                                  .toLowerCase()
                                  .split(RegExp(r'[\+\•\-\:]'))
                                  .map((s) => s.trim())
                                  .where((s) => s.isNotEmpty)
                                  .toSet();
                              if (comboSet.isNotEmpty &&
                                  entrySet.length == comboSet.length &&
                                  entrySet.containsAll(comboSet) &&
                                  entry.value > 0) {
                                initialVal = entry.value;
                                break;
                              }
                            }
                          }

                          return Padding(
                            padding: const EdgeInsets.only(bottom: 6),
                            child: Row(
                              children: [
                                Expanded(
                                  flex: 3,
                                  child: Text(
                                    'Price for $combo:',
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w600, fontSize: 13),
                                  ),
                                ),
                                Expanded(
                                  flex: 2,
                                  child: TextField(
                                    controller: TextEditingController(
                                      text: initialVal != null && initialVal > 0
                                          ? initialVal.toString()
                                          : '',
                                    ),
                                    keyboardType:
                                        const TextInputType.numberWithOptions(
                                            decimal: true),
                                    decoration: const InputDecoration(
                                      isDense: true,
                                      prefixText: '₹ ',
                                      hintText: 'Default base price',
                                    ),
                                    onChanged: (v) {
                                      final p = double.tryParse(v);
                                      if (p != null && p > 0) {
                                        variantPrices[combo] = p;
                                      } else {
                                        variantPrices.remove(combo);
                                      }
                                    },
                                  ),
                                ),
                              ],
                            ),
                          );
                        }),
                      ],
                    ],
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        icon: const Icon(Icons.check),
                        label: const Text('SAVE PRODUCT'),
                        onPressed: () async {
                          final parsedPrice =
                              double.tryParse(price.text.trim()) ?? 0.0;
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
                                defaultUnit: unit ??
                                    (selectedUnits.isNotEmpty
                                        ? selectedUnits.first
                                        : 'Piece'),
                                unitOptions: selectedUnits.toList(),
                                basePrice: parsedPrice,
                                unitConversions: <String, double>{
                                  for (final selected in selectedUnits)
                                    selected: customConversions[selected] ??
                                        _defaultConversion(selected),
                                },
                                variantPrices: variantPrices),
                          ));
                          if (context.mounted) Navigator.pop(context, true);
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
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
      appBar: AppBar(
        title: const Text('Manage products'),
        actions: [
          IconButton(
            icon: const Icon(Icons.file_upload_outlined),
            tooltip: 'Import Excel / CSV',
            onPressed: _showImportOptions,
          ),
        ],
      ),
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          FloatingActionButton.extended(
            heroTag: 'import_excel_fab',
            onPressed: _showImportOptions,
            backgroundColor: Colors.teal.shade700,
            foregroundColor: Colors.white,
            icon: const Icon(Icons.file_upload_outlined),
            label: const Text('IMPORT EXCEL'),
          ),
          const SizedBox(height: 10),
          FloatingActionButton.extended(
            heroTag: 'add_product_fab',
            onPressed: () => _editProduct(),
            icon: const Icon(Icons.add),
            label: const Text('ADD PRODUCT'),
          ),
        ],
      ),
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
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 140),
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
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Switch(
                                value: product.isActive,
                                onChanged: (value) async {
                                  await widget.productRepository
                                      .setProductActive(product.id!, value);
                                  await _load();
                                }),
                            IconButton(
                              icon: const Icon(Icons.delete_outline, color: Colors.red),
                              tooltip: 'Delete Product',
                              onPressed: () => _confirmDeleteProduct(product),
                            ),
                          ],
                        ),
                        onTap: () => _editProduct(product: product),
                      ));
                    },
                  )),
      ]),
    );
  }
}
