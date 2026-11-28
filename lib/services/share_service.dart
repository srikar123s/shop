import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shop/models/order.dart';
import 'package:shop/services/shop_customization_service.dart';

class ShareService {
  static Future<void> shareDraftEstimate(DraftOrder draftOrder,
      {double? totalOverride, BillBreakdown? billBreakdown}) async {
    final subtotal = draftOrder.items.fold<double>(
      0, (sum, item) => sum + (item.unitPrice ?? 0) * item.quantity);
    final breakdown = billBreakdown ??
        BillBreakdown.calculate(
          subtotal: subtotal,
          applyGst: draftOrder.applyGst,
          gstRate: draftOrder.gstRate,
          otherCharges: draftOrder.otherCharges,
          grandTotalOverride: totalOverride ?? draftOrder.estimateTotal,
        );
    final total = totalOverride ?? breakdown.grandTotal;

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
      final imageFiles = await _generateEstimateImages(
        title: 'ORDER ESTIMATE',
        orderId: orderIdStr,
        customerName: draftOrder.customer.name,
        phone: draftOrder.customer.phone ?? '',
        dateStr: DateFormat('dd MMM yyyy, hh:mm a').format(DateTime.now()),
        items: itemsData,
        grandTotal: total,
        billBreakdown: breakdown,
      );

      await Share.shareXFiles(
        imageFiles.map((f) => XFile(f.path)).toList(),
        text: 'Order Estimate for ${draftOrder.customer.name}',
      );
    } catch (_) {
      // Fallback to text if image generation/sharing fails
      await _shareDraftAsText(draftOrder, totalOverride: total, billBreakdown: breakdown);
    }
  }

  static Future<void> shareOrderDetails(
    OrderDetails details, {
    int? customerBillNumber,
  }) async {
    final order = details.order;
    double calculatedTotal = 0;

    final itemsData = details.items.map((item) {
      final seenOpts = <String>{};
      final distinctOpts = <String>[];
      for (final e in item.options) {
        final k = '${e.optionName.trim().toLowerCase()}:${e.optionValue.trim().toLowerCase()}';
        if (e.optionName.trim().isNotEmpty && seenOpts.add(k)) {
          distinctOpts.add('${e.optionName}: ${e.optionValue}');
        }
      }
      final opts = distinctOpts.join(', ');
      final isFinalizedOrder = order.status == OrderStatus.completed || order.status == OrderStatus.closed;
      final effectiveQty = isFinalizedOrder ? item.quantityGiven : item.quantityOrdered;
      final qtyStr = effectiveQty % 1 == 0 ? effectiveQty.toInt().toString() : effectiveQty.toString();
      
      double price = item.unitPrice > 0 ? item.unitPrice : 0.0;
      if (price <= 0) {
        try {
          final snapshot = jsonDecode(item.productSnapshot) as Map<String, dynamic>;
          if (snapshot.containsKey('unitPrice') && snapshot['unitPrice'] != null) {
            price = (snapshot['unitPrice'] as num).toDouble();
          }
        } catch (_) {}
      }

      final amount = price * effectiveQty;
      calculatedTotal += amount;

      return {
        'name': item.itemName,
        'options': opts,
        'qtyStr': '$qtyStr ${item.unit}',
        'price': price,
        'amount': amount,
      };
    }).toList();

    var breakdown = order.billBreakdown;
    if (breakdown == null || (breakdown.subtotal == 0 && calculatedTotal > 0)) {
      breakdown = BillBreakdown.calculate(
        subtotal: calculatedTotal,
        applyGst: breakdown?.applyGst ?? false,
        gstRate: breakdown?.gstRate ?? 18.0,
        otherCharges: breakdown?.otherCharges ?? const [],
        note: breakdown?.note,
      );
    }
    final finalTotal = breakdown.grandTotal > 0 ? breakdown.grandTotal : (order.estimateTotal > 0 ? order.estimateTotal : calculatedTotal);

    final billLabel = customerBillNumber != null
        ? 'Bill #$customerBillNumber (${order.formattedOrderId})'
        : order.formattedOrderId;
    try {
      final imageFiles = await _generateEstimateImages(
        title: 'ORDER RECEIPT',
        orderId: billLabel,
        customerName: order.customerNameSnapshot,
        phone: '',
        dateStr: DateFormat('dd MMM yyyy, hh:mm a').format(order.createdAt),
        items: itemsData,
        grandTotal: finalTotal,
        billBreakdown: breakdown,
      );

      final shareSubject = customerBillNumber != null
          ? 'Bill #$customerBillNumber for ${order.customerNameSnapshot}'
          : 'Bill Receipt ${order.formattedOrderId} for ${order.customerNameSnapshot}';
      await Share.shareXFiles(
        imageFiles.map((f) => XFile(f.path)).toList(),
        text: shareSubject,
      );
    } catch (_) {
      await _shareOrderAsText(
        details,
        billBreakdown: breakdown,
        customerBillNumber: customerBillNumber,
      );
    }
  }

  /// Generates the exact styled image files matching the WhatsApp receipt
  static Future<List<File>> generateReceiptImages(
    OrderDetails details, {
    int? customerBillNumber,
    String title = 'ORDER RECEIPT',
  }) async {
    final order = details.order;
    var breakdown = order.billBreakdown;
    final double calculatedTotal = details.items.fold<double>(
      0.0,
      (sum, item) => sum + (item.unitPrice * item.quantityOrdered),
    );

    if (breakdown == null && calculatedTotal > 0) {
      breakdown = BillBreakdown(
        subtotal: calculatedTotal,
        grandTotal: calculatedTotal,
        applyGst: false,
        gstRate: 18.0,
        otherCharges: const [],
      );
    }

    final double finalTotal = (breakdown != null && breakdown.grandTotal > 0)
        ? breakdown.grandTotal
        : (order.estimateTotal > 0 ? order.estimateTotal : calculatedTotal);

    final billLabel = customerBillNumber != null
        ? 'Bill #$customerBillNumber (${order.formattedOrderId})'
        : order.formattedOrderId;

    final isFinalized = order.status == OrderStatus.completed || order.status == OrderStatus.closed;
    final itemsData = details.items.map((i) {
      final opt = i.options
          .map((o) => '${o.optionName}: ${o.optionValue}')
          .join(', ');
      final effectiveQty = isFinalized ? i.quantityGiven : i.quantityOrdered;
      final qtyFormatted = effectiveQty % 1 == 0
          ? '${effectiveQty.toInt()} ${i.unit}'
          : '$effectiveQty ${i.unit}';
      return {
        'name': i.itemName,
        'options': opt,
        'qty': qtyFormatted,
        'qtyStr': qtyFormatted,
        'rate': i.unitPrice,
        'price': i.unitPrice,
        'amount': i.unitPrice * effectiveQty,
      };
    }).toList();

    return _generateEstimateImages(
      title: title,
      orderId: billLabel,
      customerName: order.customerNameSnapshot,
      phone: '',
      dateStr: DateFormat('dd MMM yyyy, hh:mm a').format(order.createdAt),
      items: itemsData,
      grandTotal: finalTotal,
      billBreakdown: breakdown,
    );
  }

  static Future<List<File>> _generateEstimateImages({
    required String title,
    required String orderId,
    required String customerName,
    required String phone,
    required String dateStr,
    required List<Map<String, dynamic>> items,
    required double grandTotal,
    BillBreakdown? billBreakdown,
  }) async {
    const int itemsPerPage = 16;
    final int totalPages = (items.length / itemsPerPage).ceil().clamp(1, 99);
    final tempDir = await getTemporaryDirectory();
    unawaited(_cleanupStaleTempImages(tempDir));
    final List<File> generatedFiles = [];

    final customShopName =
        ShopCustomizationService.instance.shopName.toUpperCase();
    const double width = 800;
    const double headerHeight = 220;
    const double itemHeight = 65;
    final bool hasBreakdown = billBreakdown != null &&
        (billBreakdown.applyDiscount ||
            billBreakdown.applyGst ||
            billBreakdown.otherCharges.isNotEmpty);
    final double breakdownHeight = hasBreakdown
        ? (35.0 +
            (billBreakdown.applyDiscount ? 28.0 : 0.0) +
            (billBreakdown.applyGst ? 28.0 : 0.0) +
            (billBreakdown.otherCharges.length * 28.0) +
            15.0)
        : 0.0;
    const double footerHeight = 160;

    for (int page = 0; page < totalPages; page++) {
      final startIndex = page * itemsPerPage;
      final endIndex = (startIndex + itemsPerPage < items.length)
          ? startIndex + itemsPerPage
          : items.length;
      final pageItems = items.sublist(startIndex, endIndex);
      final isLastPage = (page == totalPages - 1);

      final double height = headerHeight +
          (pageItems.length * itemHeight) +
          (isLastPage ? breakdownHeight : 0.0) +
          (isLastPage ? footerHeight : 90.0);

      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder, Rect.fromLTWH(0, 0, width, height));

      // Paint Background
      final bgPaint = Paint()..color = const Color(0xFFF8FAFC);
      canvas.drawRect(Rect.fromLTWH(0, 0, width, height), bgPaint);

      // Header Banner
      final bannerPaint = Paint()..color = const Color(0xFF0F766E);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
            const Rect.fromLTWH(20, 20, width - 40, 140),
            const Radius.circular(16)),
        bannerPaint,
      );

      // Title Text (with Page Number if multi-page)
      final pageIndicator =
          totalPages > 1 ? ' (Page ${page + 1} of $totalPages)' : '';
      final titlePainter = TextPainter(
        text: TextSpan(
          text: '$customShopName • $title$pageIndicator',
          style: const TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.5),
        ),
        textDirection: ui.TextDirection.ltr,
      );
      titlePainter.layout(maxWidth: width - 80);
      titlePainter.paint(canvas, const Offset(40, 36));

      // Subheader Date & ID
      final subPainter = TextPainter(
        text: TextSpan(
          text: '$orderId   •   $dateStr',
          style: const TextStyle(color: Color(0xFFCCFBF1), fontSize: 15),
        ),
        textDirection: ui.TextDirection.ltr,
      );
      subPainter.layout();
      subPainter.paint(canvas, const Offset(40, 76));

      // Customer Name & Phone
      final custPainter = TextPainter(
        text: TextSpan(
          text: 'Customer: $customerName ${phone.isNotEmpty ? "($phone)" : ""}',
          style: const TextStyle(
              color: Colors.white, fontSize: 17, fontWeight: FontWeight.w600),
        ),
        textDirection: ui.TextDirection.ltr,
      );
      custPainter.layout(maxWidth: width - 80);
      custPainter.paint(canvas, const Offset(40, 110));

      // Table Header Background
      final thBg = Paint()..color = const Color(0xFFE2E8F0);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
            Rect.fromLTWH(20, headerHeight - 30, width - 40, 40),
            const Radius.circular(8)),
        thBg,
      );

      // Table Column Titles
      _drawText(canvas, '#  ITEM & DETAILS', 36, headerHeight - 22, 14,
          FontWeight.bold, const Color(0xFF334155),
          width: 340);
      _drawText(canvas, 'QTY', 384, headerHeight - 22, 14, FontWeight.bold,
          const Color(0xFF334155),
          width: 110);
      _drawText(canvas, 'RATE', 502, headerHeight - 22, 14, FontWeight.bold,
          const Color(0xFF334155),
          width: 116,
          textAlign: TextAlign.right);
      _drawText(canvas, 'AMOUNT', 626, headerHeight - 22, 14, FontWeight.bold,
          const Color(0xFF334155),
          width: 140,
          textAlign: TextAlign.right);

      // Draw Items for this page
      double currentY = headerHeight + 20;

      for (int i = 0; i < pageItems.length; i++) {
        final globalIndex = startIndex + i;
        final item = pageItems[i];
        final name = '${globalIndex + 1}. ${item['name'] as String}';
        final options = item['options'] as String;
        final qtyStr = (item['qtyStr'] ?? item['qty']) as String? ?? '';
        final price = (item['price'] as num?)?.toDouble() ?? (item['rate'] as num?)?.toDouble() ?? 0.0;
        final amount = (item['amount'] as num?)?.toDouble() ?? 0.0;

        // Card row background
        final rowBg = Paint()
          ..color =
              globalIndex % 2 == 0 ? Colors.white : const Color(0xFFF1F5F9);
        canvas.drawRRect(
          RRect.fromRectAndRadius(
              Rect.fromLTWH(20, currentY - 10, width - 40, itemHeight - 8),
              const Radius.circular(8)),
          rowBg,
        );

        // Item Name & details bounded inside left column
        _drawText(canvas, name, 36, currentY - 4, 15, FontWeight.bold,
            const Color(0xFF1E293B),
            width: 340);
        if (options.isNotEmpty) {
          _drawText(canvas, options, 40, currentY + 18, 12, FontWeight.normal,
              const Color(0xFF64748B),
              width: 336);
        }

        _drawText(canvas, qtyStr, 384, currentY + 6, 14, FontWeight.w600,
            const Color(0xFF1E293B),
            width: 110);
        _drawText(
            canvas,
            price > 0 ? '₹${price.toStringAsFixed(2)}' : '-',
            502,
            currentY + 6,
            14,
            FontWeight.normal,
            const Color(0xFF475569),
            width: 116,
            textAlign: TextAlign.right);
        _drawText(
            canvas,
            amount > 0 ? '₹${amount.toStringAsFixed(2)}' : '-',
            626,
            currentY + 6,
            15,
            FontWeight.bold,
            const Color(0xFF0F766E),
            width: 140,
            textAlign: TextAlign.right);

        currentY += itemHeight;
      }

      // Divider Line
      final linePaint = Paint()
        ..color = const Color(0xFFCBD5E1)
        ..strokeWidth = 2;
      canvas.drawLine(Offset(20, currentY + 10),
          Offset(width - 20, currentY + 10), linePaint);
      currentY += 24;

      if (isLastPage) {
        if (hasBreakdown) {
          // Subtotal
          _drawText(canvas, 'Items Subtotal', 40, currentY, 15, FontWeight.w600,
              const Color(0xFF475569),
              width: 440);
          _drawText(canvas, '₹ ${billBreakdown.subtotal.toStringAsFixed(2)}',
              500, currentY, 15, FontWeight.w700, const Color(0xFF1E293B),
              width: 266,
              textAlign: TextAlign.right);
          currentY += 28;

          if (billBreakdown.applyDiscount && billBreakdown.discountAmount > 0) {
            final discLabel = billBreakdown.discountType == 'percent'
                ? 'Discount (${billBreakdown.discountValue % 1 == 0 ? billBreakdown.discountValue.toInt() : billBreakdown.discountValue}%)'
                : 'Discount (Flat)';
            _drawText(canvas, discLabel, 40, currentY, 15, FontWeight.w600,
                const Color(0xFF166534),
                width: 440);
            _drawText(
                canvas,
                '- ₹ ${billBreakdown.discountAmount.toStringAsFixed(2)}',
                500,
                currentY,
                15,
                FontWeight.w700,
                const Color(0xFF166534),
                width: 266,
                textAlign: TextAlign.right);
            currentY += 28;
          }

          if (billBreakdown.applyGst) {
            final rateStr = billBreakdown.gstRate % 1 == 0
                ? billBreakdown.gstRate.toInt().toString()
                : billBreakdown.gstRate.toString();
            _drawText(canvas, 'GST ($rateStr%)', 40, currentY, 15,
                FontWeight.w600, const Color(0xFF475569),
                width: 440);
            _drawText(
                canvas,
                '+ ₹ ${billBreakdown.gstAmount.toStringAsFixed(2)}',
                500,
                currentY,
                15,
                FontWeight.w700,
                const Color(0xFF0F766E),
                width: 266,
                textAlign: TextAlign.right);
            currentY += 28;
          }

          for (final charge in billBreakdown.otherCharges) {
            _drawText(canvas, charge.name, 40, currentY, 15, FontWeight.w600,
                const Color(0xFF475569),
                width: 440);
            _drawText(canvas, '+ ₹ ${charge.amount.toStringAsFixed(2)}', 500,
                currentY, 15, FontWeight.w700, const Color(0xFF0F766E),
                width: 266,
                textAlign: TextAlign.right);
            currentY += 28;
          }

          canvas.drawLine(Offset(20, currentY + 4),
              Offset(width - 20, currentY + 4), linePaint);
          currentY += 16;
        }

        // Total Card Banner
        final totalCard = Paint()..color = const Color(0xFF0F766E);
        canvas.drawRRect(
          RRect.fromRectAndRadius(
              Rect.fromLTWH(20, currentY, width - 40, 70),
              const Radius.circular(12)),
          totalCard,
        );

        _drawText(canvas, 'TOTAL AMOUNT:', 40, currentY + 24, 18,
            FontWeight.bold, Colors.white,
            width: 320);
        _drawText(canvas, '₹ ${grandTotal.toStringAsFixed(2)}', 380,
            currentY + 20, 24, FontWeight.w900, const Color(0xFF5EEAD4),
            width: 380,
            textAlign: TextAlign.right);

        // Footer (centered full width so long shop names never clip)
        _drawText(
            canvas,
            'Thank you for your business! • $customShopName',
            40,
            currentY + 105,
            14,
            FontWeight.normal,
            const Color(0xFF94A3B8),
            width: width - 80,
            textAlign: TextAlign.center);
      } else {
        // Intermediate page bottom banner
        final contBg = Paint()..color = const Color(0xFFE2E8F0);
        canvas.drawRRect(
          RRect.fromRectAndRadius(
              Rect.fromLTWH(20, currentY, width - 40, 48),
              const Radius.circular(8)),
          contBg,
        );
        _drawText(
            canvas,
            '--- Continued on Page ${page + 2} of $totalPages ---',
            40,
            currentY + 15,
            15,
            FontWeight.bold,
            const Color(0xFF0F766E),
            width: width - 80,
            textAlign: TextAlign.center);
      }

      final picture = recorder.endRecording();
      final img = await picture.toImage(width.toInt(), height.toInt());
      final byteData = await img.toByteData(format: ui.ImageByteFormat.png);
      final pngBytes = byteData!.buffer.asUint8List();

      final cleanId = orderId.replaceAll('#', '');
      final pageSuffix = totalPages > 1 ? '_p${page + 1}' : '';
      final file = File('${tempDir.path}/estimate_$cleanId$pageSuffix.png');
      await file.writeAsBytes(pngBytes);
      generatedFiles.add(file);
    }

    return generatedFiles;
  }
  static Future<void> _cleanupStaleTempImages(Directory tempDir) async {
    try {
      final cutoff = DateTime.now().subtract(const Duration(hours: 24));
      await for (final entity in tempDir.list()) {
        if (entity is File &&
            entity.path.contains('estimate_') &&
            entity.path.toLowerCase().endsWith('.png')) {
          final stat = await entity.stat();
          if (stat.modified.isBefore(cutoff)) {
            await entity.delete();
          }
        }
      }
    } catch (_) {}
  }

  static void _drawText(Canvas canvas, String text, double x, double y,
      double fontSize, FontWeight weight, Color color,
      {double? width, double maxWidth = 760, TextAlign textAlign = TextAlign.left}) {
    final availableWidth =
        width ?? (maxWidth - x).clamp(80.0, maxWidth).toDouble();
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(color: color, fontSize: fontSize, fontWeight: weight),
      ),
      textAlign: textAlign,
      textDirection: ui.TextDirection.ltr,
      maxLines: 1,
      ellipsis: '…',
    );
    painter.layout(minWidth: width ?? 0, maxWidth: availableWidth);
    painter.paint(canvas, Offset(x, y));
  }

  static Future<void> _shareDraftAsText(
    DraftOrder draftOrder, {
    double? totalOverride,
    BillBreakdown? billBreakdown,
  }) async {
    final shopName = ShopCustomizationService.instance.shopName;
    final subtotal = draftOrder.items.fold<double>(
        0, (sum, item) => sum + (item.unitPrice ?? 0) * item.quantity);
    final breakdown = billBreakdown ??
        BillBreakdown.calculate(
          subtotal: subtotal,
          applyGst: draftOrder.applyGst,
          gstRate: draftOrder.gstRate,
          otherCharges: draftOrder.otherCharges,
          applyDiscount: draftOrder.applyDiscount,
          discountType: draftOrder.discountType,
          discountValue: draftOrder.discountValue,
          grandTotalOverride: totalOverride ?? draftOrder.estimateTotal,
        );
    final total = totalOverride ?? breakdown.grandTotal;

    final buffer = StringBuffer();
    buffer.writeln('📋 *$shopName • ORDER ESTIMATE*');
    buffer.writeln('Customer: ${draftOrder.customer.name}');
    buffer.writeln(
        'Date: ${DateFormat('dd MMM yyyy, hh:mm a').format(DateTime.now())}');
    buffer.writeln('--------------------------------');
    buffer.writeln('ITEMS:');

    for (int i = 0; i < draftOrder.items.length; i++) {
      final item = draftOrder.items[i];
      final opts =
          item.options.entries.map((e) => '${e.key}: ${e.value}').join(', ');
      final optsStr = opts.isNotEmpty ? ' ($opts)' : '';
      final qtyStr = item.quantity % 1 == 0
          ? item.quantity.toInt().toString()
          : item.quantity.toString();
      final priceStr = item.unitPrice != null && item.unitPrice! > 0
          ? ' @ ₹${item.unitPrice!.toStringAsFixed(2)} = ₹${((item.unitPrice ?? 0) * item.quantity).toStringAsFixed(2)}'
          : '';
      buffer.writeln(
          '${i + 1}. *${item.itemName}*$optsStr - $qtyStr ${item.unit}$priceStr');
    }
    buffer.writeln('--------------------------------');
    if (breakdown.applyDiscount ||
        breakdown.applyGst ||
        breakdown.otherCharges.isNotEmpty) {
      buffer.writeln(
          'Items Subtotal: ₹${breakdown.subtotal.toStringAsFixed(2)}');
      if (breakdown.applyDiscount && breakdown.discountAmount > 0) {
        final discStr = breakdown.discountType == 'percent'
            ? '${breakdown.discountValue % 1 == 0 ? breakdown.discountValue.toInt() : breakdown.discountValue}%'
            : '₹${breakdown.discountValue.toStringAsFixed(2)}';
        buffer.writeln(
            'Discount ($discStr): -₹${breakdown.discountAmount.toStringAsFixed(2)}');
      }
      if (breakdown.applyGst) {
        final rateStr = breakdown.gstRate % 1 == 0
            ? breakdown.gstRate.toInt().toString()
            : breakdown.gstRate.toString();
        buffer.writeln(
            'GST ($rateStr%): +₹${breakdown.gstAmount.toStringAsFixed(2)}');
      }
      for (final charge in breakdown.otherCharges) {
        buffer.writeln('${charge.name}: +₹${charge.amount.toStringAsFixed(2)}');
      }
      buffer.writeln('--------------------------------');
    }
    buffer.writeln('💰 *Total Amount: ₹${total.toStringAsFixed(2)}*');

    final text = buffer.toString();
    try {
      await Share.share(text);
    } catch (_) {
      await Clipboard.setData(ClipboardData(text: text));
    }
  }

  static Future<void> _shareOrderAsText(
    OrderDetails details, {
    BillBreakdown? billBreakdown,
    int? customerBillNumber,
  }) async {
    final shopName = ShopCustomizationService.instance.shopName;
    final order = details.order;
    final breakdown = billBreakdown ?? order.billBreakdown;
    final buffer = StringBuffer();
    final billTitle = customerBillNumber != null
        ? 'BILL #$customerBillNumber (${order.formattedOrderId})'
        : 'ORDER ${order.formattedOrderId}';
    buffer.writeln('📋 *$shopName • $billTitle*');
    buffer.writeln('Customer: ${order.customerNameSnapshot}');
    buffer.writeln(
        'Date: ${DateFormat('dd MMM yyyy, hh:mm a').format(order.createdAt)}');
    buffer.writeln('--------------------------------');
    for (int i = 0; i < details.items.length; i++) {
      final item = details.items[i];
      final seenOpts = <String>{};
      final distinctOpts = <String>[];
      for (final e in item.options) {
        final k = '${e.optionName.trim().toLowerCase()}:${e.optionValue.trim().toLowerCase()}';
        if (e.optionName.trim().isNotEmpty && seenOpts.add(k)) {
          distinctOpts.add('${e.optionName}: ${e.optionValue}');
        }
      }
      final opts = distinctOpts.join(', ');
      final optsStr = opts.isNotEmpty ? ' ($opts)' : '';
      final isFinalized = order.status == OrderStatus.completed || order.status == OrderStatus.closed;
      final effectiveQty = isFinalized ? item.quantityGiven : item.quantityOrdered;
      final orderedStr = effectiveQty % 1 == 0
          ? effectiveQty.toInt().toString()
          : effectiveQty.toString();
      final priceStr = item.unitPrice > 0
          ? ' @ ₹${item.unitPrice.toStringAsFixed(2)} = ₹${(item.unitPrice * effectiveQty).toStringAsFixed(2)}'
          : '';
      buffer.writeln(
          '${i + 1}. *${item.itemName}*$optsStr - $orderedStr ${item.unit}$priceStr');
    }
    buffer.writeln('--------------------------------');
    if (breakdown != null &&
        (breakdown.applyDiscount ||
            breakdown.applyGst ||
            breakdown.otherCharges.isNotEmpty)) {
      buffer.writeln(
          'Items Subtotal: ₹${breakdown.subtotal.toStringAsFixed(2)}');
      if (breakdown.applyDiscount && breakdown.discountAmount > 0) {
        final discStr = breakdown.discountType == 'percent'
            ? '${breakdown.discountValue % 1 == 0 ? breakdown.discountValue.toInt() : breakdown.discountValue}%'
            : '₹${breakdown.discountValue.toStringAsFixed(2)}';
        buffer.writeln(
            'Discount ($discStr): -₹${breakdown.discountAmount.toStringAsFixed(2)}');
      }
      if (breakdown.applyGst) {
        final rateStr = breakdown.gstRate % 1 == 0
            ? breakdown.gstRate.toInt().toString()
            : breakdown.gstRate.toString();
        buffer.writeln(
            'GST ($rateStr%): +₹${breakdown.gstAmount.toStringAsFixed(2)}');
      }
      for (final charge in breakdown.otherCharges) {
        buffer.writeln('${charge.name}: +₹${charge.amount.toStringAsFixed(2)}');
      }
      buffer.writeln('--------------------------------');
    }
    if (order.estimateTotal > 0) {
      buffer.writeln(
          '💰 *Total Amount: ₹${order.estimateTotal.toStringAsFixed(2)}*');
    }
    if (breakdown?.note != null && breakdown!.note!.isNotEmpty) {
      buffer.writeln('📝 *Note:* ${breakdown.note}');
    }

    final text = buffer.toString();
    try {
      await Share.share(text);
    } catch (_) {
      await Clipboard.setData(ClipboardData(text: text));
    }
  }
}
