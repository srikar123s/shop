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
  List<Product> _products = <Product>[];
  List<Product> _frequentlyUsed = <Product>[];
  final List<DraftOrderItem> _items = <DraftOrderItem>[];
  bool _loading = true;
  Timer? _searchDebounce;

  @override
  void initState() {
    super.initState();
    _loadProducts();
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
    _searchDebounce = Timer(const Duration(milliseconds: 250), _loadProducts);
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
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context);
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
            title: Text('${s.t('selectItems')} - ${widget.customer.name}')),
        body: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            children: <Widget>[
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
                          if (_searchController.text.trim().isNotEmpty &&
                              _products.isNotEmpty)
                            _ProductSuggestions(
                              products: _products.take(6).toList(),
                              onProductTap: _selectProduct,
                            ),
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
                      ),
              ),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(8),
                color: Colors.white,
                child: Text(
                  s.t('currentOrder'),
                  style: const TextStyle(
                      fontWeight: FontWeight.w800, fontSize: 16),
                ),
              ),
              SizedBox(
                height: 150,
                child: _items.isEmpty
                    ? Center(child: Text(s.t('noItems')))
                    : ListView.builder(
                        itemCount: _items.length,
                        itemBuilder: (context, index) {
                          final item = _items[index];
                          return OrderItemCard(
                            item: item,
                            onEdit: item.isOtherItem
                                ? null
                                : () async {
                                    final product = await widget
                                        .productRepository
                                        .getProductById(item.productId!);
                                    if (product != null && context.mounted) {
                                      await _selectProduct(product,
                                          editIndex: index);
                                    }
                                  },
                            onDelete: () => _deleteItem(index),
                          );
                        },
                      ),
              ),
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
        crossAxisCount: 2,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
        childAspectRatio: 2,
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
            padding: EdgeInsets.fromLTRB(14, 10, 14, 4),
            child: Text(
              AppLocalizations.of(context).t('suggestions'),
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
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
