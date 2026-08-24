import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shop/models/order.dart';

class ShareService {
  static Future<void> shareDraftEstimate(DraftOrder draftOrder, {double? totalOverride}) async {
    final total = totalOverride ?? draftOrder.estimateTotal ?? 
        draftOrder.items.fold<double>(0, (sum, item) => sum + (item.unitPrice ?? 0) * item.quantity);

    final orderIdStr = 'DRAFT-${DateTime.now().millisecondsSinceEpoch.toString().substring(8)}';

    final itemsData = draftOrder.items.map((item) {
      final opts = item.options.entries.map((e) => '${e.key}: ${e.value}').join(', ');
      final qtyStr = item.quantity % 1 == 0 ? item.quantity.toInt().toString() : item.quantity.toString();
      final price = item.unitPrice ?? 0.0;
      final amount = price * item.quantity;

      return {
        'name': item.itemName,
        'options': opts,
        'qtyStr': '$qtyStr ${item.unit}',
        'price': price,
        'amount': amount,
      };
    }).toList();

    try {
      final imageFile = await _generateEstimateImage(
        title: 'ORDER ESTIMATE',
        orderId: orderIdStr,
        customerName: draftOrder.customer.name,
        phone: draftOrder.customer.phone ?? '',
        dateStr: DateFormat('dd MMM yyyy, hh:mm a').format(DateTime.now()),
        items: itemsData,
        grandTotal: total,
      );

      await Share.shareXFiles(
        [XFile(imageFile.path)],
        text: 'Order Estimate for ${draftOrder.customer.name}',
      );
    } catch (_) {
      // Fallback to text if image generation/sharing fails
      await _shareDraftAsText(draftOrder, totalOverride: total);
    }
  }

  static Future<void> shareOrderDetails(OrderDetails details) async {
    final order = details.order;
    double calculatedTotal = 0;

    final itemsData = details.items.map((item) {
      final opts = item.options.map((e) => '${e.optionName}: ${e.optionValue}').join(', ');
      final qtyStr = item.quantityOrdered % 1 == 0 ? item.quantityOrdered.toInt().toString() : item.quantityOrdered.toString();
      
      double price = 0;
      try {
        final snapshot = jsonDecode(item.productSnapshot) as Map<String, dynamic>;
        if (snapshot.containsKey('unitPrice') && snapshot['unitPrice'] != null) {
          price = (snapshot['unitPrice'] as num).toDouble();
        }
      } catch (_) {}

      final amount = price * item.quantityOrdered;
      calculatedTotal += amount;

      return {
        'name': item.itemName,
        'options': opts,
        'qtyStr': '$qtyStr ${item.unit}',
        'price': price,
        'amount': amount,
      };
    }).toList();

    final finalTotal = order.estimateTotal > 0 ? order.estimateTotal : calculatedTotal;

    try {
      final imageFile = await _generateEstimateImage(
        title: 'ORDER RECEIPT',
        orderId: order.formattedOrderId,
        customerName: order.customerNameSnapshot,
        phone: '',
        dateStr: DateFormat('dd MMM yyyy, hh:mm a').format(order.createdAt),
        items: itemsData,
        grandTotal: finalTotal,
      );

      await Share.shareXFiles(
        [XFile(imageFile.path)],
        text: 'Order ${order.formattedOrderId} for ${order.customerNameSnapshot}',
      );
    } catch (_) {
      await _shareOrderAsText(details);
    }
  }

  static Future<File> _generateEstimateImage({
    required String title,
    required String orderId,
    required String customerName,
    required String phone,
    required String dateStr,
    required List<Map<String, dynamic>> items,
    required double grandTotal,
  }) async {
    const double width = 800;
    final double headerHeight = 220;
    final double itemHeight = 65;
    final double footerHeight = 160;
    final double height = headerHeight + (items.length * itemHeight) + footerHeight;

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder, Rect.fromLTWH(0, 0, width, height));

    // Paint Background
    final bgPaint = Paint()..color = const Color(0xFFF8FAFC);
    canvas.drawRect(Rect.fromLTWH(0, 0, width, height), bgPaint);

