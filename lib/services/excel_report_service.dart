import 'dart:io';
import 'package:excel/excel.dart' as xl;
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

class ExcelReportService {
  ExcelReportService._();
  static final ExcelReportService instance = ExcelReportService._();

  Future<void> exportAndShareLifetimeReport(
    Map<String, dynamic> report, {
    String dateRangeLabel = 'Lifetime',
    String? locationFilter,
    String? staffFilter,
  }) async {
    final excel = xl.Excel.createExcel();

    // Remove default Sheet1
    excel.delete('Sheet1');

    // 1. Executive Summary Sheet
    _buildSummarySheet(excel, report, dateRangeLabel, locationFilter, staffFilter);

    // 2. High Due Udhaar Watchlist Sheet
    _buildUdhaarSheet(excel, report);

    // 3. Top Buyers & Payers Sheet
    _buildCustomersSheet(excel, report);

    // 4. Dormant Customers Sheet (Win-Back)
    _buildDormantSheet(excel, report);

    // 5. Product & Category Performance Sheet
    _buildProductsSheet(excel, report);

    // 6. Collections Ledger Sheet
    _buildCollectionsSheet(excel, report);

    // 7. Staff Performance Sheet
    _buildStaffSheet(excel, report);

    // Save and Share
    final fileBytes = excel.save();
    if (fileBytes == null) return;

    final tempDir = await getTemporaryDirectory();
    final dateSlug = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
    final file = File('${tempDir.path}/Lifetime_Business_Audit_$dateSlug.xlsx');
    await file.writeAsBytes(fileBytes);

    await Share.shareXFiles(
      [XFile(file.path)],
      subject: 'Lifetime Business Audit Report - $dateRangeLabel',
      text: 'Lifetime Business Audit & Analytics Excel Report ($dateRangeLabel).',
    );
  }

  void _buildSummarySheet(
    xl.Excel excel,
    Map<String, dynamic> r,
    String dateRange,
    String? location,
    String? staff,
  ) {
    final sheet = excel['Executive Summary'];

    sheet.appendRow([xl.TextCellValue('BUSINESS AUDIT & LIFETIME SUMMARY')]);
    sheet.appendRow([xl.TextCellValue('Generated On'), xl.TextCellValue(DateFormat('dd MMM yyyy, hh:mm a').format(DateTime.now()))]);
    sheet.appendRow([xl.TextCellValue('Date Range Filter'), xl.TextCellValue(dateRange)]);
    if (location != null) sheet.appendRow([xl.TextCellValue('Location Filter'), xl.TextCellValue(location)]);
    if (staff != null) sheet.appendRow([xl.TextCellValue('Staff Filter'), xl.TextCellValue(staff)]);
    sheet.appendRow([xl.TextCellValue('')]);

    // Financial Health Grade
    sheet.appendRow([xl.TextCellValue('STORE FINANCIAL HEALTH'), xl.TextCellValue('${r['healthGrade']} (${r['healthScore']}/100)')]);
    sheet.appendRow([xl.TextCellValue('Health Diagnosis'), xl.TextCellValue(r['healthSummary']?.toString() ?? '')]);
    sheet.appendRow([xl.TextCellValue('')]);

    // Core Financials
    sheet.appendRow([xl.TextCellValue('METRIC'), xl.TextCellValue('VALUE')]);
    sheet.appendRow([xl.TextCellValue('Total Sales (Billed)'), xl.DoubleCellValue((r['totalSales'] as num?)?.toDouble() ?? 0.0)]);
    sheet.appendRow([xl.TextCellValue('Total Collected (Cash + UPI)'), xl.DoubleCellValue((r['totalCollected'] as num?)?.toDouble() ?? 0.0)]);
    sheet.appendRow([xl.TextCellValue('Current Market Udhaar (Due)'), xl.DoubleCellValue((r['totalMarketDue'] as num?)?.toDouble() ?? 0.0)]);
    sheet.appendRow([xl.TextCellValue('Advance Deposit Pool'), xl.DoubleCellValue((r['advancePoolTotal'] as num?)?.toDouble() ?? 0.0)]);
    sheet.appendRow([xl.TextCellValue('Advance Accounts Count'), xl.IntCellValue((r['advanceAccountsCount'] as num?)?.toInt() ?? 0)]);
    sheet.appendRow([xl.TextCellValue('')]);

    // Order & Basket Size
    sheet.appendRow([xl.TextCellValue('Total Orders Billed'), xl.IntCellValue((r['totalOrders'] as num?)?.toInt() ?? 0)]);
    sheet.appendRow([xl.TextCellValue('Completed / Delivered Orders'), xl.IntCellValue((r['completedOrders'] as num?)?.toInt() ?? 0)]);
    sheet.appendRow([xl.TextCellValue('Pending Delivery Orders'), xl.IntCellValue((r['pendingOrders'] as num?)?.toInt() ?? 0)]);
    sheet.appendRow([xl.TextCellValue('Average Order Value (AOV)'), xl.DoubleCellValue((r['averageOrderValue'] as num?)?.toDouble() ?? 0.0)]);
    sheet.appendRow([xl.TextCellValue('Average Basket Size (Items/Bill)'), xl.DoubleCellValue((r['avgBasketSize'] as num?)?.toDouble() ?? 0.0)]);
    sheet.appendRow([xl.TextCellValue('Total Items Sold (Units)'), xl.DoubleCellValue((r['totalItemsSold'] as num?)?.toDouble() ?? 0.0)]);
    sheet.appendRow([xl.TextCellValue('')]);

    // Discounts & Taxes
    sheet.appendRow([xl.TextCellValue('Total Discounts Given'), xl.DoubleCellValue((r['totalDiscountsGiven'] as num?)?.toDouble() ?? 0.0)]);
    sheet.appendRow([xl.TextCellValue('Total GST Tax Billed'), xl.DoubleCellValue((r['totalGstBilled'] as num?)?.toDouble() ?? 0.0)]);
    sheet.appendRow([xl.TextCellValue('')]);

    // Cash vs UPI Collections
    sheet.appendRow([xl.TextCellValue('Cash Collections (Rs.)'), xl.DoubleCellValue((r['cashCollected'] as num?)?.toDouble() ?? 0.0)]);
    sheet.appendRow([xl.TextCellValue('Cash Collection Share (%)'), xl.DoubleCellValue((r['cashPercentage'] as num?)?.toDouble() ?? 0.0)]);
    sheet.appendRow([xl.TextCellValue('UPI / Online Received (Rs.)'), xl.DoubleCellValue((r['upiCollected'] as num?)?.toDouble() ?? 0.0)]);
    sheet.appendRow([xl.TextCellValue('UPI Collection Share (%)'), xl.DoubleCellValue((r['upiPercentage'] as num?)?.toDouble() ?? 0.0)]);
    sheet.appendRow([xl.TextCellValue('')]);

    // Customer Retention & Debt Clearance
    sheet.appendRow([xl.TextCellValue('Total Unique Customers'), xl.IntCellValue((r['uniqueCustomerCount'] as num?)?.toInt() ?? 0)]);
    sheet.appendRow([xl.TextCellValue('Repeat Customers (2+ Orders)'), xl.IntCellValue((r['repeatCustomerCount'] as num?)?.toInt() ?? 0)]);
    sheet.appendRow([xl.TextCellValue('Customer Repeat Rate (%)'), xl.DoubleCellValue((r['repeatRatePercentage'] as num?)?.toDouble() ?? 0.0)]);
    sheet.appendRow([xl.TextCellValue('Avg Debt Clearance Cycle (DSO)'), xl.TextCellValue('${r['avgDsoDays']} Days')]);
  }

