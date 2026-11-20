import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:shop/models/order.dart';
import 'package:shop/repositories/customer_repository.dart';
import 'package:shop/repositories/order_repository.dart';
import 'package:shop/repositories/product_repository.dart';
import 'package:shop/screens/order_details_screen.dart';
import 'package:shop/services/shop_customization_service.dart';
import 'package:url_launcher/url_launcher.dart';

class ProcurementScreen extends StatefulWidget {
  const ProcurementScreen({
    super.key,
    required this.orderRepository,
    required this.customerRepository,
    required this.productRepository,
  });

  final OrderRepository orderRepository;
  final CustomerRepository customerRepository;
  final ProductRepository productRepository;

  @override
  State<ProcurementScreen> createState() => _ProcurementScreenState();
}

class _ProcurementScreenState extends State<ProcurementScreen> {
  final TextEditingController _searchController = TextEditingController();
  List<ProcurementItem> _items = [];
  bool _loading = true;
  String _selectedCategory = 'ALL';

  @override
  void initState() {
    super.initState();
    _loadItems();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadItems() async {
    setState(() => _loading = true);
    try {
      final items = await widget.orderRepository
          .getProcurementItems(query: _searchController.text);
      if (!mounted) return;
      setState(() {
        _items = items;
        _loading = false;
      });
    } catch (e, stack) {
      debugPrint('Error loading procurement items: $e\n$stack');
      if (!mounted) return;
      setState(() {
        _items = [];
        _loading = false;
      });
    }
  }

  String _formatQty(double qty) =>
      qty % 1 == 0 ? qty.toInt().toString() : qty.toString();

  String _getItemCategory(ProcurementItem item) {
    if (item.productSnapshot.isNotEmpty) {
      try {
        final map = jsonDecode(item.productSnapshot) as Map<String, dynamic>;
        final cat = map['category'] as String?;
        if (cat != null && cat.trim().isNotEmpty) return cat.trim();
      } catch (_) {}
    }
    return item.itemName.split(' ').first;
  }

  List<String> get _categories {
    final set = <String>{'ALL'};
    for (final item in _items) {
      set.add(_getItemCategory(item));
    }
    return set.toList();
  }

  List<ProcurementItem> get _filteredItems {
    if (_selectedCategory == 'ALL') return _items;
    return _items.where((i) => _getItemCategory(i) == _selectedCategory).toList();
  }

  Future<void> _markItemProcured(ProcurementItem item) async {
    HapticFeedback.mediumImpact();
    await widget.orderRepository.markItemAsProcured(
      itemId: item.itemId,
      orderId: item.orderId,
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('✅ ${item.itemName} (${_formatQty(item.quantityPending)} ${item.unit}) marked as procured & delivered!'),
        backgroundColor: const Color(0xFF0F766E),
        duration: const Duration(seconds: 2),
      ),
    );
    _loadItems();
  }

