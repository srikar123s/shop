import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shop/l10n/app_localizations.dart';
import 'package:shop/models/customer.dart';
import 'package:shop/models/order.dart';
import 'package:shop/models/product.dart';
import 'package:shop/repositories/order_repository.dart';
import 'package:shop/repositories/product_repository.dart';
import 'package:shop/screens/order_preview_screen.dart';
import 'package:shop/screens/bulk_product_options_screen.dart';
import 'package:shop/screens/product_options_screen.dart';
import 'package:shop/services/draft_order_service.dart';
import 'package:shop/services/voice_search_service.dart';
import 'package:shop/widgets/large_action_button.dart';
import 'package:shop/widgets/order_item_card.dart';
import 'package:shop/widgets/product_card.dart';
import 'package:shop/widgets/quantity_selector.dart';

class ProductSelectionScreen extends StatefulWidget {
  const ProductSelectionScreen({
    super.key,
    required this.customer,
    required this.productRepository,
    required this.orderRepository,
    this.existingOrderId,
    this.initialItems,
  });

  final Customer customer;
  final ProductRepository productRepository;
  final OrderRepository orderRepository;
  final int? existingOrderId;
  final List<DraftOrderItem>? initialItems;

  @override
  State<ProductSelectionScreen> createState() => _ProductSelectionScreenState();
}

class _ProductSelectionScreenState extends State<ProductSelectionScreen> {
  final TextEditingController _searchController = TextEditingController();
  final DraftOrderService _draftService = DraftOrderService();
  List<Product> _products = <Product>[];
  List<Product> _frequentlyUsed = <Product>[];
  final List<DraftOrderItem> _items = <DraftOrderItem>[];
  bool _loading = true;
  Timer? _searchDebounce;
  DraftOrder? _savedDraft;

  @override
  void initState() {
    super.initState();
    if (widget.initialItems != null && widget.initialItems!.isNotEmpty) {
      _items.addAll(widget.initialItems!);
    }
    _loadProducts();
    if (widget.initialItems == null || widget.initialItems!.isEmpty) {
      _checkDraft();
    }
  }

  Future<void> _checkDraft() async {
    final draft = await _draftService.getDraft(customerId: widget.customer.id);
    if (draft != null && draft.items.isNotEmpty && mounted) {
      setState(() {
        _savedDraft = draft;
      });
    }
  }

  void _resumeDraft() {
    if (_savedDraft == null) return;
    setState(() {
      _items.clear();
      _items.addAll(_savedDraft!.items);
      _savedDraft = null;
    });
    _saveCurrentDraft();
  }

  Future<void> _clearDraft() async {
    await _draftService.clearDraft(customerId: widget.customer.id);
    if (!mounted) return;
    setState(() {
      _items.clear();
      _savedDraft = null;
    });
  }

  void _saveCurrentDraft() {
    if (widget.existingOrderId != null) return;
    if (_items.isEmpty) {
      _draftService.clearDraft(customerId: widget.customer.id);
    } else {
      _draftService.saveDraft(
        DraftOrder(
        customer: widget.customer,
        items: List<DraftOrderItem>.from(_items),
      ));
    }
  }

  Future<void> _loadProducts() async {
    setState(() => _loading = true);
    final results = await Future.wait<List<Product>>(<Future<List<Product>>>[
      widget.productRepository.searchProducts(_searchController.text),
      widget.productRepository.getFrequentlyUsedProducts(),
    ]);
    if (!mounted) return;
    setState(() {
      _products = results[0];
      _frequentlyUsed = results[1];
      _loading = false;
    });
  }

