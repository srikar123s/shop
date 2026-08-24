import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shop/l10n/app_localizations.dart';
import 'package:shop/models/order.dart';
import 'package:shop/repositories/order_repository.dart';
import 'package:shop/repositories/customer_repository.dart';
import 'package:shop/repositories/product_repository.dart';
import 'package:shop/screens/customer_orders_screen.dart';
import 'package:shop/services/backup_service.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({
    super.key,
    required this.orderRepository,
    required this.backupService,
    required this.customerRepository,
    required this.productRepository,
  });

  final OrderRepository orderRepository;
  final BackupService backupService;
  final CustomerRepository customerRepository;
  final ProductRepository productRepository;

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  final TextEditingController _searchController = TextEditingController();
  List<OrderSummary> _orders = <OrderSummary>[];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final data = await widget.orderRepository
        .searchOrderSummaries(_searchController.text);
    if (!mounted) return;
    setState(() {
      _orders = data;
      _loading = false;
    });
  }

  String _dateHeading(DateTime dt, AppLocalizations s) {
    final now = DateTime.now();
    final dayStart = DateTime(now.year, now.month, now.day);
    final orderDay = DateTime(dt.year, dt.month, dt.day);
    final diff = dayStart.difference(orderDay).inDays;
    if (diff == 0) return s.t('today');
    if (diff == 1) return s.t('yesterday');
    return DateFormat('dd MMM yyyy').format(dt);
  }

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context);
    final groupedOrders = <int, List<OrderSummary>>{};
    for (final order in _orders) {
      groupedOrders
          .putIfAbsent(order.customerId, () => <OrderSummary>[])
          .add(order);
    }
    final customers = groupedOrders.entries.toList()
      ..sort(
          (a, b) => b.value.first.createdAt.compareTo(a.value.first.createdAt));

    return Scaffold(
      appBar: AppBar(
        title: Text(s.t('historyTitle')),
        actions: <Widget>[
          IconButton(
            tooltip: s.t('backup'),
            onPressed: () async {
              final path = await widget.backupService.createBackup();
              if (!context.mounted) {
                return;
              }
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('${s.t('backupCreatedAt')} $path'),
                  duration: const Duration(seconds: 3),
                ),
              );
            },
            icon: const Icon(Icons.backup_outlined),
          ),
          IconButton(
            tooltip: s.t('restore'),
            onPressed: () async {
              final restored = await widget.backupService.restoreBackup();
              if (!context.mounted) {
                return;
              }
              if (restored) {
                await _load();
                if (!context.mounted) {
                  return;
                }
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(s.t('restoreComplete')),
                    duration: const Duration(seconds: 3),
                  ),
                );
              }
            },

            icon: const Icon(Icons.restore_outlined),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: <Widget>[
            TextField(
              controller: _searchController,
              decoration: InputDecoration(
                labelText: s.t('searchCustomer'),
                prefixIcon: const Icon(Icons.search),
                suffixIcon: IconButton(
                    onPressed: _load, icon: const Icon(Icons.clear)),
              ),
              onChanged: (_) => _load(),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : customers.isEmpty
                      ? const Center(child: Text('No order history found'))
                      : ListView.separated(
                          itemCount: customers.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 10),
                          itemBuilder: (context, index) {
                            final orders = customers[index].value;
                            final latest = orders.first;
                            final pendingOrders = orders.where((o) => o.status == OrderStatus.pending || o.status == OrderStatus.partiallyCompleted).length;

                            return Card(
                              elevation: 1,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                              child: ListTile(
                                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                leading: CircleAvatar(
                                  radius: 22,
                                  backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                                  child: Text(
                                    latest.customerName.isNotEmpty ? latest.customerName[0].toUpperCase() : 'C',
                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                                  ),
                                ),
                                title: Text(
                                  latest.customerName,
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                                ),
                                subtitle: Padding(
                                  padding: const EdgeInsets.only(top: 4),
                                  child: Text(
                                    '${orders.length} ${orders.length == 1 ? 'order' : 'orders'} • Last: ${_dateHeading(latest.createdAt, s)}',
                                    style: TextStyle(color: Colors.grey.shade700, fontSize: 13),
                                  ),
                                ),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (pendingOrders > 0)
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: Colors.deepOrange.shade100,
                                          borderRadius: BorderRadius.circular(12),
                                        ),
                                        child: Text(
                                          '$pendingOrders pending',
                                          style: TextStyle(
                                            color: Colors.deepOrange.shade900,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 11,
                                          ),
                                        ),
                                      ),
                                    const SizedBox(width: 6),
                                    const Icon(Icons.chevron_right, color: Colors.grey),
                                  ],
                                ),
                                onTap: () async {
                                  await Navigator.push(
                                    context,
                                    MaterialPageRoute<void>(
                                      builder: (_) => CustomerOrdersScreen(
                                        customerId: latest.customerId,
                                        customerName: latest.customerName,
                                        customerRepository: widget.customerRepository,
                                        productRepository: widget.productRepository,
                                        orderRepository: widget.orderRepository,
                                      ),
                                    ),
                                  );
                                  await _load();
                                },
                              ),
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }
}
