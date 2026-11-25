import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shop/database/database_helper.dart';
import 'package:shop/repositories/customer_repository.dart';
import 'package:shop/repositories/order_repository.dart';
import 'package:shop/repositories/product_repository.dart';
import 'package:shop/screens/lifetime_report_screen.dart';
import 'package:shop/services/invoice_pdf_service.dart';
import 'package:shop/services/shop_customization_service.dart';

class EveningReportScreen extends StatefulWidget {
  const EveningReportScreen({
    super.key,
    this.customerRepository,
    this.orderRepository,
    this.productRepository,
  });

  final CustomerRepository? customerRepository;
  final OrderRepository? orderRepository;
  final ProductRepository? productRepository;

  @override
  State<EveningReportScreen> createState() => _EveningReportScreenState();
}

class _EveningReportScreenState extends State<EveningReportScreen> {
  final GlobalKey _reportKey = GlobalKey();
  DateTime _selectedDate = DateTime.now();
  Map<String, dynamic>? _report;
  bool _loading = true;
  bool _isSharing = false;

  @override
  void initState() {
    super.initState();
    _loadReport();
  }

  Future<void> _loadReport() async {
    setState(() => _loading = true);
    try {
      final report =
          await DatabaseHelper.instance.getEveningClosingReport(_selectedDate);
      if (!mounted) return;
      setState(() {
        _report = report;
        _loading = false;
      });
    } catch (e) {
      debugPrint('Error loading evening closing report: $e');
      if (!mounted) return;
      setState(() {
        _loading = false;
      });
    }
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (!mounted) return;
    if (picked != null) {
      setState(() => _selectedDate = picked);
      _loadReport();
    }
  }

  Future<void> _shareReportAsImage() async {
    if (_report == null || _isSharing) return;
    setState(() => _isSharing = true);

    try {
      final boundary =
          _reportKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) {
        _shareReportTextFallback();
        return;
      }

      final image = await boundary.toImage(pixelRatio: 2.5);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) {
        _shareReportTextFallback();
        return;
      }

      final pngBytes = byteData.buffer.asUint8List();
      final tempDir = await getTemporaryDirectory();
      final dateSlug = DateFormat('yyyyMMdd').format(_selectedDate);
      final file = File('${tempDir.path}/Closing_Report_$dateSlug.png');
      await file.writeAsBytes(pngBytes);

