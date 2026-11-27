import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:shop/database/database_helper.dart';
import 'package:shop/l10n/app_localizations.dart';
import 'package:shop/models/customer.dart';
import 'package:shop/repositories/delivery_repository.dart';
import 'package:shop/services/excel_report_service.dart';
import 'package:shop/services/invoice_pdf_service.dart';
import 'package:shop/services/shop_customization_service.dart';

enum DateRangeFilter { lifetime, today, thisWeek, thisMonth, custom }

class LifetimeReportScreen extends StatefulWidget {
  const LifetimeReportScreen({super.key});

  @override
  State<LifetimeReportScreen> createState() => _LifetimeReportScreenState();
}

class _LifetimeReportScreenState extends State<LifetimeReportScreen>
    with SingleTickerProviderStateMixin {
  DateRangeFilter _rangeFilter = DateRangeFilter.lifetime;
  DateTimeRange? _customDateRange;
  String? _selectedLocation;
  String? _selectedTakenBy;

  Map<String, dynamic>? _reportData;
  Map<String, dynamic> _deliverySummary = const {};
  bool _loading = true;
  bool _isSharingPdf = false;
  bool _isExportingExcel = false;
  late TabController _tabController;

  final TextEditingController _collectionSearchCtrl = TextEditingController();
  String _collectionQuery = '';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 5, vsync: this);
    _loadReport();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _collectionSearchCtrl.dispose();
    super.dispose();
  }

  DateTime? get _effectiveStartDate {
    final now = DateTime.now();
    switch (_rangeFilter) {
      case DateRangeFilter.lifetime:
        return null;
      case DateRangeFilter.today:
        return DateTime(now.year, now.month, now.day);
      case DateRangeFilter.thisWeek:
        return DateTime(now.year, now.month, now.day)
            .subtract(Duration(days: now.weekday - 1));
      case DateRangeFilter.thisMonth:
        return DateTime(now.year, now.month, 1);
      case DateRangeFilter.custom:
        return _customDateRange?.start;
    }
  }

  DateTime? get _effectiveEndDate {
    final now = DateTime.now();
    switch (_rangeFilter) {
      case DateRangeFilter.lifetime:
        return null;
      case DateRangeFilter.today:
        return DateTime(now.year, now.month, now.day, 23, 59, 59, 999);
      case DateRangeFilter.thisWeek:
        return DateTime(now.year, now.month, now.day, 23, 59, 59, 999);
      case DateRangeFilter.thisMonth:
        return DateTime(now.year, now.month, now.day, 23, 59, 59, 999);
      case DateRangeFilter.custom:
        if (_customDateRange == null) return null;
        return DateTime(_customDateRange!.end.year, _customDateRange!.end.month,
            _customDateRange!.end.day, 23, 59, 59, 999);
    }
  }

  String get _dateRangeLabel {
    switch (_rangeFilter) {
      case DateRangeFilter.lifetime:
        return 'Lifetime (All Time)';
      case DateRangeFilter.today:
        return 'Today (${DateFormat('dd MMM yyyy').format(DateTime.now())})';
      case DateRangeFilter.thisWeek:
        return 'This Week';
      case DateRangeFilter.thisMonth:
        return DateFormat('MMMM yyyy').format(DateTime.now());
      case DateRangeFilter.custom:
        if (_customDateRange != null) {
          final s = DateFormat('dd MMM yy').format(_customDateRange!.start);
          final e = DateFormat('dd MMM yy').format(_customDateRange!.end);
          return '$s - $e';
        }
        return 'Custom Range';
    }
  }

  Future<void> _loadReport() async {
    setState(() => _loading = true);
    try {
      final results = await Future.wait([
        DatabaseHelper.instance.getLifetimeBusinessReport(
          startDate: _effectiveStartDate,
          endDate: _effectiveEndDate,
          locationFilter: _selectedLocation,
          staffFilter: _selectedTakenBy,
        ),
        DeliveryRepository().getDeliverySummary(
          start: _effectiveStartDate,
          end: _effectiveEndDate,
          locationFilter: _selectedLocation,
        ),
      ]);
      if (!mounted) return;
      setState(() {
        _reportData = results[0];
        _deliverySummary = results[1];
        _loading = false;
      });
    } catch (e, stack) {
      debugPrint('Error loading lifetime business report: $e\n$stack');
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to load report: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _pickCustomDateRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      initialDateRange: _customDateRange ??
          DateTimeRange(
            start: DateTime.now().subtract(const Duration(days: 30)),
            end: DateTime.now(),
          ),
    );
    if (picked != null) {
      setState(() {
        _rangeFilter = DateRangeFilter.custom;
        _customDateRange = picked;
      });
      _loadReport();
    }
  }

  Future<void> _shareReportPdf() async {
    if (_reportData == null || _isSharingPdf) return;
    setState(() => _isSharingPdf = true);
    try {
      await InvoicePdfService.instance.shareLifetimeReportPdf(
        _reportData!,
        dateRangeLabel: _dateRangeLabel,
        locationFilter: _selectedLocation,
        staffFilter: _selectedTakenBy,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to share PDF: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSharingPdf = false);
    }
  }

  Future<void> _exportExcel() async {
    if (_reportData == null || _isExportingExcel) return;
    setState(() => _isExportingExcel = true);
    try {
      await ExcelReportService.instance.exportAndShareLifetimeReport(
        _reportData!,
        dateRangeLabel: _dateRangeLabel,
        locationFilter: _selectedLocation,
        staffFilter: _selectedTakenBy,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to export Excel: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isExportingExcel = false);
    }
  }

  String? _firstCleanPhone(String rawPhone) {
    final numbers = Customer.extractNumbers(rawPhone);
    final candidate = numbers.isNotEmpty ? numbers.first : rawPhone;
    final clean = candidate.replaceAll(RegExp(r'[^0-9]'), '');
    if (clean.length < 6) return null;
    return clean;
  }

  Future<void> _launchWhatsAppMessage(String rawPhone, String text) async {
    final clean = _firstCleanPhone(rawPhone);
    if (clean == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Invalid phone number for WhatsApp.')),
        );
      }
      return;
    }
    final target = clean.length == 10 ? '91$clean' : clean;
    final encoded = Uri.encodeComponent(text);
    final url = Uri.parse('whatsapp://send?phone=$target&text=$encoded');
    final webUrl =
        Uri.parse('https://api.whatsapp.com/send?phone=$target&text=$encoded');
    try {
      if (await canLaunchUrl(url)) {
        await launchUrl(url);
      } else {
        await launchUrl(webUrl, mode: LaunchMode.externalApplication);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not open WhatsApp: $e')),
        );
      }
    }
  }

  Future<void> _sendPaymentReminderWhatsApp({
    required String customerName,
    required String phone,
    required double dueAmount,
  }) async {
    final shopName = ShopCustomizationService.instance.currentShopName;
    final upiId = ShopCustomizationService.instance.upiId;
    final upiLine = upiId.isNotEmpty ? '\nUPI ID: $upiId' : '';
    final text =
        'Dear $customerName,\n\nGreetings from $shopName! 🙏\nYour current outstanding balance is ₹ ${dueAmount.toStringAsFixed(2)}.$upiLine\n\nPlease settle at your earliest convenience. Thank you!';
    await _launchWhatsAppMessage(phone, text);
  }

  Future<void> _sendWinBackWhatsApp({
    required String customerName,
    required String phone,
    required int daysInactive,
  }) async {
    final shopName = ShopCustomizationService.instance.currentShopName;
    final text =
        'Hello $customerName,\n\nWe missed seeing you at $shopName over the past few weeks! 😊\nWe have new stock and best wholesale prices available. Please let us know if you need any goods today.\n\nThank you!';
    await _launchWhatsAppMessage(phone, text);
  }

  Future<void> _callPhone(String phone) async {
    final clean = _firstCleanPhone(phone);
    if (clean == null) return;
    try {
      final url = Uri.parse('tel:$clean');
      if (await canLaunchUrl(url)) {
        await launchUrl(url);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not initiate call: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final currency = NumberFormat.currency(locale: 'en_IN', symbol: '₹ ');

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Lifetime Business Analytics',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            Text(
              'Full Audit, Intelligence & Growth',
              style: TextStyle(fontSize: 11, color: Colors.white70),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Export Excel (.xlsx) for CA / Tally',
            icon: _isExportingExcel
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 2,
                    ),
                  )
                : const Icon(Icons.table_view_outlined),
            onPressed: _exportExcel,
          ),
          IconButton(
            tooltip: 'Share PDF via WhatsApp',
            icon: _isSharingPdf
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 2,
                    ),
                  )
                : const Icon(Icons.picture_as_pdf_outlined),
            onPressed: _shareReportPdf,
          ),
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh),
            onPressed: _loadReport,
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: Container(
            color: Colors.white,
            child: TabBar(
              controller: _tabController,
              isScrollable: true,
              labelColor: const Color(0xFF0F766E),
              unselectedLabelColor: Colors.grey.shade600,
              indicatorColor: const Color(0xFF0F766E),
              indicatorWeight: 3,
              labelStyle:
                  const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
              tabs: const [
                Tab(text: 'Financial Health & KPIs'),
                Tab(text: 'Customer Loyalty & Risk'),
                Tab(text: 'Products & Inventory'),
                Tab(text: 'Partner Leaderboard'),
                Tab(text: 'Collections Ledger'),
              ],
            ),
          ),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _reportData == null
              ? const Center(child: Text('Failed to load analytics.'))
              : Column(
                  children: [
                    // Filter Bar: Date Range + Location + Staff
                    _buildFilterControls(),

                    if (((_deliverySummary['totalEarned'] as num?) ?? 0) > 0 ||
                        ((_deliverySummary['totalPaid'] as num?) ?? 0) > 0)
                      Container(
                        margin: const EdgeInsets.fromLTRB(16, 6, 16, 4),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.indigo.shade50,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Colors.indigo.shade100),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              children: [
                                Icon(Icons.local_shipping_outlined,
                                    size: 16, color: Colors.indigo.shade700),
                                const SizedBox(width: 6),
                                Text(
                                  AppLocalizations.of(context)
                                      .t('deliveryExpense'),
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.indigo.shade900,
                                  ),
                                ),
                              ],
                            ),
                            Text(
                              '₹${((_deliverySummary['totalEarned'] as num?) ?? 0).toStringAsFixed(0)} • Paid: ₹${((_deliverySummary['totalPaid'] as num?) ?? 0).toStringAsFixed(0)}',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                                color: Colors.indigo.shade800,
                              ),
                            ),
                          ],
                        ),
                      ),

                    // Tab View Body
                    Expanded(
                      child: TabBarView(
                        controller: _tabController,
                        children: [
                          _buildFinancialHealthTab(currency),
                          _buildCustomerLoyaltyTab(currency),
                          _buildProductsInventoryTab(currency),
                          _buildStaffLeaderboardTab(currency),
                          _buildCollectionsLedgerTab(currency),
                        ],
                      ),
                    ),
                  ],
                ),
    );
  }

  Widget _buildFilterControls() {
    final allLocations =
        (_reportData?['allLocations'] as List<dynamic>?)?.cast<String>() ?? [];
    final allStaff =
        (_reportData?['allStaff'] as List<dynamic>?)?.cast<String>() ?? [];

    final locationItems = <String>[...allLocations];
    if (_selectedLocation != null && !locationItems.contains(_selectedLocation)) {
      locationItems.insert(0, _selectedLocation!);
    }

    final staffItems = <String>[...allStaff];
    if (_selectedTakenBy != null && !staffItems.contains(_selectedTakenBy)) {
      staffItems.insert(0, _selectedTakenBy!);
    }

    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Range Filter Chips
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _buildFilterChip('Lifetime', DateRangeFilter.lifetime),
                const SizedBox(width: 6),
                _buildFilterChip('Today', DateRangeFilter.today),
                const SizedBox(width: 6),
                _buildFilterChip('This Week', DateRangeFilter.thisWeek),
                const SizedBox(width: 6),
                _buildFilterChip('This Month', DateRangeFilter.thisMonth),
                const SizedBox(width: 6),
                ActionChip(
                  avatar: const Icon(Icons.date_range, size: 16),
                  label: Text(_rangeFilter == DateRangeFilter.custom
                      ? _dateRangeLabel
                      : 'Custom Range'),
                  backgroundColor: _rangeFilter == DateRangeFilter.custom
                      ? const Color(0xFFCCFBF1)
                      : Colors.grey.shade100,
                  onPressed: _pickCustomDateRange,
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),

          // Location and Staff Dropdown Filters
          Row(
            children: [
              // Location Dropdown
              Expanded(
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                  decoration: BoxDecoration(
                    color: _selectedLocation != null
                        ? const Color(0xFFF0FDFA)
                        : Colors.grey.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: _selectedLocation != null
                          ? const Color(0xFF0F766E)
                          : Colors.grey.shade300,
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.location_on,
                          size: 14, color: Color(0xFF0F766E)),
                      const SizedBox(width: 4),
                      Expanded(
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String?>(
                            value: _selectedLocation,
                            isDense: true,
                            hint: const Text('All Locations',
                                style: TextStyle(fontSize: 11)),
                            style: const TextStyle(
                                fontSize: 11, color: Colors.black87),
                            items: [
                              const DropdownMenuItem<String?>(
                                value: null,
                                child: Text('All Locations (Market)',
                                    style: TextStyle(fontSize: 11)),
                              ),
                              ...locationItems.map(
                                (loc) => DropdownMenuItem<String?>(
                                  value: loc,
                                  child: Text(loc,
                                      style: const TextStyle(fontSize: 11),
                                      overflow: TextOverflow.ellipsis),
                                ),
                              ),
                            ],
                            onChanged: (val) {
                              setState(() => _selectedLocation = val);
                              _loadReport();
                            },
                          ),
                        ),
                      ),
                      if (_selectedLocation != null)
                        GestureDetector(
                          onTap: () {
                            setState(() => _selectedLocation = null);
                            _loadReport();
                          },
                          child: const Icon(Icons.close,
                              size: 14, color: Colors.grey),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),

              // Staff Dropdown
              Expanded(
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                  decoration: BoxDecoration(
                    color: _selectedTakenBy != null
                        ? const Color(0xFFF0FDFA)
                        : Colors.grey.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: _selectedTakenBy != null
                          ? const Color(0xFF0F766E)
                          : Colors.grey.shade300,
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.person_outline,
                          size: 14, color: Color(0xFF0F766E)),
                      const SizedBox(width: 4),
                      Expanded(
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String?>(
                            value: _selectedTakenBy,
                            isDense: true,
                            hint: const Text('All Partners',
                                style: TextStyle(fontSize: 11)),
                            style: const TextStyle(
                                fontSize: 11, color: Colors.black87),
                            items: [
                              const DropdownMenuItem<String?>(
                                value: null,
                                child: Text('All Partner Devices / Counters',
                                    style: TextStyle(fontSize: 11)),
                              ),
                              ...staffItems.map(
                                (st) => DropdownMenuItem<String?>(
                                  value: st,
                                  child: Text(st,
                                      style: const TextStyle(fontSize: 11),
                                      overflow: TextOverflow.ellipsis),
                                ),
                              ),
                            ],
                            onChanged: (val) {
                              setState(() => _selectedTakenBy = val);
                              _loadReport();
                            },
                          ),
                        ),
                      ),
                      if (_selectedTakenBy != null)
                        GestureDetector(
                          onTap: () {
                            setState(() => _selectedTakenBy = null);
                            _loadReport();
                          },
                          child: const Icon(Icons.close,
                              size: 14, color: Colors.grey),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String label, DateRangeFilter filter) {
    final selected = _rangeFilter == filter;
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      selectedColor: const Color(0xFFCCFBF1),
      labelStyle: TextStyle(
        fontSize: 12,
        fontWeight: selected ? FontWeight.bold : FontWeight.normal,
        color: selected ? const Color(0xFF0F766E) : Colors.black87,
      ),
      onSelected: (val) {
        if (val) {
          setState(() {
            _rangeFilter = filter;
            _customDateRange = null;
          });
          _loadReport();
        }
      },
      visualDensity: VisualDensity.compact,
    );
  }

  // -------------------------------------------------------------
  // TAB 1: FINANCIAL HEALTH, KPIS & TIME TRENDS
  // -------------------------------------------------------------
  Widget _buildFinancialHealthTab(NumberFormat currency) {
    final r = _reportData!;
    final totalSales = (r['totalSales'] as num).toDouble();
    final totalCollections = (r['totalCollected'] as num).toDouble();
    final totalMarketDue = (r['totalMarketDue'] as num).toDouble();
    final advancePool = (r['advancePoolTotal'] as num?)?.toDouble() ?? 0.0;
    final advanceCount = (r['advanceAccountsCount'] as num?)?.toInt() ?? 0;

    final totalOrders = (r['totalOrders'] as num).toInt();
    final aov = (r['averageOrderValue'] as num?)?.toDouble() ?? 0.0;
    final basketSize = (r['avgBasketSize'] as num?)?.toDouble() ?? 0.0;
    final totalItems = (r['totalItemsSold'] as num?)?.toDouble() ?? 0.0;

    final discounts = (r['totalDiscountsGiven'] as num?)?.toDouble() ?? 0.0;
    final gst = (r['totalGstBilled'] as num?)?.toDouble() ?? 0.0;

    final cash = (r['cashCollected'] as num?)?.toDouble() ?? 0.0;
    final upi = (r['upiCollected'] as num?)?.toDouble() ?? 0.0;
    final cashPct = (r['cashPercentage'] as num?)?.toDouble() ?? 0.0;
    final upiPct = (r['upiPercentage'] as num?)?.toDouble() ?? 0.0;

    final healthGrade = r['healthGrade'] as String? ?? 'Grade A';
    final healthScore = (r['healthScore'] as num?)?.toInt() ?? 80;
    final healthSummary = r['healthSummary'] as String? ?? '';

    final monthlyTrend = (r['monthlyTrend'] as List<dynamic>?)?.cast<Map<String, dynamic>>() ?? [];
    final hourlyStats = (r['hourlyStats'] as List<dynamic>?)?.cast<Map<String, dynamic>>() ?? [];
    final dayOfWeekStats = r['dayOfWeekStats'] as Map<int, Map<String, dynamic>>? ?? {};

    return ListView(
      padding: const EdgeInsets.all(14),
      children: [
        // 1. Store Financial Health Card
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: healthScore >= 75
                  ? [const Color(0xFF0F766E), const Color(0xFF14B8A6)]
                  : (healthScore >= 50
                      ? [const Color(0xFFD97706), const Color(0xFFF59E0B)]
                      : [const Color(0xFFBE123C), const Color(0xFFE11D48)]),
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.1),
                blurRadius: 8,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 58,
                height: 58,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: Text(
                  '$healthScore',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.verified_user_rounded, color: Colors.white, size: 16),
                        const SizedBox(width: 6),
                        Text(
                          healthGrade,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      healthSummary,
                      style: const TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.w500),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),

        // 2. Core KPI Cards (Sales, Collections, Udhaar, Advance Pool)
        Row(
          children: [
            Expanded(
              child: _buildGradientKpiCard(
                title: 'TOTAL SALES BILLED',
                subtitle: '$totalOrders Orders Created',
                amount: currency.format(totalSales),
                gradient: const LinearGradient(
                  colors: [Color(0xFF0F766E), Color(0xFF0D9488)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                icon: Icons.storefront_outlined,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _buildGradientKpiCard(
                title: 'TOTAL COLLECTED',
                subtitle: 'Cash + UPI Received',
                amount: currency.format(totalCollections),
                gradient: const LinearGradient(
                  colors: [Color(0xFF0369A1), Color(0xFF0284C7)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                icon: Icons.payments_outlined,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),

        Row(
          children: [
            Expanded(
              child: _buildGradientKpiCard(
                title: 'TOTAL MARKET DUE',
                subtitle: 'Active Unpaid Udhaar',
                amount: currency.format(totalMarketDue),
                gradient: const LinearGradient(
                  colors: [Color(0xFFBE123C), Color(0xFFE11D48)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                icon: Icons.account_balance_wallet_outlined,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _buildGradientKpiCard(
                title: 'ADVANCE DEPOSIT POOL',
                subtitle: '$advanceCount Advance Accounts',
                amount: currency.format(advancePool),
                gradient: const LinearGradient(
                  colors: [Color(0xFF475569), Color(0xFF64748B)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                icon: Icons.savings_outlined,
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),

        // 3. Average Order Value (AOV) & Basket Size
        _buildSectionHeader('Average Order Value & Basket Size', Icons.shopping_basket_outlined),
        const SizedBox(height: 8),
        Card(
          elevation: 0,
          color: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: Colors.grey.shade200),
          ),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                Column(
                  children: [
                    const Text('AVG BILL VALUE (AOV)', style: TextStyle(fontSize: 10, color: Colors.grey, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    Text(
                      currency.format(aov),
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: Color(0xFF0F766E)),
                    ),
                    const SizedBox(height: 2),
                    const Text('per order', style: TextStyle(fontSize: 9.5, color: Colors.grey)),
                  ],
                ),
                Container(height: 36, width: 1, color: Colors.grey.shade200),
                Column(
                  children: [
                    const Text('BASKET SIZE', style: TextStyle(fontSize: 10, color: Colors.grey, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    Text(
                      '${basketSize.toStringAsFixed(1)} items',
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: Color(0xFF0369A1)),
                    ),
                    const SizedBox(height: 2),
                    Text('Total: ${totalItems.toStringAsFixed(0)} units', style: const TextStyle(fontSize: 9.5, color: Colors.grey)),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 18),

        // 4. Cash vs. UPI Collection Ratio
        _buildSectionHeader('Cash vs. UPI Collection Breakdown', Icons.pie_chart_outline),
        const SizedBox(height: 8),
        Card(
          elevation: 0,
          color: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: Colors.grey.shade200),
          ),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Container(width: 10, height: 10, decoration: BoxDecoration(color: const Color(0xFF0F766E), borderRadius: BorderRadius.circular(2))),
                        const SizedBox(width: 6),
                        Text('Cash: ${currency.format(cash)} (${cashPct.toStringAsFixed(1)}%)', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                      ],
                    ),
                    Row(
                      children: [
                        Container(width: 10, height: 10, decoration: BoxDecoration(color: const Color(0xFF0284C7), borderRadius: BorderRadius.circular(2))),
                        const SizedBox(width: 6),
                        Text('UPI: ${currency.format(upi)} (${upiPct.toStringAsFixed(1)}%)', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: SizedBox(
                    height: 12,
                    child: Row(
                      children: [
                        if (cashPct > 0)
                          Expanded(
                            flex: (cashPct * 10).round().clamp(1, 1000),
                            child: Container(color: const Color(0xFF0F766E)),
                          ),
                        if (upiPct > 0)
                          Expanded(
                            flex: (upiPct * 10).round().clamp(1, 1000),
                            child: Container(color: const Color(0xFF0284C7)),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 18),

        // 5. Discounts & GST Tax Impact
        _buildSectionHeader('Discounts Given & GST Taxes Billed', Icons.discount_outlined),
        const SizedBox(height: 8),
        Card(
          elevation: 0,
          color: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: Colors.grey.shade200),
          ),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                Column(
                  children: [
                    const Text('DISCOUNTS GIVEN', style: TextStyle(fontSize: 10, color: Colors.grey, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    Text(
                      currency.format(discounts),
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: Colors.orange.shade800),
                    ),
                    const SizedBox(height: 2),
                    const Text('Flat & % margins deducted', style: TextStyle(fontSize: 9.5, color: Colors.grey)),
                  ],
                ),
                Container(height: 36, width: 1, color: Colors.grey.shade200),
                Column(
                  children: [
                    const Text('GST BILLED', style: TextStyle(fontSize: 10, color: Colors.grey, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    Text(
                      currency.format(gst),
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: Color(0xFF475569)),
                    ),
                    const SizedBox(height: 2),
                    const Text('Official tax collected', style: TextStyle(fontSize: 9.5, color: Colors.grey)),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 18),

        // 6. Month-on-Month Growth Trend
        if (monthlyTrend.isNotEmpty) ...[
          _buildSectionHeader('Month-on-Month Growth Trend', Icons.trending_up),
          const SizedBox(height: 8),
          Card(
            elevation: 0,
            color: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: Colors.grey.shade200),
            ),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                children: monthlyTrend.map((m) {
                  final s = (m['sales'] as num?)?.toDouble() ?? 0.0;
                  final c = (m['collections'] as num?)?.toDouble() ?? 0.0;
                  final count = (m['orders'] as num?)?.toInt() ?? 0;
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 70,
                          child: Text(
                            m['month_key'] as String? ?? '',
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                          ),
                        ),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text('Billed: ${currency.format(s)} ($count orders)', style: const TextStyle(fontSize: 10.5, color: Color(0xFF0F766E), fontWeight: FontWeight.w600)),
                                  Text('Collected: ${currency.format(c)}', style: const TextStyle(fontSize: 10.5, color: Color(0xFF0284C7), fontWeight: FontWeight.w600)),
                                ],
                              ),
                              const SizedBox(height: 4),
                              ClipRRect(
                                borderRadius: BorderRadius.circular(4),
                                child: SizedBox(
                                  height: 6,
                                  child: LinearProgressIndicator(
                                    value: totalSales > 0 ? (s / totalSales).clamp(0.05, 1.0) : 0.1,
                                    backgroundColor: Colors.grey.shade200,
                                    valueColor: const AlwaysStoppedAnimation(Color(0xFF0F766E)),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
          const SizedBox(height: 18),
        ],

        // 7. Busiest Hours of the Day Heatmap
        if (hourlyStats.isNotEmpty) ...[
          _buildSectionHeader('Busiest Hours of the Day (Rush Hour)', Icons.access_time),
          const SizedBox(height: 8),
          Card(
            elevation: 0,
            color: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: Colors.grey.shade200),
            ),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: hourlyStats.map((h) {
                    final hr = h['hour_of_day'] as String? ?? '';
                    final count = (h['order_count'] as num?)?.toInt() ?? 0;
                    return Container(
                      margin: const EdgeInsets.only(right: 8),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      decoration: BoxDecoration(
                        color: count >= 5 ? const Color(0xFFCCFBF1) : Colors.grey.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: count >= 5 ? const Color(0xFF0F766E) : Colors.grey.shade200),
                      ),
                      child: Column(
                        children: [
                          Text('$hr:00', style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold)),
                          const SizedBox(height: 4),
                          Text('$count orders', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: count >= 5 ? const Color(0xFF0F766E) : Colors.black87)),
                        ],
                      ),
                    );
                  }).toList(),
                ),
              ),
            ),
          ),
          const SizedBox(height: 18),
        ],

        // 8. Peak Busiest Days
        _buildSectionHeader('Peak Busiest Days of the Week', Icons.calendar_month),
        const SizedBox(height: 8),
        Card(
          elevation: 0,
          color: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: Colors.grey.shade200),
          ),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: _buildDayOfWeekBarChart(dayOfWeekStats, currency),
          ),
        ),
        const SizedBox(height: 30),
      ],
    );
  }

  // -------------------------------------------------------------
  // TAB 2: CUSTOMER LOYALTY, WIN-BACK & DEBT RISK
  // -------------------------------------------------------------
  Widget _buildCustomerLoyaltyTab(NumberFormat currency) {
    final r = _reportData!;
    final uniqueCount = (r['uniqueCustomerCount'] as num?)?.toInt() ?? 0;
    final repeatCount = (r['repeatCustomerCount'] as num?)?.toInt() ?? 0;
    final oneTimeCount = (r['oneTimeCustomerCount'] as num?)?.toInt() ?? 0;
    final repeatRate = (r['repeatRatePercentage'] as num?)?.toDouble() ?? 0.0;
    final dsoDays = (r['avgDsoDays'] as num?)?.toInt() ?? 14;

    final dormant = (r['dormantCustomers'] as List<dynamic>?)?.cast<Map<String, dynamic>>() ?? [];
    final highestDues = (r['highestDueCustomers'] as List<dynamic>?)?.cast<Map<String, dynamic>>() ?? [];
    final topBuyers = (r['topBuyers'] as List<dynamic>?)?.cast<Map<String, dynamic>>() ?? [];
    final topPayers = (r['topPayers'] as List<dynamic>?)?.cast<Map<String, dynamic>>() ?? [];

    return ListView(
      padding: const EdgeInsets.all(14),
      children: [
        // Loyalty & DSO Banner
        Card(
          elevation: 0,
          color: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: Colors.grey.shade200),
          ),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                Column(
                  children: [
                    const Text('CUSTOMER REPEAT RATE', style: TextStyle(fontSize: 10, color: Colors.grey, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    Text(
                      '${repeatRate.toStringAsFixed(1)}%',
                      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: Color(0xFF0F766E)),
                    ),
                    const SizedBox(height: 2),
                    Text('$repeatCount repeat • $oneTimeCount walk-in ($uniqueCount total)', style: const TextStyle(fontSize: 10, color: Colors.grey)),
                  ],
                ),
                Container(height: 36, width: 1, color: Colors.grey.shade200),
                Column(
                  children: [
                    const Text('AVG UDHAAR CLEARANCE', style: TextStyle(fontSize: 10, color: Colors.grey, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    Text(
                      '$dsoDays Days',
                      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: Color(0xFF0369A1)),
                    ),
                    const SizedBox(height: 2),
                    const Text('Average debt collection cycle', style: TextStyle(fontSize: 10, color: Colors.grey)),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 18),

        // Dormant Customers Win-Back Section
        _buildSectionHeader('Dormant Regulars (No order in 30+ days)', Icons.history_toggle_off),
        const SizedBox(height: 4),
        const Text(
          'Valuable customers who used to buy from your shop. Tap WhatsApp or Call to win them back!',
          style: TextStyle(fontSize: 11, color: Colors.grey),
        ),
        const SizedBox(height: 8),
        if (dormant.isEmpty)
          _buildEmptyCard('All regular customers are active! No dormant accounts.')
        else
          ...dormant.map((d) {
            final name = d['customer_name'] as String? ?? 'Customer';
            final phone = d['customer_phone'] as String? ?? '';
            final loc = d['customer_location'] as String? ?? '';
            final days = (d['days_since_last_order'] as num?)?.toInt() ?? 30;
            final pastBought = (d['past_total_bought'] as num?)?.toDouble() ?? 0.0;

            return Card(
              elevation: 0,
              margin: const EdgeInsets.only(bottom: 8),
              color: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
                side: BorderSide(color: Colors.grey.shade200),
              ),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5)),
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                                decoration: BoxDecoration(color: Colors.amber.shade50, borderRadius: BorderRadius.circular(4)),
                                child: Text('⏱️ $days d ago', style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.bold, color: Colors.amber.shade900)),
                              ),
                            ],
                          ),
                          const SizedBox(height: 2),
                          Text('$phone • $loc', style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                          const SizedBox(height: 2),
                          Text('Past purchases: ${currency.format(pastBought)}', style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: Color(0xFF0F766E))),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'WhatsApp Win-Back Message',
                      icon: const Icon(Icons.chat_bubble_outline, color: Colors.green, size: 20),
                      onPressed: () => _sendWinBackWhatsApp(customerName: name, phone: phone, daysInactive: days),
                    ),
                    IconButton(
                      tooltip: 'Call Customer',
                      icon: const Icon(Icons.phone_outlined, color: Color(0xFF0F766E), size: 20),
                      onPressed: () => _callPhone(phone),
                    ),
                  ],
                ),
              ),
            );
          }),
        const SizedBox(height: 18),

        // Highest Outstanding Dues Watchlist with 1-Tap WhatsApp Reminder
        _buildSectionHeader('Highest Outstanding Dues (Udhaar Watchlist)', Icons.warning_amber_rounded),
        const SizedBox(height: 4),
        const Text(
          'Top debt accounts. Tap the WhatsApp icon to send a polite payment reminder with your UPI QR code!',
          style: TextStyle(fontSize: 11, color: Colors.grey),
        ),
        const SizedBox(height: 8),
        if (highestDues.isEmpty)
          _buildEmptyCard('No pending dues! All customer Khata is settled.')
        else
          ...highestDues.map((item) {
            final name = item['customer_name'] as String? ?? 'Customer';
            final phone = item['customer_phone'] as String? ?? '';
            final loc = item['customer_location'] as String? ?? '';
            final due = (item['balance_due'] as num?)?.toDouble() ?? 0.0;
            final days = (item['days_overdue'] as num?)?.toInt() ?? 0;

            return Card(
              elevation: 0,
              margin: const EdgeInsets.only(bottom: 8),
              color: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
                side: BorderSide(color: Colors.red.shade100),
              ),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5)),
                              if (days > 0) ...[
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                  decoration: BoxDecoration(color: Colors.red.shade50, borderRadius: BorderRadius.circular(4)),
                                  child: Text('⚠️ $days d due', style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.bold, color: Colors.red.shade800)),
                                ),
                              ],
                            ],
                          ),
                          const SizedBox(height: 2),
                          Text('$phone • $loc', style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                          const SizedBox(height: 2),
                          Text('Due: ${currency.format(due)}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w900, color: Colors.red)),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'Send Payment Reminder via WhatsApp',
                      icon: const Icon(Icons.send_rounded, color: Colors.green, size: 20),
                      onPressed: () => _sendPaymentReminderWhatsApp(customerName: name, phone: phone, dueAmount: due),
                    ),
                    IconButton(
                      tooltip: 'Call Customer',
                      icon: const Icon(Icons.phone_outlined, color: Color(0xFF0F766E), size: 20),
                      onPressed: () => _callPhone(phone),
                    ),
                  ],
                ),
              ),
            );
          }),
        const SizedBox(height: 18),

        // Top Buyers
        _buildSectionHeader('Top Customers Who Buy Most', Icons.shopping_bag_outlined),
        const SizedBox(height: 8),
        ...topBuyers.asMap().entries.map((entry) {
          final idx = entry.key + 1;
          final c = entry.value;
          return _buildCustomerRankCard(
            rank: idx,
            name: c['customer_name'] as String? ?? 'Customer',
            phone: c['customer_phone'] as String?,
            location: c['customer_location'] as String?,
            statLabel: 'Total Purchased',
            statValue: currency.format((c['total_bought'] as num).toDouble()),
            statColor: const Color(0xFF0F766E),
            badgeColor: Colors.teal.shade50,
          );
        }),
        const SizedBox(height: 18),

        // Top Payers
        _buildSectionHeader('Top Payers (Most Cash & UPI Paid)', Icons.verified_outlined),
        const SizedBox(height: 8),
        ...topPayers.asMap().entries.map((entry) {
          final idx = entry.key + 1;
          final c = entry.value;
          return _buildCustomerRankCard(
            rank: idx,
            name: c['customer_name'] as String? ?? 'Customer',
            phone: c['customer_phone'] as String?,
            location: c['customer_location'] as String?,
            statLabel: 'Total Paid',
            statValue: currency.format((c['total_paid'] as num).toDouble()),
            statColor: const Color(0xFF0284C7),
            badgeColor: Colors.lightBlue.shade50,
          );
        }),
        const SizedBox(height: 30),
      ],
    );
  }

  // -------------------------------------------------------------
  // TAB 3: PRODUCTS, CATEGORIES & INVENTORY MOVEMENT
  // -------------------------------------------------------------
  Widget _buildProductsInventoryTab(NumberFormat currency) {
    final r = _reportData!;
    final topProducts = (r['topProducts'] as List<dynamic>?)?.cast<Map<String, dynamic>>() ?? [];
    final leastProducts = (r['leastProducts'] as List<dynamic>?)?.cast<Map<String, dynamic>>() ?? [];
    final categorySales = (r['categorySales'] as List<dynamic>?)?.cast<Map<String, dynamic>>() ?? [];
    final topStockouts = (r['topStockouts'] as List<dynamic>?)?.cast<Map<String, dynamic>>() ?? [];
    final deadStock = (r['deadStockProducts'] as List<dynamic>?)?.cast<Map<String, dynamic>>() ?? [];

    return ListView(
      padding: const EdgeInsets.all(14),
      children: [
        // Category Sales Breakdown
        _buildSectionHeader('Category & Department Sales Breakdown', Icons.category_outlined),
        const SizedBox(height: 8),
        if (categorySales.isEmpty)
          _buildEmptyCard('No category sales recorded yet.')
        else
          Card(
            elevation: 0,
            color: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: Colors.grey.shade200),
            ),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                children: categorySales.map((cat) {
                  final name = cat['category'] as String? ?? 'General';
                  final s = (cat['category_sales'] as num?)?.toDouble() ?? 0.0;
                  final count = (cat['item_count'] as num?)?.toInt() ?? 0;
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('$name ($count items)', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                        Text(currency.format(s), style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13, color: Color(0xFF0F766E))),
                      ],
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
        const SizedBox(height: 18),

        // Most Frequent Shortage Items (Stockout Frequency)
        _buildSectionHeader('Frequent Shortages during Packing (Stockouts)', Icons.production_quantity_limits),
        const SizedBox(height: 4),
        const Text('Items most frequently marked Short or Not Given. Consider increasing stock for these!', style: TextStyle(fontSize: 11, color: Colors.grey)),
        const SizedBox(height: 8),
        if (topStockouts.isEmpty)
          _buildEmptyCard('All orders fulfilled without shortages!')
        else
          ...topStockouts.map((s) {
            final name = s['item_name'] as String? ?? 'Product';
            final unit = s['unit'] as String? ?? '';
            final events = (s['shortage_events'] as num?)?.toInt() ?? 0;
            final qty = (s['total_short_qty'] as num?)?.toDouble() ?? 0.0;
            return Card(
              elevation: 0,
              margin: const EdgeInsets.only(bottom: 8),
              color: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
                side: BorderSide(color: Colors.orange.shade200),
              ),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                          const SizedBox(height: 2),
                          Text('$events times short during packing', style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                        ],
                      ),
                    ),
                    Text(
                      '-${qty.toStringAsFixed(1)} $unit short',
                      style: TextStyle(fontWeight: FontWeight.w900, fontSize: 12.5, color: Colors.orange.shade900),
                    ),
                  ],
                ),
              ),
            );
          }),
        const SizedBox(height: 18),

        // Dead Stock Alert (0 sales)
        _buildSectionHeader('Dead Stock Alert (Active Catalog with 0 Sales)', Icons.inventory_2_outlined),
        const SizedBox(height: 4),
        const Text('Active products in your catalog that have had zero sales. Capital is trapped on these items.', style: TextStyle(fontSize: 11, color: Colors.grey)),
        const SizedBox(height: 8),
        if (deadStock.isEmpty)
          _buildEmptyCard('All catalog products are selling! No zero-sales dead stock.')
        else
          ...deadStock.take(10).map((d) {
            final name = d['item_name'] as String? ?? '';
            final cat = d['category'] as String? ?? '';
            return Card(
              elevation: 0,
              margin: const EdgeInsets.only(bottom: 8),
              color: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
                side: BorderSide(color: Colors.grey.shade200),
              ),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                          const SizedBox(height: 2),
                          Text('Category: $cat', style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(color: Colors.red.shade50, borderRadius: BorderRadius.circular(6)),
                      child: Text('0 Sales', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.red.shade800)),
                    ),
                  ],
                ),
              ),
            );
          }),
        const SizedBox(height: 18),

        // Top 10 Best Sellers
        _buildSectionHeader('Top 10 Best-Selling Products', Icons.local_fire_department),
        const SizedBox(height: 8),
        ...topProducts.asMap().entries.map((entry) {
          final idx = entry.key + 1;
          final p = entry.value;
          final qty = (p['total_qty'] as num).toDouble();
          final rev = (p['total_rev'] as num).toDouble();
          final unit = p['unit'] as String? ?? '';
          return _buildProductRankCard(
            rank: idx,
            name: p['item_name'] as String? ?? 'Product',
            qtyText: '${qty.toStringAsFixed(1)} $unit',
            revenueText: currency.format(rev),
            isTop: true,
          );
        }),
        const SizedBox(height: 18),

        // Least-Selling Products
        _buildSectionHeader('Least-Selling / Slow-Moving Products', Icons.hourglass_bottom),
        const SizedBox(height: 8),
        ...leastProducts.asMap().entries.map((entry) {
          final idx = entry.key + 1;
          final p = entry.value;
          final qty = (p['total_qty'] as num).toDouble();
          final unit = p['unit'] as String? ?? '';
          return _buildProductRankCard(
            rank: idx,
            name: p['item_name'] as String? ?? 'Product',
            qtyText: '${qty.toStringAsFixed(1)} $unit',
            revenueText: '',
            isTop: false,
          );
        }),
        const SizedBox(height: 30),
      ],
    );
  }

  // -------------------------------------------------------------
  // TAB 4: STAFF & DEVICE LEADERBOARD
  // -------------------------------------------------------------
  Widget _buildStaffLeaderboardTab(NumberFormat currency) {
    final staffList = (_reportData!['staffLeaderboard'] as List<dynamic>?)?.cast<Map<String, dynamic>>() ?? [];

    return ListView(
      padding: const EdgeInsets.all(14),
      children: [
        _buildSectionHeader('Partner Device & Counter Leaderboard', Icons.military_tech_outlined),
        const SizedBox(height: 4),
        const Text('Track sales productivity, orders taken, and payments recovered per partner phone/counter.', style: TextStyle(fontSize: 11, color: Colors.grey)),
        const SizedBox(height: 12),
        if (staffList.isEmpty)
          _buildEmptyCard('No partner device orders recorded.')
        else
          ...staffList.asMap().entries.map((entry) {
            final idx = entry.key + 1;
            final s = entry.value;
            final name = s['staff_name'] as String? ?? 'Store';
            final orders = (s['orders_taken'] as num?)?.toInt() ?? 0;
            final sales = (s['total_sales'] as num?)?.toDouble() ?? 0.0;
            final directCollected = (s['direct_collected'] as num?)?.toDouble() ?? 0.0;
            final avgPerOrder = orders > 0 ? (sales / orders) : 0.0;

            return Card(
              elevation: 0,
              margin: const EdgeInsets.only(bottom: 10),
              color: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(color: idx == 1 ? const Color(0xFF0F766E) : Colors.grey.shade200, width: idx == 1 ? 1.5 : 1),
              ),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            color: idx == 1 ? const Color(0xFFCCFBF1) : Colors.grey.shade100,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            '#$idx',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                              color: idx == 1 ? const Color(0xFF0F766E) : Colors.black87,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            name,
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                          ),
                        ),
                        Text(
                          currency.format(sales),
                          style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: Color(0xFF0F766E)),
                        ),
                      ],
                    ),
                    const Divider(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('$orders orders taken', style: TextStyle(fontSize: 11, color: Colors.grey.shade700, fontWeight: FontWeight.w500)),
                        Text('Avg: ${currency.format(avgPerOrder)}/order', style: TextStyle(fontSize: 11, color: Colors.grey.shade700)),
                        Text('Collected: ${currency.format(directCollected)}', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF0284C7))),
                      ],
                    ),
                  ],
                ),
              ),
            );
          }),
        const SizedBox(height: 30),
      ],
    );
  }

  // -------------------------------------------------------------
  // TAB 5: COLLECTIONS LEDGER (SEARCHABLE)
  // -------------------------------------------------------------
  Widget _buildCollectionsLedgerTab(NumberFormat currency) {
    final rawList = (_reportData!['collections'] as List<dynamic>?)?.cast<Map<String, dynamic>>() ?? [];

    final filtered = rawList.where((c) {
      if (_collectionQuery.isEmpty) return true;
      final n = (c['customer_name'] as String? ?? '').toLowerCase();
      final p = (c['customer_phone'] as String? ?? '').toLowerCase();
      final l = (c['customer_location'] as String? ?? '').toLowerCase();
      return n.contains(_collectionQuery) ||
          p.contains(_collectionQuery) ||
          l.contains(_collectionQuery);
    }).toList();

    final totalCollectedInList =
        filtered.fold<double>(0.0, (sum, c) => sum + ((c['amount'] as num?)?.toDouble() ?? 0.0));

    return Column(
      children: [
        // Search & Total Bar
        Container(
          color: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Column(
            children: [
              TextField(
                controller: _collectionSearchCtrl,
                decoration: InputDecoration(
                  hintText: 'Search payer by name, phone or location...',
                  prefixIcon: const Icon(Icons.search, size: 18),
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  suffixIcon: _collectionSearchCtrl.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear, size: 16),
                          onPressed: () {
                            _collectionSearchCtrl.clear();
                            setState(() => _collectionQuery = '');
                          },
                        )
                      : null,
                ),
                onChanged: (val) => setState(() => _collectionQuery = val.trim().toLowerCase()),
              ),
              const SizedBox(height: 6),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '${filtered.length} Collections Found',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.grey.shade700),
                  ),
                  Text(
                    'Total: ${currency.format(totalCollectedInList)}',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w900,
                      color: Color(0xFF0F766E),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),

        // List of Collections
        Expanded(
          child: filtered.isEmpty
              ? _buildEmptyCard('No collections found matching this filter.')
              : ListView.separated(
                  padding: const EdgeInsets.all(12),
                  itemCount: filtered.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, idx) {
                    final item = filtered[idx];
                    final name = item['customer_name'] as String? ?? 'Customer';
                    final phone = item['customer_phone'] as String? ?? '';
                    final location = item['customer_location'] as String? ?? '';
                    final amount = (item['amount'] as num?)?.toDouble() ?? 0.0;
                    final remainingDue = (item['remaining_due'] as num?)?.toDouble() ?? 0.0;
                    final mode = (item['payment_mode'] as String? ?? 'cash').toUpperCase();
                    final rawDate = item['created_at'] as String?;
                    String timeFormatted = '';
                    if (rawDate != null) {
                      final dt = DateTime.tryParse(rawDate);
                      if (dt != null) timeFormatted = DateFormat('dd MMM yy • hh:mm a').format(dt);
                    }

                    return Card(
                      elevation: 0,
                      color: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(color: Colors.grey.shade200),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Left Block: Customer Details
                            Expanded(
                              flex: 6,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                                  const SizedBox(height: 3),
                                  if (phone.isNotEmpty)
                                    Row(
                                      children: [
                                        Icon(Icons.phone_outlined, size: 12, color: Colors.grey.shade600),
                                        const SizedBox(width: 4),
                                        Text(phone, style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
                                      ],
                                    ),
                                  if (location.isNotEmpty) ...[
                                    const SizedBox(height: 2),
                                    Row(
                                      children: [
                                        const Icon(Icons.location_on_outlined, size: 12, color: Color(0xFF0F766E)),
                                        const SizedBox(width: 4),
                                        Expanded(
                                          child: Text(
                                            location,
                                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: Color(0xFF0F766E)),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                  if (timeFormatted.isNotEmpty) ...[
                                    const SizedBox(height: 4),
                                    Text(timeFormatted, style: TextStyle(fontSize: 10, color: Colors.grey.shade500)),
                                  ],
                                ],
                              ),
                            ),

                            // Right Block: Collected Amount & Remaining Due
                            Expanded(
                              flex: 5,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(
                                    '+ ${currency.format(amount)}',
                                    style: const TextStyle(
                                      color: Color(0xFF0F766E),
                                      fontWeight: FontWeight.w900,
                                      fontSize: 15,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: mode == 'UPI' ? Colors.blue.shade50 : Colors.amber.shade50,
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      mode,
                                      style: TextStyle(
                                        fontSize: 9.5,
                                        fontWeight: FontWeight.bold,
                                        color: mode == 'UPI' ? Colors.blue.shade800 : Colors.amber.shade900,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Remaining: ${currency.format(remainingDue)}',
                                    style: TextStyle(
                                      fontSize: 10.5,
                                      fontWeight: FontWeight.w600,
                                      color: remainingDue > 0 ? Colors.red.shade700 : Colors.green.shade700,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildGradientKpiCard({
    required String title,
    required String subtitle,
    required String amount,
    required LinearGradient gradient,
    required IconData icon,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        gradient: gradient,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: gradient.colors.first.withValues(alpha: 0.25),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 9.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.4,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Icon(icon, size: 16, color: Colors.white70),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            amount,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 17,
              fontWeight: FontWeight.w900,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 3),
          Text(
            subtitle,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 10,
              fontWeight: FontWeight.w500,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _buildDayOfWeekBarChart(
      Map<int, Map<String, dynamic>> dayStats, NumberFormat currency) {
    final days = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
    double maxSales = 1.0;
    for (int i = 0; i < 7; i++) {
      final s = (dayStats[i]?['sales'] as num?)?.toDouble() ?? 0.0;
      if (s > maxSales) maxSales = s;
    }

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceAround,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: List.generate(7, (i) {
        final stat = dayStats[i];
        final count = (stat?['count'] as num?)?.toInt() ?? 0;
        final sales = (stat?['sales'] as num?)?.toDouble() ?? 0.0;
        final ratio = (sales / maxSales).clamp(0.08, 1.0);

        return Column(
          children: [
            Text('$count',
                style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF0F766E))),
            const SizedBox(height: 4),
            Container(
              width: 28,
              height: 100 * ratio,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF0F766E), Color(0xFF14B8A6)],
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                ),
                borderRadius: BorderRadius.circular(6),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              days[i],
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: Colors.grey.shade700,
              ),
            ),
          ],
        );
      }),
    );
  }

  Widget _buildCustomerRankCard({
    required int rank,
    required String name,
    required String? phone,
    required String? location,
    required String statLabel,
    required String statValue,
    required Color statColor,
    required Color badgeColor,
  }) {
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 8),
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: badgeColor,
                borderRadius: BorderRadius.circular(6),
              ),
              alignment: Alignment.center,
              child: Text(
                '#$rank',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                  color: statColor,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      if (phone != null && phone.isNotEmpty) ...[
                        Icon(Icons.phone_outlined, size: 11, color: Colors.grey.shade600),
                        const SizedBox(width: 3),
                        Text(phone, style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                        const SizedBox(width: 8),
                      ],
                      if (location != null && location.isNotEmpty) ...[
                        Icon(Icons.location_on_outlined, size: 11, color: Colors.grey.shade600),
                        const SizedBox(width: 2),
                        Flexible(
                          child: Text(
                            location,
                            style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(statLabel, style: TextStyle(fontSize: 9.5, color: Colors.grey.shade600)),
                Text(
                  statValue,
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 13.5,
                    color: statColor,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProductRankCard({
    required int rank,
    required String name,
    required String qtyText,
    required String revenueText,
    required bool isTop,
  }) {
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 8),
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            Container(
              width: 26,
              height: 26,
              decoration: BoxDecoration(
                color: isTop ? Colors.amber.shade50 : Colors.blueGrey.shade50,
                borderRadius: BorderRadius.circular(6),
              ),
              alignment: Alignment.center,
              child: Text(
                '#$rank',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 11,
                  color: isTop ? Colors.orange.shade800 : Colors.blueGrey,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                name,
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  qtyText,
                  style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 13,
                      color: Color(0xFF0F766E)),
                ),
                if (revenueText.isNotEmpty)
                  Text(
                    revenueText,
                    style: TextStyle(fontSize: 10, color: Colors.grey.shade600),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 16, color: const Color(0xFF0F766E)),
        const SizedBox(width: 6),
        Text(
          title,
          style: const TextStyle(
            fontSize: 13.5,
            fontWeight: FontWeight.w800,
            color: Color(0xFF1E293B),
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyCard(String msg) {
    return Card(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Center(
          child: Text(
            msg,
            style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
          ),
        ),
      ),
    );
  }
}