  void _onSearchChanged(String _) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 250), () {
      _loadProducts();
      setState(() {});
    });
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _selectProduct(Product product, {int? editIndex}) async {
    if (editIndex == null) {
      final existingForThisProduct = _items
          .where((i) =>
              (product.id != null && i.productId == product.id) ||
              (product.name.isNotEmpty && i.itemName == product.name))
          .toList();

      final bulkItems = await Navigator.push<List<DraftOrderItem>>(
        context,
        MaterialPageRoute<List<DraftOrderItem>>(
          builder: (_) => BulkProductOptionsScreen(
            product: product,
            existingItems: existingForThisProduct,
          ),
        ),
      );
      if (bulkItems == null || !mounted) return;
      setState(() {
        _items.removeWhere(
            (i) => i.productId == product.id || i.itemName == product.name);
        _items.addAll(bulkItems);
      });
      _saveCurrentDraft();
      return;
    }
    final initial = _items[editIndex];
    final result = await Navigator.push<DraftOrderItem>(
      context,
      MaterialPageRoute<DraftOrderItem>(
        builder: (_) =>
            ProductOptionsScreen(product: product, initial: initial),
      ),
    );
    if (result == null || !mounted) {
      return;
    }
    setState(() => _items[editIndex] = result);
    _saveCurrentDraft();
  }

  Future<void> _addOtherItem() async {
    final s = AppLocalizations.of(context);
    final itemNameCtrl = TextEditingController();
    final detailsCtrl = TextEditingController();
    final notesCtrl = TextEditingController();
    final rateCtrl = TextEditingController();
    double qty = 1;
    String unit =
        const bool.fromEnvironment('STANDALONE_LOCAL', defaultValue: false)
            ? 'Piece'
            : 'Box';

    final DraftOrderItem? result;
    try {
      result = await showModalBottomSheet<DraftOrderItem>(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Padding(
              padding: EdgeInsets.only(
                left: 16,
                right: 16,
                top: 16,
                bottom: MediaQuery.of(context).viewInsets.bottom + 16,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(s.t('otherItem'),
                        style: const TextStyle(
                            fontSize: 19, fontWeight: FontWeight.w800)),
                    TextField(
                        controller: itemNameCtrl,
                        decoration:
                            InputDecoration(labelText: s.t('itemName'))),
                    TextField(
                        controller: rateCtrl,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: const InputDecoration(
                          labelText: 'Price / Rate per unit (₹)',
                          prefixText: '₹ ',
                        )),
                    TextField(
                        controller: detailsCtrl,
                        decoration: InputDecoration(
                            labelText: s.t('descriptionDetails'))),
                    const SizedBox(height: 10),
                    Text(s.t('quantity')),
                    QuantitySelector(
                      value: qty,
                      min: 1,
                      onChanged: (v) => setModalState(() => qty = v),
                    ),
                    QuantityPresets(
                      onSelected: (v) => setModalState(() => qty = v),
                    ),
                    DropdownButtonFormField<String>(
                      initialValue: const bool.fromEnvironment('STANDALONE_LOCAL',
                              defaultValue: false)
                          ? 'Piece'
                          : 'Box',
                      decoration: InputDecoration(labelText: s.t('unit')),
                      items: (const bool.fromEnvironment('STANDALONE_LOCAL',
                                  defaultValue: false)
                              ? const <String>[
                                  'Piece',
                                  'Meter',
                                  'Litre',
                                  'Kg',
                                  'Packet',
                                  'Box'
                                ]
                              : const <String>[
                                  'Box',
                                  'Carton',
                                  'Bundle',
                                  'Bag',
                                  'Piece',
                                  'Kg'
                                ])
                          .map((e) => DropdownMenuItem<String>(
                              value: e, child: Text(e)))
                          .toList(),
                      onChanged: (v) {
                        if (v != null) {
                          setModalState(() => unit = v);
                        }
                      },
                    ),
                    TextField(
                        controller: notesCtrl,
                        decoration: InputDecoration(labelText: s.t('notes'))),
                    const SizedBox(height: 16),
                    LargeActionButton(
                      label: s.t('addItem'),
                      onTap: () async {
                        final rawName = itemNameCtrl.text.trim();
                        if (rawName.isEmpty) return;

                        final enteredRate = double.tryParse(rateCtrl.text.trim()) ?? 0.0;

                        // Check if product exists; if not, auto-create in catalog with needsReview flag
                        final existing = await widget.productRepository.searchProducts(rawName);
                        Product? matched = existing.cast<Product?>().firstWhere(
                          (p) => p?.name.trim().toLowerCase() == rawName.toLowerCase(),
                          orElse: () => null,
                        );

                        int productId;
                        if (matched != null && matched.id != null) {
                          productId = matched.id!;
                        } else {
                          final newProd = Product(
                            name: rawName,
                            category: 'Custom / Other',
                            isActive: true,
                            needsReview: true,
                            configuration: ProductConfiguration(
                              steps: const [],
                              defaultUnit: unit,
                              unitOptions: [unit],
                              basePrice: enteredRate,
                            ),
                          );
                          productId = await widget.productRepository.upsertProduct(newProd);
                        }

                        if (context.mounted) {
                          Navigator.pop(
                            context,
                            DraftOrderItem(
                              productId: productId,
                              itemName: rawName,
                              options: const <String, String>{},
                              quantity: qty,
                              unit: unit,
                              unitPrice: enteredRate > 0 ? enteredRate : null,
                              isOtherItem: true,
                              description: detailsCtrl.text.trim(),
                              notes: notesCtrl.text.trim(),
                            ),
                          );
                        }
                      },
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
    } finally {
      itemNameCtrl.dispose();
      detailsCtrl.dispose();
      notesCtrl.dispose();
      rateCtrl.dispose();
    }

    if (result != null) {
      final addedItem = result;
      setState(() => _items.add(addedItem));
      _saveCurrentDraft();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Added "${result.itemName}" to cart & saved to catalog (flagged for review).'),
            backgroundColor: const Color(0xFF0F766E),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  Future<void> _quickAddNewProductFromSearch(String rawName) async {
    final name = rawName.trim();
    if (name.isEmpty) return;

    final rateCtrl = TextEditingController();
    double qty = 1;
    String unit = const bool.fromEnvironment('STANDALONE_LOCAL', defaultValue: false)
        ? 'Piece'
        : 'Box';

    final DraftOrderItem? added;
    try {
      added = await showModalBottomSheet<DraftOrderItem>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) {
          return Padding(
            padding: EdgeInsets.only(
              left: 20,
              right: 20,
              top: 20,
              bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0F766E).withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(Icons.add_shopping_cart,
                            color: Color(0xFF0F766E), size: 22),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Add "$name"',
                              style: const TextStyle(
                                  fontSize: 18, fontWeight: FontWeight.bold),
                            ),
                            const Text(
                              'Add to cart & auto-save to product catalog',
                              style: TextStyle(fontSize: 12, color: Colors.grey),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: rateCtrl,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                      labelText: 'Price / Rate per unit (₹)',
                      prefixText: '₹ ',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Quantity',
                                style: TextStyle(
                                    fontWeight: FontWeight.bold, fontSize: 13)),
                            const SizedBox(height: 6),
                            QuantitySelector(
                              value: qty,
                              min: 1,
                              onChanged: (v) => setSheetState(() => qty = v),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Unit',
                                style: TextStyle(
                                    fontWeight: FontWeight.bold, fontSize: 13)),
                            const SizedBox(height: 6),
                            DropdownButtonFormField<String>(
                              initialValue: unit,
                              decoration: const InputDecoration(
                                isDense: true,
                                border: OutlineInputBorder(),
                                contentPadding: EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 8),
                              ),
                              items: const [
                                'Piece',
                                'Box',
                                'Kg',
                                'Litre',
                                'Meter',
                                'Packet',
                                'Bundle',
                                'Carton',
                                'Bag',
                              ]
                                  .map((u) => DropdownMenuItem(
                                      value: u, child: Text(u)))
                                  .toList(),
                              onChanged: (val) {
                                if (val != null) setSheetState(() => unit = val);
                              },
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF0F766E),
                      minimumSize: const Size(double.infinity, 48),
                    ),
                    onPressed: () async {
                      final enteredRate =
                          double.tryParse(rateCtrl.text.trim()) ?? 0.0;
                      final newProd = Product(
                        name: name,
                        category: 'Custom / Other',
                        isActive: true,
                        needsReview: true,
                        configuration: ProductConfiguration(
                          steps: const [],
                          defaultUnit: unit,
                          unitOptions: [unit],
                          basePrice: enteredRate,
                        ),
                      );
                      final pid =
                          await widget.productRepository.upsertProduct(newProd);

                      final orderItem = DraftOrderItem(
                        productId: pid,
                        itemName: name,
                        options: const <String, String>{},
                        quantity: qty,
                        unit: unit,
                        unitPrice: enteredRate > 0 ? enteredRate : null,
                        isOtherItem: true,
                      );
                      if (ctx.mounted) Navigator.pop(ctx, orderItem);
                    },
                    icon: const Icon(Icons.check),
                    label: const Text('ADD TO CART & SAVE ITEM',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
    } finally {
      rateCtrl.dispose();
    }

    if (added != null && mounted) {
      setState(() {
        _items.add(added!);
        _searchController.clear();
      });
      _saveCurrentDraft();
      await _loadProducts();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              'Added "$name" to cart & saved to product catalog (flagged for review).'),
          backgroundColor: const Color(0xFF0F766E),
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  Future<void> _deleteItem(int index) async {
    final s = AppLocalizations.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(s.t('deleteItemTitle')),
          content: Text(s.t('deleteItemMessage')),
          actions: <Widget>[
            TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text(s.t('cancel'))),
            FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: Text(s.t('delete'))),
          ],
        );
      },
    );
    if (ok == true) {
      setState(() => _items.removeAt(index));
      _saveCurrentDraft();
    }
  }

  Widget _buildGroupedCurrentOrderList() {
    final Map<String, List<int>> grouped = {};
    for (int i = 0; i < _items.length; i++) {
      grouped.putIfAbsent(_items[i].itemName, () => []).add(i);
    }
    final entries = grouped.entries.toList();

    return ListView.builder(
      itemCount: entries.length,
      itemBuilder: (context, index) {
        final entry = entries[index];
        final productName = entry.key;
        final indices = entry.value;

        if (indices.length == 1) {
          final itemIndex = indices.first;
          final item = _items[itemIndex];
          return OrderItemCard(
            item: item,
            onEdit: item.isOtherItem || item.productId == null
                ? null
                : () async {
                    final pid = item.productId;
                    if (pid == null) return;
                    final product =
                        await widget.productRepository.getProductById(pid);
                    if (product != null && context.mounted) {
                      await _selectProduct(product, editIndex: itemIndex);
                    }
                  },
            onDelete: () => _deleteItem(itemIndex),
          );
        }

        // Grouped card for multiple variants under same product name
        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          elevation: 1,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '$productName (${indices.length} variants)',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                ...indices.map((i) {
                  final item = _items[i];
                  final opts = item.options.entries
                      .map((e) => e.value)
                      .join(', ');

                  final qtyStr = item.quantity % 1 == 0
                      ? item.quantity.toInt().toString()
                      : item.quantity.toString();

                  return Container(
                    margin: const EdgeInsets.only(bottom: 4),
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade50,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            opts.isNotEmpty ? '$opts • $qtyStr ${item.unit}' : '$qtyStr ${item.unit}',
                            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                          ),
                        ),
                        if (!item.isOtherItem && item.productId != null)
                          InkWell(
                            onTap: () async {
                              final pid = item.productId;
                              if (pid == null) return;
                              final product = await widget.productRepository
                                  .getProductById(pid);
                              if (product != null && context.mounted) {
                                await _selectProduct(product, editIndex: i);
                              }
                            },
                            child: const Icon(Icons.edit_outlined, size: 16, color: Colors.blue),
                          ),
                        const SizedBox(width: 8),
                        InkWell(
                          onTap: () => _deleteItem(i),
                          child: const Icon(Icons.delete_outline, size: 16, color: Colors.red),
                        ),
                      ],
                    ),
                  );
                }),
              ],
            ),
          ),
        );
      },
    );
  }



  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context);
    final isSearching = _searchController.text.trim().isNotEmpty;

    return PopScope(
      canPop: _items.isEmpty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop || _items.isEmpty) return;
        final discard = await showDialog<bool>(
              context: context,
              builder: (context) {
                return AlertDialog(
                  title: Text(s.t('leaveUnsavedTitle')),
                  content: Text(s.t('leaveUnsavedMessage')),
                  actions: <Widget>[
                    TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: Text(s.t('stay'))),
                    FilledButton(
                        onPressed: () => Navigator.pop(context, true),
                        child: Text(s.t('leave'))),
                  ],
                );
              },
            ) ??
            false;
        if (discard && context.mounted) {
          Navigator.pop(context);
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                s.t('selectItems'),
                style:
                    const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              Text(
                widget.customer.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.normal,
                  color: Colors.grey.shade600,
                ),
              ),
            ],
          ),
          actions: <Widget>[
            if (_items.isNotEmpty)
              TextButton.icon(
                style: TextButton.styleFrom(
                  foregroundColor: Colors.red.shade700,
                  visualDensity: VisualDensity.compact,
                ),
                onPressed: _clearDraft,
                icon: const Icon(Icons.delete_sweep, size: 18),
                label: const Text(
                  'Clear Draft',
                  style:
                      TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                ),
              ),
          ],
        ),
        body: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            children: <Widget>[
              if (_savedDraft != null && _items.isEmpty)
                Card(
                  color: Colors.amber.shade100,
                  margin: const EdgeInsets.only(bottom: 10),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    child: Row(
                      children: <Widget>[
                        const Icon(Icons.history, color: Colors.brown),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Unsaved draft order found for ${_savedDraft!.customer.name} (${_savedDraft!.items.length} items)',
                            style: const TextStyle(color: Colors.brown, fontWeight: FontWeight.w600, fontSize: 13),
                          ),
                        ),
                        TextButton(
                          onPressed: _resumeDraft,
                          child: const Text('RESUME', style: TextStyle(fontWeight: FontWeight.bold)),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close, size: 18),
                          onPressed: _clearDraft,
                        ),
                      ],
                    ),
                  ),
                ),
              TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  labelText: s.t('searchItems'),
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_searchController.text.isNotEmpty)
                        IconButton(
                          icon: const Icon(Icons.clear, size: 20),
                          onPressed: () {
                            _searchController.clear();
                            _loadProducts();
                          },
                        ),
                      IconButton(
                        tooltip: 'Voice Search Product',
                        icon: const Icon(Icons.mic, color: Color(0xFF0F766E)),
                        onPressed: () async {
                          final text = await VoiceSearchService.instance
                              .recordSpeech(
                            context,
                            title: 'Search Product',
                            hint:
                                'Say product name (e.g. Cut-off Wheels, Paints)...',
                          );
                          if (text != null && text.trim().isNotEmpty) {
                            _searchController.text = text.trim();
                            await _loadProducts();
                          }
                        },
                      ),
                    ],
                  ),
                ),
                onChanged: _onSearchChanged,
              ),
              const SizedBox(height: 10),
              Expanded(
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : ListView(
                        children: <Widget>[
                          if (isSearching) ...<Widget>[
                            // Quick Add Banner for typed search query
                            Card(
                              elevation: 0,
                              color: const Color(0xFFF0FDF4),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                                side: const BorderSide(color: Color(0xFF86EFAC)),
                              ),
                              child: ListTile(
                                dense: true,
                                leading: Container(
                                  padding: const EdgeInsets.all(6),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF0F766E),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: const Icon(Icons.add_shopping_cart,
                                      color: Colors.white, size: 18),
                                ),
                                title: Text(
                                  'Add "${_searchController.text.trim()}" as New Item',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13,
                                    color: Color(0xFF065F46),
                                  ),
                                ),
                                subtitle: const Text(
                                  'Add to cart & auto-save to product catalog',
                                  style: TextStyle(
                                      fontSize: 10, color: Color(0xFF047857)),
                                ),
                                trailing: FilledButton.tonal(
                                  style: FilledButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 10, vertical: 4),
                                    visualDensity: VisualDensity.compact,
                                  ),
                                  onPressed: () =>
                                      _quickAddNewProductFromSearch(
                                          _searchController.text.trim()),
                                  child: const Text('ADD TO CART',
                                      style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold)),
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),

                            if (_products.isNotEmpty)
                              _ProductSuggestions(
                                products: _products,
                                onProductTap: _selectProduct,
                                cartItems: _items,
                              )
                            else
                              Padding(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 24),
                                child: Center(
                                  child: Column(
                                    children: [
                                      const Icon(Icons.search_off_rounded,
                                          size: 40, color: Colors.grey),
                                      const SizedBox(height: 8),
                                      Text(
                                        'No catalog match for "${_searchController.text.trim()}"',
                                        style: TextStyle(
                                            fontWeight: FontWeight.w600,
                                            fontSize: 13,
                                            color: Colors.grey.shade700),
                                      ),
                                      const SizedBox(height: 4),
                                      const Text(
                                        'Tap the green button above to add it now!',
                                        style: TextStyle(
                                            fontSize: 11, color: Colors.grey),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                          ]
                          else ...<Widget>[
                            if (_frequentlyUsed.isNotEmpty) ...<Widget>[
                              Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: Text(s.t('frequentlyUsed'),
                                    style: const TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w800)),
                              ),
                              _ProductGrid(
                                products: _frequentlyUsed,
                                onProductTap: _selectProduct,
                                cartItems: _items,
                              ),
                              const Divider(height: 28),
                            ],
                            Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: Text(s.t('allProducts'),
                                  style: const TextStyle(
                                      fontSize: 15, fontWeight: FontWeight.w800)),
                            ),
                            _ProductGrid(
                              products: _products,
                              onProductTap: _selectProduct,
                              includeOther: true,
                              otherLabel: s.t('others'),
                              onOtherTap: _addOtherItem,
                              cartItems: _items,
                            ),
                          ],
                        ],
                      ),
              ),
              // Show Current Order ONLY when NOT searching
              if (!isSearching) ...<Widget>[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(8),
                  color: Colors.grey.shade100,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '${s.t('currentOrder')} (${_items.length})',
                        style: const TextStyle(
                            fontWeight: FontWeight.w800, fontSize: 16),
                      ),
                      if (_items.isNotEmpty)
                        GestureDetector(
                          onTap: _clearDraft,
                          child: const Text('Clear', style: TextStyle(color: Colors.red, fontWeight: FontWeight.w600)),
                        ),
                    ],
                  ),
                ),
                SizedBox(
                  height: 150,
                  child: _items.isEmpty
                      ? Center(child: Text(s.t('noItems')))
                      : _buildGroupedCurrentOrderList(),
                ),

              ],
              const SizedBox(height: 10),
              LargeActionButton(
                label: widget.existingOrderId == null
                    ? s.t('createOrderCta')
                    : 'ADD TO ORDER',
                onTap: _items.isEmpty
                    ? null
                    : () {
                        final draft = DraftOrder(
                            customer: widget.customer,
                            items: List<DraftOrderItem>.from(_items));
                        Navigator.push(
                          context,
                          MaterialPageRoute<void>(
                            builder: (_) => OrderPreviewScreen(
                              draftOrder: draft,
                              orderRepository: widget.orderRepository,
                              existingOrderId: widget.existingOrderId,
                            ),
                          ),
                        );
                      },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProductGrid extends StatelessWidget {
  const _ProductGrid({
    required this.products,
    required this.onProductTap,
    this.includeOther = false,
    this.otherLabel,
    this.onOtherTap,
    this.cartItems = const <DraftOrderItem>[],
  });

  final List<Product> products;
  final ValueChanged<Product> onProductTap;
  final bool includeOther;
  final String? otherLabel;
  final VoidCallback? onOtherTap;
  final List<DraftOrderItem> cartItems;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final int crossAxisCount = width > 700 ? 4 : (width > 420 ? 3 : 2);
    final double childAspectRatio =
        width > 700 ? 2.0 : (width > 420 ? 1.6 : 1.9);

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: crossAxisCount,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
        childAspectRatio: childAspectRatio,
      ),
      itemCount: products.length + (includeOther ? 1 : 0),
      itemBuilder: (context, index) {
        if (index == products.length) {
          return ProductCard(
            title: otherLabel!,
            icon: Icons.add_circle_outline,
            onTap: onOtherTap!,
          );
        }
        final product = products[index];
        final cartQty = cartItems
            .where(
                (i) => i.productId == product.id || i.itemName == product.name)
            .fold<double>(0, (sum, i) => sum + i.quantity);

        return ProductCard(
          title: AppLocalizations.of(context).catalog(product.name),
          icon: Icons.inventory_2_outlined,
          cartQuantity: cartQty > 0 ? cartQty : null,
          onTap: () => onProductTap(product),
        );
      },
    );
  }
}