      final shopName = ShopCustomizationService.instance.shopName;
      final dateStr = DateFormat('dd MMMM yyyy').format(_selectedDate);
      await Share.shareXFiles(
        [XFile(file.path)],
        text: '🌙 $shopName - Evening Business Closing Report ($dateStr)',
      );
    } catch (e) {
      debugPrint('Error capturing report image: $e');
      _shareReportTextFallback();
    } finally {
      if (mounted) {
        setState(() => _isSharing = false);
      }
    }
  }

  void _shareReportTextFallback() {
    if (_report == null) return;
    final shopName = ShopCustomizationService.instance.shopName;
    final dateStr = DateFormat('dd MMMM yyyy (EEEE)').format(_selectedDate);
    final totalSales = (_report!['totalSales'] as num).toDouble();
    final cashSales = (_report!['cashSales'] as num).toDouble();
    final upiSales = (_report!['upiSales'] as num).toDouble();
    final creditSales = (_report!['creditSales'] as num).toDouble();
    final directPayments = (_report!['directPayments'] as num).toDouble();
    final totalCollected = (_report!['totalCollectedToday'] as num?)?.toDouble() ??
        (cashSales + upiSales);
    final totalOrders = _report!['totalOrders'] as int;
    final completedOrders = _report!['completedOrders'] as int;
    final pendingOrders = _report!['pendingOrders'] as int;
    final topItem = _report!['topItemName'] as String;
    final topQty = (_report!['topItemQty'] as num).toDouble();
    final topUnit = _report!['topItemUnit'] as String;

    final buffer = StringBuffer();
    buffer.writeln('🌙 *$shopName - Evening Business Closing Summary*');
    buffer.writeln('📅 Date: $dateStr');
    buffer.writeln('------------------------------------------');
    buffer.writeln('💰 *Total Sales Billed: ₹ ${totalSales.toStringAsFixed(2)}*');
    buffer.writeln('📥 *Total Due/Payments Collected: ₹ ${totalCollected.toStringAsFixed(2)}*');
    buffer.writeln('💵 Cash Collected: ₹ ${cashSales.toStringAsFixed(2)}');
    buffer.writeln('📱 UPI Collected: ₹ ${upiSales.toStringAsFixed(2)}');
    buffer.writeln('📒 New Udhaar Given: ₹ ${creditSales.toStringAsFixed(2)}');
    if (directPayments > 0) {
      buffer.writeln('📥 Old Udhaar Recovered: ₹ ${directPayments.toStringAsFixed(2)}');
    }
    buffer.writeln('------------------------------------------');
    buffer.writeln('📦 Total Orders: $totalOrders');
    buffer.writeln('✅ Completed: $completedOrders | ⏳ Pending: $pendingOrders');
    if (topItem != 'None' && topQty > 0) {
      buffer.writeln(
          '🔥 Top Item Today: $topItem (${topQty % 1 == 0 ? topQty.toInt() : topQty.toStringAsFixed(1)} $topUnit)');
    }
    buffer.writeln('------------------------------------------');
    buffer.writeln('Generated automatically by Shop Notebook App');

    Share.share(buffer.toString());
  }

  Future<void> _showCollectionsDialog() async {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) {
        return FutureBuilder<List<Map<String, dynamic>>>(
          future: DatabaseHelper.instance.getCollectionsForDate(_selectedDate),
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return const AlertDialog(
                content: SizedBox(
                  height: 120,
                  child: Center(child: CircularProgressIndicator()),
                ),
              );
            }
            final list = snapshot.data!;
            final currency = NumberFormat.currency(locale: 'en_IN', symbol: '₹ ');
            final totalAmt = list.fold<double>(
                0.0, (sum, i) => sum + ((i['amount'] as num?)?.toDouble() ?? 0.0));

            return AlertDialog(
              title: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Today\'s Collections',
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                        Text('${list.length} payments • Total: ${currency.format(totalAmt)}',
                            style: const TextStyle(
                                fontSize: 12, color: Color(0xFF0F766E), fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Share as PDF',
                    icon: const Icon(Icons.picture_as_pdf, color: Color(0xFF0F766E)),
                    onPressed: list.isEmpty
                        ? null
                        : () => InvoicePdfService.instance
                            .shareDailyCollectionsPdf(_selectedDate, list),
                  ),
                ],
              ),
              content: SizedBox(
                width: double.maxFinite,
                child: list.isEmpty
                    ? const Padding(
                        padding: EdgeInsets.symmetric(vertical: 24),
                        child: Center(child: Text('No collections recorded for this date')),
                      )
                    : ListView.separated(
                        shrinkWrap: true,
                        itemCount: list.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (context, idx) {
                          final item = list[idx];
                          final name = item['customer_name'] as String? ?? 'Customer';
                          final phone = item['customer_phone'] as String? ?? '';
                          final location =
                              (item['customer_location'] as String?)?.trim() ?? '';
                          final amt = (item['amount'] as num?)?.toDouble() ?? 0.0;
                          final remDue =
                              (item['remaining_due'] as num?)?.toDouble() ?? 0.0;
                          final mode =
                              (item['payment_mode'] as String? ?? 'Cash').toUpperCase();
                          final dtStr = item['created_at'] as String?;
                          String timeStr = '';
                          if (dtStr != null) {
                            final dt = DateTime.tryParse(dtStr);
                            if (dt != null) timeStr = DateFormat('hh:mm a').format(dt);
                          }

                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Left details block
                                Expanded(
                                  flex: 3,
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        name,
                                        style: const TextStyle(
                                            fontWeight: FontWeight.bold, fontSize: 13),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      if (phone.isNotEmpty) ...[
                                        const SizedBox(height: 2),
                                        Row(
                                          children: [
                                            Icon(Icons.phone_outlined,
                                                size: 12, color: Colors.grey.shade600),
                                            const SizedBox(width: 4),
                                            Text(phone,
                                                style: TextStyle(
                                                    fontSize: 11,
                                                    color: Colors.grey.shade700)),
                                          ],
                                        ),
                                      ],
                                      if (location.isNotEmpty) ...[
                                        const SizedBox(height: 2),
                                        Row(
                                          children: [
                                            Icon(Icons.location_on_outlined,
                                                size: 12, color: Colors.teal.shade700),
                                            const SizedBox(width: 4),
                                            Expanded(
                                              child: Text(
                                                location,
                                                style: TextStyle(
                                                    fontSize: 11,
                                                    color: Colors.teal.shade800),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 8),
                                // Right financial block
                                Expanded(
                                  flex: 2,
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      Text(
                                        '+ ${currency.format(amt)}',
                                        style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 13,
                                            color: Colors.green.shade700),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        remDue > 0.01
                                            ? 'Due: ${currency.format(remDue)}'
                                            : 'Fully Cleared',
                                        style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.w600,
                                          color: remDue > 0.01
                                              ? Colors.red.shade700
                                              : Colors.teal,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 5, vertical: 1),
                                            decoration: BoxDecoration(
                                              color: mode == 'UPI'
                                                  ? Colors.blue.shade50
                                                  : Colors.green.shade50,
                                              borderRadius: BorderRadius.circular(4),
                                              border: Border.all(
                                                  color: mode == 'UPI'
                                                      ? Colors.blue.shade200
                                                      : Colors.green.shade200,
                                                  width: 0.5),
                                            ),
                                            child: Text(
                                              mode,
                                              style: TextStyle(
                                                fontSize: 9,
                                                fontWeight: FontWeight.bold,
                                                color: mode == 'UPI'
                                                    ? Colors.blue.shade800
                                                    : Colors.green.shade800,
                                              ),
                                            ),
                                          ),
                                          if (timeStr.isNotEmpty) ...[
                                            const SizedBox(width: 4),
                                            Text(timeStr,
                                                style: TextStyle(
                                                    fontSize: 9.5,
                                                    color: Colors.grey.shade600)),
                                          ],
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('CLOSE'),
                ),
                if (list.isNotEmpty)
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF0F766E)),
                    icon: const Icon(Icons.share, size: 16),
                    label: const Text('SHARE AS PDF'),
                    onPressed: () {
                      Navigator.pop(ctx);
                      InvoicePdfService.instance
                          .shareDailyCollectionsPdf(_selectedDate, list);
                    },
                  ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final currency = NumberFormat.currency(locale: 'en_IN', symbol: '₹ ');
    final dateHeading = DateFormat('dd MMMM yyyy').format(_selectedDate);

    final totalSales = (_report?['totalSales'] as num?)?.toDouble() ?? 0.0;
    final cashSales = (_report?['cashSales'] as num?)?.toDouble() ?? 0.0;
    final upiSales = (_report?['upiSales'] as num?)?.toDouble() ?? 0.0;
    final totalCollected =
        (_report?['totalCollectedToday'] as num?)?.toDouble() ?? (cashSales + upiSales);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Evening Closing Report',
            style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            tooltip: 'Lifetime Business Analytics',
            icon: const Icon(Icons.query_stats_rounded),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => const LifetimeReportScreen(),
                ),
              );
            },
          ),
          IconButton(
            tooltip: 'Select Date',
            icon: const Icon(Icons.calendar_month_outlined),
            onPressed: _pickDate,
          ),
          IconButton(
            tooltip: 'Share on WhatsApp as Image',
            icon: _isSharing
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.share),
            onPressed: _isSharing ? null : _shareReportAsImage,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _report == null
              ? const Center(child: Text('No data found for this date'))
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    // Header Date Banner
                    Card(
                      elevation: 0,
                      color: const Color(0xFFF1F5F9),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: const BorderSide(color: Color(0xFFE2E8F0)),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 12),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              children: [
                                const Icon(Icons.nightlight_round,
                                    color: Color(0xFF0F766E), size: 20),
                                const SizedBox(width: 10),
                                Text(
                                  dateHeading,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 15,
                                  ),
                                ),
                              ],
                            ),
                            TextButton.icon(
                              style: TextButton.styleFrom(
                                  visualDensity: VisualDensity.compact),
                              icon: const Icon(Icons.edit_calendar, size: 16),
                              label: const Text('Change'),
                              onPressed: _pickDate,
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),

                    // RepaintBoundary for crisp Image export
                    RepaintBoundary(
                      key: _reportKey,
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.05),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Dual Top Metric Cards: Total Sales Billed & Total Due Collected Today
                            Row(
                              children: [
                                // 1. Total Sales Card
                                Expanded(
                                  child: Container(
                                    padding: const EdgeInsets.all(14),
                                    decoration: BoxDecoration(
                                      gradient: const LinearGradient(
                                        colors: [Color(0xFF0F766E), Color(0xFF14B8A6)],
                                        begin: Alignment.topLeft,
                                        end: Alignment.bottomRight,
                                      ),
                                      borderRadius: BorderRadius.circular(14),
                                      boxShadow: [
                                        BoxShadow(
                                          color: const Color(0xFF0F766E).withValues(alpha: 0.2),
                                          blurRadius: 8,
                                          offset: const Offset(0, 3),
                                        ),
                                      ],
                                    ),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        const Text(
                                          'TOTAL SALES BILLED',
                                          style: TextStyle(
                                            color: Color(0xFFCCFBF1),
                                            fontSize: 10,
                                            fontWeight: FontWeight.w800,
                                            letterSpacing: 0.4,
                                          ),
                                        ),
                                        const SizedBox(height: 6),
                                        FittedBox(
                                          fit: BoxFit.scaleDown,
                                          child: Text(
                                            currency.format(totalSales),
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 20,
                                              fontWeight: FontWeight.w900,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          '${_report!['totalOrders']} orders created',
                                          style: const TextStyle(
                                            color: Colors.white70,
                                            fontSize: 10.5,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),

                                // 2. Total Due / Payments Collected Card
                                Expanded(
                                  child: Container(
                                    padding: const EdgeInsets.all(14),
                                    decoration: BoxDecoration(
                                      gradient: const LinearGradient(
                                        colors: [Color(0xFF1E40AF), Color(0xFF3B82F6)],
                                        begin: Alignment.topLeft,
                                        end: Alignment.bottomRight,
                                      ),
                                      borderRadius: BorderRadius.circular(14),
                                      boxShadow: [
                                        BoxShadow(
                                          color: const Color(0xFF1E40AF).withValues(alpha: 0.2),
                                          blurRadius: 8,
                                          offset: const Offset(0, 3),
                                        ),
                                      ],
                                    ),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        const Text(
                                          'TOTAL DUE COLLECTED',
                                          style: TextStyle(
                                            color: Color(0xFFDBEAFE),
                                            fontSize: 10,
                                            fontWeight: FontWeight.w800,
                                            letterSpacing: 0.4,
                                          ),
                                        ),
                                        const SizedBox(height: 6),
                                        FittedBox(
                                          fit: BoxFit.scaleDown,
                                          child: Text(
                                            currency.format(totalCollected),
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 20,
                                              fontWeight: FontWeight.w900,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          'Cash: ₹${cashSales.toStringAsFixed(0)} • UPI: ₹${upiSales.toStringAsFixed(0)}',
                                          style: const TextStyle(
                                            color: Colors.white70,
                                            fontSize: 10.5,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),

                            // Cash vs UPI vs Udhaar Collection Breakdown
                            const Text(
                              'COLLECTION & PAYMENT BREAKDOWN',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                                color: Colors.grey,
                                letterSpacing: 0.5,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Card(
                              elevation: 0,
                              color: const Color(0xFFF8FAFC),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                                side: const BorderSide(color: Color(0xFFE2E8F0)),
                              ),
                              child: Column(
                                children: [
                                  _buildReportRow(
                                    Icons.payments_outlined,
                                    'Cash Collected',
                                    currency.format(_report!['cashSales']),
                                    Colors.green.shade700,
                                  ),
                                  const Divider(height: 1),
                                  _buildReportRow(
                                    Icons.qr_code_2_rounded,
                                    'UPI / Online Received',
                                    currency.format(_report!['upiSales']),
                                    Colors.blue.shade700,
                                  ),
                                  const Divider(height: 1),
                                  _buildReportRow(
                                    Icons.book_outlined,
                                    'New Udhaar (Credit Given)',
                                    currency.format(_report!['creditSales']),
                                    Colors.red.shade700,
                                  ),
                                  if ((_report!['directPayments'] as num) > 0) ...[
                                    const Divider(height: 1),
                                    _buildReportRow(
                                      Icons.restore_outlined,
                                      'Old Udhaar Payments Recovered',
                                      currency.format(_report!['directPayments']),
                                      Colors.teal.shade800,
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            const SizedBox(height: 16),

                            // Order Fulfillment & Top Item
                            const Text(
                              'FULFILLMENT & TOP PRODUCT',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                                color: Colors.grey,
                                letterSpacing: 0.5,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Card(
                              elevation: 0,
                              color: const Color(0xFFF8FAFC),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                                side: const BorderSide(color: Color(0xFFE2E8F0)),
                              ),
                              child: Column(
                                children: [
                                  _buildReportRow(
                                    Icons.check_circle_outline,
                                    'Completed Orders',
                                    '${_report!['completedOrders']} orders',
                                    Colors.teal,
                                  ),
                                  const Divider(height: 1),
                                  _buildReportRow(
                                    Icons.pending_actions,
                                    'Pending Delivery Orders',
                                    '${_report!['pendingOrders']} orders',
                                    Colors.orange.shade800,
                                  ),
                                  if (_report!['topItemName'] != 'None' &&
                                      ((_report!['topItemQty'] as num?) ?? 0) > 0) ...[
                                    const Divider(height: 1),
                                    _buildReportRow(
                                      Icons.local_fire_department_rounded,
                                      'Top Selling Product',
                                      '${_report!['topItemName']} (${_report!['topItemQty']} ${_report!['topItemUnit']})',
                                      Colors.amber.shade900,
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            const SizedBox(height: 8),

                            // Footnote inside the printable image
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  ShopCustomizationService.instance.shopName,
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.grey.shade600,
                                  ),
                                ),
                                Text(
                                  dateHeading,
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: Colors.grey.shade600,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Button: View Collections List (Detailed customers with remaining dues)
                    FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF0F766E),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      onPressed: _showCollectionsDialog,
                      icon: const Icon(Icons.people_alt_outlined, color: Colors.white),
                      label: const Text(
                        'VIEW TODAY\'S COLLECTIONS LIST',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                          fontSize: 13,
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),

                    // Big Share Button (Image)
                    FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF25D366),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      onPressed: _isSharing ? null : _shareReportAsImage,
                      icon: _isSharing
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white),
                            )
                          : const Icon(Icons.share, color: Colors.white),
                      label: Text(
                        _isSharing ? 'PREPARING IMAGE...' : 'SHARE REPORT AS IMAGE ON WHATSAPP',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                          fontSize: 13.5,
                        ),
                      ),
                    ),
                  ],
                ),
    );
  }

  Widget _buildReportRow(
      IconData icon, String label, String value, Color color) {
    return ListTile(
      visualDensity: VisualDensity.compact,
      leading: Container(
        padding: const EdgeInsets.all(7),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, color: color, size: 18),
      ),
      title: Text(label,
          style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w500)),
      trailing: Text(
        value,
        style: TextStyle(
          fontSize: 13.5,
          fontWeight: FontWeight.bold,
          color: color,
        ),
      ),
    );
  }
}
