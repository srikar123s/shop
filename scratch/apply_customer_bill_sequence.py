import sys

# 3. Update share_service.dart
path_share = r'lib\services\share_service.dart'
with open(path_share, 'r', encoding='utf-8') as f:
    cs = f.read()

target_share_def = """  static Future<void> shareOrderDetails(OrderDetails details) async {"""
rep_share_def = """  static Future<void> shareOrderDetails(
    OrderDetails details, {
    int? customerBillNumber,
  }) async {"""

target_share_exec = """    try {
      final imageFiles = await _generateEstimateImages(
        title: 'ORDER RECEIPT',
        orderId: order.formattedOrderId,
        customerName: order.customerNameSnapshot,
        phone: '',
        dateStr: DateFormat('dd MMM yyyy, hh:mm a').format(order.createdAt),
        items: itemsData,
        grandTotal: finalTotal,
        billBreakdown: breakdown,
      );

      await Share.shareXFiles(
        imageFiles.map((f) => XFile(f.path)).toList(),
        text: 'Order  for  ( items)',
      );
    } catch (_) {
      await _shareOrderAsText(details, billBreakdown: breakdown);
    }"""

rep_share_exec = """    final billLabel = customerBillNumber != null
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
    }"""

target_share_text_def = """  static Future<void> _shareOrderAsText(OrderDetails details,
      {BillBreakdown? billBreakdown}) async {
    final shopName = ShopCustomizationService.instance.shopName;
    final order = details.order;
    final breakdown = billBreakdown ?? order.billBreakdown;
    final buffer = StringBuffer();
    buffer.writeln('📋 *$shopName • ORDER ${order.formattedOrderId}*');"""

rep_share_text_def = """  static Future<void> _shareOrderAsText(
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
    buffer.writeln('📋 *$shopName • $billTitle*');"""

assert target_share_def in cs, "target_share_def not found"
assert target_share_exec in cs, "target_share_exec not found"
assert target_share_text_def in cs, "target_share_text_def not found"

cs = cs.replace(target_share_def, rep_share_def, 1)
cs = cs.replace(target_share_exec, rep_share_exec, 1)
cs = cs.replace(target_share_text_def, rep_share_text_def, 1)

with open(path_share, 'w', encoding='utf-8') as f:
    f.write(cs)
print("share_service updated successfully")


# 4. Update invoice_pdf_service.dart
path_pdf = r'lib\services\invoice_pdf_service.dart'
with open(path_pdf, 'r', encoding='utf-8') as f:
    cp = f.read()

target_pdf_gen = """  Future<Uint8List> generatePdfBytes(
    OrderDetails details, {
    bool isDeliveryChallan = false,
    bool isThermal58mm = false,
  }) async {"""

rep_pdf_gen = """  Future<Uint8List> generatePdfBytes(
    OrderDetails details, {
    bool isDeliveryChallan = false,
    bool isThermal58mm = false,
    int? customerBillNumber,
  }) async {"""

target_call_thermal = """          if (isThermal58mm) {
            return _buildThermalLayout(
              shopName: shopName,
              shopPhone: shopPhone,
              shopAddress: shopAddress,
              gstin: gstin,
              upiId: upiId,
              docTitle: docTitle,
              order: order,
              items: items,
              breakdown: breakdown,
              dateStr: dateStr,
              isDeliveryChallan: isDeliveryChallan,
              digitalStamp: digitalStamp,
            );
          }"""

rep_call_thermal = """          if (isThermal58mm) {
            return _buildThermalLayout(
              shopName: shopName,
              shopPhone: shopPhone,
              shopAddress: shopAddress,
              gstin: gstin,
              upiId: upiId,
              docTitle: docTitle,
              order: order,
              items: items,
              breakdown: breakdown,
              dateStr: dateStr,
              isDeliveryChallan: isDeliveryChallan,
              digitalStamp: digitalStamp,
              customerBillNumber: customerBillNumber,
            );
          }"""

target_a4_ord = """                      pw.Text(order.formattedOrderId,
                          style: pw.TextStyle(
                              fontWeight: pw.FontWeight.bold,
                              fontSize: 13,
                              color: PdfColors.teal800)),"""

