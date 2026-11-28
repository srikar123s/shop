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
import 'package:shop/widgets/phone_picker_modal.dart';

part 'lifetime_report_tabs.dart';

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
      await _loadReport();
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

  Future<String?> _pickCleanPhone(
    String rawPhone, {
    required String customerName,
    required String actionTitle,
  }) async {
    final numbers = Customer.extractNumbers(rawPhone);
    final validNumbers = <String>[];
    for (final numStr in numbers) {
      final clean = numStr.replaceAll(RegExp(r'[^0-9]'), '');
      if (clean.length >= 6 && !validNumbers.contains(clean)) {
        validNumbers.add(clean);
      }
    }
    if (validNumbers.isEmpty) {
      final fallback = _firstCleanPhone(rawPhone);
      if (fallback == null) return null;
      validNumbers.add(fallback);
    }
    if (validNumbers.length == 1) {
      return validNumbers.first;
    }
    if (!mounted) return null;
    final selected = await showPhonePickerModal(
      context: context,
      customerName: customerName,
      phoneNumbers: validNumbers,
      actionTitle: actionTitle,
    );
    if (selected == null) return null;
    return selected.replaceAll(RegExp(r'[^0-9]'), '');
  }

  Future<void> _launchWhatsAppMessage(
    String rawPhone,
    String text, {
    String customerName = 'Customer',
  }) async {
    final numbers = Customer.extractNumbers(rawPhone);
    final hasAnyValid = numbers.any((n) => n.replaceAll(RegExp(r'[^0-9]'), '').length >= 6) ||
        _firstCleanPhone(rawPhone) != null;
    if (!hasAnyValid) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Invalid phone number for WhatsApp.')),
        );
      }
      return;
    }
    final clean = await _pickCleanPhone(
      rawPhone,
      customerName: customerName,
      actionTitle: 'Send WhatsApp To',
    );
    if (clean == null) return;
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
    await _launchWhatsAppMessage(phone, text, customerName: customerName);
  }

  Future<void> _sendWinBackWhatsApp({
    required String customerName,
    required String phone,
    required int daysInactive,
  }) async {
    final shopName = ShopCustomizationService.instance.currentShopName;
    final text =
        'Hello $customerName,\n\nWe missed seeing you at $shopName over the past few weeks! 😊\nWe have new stock and best wholesale prices available. Please let us know if you need any goods today.\n\nThank you!';
    await _launchWhatsAppMessage(phone, text, customerName: customerName);
  }

  Future<void> _callPhone(String phone, {String customerName = 'Customer'}) async {
    final clean = await _pickCleanPhone(
      phone,
      customerName: customerName,
      actionTitle: 'Call Customer',
    );
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

    final s = AppLocalizations.of(context);
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              s.t('lifetimeAnalytics'),
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            Text(
              s.t('lifetimeAnalyticsSubtitle'),
              style: const TextStyle(fontSize: 11, color: Colors.white70),
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
            tooltip: s.t('refresh'),
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
              tabs: [
                Tab(text: s.t('tabFinancialHealth')),
                Tab(text: s.t('tabCustomerLoyalty')),
                Tab(text: s.t('tabProductsInventory')),
                Tab(text: s.t('tabPartnerLeaderboard')),
                Tab(text: s.t('tabCollectionsLedger')),
              ],
            ),
          ),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _reportData == null
              ? Center(child: Text(s.t('failedLoadAnalytics')))
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
                                  _selectedTakenBy != null
                                      ? '${AppLocalizations.of(context).t('deliveryExpense')} (${AppLocalizations.of(context).t('allDrivers')})'
                                      : AppLocalizations.of(context)
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
                _buildFilterChip(AppLocalizations.of(context).t('rangeLifetime'), DateRangeFilter.lifetime),
                const SizedBox(width: 6),
                _buildFilterChip(AppLocalizations.of(context).t('rangeToday'), DateRangeFilter.today),
                const SizedBox(width: 6),
                _buildFilterChip(AppLocalizations.of(context).t('rangeThisWeek'), DateRangeFilter.thisWeek),
                const SizedBox(width: 6),
                _buildFilterChip(AppLocalizations.of(context).t('rangeThisMonth'), DateRangeFilter.thisMonth),
                const SizedBox(width: 6),
                ActionChip(
                  avatar: const Icon(Icons.date_range, size: 16),
                  label: Text(_rangeFilter == DateRangeFilter.custom
                      ? _dateRangeLabel
                      : AppLocalizations.of(context).t('rangeCustom')),
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
                            hint: Text(
                                AppLocalizations.of(context).t('allLocationsHint'),
                                style: const TextStyle(fontSize: 11)),
                            style: const TextStyle(
                                fontSize: 11, color: Colors.black87),
                            items: [
                              DropdownMenuItem<String?>(
                                value: null,
                                child: Text(
                                    AppLocalizations.of(context).t('allLocationsMarket'),
                                    style: const TextStyle(fontSize: 11)),
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
                            hint: Text(
                                AppLocalizations.of(context).t('allPartnersHint'),
                                style: const TextStyle(fontSize: 11)),
                            style: const TextStyle(
                                fontSize: 11, color: Colors.black87),
                            items: [
                              DropdownMenuItem<String?>(
                                value: null,
                                child: Text(
                                    AppLocalizations.of(context).t('allPartnerDevices'),
                                    style: const TextStyle(fontSize: 11)),
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

  void _setCollectionQuery(String value) => setState(() => _collectionQuery = value);

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

}
