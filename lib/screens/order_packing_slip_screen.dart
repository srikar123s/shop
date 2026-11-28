import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shop/l10n/app_localizations.dart';
import 'package:shop/models/order.dart';
import 'package:shop/repositories/delivery_repository.dart';
import 'package:shop/services/invoice_pdf_service.dart';
import 'package:shop/services/shop_customization_service.dart';

/// Clean, simple Order Packing Preview / Slip designed for shop partners and counters
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
  final DeliveryRepository _deliveryRepo = DeliveryRepository();
  late int _boxCount;
  String? _deliveryPartnerName;

  @override
  void initState() {
    super.initState();
    _packedItemIndices = <int>{};
    _boxCount = widget.details.order.boxCount;
    _deliveryPartnerName = widget.details.order.deliveryPartnerName;
    // Pre-check items that have already been marked given
    for (int i = 0; i < widget.details.items.length; i++) {
      final item = widget.details.items[i];
      if (item.quantityGiven >= item.quantityOrdered && item.quantityOrdered > 0) {
        _packedItemIndices.add(i);
      }
    }
    _restorePackingProgress();
  }

  String? get _packingPrefKey {
    final oid = widget.details.order.id;
    return oid == null ? null : 'packing_progress_order_$oid';
  }

  Future<void> _restorePackingProgress() async {
    final key = _packingPrefKey;
    if (key == null) return;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(key);
    if (raw == null || raw.isEmpty || !mounted) return;
    try {
      final saved = (jsonDecode(raw) as List<dynamic>)
          .map((e) => (e as num).toInt())
          .where((idx) => idx >= 0 && idx < widget.details.items.length)
          .toSet();
      setState(() {
        _packedItemIndices.addAll(saved);
      });
    } catch (_) {}
  }

  Future<void> _persistPackingProgress() async {
    final key = _packingPrefKey;
    if (key == null) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(key, jsonEncode(_packedItemIndices.toList()..sort()));
  }

  Future<void> _updateBoxCount(int next) async {
    final clamped = next < 0 ? 0 : next;
    setState(() => _boxCount = clamped);
    final orderId = widget.details.order.id;
    if (orderId != null) {
      await _deliveryRepo.updateOrderDeliveryInfo(
        orderId: orderId,
        boxCount: clamped,
      );
    }
  }

  Future<void> _pickDeliveryPartner() async {
    final s = AppLocalizations.of(context);
    final partners = await _deliveryRepo.getPartnersWithSummary();
    if (!mounted) return;
    final ctrl = TextEditingController(text: _deliveryPartnerName ?? '');
    final chosen = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(s.t('assignDeliveryPartner')),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (partners.isNotEmpty) ...[
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: partners.map((p) {
                    return ActionChip(
                      avatar: const Icon(Icons.local_shipping_outlined, size: 16),
                      label: Text(p.name),
                      onPressed: () => Navigator.pop(ctx, p.name),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 12),
              ],
              TextField(
                controller: ctrl,
                textCapitalization: TextCapitalization.words,
                decoration: InputDecoration(
                  labelText: s.t('deliveryPartnerLabel'),
                  hintText: 'e.g. Raju Auto',
                  border: const OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(s.t('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: Text(s.t('save')),
          ),
        ],
      ),
    );
    ctrl.dispose();
    if (chosen != null && chosen.isNotEmpty) {
      setState(() => _deliveryPartnerName = chosen);
      final orderId = widget.details.order.id;
      if (orderId != null) {
        await _deliveryRepo.updateOrderDeliveryInfo(
          orderId: orderId,
          deliveryPartnerName: chosen,
        );
      }
    }
  }

  Future<void> _shareBoxLabels() async {
    final order = widget.details.order;
    final billLabel = widget.customerBillNumber != null
        ? 'Bill #${widget.customerBillNumber}'
        : order.formattedOrderId;
    final count = _boxCount > 0 ? _boxCount : 1;
    final buf = StringBuffer()
      ..writeln('📦 *${order.customerNameSnapshot}* ($billLabel)')
      ..writeln('Total Boxes: $count');
    if (_deliveryPartnerName != null && _deliveryPartnerName!.isNotEmpty) {
      buf.writeln('Delivery: $_deliveryPartnerName');
    }
    for (var i = 1; i <= count; i++) {
      buf.writeln('• ${order.customerNameSnapshot} — Box $i / $count');
    }
    await Share.share(buf.toString());
  }

  void _togglePacked(int index) {
    setState(() {
      if (_packedItemIndices.contains(index)) {
        _packedItemIndices.remove(index);
      } else {
        _packedItemIndices.add(index);
      }
    });
    unawaited(_persistPackingProgress());
  }

  void _toggleAll() {
    setState(() {
      if (_packedItemIndices.length == widget.details.items.length) {
        _packedItemIndices.clear();
      } else {
        _packedItemIndices.addAll(List.generate(widget.details.items.length, (i) => i));
      }
    });
    unawaited(_persistPackingProgress());
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
              await InvoicePdfService.instance.sharePdf(
                widget.details,
                isDeliveryChallan: true,
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
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.grey.shade300),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.remove_circle_outline, size: 18),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                            onPressed: _boxCount > 0
                                ? () => _updateBoxCount(_boxCount - 1)
                                : null,
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            child: Text(
                              '$_boxCount ${AppLocalizations.of(context).t('boxes')}',
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 12,
                              ),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.add_circle_outline, size: 18),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                            onPressed: () => _updateBoxCount(_boxCount + 1),
                          ),
                        ],
                      ),
                    ),
                    OutlinedButton.icon(
                      onPressed: _pickDeliveryPartner,
                      icon: const Icon(Icons.local_shipping_outlined, size: 16),
                      label: Text(
                        (_deliveryPartnerName != null &&
                                _deliveryPartnerName!.isNotEmpty)
                            ? _deliveryPartnerName!
                            : AppLocalizations.of(context).t('deliveryPartnerLabel'),
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                    OutlinedButton.icon(
                      onPressed: _shareBoxLabels,
                      icon: const Icon(Icons.qr_code_2_outlined, size: 16),
                      label: Text(
                        AppLocalizations.of(context).t('boxLabels'),
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                  ],
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
      bottomNavigationBar: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: Colors.grey.shade300)),
        ),
        child: SafeArea(
          child: ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: allPacked ? const Color(0xFF16A34A) : const Color(0xFF0F766E),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () async {
              await _persistPackingProgress();
              if (context.mounted) {
                Navigator.pop(context, _packedItemIndices);
              }
            },
            icon: const Icon(Icons.check_circle_outline),
            label: Text(
              allPacked ? 'All Items Packed ($packedCount/$totalItems) - Done' : 'Save Packing Progress ($packedCount/$totalItems)',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
            ),
          ),
        ),
      ),
    );
  }
}
