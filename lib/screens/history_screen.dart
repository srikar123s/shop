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
    return DateFormat('dd MMM yyyy').format(dt).toUpperCase();
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
                SnackBar(content: Text('${s.t('backupCreatedAt')} $path')),
              );
            },
            icon: const Icon(Icons.backup),
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
                  SnackBar(content: Text(s.t('restoreComplete'))),
                );
              }
            },
            icon: const Icon(Icons.restore),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: <Widget>[
            TextField(
              controller: _searchController,
              decoration: InputDecoration(
                labelText: s.t('searchCustomer'),
                suffixIcon: IconButton(
                    onPressed: _load, icon: const Icon(Icons.search)),
              ),
              onChanged: (_) => _load(),
            ),
            const SizedBox(height: 10),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : ListView.builder(
                      itemCount: customers.length,
                      itemBuilder: (context, index) {
                        final orders = customers[index].value;
                        final latest = orders.first;
                        return Card(
                          child: ListTile(
                            leading: CircleAvatar(
                                child: Text(latest.customerName
                                    .substring(0, 1)
                                    .toUpperCase())),
                            title: Text(latest.customerName),
                            subtitle: Text(
                                '${orders.length} orders • Last: ${_dateHeading(latest.createdAt, s)}'),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () async {
                              await Navigator.push(
                                context,
                                MaterialPageRoute<void>(
                                  builder: (_) => CustomerOrdersScreen(
                                    customerId: latest.customerId,
                                    customerName: latest.customerName,
                                    customerRepository:
                                        widget.customerRepository,
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
