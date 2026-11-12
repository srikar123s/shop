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

    List<String> getPresetsForStep(String key) {
      final k = key.toLowerCase();
      if (k.contains('weight') || k.contains('size')) {
        return const [
          '500ml',
          '1 Litre',
          '4 Litre',
          '10 Litre',
          '20 Litre',
          '100g',
          '250g',
          '500g',
          '1 kg',
          '5 kg'
        ];
      }
      if (k.contains('colour') || k.contains('color')) {
        return const [
          'White',
          'Black',
          'Red',
          'Blue',
          'Yellow',
          'Green',
          'Grey',
          'Brown',
          'Golden'
        ];
      }
      if (k.contains('brand')) {
        return const [
          'Asian Paints',
          'Berger',
          'Nerolac',
          'Dulux',
          'Pidilite',
          'Tata'
        ];
      }
      if (k.contains('type')) {
        return const [
          'Standard',
          'Premium',
          'Economy',
          'Matte',
          'Gloss',
          'Heavy Duty'
        ];
      }
      return const [];
    }

    final presets = getPresetsForStep(step.key);

    return showDialog<ProductStep>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          void addChoicesFromText(String raw) {
            final tokens = raw
                .split(RegExp(r'[,;\n]'))
                .map((s) => s.trim())
                .where((s) => s.isNotEmpty);
            if (tokens.isEmpty) return;
            setDialogState(() {
              for (final t in tokens) {
                if (!choices.contains(t)) {
                  choices.add(t);
                }
              }
              controller.clear();
            });
          }

          return AlertDialog(
            title: Text('Configure ${step.label}'),
            content: SizedBox(
              width: 380,
              child: SingleChildScrollView(
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
                              hintText: 'Type values (or comma separated, e.g. 1L, 4L, 10L)',
                            ),
                            onSubmitted: (val) => addChoicesFromText(val),
                          ),
                        ),
                        const SizedBox(width: 8),
                        FilledButton(
                          onPressed: () =>
                              addChoicesFromText(controller.text),
                          child: const Text('ADD'),
                        ),
                      ],
                    ),
                    if (presets.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      const Text(
                        'Quick presets (tap to add):',
                        style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 11,
                            color: Colors.teal),
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: presets.map((preset) {
                          final added = choices.contains(preset);
                          return ActionChip(
                            label: Text(preset),
                            avatar: Icon(
                              added ? Icons.check : Icons.add,
                              size: 14,
                              color: added ? Colors.teal : Colors.grey.shade700,
                            ),
                            backgroundColor: added
                                ? Colors.teal.shade50
                                : Colors.grey.shade100,
                            onPressed: () {
                              setDialogState(() {
                                if (!choices.contains(preset)) {
                                  choices.add(preset);
                                }
                              });
                            },
                          );
                        }).toList(),
                      ),
                    ],
                    const SizedBox(height: 14),
                    Text(
                      'Added choices (${choices.length}):',
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 12),
                    ),
                    const SizedBox(height: 6),
                    if (choices.isEmpty)
                      const Text('No choices added yet.',
                          style: TextStyle(color: Colors.grey))
                    else
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: choices.asMap().entries.map(
                              (entry) => Chip(
                                label: Text(entry.value),
                                deleteIcon:
                                    const Icon(Icons.close, size: 16),
                                onDeleted: () => setDialogState(
                                  () => choices.removeAt(entry.key),
                                ),
                              ),
                            ).toList(),
                      ),
                  ],
                ),
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
    final categoryCtrl =
        TextEditingController(text: product?.category ?? 'General');
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

    // Determine default primary pricing key (e.g. Weight or Size if present, or first step)
    String? primaryPricingKey;
    for (final s in steps) {
      final k = s.key.toLowerCase();
      if (k.contains('weight') || k.contains('size')) {
        primaryPricingKey = s.key;
        break;
      }
    }
    primaryPricingKey ??= steps.isNotEmpty ? steps.first.key : null;

    String pricingMode = steps.isNotEmpty ? 'by_attribute' : 'base_only';

    // Map of attribute-level prices (e.g. '1 Litre': 350, '4 Litre': 1200)
    final attributePrices = <String, double>{};
    for (final s in steps) {
      for (final val in s.values) {
        if (variantPrices.containsKey(val) && variantPrices[val]! > 0) {
          attributePrices[val] = variantPrices[val]!;
        } else {
          for (final entry in variantPrices.entries) {
            if (entry.key.contains(val) && entry.value > 0) {
              attributePrices[val] = entry.value;
              break;
            }
          }
        }
      }
    }

    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) {
          final combinations = _generateCombinations(steps);
          if (primaryPricingKey == null && steps.isNotEmpty) {
            primaryPricingKey = steps.first.key;
          }

          ProductStep? currentPrimaryStep;
          if (steps.isNotEmpty) {
            currentPrimaryStep = steps.firstWhere(
              (s) => s.key == primaryPricingKey,
              orElse: () => steps.first,
            );
          }

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
                            icon: const Icon(Icons.delete_forever,
                                color: Colors.red),
                            tooltip: 'Delete Product',
                            onPressed: () {
                              Navigator.pop(context);
                              _confirmDeleteProduct(product);
                            },
                          ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // CARD 1: Basic Info & Units
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Row(
                            children: [
                              Icon(Icons.inventory_2_outlined,
                                  size: 20, color: Color(0xFF0F766E)),
                              SizedBox(width: 8),
                              Text('1. Basic Details & Units',
                                  style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 15)),
                            ],
                          ),
                          const SizedBox(height: 14),
                          TextField(
                            controller: name,
                            autofocus: product == null,
                            decoration: const InputDecoration(
                              labelText: 'Product Name *',
                              hintText: 'e.g. Asian Paints Royale / Welding Rod',
                            ),
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                flex: 3,
                                child: TextField(
                                  controller: categoryCtrl,
                                  decoration: const InputDecoration(
                                    labelText: 'Category',
                                    hintText: 'e.g. Paints, Hardware',
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                flex: 2,
                                child: TextField(
                                  controller: price,
                                  keyboardType:
                                      const TextInputType.numberWithOptions(
                                          decimal: true),
                                  decoration: const InputDecoration(
                                    labelText: 'Base Price',
                                    prefixText: '₹ ',
                                    hintText: 'Optional',
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: [
                              'Paints',
                              'Hardware',
                              'Tools',
                              'Electrical',
                              'Sanitary',
                              'General'
                            ].map((cat) {
                              final sel = categoryCtrl.text.trim() == cat;
                              return ChoiceChip(
                                label: Text(cat),
                                selected: sel,
                                onSelected: (val) {
                                  if (val) {
                                    setSheetState(
                                        () => categoryCtrl.text = cat);
                                  }
                                },
                              );
                            }).toList(),
                          ),
                          const SizedBox(height: 14),
                          const Text('Available Units:',
                              style: TextStyle(
                                  fontWeight: FontWeight.w700, fontSize: 13)),
                          const SizedBox(height: 6),
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: _units.map((value) {
                              return FilterChip(
                                label: Text(value),
                                selected: selectedUnits.contains(value),
                                onSelected: (selected) {
                                  setSheetState(() {
                                    if (selected) {
                                      selectedUnits.add(value);
                                      customConversions.putIfAbsent(value,
                                          () => _defaultConversion(value));
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
                            const SizedBox(height: 10),
                            ...selectedUnits.map((u) {
                              final factorCtrl = TextEditingController(
                                text: (customConversions[u] ??
                                        _defaultConversion(u))
                                    .toString(),
                              );
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 6),
                                child: Row(
                                  children: <Widget>[
                                    Expanded(
                                      flex: 2,
                                      child: Text('1 $u =',
                                          style: const TextStyle(
                                              fontWeight: FontWeight.w600,
                                              fontSize: 13)),
                                    ),
                                    Expanded(
                                      flex: 3,
                                      child: TextField(
                                        controller: factorCtrl,
                                        keyboardType: const TextInputType
                                            .numberWithOptions(decimal: true),
                                        decoration: const InputDecoration(
                                          isDense: true,
                                          suffixText: 'pcs/units',
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
                        ],
                      ),
                    ),

                    const SizedBox(height: 16),

                    // CARD 2: Options & Steps (Size/Weight, Colour, Brand...)
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Row(
                            children: [
                              Icon(Icons.tune,
                                  size: 20, color: Color(0xFF0F766E)),
                              SizedBox(width: 8),
                              Text('2. Options & Variants (Size, Colour...)',
                                  style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 15)),
                            ],
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'Select attributes for this product (e.g. Weight/Size, Colour):',
                            style: TextStyle(fontSize: 12, color: Colors.grey),
                          ),
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
                                      setSheetState(() {
                                        steps.removeWhere(
                                            (step) => step.key == entry.key);
                                        if (primaryPricingKey == entry.key) {
                                          primaryPricingKey = steps.isNotEmpty
                                              ? steps.first.key
                                              : null;
                                        }
                                      });
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
                          if (steps.isNotEmpty) ...[
                            const SizedBox(height: 12),
                            ...steps.asMap().entries.map((entry) => Card(
                                  elevation: 0,
                                  color: Colors.grey.shade50,
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(10),
                                      side: BorderSide(
                                          color: Colors.grey.shade300)),
                                  child: ListTile(
                                    dense: true,
                                    title: Text(entry.value.label,
                                        style: const TextStyle(
                                            fontWeight: FontWeight.bold)),
                                    subtitle: Text(
                                      entry.value.values.join(' • '),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    trailing: const Icon(Icons.edit_outlined,
                                        size: 18),
                                    onTap: () async {
                                      final step =
                                          await _editChoices(entry.value);
                                      if (step != null) {
                                        setSheetState(
                                            () => steps[entry.key] = step);
                                      }
                                    },
                                  ),
                                )),
                          ],
                        ],
                      ),
                    ),

                    const SizedBox(height: 16),

                    // CARD 3: Smart Pricing Setup (Addresses Paint/Color pricing!)
                    if (steps.isNotEmpty && combinations.isNotEmpty) ...[
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: const Color(0xFFE2E8F0)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(6),
                                  decoration: BoxDecoration(
                                    color: Colors.teal.shade50,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: const Icon(Icons.currency_rupee,
                                      size: 18, color: Color(0xFF0F766E)),
                                ),
                                const SizedBox(width: 8),
                                const Text(
                                  '3. Set Rates & Pricing',
                                  style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 15),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),

                            // Pricing Strategy Mode Selector
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                ChoiceChip(
                                  label: const Text(
                                      '🌟 Price by Attribute (e.g. Size/Weight)'),
                                  selected: pricingMode == 'by_attribute',
                                  onSelected: (sel) {
                                    if (sel) {
                                      setSheetState(
                                          () => pricingMode = 'by_attribute');
                                    }
                                  },
                                ),
                                ChoiceChip(
                                  label: const Text('🎨 Grouped Combinations'),
                                  selected: pricingMode == 'matrix',
                                  onSelected: (sel) {
                                    if (sel) {
                                      setSheetState(
                                          () => pricingMode = 'matrix');
                                    }
                                  },
                                ),
                                ChoiceChip(
                                  label: const Text('🏷️ Base Price Only'),
                                  selected: pricingMode == 'base_only',
                                  onSelected: (sel) {
                                    if (sel) {
                                      setSheetState(
                                          () => pricingMode = 'base_only');
                                    }
                                  },
                                ),
                              ],
                            ),

                            // MODE 1: Price by Attribute (e.g. Weight/Size)
                            if (pricingMode == 'by_attribute' &&
                                currentPrimaryStep != null) ...[
                              const SizedBox(height: 14),
                              Row(
                                children: [
                                  const Text(
                                    'Price determined by:',
                                    style: TextStyle(
                                        fontWeight: FontWeight.w600,
                                        fontSize: 13),
                                  ),
                                  const SizedBox(width: 10),
                                  DropdownButton<String>(
                                    value: steps.any((s) =>
                                            s.key == primaryPricingKey)
                                        ? primaryPricingKey
                                        : steps.first.key,
                                    items: steps
                                        .map((s) => DropdownMenuItem(
                                            value: s.key, child: Text(s.label)))
                                        .toList(),
                                    onChanged: (val) {
                                      if (val != null) {
                                        setSheetState(
                                            () => primaryPricingKey = val);
                                      }
                                    },
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: Colors.teal.shade50,
                                  borderRadius: BorderRadius.circular(10),
                                  border:
                                      Border.all(color: Colors.teal.shade200),
                                ),
                                child: Row(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    const Icon(Icons.auto_awesome,
                                        color: Colors.teal, size: 18),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        'Set rate once for each ${currentPrimaryStep.label}. All colours/other choices will share this same rate automatically!',
                                        style: TextStyle(
                                            fontSize: 12,
                                            color: Colors.teal.shade900,
                                            fontWeight: FontWeight.w600),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 14),
                              ...currentPrimaryStep.values.map((val) {
                                final curVal = attributePrices[val] ?? 0;
                                return Padding(
                                  padding: const EdgeInsets.only(bottom: 8),
                                  child: Row(
                                    children: [
                                      Expanded(
                                        flex: 3,
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              val,
                                              style: const TextStyle(
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 14),
                                            ),
                                            Text(
                                              'Applies to all colours for $val',
                                              style: TextStyle(
                                                  fontSize: 11,
                                                  color: Colors.grey.shade600),
                                            ),
                                          ],
                                        ),
                                      ),
                                      Expanded(
                                        flex: 2,
                                        child: TextField(
                                          controller: TextEditingController(
                                            text: curVal > 0
                                                ? (curVal % 1 == 0
                                                    ? curVal.toInt().toString()
                                                    : curVal.toString())
                                                : '',
                                          ),
                                          keyboardType: const TextInputType
                                              .numberWithOptions(
                                              decimal: true),
                                          decoration: InputDecoration(
                                            isDense: true,
                                            prefixText: '₹ ',
                                            hintText: 'Enter rate',
                                            border: OutlineInputBorder(
                                                borderRadius:
                                                    BorderRadius.circular(8)),
                                          ),
                                          onChanged: (v) {
                                            final p = double.tryParse(v);
                                            if (p != null && p > 0) {
                                              attributePrices[val] = p;
                                              variantPrices[val] = p;
                                              for (final combo
                                                  in combinations) {
                                                if (combo.contains(val)) {
                                                  variantPrices[combo] = p;
                                                }
                                              }
                                            } else {
                                              attributePrices.remove(val);
                                              variantPrices.remove(val);
                                              for (final combo
                                                  in combinations) {
                                                if (combo.contains(val)) {
                                                  variantPrices.remove(combo);
                                                }
                                              }
                                            }
                                          },
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              }),
                              const SizedBox(height: 8),
                              Theme(
                                data: Theme.of(context).copyWith(
                                    dividerColor: Colors.transparent),
                                child: ExpansionTile(
                                  tilePadding: EdgeInsets.zero,
                                  leading: const Icon(Icons.tune,
                                      size: 18, color: Colors.teal),
                                  title: const Text(
                                    'Special shade overrides (Optional)',
                                    style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.teal),
                                  ),
                                  children: [
                                    const Text(
                                      'If a specific shade has a different rate, you can override it below:',
                                      style: TextStyle(
                                          fontSize: 11, color: Colors.grey),
                                    ),
                                    const SizedBox(height: 8),
                                    ...combinations.map((combo) {
                                      final p = variantPrices[combo];
                                      return Padding(
                                        padding:
                                            const EdgeInsets.only(bottom: 6),
                                        child: Row(
                                          children: [
                                            Expanded(
                                              flex: 3,
                                              child: Text(combo,
                                                  style: const TextStyle(
                                                      fontSize: 12,
                                                      fontWeight:
                                                          FontWeight.w600)),
                                            ),
                                            Expanded(
                                              flex: 2,
                                              child: TextField(
                                                controller:
                                                    TextEditingController(
                                                  text: p != null && p > 0
                                                      ? (p % 1 == 0
                                                          ? p.toInt().toString()
                                                          : p.toString())
                                                      : '',
                                                ),
                                                keyboardType:
                                                    const TextInputType
                                                        .numberWithOptions(
                                                        decimal: true),
                                                decoration: InputDecoration(
                                                  isDense: true,
                                                  prefixText: '₹ ',
                                                  hintText: 'Rate',
                                                  border: OutlineInputBorder(
                                                      borderRadius:
                                                          BorderRadius
                                                              .circular(8)),
                                                ),
                                                onChanged: (v) {
                                                  final parsed =
                                                      double.tryParse(v);
                                                  if (parsed != null &&
                                                      parsed > 0) {
                                                    variantPrices[combo] =
                                                        parsed;
                                                  } else {
                                                    variantPrices
                                                        .remove(combo);
                                                  }
                                                },
                                              ),
                                            ),
                                          ],
                                        ),
                                      );
                                    }),
                                  ],
                                ),
                              ),
                            ]
                            // MODE 2: Grouped Combinations with Quick Fill
                            else if (pricingMode == 'matrix' &&
                                currentPrimaryStep != null) ...[
                              const SizedBox(height: 12),
                              const Text(
                                'Grouped by option. Use "APPLY ALL" to quickly set rates for all colours in that size:',
                                style:
                                    TextStyle(fontSize: 12, color: Colors.grey),
                              ),
                              const SizedBox(height: 10),
                              ...currentPrimaryStep.values.map((groupVal) {
                                final groupCombos = combinations
                                    .where((c) => c.contains(groupVal))
                                    .toList();
                                final quickFillCtrl =
                                    TextEditingController();
                                return Card(
                                  margin: const EdgeInsets.only(bottom: 12),
                                  elevation: 0,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    side:
                                        BorderSide(color: Colors.grey.shade300),
                                  ),
                                  child: Padding(
                                    padding: const EdgeInsets.all(12),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Expanded(
                                              child: Text(
                                                groupVal,
                                                style: const TextStyle(
                                                    fontWeight:
                                                        FontWeight.bold,
                                                    fontSize: 14),
                                              ),
                                            ),
                                            SizedBox(
                                              width: 80,
                                              child: TextField(
                                                controller: quickFillCtrl,
                                                keyboardType:
                                                    const TextInputType
                                                        .numberWithOptions(
                                                        decimal: true),
                                                decoration:
                                                    const InputDecoration(
                                                  isDense: true,
                                                  hintText: '₹ Rate',
                                                  contentPadding:
                                                      EdgeInsets.symmetric(
                                                          horizontal: 6,
                                                          vertical: 6),
                                                ),
                                              ),
                                            ),
                                            const SizedBox(width: 6),
                                            FilledButton.tonal(
                                              style: FilledButton.styleFrom(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                        horizontal: 8,
                                                        vertical: 6),
                                                visualDensity:
                                                    VisualDensity.compact,
                                              ),
                                              onPressed: () {
                                                final p = double.tryParse(
                                                    quickFillCtrl.text.trim());
                                                if (p != null && p > 0) {
                                                  setSheetState(() {
                                                    attributePrices[
                                                        groupVal] = p;
                                                    variantPrices[groupVal] =
                                                        p;
                                                    for (final c
                                                        in groupCombos) {
                                                      variantPrices[c] = p;
                                                    }
                                                  });
                                                }
                                              },
                                              child: const Text('APPLY ALL',
                                                  style: TextStyle(
                                                      fontSize: 10,
                                                      fontWeight:
                                                          FontWeight.bold)),
                                            ),
                                          ],
                                        ),
                                        const Divider(),
                                        ...groupCombos.map((combo) {
                                          final cur = variantPrices[combo] ??
                                              attributePrices[groupVal];
                                          return Padding(
                                            padding: const EdgeInsets.only(
                                                bottom: 4),
                                            child: Row(
                                              children: [
                                                Expanded(
                                                  flex: 3,
                                                  child: Text(combo,
                                                      style: const TextStyle(
                                                          fontSize: 12)),
                                                ),
                                                Expanded(
                                                  flex: 2,
                                                  child: TextField(
                                                    controller:
                                                        TextEditingController(
                                                      text: cur != null &&
                                                              cur > 0
                                                          ? (cur % 1 == 0
                                                              ? cur
                                                                  .toInt()
                                                                  .toString()
                                                              : cur.toString())
                                                          : '',
                                                    ),
                                                    keyboardType:
                                                        const TextInputType
                                                            .numberWithOptions(
                                                            decimal: true),
                                                    decoration:
                                                        const InputDecoration(
                                                      isDense: true,
                                                      prefixText: '₹ ',
                                                      hintText: 'Rate',
                                                    ),
                                                    onChanged: (v) {
                                                      final p =
                                                          double.tryParse(v);
                                                      if (p != null && p > 0) {
                                                        variantPrices[combo] =
                                                            p;
                                                      } else {
                                                        variantPrices
                                                            .remove(combo);
                                                      }
                                                    },
                                                  ),
                                                ),
                                              ],
                                            ),
                                          );
                                        }),
                                      ],
                                    ),
                                  ),
                                );
                              }),
                            ]
                            // MODE 3: Base Price Only
                            else ...[
                              const SizedBox(height: 12),
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: Colors.blue.shade50,
                                  borderRadius: BorderRadius.circular(10),
                                  border:
                                      Border.all(color: Colors.blue.shade200),
                                ),
                                child: Row(
                                  children: [
                                    Icon(Icons.info_outline,
                                        color: Colors.blue.shade800, size: 20),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        'All options will share the Base Price (₹ ${price.text.isNotEmpty ? price.text : "0"}) entered in Section 1.',
                                        style: TextStyle(
                                            fontSize: 12,
                                            color: Colors.blue.shade900),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
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

                          // Ensure all attribute-level prices are mirrored into combinations and attribute keys
                          if (pricingMode == 'by_attribute') {
                            for (final entry in attributePrices.entries) {
                              if (entry.value > 0) {
                                variantPrices[entry.key] = entry.value;
                                variantPrices[entry.key.toLowerCase()] =
                                    entry.value;
                                for (final combo in combinations) {
                                  if (combo.contains(entry.key) &&
                                      !variantPrices.containsKey(combo)) {
                                    variantPrices[combo] = entry.value;
                                    variantPrices[combo.toLowerCase()] =
                                        entry.value;
                                  }
                                }
                              }
                            }
                          }

                          await widget.productRepository.upsertProduct(Product(
                            id: product?.id,
                            name: name.text.trim(),
                            category: categoryCtrl.text.trim().isNotEmpty
                                ? categoryCtrl.text.trim()
                                : 'General',
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
                        title: Text(
                          product.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        subtitle: Text(
                          product.configuration.steps.isEmpty
                              ? 'Quantity only • ${product.configuration.defaultUnit}'
                              : '${product.configuration.steps.map((step) => step.label).join(' → ')} • ${product.configuration.defaultUnit}',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 12, color: Colors.grey.shade600),
                        ),
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
