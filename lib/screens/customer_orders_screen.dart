import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shop/models/customer.dart';
import 'package:shop/models/order.dart';
import 'package:shop/repositories/customer_repository.dart';
import 'package:shop/repositories/order_repository.dart';
import 'package:shop/repositories/product_repository.dart';
import 'package:shop/screens/order_details_screen.dart';
import 'package:shop/screens/product_selection_screen.dart';

class CustomerOrdersScreen extends StatefulWidget {
  const CustomerOrdersScreen({
    super.key,
    required this.customerId,
    required this.customerName,
    required this.customerRepository,
    required this.productRepository,
    required this.orderRepository,
  });

  final int customerId;
  final String customerName;
  final CustomerRepository customerRepository;
  final ProductRepository productRepository;
  final OrderRepository orderRepository;

  @override
  State<CustomerOrdersScreen> createState() => _CustomerOrdersScreenState();
}

class _CustomerOrdersScreenState extends State<CustomerOrdersScreen> {
  List<OrderSummary> _orders = <OrderSummary>[];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final orders = await widget.orderRepository
        .getCustomerOrderSummaries(widget.customerId);
    if (!mounted) return;
    setState(() {
      _orders = orders;
      _loading = false;
    });
  }

  Future<void> _createOrder() async {
    final Customer? customer =
        await widget.customerRepository.getCustomerById(widget.customerId);
    if (!mounted || customer == null) return;
    await Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => ProductSelectionScreen(
          customer: customer,
          productRepository: widget.productRepository,
          orderRepository: widget.orderRepository,
        ),
      ),
    );
    await _load();
  }

  Color _statusColor(OrderStatus status) {
    switch (status) {
      case OrderStatus.completed:
        return Colors.green;
      case OrderStatus.partiallyCompleted:
        return Colors.orange;
      case OrderStatus.pending:
        return Colors.red;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.customerName)),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _createOrder,
        icon: const Icon(Icons.add_shopping_cart),
        label: const Text('ADD ORDER'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _orders.isEmpty
              ? const Center(child: Text('No orders for this customer yet.'))
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: _orders.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final order = _orders[index];
                    return Card(
                      child: ListTile(
                        leading: CircleAvatar(child: Text('${index + 1}')),
                        title: Text(
                          DateFormat('dd MMM yyyy • hh:mm a')
                              .format(order.createdAt),
                        ),
                        subtitle: Text(
                          '${order.totalItems} items • ${order.pendingCount} pending',
                        ),
                        trailing: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: <Widget>[
                            Text(
                              orderStatusLabel(order.status),
                              style: TextStyle(
                                color: _statusColor(order.status),
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 4),
                            const Text('EDIT'),
                          ],
                        ),
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
                          await _load();
                        },
                      ),
                    );
                  },
                ),
    );
  }
}
