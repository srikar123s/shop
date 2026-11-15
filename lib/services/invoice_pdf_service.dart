import 'dart:io';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shop/models/order.dart';
import 'package:shop/services/shop_customization_service.dart';

class InvoicePdfService {
  InvoicePdfService._();
  static final InvoicePdfService instance = InvoicePdfService._();

  Future<Uint8List> generatePdfBytes(
    OrderDetails details, {
    bool isDeliveryChallan = false,
    bool isThermal58mm = false,
  }) async {
    final pdf = pw.Document();
    final shopService = ShopCustomizationService.instance;
    final shopName = shopService.shopName;
    final shopPhone = shopService.shopPhone;
    final shopAddress = shopService.shopAddress;
    final gstin = shopService.gstin;
    final digitalStamp = shopService.digitalStamp;
    final upiId = shopService.upiId;

    final order = details.order;
    final items = details.items;
    final breakdown = order.billBreakdown;

    final dateStr =
        DateFormat('dd-MM-yyyy hh:mm a').format(order.createdAt);
    final docTitle = isDeliveryChallan ? 'DELIVERY CHALLAN' : 'ORDER RECEIPT';

    // Page format
    final pageFormat = isThermal58mm
        ? const PdfPageFormat(
            58 * PdfPageFormat.mm,
            double.infinity,
            marginAll: 3 * PdfPageFormat.mm,
          )
        : PdfPageFormat.a4;

    pdf.addPage(
      pw.Page(
        pageFormat: pageFormat,
        build: (pw.Context context) {
          if (isThermal58mm) {
            return _buildThermalLayout(
              shopName: shopName,
              shopPhone: shopPhone,
              shopAddress: shopAddress,
              docTitle: docTitle,
              order: order,
              items: items,
              breakdown: breakdown,
              dateStr: dateStr,
              isDeliveryChallan: isDeliveryChallan,
              digitalStamp: digitalStamp,
            );
          }

          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              // Header
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        shopName,
                        style: pw.TextStyle(
                          fontSize: 20,
                          fontWeight: pw.FontWeight.bold,
                          color: PdfColors.teal900,
                        ),
                      ),
                      if (shopAddress.isNotEmpty)
                        pw.Text(shopAddress,
                            style: const pw.TextStyle(fontSize: 10)),
                      if (shopPhone.isNotEmpty)
                        pw.Text('Phone: $shopPhone',
                            style: const pw.TextStyle(fontSize: 10)),
                      if (gstin.isNotEmpty)
                        pw.Text('GSTIN: $gstin',
                            style: pw.TextStyle(
                                fontSize: 10,
                                fontWeight: pw.FontWeight.bold)),
                    ],
                  ),
                  pw.Container(
                    padding: const pw.EdgeInsets.symmetric(
                        horizontal: 12, vertical: 6),
                    decoration: pw.BoxDecoration(
                      color: isDeliveryChallan
                          ? PdfColors.amber100
                          : PdfColors.teal50,
                      borderRadius: pw.BorderRadius.circular(6),
                      border: pw.Border.all(
                        color: isDeliveryChallan
                            ? PdfColors.amber800
                            : PdfColors.teal700,
                      ),
                    ),
                    child: pw.Text(
                      docTitle,
                      style: pw.TextStyle(
                        fontSize: 12,
                        fontWeight: pw.FontWeight.bold,
                        color: isDeliveryChallan
                            ? PdfColors.amber900
                            : PdfColors.teal900,
                      ),
                    ),
                  ),
                ],
              ),
              pw.SizedBox(height: 10),
              pw.Divider(thickness: 1, color: PdfColors.grey300),
              pw.SizedBox(height: 6),

              // Order & Customer Details
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text('Customer: ${order.customerNameSnapshot}',
                          style: pw.TextStyle(
                              fontWeight: pw.FontWeight.bold, fontSize: 12)),
                      if (order.customerPhone != null &&
                          order.customerPhone!.isNotEmpty)
                        pw.Text('Phone: ${order.customerPhone}',
                            style: const pw.TextStyle(fontSize: 10)),
                      if (order.takenBy != null && order.takenBy!.isNotEmpty)
                        pw.Text('Billed by: ${order.takenBy}',
                            style: const pw.TextStyle(fontSize: 10)),
                    ],
                  ),
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.end,
                    children: [
                      pw.Text(order.formattedOrderId,
                          style: pw.TextStyle(
                              fontWeight: pw.FontWeight.bold,
                              fontSize: 13,
                              color: PdfColors.teal800)),
                      pw.Text('Date: $dateStr',
                          style: const pw.TextStyle(fontSize: 10)),
                      pw.Text('Status: ${orderStatusLabel(order.status)}',
                          style: pw.TextStyle(
                              fontSize: 10,
                              fontWeight: pw.FontWeight.bold)),
                    ],
                  ),
                ],
              ),
              pw.SizedBox(height: 14),

              // Items Table
              pw.TableHelper.fromTextArray(
                border: pw.TableBorder.all(color: PdfColors.grey300),
                headerStyle: pw.TextStyle(
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColors.white,
                    fontSize: 10),
                headerDecoration:
                    const pw.BoxDecoration(color: PdfColors.teal700),
                cellStyle: const pw.TextStyle(fontSize: 9),
                cellAlignment: pw.Alignment.centerLeft,
                headers: [
                  '#',
                  'Item & Description',
                  'Qty',
                  'Unit',
                  if (!isDeliveryChallan) 'Rate (₹)',
                  if (!isDeliveryChallan) 'Amount (₹)',
                ],
                data: List.generate(items.length, (i) {
                  final item = items[i];
                  final details = item.description?.isNotEmpty == true
                      ? '\n${item.description}'
                      : '';
                  return [
                    '${i + 1}',
                    '${item.itemName}$details',
                    '${item.quantityOrdered % 1 == 0 ? item.quantityOrdered.toInt() : item.quantityOrdered}',
                    item.unit,
                    if (!isDeliveryChallan)
                      item.unitPrice.toStringAsFixed(2),
                    if (!isDeliveryChallan)
                      (item.unitPrice * item.quantityOrdered)
                          .toStringAsFixed(2),
                  ];
                }),
              ),
              pw.SizedBox(height: 12),

              // Totals and Signatory
              if (!isDeliveryChallan) ...[
                pw.Row(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    // UPI QR code
                    if (upiId.isNotEmpty && order.estimateTotal > 0)
                      pw.Container(
                        padding: const pw.EdgeInsets.all(6),
                        decoration: pw.BoxDecoration(
                          border: pw.Border.all(color: PdfColors.grey300),
                          borderRadius: pw.BorderRadius.circular(6),
                        ),
                        child: pw.Column(
                          children: [
                            pw.BarcodeWidget(
                              barcode: pw.Barcode.qrCode(),
                              data:
                                  'upi://pay?pa=$upiId&pn=${Uri.encodeComponent(shopName)}&am=${order.estimateTotal.toStringAsFixed(2)}&cu=INR&tn=${order.formattedOrderId}',
                              width: 75,
                              height: 75,
                            ),
                            pw.SizedBox(height: 4),
                            pw.Text('Scan & Pay via UPI',
                                style: const pw.TextStyle(fontSize: 8)),
                          ],
                        ),
                      )
                    else
                      pw.SizedBox(width: 80),

                    // Bill Breakdown Box
                    pw.Container(
                      width: 200,
                      child: pw.Column(
                        children: [
                          if (breakdown != null) ...[
                            _buildPdfRow('Items Subtotal:',
                                '₹ ${breakdown.subtotal.toStringAsFixed(2)}'),
                            if (breakdown.discountAmount > 0)
                              _buildPdfRow('Discount:',
                                  '- ₹ ${breakdown.discountAmount.toStringAsFixed(2)}'),
                            if (breakdown.applyGst)
                              _buildPdfRow(
                                  'GST (${breakdown.gstRate}%):',
                                  '+ ₹ ${breakdown.gstAmount.toStringAsFixed(2)}'),
                            if (breakdown.otherChargesTotal > 0)
                              _buildPdfRow('Other Charges:',
                                  '+ ₹ ${breakdown.otherChargesTotal.toStringAsFixed(2)}'),
                            pw.Divider(color: PdfColors.grey400),
                          ],
                          _buildPdfRow(
                            'TOTAL AMOUNT:',
                            '₹ ${order.estimateTotal.toStringAsFixed(2)}',
                            isBold: true,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],

              pw.Spacer(),
              pw.Divider(color: PdfColors.grey300),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('Thank you for your business! - $shopName',
                      style: const pw.TextStyle(
                          fontSize: 9, color: PdfColors.grey700)),
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.end,
                    children: [
                      pw.Text(
                        digitalStamp.isNotEmpty
                            ? digitalStamp
                            : 'Authorized Signatory',
                        style: pw.TextStyle(
                            fontSize: 9, fontWeight: pw.FontWeight.bold),
                      ),
                      pw.Text('For $shopName',
                          style: const pw.TextStyle(fontSize: 8)),
                    ],
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );

    return pdf.save();
  }

  pw.Widget _buildThermalLayout({
    required String shopName,
    required String shopPhone,
    required String shopAddress,
    required String docTitle,
    required OrderEntity order,
    required List<OrderItemEntity> items,
    required BillBreakdown? breakdown,
    required String dateStr,
    required bool isDeliveryChallan,
    required String digitalStamp,
  }) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.center,
      children: [
        pw.Text(shopName,
            style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold),
            textAlign: pw.TextAlign.center),
        if (shopAddress.isNotEmpty)
          pw.Text(shopAddress,
              style: const pw.TextStyle(fontSize: 8),
              textAlign: pw.TextAlign.center),
        if (shopPhone.isNotEmpty)
          pw.Text('Tel: $shopPhone',
              style: const pw.TextStyle(fontSize: 8),
              textAlign: pw.TextAlign.center),
        pw.SizedBox(height: 4),
        pw.Text('*** $docTitle ***',
            style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
        pw.Text('Order: ${order.formattedOrderId} | $dateStr',
            style: const pw.TextStyle(fontSize: 7)),
        pw.Text('Cust: ${order.customerNameSnapshot}',
            style: const pw.TextStyle(fontSize: 8)),
        pw.SizedBox(height: 4),
        pw.Divider(thickness: 0.5),
        ...items.map((item) => pw.Padding(
              padding: const pw.EdgeInsets.symmetric(vertical: 1.5),
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Expanded(
                    child: pw.Text(
                      '${item.itemName} x ${item.quantityOrdered % 1 == 0 ? item.quantityOrdered.toInt() : item.quantityOrdered}',
                      style: const pw.TextStyle(fontSize: 7.5),
                    ),
                  ),
                  if (!isDeliveryChallan)
                    pw.Text(
                      '₹ ${(item.unitPrice * item.quantityOrdered).toStringAsFixed(0)}',
                      style: pw.TextStyle(
                          fontSize: 7.5, fontWeight: pw.FontWeight.bold),
                    ),
                ],
              ),
            )),
        pw.Divider(thickness: 0.5),
        if (!isDeliveryChallan) ...[
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text('TOTAL:',
                  style: pw.TextStyle(
                      fontSize: 9, fontWeight: pw.FontWeight.bold)),
              pw.Text('₹ ${order.estimateTotal.toStringAsFixed(2)}',
                  style: pw.TextStyle(
                      fontSize: 10, fontWeight: pw.FontWeight.bold)),
            ],
          ),
          pw.SizedBox(height: 4),
        ],
        pw.Text('Thank you! Visit again.',
            style: const pw.TextStyle(fontSize: 7)),
        pw.SizedBox(height: 10),
      ],
    );
  }

  pw.Widget _buildPdfRow(String label, String value, {bool isBold = false}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 1.5),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(label,
              style: pw.TextStyle(
                  fontSize: 9,
                  fontWeight:
                      isBold ? pw.FontWeight.bold : pw.FontWeight.normal)),
          pw.Text(value,
              style: pw.TextStyle(
                  fontSize: 10,
                  fontWeight:
                      isBold ? pw.FontWeight.bold : pw.FontWeight.normal,
                  color: isBold ? PdfColors.teal900 : PdfColors.black)),
        ],
      ),
    );
  }

  /// Prints to thermal printer or system printer
  Future<void> printReceipt(
    OrderDetails details, {
    bool isDeliveryChallan = false,
    bool isThermal58mm = false,
  }) async {
    final bytes = await generatePdfBytes(
      details,
      isDeliveryChallan: isDeliveryChallan,
      isThermal58mm: isThermal58mm,
    );
    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => bytes,
      name:
          '${details.order.formattedOrderId}_${isDeliveryChallan ? "Challan" : "Invoice"}',
    );
  }

  /// Shares PDF as a file via WhatsApp or other apps
  Future<void> sharePdf(
    OrderDetails details, {
    bool isDeliveryChallan = false,
  }) async {
    final bytes = await generatePdfBytes(
      details,
      isDeliveryChallan: isDeliveryChallan,
    );
    final tempDir = await getTemporaryDirectory();
    final filename =
        '${details.order.formattedOrderId}_${isDeliveryChallan ? "Challan" : "Bill"}.pdf';
    final file = File('${tempDir.path}/$filename');
    await file.writeAsBytes(bytes);

    await Share.shareXFiles(
      [XFile(file.path)],
      text:
          '${isDeliveryChallan ? "Delivery Challan" : "Order Receipt"} for ${details.order.customerNameSnapshot} (${details.order.formattedOrderId})',
    );
  }
}
