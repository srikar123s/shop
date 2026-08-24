import 'package:flutter/material.dart';
import 'package:shop/l10n/app_localizations.dart';
import 'package:intl/intl.dart';
import 'package:shop/models/order.dart';
import 'package:shop/repositories/customer_repository.dart';
import 'package:shop/repositories/order_repository.dart';
import 'package:shop/repositories/product_repository.dart';
import 'package:shop/screens/customer_screen.dart';
import 'package:shop/screens/history_screen.dart';
import 'package:shop/screens/order_details_screen.dart';
import 'package:shop/screens/shop_settings_screen.dart';
import 'package:shop/services/backup_service.dart';
import 'package:shop/widgets/large_action_button.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    required this.customerRepository,
    required this.productRepository,
    required this.orderRepository,
    required this.backupService,
    required this.locale,
    required this.onLocaleChanged,
  });

  final CustomerRepository customerRepository;
  final ProductRepository productRepository;
  final OrderRepository orderRepository;
  final BackupService backupService;
  final Locale locale;
  final ValueChanged<Locale> onLocaleChanged;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  Color _statusColor(OrderStatus status) {
    switch (status) {
      case OrderStatus.completed:
        return Colors.green;
      case OrderStatus.partiallyCompleted:
        return Colors.orange;
      case OrderStatus.pending:
        return Colors.red;
      case OrderStatus.closed:
        return Colors.blueGrey;
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(s.t('appTitle')),
        centerTitle: true,
        actions: <Widget>[
          IconButton(
            tooltip: s.t('shopSettings'),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => ShopSettingsScreen(
                    productRepository: widget.productRepository,
                    locale: widget.locale,
                    onLocaleChanged: widget.onLocaleChanged,
                  ),
                ),
              );
            },
            icon: const Icon(Icons.settings),
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Text(
                s.t('appTitle'),
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 8),
              const Text('Fast, simple order management'),
              const SizedBox(height: 32),
              LargeActionButton(
                label: s.t('createOrder'),
                onTap: () async {
                  await Navigator.push(
                    context,
                    MaterialPageRoute<void>(
                      builder: (_) => CustomerScreen(
                        customerRepository: widget.customerRepository,
                        productRepository: widget.productRepository,
                        orderRepository: widget.orderRepository,
                      ),
                    ),
                  );
                  setState(() {});
                },
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'RECENT ORDERS',
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                  TextButton(
                    onPressed: () async {
                      await Navigator.push(
                        context,
                        MaterialPageRoute<void>(
                          builder: (_) => HistoryScreen(
                            orderRepository: widget.orderRepository,
                            backupService: widget.backupService,
                            customerRepository: widget.customerRepository,
                            productRepository: widget.productRepository,
                          ),
                        ),
                      );
                      setState(() {});
                    },
                    child: const Text('View All'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 140,
                child: FutureBuilder<List<OrderSummary>>(
                  future: widget.orderRepository.searchOrderSummaries(''),
                  builder: (context, snapshot) {
                    final orders = snapshot.data?.take(5).toList() ??
                        <OrderSummary>[];
                    if (orders.isEmpty) {
                      return const Center(child: Text('No recent orders'));
                    }
                    return ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: orders.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 10),
                      itemBuilder: (context, index) {
                        final order = orders[index];
                        return SizedBox(
                          width: 230,
                          child: Card(
                            child: InkWell(
                              borderRadius: BorderRadius.circular(12),
                              onTap: () async {
                                await Navigator.push(
                                  context,
                                  MaterialPageRoute<void>(
                                    builder: (_) => OrderDetailsScreen(
                                      orderId: order.orderId,
                                      orderRepository: widget.orderRepository,
                                      customerRepository: widget.customerRepository,
                                      productRepository: widget.productRepository,
                                    ),
                                  ),
                                );
                                setState(() {});
                              },
                              child: Padding(
                                padding: const EdgeInsets.all(12),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Text(
                                          order.formattedOrderId,
                                          style: const TextStyle(
                                              fontWeight: FontWeight.w800,
                                              fontSize: 14),
                                        ),
                                        Text(
                                          orderStatusLabel(order.status),
                                          style: TextStyle(
                                            color: _statusColor(order.status),
                                            fontSize: 11,
                                            fontWeight: FontWeight.w800,
                                          ),
                                        ),
                                      ],
                                    ),
                                    Text(
                                      order.customerName,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 15),
                                    ),
                                    Text(
                                      '${DateFormat('dd MMM, hh:mm a').format(order.createdAt)}\n${order.totalItems} items${order.estimateTotal > 0 ? " • ₹${order.estimateTotal.toStringAsFixed(2)}" : ""}',
                                      style: TextStyle(
                                          fontSize: 12, color: Colors.grey.shade700),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
              const SizedBox(height: 24),
              LargeActionButton(
                label: s.t('history'),
                onTap: () async {
                  await Navigator.push(
                    context,
                    MaterialPageRoute<void>(
                      builder: (_) => HistoryScreen(
                        orderRepository: widget.orderRepository,
                        backupService: widget.backupService,
                        customerRepository: widget.customerRepository,
                        productRepository: widget.productRepository,
                      ),
                    ),
                  );
                  setState(() {});
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