  void _buildUdhaarSheet(xl.Excel excel, Map<String, dynamic> r) {
    final sheet = excel['High Due Watchlist'];
    sheet.appendRow([
      xl.TextCellValue('Customer Name'),
      xl.TextCellValue('Phone Number'),
      xl.TextCellValue('Location / Address'),
      xl.TextCellValue('Balance Due (Rs.)'),
      xl.TextCellValue('Credit Limit (Rs.)'),
      xl.TextCellValue('Days Overdue'),
      xl.TextCellValue('Over Limit?'),
    ]);

    final dues = (r['highestDueCustomers'] as List?) ?? [];
    for (final item in dues) {
      final name = item['customer_name'] as String? ?? '';
      final phone = item['customer_phone'] as String? ?? '';
      final loc = item['customer_location'] as String? ?? '';
      final due = (item['balance_due'] as num?)?.toDouble() ?? 0.0;
      final limit = (item['credit_limit'] as num?)?.toDouble() ?? 0.0;
      final days = (item['days_overdue'] as num?)?.toInt() ?? 0;
      final isOver = item['is_over_limit'] == true ? 'YES' : 'NO';

      sheet.appendRow([
        xl.TextCellValue(name),
        xl.TextCellValue(phone),
        xl.TextCellValue(loc),
        xl.DoubleCellValue(due),
        xl.DoubleCellValue(limit),
        xl.IntCellValue(days),
        xl.TextCellValue(isOver),
      ]);
    }
  }

