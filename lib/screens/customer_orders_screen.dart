import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shop/models/customer.dart';
import 'package:shop/models/order.dart';
import 'package:shop/repositories/customer_repository.dart';
import 'package:shop/repositories/order_repository.dart';
import 'package:shop/repositories/product_repository.dart';
import 'package:shop/screens/order_details_screen.dart';
import 'package:shop/screens/product_selection_screen.dart';
import 'package:shop/services/share_service.dart';

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

  Future<void> _closeSingleOrder(OrderSummary order) async {
    final details = await widget.orderRepository.getOrderDetails(order.orderId);
    if (details == null || !mounted) return;

    final unfulfilled = details.items
        .where((i) => i.quantityGiven < i.quantityOrdered)
        .toList();

    if (unfulfilled.isEmpty) {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('Complete ${order.formattedOrderId}?'),
          content: Text(
            'All ${details.items.length} item(s) have been delivered. Mark this order as completed?',
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('CANCEL'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('COMPLETE ORDER'),
            ),
          ],
        ),
      );
      if (confirm == true && mounted) {
        await widget.orderRepository.closeOrderWithAllGiven(order.orderId);
        await _load();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('${order.formattedOrderId} marked as completed.'),
              backgroundColor: Colors.teal,
            ),
          );
        }
      }
      return;
    }

    // Has unfulfilled items!
    final orderedSubtotal = details.items.fold<double>(
      0,
      (s, i) => s + (i.unitPrice * i.quantityOrdered),
    );
    final deliveredSubtotal = details.items.fold<double>(
      0,
      (s, i) => s + (i.unitPrice * i.quantityGiven),
    );

    final existingBreakdown = details.order.billBreakdown;
    final deliveredBreakdown = existingBreakdown != null
        ? BillBreakdown.calculate(
            subtotal: deliveredSubtotal,
            applyGst: existingBreakdown.applyGst,
            gstRate: existingBreakdown.gstRate,
            otherCharges: existingBreakdown.otherCharges,
          )
        : BillBreakdown.calculate(subtotal: deliveredSubtotal);

    final fullBreakdown = existingBreakdown != null
        ? BillBreakdown.calculate(
            subtotal: orderedSubtotal,
            applyGst: existingBreakdown.applyGst,
            gstRate: existingBreakdown.gstRate,
            otherCharges: existingBreakdown.otherCharges,
          )
        : BillBreakdown.calculate(subtotal: orderedSubtotal);

    final choice = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
        contentPadding: const EdgeInsets.symmetric(horizontal: 20),
        actionsPadding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.orange.shade100,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(Icons.warning_amber_rounded,
                  color: Colors.orange.shade900, size: 24),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Order ${order.formattedOrderId}',
                    style: const TextStyle(
                        fontSize: 17, fontWeight: FontWeight.bold),
                  ),
                  Text(
                    '${unfulfilled.length} item(s) not fully given',
                    style: TextStyle(
                        fontSize: 12,
                        color: Colors.deepOrange.shade800,
                        fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade50,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey.shade300),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Items not given / partially given:',
                        style: TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                      const SizedBox(height: 8),
                      ...unfulfilled.map((item) {
                        final pending =
                            item.quantityOrdered - item.quantityGiven;
                        final ordStr = item.quantityOrdered % 1 == 0
                            ? item.quantityOrdered.toInt().toString()
                            : item.quantityOrdered.toString();
                        final gvnStr = item.quantityGiven % 1 == 0
                            ? item.quantityGiven.toInt().toString()
                            : item.quantityGiven.toString();
                        final pndStr = pending % 1 == 0
                            ? pending.toInt().toString()
                            : pending.toString();
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('• ',
                                  style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: Colors.red)),
                              Expanded(
                                child: Text(
                                  item.itemName,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 13),
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.red.shade50,
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(
                                      color: Colors.red.shade200),
                                ),
                                child: Text(
                                  'Given $gvnStr of $ordStr ($pndStr not given)',
                                  style: TextStyle(
                                      fontSize: 11,
                                      color: Colors.red.shade900,
                                      fontWeight: FontWeight.w700),
                                ),
                              ),
                            ],
                          ),
                        );
                      }),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                // Price Comparison Box
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Theme.of(context)
                        .colorScheme
                        .primaryContainer
                        .withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: Theme.of(context)
                            .colorScheme
                            .primary
                            .withValues(alpha: 0.3)),
                  ),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Delivered Items Value:'),
                          Text(
                            '₹ ${deliveredBreakdown.grandTotal.toStringAsFixed(2)}',
                            style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Colors.teal,
                                fontSize: 14),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Original Ordered Value:'),
                          Text(
                            '₹ ${fullBreakdown.grandTotal.toStringAsFixed(2)}',
                            style: TextStyle(
                                color: Colors.grey.shade700,
                                decoration: TextDecoration.lineThrough,
                                fontSize: 13),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'How would you like to close this order?',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                ),
              ],
            ),
          ),
        ),
        actions: [
          Row(
            children: [
              TextButton(
                onPressed: () => Navigator.pop(context, 'details'),
                child: const Text('OPEN DETAILS'),
              ),
              const Spacer(),
              TextButton(
                onPressed: () => Navigator.pop(context, 'cancel'),
                child: const Text('CANCEL'),
              ),
            ],
          ),
          const SizedBox(height: 6),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              icon: const Icon(Icons.done_all, size: 18),
              label: Text(
                'Deliver All Remaining Items (₹${fullBreakdown.grandTotal.toStringAsFixed(2)}) & Close',
                textAlign: TextAlign.center,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              onPressed: () => Navigator.pop(context, 'all_given'),
            ),
          ),
          const SizedBox(height: 6),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF0F766E)),
              icon: const Icon(Icons.receipt_long, size: 18),
              label: Text(
                'Adjust Bill for Given Items (₹${deliveredBreakdown.grandTotal.toStringAsFixed(2)}) & Close',
                textAlign: TextAlign.center,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              onPressed: () => Navigator.pop(context, 'delivered_only'),
            ),
          ),
        ],
      ),
    );

    if (!mounted || choice == null || choice == 'cancel') return;

    if (choice == 'details') {
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
      return;
    }

    if (choice == 'delivered_only') {
      await widget.orderRepository.closeOrderWithDeliveredItemsOnly(
        orderId: order.orderId,
      );
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${order.formattedOrderId} closed. Bill adjusted to ₹${deliveredBreakdown.grandTotal.toStringAsFixed(2)} with partial items note.',
            ),
            backgroundColor: Colors.teal,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } else if (choice == 'all_given') {
      await widget.orderRepository.closeOrderWithAllGiven(order.orderId);
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                '${order.formattedOrderId} marked fully delivered & completed.'),
            backgroundColor: Colors.teal,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  Color _statusColor(OrderStatus status) {
    switch (status) {
      case OrderStatus.completed:
        return Colors.teal;
      case OrderStatus.partiallyCompleted:
        return Colors.orange.shade800;
      case OrderStatus.pending:
        return Colors.red.shade700;
      case OrderStatus.closed:
        return Colors.blueGrey.shade700;
    }
  }

  Color _statusBgColor(OrderStatus status) {
    switch (status) {
      case OrderStatus.completed:
        return Colors.teal.shade50;
      case OrderStatus.partiallyCompleted:
        return Colors.orange.shade50;
      case OrderStatus.pending:
        return Colors.red.shade50;
      case OrderStatus.closed:
        return Colors.blueGrey.shade50;
    }
  }

  @override
  Widget build(BuildContext context) {
    final pendingCount = _orders.where((o) => o.status == OrderStatus.pending || o.status == OrderStatus.partiallyCompleted).length;
    final completedCount = _orders.where((o) => o.status == OrderStatus.completed).length;
    final totalEstimateSum = _orders.fold<double>(0, (sum, o) => sum + o.estimateTotal);

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.customerName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
            Text('${_orders.length} total orders', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.normal)),
          ],
        ),
        actions: <Widget>[
          if (pendingCount > 0)
            IconButton(
              tooltip: 'Close all pending orders',
              icon: const Icon(Icons.archive_outlined),
              onPressed: () async {
                final choice = await showDialog<String>(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text('Close all pending orders?'),
                    content: const Text(
                      'If any orders have items not fully given, how would you like to close them?',
                    ),
                    actions: <Widget>[
                      TextButton(
                        onPressed: () => Navigator.pop(context, 'cancel'),
                        child: const Text('CANCEL'),
                      ),
                      OutlinedButton(
                        onPressed: () => Navigator.pop(context, 'all_given'),
                        child: const Text('MARK ALL GIVEN (FULL BILL)'),
                      ),
                      FilledButton(
                        style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xFF0F766E)),
                        onPressed: () =>
                            Navigator.pop(context, 'delivered_only'),
                        child: const Text('ADJUST BILLS TO GIVEN ITEMS'),
                      ),
                    ],
                  ),
                );
                if (choice == null || choice == 'cancel' || !context.mounted) {
                  return;
                }
                await widget.orderRepository.closePendingOrdersForCustomer(
                  widget.customerId,
                  adjustToGivenOnly: choice == 'delivered_only',
                );
                if (!context.mounted) return;
                await _load();
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(choice == 'delivered_only'
                        ? 'All pending orders closed with bills adjusted for delivered items.'
                        : 'All pending orders marked fully completed.'),
                    backgroundColor: Colors.teal,
                    duration: const Duration(seconds: 3),
                  ),
                );
              },
            ),

        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _createOrder,
        icon: const Icon(Icons.add_shopping_cart),
        label: const Text('NEW ORDER'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _orders.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.receipt_long_outlined, size: 64, color: Colors.grey.shade400),
                      const SizedBox(height: 12),
                      Text('No orders for ${widget.customerName} yet.', style: TextStyle(color: Colors.grey.shade600, fontSize: 16)),
                      const SizedBox(height: 16),
                      FilledButton.icon(
                        onPressed: _createOrder,
                        icon: const Icon(Icons.add),
                        label: const Text('Create First Order'),
                      ),
                    ],
                  ),
                )
              : Column(
                  children: [
                    // Top Summary Card
                    Container(
                      margin: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [Theme.of(context).colorScheme.primaryContainer, Theme.of(context).colorScheme.surfaceContainerHighest],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          _MetricStat(label: 'Total Orders', value: '${_orders.length}', color: Colors.blue.shade900),
                          _MetricStat(label: 'Pending', value: '$pendingCount', color: Colors.deepOrange.shade800),
                          _MetricStat(label: 'Completed', value: '$completedCount', color: Colors.teal.shade800),
                          if (totalEstimateSum > 0)
                            _MetricStat(label: 'Total Value', value: '₹${totalEstimateSum.toStringAsFixed(0)}', color: Colors.purple.shade900),
                        ],
                      ),
                    ),
                    Expanded(
                      child: ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 80),
                        itemCount: _orders.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 12),
                        itemBuilder: (context, index) {
                          final order = _orders[index];
                          final isPending = order.status == OrderStatus.pending ||
                              order.status == OrderStatus.partiallyCompleted;
                          final deliveredItems = order.totalItems - order.pendingCount;
                          final progress = order.totalItems > 0 ? (deliveredItems / order.totalItems) : 0.0;

                          return Card(
                            elevation: 1.5,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(16),
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
                              child: Padding(
                                padding: const EdgeInsets.all(16),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 10, vertical: 4),
                                          decoration: BoxDecoration(
                                            color: Theme.of(context)
                                                .colorScheme
                                                .primaryContainer
                                                .withValues(alpha: 0.6),
                                            borderRadius:
                                                BorderRadius.circular(8),
                                          ),
                                          child: Text(
                                            order.formattedOrderId,
                                            style: TextStyle(
                                              fontWeight: FontWeight.w800,
                                              fontSize: 13,
                                              color: Theme.of(context)
                                                  .colorScheme
                                                  .primary,
                                            ),
                                          ),
                                        ),
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 10, vertical: 4),
                                          decoration: BoxDecoration(
                                            color: _statusBgColor(order.status),
                                            borderRadius:
                                                BorderRadius.circular(20),
                                            border: Border.all(
                                                color: _statusColor(order.status)
                                                    .withValues(alpha: 0.5)),
                                          ),
                                          child: Text(
                                            orderStatusLabel(order.status),
                                            style: TextStyle(
                                              color: _statusColor(order.status),
                                              fontSize: 11,
                                              fontWeight: FontWeight.w800,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      DateFormat('dd MMM yyyy, hh:mm a')
                                          .format(order.createdAt),
                                      style: TextStyle(
                                          color: Colors.grey.shade600,
                                          fontSize: 12),
                                    ),
                                    const SizedBox(height: 10),
                                    // Progress bar
                                    Row(
                                      children: [
                                        Expanded(
                                          child: ClipRRect(
                                            borderRadius:
                                                BorderRadius.circular(6),
                                            child: LinearProgressIndicator(
                                              value: progress,
                                              minHeight: 8,
                                              backgroundColor:
                                                  Colors.grey.shade200,
                                              color: _statusColor(order.status),
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        Text(
                                          '$deliveredItems / ${order.totalItems} given',
                                          style: const TextStyle(
                                              fontWeight: FontWeight.w700,
                                              fontSize: 12),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 10),
                                    Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        Expanded(
                                          child: Text(
                                            order.estimateTotal > 0
                                                ? 'Total: ₹${order.estimateTotal.toStringAsFixed(2)}'
                                                : '${order.totalItems} items total',
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                                fontWeight: FontWeight.bold,
                                                fontSize: 14),
                                          ),
                                        ),
                                        Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            if (isPending)
                                              TextButton.icon(
                                                style: TextButton.styleFrom(
                                                  foregroundColor:
                                                      Colors.deepOrange,
                                                  visualDensity:
                                                      VisualDensity.compact,
                                                  padding:
                                                      const EdgeInsets.symmetric(
                                                          horizontal: 6),
                                                ),
                                                icon: const Icon(
                                                    Icons.check_circle_outline,
                                                    size: 16),
                                                label: const Text('Close',
                                                    style: TextStyle(
                                                        fontSize: 12)),
                                                onPressed: () =>
                                                    _closeSingleOrder(order),
                                              ),
                                            IconButton(
                                              tooltip: 'Share Estimate',
                                              icon: const Icon(Icons.share,
                                                  size: 18),
                                              visualDensity:
                                                  VisualDensity.compact,
                                              onPressed: () async {
                                                final details = await widget
                                                    .orderRepository
                                                    .getOrderDetails(
                                                        order.orderId);
                                                if (details != null) {
                                                  ShareService.shareOrderDetails(details);
                                                }
                                              },
                                            ),
                                            const Icon(Icons.chevron_right, size: 20, color: Colors.grey),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
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

class _MetricStat extends StatelessWidget {
  const _MetricStat({required this.label, required this.value, required this.color});

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(value, style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18, color: color)),
        const SizedBox(height: 2),
        Text(label, style: TextStyle(fontSize: 11, color: Colors.grey.shade700, fontWeight: FontWeight.w600)),
      ],
    );
  }
}