rep_a4_ord = """                      pw.Text(
                        customerBillNumber != null
                            ? 'Bill #$customerBillNumber (${order.formattedOrderId})'
                            : order.formattedOrderId,
                        style: pw.TextStyle(
                            fontWeight: pw.FontWeight.bold,
                            fontSize: 13,
                            color: PdfColors.teal800),
                      ),"""

target_thermal_def = """  pw.Widget _buildThermalLayout({
    required String shopName,
    required String shopPhone,
    required String shopAddress,
    required String gstin,
    required String upiId,
    required String docTitle,
    required OrderEntity order,
    required List<OrderItemEntity> items,
    required BillBreakdown? breakdown,
    required String dateStr,
    required bool isDeliveryChallan,
    required String digitalStamp,
  }) {"""

rep_thermal_def = """  pw.Widget _buildThermalLayout({
    required String shopName,
    required String shopPhone,
    required String shopAddress,
    required String gstin,
    required String upiId,
    required String docTitle,
    required OrderEntity order,
    required List<OrderItemEntity> items,
    required BillBreakdown? breakdown,
    required String dateStr,
    required bool isDeliveryChallan,
    required String digitalStamp,
    int? customerBillNumber,
  }) {"""

target_thermal_meta = """        // Order metadata
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text('Order: ${order.formattedOrderId}',
                style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold)),
            pw.Text(dateStr, style: const pw.TextStyle(fontSize: 7.5)),
          ],
        ),"""

rep_thermal_meta = """        // Order metadata
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(
              customerBillNumber != null
                  ? 'Bill: Bill #$customerBillNumber (${order.formattedOrderId})'
                  : 'Order: ${order.formattedOrderId}',
              style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold),
            ),
            pw.Text(dateStr, style: const pw.TextStyle(fontSize: 7.5)),
          ],
        ),"""

target_pdf_print = """  /// Prints to thermal printer or system printer
  Future<void> printReceipt(
    OrderDetails details, {
    bool isDeliveryChallan = false,
    bool isThermal58mm = false,
  }) async {
    final bytes = await generatePdfBytes(
      details,
      isDeliveryChallan: isDeliveryChallan,
      isThermal58mm: isThermal58mm,
    );"""

rep_pdf_print = """  /// Prints to thermal printer or system printer
  Future<void> printReceipt(
    OrderDetails details, {
    bool isDeliveryChallan = false,
    bool isThermal58mm = false,
    int? customerBillNumber,
  }) async {
    final bytes = await generatePdfBytes(
      details,
      isDeliveryChallan: isDeliveryChallan,
      isThermal58mm: isThermal58mm,
      customerBillNumber: customerBillNumber,
    );"""

target_pdf_share = """  /// Shares PDF as a file via WhatsApp or other apps
  Future<void> sharePdf(
    OrderDetails details, {
    bool isDeliveryChallan = false,
  }) async {
    final bytes = await generatePdfBytes(
      details,
      isDeliveryChallan: isDeliveryChallan,
    );"""

rep_pdf_share = """  /// Shares PDF as a file via WhatsApp or other apps
  Future<void> sharePdf(
    OrderDetails details, {
    bool isDeliveryChallan = false,
    int? customerBillNumber,
  }) async {
    final bytes = await generatePdfBytes(
      details,
      isDeliveryChallan: isDeliveryChallan,
      customerBillNumber: customerBillNumber,
    );"""

assert target_pdf_gen in cp, "target_pdf_gen not found"
assert target_call_thermal in cp, "target_call_thermal not found"
assert target_a4_ord in cp, "target_a4_ord not found"
assert target_thermal_def in cp, "target_thermal_def not found"
assert target_thermal_meta in cp, "target_thermal_meta not found"
assert target_pdf_print in cp, "target_pdf_print not found"
assert target_pdf_share in cp, "target_pdf_share not found"

cp = cp.replace(target_pdf_gen, rep_pdf_gen, 1)
cp = cp.replace(target_call_thermal, rep_call_thermal, 1)
cp = cp.replace(target_a4_ord, rep_a4_ord, 1)
cp = cp.replace(target_thermal_def, rep_thermal_def, 1)
cp = cp.replace(target_thermal_meta, rep_thermal_meta, 1)
cp = cp.replace(target_pdf_print, rep_pdf_print, 1)
cp = cp.replace(target_pdf_share, rep_pdf_share, 1)

with open(path_pdf, 'w', encoding='utf-8') as f:
    f.write(cp)
print("invoice_pdf_service updated successfully")
