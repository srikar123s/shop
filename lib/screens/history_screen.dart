import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shop/l10n/app_localizations.dart';
import 'package:shop/models/order.dart';
import 'package:shop/repositories/customer_repository.dart';
import 'package:shop/repositories/order_repository.dart';
import 'package:shop/repositories/product_repository.dart';
import 'package:shop/screens/customer_orders_screen.dart';
import 'package:shop/screens/order_details_screen.dart';
import 'package:shop/services/backup_service.dart';
import 'package:shop/services/shop_customization_service.dart';
import 'package:shop/services/shop_sync_service.dart';
import 'package:shop/services/voice_search_service.dart';

enum HistoryFilter { all, today, pending, partial, completed, customDate }

enum HistoryViewMode { byCustomer, byStaff, timeline }

class StaffHistoryGroup {
  StaffHistoryGroup({
    required this.staffName,
    required this.orders,
  });

  final String staffName;
  final List<OrderSummary> orders;

  int get pendingCount => orders
      .where((o) =>
          o.status == OrderStatus.pending ||
          o.status == OrderStatus.partiallyCompleted)
      .length;

  int get completedCount => orders
      .where((o) => o.status == OrderStatus.completed)
      .length;

  double get totalBillValue =>
      orders.fold(0.0, (sum, o) => sum + o.estimateTotal);

  DateTime get latestOrderDate => orders.isEmpty
      ? DateTime.now()
      : orders.map((o) => o.createdAt).reduce((a, b) => a.isAfter(b) ? a : b);
}

class CustomerHistoryGroup {
  CustomerHistoryGroup({
    required this.key,
    required this.name,
    required this.phone,
    required this.primaryCustomerId,
    required this.orders,
  });

  final String key;
  final String name;
  final String? phone;
  final int primaryCustomerId;
  final List<OrderSummary> orders;

  int get pendingCount => orders
      .where((o) =>
          o.status == OrderStatus.pending ||
          o.status == OrderStatus.partiallyCompleted)
      .length;

  double get totalBillValue =>
      orders.fold(0.0, (sum, o) => sum + o.estimateTotal);

