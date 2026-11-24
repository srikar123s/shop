import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shop/models/product.dart';
import 'package:shop/repositories/product_repository.dart';
import 'package:shop/services/voice_search_service.dart';

class PriceListScreen extends StatefulWidget {
  const PriceListScreen({super.key, required this.productRepository});

  final ProductRepository productRepository;

  @override
  State<PriceListScreen> createState() => _PriceListScreenState();
}

class _PriceListScreenState extends State<PriceListScreen> {
  final TextEditingController _searchController = TextEditingController();
  List<Product> _allProducts = [];
  List<Product> _filteredProducts = [];
  String _selectedCategory = 'All';
  List<String> _categories = ['All'];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadProducts();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadProducts() async {
    setState(() => _loading = true);
    final products =
        await widget.productRepository.getAllProducts(includeInactive: false);
    if (!mounted) return;

    final cats = {'All', ...products.map((p) => p.category)};
    setState(() {
      _allProducts = products;
      _categories = cats.toList();
      _loading = false;
    });
    _filter();
  }

  void _filter() {
    final query = _searchController.text.trim().toLowerCase();
    setState(() {
      _filteredProducts = _allProducts.where((p) {
        final matchesCat =
            _selectedCategory == 'All' || p.category == _selectedCategory;
        final matchesQuery = query.isEmpty ||
            p.name.toLowerCase().contains(query) ||
            p.category.toLowerCase().contains(query);
        return matchesCat && matchesQuery;
      }).toList();
    });
  }

  List<Map<String, dynamic>> _extractVariantPrices(Product p) {
    final variants = <Map<String, dynamic>>[];
    try {
      final config = p.configuration;
      if (config.variantPrices.isNotEmpty) {
        config.variantPrices.forEach((key, price) {
          final parts = key.split('__');
          final label = parts.join(' • ');
          variants.add({'label': label, 'price': price});
        });
      } else if (config.basePrice > 0) {
        variants.add({'label': 'Standard', 'price': config.basePrice});
      }
    } catch (_) {}
    return variants;
  }

  void _shareItemPrice(Product p, List<Map<String, dynamic>> variants) {
    final defaultUnit = p.configuration.defaultUnit ?? 'pcs';
    final buffer = StringBuffer();
    buffer.writeln('🏷️ *Price Details - ${p.name}*');
    buffer.writeln('Category: ${p.category}');
    buffer.writeln('Default Unit: $defaultUnit');
    buffer.writeln('---------------------------');
    if (variants.isNotEmpty) {
      for (final v in variants) {
        buffer.writeln(
            '• ${v['label']}: ₹ ${(v['price'] as double).toStringAsFixed(2)} / $defaultUnit');
      }
    } else {
      buffer.writeln('Price: Available on request');
    }
    buffer.writeln('---------------------------');
    buffer.writeln('Inquire with us for bulk orders!');
    Share.share(buffer.toString());
  }

  @override
  Widget build(BuildContext context) {
    final currency = NumberFormat.currency(locale: 'en_IN', symbol: '₹ ');

    return Scaffold(
      appBar: AppBar(
        title: const Text('Quick Price List',
            style: TextStyle(fontWeight: FontWeight.bold)),
      ),
      body: Column(
        children: [
          // Search & Voice Search
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search product or category...',
                prefixIcon: const Icon(Icons.search),
                isDense: true,
                suffixIcon: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_searchController.text.isNotEmpty)
                      IconButton(
                        icon: const Icon(Icons.clear, size: 20),
                        onPressed: () {
                          _searchController.clear();
                          _filter();
                        },
                      ),
                    IconButton(
                      tooltip: 'Voice Search',
                      icon: const Icon(Icons.mic, color: Color(0xFF0F766E)),
                      onPressed: () async {
                        final text =
                            await VoiceSearchService.instance.recordSpeech(
                          context,
                          title: 'Search Price List',
                          hint: 'Say product name (e.g. Paints, Sponges)...',
                        );
                        if (!mounted) return;
                        if (text != null && text.trim().isNotEmpty) {
                          _searchController.text = text.trim();
                          _filter();
                        }
                      },
                    ),
                  ],
                ),
              ),
              onChanged: (_) => _filter(),
            ),
          ),

          // Category Chips
          if (_categories.length > 1)
            SizedBox(
              height: 42,
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                scrollDirection: Axis.horizontal,
                itemCount: _categories.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (context, idx) {
                  final cat = _categories[idx];
                  final isSelected = cat == _selectedCategory;
                  return ChoiceChip(
                    label: Text(cat),
                    selected: isSelected,
                    onSelected: (selected) {
                      if (selected) {
                        setState(() => _selectedCategory = cat);
                        _filter();
                      }
                    },
                    selectedColor: const Color(0xFF0F766E),
                    labelStyle: TextStyle(
                      fontSize: 12,
                      fontWeight:
                          isSelected ? FontWeight.bold : FontWeight.w500,
                      color: isSelected ? Colors.white : Colors.black87,
                    ),
                    visualDensity: VisualDensity.compact,
                  );
                },
              ),
            ),
          const SizedBox(height: 8),

          // Price List Content
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _filteredProducts.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.inventory_2_outlined,
                                size: 52, color: Colors.grey.shade400),
                            const SizedBox(height: 12),
                            Text('No matching products found',
                                style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.grey.shade600)),
                          ],
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                        itemCount: _filteredProducts.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 10),
                        itemBuilder: (context, index) {
                          final product = _filteredProducts[index];
                          final variants = _extractVariantPrices(product);

                          return Card(
                            elevation: 1,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                              side: BorderSide(color: Colors.grey.shade200),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(14),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.all(8),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFF0F766E)
                                              .withValues(alpha: 0.1),
                                          borderRadius:
                                              BorderRadius.circular(10),
                                        ),
                                        child: const Icon(
                                          Icons.sell_outlined,
                                          color: Color(0xFF0F766E),
                                          size: 20,
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              product.name,
                                              style: const TextStyle(
                                                fontWeight: FontWeight.bold,
                                                fontSize: 16,
                                              ),
                                            ),
                                            const SizedBox(height: 2),
                                            Text(
                                              '${product.category} • Unit: ${product.configuration.defaultUnit ?? "pcs"}',
                                              style: TextStyle(
                                                fontSize: 12,
                                                color: Colors.grey.shade600,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      IconButton(
                                        tooltip: 'Share Price',
                                        icon: const Icon(Icons.share_outlined,
                                            size: 20, color: Color(0xFF0F766E)),
                                        onPressed: () => _shareItemPrice(
                                            product, variants),
                                      ),
                                    ],
                                  ),
                                  if (variants.isNotEmpty) ...[
                                    const Divider(height: 16),
                                    Wrap(
                                      spacing: 8,
                                      runSpacing: 6,
                                      children: variants.map((v) {
                                        final pVal = v['price'] as double;
                                        return Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 10, vertical: 5),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFFF1F5F9),
                                            borderRadius:
                                                BorderRadius.circular(8),
                                            border: Border.all(
                                                color: const Color(0xFFE2E8F0)),
                                          ),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Text(
                                                '${v['label']}: ',
                                                style: const TextStyle(
                                                    fontSize: 12,
                                                    fontWeight: FontWeight.w600),
                                              ),
                                              Text(
                                                currency.format(pVal),
                                                style: const TextStyle(
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.w900,
                                                  color: Color(0xFF0F766E),
                                                ),
                                              ),
                                            ],
                                          ),
                                        );
                                      }).toList(),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}
