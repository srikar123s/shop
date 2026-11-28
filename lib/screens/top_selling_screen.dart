import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shop/database/database_helper.dart';
import 'package:shop/models/top_product_stat.dart';

class TopSellingScreen extends StatefulWidget {
  const TopSellingScreen({super.key});

  @override
  State<TopSellingScreen> createState() => _TopSellingScreenState();
}

class _TopSellingScreenState extends State<TopSellingScreen> {
  String _timeRange = 'all'; // 'today', 'week', 'month', 'all'
  String _sortBy = 'quantity'; // 'quantity' or 'revenue'
  List<TopProductStat> _stats = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadStats();
  }

  Future<void> _loadStats() async {
    setState(() => _loading = true);
    final stats = await DatabaseHelper.instance.getTopSellingProducts(
      timeRange: _timeRange,
      sortBy: _sortBy,
      limit: 50,
    );
    if (!mounted) return;
    setState(() {
      _stats = stats;
      _loading = false;
    });
  }

  Color _rankColor(int index) {
    if (index == 0) return const Color(0xFFEAB308); // Gold
    if (index == 1) return const Color(0xFF94A3B8); // Silver
    if (index == 2) return const Color(0xFFD97706); // Bronze
    return const Color(0xFF64748B);
  }

  String _rankBadge(int index) {
    if (index == 0) return '🥇';
    if (index == 1) return '🥈';
    if (index == 2) return '🥉';
    return '#${index + 1}';
  }

  @override
  Widget build(BuildContext context) {
    final currencyFormat = NumberFormat.currency(
      locale: 'en_IN',
      symbol: '₹ ',
      decimalDigits: 2,
    );

    final totalRevenue =
        _stats.fold<double>(0.0, (sum, s) => sum + s.totalRevenue);

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Top Selling Products',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
      body: Column(
        children: [
          // Filter Header
          Container(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Time Range Pills
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _timeChip('All Time', 'all'),
                      const SizedBox(width: 8),
                      _timeChip('This Month', 'month'),
                      const SizedBox(width: 8),
                      _timeChip('This Week', 'week'),
                      const SizedBox(width: 8),
                      _timeChip('Today', 'today'),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                // Sort by toggle
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Sort Products By:',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Colors.grey.shade700,
                      ),
                    ),
                    SegmentedButton<String>(
                      segments: const [
                        ButtonSegment(
                          value: 'quantity',
                          label: Text('Units Sold', style: TextStyle(fontSize: 11)),
                          icon: Icon(Icons.trending_up_rounded, size: 14),
                        ),
                        ButtonSegment(
                          value: 'revenue',
                          label: Text('Highest ₹', style: TextStyle(fontSize: 11)),
                          icon: Icon(Icons.currency_rupee_rounded, size: 14),
                        ),
                      ],
                      selected: {_sortBy},
                      onSelectionChanged: (val) {
                        setState(() => _sortBy = val.first);
                        _loadStats();
                      },
                      style: const ButtonStyle(
                        visualDensity: VisualDensity.compact,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Total Summary Ribbon
          if (!_loading && _stats.isNotEmpty)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              color: const Color(0xFFF0FDF4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  Column(
                    children: [
                      const Text(
                        'Top Products Ranked',
                        style: TextStyle(fontSize: 11, color: Color(0xFF166534)),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${_stats.length} product(s)',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w900,
                          color: Color(0xFF15803D),
                        ),
                      ),
                    ],
                  ),
                  Container(height: 24, width: 1, color: Colors.green.shade200),
                  Column(
                    children: [
                      const Text(
                        'Total Revenue Generated',
                        style: TextStyle(fontSize: 11, color: Color(0xFF166534)),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        currencyFormat.format(totalRevenue),
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w900,
                          color: Color(0xFF15803D),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

          // List of Top Products
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _stats.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.query_stats_rounded,
                                size: 54, color: Colors.grey.shade400),
                            const SizedBox(height: 12),
                            Text(
                              'No sales data found for this period',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                                color: Colors.grey.shade600,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'Completed orders will rank here automatically',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey.shade500,
                              ),
                            ),
                          ],
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 12),
                        itemCount: _stats.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (context, index) {
                          final item = _stats[index];
                          final avgPrice = item.totalQuantity > 0
                              ? item.totalRevenue / item.totalQuantity
                              : 0.0;

                          return Card(
                            elevation: 1,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                              side: BorderSide(
                                color: index < 3
                                    ? _rankColor(index).withValues(alpha: 0.5)
                                    : Colors.grey.shade200,
                                width: index < 3 ? 1.5 : 1.0,
                              ),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(14),
                              child: Row(
                                children: [
                                  // Rank Avatar
                                  Container(
                                    width: 38,
                                    height: 38,
                                    alignment: Alignment.center,
                                    decoration: BoxDecoration(
                                      color: _rankColor(index)
                                          .withValues(alpha: 0.12),
                                      shape: BoxShape.circle,
                                    ),
                                    child: Text(
                                      _rankBadge(index),
                                      style: TextStyle(
                                        fontSize: index < 3 ? 18 : 13,
                                        fontWeight: FontWeight.bold,
                                        color: _rankColor(index),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 14),

                                  // Name and Details
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          item.itemName,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 15,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        const SizedBox(height: 4),
                                        Row(
                                          children: [
                                            Text(
                                              '${item.orderCount} ${item.orderCount == 1 ? "order" : "orders"}',
                                              style: TextStyle(
                                                fontSize: 12,
                                                color: Colors.grey.shade600,
                                              ),
                                            ),
                                            if (avgPrice > 0) ...[
                                              Text(' • ',
                                                  style: TextStyle(
                                                      color: Colors.grey.shade400)),
                                              Text(
                                                'Avg: ₹${avgPrice.toStringAsFixed(1)}/${item.unit}',
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  color: Colors.grey.shade600,
                                                ),
                                              ),
                                            ],
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),

                                  // Right Stats: Qty and Revenue
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      Text(
                                        '${item.totalQuantity % 1 == 0 ? item.totalQuantity.toInt() : item.totalQuantity.toStringAsFixed(1)} ${item.unit}',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w900,
                                          fontSize: 14,
                                          color: Color(0xFF0F766E),
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        currencyFormat.format(item.totalRevenue),
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w700,
                                          color: Colors.grey.shade800,
                                        ),
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
        ],
      ),
    );
  }

  Widget _timeChip(String label, String value) {
    final isSelected = _timeRange == value;
    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (selected) {
        if (selected) {
          setState(() => _timeRange = value);
          _loadStats();
        }
      },
      selectedColor: const Color(0xFF0F766E),
      labelStyle: TextStyle(
        fontSize: 12,
        fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
        color: isSelected ? Colors.white : Colors.black87,
      ),
      visualDensity: VisualDensity.compact,
    );
  }
}
