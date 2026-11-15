import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shop/database/database_helper.dart';
import 'package:shop/services/shop_customization_service.dart';

class EveningReportScreen extends StatefulWidget {
  const EveningReportScreen({super.key});

  @override
  State<EveningReportScreen> createState() => _EveningReportScreenState();
}

class _EveningReportScreenState extends State<EveningReportScreen> {
  DateTime _selectedDate = DateTime.now();
  Map<String, dynamic>? _report;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadReport();
  }

  Future<void> _loadReport() async {
    setState(() => _loading = true);
    final report =
        await DatabaseHelper.instance.getEveningClosingReport(_selectedDate);
    if (!mounted) return;
    setState(() {
      _report = report;
      _loading = false;
    });
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (picked != null) {
      setState(() => _selectedDate = picked);
      _loadReport();
    }
  }

  void _shareReport() {
    if (_report == null) return;
    final shopName = ShopCustomizationService.instance.shopName;
    final dateStr = DateFormat('dd MMMM yyyy (EEEE)').format(_selectedDate);
    final totalSales = (_report!['totalSales'] as num).toDouble();
    final cashSales = (_report!['cashSales'] as num).toDouble();
    final upiSales = (_report!['upiSales'] as num).toDouble();
    final creditSales = (_report!['creditSales'] as num).toDouble();
    final directPayments = (_report!['directPayments'] as num).toDouble();
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
    buffer.writeln('💵 Cash Collected: ₹ ${cashSales.toStringAsFixed(2)}');
    buffer.writeln('📱 UPI Collected: ₹ ${upiSales.toStringAsFixed(2)}');
    buffer.writeln('📒 New Udhaar Given: ₹ ${creditSales.toStringAsFixed(2)}');
    if (directPayments > 0) {
      buffer.writeln(
          '📥 Old Udhaar Recovered: ₹ ${directPayments.toStringAsFixed(2)}');
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

  @override
  Widget build(BuildContext context) {
    final currency = NumberFormat.currency(locale: 'en_IN', symbol: '₹ ');
    final dateHeading = DateFormat('dd MMMM yyyy').format(_selectedDate);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Evening Closing Report',
            style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            tooltip: 'Select Date',
            icon: const Icon(Icons.calendar_month_outlined),
            onPressed: _pickDate,
          ),
          IconButton(
            tooltip: 'Share on WhatsApp',
            icon: const Icon(Icons.share),
            onPressed: _shareReport,
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

                    // Total Sales Card
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF0F766E), Color(0xFF14B8A6)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color:
                                const Color(0xFF0F766E).withValues(alpha: 0.25),
                            blurRadius: 16,
                            offset: const Offset(0, 6),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'TOTAL SALES BILLED TODAY',
                            style: TextStyle(
                              color: Color(0xFFCCFBF1),
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.5,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            currency.format(_report!['totalSales']),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 28,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            '${_report!['totalOrders']} total orders created',
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Cash vs UPI vs Udhaar Collection Breakdown
                    const Text(
                      'COLLECTION & PAYMENT BREAKDOWN',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: Colors.grey,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Card(
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
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: Colors.grey,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Card(
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
                          const Divider(height: 1),
                          _buildReportRow(
                            Icons.local_fire_department_rounded,
                            'Top Selling Product',
                            '${_report!['topItemName']} (${_report!['topItemQty']} ${_report!['topItemUnit']})',
                            Colors.amber.shade900,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Big Share Button
                    FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF25D366),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      onPressed: _shareReport,
                      icon: const Icon(Icons.share, color: Colors.white),
                      label: const Text(
                        'SHARE CLOSING REPORT ON WHATSAPP',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                          fontSize: 14,
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
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, color: color, size: 20),
      ),
      title: Text(label,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
      trailing: Text(
        value,
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.bold,
          color: color,
        ),
      ),
    );
  }
}
