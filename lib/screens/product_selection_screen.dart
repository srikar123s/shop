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
  });

  final Customer customer;
  final ProductRepository productRepository;
  final OrderRepository orderRepository;
  final int? existingOrderId;

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
    _loadProducts();
    _checkDraft();
  }

  Future<void> _checkDraft() async {
    final draft = await _draftService.getDraft();
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
    await _draftService.clearDraft();
    if (!mounted) return;
    setState(() {
      _items.clear();
      _savedDraft = null;
    });
  }

  void _saveCurrentDraft() {
    if (widget.existingOrderId != null) return;
    if (_items.isEmpty) {
      _draftService.clearDraft();
    } else {
      _draftService.saveDraft(DraftOrder(
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
      final bulkItems = await Navigator.push<List<DraftOrderItem>>(
        context,
        MaterialPageRoute<List<DraftOrderItem>>(
          builder: (_) => BulkProductOptionsScreen(product: product),
        ),
      );
      if (bulkItems == null || bulkItems.isEmpty || !mounted) return;
      setState(() => _items.addAll(bulkItems));
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
    if (result == null) {
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
    double qty = 1;
    String unit = 'Piece';

    final result = await showModalBottomSheet<DraftOrderItem>(
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
                      initialValue: unit,
                      decoration: InputDecoration(labelText: s.t('unit')),
                      items: const <String>[
                        'Piece',
                        'Box',
                        'Kg',
                        'Litre',
                        'Feet',
                        'Packet'
                      ]
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
                      onTap: () {
                        if (itemNameCtrl.text.trim().isEmpty) {
                          return;
                        }
                        Navigator.pop(
                          context,
                          DraftOrderItem(
                            itemName: itemNameCtrl.text.trim(),
                            options: const <String, String>{},
                            quantity: qty,
                            unit: unit,
                            isOtherItem: true,
                            description: detailsCtrl.text.trim(),
                            notes: notesCtrl.text.trim(),
                          ),
                        );
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

    if (result != null) {
      setState(() => _items.add(result));
      _saveCurrentDraft();
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
            onEdit: item.isOtherItem
                ? null
                : () async {
                    final product = await widget.productRepository
                        .getProductById(item.productId!);
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
                        if (!item.isOtherItem)
                          InkWell(
                            onTap: () async {
                              final product = await widget.productRepository
                                  .getProductById(item.productId!);
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
          title: Text('${s.t('selectItems')} - ${widget.customer.name}'),
          actions: <Widget>[
            if (_items.isNotEmpty)
              TextButton.icon(
                style: TextButton.styleFrom(foregroundColor: Colors.white),
                onPressed: _clearDraft,
                icon: const Icon(Icons.delete_sweep, size: 18),
                label: const Text('Clear Draft'),
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
                  suffixIcon: IconButton(
                    onPressed: _loadProducts,
                    icon: const Icon(Icons.search),
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
                          if (isSearching && _products.isNotEmpty)
                            _ProductSuggestions(
                              products: _products,
                              onProductTap: _selectProduct,
                            )
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
  });

  final List<Product> products;
  final ValueChanged<Product> onProductTap;
  final bool includeOther;
  final String? otherLabel;
  final VoidCallback? onOtherTap;

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
        childAspectRatio: 1.35,
      ),

      itemCount: products.length + (includeOther ? 1 : 0),
      itemBuilder: (context, index) {
        if (index == products.length) {
          return ProductCard(title: otherLabel!, onTap: onOtherTap!);
        }
        final product = products[index];
        return ProductCard(
            title: AppLocalizations.of(context).catalog(product.name),
            onTap: () => onProductTap(product));
      },
    );
  }
}

class _ProductSuggestions extends StatelessWidget {
  const _ProductSuggestions({
    required this.products,
    required this.onProductTap,
  });

  final List<Product> products;
  final ValueChanged<Product> onProductTap;

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
            (product) => ListTile(
              dense: true,
              leading: const Icon(Icons.inventory_2_outlined, size: 20),
              title: Text(s.catalog(product.name)),
              subtitle: Text(product.category),
              trailing: const Icon(Icons.chevron_right, size: 20),
              onTap: () => onProductTap(product),
            ),
          ),
        ],
      ),
    );
  }
}