  Future<void> _confirmMarkAllProcured() async {
    if (_items.isEmpty) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Mark All as Procured?'),
        content: Text(
          'This will mark all ${_items.length} pending item(s) as delivered to customers and update active orders.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFF0F766E)),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Yes, Mark All Procured'),
          ),
        ],
      ),
    );

    if (confirm == true && mounted) {
      HapticFeedback.heavyImpact();
      await widget.orderRepository.markAllItemsAsProcured();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('🎉 All items marked as procured & fulfilled!'),
          backgroundColor: Color(0xFF0F766E),
        ),
      );
      _loadItems();
    }
  }

  Future<void> _confirmCancelShortage(ProcurementItem item) async {
    final fmtGiven = _formatQty(item.quantityGiven);
    final fmtOrdered = _formatQty(item.quantityOrdered);
    final fmtPending = _formatQty(item.quantityPending);

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Cut Shortage for "${item.itemName}"?'),
        content: Text(
          'Customer took $fmtGiven ${item.unit} out of $fmtOrdered ${item.unit}.\n\n'
          'Cancel the remaining $fmtPending ${item.unit}?\n'
          '• Item will be removed from Procurement\n'
          '• Bill for order ${item.formattedOrderId} will be adjusted to what was delivered\n'
          '• Godown will NOT purchase this shortage',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFFD97706)),
            onPressed: () => Navigator.pop(ctx, true),
            icon: const Icon(Icons.content_cut_rounded, size: 16),
            label: const Text('Yes, Cut Shortage'),
          ),
        ],
      ),
    );

    if (confirm == true && mounted) {
      HapticFeedback.mediumImpact();
      await widget.orderRepository.cancelItemShortage(
        itemId: item.itemId,
        orderId: item.orderId,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('✂️ Shortage cancelled for "${item.itemName}". Order updated.'),
          backgroundColor: const Color(0xFF0F766E),
        ),
      );
      _loadItems();
    }
  }

  Future<void> _shareProcurementList() async {
    HapticFeedback.lightImpact();
    if (_items.isEmpty) return;
    final shopName = ShopCustomizationService.instance.shopName;
    final dateStr = DateFormat('dd MMM yyyy, hh:mm a').format(DateTime.now());

    final sb = StringBuffer();
    sb.writeln('📋 *PROCUREMENT / SHORTAGE LIST*');
    sb.writeln('🏪 *$shopName*');
    sb.writeln('📅 $dateStr');
    sb.writeln('────────────────────────');
    sb.writeln('Total items needed: ${_items.length}');
    sb.writeln('');

    // Group items by category for easy shopping in market
    final Map<String, List<ProcurementItem>> grouped = {};
    for (final item in _items) {
      final cat = _getItemCategory(item);
      grouped.putIfAbsent(cat, () => []).add(item);
    }

    grouped.forEach((cat, items) {
      sb.writeln('📁 *${cat.toUpperCase()}*');
      int count = 1;
      for (final item in items) {
        final opts = item.options.isNotEmpty ? ' (${item.options.join(', ')})' : '';
        sb.writeln('  $count. *${item.itemName}*$opts');
        sb.writeln('     👉 *Need: ${_formatQty(item.quantityPending)} ${item.unit}* (Given ${_formatQty(item.quantityGiven)}/${_formatQty(item.quantityOrdered)})');
        sb.writeln('     👤 For: ${item.customerName} (${item.formattedOrderId})');
        count++;
      }
      sb.writeln('');
    });

    sb.writeln('────────────────────────');
    sb.writeln('Generated via Hardware Shop Notebook');

    final text = Uri.encodeComponent(sb.toString());
    final url = Uri.parse('whatsapp://send?text=$text');
    final webUrl = Uri.parse('https://api.whatsapp.com/send?text=$text');

    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    } else if (await canLaunchUrl(webUrl)) {
      await launchUrl(webUrl, mode: LaunchMode.externalApplication);
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open WhatsApp.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final totalPendingUnits = _items.fold<double>(
      0,
      (sum, i) => sum + i.quantityPending,
    );
    final displayedItems = _filteredItems;

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Procurement List',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        actions: [
          if (_items.isNotEmpty)
            IconButton(
              tooltip: 'Mark All as Procured',
              icon: const Icon(Icons.done_all_rounded, color: Color(0xFF0F766E)),
              onPressed: _confirmMarkAllProcured,
            ),
          IconButton(
            tooltip: 'Share via WhatsApp',
            icon: const Icon(Icons.share_rounded, color: Colors.green),
            onPressed: _items.isEmpty ? null : _shareProcurementList,
          ),
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _loadItems,
          ),
        ],
      ),
      body: Column(
        children: [
          // Header Summary Card
          Container(
            margin: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF0F766E), Color(0xFF115E59)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF0F766E).withValues(alpha: 0.25),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.inventory_2_outlined,
                      color: Colors.white, size: 28),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${_items.length} Item(s) to Procure',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _items.isEmpty
                            ? 'All orders are fully fulfilled! 🎉'
                            : '${_formatQty(totalPendingUnits)} total units pending delivery',
                        style: TextStyle(
                          color: Colors.teal.shade100,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
                if (_items.isNotEmpty)
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: const Color(0xFF0F766E),
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      textStyle: const TextStyle(
                          fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                    onPressed: _shareProcurementList,
                    icon: const Icon(Icons.send_rounded, size: 14),
                    label: const Text('Share'),
                  ),
              ],
            ),
          ),

          // Search Bar
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search items, customer, order #...',
                prefixIcon: const Icon(Icons.search, size: 20),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 18),
                        onPressed: () {
                          _searchController.clear();
                          _loadItems();
                        },
                      )
                    : null,
                isDense: true,
                filled: true,
                fillColor: Colors.grey.shade100,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
              onChanged: (_) => _loadItems(),
            ),
          ),

          // Category Filter Chips
          if (_categories.length > 2)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: SizedBox(
                height: 36,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: _categories.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 6),
                  itemBuilder: (context, idx) {
                    final cat = _categories[idx];
                    final isSel = cat == _selectedCategory;
                    return FilterChip(
                      selected: isSel,
                      showCheckmark: false,
                      label: Text(cat),
                      labelStyle: TextStyle(
                        fontSize: 12,
                        fontWeight: isSel ? FontWeight.bold : FontWeight.w600,
                        color: isSel ? Colors.white : Colors.grey.shade800,
                      ),
                      backgroundColor: Colors.grey.shade100,
                      selectedColor: const Color(0xFF0F766E),
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      onSelected: (_) {
                        HapticFeedback.selectionClick();
                        setState(() => _selectedCategory = cat);
                      },
                    );
                  },
                ),
              ),
            ),

          // Item List
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : displayedItems.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.check_circle_outline_rounded,
                                size: 64, color: Colors.green.shade400),
                            const SizedBox(height: 12),
                            const Text(
                              'No Items to Procure',
                              style: TextStyle(
                                  fontSize: 17, fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              _items.isEmpty
                                  ? 'All active orders have items fully given.'
                                  : 'No items in $_selectedCategory category.',
                              style: TextStyle(color: Colors.grey.shade600),
                            ),
                          ],
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: _loadItems,
                        child: ListView.separated(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                          itemCount: displayedItems.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 10),
                          itemBuilder: (context, index) {
                            final item = displayedItems[index];
                            final ageInDays = DateTime.now()
                                .difference(item.createdAt)
                                .inDays;
                            final isOver3Days = ageInDays >= 3;

                            return Card(
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                                side: BorderSide(
                                  color: isOver3Days
                                      ? Colors.red.shade300
                                      : const Color(0xFFE2E8F0),
                                  width: isOver3Days ? 1.5 : 1,
                                ),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.all(14),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    // Top row: Item Name + Age tag
                                    Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                item.itemName,
                                                style: const TextStyle(
                                                  fontSize: 16,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                              if (item.options.isNotEmpty)
                                                Padding(
                                                  padding:
                                                      const EdgeInsets.only(
                                                          top: 2),
                                                  child: Text(
                                                    item.options.join(' • '),
                                                    style: TextStyle(
                                                      fontSize: 12,
                                                      color: Colors
                                                          .grey.shade700,
                                                    ),
                                                  ),
                                                ),
                                            ],
                                          ),
                                        ),
                                        if (isOver3Days)
                                          Container(
                                            padding:
                                                const EdgeInsets.symmetric(
                                                    horizontal: 8, vertical: 3),
                                            decoration: BoxDecoration(
                                              color: Colors.red.shade50,
                                              borderRadius:
                                                  BorderRadius.circular(6),
                                              border: Border.all(
                                                  color: Colors.red.shade200),
                                            ),
                                            child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Icon(
                                                    Icons
                                                        .warning_amber_rounded,
                                                    size: 13,
                                                    color:
                                                        Colors.red.shade700),
                                                const SizedBox(width: 4),
                                                Text(
                                                  '$ageInDays days old',
                                                  style: TextStyle(
                                                    fontSize: 11,
                                                    fontWeight:
                                                        FontWeight.bold,
                                                    color: Colors.red.shade700,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                      ],
                                    ),
                                    const SizedBox(height: 12),

                                    // Quantity badge row
                                    Row(
                                      children: [
                                        _ProcureBadge(
                                          label: 'Ordered',
                                          value:
                                              '${_formatQty(item.quantityOrdered)} ${item.unit}',
                                          color: Colors.blue.shade700,
                                          bgColor: Colors.blue.shade50,
                                        ),
                                        const SizedBox(width: 8),
                                        _ProcureBadge(
                                          label: 'Given',
                                          value:
                                              '${_formatQty(item.quantityGiven)} ${item.unit}',
                                          color: Colors.teal.shade700,
                                          bgColor: Colors.teal.shade50,
                                        ),
                                        const SizedBox(width: 8),
                                        _ProcureBadge(
                                          label: 'To Procure',
                                          value:
                                              '${_formatQty(item.quantityPending)} ${item.unit}',
                                          color: Colors.red.shade800,
                                          bgColor: Colors.red.shade50,
                                          isHighlight: true,
                                        ),
                                      ],
                                    ),

                                    const SizedBox(height: 12),
                                    const Divider(height: 1),
                                    const SizedBox(height: 8),

                                    // Action Row: Customer info + "Mark Procured" button
                                    Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        Expanded(
                                          child: InkWell(
                                            onTap: () async {
                                              await Navigator.push(
                                                context,
                                                MaterialPageRoute<void>(
                                                  builder: (_) =>
                                                      OrderDetailsScreen(
                                                    orderId: item.orderId,
                                                    orderRepository:
                                                        widget.orderRepository,
                                                    productRepository:
                                                        widget.productRepository,
                                                    customerRepository:
                                                        widget.customerRepository,
                                                  ),
                                                ),
                                              );
                                              _loadItems();
                                            },
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  '${item.customerName} • ${item.formattedOrderId}',
                                                  style: const TextStyle(
                                                    fontWeight: FontWeight.w700,
                                                    fontSize: 12,
                                                  ),
                                                ),
                                                Text(
                                                  'Order taken: ${DateFormat("dd MMM, hh:mm a").format(item.createdAt)}',
                                                  style: TextStyle(
                                                    fontSize: 11,
                                                    color: Colors.grey.shade600,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            OutlinedButton.icon(
                                              style: OutlinedButton.styleFrom(
                                                foregroundColor:
                                                    const Color(0xFFD97706),
                                                side: const BorderSide(
                                                    color: Color(0xFFF59E0B)),
                                                visualDensity:
                                                    VisualDensity.compact,
                                                padding: const EdgeInsets.symmetric(
                                                    horizontal: 8, vertical: 4),
                                                shape: RoundedRectangleBorder(
                                                  borderRadius:
                                                      BorderRadius.circular(8),
                                                ),
                                              ),
                                              onPressed: () =>
                                                  _confirmCancelShortage(item),
                                              icon: const Icon(
                                                  Icons.content_cut_rounded,
                                                  size: 14),
                                              label: const Text(
                                                'Cut',
                                                style: TextStyle(
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                            ),
                                            const SizedBox(width: 6),
                                            FilledButton.icon(
                                              style: FilledButton.styleFrom(
                                                backgroundColor:
                                                    const Color(0xFF0F766E),
                                                visualDensity:
                                                    VisualDensity.compact,
                                                padding: const EdgeInsets.symmetric(
                                                    horizontal: 10, vertical: 4),
                                                shape: RoundedRectangleBorder(
                                                  borderRadius:
                                                      BorderRadius.circular(8),
                                                ),
                                              ),
                                              onPressed: () =>
                                                  _markItemProcured(item),
                                              icon: const Icon(
                                                  Icons.check_circle_outline,
                                                  size: 15),
                                              label: const Text(
                                                'Mark Procured',
                                                style: TextStyle(
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ),
          ),
        ],
      ),
    );
  }
}

class _ProcureBadge extends StatelessWidget {
  const _ProcureBadge({
    required this.label,
    required this.value,
    required this.color,
    required this.bgColor,
    this.isHighlight = false,
  });

  final String label;
  final String value;
  final Color color;
  final Color bgColor;
  final bool isHighlight;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color:
              isHighlight ? color.withValues(alpha: 0.4) : Colors.transparent,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: color.withValues(alpha: 0.8),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
