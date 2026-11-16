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

    final isRetailMode = ShopCustomizationService.instance.isPureOfflineMode;
    final dateStr =
        DateFormat('dd-MM-yyyy hh:mm a').format(order.createdAt);
    final docTitle = isDeliveryChallan
        ? 'DELIVERY CHALLAN'
        : (isRetailMode ? 'RETAIL CASH ESTIMATE / RECEIPT' : 'TAX INVOICE');

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
                          : (isRetailMode ? PdfColors.orange50 : PdfColors.teal50),
                      borderRadius: pw.BorderRadius.circular(6),
                      border: pw.Border.all(
                        color: isDeliveryChallan
                            ? PdfColors.amber800
                            : (isRetailMode ? PdfColors.orange700 : PdfColors.teal700),
                      ),
                    ),
                    child: pw.Text(
                      docTitle,
                      style: pw.TextStyle(
                        fontSize: 12,
                        fontWeight: pw.FontWeight.bold,
                        color: isDeliveryChallan
                            ? PdfColors.amber900
                            : (isRetailMode ? PdfColors.orange900 : PdfColors.teal900),
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

  /// Generates Customer Statement of Account / Khata Ledger PDF
  Future<Uint8List> generateCustomerKhataStatementPdf({
    required String customerName,
    String? customerPhone,
    required List<Map<String, dynamic>> ledgerEntries,
    required double totalDue,
    required double totalBilled,
    required double totalPaid,
  }) async {
    final pdf = pw.Document();
    final shopService = ShopCustomizationService.instance;
    final shopName = shopService.shopName;
    final shopPhone = shopService.shopPhone;
    final shopAddress = shopService.shopAddress;
    final gstin = shopService.gstin;
    final upiId = shopService.upiId;
    final dateStr = DateFormat('dd-MM-yyyy hh:mm a').format(DateTime.now());

    final upiUri = upiId.isNotEmpty
        ? 'upi://pay?pa=$upiId&pn=${Uri.encodeComponent(shopName)}&am=${totalDue > 0 ? totalDue.toStringAsFixed(2) : "0"}&cu=INR'
        : '';

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(24),
        build: (pw.Context context) {
          return [
            // Header
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              crossAxisAlignment: pw.CrossAxisAlignment.start,
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
                          style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700)),
                    if (shopPhone.isNotEmpty)
                      pw.Text('Phone: $shopPhone',
                          style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700)),
                    if (gstin.isNotEmpty)
                      pw.Text('GSTIN: $gstin',
                          style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
                  ],
                ),
                pw.Container(
                  padding: const pw.EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: pw.BoxDecoration(
                    color: PdfColors.teal50,
                    borderRadius: pw.BorderRadius.circular(8),
                    border: pw.Border.all(color: PdfColors.teal300),
                  ),
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.end,
                    children: [
                      pw.Text(
                        'KHATA STATEMENT',
                        style: pw.TextStyle(
                          fontSize: 13,
                          fontWeight: pw.FontWeight.bold,
                          color: PdfColors.teal900,
                        ),
                      ),
                      pw.SizedBox(height: 2),
                      pw.Text('Date: $dateStr',
                          style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700)),
                    ],
                  ),
                ),
              ],
            ),
            pw.SizedBox(height: 14),
            pw.Divider(thickness: 1, color: PdfColors.grey300),
            pw.SizedBox(height: 8),

            // Customer Info Box & Balance Banner
            pw.Row(
              children: [
                pw.Expanded(
                  flex: 3,
                  child: pw.Container(
                    padding: const pw.EdgeInsets.all(10),
                    decoration: pw.BoxDecoration(
                      color: PdfColors.grey100,
                      borderRadius: pw.BorderRadius.circular(8),
                    ),
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text('STATEMENT FOR:',
                            style: pw.TextStyle(
                                fontSize: 9,
                                fontWeight: pw.FontWeight.bold,
                                color: PdfColors.grey600)),
                        pw.SizedBox(height: 2),
                        pw.Text(
                          customerName,
                          style: pw.TextStyle(fontSize: 15, fontWeight: pw.FontWeight.bold),
                        ),
                        if (customerPhone != null && customerPhone.isNotEmpty)
                          pw.Text('Phone: $customerPhone',
                              style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700)),
                      ],
                    ),
                  ),
                ),
                pw.SizedBox(width: 12),
                pw.Expanded(
                  flex: 2,
                  child: pw.Container(
                    padding: const pw.EdgeInsets.all(10),
                    decoration: pw.BoxDecoration(
                      color: totalDue > 0.01 ? PdfColors.red50 : PdfColors.green50,
                      borderRadius: pw.BorderRadius.circular(8),
                      border: pw.Border.all(
                        color: totalDue > 0.01 ? PdfColors.red300 : PdfColors.green300,
                      ),
                    ),
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.center,
                      children: [
                        pw.Text(
                          totalDue > 0.01 ? 'NET BALANCE DUE' : 'ACCOUNT STATUS',
                          style: pw.TextStyle(
                            fontSize: 9,
                            fontWeight: pw.FontWeight.bold,
                            color: totalDue > 0.01 ? PdfColors.red900 : PdfColors.green900,
                          ),
                        ),
                        pw.SizedBox(height: 4),
                        pw.Text(
                          totalDue > 0.01 ? '₹ ${totalDue.toStringAsFixed(2)}' : 'ALL SETTLED',
                          style: pw.TextStyle(
                            fontSize: 16,
                            fontWeight: pw.FontWeight.bold,
                            color: totalDue > 0.01 ? PdfColors.red900 : PdfColors.green900,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            pw.SizedBox(height: 14),

            // Ledger Table
            pw.Table(
              border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
              columnWidths: const {
                0: pw.FlexColumnWidth(2.2),
                1: pw.FlexColumnWidth(3.8),
                2: pw.FlexColumnWidth(2.0),
                3: pw.FlexColumnWidth(2.0),
                4: pw.FlexColumnWidth(2.2),
              },
              children: [
                pw.TableRow(
                  decoration: const pw.BoxDecoration(color: PdfColors.teal700),
                  children: [
                    _cellHeader('Date'),
                    _cellHeader('Particulars / Ref'),
                    _cellHeader('Debit (Gave ₹)'),
                    _cellHeader('Credit (Got ₹)'),
                    _cellHeader('Balance (₹)'),
                  ],
                ),
                ...ledgerEntries.map((e) {
                  final date = e['date'] as DateTime? ?? DateTime.now();
                  final dateFormatted = DateFormat('dd/MM/yyyy').format(date);
                  final title = e['title'] as String? ?? '';
                  final debit = (e['debit'] as num?)?.toDouble() ?? 0.0;
                  final credit = (e['credit'] as num?)?.toDouble() ?? 0.0;
                  final bal = (e['running_balance'] as num?)?.toDouble() ?? 0.0;

                  return pw.TableRow(
                    decoration: pw.BoxDecoration(
                      color: debit > 0 ? PdfColors.white : PdfColors.green50,
                    ),
                    children: [
                      _cellText(dateFormatted, align: pw.TextAlign.center),
                      _cellText(title),
                      _cellText(
                        debit > 0 ? debit.toStringAsFixed(2) : '-',
                        align: pw.TextAlign.right,
                        color: debit > 0 ? PdfColors.red900 : PdfColors.black,
                      ),
                      _cellText(
                        credit > 0 ? credit.toStringAsFixed(2) : '-',
                        align: pw.TextAlign.right,
                        color: credit > 0 ? PdfColors.green900 : PdfColors.black,
                      ),
                      _cellText(
                        bal.toStringAsFixed(2),
                        align: pw.TextAlign.right,
                        bold: true,
                      ),
                    ],
                  );
                }),
              ],
            ),
            pw.SizedBox(height: 14),

            // Summary & QR Block
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              crossAxisAlignment: pw.CrossAxisAlignment.end,
              children: [
                if (upiId.isNotEmpty && totalDue > 0.01)
                  pw.Row(
                    children: [
                      pw.BarcodeWidget(
                        barcode: pw.Barcode.qrCode(),
                        data: upiUri,
                        width: 75,
                        height: 75,
                      ),
                      pw.SizedBox(width: 10),
                      pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Text('Scan to Pay via UPI',
                              style: pw.TextStyle(
                                  fontWeight: pw.FontWeight.bold, fontSize: 10)),
                          pw.Text('UPI ID: $upiId',
                              style: const pw.TextStyle(
                                  fontSize: 8, color: PdfColors.grey700)),
                          pw.Text('GPay / PhonePe / Paytm',
                              style: const pw.TextStyle(
                                  fontSize: 8, color: PdfColors.grey600)),
                        ],
                      ),
                    ],
                  )
                else
                  pw.SizedBox(width: 10),
                pw.Container(
                  width: 200,
                  padding: const pw.EdgeInsets.all(10),
                  decoration: pw.BoxDecoration(
                    color: PdfColors.grey100,
                    borderRadius: pw.BorderRadius.circular(8),
                    border: pw.Border.all(color: PdfColors.grey300),
                  ),
                  child: pw.Column(
                    children: [
                      _summaryRow('Total Billed:', '₹ ${totalBilled.toStringAsFixed(2)}'),
                      pw.SizedBox(height: 4),
                      _summaryRow('Total Paid:', '₹ ${totalPaid.toStringAsFixed(2)}'),
                      pw.Divider(thickness: 0.5, color: PdfColors.grey400),
                      _summaryRow(
                        'Net Balance Due:',
                        '₹ ${totalDue.toStringAsFixed(2)}',
                        bold: true,
                        color: totalDue > 0 ? PdfColors.red900 : PdfColors.green900,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            pw.SizedBox(height: 24),
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text('Computer-generated Khata Statement',
                    style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey500)),
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.Text('For $shopName',
                        style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9)),
                    pw.SizedBox(height: 20),
                    pw.Text('Authorized Signatory',
                        style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600)),
                  ],
                ),
              ],
            ),
          ];
        },
      ),
    );

    return pdf.save();
  }

  /// Generates Market Udhaar Outstanding Summary PDF report for the business owner
  Future<Uint8List> generateKhataMarketSummaryPdf(
    List<Map<String, dynamic>> khataList,
    Map<String, dynamic> metrics,
  ) async {
    final pdf = pw.Document();
    final shopService = ShopCustomizationService.instance;
    final shopName = shopService.shopName;
    final dateStr = DateFormat('dd-MM-yyyy hh:mm a').format(DateTime.now());

    final totalDue = (metrics['totalMarketDue'] as num?)?.toDouble() ?? 0.0;
    final overdue30 = (metrics['overdue30Days'] as num?)?.toDouble() ?? 0.0;
    final dueCount = (metrics['dueCustomersCount'] as num?)?.toInt() ?? 0;

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(24),
        build: (pw.Context context) {
          return [
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
                    pw.Text('MARKET CREDIT & UDHAAR REPORT',
                        style: pw.TextStyle(
                          fontSize: 12,
                          fontWeight: pw.FontWeight.bold,
                          color: PdfColors.red900,
                        )),
                  ],
                ),
                pw.Text('Generated: $dateStr',
                    style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700)),
              ],
            ),
            pw.SizedBox(height: 10),
            pw.Divider(thickness: 1, color: PdfColors.grey300),
            pw.SizedBox(height: 8),

            // 3 Summary Metric Cards
            pw.Row(
              children: [
                pw.Expanded(
                  child: _metricCard('TOTAL OUTSTANDING', '₹ ${totalDue.toStringAsFixed(2)}',
                      PdfColors.red900, PdfColors.red50),
                ),
                pw.SizedBox(width: 8),
                pw.Expanded(
                  child: _metricCard('OVERDUE (>30 DAYS)', '₹ ${overdue30.toStringAsFixed(2)}',
                      PdfColors.orange900, PdfColors.orange50),
                ),
                pw.SizedBox(width: 8),
                pw.Expanded(
                  child: _metricCard('ACTIVE DEBTORS', '$dueCount Customers',
                      PdfColors.teal900, PdfColors.teal50),
                ),
              ],
            ),
            pw.SizedBox(height: 14),

            // Customers Table
            pw.Table(
              border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
              columnWidths: const {
                0: pw.FlexColumnWidth(0.8),
                1: pw.FlexColumnWidth(3.5),
                2: pw.FlexColumnWidth(2.2),
                3: pw.FlexColumnWidth(1.8),
                4: pw.FlexColumnWidth(2.2),
              },
              children: [
                pw.TableRow(
                  decoration: const pw.BoxDecoration(color: PdfColors.grey800),
                  children: [
                    _cellHeader('#', color: PdfColors.white),
                    _cellHeader('Customer Name', color: PdfColors.white),
                    _cellHeader('Phone', color: PdfColors.white),
                    _cellHeader('Ageing (Days)', color: PdfColors.white),
                    _cellHeader('Balance Due (₹)', color: PdfColors.white),
                  ],
                ),
                ...khataList.asMap().entries.map((entry) {
                  final index = entry.key + 1;
                  final item = entry.value;
                  final name = item['customer_name'] as String? ?? '';
                  final phone = item['customer_phone'] as String? ?? '-';
                  final due = (item['balance_due'] as num?)?.toDouble() ?? 0.0;
                  final days = (item['days_overdue'] as num?)?.toInt() ?? 0;

                  return pw.TableRow(
                    decoration: pw.BoxDecoration(
                      color: days >= 30 ? PdfColors.red50 : PdfColors.white,
                    ),
                    children: [
                      _cellText('$index', align: pw.TextAlign.center),
                      _cellText(name, bold: true),
                      _cellText(phone, align: pw.TextAlign.center),
                      _cellText(
                        days > 0 ? '$days days' : 'Current',
                        align: pw.TextAlign.center,
                        color: days >= 30 ? PdfColors.red900 : PdfColors.grey800,
                        bold: days >= 30,
                      ),
                      _cellText(
                        due.toStringAsFixed(2),
                        align: pw.TextAlign.right,
                        bold: true,
                        color: due > 0 ? PdfColors.red900 : PdfColors.green900,
                      ),
                    ],
                  );
                }),
              ],
            ),
            pw.SizedBox(height: 16),
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text('Total market balance across all customers: ₹ ${totalDue.toStringAsFixed(2)}',
                    style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)),
                pw.Text('Shop Management System',
                    style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey500)),
              ],
            ),
          ];
        },
      ),
    );

    return pdf.save();
  }

  static pw.Widget _metricCard(
      String title, String value, PdfColor textColor, PdfColor bgColor) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(8),
      decoration: pw.BoxDecoration(
        color: bgColor,
        borderRadius: pw.BorderRadius.circular(6),
        border: pw.Border.all(color: textColor, width: 0.5),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(title,
              style: pw.TextStyle(fontSize: 7, fontWeight: pw.FontWeight.bold, color: textColor)),
          pw.SizedBox(height: 2),
          pw.Text(value,
              style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold, color: textColor)),
        ],
      ),
    );
  }

  static pw.Widget _summaryRow(String label, String value,
      {bool bold = false, PdfColor? color}) {
    return pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.Text(label,
            style: pw.TextStyle(
                fontSize: 9,
                fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal)),
        pw.Text(value,
            style: pw.TextStyle(
                fontSize: 9,
                fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
                color: color ?? PdfColors.black)),
      ],
    );
  }

  static pw.Widget _cellHeader(String text, {PdfColor color = PdfColors.white}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.all(5),
      child: pw.Text(
        text,
        textAlign: pw.TextAlign.center,
        style: pw.TextStyle(color: color, fontSize: 8, fontWeight: pw.FontWeight.bold),
      ),
    );
  }

  static pw.Widget _cellText(
    String text, {
    pw.TextAlign align = pw.TextAlign.left,
    bool bold = false,
    PdfColor color = PdfColors.black,
  }) {
    return pw.Padding(
      padding: const pw.EdgeInsets.all(5),
      child: pw.Text(
        text,
        textAlign: align,
        style: pw.TextStyle(
          fontSize: 8,
          fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
          color: color,
        ),
      ),
    );
  }

  /// Shares Customer Khata Statement PDF
  Future<void> shareCustomerKhataStatement({
    required String customerName,
    String? customerPhone,
    required List<Map<String, dynamic>> ledgerEntries,
    required double totalDue,
    required double totalBilled,
    required double totalPaid,
  }) async {
    final bytes = await generateCustomerKhataStatementPdf(
      customerName: customerName,
      customerPhone: customerPhone,
      ledgerEntries: ledgerEntries,
      totalDue: totalDue,
      totalBilled: totalBilled,
      totalPaid: totalPaid,
    );
    final tempDir = await getTemporaryDirectory();
    final cleanName = customerName.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_');
    final file = File('${tempDir.path}/Khata_Statement_${cleanName}.pdf');
    await file.writeAsBytes(bytes);

    await Share.shareXFiles(
      [XFile(file.path)],
      text: 'Khata Statement of Account for $customerName (Due: ₹ ${totalDue.toStringAsFixed(2)})',
    );
  }

  /// Prints Customer Khata Statement PDF
  Future<void> printCustomerKhataStatement({
    required String customerName,
    String? customerPhone,
    required List<Map<String, dynamic>> ledgerEntries,
    required double totalDue,
    required double totalBilled,
    required double totalPaid,
  }) async {
    final bytes = await generateCustomerKhataStatementPdf(
      customerName: customerName,
      customerPhone: customerPhone,
      ledgerEntries: ledgerEntries,
      totalDue: totalDue,
      totalBilled: totalBilled,
      totalPaid: totalPaid,
    );
    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => bytes,
      name: 'Khata_Statement_$customerName',
    );
  }

  /// Shares Market Udhaar Summary PDF
  Future<void> shareKhataMarketSummary(
    List<Map<String, dynamic>> khataList,
    Map<String, dynamic> metrics,
  ) async {
    final bytes = await generateKhataMarketSummaryPdf(khataList, metrics);
    final tempDir = await getTemporaryDirectory();
    final file = File('${tempDir.path}/Market_Udhaar_Summary_${DateFormat("ddMMyyyy").format(DateTime.now())}.pdf');
    await file.writeAsBytes(bytes);

    await Share.shareXFiles(
      [XFile(file.path)],
      text: 'Market Udhaar Summary Report - Total Outstanding: ₹ ${(metrics["totalMarketDue"] as num?)?.toDouble().toStringAsFixed(2) ?? "0"}',
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