  void _buildCustomersSheet(xl.Excel excel, Map<String, dynamic> r) {
    final sheet = excel['Top Buyers & Payers'];
    sheet.appendRow([xl.TextCellValue('TOP HIGH-VALUE BUYERS (BY SALES VOLUME)')]);
    sheet.appendRow([
      xl.TextCellValue('#'),
      xl.TextCellValue('Customer Name'),
      xl.TextCellValue('Phone Number'),
      xl.TextCellValue('Location'),
      xl.TextCellValue('Total Billed (Rs.)'),
      xl.TextCellValue('Orders Count'),
    ]);

    final buyers = (r['topBuyers'] as List?) ?? [];
    for (int i = 0; i < buyers.length; i++) {
      final b = buyers[i];
      sheet.appendRow([
        xl.IntCellValue(i + 1),
        xl.TextCellValue(b['name'] as String? ?? b['customer_name'] as String? ?? ''),
        xl.TextCellValue(b['phone'] as String? ?? b['customer_phone'] as String? ?? ''),
        xl.TextCellValue(b['location'] as String? ?? b['customer_location'] as String? ?? ''),
        xl.DoubleCellValue((b['total_bought'] as num?)?.toDouble() ?? 0.0),
        xl.IntCellValue((b['order_count'] as num?)?.toInt() ?? 0),
      ]);
    }

    sheet.appendRow([xl.TextCellValue('')]);
    sheet.appendRow([xl.TextCellValue('TOP PAYERS (MOST CASH & UPI RECOVERED)')]);
    sheet.appendRow([
      xl.TextCellValue('#'),
      xl.TextCellValue('Customer Name'),
      xl.TextCellValue('Phone Number'),
      xl.TextCellValue('Location'),
      xl.TextCellValue('Total Paid (Rs.)'),
      xl.TextCellValue('Payments Count'),
    ]);

    final payers = (r['topPayers'] as List?) ?? [];
    for (int i = 0; i < payers.length; i++) {
      final p = payers[i];
      sheet.appendRow([
        xl.IntCellValue(i + 1),
        xl.TextCellValue(p['name'] as String? ?? p['customer_name'] as String? ?? ''),
        xl.TextCellValue(p['phone'] as String? ?? p['customer_phone'] as String? ?? ''),
        xl.TextCellValue(p['location'] as String? ?? p['customer_location'] as String? ?? ''),
        xl.DoubleCellValue((p['total_paid'] as num?)?.toDouble() ?? 0.0),
        xl.IntCellValue((p['payment_count'] as num?)?.toInt() ?? 0),
      ]);
    }
  }

  void _buildDormantSheet(xl.Excel excel, Map<String, dynamic> r) {
    final sheet = excel['Dormant Customers'];
    sheet.appendRow([xl.TextCellValue('DORMANT / INACTIVE CUSTOMERS (NO PURCHASE IN 30+ DAYS)')]);
    sheet.appendRow([
      xl.TextCellValue('Customer Name'),
      xl.TextCellValue('Phone Number'),
      xl.TextCellValue('Location'),
      xl.TextCellValue('Days Inactive'),
      xl.TextCellValue('Last Order Date'),
      xl.TextCellValue('Past Total Bought (Rs.)'),
      xl.TextCellValue('Past Orders Count'),
    ]);

    final dormant = (r['dormantCustomers'] as List?) ?? [];
    for (final d in dormant) {
      sheet.appendRow([
        xl.TextCellValue(d['customer_name'] as String? ?? ''),
        xl.TextCellValue(d['customer_phone'] as String? ?? ''),
        xl.TextCellValue(d['customer_location'] as String? ?? ''),
        xl.IntCellValue((d['days_since_last_order'] as num?)?.toInt() ?? 0),
        xl.TextCellValue(d['last_order_date'] as String? ?? ''),
        xl.DoubleCellValue((d['past_total_bought'] as num?)?.toDouble() ?? 0.0),
        xl.IntCellValue((d['past_order_count'] as num?)?.toInt() ?? 0),
      ]);
    }
  }