class _ProductSuggestions extends StatelessWidget {
  const _ProductSuggestions({
    required this.products,
    required this.onProductTap,
    this.cartItems = const <DraftOrderItem>[],
  });

  final List<Product> products;
  final ValueChanged<Product> onProductTap;
  final List<DraftOrderItem> cartItems;

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 4),
            child: Text(
              AppLocalizations.of(context).t('suggestions'),
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
            ),
          ),
          ...products.map(
            (product) {
              final cartQty = cartItems
                  .where((i) =>
                      i.productId == product.id || i.itemName == product.name)
                  .fold<double>(0, (sum, i) => sum + i.quantity);
              final inCart = cartQty > 0;
              final qtyStr = cartQty % 1 == 0
                  ? cartQty.toInt().toString()
                  : cartQty.toString();

              return ListTile(
                dense: true,
                leading: Icon(
                  Icons.inventory_2_outlined,
                  size: 20,
                  color: inCart ? const Color(0xFF0F766E) : null,
                ),
                title: Text(
                  s.catalog(product.name),
                  style: TextStyle(
                    fontWeight: inCart ? FontWeight.bold : FontWeight.normal,
                    color: inCart ? const Color(0xFF0F766E) : null,
                  ),
                ),
                subtitle: Text(
                  inCart
                      ? '${product.category} • $qtyStr in cart'
                      : product.category,
                  style: TextStyle(
                    color: inCart ? const Color(0xFF0F766E) : null,
                    fontWeight: inCart ? FontWeight.w600 : FontWeight.normal,
                  ),
                ),
                trailing: inCart
                    ? Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0F766E),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          '$qtyStr in cart',
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.bold),
                        ),
                      )
                    : const Icon(Icons.chevron_right, size: 20),
                onTap: () => onProductTap(product),
              );
            },
          ),
        ],
      ),
    );
  }
}
