import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shop/models/order.dart';
import 'package:shop/services/invoice_pdf_service.dart';
import 'package:shop/services/share_service.dart';
import 'package:shop/services/shop_customization_service.dart';

/// Clean, simple Order Packing Preview / Slip designed for shop staff
/// to pick and pack goods without confusing financial or procurement controls.
class OrderPackingSlipScreen extends StatefulWidget {
  const OrderPackingSlipScreen({
    super.key,
    required this.details,
    this.customerBillNumber,
  });

  final OrderDetails details;
  final int? customerBillNumber;

  @override
  State<OrderPackingSlipScreen> createState() => _OrderPackingSlipScreenState();
}

class _OrderPackingSlipScreenState extends State<OrderPackingSlipScreen> {
  late final Set<int> _packedItemIndices;

  @override
  void initState() {
    super.initState();
    _packedItemIndices = <int>{};
    // Pre-check items that have already been marked given
    for (int i = 0; i < widget.details.items.length; i++) {
      final item = widget.details.items[i];
      if (item.quantityGiven >= item.quantityOrdered && item.quantityOrdered > 0) {
        _packedItemIndices.add(i);
      }
    }
  }

  void _togglePacked(int index) {
    setState(() {
      if (_packedItemIndices.contains(index)) {
        _packedItemIndices.remove(index);
      } else {
        _packedItemIndices.add(index);
      }
    });
  }

  void _toggleAll() {
    setState(() {
      if (_packedItemIndices.length == widget.details.items.length) {
        _packedItemIndices.clear();
      } else {
        _packedItemIndices.addAll(List.generate(widget.details.items.length, (i) => i));
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final order = widget.details.order;
    final items = widget.details.items;
    final totalItems = items.length;
    final packedCount = _packedItemIndices.length;
    final allPacked = totalItems > 0 && packedCount == totalItems;
    final shopName = ShopCustomizationService.instance.shopName;

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '📦 Packing Slip • ${widget.customerBillNumber != null ? "Bill #${widget.customerBillNumber}" : order.formattedOrderId}',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            Text(
              order.customerNameSnapshot,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.normal),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Print Packing Challan',
            icon: const Icon(Icons.print_outlined),
            onPressed: () async {
              await InvoicePdfService.instance.printReceipt(
                widget.details,
                isDeliveryChallan: true,
                customerBillNumber: widget.customerBillNumber,
              );
            },
          ),
          IconButton(
            tooltip: 'Share Packing Slip',
            icon: const Icon(Icons.share_outlined),
            onPressed: () async {
              await ShareService.shareOrderDetails(
                widget.details,
                customerBillNumber: widget.customerBillNumber,
              );
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // Header Card
          Container(
            width: double.infinity,
            margin: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFE2E8F0)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.03),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      shopName,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                        color: Color(0xFF0F766E),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: allPacked ? const Color(0xFFDCFCE7) : const Color(0xFFFEF3C7),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: allPacked ? const Color(0xFF16A34A) : const Color(0xFFD97706),
                          width: 1,
                        ),
                      ),
                      child: Text(
                        allPacked ? 'ALL PACKED ✓' : '$packedCount of $totalItems PACKED',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: allPacked ? const Color(0xFF15803D) : const Color(0xFFB45309),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  'Customer: ${order.customerNameSnapshot}${(order.customerPhone != null && order.customerPhone!.isNotEmpty) ? " • ${order.customerPhone}" : ""}',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF1E293B),
                  ),
                ),
                Text(
                  'Order Date: ${DateFormat("dd MMM yyyy, hh:mm a").format(order.createdAt)}',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
                const SizedBox(height: 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    value: totalItems > 0 ? (packedCount / totalItems) : 0.0,
                    minHeight: 7,
                    backgroundColor: Colors.grey.shade200,
                    color: allPacked ? const Color(0xFF16A34A) : const Color(0xFF0F766E),
                  ),
                ),
              ],
            ),
          ),

          // Packing Table Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
            child: Row(
              children: [
                const Expanded(
                  flex: 5,
                  child: Text(
                    'ITEM & DETAILS',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 11.5,
                      color: Color(0xFF64748B),
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
                const Expanded(
                  flex: 3,
                  child: Text(
                    'QTY TO PACK',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 11.5,
                      color: Color(0xFF64748B),
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: InkWell(
                    onTap: _toggleAll,
                    child: Text(
                      allPacked ? 'CLEAR' : 'PACK ALL',
                      textAlign: TextAlign.right,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 11,
                        color: Color(0xFF0F766E),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Item Packing List
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
              itemCount: items.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final item = items[index];
                final isPacked = _packedItemIndices.contains(index);

                // Build options text
                final seenOpts = <String>{};
                final distinctOpts = <String>[];
                for (final e in item.options) {
                  final k = '${e.optionName.trim().toLowerCase()}:${e.optionValue.trim().toLowerCase()}';
                  if (e.optionName.trim().isNotEmpty && seenOpts.add(k)) {
                    distinctOpts.add('${e.optionName}: ${e.optionValue}');
                  }
                }
                final optsStr = distinctOpts.join(' • ');

                final orderedQty = item.quantityOrdered;
                final formattedQty = orderedQty % 1 == 0
                    ? orderedQty.toInt().toString()
                    : orderedQty.toString();

                return Card(
                  elevation: isPacked ? 0 : 1,
                  color: isPacked ? const Color(0xFFF0FDF4) : Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(
                      color: isPacked ? const Color(0xFF86EFAC) : const Color(0xFFE2E8F0),
                      width: isPacked ? 1.5 : 1,
                    ),
                  ),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () => _togglePacked(index),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Row(
                        children: [
                          // Item Name & Options
                          Expanded(
                            flex: 5,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  item.itemName,
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 15,
                                    color: isPacked ? const Color(0xFF15803D) : const Color(0xFF1E293B),
                                    decoration: isPacked ? TextDecoration.lineThrough : null,
                                  ),
                                ),
                                if (optsStr.isNotEmpty) ...[
                                  const SizedBox(height: 3),
                                  Text(
                                    optsStr,
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: isPacked ? const Color(0xFF16A34A) : const Color(0xFF64748B),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),

                          // Quantity to pack
                          Expanded(
                            flex: 3,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              decoration: BoxDecoration(
                                color: isPacked ? const Color(0xFFDCFCE7) : const Color(0xFFF1F5F9),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                '$formattedQty ${item.unit}',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontWeight: FontWeight.w900,
                                  fontSize: 15,
                                  color: isPacked ? const Color(0xFF15803D) : const Color(0xFF0F172A),
                                ),
                              ),
                            ),
                          ),

                          // Checkbox Indicator
                          Expanded(
                            flex: 2,
                            child: Align(
                              alignment: Alignment.centerRight,
                              child: Checkbox(
                                value: isPacked,
                                activeColor: const Color(0xFF16A34A),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(5),
                                ),
                                onChanged: (_) => _togglePacked(index),
                              ),
                            ),
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