  void _buildProductsSheet(xl.Excel excel, Map<String, dynamic> r) {
    final sheet = excel['Products & Inventory'];

    // Top Selling Products
    sheet.appendRow([xl.TextCellValue('TOP 10 BEST-SELLING PRODUCTS')]);
    sheet.appendRow([
      xl.TextCellValue('#'),
      xl.TextCellValue('Product Name'),
      xl.TextCellValue('Unit'),
      xl.TextCellValue('Quantity Sold'),
      xl.TextCellValue('Total Revenue (Rs.)'),
    ]);
    final topProds = (r['topProducts'] as List?) ?? [];
    for (int i = 0; i < topProds.length; i++) {
      final p = topProds[i];
      sheet.appendRow([
        xl.IntCellValue(i + 1),
        xl.TextCellValue(p['item_name'] as String? ?? ''),
        xl.TextCellValue(p['unit'] as String? ?? ''),
        xl.DoubleCellValue((p['total_qty'] as num?)?.toDouble() ?? 0.0),
        xl.DoubleCellValue((p['total_rev'] as num?)?.toDouble() ?? 0.0),
      ]);
    }

    sheet.appendRow([xl.TextCellValue('')]);

    // Category Sales Breakdown
    sheet.appendRow([xl.TextCellValue('SALES BY CATEGORY / DEPARTMENT')]);
    sheet.appendRow([
      xl.TextCellValue('Category Name'),
      xl.TextCellValue('Total Sales (Rs.)'),
      xl.TextCellValue('Lines Sold Count'),
    ]);
    final catSales = (r['categorySales'] as List?) ?? [];
    for (final c in catSales) {
      sheet.appendRow([
        xl.TextCellValue(c['category'] as String? ?? 'General'),
        xl.DoubleCellValue((c['category_sales'] as num?)?.toDouble() ?? 0.0),
        xl.IntCellValue((c['item_count'] as num?)?.toInt() ?? 0),
      ]);
    }

    sheet.appendRow([xl.TextCellValue('')]);

    // Frequent Shortages
    sheet.appendRow([xl.TextCellValue('FREQUENT SHORTAGES / STOCKOUTS (GOODS NOT GIVEN)')]);
    sheet.appendRow([
      xl.TextCellValue('Product Name'),
      xl.TextCellValue('Unit'),
      xl.TextCellValue('Shortage Incidents'),
      xl.TextCellValue('Total Quantity Short'),
    ]);
    final stockouts = (r['topStockouts'] as List?) ?? [];
    for (final s in stockouts) {
      sheet.appendRow([
        xl.TextCellValue(s['item_name'] as String? ?? ''),
        xl.TextCellValue(s['unit'] as String? ?? ''),
        xl.IntCellValue((s['shortage_events'] as num?)?.toInt() ?? 0),
        xl.DoubleCellValue((s['total_short_qty'] as num?)?.toDouble() ?? 0.0),
      ]);
    }

    sheet.appendRow([xl.TextCellValue('')]);

    // Dead Stock
    sheet.appendRow([xl.TextCellValue('DEAD STOCK (ACTIVE PRODUCTS WITH 0 SALES)')]);
    sheet.appendRow([
      xl.TextCellValue('Product Name'),
      xl.TextCellValue('Category'),
      xl.TextCellValue('Catalog Added Date'),
    ]);
    final dead = (r['deadStockProducts'] as List?) ?? [];
    for (final d in dead) {
      sheet.appendRow([
        xl.TextCellValue(d['item_name'] as String? ?? ''),
        xl.TextCellValue(d['category'] as String? ?? ''),
        xl.TextCellValue(d['created_at'] as String? ?? ''),
      ]);
    }
  }

  void _buildCollectionsSheet(xl.Excel excel, Map<String, dynamic> r) {
    final sheet = excel['Collections Ledger'];
    sheet.appendRow([
      xl.TextCellValue('Date & Time'),
      xl.TextCellValue('Customer Name'),
      xl.TextCellValue('Phone Number'),
      xl.TextCellValue('Location'),
      xl.TextCellValue('Amount Collected (Rs.)'),
      xl.TextCellValue('Payment Mode'),
      xl.TextCellValue('Notes'),
      xl.TextCellValue('Remaining Udhaar Due (Rs.)'),
    ]);

    final cols = (r['collections'] as List?) ?? [];
    for (final c in cols) {
      sheet.appendRow([
        xl.TextCellValue(c['created_at'] as String? ?? ''),
        xl.TextCellValue(c['customer_name'] as String? ?? ''),
        xl.TextCellValue(c['customer_phone'] as String? ?? ''),
        xl.TextCellValue(c['customer_location'] as String? ?? ''),
        xl.DoubleCellValue((c['amount'] as num?)?.toDouble() ?? 0.0),
        xl.TextCellValue((c['payment_mode'] as String? ?? '').toUpperCase()),
        xl.TextCellValue(c['notes'] as String? ?? ''),
        xl.DoubleCellValue((c['remaining_due'] as num?)?.toDouble() ?? 0.0),
      ]);
    }
  }

  void _buildStaffSheet(xl.Excel excel, Map<String, dynamic> r) {
    final sheet = excel['Staff Performance'];
    sheet.appendRow([
      xl.TextCellValue('Staff / Counter / Device'),
      xl.TextCellValue('Orders Taken'),
      xl.TextCellValue('Total Sales Billed (Rs.)'),
      xl.TextCellValue('Direct Payments Collected (Rs.)'),
    ]);

    final staffList = (r['staffLeaderboard'] as List?) ?? [];
    for (final s in staffList) {
      sheet.appendRow([
        xl.TextCellValue(s['staff_name'] as String? ?? ''),
        xl.IntCellValue((s['orders_taken'] as num?)?.toInt() ?? 0),
        xl.DoubleCellValue((s['total_sales'] as num?)?.toDouble() ?? 0.0),
        xl.DoubleCellValue((s['direct_collected'] as num?)?.toDouble() ?? 0.0),
      ]);
    }
  }
}