  DateTime get latestOrderDate => orders.isEmpty
      ? DateTime.now()
      : orders.map((o) => o.createdAt).reduce((a, b) => a.isAfter(b) ? a : b);
}

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({
    super.key,
    required this.orderRepository,
    required this.backupService,
    required this.customerRepository,
    required this.productRepository,
    this.initialFilter = HistoryFilter.all,
  });

  final OrderRepository orderRepository;
  final BackupService backupService;
  final CustomerRepository customerRepository;
  final ProductRepository productRepository;
  final HistoryFilter initialFilter;

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  final TextEditingController _searchController = TextEditingController();
  List<OrderSummary> _orders = <OrderSummary>[];
  bool _loading = true;
  late HistoryFilter _filter;
  DateTime? _selectedDate;
  HistoryViewMode _viewMode = HistoryViewMode.byCustomer;
  String? _selectedTakenBy;
  String? _selectedLocation;

  @override
  void initState() {
    super.initState();
    _filter = widget.initialFilter;
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final data = await widget.orderRepository
        .searchOrderSummaries(_searchController.text);
    if (!mounted) return;
    setState(() {
      _orders = data;
      _loading = false;
    });
  }

  String _dateHeading(DateTime dt, AppLocalizations s) {
    final now = DateTime.now();
    final dayStart = DateTime(now.year, now.month, now.day);
    final orderDay = DateTime(dt.year, dt.month, dt.day);
    final diff = dayStart.difference(orderDay).inDays;
    if (diff == 0) return s.t('today');
    if (diff == 1) return s.t('yesterday');
    return DateFormat('dd MMM yyyy').format(dt);
  }

  Color _statusColor(OrderStatus status) {
    switch (status) {
      case OrderStatus.completed:
        return Colors.teal;
      case OrderStatus.partiallyCompleted:
        return Colors.orange.shade800;
      case OrderStatus.pending:
        return Colors.red.shade700;
      case OrderStatus.closed:
        return Colors.blueGrey;
    }
  }

  Color _statusBgColor(OrderStatus status) {
    switch (status) {
      case OrderStatus.completed:
        return Colors.teal.shade50;
      case OrderStatus.partiallyCompleted:
        return Colors.orange.shade50;
      case OrderStatus.pending:
        return Colors.red.shade50;
      case OrderStatus.closed:
        return Colors.blueGrey.shade50;
    }
  }

  Future<void> _pickCustomDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (!mounted) return;
    if (picked != null) {
      setState(() {
        _selectedDate = picked;
        _filter = HistoryFilter.customDate;
      });
    }
  }

  String _getCustomerGroupKey(String name, String? phone) {
    final cleanPhone = phone?.replaceAll(RegExp(r'[^0-9+]'), '').trim();
    if (cleanPhone != null && cleanPhone.isNotEmpty) {
      return 'phone:$cleanPhone';
    }
    return 'name:${name.trim().toLowerCase()}';
  }

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context);
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    final canViewTotals = ShopSyncService.instance.canViewBillTotals;

    final fallbackUser = ShopSyncService.instance.currentUserOrDeviceName;

    // Collect all members who have taken orders
    final allMembers = _orders
        .map((o) {
          final t = o.takenBy?.trim();
          if (t == null || t.isEmpty || t == 'Store') {
            return fallbackUser;
          }
          return t;
        })
        .toSet()
        .toList()
      ..sort();

    // Collect all customer locations
    final allLocations = _orders
        .map((o) => o.customerAddress?.trim() ?? '')
        .where((loc) => loc.isNotEmpty)
        .toSet()
        .toList()
      ..sort();

    // Filter orders
    final filteredOrders = _orders.where((order) {
      if (_selectedTakenBy != null) {
        final t = order.takenBy?.trim();
        final effectiveTaken = (t == null || t.isEmpty || t == 'Store') ? fallbackUser : t;
        if (effectiveTaken != _selectedTakenBy) return false;
      }
      if (_selectedLocation != null) {
        final loc = order.customerAddress?.trim() ?? '';
        if (loc != _selectedLocation) return false;
      }
      if (_filter == HistoryFilter.today) {
        return !order.createdAt.isBefore(todayStart) &&
            order.createdAt.isBefore(todayStart.add(const Duration(days: 1)));
      } else if (_filter == HistoryFilter.pending) {
        return order.status == OrderStatus.pending ||
            order.status == OrderStatus.partiallyCompleted;
      } else if (_filter == HistoryFilter.partial) {
        return order.status == OrderStatus.partiallyCompleted;
      } else if (_filter == HistoryFilter.completed) {
        return order.status == OrderStatus.completed;
      } else if (_filter == HistoryFilter.customDate && _selectedDate != null) {
        final dStart = DateTime(
            _selectedDate!.year, _selectedDate!.month, _selectedDate!.day);
        return !order.createdAt.isBefore(dStart) &&
            order.createdAt.isBefore(dStart.add(const Duration(days: 1)));
      }
      return true;
    }).toList();

    // Month summary for current month
    final currentMonthOrders = _orders
        .where((o) =>
            o.createdAt.year == now.year && o.createdAt.month == now.month)
        .toList();
    final currentMonthTotal = currentMonthOrders.fold<double>(
        0.0, (sum, o) => sum + o.estimateTotal);

    // Group filtered orders by month
    final monthGroups = <DateTime, List<OrderSummary>>{};
    for (final order in filteredOrders) {
      final mKey = DateTime(order.createdAt.year, order.createdAt.month);
      monthGroups.putIfAbsent(mKey, () => <OrderSummary>[]).add(order);
    }
    final sortedMonths = monthGroups.keys.toList()
      ..sort((a, b) => b.compareTo(a));

    final isLocalMode = ShopCustomizationService.instance.isPureOfflineMode;
    if (isLocalMode && _viewMode == HistoryViewMode.byStaff) {
      _viewMode = HistoryViewMode.byCustomer;
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(s.t('historyTitle')),
        actions: <Widget>[
          IconButton(
            tooltip: s.t('backup'),
            onPressed: () async {
              final path = await widget.backupService.createBackup();
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('${s.t('backupCreatedAt')} $path'),
                  duration: const Duration(seconds: 3),
                ),
              );
            },
            icon: const Icon(Icons.backup_outlined),
          ),
          IconButton(
            tooltip: s.t('restore'),
            onPressed: () async {
              final restored = await widget.backupService.restoreBackup();
              if (!context.mounted) return;
              if (restored) {
                await _load();
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(s.t('restoreComplete')),
                    duration: const Duration(seconds: 3),
                  ),
                );
              }
            },
            icon: const Icon(Icons.restore_outlined),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            // Search Input
            TextField(
              controller: _searchController,
              decoration: InputDecoration(
                labelText: s.t('searchCustomer'),
                hintText: 'Search by customer name, phone, order #...',
                prefixIcon: const Icon(Icons.search),
                isDense: true,
                suffixIcon: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_searchController.text.isNotEmpty)
                      IconButton(
                        onPressed: () {
                          _searchController.clear();
                          _load();
                        },
                        icon: const Icon(Icons.clear),
                      ),
                    IconButton(
                      tooltip: 'Voice Search Customer',
                      icon: const Icon(Icons.mic, color: Color(0xFF0F766E), size: 20),
                      onPressed: () async {
                        final text = await VoiceSearchService.instance
                            .recordSpeech(
                          context,
                          title: 'Search Orders',
                          hint: 'Say customer name (e.g. Srikar, Kamal Sai)...',
                        );
                        if (text != null && text.trim().isNotEmpty) {
                          _searchController.text = text.trim();
                          _load();
                        }
                      },
                    ),
                  ],
                ),
              ),
              onChanged: (_) => _load(),
            ),
            const SizedBox(height: 8),

            // View Mode Selector (By Customer / By Staff / All Orders)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 4),
              child: SegmentedButton<HistoryViewMode>(
                segments: [
                  const ButtonSegment(
                    value: HistoryViewMode.byCustomer,
                    label: Text('Customers', style: TextStyle(fontSize: 12)),
                    icon: Icon(Icons.people_outline, size: 16),
                  ),
                  if (!isLocalMode)
                    const ButtonSegment(
                      value: HistoryViewMode.byStaff,
                      label: Text('By Partner', style: TextStyle(fontSize: 12)),
                      icon: Icon(Icons.person_pin_outlined, size: 16),
                    ),
                  const ButtonSegment(
                    value: HistoryViewMode.timeline,
                    label: Text('All Orders', style: TextStyle(fontSize: 12)),
                    icon: Icon(Icons.format_list_bulleted_rounded, size: 16),
                  ),
                ],
                selected: {_viewMode},
                onSelectionChanged: (val) {
                  setState(() => _viewMode = val.first);
                },
                style: const ButtonStyle(
                  visualDensity: VisualDensity.compact,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
            ),
            const SizedBox(height: 6),

            // Top Monthly Total Banner
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFF0F766E).withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                    color: const Color(0xFF0F766E).withValues(alpha: 0.2)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0F766E).withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(Icons.calendar_month_rounded,
                            color: Color(0xFF0F766E), size: 20),
                      ),
                      const SizedBox(width: 10),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${DateFormat('MMMM yyyy').format(now)} Total',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                              color: Color(0xFF0F766E),
                            ),
                          ),
                          Text(
                            '${currentMonthOrders.length} orders this month',
                            style: TextStyle(
                                fontSize: 11, color: Colors.grey.shade700),
                          ),
                        ],
                      ),
                    ],
                  ),
                  Text(
                    canViewTotals
                        ? '₹ ${currentMonthTotal.toStringAsFixed(2)}'
                        : '₹ ••••',
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 16,
                      color: Color(0xFF0F766E),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),

            // Filter by "Taken By" Member Dropdown
            if (!isLocalMode && allMembers.length > 1)
              Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.badge_outlined,
                        size: 16, color: Color(0xFF0F766E)),
                    const SizedBox(width: 8),
                    const Text('Taken by:',
                        style: TextStyle(
                            fontSize: 12, fontWeight: FontWeight.bold)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String?>(
                          value: _selectedTakenBy,
                          isDense: true,
                          style: const TextStyle(
                            fontSize: 12,
                            color: Color(0xFF0F766E),
                            fontWeight: FontWeight.bold,
                          ),
                          items: [
                            const DropdownMenuItem<String?>(
                              value: null,
                              child: Text('All Members / Devices'),
                            ),
                            ...allMembers.map((m) => DropdownMenuItem<String?>(
                                  value: m,
                                  child: Text(m),
                                )),
                          ],
                          onChanged: (val) {
                            setState(() => _selectedTakenBy = val);
                          },
                        ),
                      ),
                    ),
                    if (_selectedTakenBy != null)
                      GestureDetector(
                        onTap: () => setState(() => _selectedTakenBy = null),
                        child: const Icon(Icons.close,
                            size: 16, color: Colors.grey),
                      ),
                  ],
                ),
              ),

            // Filter by Location Dropdown
            if (allLocations.isNotEmpty)
              Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.location_on_outlined,
                        size: 16, color: Color(0xFF0F766E)),
                    const SizedBox(width: 8),
                    const Text('Location:',
                        style: TextStyle(
                            fontSize: 12, fontWeight: FontWeight.bold)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String?>(
                          value: _selectedLocation,
                          isDense: true,
                          style: const TextStyle(
                            fontSize: 12,
                            color: Color(0xFF0F766E),
                            fontWeight: FontWeight.bold,
                          ),
                          items: [
                            const DropdownMenuItem<String?>(
                              value: null,
                              child: Text('All Locations'),
                            ),
                            ...allLocations.map((loc) => DropdownMenuItem<String?>(
                                  value: loc,
                                  child: Text(loc, overflow: TextOverflow.ellipsis),
                                )),
                          ],
                          onChanged: (val) {
                            setState(() => _selectedLocation = val);
                          },
                        ),
                      ),
                    ),
                    if (_selectedLocation != null)
                      GestureDetector(
                        onTap: () => setState(() => _selectedLocation = null),
                        child: const Icon(Icons.close,
                            size: 16, color: Colors.grey),
                      ),
                  ],
                ),
              ),

            // Status Filter Chips Row
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  ChoiceChip(
                    label: Text('All (${_orders.length})'),
                    selected: _filter == HistoryFilter.all,
                    onSelected: (val) {
                      if (val) setState(() => _filter = HistoryFilter.all);
                    },
                  ),
                  const SizedBox(width: 6),
                  ChoiceChip(
                    label: const Text('Today'),
                    selected: _filter == HistoryFilter.today,
                    onSelected: (val) {
                      if (val) setState(() => _filter = HistoryFilter.today);
                    },
                  ),
                  const SizedBox(width: 6),
                  ChoiceChip(
                    label: const Text('Pending / Open'),
                    selected: _filter == HistoryFilter.pending,
                    onSelected: (val) {
                      if (val) setState(() => _filter = HistoryFilter.pending);
                    },
                  ),
                  const SizedBox(width: 6),
                  ChoiceChip(
                    label: const Text('Partially Delivered'),
                    selected: _filter == HistoryFilter.partial,
                    onSelected: (val) {
                      if (val) setState(() => _filter = HistoryFilter.partial);
                    },
                  ),
                  const SizedBox(width: 6),
                  ChoiceChip(
                    label: const Text('Completed'),
                    selected: _filter == HistoryFilter.completed,
                    onSelected: (val) {
                      if (val) {
                        setState(() => _filter = HistoryFilter.completed);
                      }
                    },
                  ),
                  const SizedBox(width: 6),
                  ActionChip(
                    avatar: const Icon(Icons.calendar_month_outlined, size: 16),
                    label: Text(_selectedDate != null &&
                            _filter == HistoryFilter.customDate
                        ? DateFormat('dd MMM yyyy').format(_selectedDate!)
                        : 'Pick Date'),
                    backgroundColor: _filter == HistoryFilter.customDate
                        ? Theme.of(context).colorScheme.primaryContainer
                        : null,
                    onPressed: _pickCustomDate,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),

            // Results count and active view label
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '${filteredOrders.length} order(s) found',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey.shade600),
                ),
                Text(
                  _viewMode == HistoryViewMode.byCustomer
                      ? 'Grouped by Customer'
                      : _viewMode == HistoryViewMode.byStaff
                          ? 'Grouped by Member / Counter'
                          : 'Individual Orders View',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).colorScheme.primary),
                ),
              ],
            ),
            const SizedBox(height: 6),

            // Content List with Month Section Headers & Totals
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : filteredOrders.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.filter_alt_off_outlined,
                                  size: 48, color: Colors.grey.shade400),
                              const SizedBox(height: 12),
                              const Text(
                                'No orders found matching this filter.',
                                style: TextStyle(
                                    fontWeight: FontWeight.w600, fontSize: 14),
                              ),
                              const SizedBox(height: 4),
                              TextButton(
                                onPressed: () {
                                  setState(() {
                                    _filter = HistoryFilter.all;
                                    _selectedTakenBy = null;
                                    _selectedLocation = null;
                                    _searchController.clear();
                                  });
                                  _load();
                                },
                                child: const Text('Clear All Filters'),
                              ),
                            ],
                          ),
                        )
                      : ListView.builder(
                          itemCount: sortedMonths.length,
                          itemBuilder: (context, mIdx) {
                            final monthDate = sortedMonths[mIdx];
                            final monthOrders = monthGroups[monthDate]!;
                            final monthTotal = monthOrders.fold<double>(
                                0.0, (sum, o) => sum + o.estimateTotal);

                            // Build grouped customers for this month
                            final customerMap =
                                <String, CustomerHistoryGroup>{};
                            for (final o in monthOrders) {
                              final gKey =
                                  _getCustomerGroupKey(o.customerName, o.customerPhone);
                              customerMap.putIfAbsent(
                                gKey,
                                () => CustomerHistoryGroup(
                                  key: gKey,
                                  name: o.customerName,
                                  phone: o.customerPhone,
                                  primaryCustomerId: o.customerId,
                                  orders: <OrderSummary>[],
                                ),
                              ).orders.add(o);
                            }
                            final customerGroups = customerMap.values.toList()
                              ..sort((a, b) => b.latestOrderDate
                                  .compareTo(a.latestOrderDate));

                            // Build grouped staff for this month
                            final staffMap = <String, StaffHistoryGroup>{};
                            for (final o in monthOrders) {
                              final sName = (o.takenBy != null &&
                                      o.takenBy!.trim().isNotEmpty &&
                                      o.takenBy!.trim() != 'Store')
                                  ? o.takenBy!.trim()
                                  : fallbackUser;
                              staffMap.putIfAbsent(
                                sName,
                                () => StaffHistoryGroup(
                                  staffName: sName,
                                  orders: <OrderSummary>[],
                                ),
                              ).orders.add(o);
                            }
                            final staffGroups = staffMap.values.toList()
                              ..sort((a, b) => b.latestOrderDate
                                  .compareTo(a.latestOrderDate));

                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Sticky/Month Section Header with Total Bill Value
                                Container(
                                  margin:
                                      const EdgeInsets.only(top: 14, bottom: 8),
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 14, vertical: 8),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF0F766E)
                                        .withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(
                                        color: const Color(0xFF0F766E)
                                            .withValues(alpha: 0.2)),
                                  ),
                                  child: Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      Row(
                                        children: [
                                          const Icon(
                                              Icons.calendar_month_outlined,
                                              size: 16,
                                              color: Color(0xFF0F766E)),
                                          const SizedBox(width: 6),
                                          Text(
                                            DateFormat('MMMM yyyy')
                                                .format(monthDate),
                                            style: const TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 14,
                                              color: Color(0xFF0F766E),
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          Text(
                                            '(${monthOrders.length} orders)',
                                            style: TextStyle(
                                                fontSize: 11,
                                                color: Colors.grey.shade700),
                                          ),
                                        ],
                                      ),
                                      Text(
                                        canViewTotals
                                            ? '₹ ${monthTotal.toStringAsFixed(2)}'
                                            : '₹ ••••',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w900,
                                          fontSize: 14,
                                          color: Color(0xFF0F766E),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),

                                // Customer Cards, Staff Groups, or Individual Orders
                                if (_viewMode == HistoryViewMode.byCustomer)
                                  ...customerGroups.map((group) {
                                    final latest = group.orders.first;
                                    final displayCustomerTakenBy = (latest.takenBy != null &&
                                            latest.takenBy!.trim().isNotEmpty &&
                                            latest.takenBy!.trim() != 'Store')
                                        ? latest.takenBy!.trim()
                                        : fallbackUser;
                                    final pendingCount = group.pendingCount;

                                    return Padding(
                                      padding:
                                          const EdgeInsets.only(bottom: 8),
                                      child: Card(
                                        elevation: 1,
                                        shape: RoundedRectangleBorder(
                                            borderRadius:
                                                BorderRadius.circular(14)),
                                        child: ListTile(
                                          contentPadding:
                                              const EdgeInsets.symmetric(
                                                  horizontal: 14, vertical: 6),
                                          leading: CircleAvatar(
                                            radius: 20,
                                            backgroundColor: Theme.of(context)
                                                .colorScheme
                                                .primaryContainer,
                                            child: Text(
                                              group.name.isNotEmpty
                                                  ? group.name[0].toUpperCase()
                                                  : 'C',
                                              style: const TextStyle(
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 16),
                                            ),
                                          ),
                                          title: Row(
                                            children: [
                                              Expanded(
                                                child: Text(
                                                  group.name,
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: const TextStyle(
                                                      fontWeight:
                                                          FontWeight.bold,
                                                      fontSize: 15),
                                                ),
                                              ),
                                              if (group.totalBillValue > 0)
                                                Text(
                                                  canViewTotals
                                                      ? '₹ ${group.totalBillValue.toStringAsFixed(0)}'
                                                      : '₹ •••',
                                                  style: const TextStyle(
                                                    fontWeight: FontWeight.w800,
                                                    fontSize: 13,
                                                    color: Color(0xFF0F766E),
                                                  ),
                                                ),
                                            ],
                                          ),
                                          subtitle: Padding(
                                            padding:
                                                const EdgeInsets.only(top: 3),
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                if (!isLocalMode) ...[
                                                  Row(
                                                    children: [
                                                      Icon(
                                                        Icons
                                                            .person_pin_circle_outlined,
                                                        size: 12,
                                                        color: Colors
                                                            .teal.shade700,
                                                      ),
                                                      const SizedBox(width: 4),
                                                      Text(
                                                        'Taken by: $displayCustomerTakenBy',
                                                        style: TextStyle(
                                                          fontSize: 11,
                                                          fontWeight:
                                                              FontWeight.w600,
                                                          color: Colors
                                                              .teal.shade800,
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                  const SizedBox(height: 2),
                                                ],
                                                if (group.phone != null &&
                                                    group.phone!
                                                        .trim()
                                                        .isNotEmpty)
                                                  Text(
                                                    '📞 ${group.phone}',
                                                    style: TextStyle(
                                                        fontSize: 11,
                                                        color: Colors
                                                            .grey.shade600),
                                                  ),
                                                Text(
                                                  '${group.orders.length} ${group.orders.length == 1 ? 'order' : 'orders'} • Latest: ${_dateHeading(latest.createdAt, s)}',
                                                  style: TextStyle(
                                                      color:
                                                          Colors.grey.shade700,
                                                      fontSize: 12),
                                                ),
                                              ],
                                            ),
                                          ),
                                          trailing: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              if (pendingCount > 0)
                                                Container(
                                                  padding: const EdgeInsets
                                                      .symmetric(
                                                      horizontal: 8,
                                                      vertical: 4),
                                                  decoration: BoxDecoration(
                                                    color: Colors
                                                        .deepOrange.shade100,
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                            12),
                                                  ),
                                                  child: Text(
                                                    '$pendingCount pending',
                                                    style: TextStyle(
                                                      color: Colors.deepOrange
                                                          .shade900,
                                                      fontWeight:
                                                          FontWeight.bold,
                                                      fontSize: 11,
                                                    ),
                                                  ),
                                                ),
                                              const SizedBox(width: 4),
                                              const Icon(Icons.chevron_right,
                                                  color: Colors.grey),
                                            ],
                                          ),
                                          onTap: () async {
                                            await Navigator.push(
                                              context,
                                              MaterialPageRoute<void>(
                                                builder: (_) =>
                                                    CustomerOrdersScreen(
                                                  customerId:
                                                      group.primaryCustomerId,
                                                  customerName: group.name,
                                                  customerPhone: group.phone,
                                                  customerRepository: widget
                                                      .customerRepository,
                                                  productRepository: widget
                                                      .productRepository,
                                                  orderRepository:
                                                      widget.orderRepository,
                                                ),
                                              ),
                                            );
                                            await _load();
                                          },
                                        ),
                                      ),
                                    );
                                  })
                                else if (_viewMode == HistoryViewMode.byStaff)
                                  ...staffGroups.map((sGroup) =>
                                      _buildStaffGroupCard(sGroup, canViewTotals, s))
                                else
                                  ...monthOrders.map((order) {
                                    final formattedId = order.formattedOrderId;
                                    final displayTakenBy = (order.takenBy != null &&
                                            order.takenBy!.trim().isNotEmpty &&
                                            order.takenBy!.trim() != "Store")
                                        ? order.takenBy!.trim()
                                        : fallbackUser;
                                    return Padding(
                                      padding:
                                          const EdgeInsets.only(bottom: 8),
                                      child: Card(
                                        elevation: 1,
                                        shape: RoundedRectangleBorder(
                                            borderRadius:
                                                BorderRadius.circular(14)),
                                        child: ListTile(
                                          contentPadding:
                                              const EdgeInsets.symmetric(
                                                  horizontal: 14, vertical: 8),
                                          leading: Container(
                                            padding: const EdgeInsets.all(8),
                                            decoration: BoxDecoration(
                                              color:
                                                  _statusBgColor(order.status),
                                              borderRadius:
                                                  BorderRadius.circular(10),
                                            ),
                                            child: Icon(
                                                Icons.receipt_long_rounded,
                                                color:
                                                    _statusColor(order.status),
                                                size: 22),
                                          ),
                                          title: Row(
                                            mainAxisAlignment:
                                                MainAxisAlignment.spaceBetween,
                                            children: [
                                              Text(
                                                formattedId,
                                                style: const TextStyle(
                                                    fontWeight: FontWeight.bold,
                                                    fontSize: 14),
                                              ),
                                              Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                        horizontal: 7,
                                                        vertical: 2),
                                                decoration: BoxDecoration(
                                                  color: _statusBgColor(
                                                      order.status),
                                                  borderRadius:
                                                      BorderRadius.circular(8),
                                                ),
                                                child: Text(
                                                  orderStatusLabel(
                                                      order.status),
                                                  style: TextStyle(
                                                      fontSize: 10,
                                                      fontWeight:
                                                          FontWeight.bold,
                                                      color: _statusColor(
                                                          order.status)),
                                                ),
                                              ),
                                            ],
                                          ),
                                          subtitle: Padding(
                                            padding:
                                                const EdgeInsets.only(top: 4),
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  order.customerName,
                                                  style: const TextStyle(
                                                      fontWeight:
                                                          FontWeight.w600,
                                                      fontSize: 13,
                                                      color:
                                                          Color(0xFF1E293B)),
                                                ),
                                                if (!isLocalMode) ...[
                                                  const SizedBox(height: 2),
                                                  Row(
                                                    children: [
                                                      Icon(
                                                          Icons
                                                              .person_pin_circle_outlined,
                                                          size: 12,
                                                          color: Colors
                                                              .teal.shade700),
                                                      const SizedBox(width: 4),
                                                      Text(
                                                        'Taken by: $displayTakenBy',
                                                        style: TextStyle(
                                                            fontSize: 11,
                                                            fontWeight:
                                                                FontWeight.w600,
                                                            color: Colors
                                                                .teal.shade800),
                                                      ),
                                                    ],
                                                  ),
                                                ],
                                                const SizedBox(height: 4),
                                                Row(
                                                  mainAxisAlignment:
                                                      MainAxisAlignment
                                                          .spaceBetween,
                                                  children: [
                                                    Text(
                                                      DateFormat(
                                                              'dd MMM yyyy, hh:mm a')
                                                          .format(
                                                              order.createdAt),
                                                      style: TextStyle(
                                                          fontSize: 11,
                                                          color: Colors
                                                              .grey.shade600),
                                                    ),
                                                    Text(
                                                      '${order.totalItems} items',
                                                      style: TextStyle(
                                                          fontSize: 11,
                                                          fontWeight:
                                                              FontWeight.bold,
                                                          color: Colors
                                                              .grey.shade700),
                                                    ),
                                                  ],
                                                ),
                                                if (order.unfulfilledItemNames.isNotEmpty) ...[
                                                  const SizedBox(height: 6),
                                                  Container(
                                                    padding: const EdgeInsets.symmetric(
                                                        horizontal: 8, vertical: 4),
                                                    decoration: BoxDecoration(
                                                      color: const Color(0xFFFEF2F2),
                                                      borderRadius:
                                                          BorderRadius.circular(6),
                                                      border: Border.all(
                                                          color: const Color(0xFFFECACA)),
                                                    ),
                                                    child: Row(
                                                      children: [
                                                        const Icon(
                                                          Icons.warning_amber_rounded,
                                                          size: 13,
                                                          color: Color(0xFFDC2626),
                                                        ),
                                                        const SizedBox(width: 4),
                                                        Expanded(
                                                          child: Text(
                                                            'Not Given: ${order.unfulfilledItemNames.join(", ")}',
                                                            style: const TextStyle(
                                                              fontSize: 10,
                                                              fontWeight:
                                                                  FontWeight.bold,
                                                              color: Color(0xFF991B1B),
                                                            ),
                                                            maxLines: 2,
                                                            overflow:
                                                                TextOverflow.ellipsis,
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                ],
                                              ],
                                            ),
                                          ),
                                          trailing: Column(
                                            mainAxisAlignment:
                                                MainAxisAlignment.center,
                                            crossAxisAlignment:
                                                CrossAxisAlignment.end,
                                            children: [
                                              if (order.estimateTotal > 0)
                                                Text(
                                                  canViewTotals
                                                      ? '₹ ${order.estimateTotal.toStringAsFixed(2)}'
                                                      : '₹ ••••',
                                                  style: const TextStyle(
                                                      fontWeight:
                                                          FontWeight.w800,
                                                      fontSize: 13,
                                                      color: Color(0xFF0F766E)),
                                                ),
                                              const SizedBox(height: 4),
                                              const Icon(Icons.chevron_right,
                                                  size: 18,
                                                  color: Colors.grey),
                                            ],
                                          ),
                                          onTap: () async {
                                            await Navigator.push(
                                              context,
                                              MaterialPageRoute<void>(
                                                builder: (_) =>
                                                    OrderDetailsScreen(
                                                  orderId: order.orderId,
                                                  orderRepository: widget
                                                      .orderRepository,
                                                  customerRepository: widget
                                                      .customerRepository,
                                                  productRepository: widget
                                                      .productRepository,
                                                ),
                                              ),
                                            );
                                            await _load();
                                          },
                                        ),
                                      ),
                                    );
                                  }),
                              ],
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStaffGroupCard(
      StaffHistoryGroup group, bool canViewTotals, AppLocalizations s) {
    final pendingCount = group.pendingCount;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Card(
        elevation: 1,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        child: ExpansionTile(
          shape: const Border(),
          collapsedShape: const Border(),
          tilePadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
          leading: CircleAvatar(
            radius: 20,
            backgroundColor: const Color(0xFF0F766E).withValues(alpha: 0.12),
            child: const Icon(Icons.person_pin_rounded,
                color: Color(0xFF0F766E), size: 22),
          ),
          title: Row(
            children: [
              Expanded(
                child: Text(
                  group.staffName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 15),
                ),
              ),
              if (group.totalBillValue > 0)
                Text(
                  canViewTotals
                      ? '₹ ${group.totalBillValue.toStringAsFixed(0)}'
                      : '₹ •••',
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                    color: Color(0xFF0F766E),
                  ),
                ),
            ],
          ),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 3),
            child: Row(
              children: [
                Text(
                  '${group.orders.length} ${group.orders.length == 1 ? 'order' : 'orders'} taken',
                  style: TextStyle(color: Colors.grey.shade700, fontSize: 12),
                ),
                if (pendingCount > 0) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                    decoration: BoxDecoration(
                      color: Colors.orange.shade50,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: Colors.orange.shade200),
                    ),
                    child: Text(
                      '$pendingCount pending',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: Colors.orange.shade900,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          children: group.orders.map((o) {
            final formattedId = o.formattedOrderId;
            return Container(
              margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: ListTile(
                dense: true,
                onTap: () async {
                  await Navigator.push(
                    context,
                    MaterialPageRoute<void>(
                      builder: (ctx) => OrderDetailsScreen(
                        orderId: o.orderId,
                        orderRepository: widget.orderRepository,
                        customerRepository: widget.customerRepository,
                        productRepository: widget.productRepository,
                      ),
                    ),
                  );
                  _load();
                },
                title: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '$formattedId • ${o.customerName}',
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                    Text(
                      canViewTotals
                          ? '₹ ${o.estimateTotal.toStringAsFixed(0)}'
                          : '₹ •••',
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF0F766E),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
                subtitle: Text(
                  '${o.totalItems} items • ${DateFormat('dd MMM, hh:mm a').format(o.createdAt)} • ${orderStatusLabel(o.status)}',
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                ),
                trailing: const Icon(Icons.chevron_right, size: 18),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }
}
