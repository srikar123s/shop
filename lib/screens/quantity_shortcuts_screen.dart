import 'package:flutter/material.dart';
import 'package:shop/models/product.dart';
import 'package:shop/repositories/product_repository.dart';
import 'package:shop/services/shop_customization_service.dart';

class QuantityShortcutsScreen extends StatefulWidget {
  const QuantityShortcutsScreen({
    super.key,
    required this.productRepository,
  });

  final ProductRepository productRepository;

  @override
  State<QuantityShortcutsScreen> createState() =>
      _QuantityShortcutsScreenState();
}

class _QuantityShortcutsScreenState extends State<QuantityShortcutsScreen> {
  final _customService = ShopCustomizationService.instance;
  List<Product> _allProducts = <Product>[];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadProducts();
    _customService.addListener(_onServiceUpdate);
  }

  @override
  void dispose() {
    _customService.removeListener(_onServiceUpdate);
    super.dispose();
  }

  void _onServiceUpdate() {
    if (mounted) setState(() {});
  }

  Future<void> _loadProducts() async {
    setState(() => _loading = true);
    final prods =
        await widget.productRepository.getAllProducts(includeInactive: false);
    if (mounted) {
      setState(() {
        _allProducts = prods;
        _loading = false;
      });
    }
  }

  Future<void> _editShortcutsDialog({
    required String title,
    required String subtitle,
    required List<double> currentShortcuts,
    required ValueChanged<List<double>> onSave,
  }) async {
    final chips = List<double>.from(currentShortcuts)..sort();
    final addController = TextEditingController();

    await showDialog<void>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return AlertDialog(
              title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(subtitle, style: TextStyle(fontSize: 13, color: Colors.grey.shade700)),
                    const SizedBox(height: 16),
                    const Text('Current Shortcuts:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                    const SizedBox(height: 8),
                    if (chips.isEmpty)
                      const Text('No shortcuts added yet.', style: TextStyle(color: Colors.red, fontSize: 13))
                    else
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: chips.map((val) {
                          final label = val % 1 == 0 ? val.toInt().toString() : val.toString();
                          return Chip(
                            label: Text('+$label', style: const TextStyle(fontWeight: FontWeight.bold)),
                            deleteIcon: const Icon(Icons.close, size: 16),
                            onDeleted: () {
                              setDialogState(() {
                                chips.remove(val);
                              });
                            },
                          );
                        }).toList(),
                      ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: addController,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            decoration: const InputDecoration(
                              labelText: 'Add shortcut number',
                              hintText: 'e.g. 6 or 10 or 25',
                              prefixText: '+',
                              isDense: true,
                              border: OutlineInputBorder(),
                            ),
                            onSubmitted: (v) {
                              final parsed = double.tryParse(v.trim());
                              if (parsed != null && parsed > 0 && !chips.contains(parsed)) {
                                setDialogState(() {
                                  chips.add(parsed);
                                  chips.sort();
                                  addController.clear();
                                });
                              }
                            },
                          ),
                        ),
                        const SizedBox(width: 8),
                        FilledButton(
                          style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xFF0F766E),
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                          ),
                          onPressed: () {
                            final parsed = double.tryParse(addController.text.trim());
                            if (parsed != null && parsed > 0 && !chips.contains(parsed)) {
                              setDialogState(() {
                                chips.add(parsed);
                                chips.sort();
                                addController.clear();
                              });
                            }
                          },
                          child: const Text('ADD'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    const Text('Quick add presets:', style: TextStyle(fontSize: 12, color: Colors.grey)),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 6,
                      children: [1.0, 2.0, 5.0, 6.0, 10.0, 12.0, 20.0, 25.0, 50.0, 100.0].map((preset) {
                        final pStr = preset % 1 == 0 ? preset.toInt().toString() : preset.toString();
                        return ActionChip(
                          label: Text('+$pStr', style: const TextStyle(fontSize: 11)),
                          visualDensity: VisualDensity.compact,
                          padding: EdgeInsets.zero,
                          onPressed: () {
                            if (!chips.contains(preset)) {
                              setDialogState(() {
                                chips.add(preset);
                                chips.sort();
                              });
                            }
                          },
                        );
                      }).toList(),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('CANCEL'),
                ),
                FilledButton(
                  style: FilledButton.styleFrom(backgroundColor: const Color(0xFF0F766E)),
                  onPressed: () {
                    if (chips.isNotEmpty) {
                      onSave(chips);
                      Navigator.pop(ctx);
                    }
                  },
                  child: const Text('SAVE SHORTCUTS'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _openCustomProductAssignmentDialog() async {
    final selectedProductIds = <int>{};
    final searchController = TextEditingController();

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            final query = searchController.text.trim().toLowerCase();
            final filtered = _allProducts.where((p) {
              if (query.isEmpty) return true;
              return p.name.toLowerCase().contains(query) ||
                  p.category.toLowerCase().contains(query);
            }).toList();

            final allSelected = filtered.isNotEmpty &&
                filtered.every((p) => p.id != null && selectedProductIds.contains(p.id!));

            return Container(
              height: MediaQuery.of(ctx).size.height * 0.85,
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Select Products for Custom Shortcuts',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.pop(ctx),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: searchController,
                    decoration: InputDecoration(
                      hintText: 'Search products by name or category...',
                      prefixIcon: const Icon(Icons.search),
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    onChanged: (_) => setModalState(() {}),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      TextButton.icon(
                        icon: Icon(
                          allSelected ? Icons.deselect : Icons.select_all,
                          size: 18,
                        ),
                        label: Text(allSelected ? 'Deselect All' : 'Select All (${filtered.length})'),
                        onPressed: () {
                          setModalState(() {
                            if (allSelected) {
                              for (final p in filtered) {
                                if (p.id != null) selectedProductIds.remove(p.id!);
                              }
                            } else {
                              for (final p in filtered) {
                                if (p.id != null) selectedProductIds.add(p.id!);
                              }
                            }
                          });
                        },
                      ),
                      Text(
                        '${selectedProductIds.length} selected',
                        style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF0F766E)),
                      ),
                    ],
                  ),
                  const Divider(height: 1),
                  Expanded(
                    child: filtered.isEmpty
                        ? const Center(child: Text('No matching products found.'))
                        : ListView.builder(
                            itemCount: filtered.length,
                            itemBuilder: (context, index) {
                              final p = filtered[index];
                              final isSelected = p.id != null && selectedProductIds.contains(p.id!);
                              final currentShortcuts =
                                  _customService.productShortcuts[p.id];
                              return CheckboxListTile(
                                dense: true,
                                value: isSelected,
                                title: Text(p.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                                subtitle: Text(
                                  '${p.category}${currentShortcuts != null ? ' • Custom: ${currentShortcuts.map((c) => "+${c % 1 == 0 ? c.toInt() : c}").join(" ")}' : ""}',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: currentShortcuts != null ? Colors.teal : Colors.grey.shade600,
                                  ),
                                ),
                                onChanged: (val) {
                                  setModalState(() {
                                    if (p.id != null) {
                                      if (val == true) {
                                        selectedProductIds.add(p.id!);
                                      } else {
                                        selectedProductIds.remove(p.id!);
                                      }
                                    }
                                  });
                                },
                              );
                            },
                          ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF0F766E),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      onPressed: selectedProductIds.isEmpty
                          ? null
                          : () {
                              final messenger = ScaffoldMessenger.of(context);
                              Navigator.pop(ctx);
                              _editShortcutsDialog(
                                title:
                                    'Set Shortcuts for ${selectedProductIds.length} Product(s)',
                                subtitle:
                                    'These shortcuts (+ chips) will appear when adding quantities for the selected products.',
                                currentShortcuts:
                                    _customService.globalShortcuts,
                                onSave: (newShortcuts) async {
                                  await _customService.setProductShortcuts(
                                    selectedProductIds.toList(),
                                    newShortcuts,
                                  );
                                  messenger.showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        'Custom shortcuts set for ${selectedProductIds.length} product(s)!',
                                      ),
                                      backgroundColor:
                                          const Color(0xFF0F766E),
                                    ),
                                  );
                                },
                              );
                            },
                      child: Text(
                        'CONTINUE WITH ${selectedProductIds.length} SELECTED',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final globalShortcuts = _customService.globalShortcuts;
    final productShortcuts = _customService.productShortcuts;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Quantity Step Shortcuts (+ chips)'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // Info Card
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0F766E).withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFF0F766E).withValues(alpha: 0.2)),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.touch_app_outlined, color: Color(0xFF0F766E), size: 24),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Speed Up Billing with One-Tap Chips',
                              style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 15,
                                  color: Color(0xFF0F172A)),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'When taking customer orders, tapping chips like +5, +6, +10 instantly adds that quantity. Customize the steps globally for all items or assign special shortcuts for specific products.',
                              style: TextStyle(fontSize: 12, color: Colors.grey.shade700, height: 1.4),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                // SECTION 1: GLOBAL SHORTCUTS
                Text(
                  '1. DEFAULT SHORTCUTS (FOR ALL PRODUCTS)',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: Colors.grey.shade700,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 8),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'These shortcut chips appear on all products unless overridden individually below:',
                          style: TextStyle(fontSize: 13),
                        ),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: globalShortcuts.map((val) {
                            final label = val % 1 == 0 ? val.toInt().toString() : val.toString();
                            return Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                              decoration: BoxDecoration(
                                color: Theme.of(context).colorScheme.primaryContainer,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                '+$label',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                  color: Theme.of(context).colorScheme.primary,
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                        const SizedBox(height: 16),
                        OutlinedButton.icon(
                          icon: const Icon(Icons.edit, size: 16),
                          label: const Text('Edit Default Shortcuts (+ chips)'),
                          onPressed: () {
                            final messenger = ScaffoldMessenger.of(context);
                            _editShortcutsDialog(
                              title: 'Default Shortcuts (All Products)',
                              subtitle: 'Choose which + buttons appear by default for all products.',
                              currentShortcuts: globalShortcuts,
                              onSave: (newShortcuts) async {
                                await _customService.setGlobalShortcuts(newShortcuts);
                                messenger.showSnackBar(
                                  const SnackBar(
                                    content: Text('Default shortcuts updated successfully!'),
                                    backgroundColor: Color(0xFF0F766E),
                                  ),
                                );
                              },
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),

                // SECTION 2: PER-PRODUCT SHORTCUTS
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '2. PER-PRODUCT CUSTOM SHORTCUTS',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: Colors.grey.shade700,
                        letterSpacing: 0.5,
                      ),
                    ),
                    TextButton.icon(
                      icon: const Icon(Icons.add, size: 16),
                      label: const Text('+ Set Custom', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                      onPressed: _openCustomProductAssignmentDialog,
                    ),
                  ],
                ),
                const SizedBox(height: 8),

                if (productShortcuts.isEmpty)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Center(
                        child: Column(
                          children: [
                            Icon(Icons.tune_outlined, color: Colors.grey.shade400, size: 36),
                            const SizedBox(height: 8),
                            const Text(
                              'No product-specific shortcuts configured yet.',
                              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'All products currently use the default shortcuts above. Tap "+ Set Custom" to select single, multiple, or all products.',
                              textAlign: TextAlign.center,
                              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                            ),
                          ],
                        ),
                      ),
                    ),
                  )
                else
                  ...productShortcuts.entries.map((entry) {
                    final productId = entry.key;
                    final shortcuts = entry.value;
                    final productMatch = _allProducts.where((p) => p.id == productId).toList();
                    final prodName = productMatch.isNotEmpty ? productMatch.first.name : 'Product #$productId';
                    final prodCategory = productMatch.isNotEmpty ? productMatch.first.category : '';

                    return Card(
                      margin: const EdgeInsets.only(bottom: 10),
                      child: ListTile(
                        title: Text(prodName, style: const TextStyle(fontWeight: FontWeight.bold)),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (prodCategory.isNotEmpty)
                              Text(prodCategory, style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                            const SizedBox(height: 6),
                            Wrap(
                              spacing: 6,
                              children: shortcuts.map((s) {
                                final label = s % 1 == 0 ? s.toInt().toString() : s.toString();
                                return Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: Colors.teal.shade50,
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(color: Colors.teal.shade200),
                                  ),
                                  child: Text('+$label',
                                      style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.teal.shade800)),
                                );
                              }).toList(),
                            ),
                          ],
                        ),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete_outline, color: Colors.red, size: 20),
                          tooltip: 'Remove custom shortcuts',
                          onPressed: () async {
                            await _customService.removeProductShortcuts([productId]);
                          },
                        ),
                      ),
                    );
                  }),
              ],
            ),
    );
  }
}
