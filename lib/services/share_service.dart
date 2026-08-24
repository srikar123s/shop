import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shop/models/order.dart';

class ShareService {
  static Future<void> shareDraftEstimate(DraftOrder draftOrder, {double? totalOverride}) async {
    final total = totalOverride ?? draftOrder.estimateTotal ?? 
        draftOrder.items.fold<double>(0, (sum, item) => sum + (item.unitPrice ?? 0) * item.quantity);

    final buffer = StringBuffer();
    buffer.writeln('📋 *ORDER ESTIMATE*');
    buffer.writeln('Customer: ${draftOrder.customer.name}');
    if ((draftOrder.customer.phone ?? '').isNotEmpty) {
      buffer.writeln('Phone: ${draftOrder.customer.phone}');
    }
    buffer.writeln('Date: ${DateFormat('dd MMM yyyy, hh:mm a').format(DateTime.now())}');
    buffer.writeln('--------------------------------');
    buffer.writeln('ITEMS:');

    for (int i = 0; i < draftOrder.items.length; i++) {
      final item = draftOrder.items[i];
      final opts = item.options.entries.map((e) => '${e.key}: ${e.value}').join(', ');
      final optsStr = opts.isNotEmpty ? ' ($opts)' : '';
      final priceStr = item.unitPrice != null ? ' @ ₹${item.unitPrice!.toStringAsFixed(2)}/${item.unit}' : '';
      final itemTotal = (item.unitPrice != null) ? ' = ₹${(item.unitPrice! * item.quantity).toStringAsFixed(2)}' : '';
      
      buffer.writeln('${i + 1}. ${item.itemName}$optsStr');
      buffer.writeln('   Qty: ${item.quantity % 1 == 0 ? item.quantity.toInt() : item.quantity} ${item.unit}$priceStr$itemTotal');
      if ((item.description ?? '').isNotEmpty) {
        buffer.writeln('   Details: ${item.description}');
      }
    }
    buffer.writeln('--------------------------------');
    buffer.writeln('Estimated Total: ₹${total.toStringAsFixed(2)}');
    buffer.writeln('Thank you!');

    final text = buffer.toString();
    try {
      await Share.share(text, subject: 'Order Estimate for ${draftOrder.customer.name}');
    } catch (_) {
      await Clipboard.setData(ClipboardData(text: text));
    }
  }

  static Future<void> shareOrderDetails(OrderDetails details) async {
    final order = details.order;
    final buffer = StringBuffer();
    buffer.writeln('📋 *ORDER SUMMARY - ${order.formattedOrderId}*');
    buffer.writeln('Customer: ${order.customerNameSnapshot}');
    buffer.writeln('Date: ${DateFormat('dd MMM yyyy, hh:mm a').format(order.createdAt)}');
    buffer.writeln('Status: ${orderStatusLabel(order.status)}');
    buffer.writeln('--------------------------------');
    buffer.writeln('ITEMS:');

    for (int i = 0; i < details.items.length; i++) {
      final item = details.items[i];
      final opts = item.options.map((e) => '${e.optionName}: ${e.optionValue}').join(', ');
      final optsStr = opts.isNotEmpty ? ' ($opts)' : '';
      buffer.writeln('${i + 1}. ${item.itemName}$optsStr');
      buffer.writeln('   Ordered: ${item.quantityOrdered % 1 == 0 ? item.quantityOrdered.toInt() : item.quantityOrdered} ${item.unit} | Given: ${item.quantityGiven % 1 == 0 ? item.quantityGiven.toInt() : item.quantityGiven} ${item.unit}');
    }
    buffer.writeln('--------------------------------');
    if (order.estimateTotal > 0) {
      buffer.writeln('Estimated Total: ₹${order.estimateTotal.toStringAsFixed(2)}');
    }
    buffer.writeln('Thank you!');

    final text = buffer.toString();
    try {
      await Share.share(text, subject: 'Order ${order.formattedOrderId} - ${order.customerNameSnapshot}');
    } catch (_) {
      await Clipboard.setData(ClipboardData(text: text));
    }
  }
}