    // Header Banner
    final bannerPaint = Paint()..color = const Color(0xFF0F766E);
    canvas.drawRRect(
      RRect.fromRectAndRadius(const Rect.fromLTWH(20, 20, width - 40, 140), const Radius.circular(16)),
      bannerPaint,
    );

    // Title Text
    final titlePainter = TextPainter(
      text: TextSpan(
        text: 'HARDWARE SHOP • $title',
        style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold, letterSpacing: 1),
      ),
      textDirection: ui.TextDirection.ltr,

    );
    titlePainter.layout();
    titlePainter.paint(canvas, const Offset(40, 40));

    // Subheader Date & ID
    final subPainter = TextPainter(
      text: TextSpan(
        text: '$orderId   •   $dateStr',
        style: const TextStyle(color: Color(0xFFCCFBF1), fontSize: 16),
      ),
      textDirection: ui.TextDirection.ltr,

    );
    subPainter.layout();
    subPainter.paint(canvas, const Offset(40, 80));

    // Customer Name & Phone
    final custPainter = TextPainter(
      text: TextSpan(
        text: 'Customer: $customerName ${phone.isNotEmpty ? "($phone)" : ""}',
        style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w600),
      ),
      textDirection: ui.TextDirection.ltr,

    );
    custPainter.layout();
    custPainter.paint(canvas, const Offset(40, 115));

    // Table Header Background
    final thBg = Paint()..color = const Color(0xFFE2E8F0);
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(20, headerHeight - 30, width - 40, 40), const Radius.circular(8)),
      thBg,
    );

    // Table Column Titles
    _drawText(canvas, 'ITEM & DETAILS', 40, headerHeight - 22, 14, FontWeight.bold, const Color(0xFF334155));
    _drawText(canvas, 'QTY', 440, headerHeight - 22, 14, FontWeight.bold, const Color(0xFF334155));
    _drawText(canvas, 'RATE', 560, headerHeight - 22, 14, FontWeight.bold, const Color(0xFF334155));
    _drawText(canvas, 'AMOUNT', 680, headerHeight - 22, 14, FontWeight.bold, const Color(0xFF334155));

    // Draw Items
    double currentY = headerHeight + 20;

    for (int i = 0; i < items.length; i++) {
      final item = items[i];
      final name = item['name'] as String;
      final options = item['options'] as String;
      final qtyStr = item['qtyStr'] as String;
      final price = item['price'] as double;
      final amount = item['amount'] as double;

      // Card row background
      final rowBg = Paint()..color = i % 2 == 0 ? Colors.white : const Color(0xFFF1F5F9);
      canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromLTWH(20, currentY - 10, width - 40, itemHeight - 8), const Radius.circular(8)),
        rowBg,
      );

      // Item Name
      _drawText(canvas, name, 40, currentY - 4, 16, FontWeight.bold, const Color(0xFF1E293B));
      if (options.isNotEmpty) {
        _drawText(canvas, options, 40, currentY + 18, 13, FontWeight.normal, const Color(0xFF64748B));
      }

      _drawText(canvas, qtyStr, 440, currentY + 6, 14, FontWeight.w600, const Color(0xFF1E293B));
      _drawText(canvas, price > 0 ? '₹${price.toStringAsFixed(2)}' : '-', 560, currentY + 6, 14, FontWeight.normal, const Color(0xFF475569));
      _drawText(canvas, amount > 0 ? '₹${amount.toStringAsFixed(2)}' : '-', 680, currentY + 6, 15, FontWeight.bold, const Color(0xFF0F766E));

      currentY += itemHeight;
    }

    // Divider Line
    final linePaint = Paint()
      ..color = const Color(0xFFCBD5E1)
      ..strokeWidth = 2;
    canvas.drawLine(Offset(20, currentY + 10), Offset(width - 20, currentY + 10), linePaint);

    // Total Card Banner
    final totalCard = Paint()..color = const Color(0xFF0F766E);
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(20, currentY + 30, width - 40, 70), const Radius.circular(12)),
      totalCard,
    );

    _drawText(canvas, 'ESTIMATED TOTAL AMOUNT:', 40, currentY + 52, 18, FontWeight.bold, Colors.white);
    _drawText(canvas, '₹ ${grandTotal.toStringAsFixed(2)}', 560, currentY + 48, 24, FontWeight.w900, const Color(0xFF5EEAD4));

    // Footer
    _drawText(canvas, 'Thank you for your business! • Hardware Shop Notebook', 220, currentY + 120, 14, FontWeight.normal, const Color(0xFF94A3B8));

    final picture = recorder.endRecording();
    final img = await picture.toImage(width.toInt(), height.toInt());
    final byteData = await img.toByteData(format: ui.ImageByteFormat.png);
    final pngBytes = byteData!.buffer.asUint8List();

    final tempDir = await getTemporaryDirectory();
    final file = File('${tempDir.path}/estimate_${orderId.replaceAll('#', '')}.png');
    await file.writeAsBytes(pngBytes);
    return file;
  }

  static void _drawText(Canvas canvas, String text, double x, double y, double fontSize, FontWeight weight, Color color) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(color: color, fontSize: fontSize, fontWeight: weight),
      ),
      textDirection: ui.TextDirection.ltr,

    );
    painter.layout();
    painter.paint(canvas, Offset(x, y));
  }

  static Future<void> _shareDraftAsText(DraftOrder draftOrder, {double? totalOverride}) async {
    final total = totalOverride ?? draftOrder.estimateTotal ?? 
        draftOrder.items.fold<double>(0, (sum, item) => sum + (item.unitPrice ?? 0) * item.quantity);

    final buffer = StringBuffer();
    buffer.writeln('📋 *ORDER ESTIMATE*');
    buffer.writeln('Customer: ${draftOrder.customer.name}');
    buffer.writeln('Date: ${DateFormat('dd MMM yyyy, hh:mm a').format(DateTime.now())}');
    buffer.writeln('--------------------------------');
    buffer.writeln('ITEMS:');

    for (int i = 0; i < draftOrder.items.length; i++) {
      final item = draftOrder.items[i];
      final opts = item.options.entries.map((e) => '${e.key}: ${e.value}').join(', ');
      final optsStr = opts.isNotEmpty ? ' ($opts)' : '';
      final qtyStr = item.quantity % 1 == 0 ? item.quantity.toInt().toString() : item.quantity.toString();
      buffer.writeln('${i + 1}. *${item.itemName}*$optsStr - $qtyStr ${item.unit}');
    }
    buffer.writeln('--------------------------------');
    buffer.writeln('💰 *Total Estimated Amount: ₹${total.toStringAsFixed(2)}*');

    final text = buffer.toString();
    try {
      await Share.share(text);
    } catch (_) {
      await Clipboard.setData(ClipboardData(text: text));
    }
  }

  static Future<void> _shareOrderAsText(OrderDetails details) async {
    final order = details.order;
    final buffer = StringBuffer();
    buffer.writeln('📋 *ORDER ${order.formattedOrderId}*');
    buffer.writeln('Customer: ${order.customerNameSnapshot}');
    buffer.writeln('Date: ${DateFormat('dd MMM yyyy, hh:mm a').format(order.createdAt)}');
    buffer.writeln('--------------------------------');
    for (int i = 0; i < details.items.length; i++) {
      final item = details.items[i];
      final opts = item.options.map((e) => '${e.optionName}: ${e.optionValue}').join(', ');
      final optsStr = opts.isNotEmpty ? ' ($opts)' : '';
      final orderedStr = item.quantityOrdered % 1 == 0 ? item.quantityOrdered.toInt().toString() : item.quantityOrdered.toString();
      buffer.writeln('${i + 1}. *${item.itemName}*$optsStr - $orderedStr ${item.unit}');
    }
    buffer.writeln('--------------------------------');
    if (order.estimateTotal > 0) {
      buffer.writeln('💰 *Total Estimated Amount: ₹${order.estimateTotal.toStringAsFixed(2)}*');
    }

    final text = buffer.toString();
    try {
      await Share.share(text);
    } catch (_) {
      await Clipboard.setData(ClipboardData(text: text));
    }
  }
}
