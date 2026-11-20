import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shop/l10n/app_localizations.dart';
import 'package:shop/models/order.dart';
import 'package:shop/repositories/customer_repository.dart';
import 'package:shop/repositories/order_repository.dart';
import 'package:shop/repositories/product_repository.dart';
import 'package:shop/screens/customer_screen.dart';
import 'package:shop/screens/history_screen.dart';
import 'package:shop/screens/order_details_screen.dart';
import 'package:shop/screens/shop_settings_screen.dart';
import 'package:shop/database/database_helper.dart';
import 'package:shop/models/top_product_stat.dart';
import 'package:shop/screens/top_selling_screen.dart';
import 'package:shop/screens/price_list_screen.dart';
import 'package:shop/screens/khata_book_screen.dart';
import 'package:shop/screens/evening_report_screen.dart';
import 'package:shop/screens/app_documentation_screen.dart';

import 'package:shop/screens/procurement_screen.dart';
import 'package:shop/screens/shop_sync_screen.dart';
import 'package:shop/screens/simple_product_admin_screen.dart';
import 'package:shop/services/app_notification_service.dart';
import 'package:shop/services/backup_service.dart';
import 'package:shop/services/shop_customization_service.dart';
import 'package:shop/services/shop_sync_service.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    required this.customerRepository,
    required this.productRepository,
    required this.orderRepository,
    required this.backupService,
    required this.locale,
    required this.onLocaleChanged,
  });

  final CustomerRepository customerRepository;
  final ProductRepository productRepository;
  final OrderRepository orderRepository;
  final BackupService backupService;
  final Locale locale;
  final ValueChanged<Locale> onLocaleChanged;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  bool _isTopSellingExpanded = false;
  bool _priceCautionBannerDismissed = false;
  @override
  void initState() {
    super.initState();
    ShopSyncService.instance.addListener(_onSyncUpdate);
    ShopCustomizationService.instance.addListener(_onSyncUpdate);
  }

  @override
  void dispose() {
    ShopSyncService.instance.removeListener(_onSyncUpdate);
    ShopCustomizationService.instance.removeListener(_onSyncUpdate);
    super.dispose();
  }

  void _onSyncUpdate() {
    if (mounted) setState(() {});
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

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final now = DateTime.now();
    final isOffline = ShopCustomizationService.instance.isPureOfflineMode ||
        const bool.fromEnvironment('STANDALONE_LOCAL', defaultValue: false);

    return Scaffold(
      key: _scaffoldKey,
      drawer: _buildSideDrawer(context, theme, s),
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Menu & Insights (Side Bar)',
          icon: const Icon(Icons.menu_rounded),
          onPressed: () => _scaffoldKey.currentState?.openDrawer(),
        ),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(Icons.storefront,
                  color: theme.colorScheme.primary, size: 20),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                ShopCustomizationService.instance.shopName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 18,
                  letterSpacing: 0.5,
                ),
              ),
            ),
          ],
        ),
        actions: <Widget>[
          IconButton(
            tooltip: 'Quick Price List',
            icon: const Icon(Icons.sell_outlined),
            onPressed: () async {
              await Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => PriceListScreen(
                    productRepository: widget.productRepository,
                  ),
                ),
              );
              setState(() {});
            },
          ),
          if (!ShopCustomizationService.instance.isPureOfflineMode &&
              !const bool.fromEnvironment('STANDALONE_LOCAL',
                  defaultValue: false))
            IconButton(
              tooltip: 'Shop Sync & Team',
              onPressed: () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                      builder: (_) => const ShopSyncScreen()),
                );
                setState(() {});
              },
              icon: Stack(
                clipBehavior: Clip.none,
                children: [
                  const Icon(Icons.cloud_sync_outlined),
                  if (ShopSyncService.instance.isConnected)
                    Positioned(
                      right: -1,
                      top: -1,
                      child: Container(
                        width: 8,
                        height: 8,
                        decoration: const BoxDecoration(
                          color: Color(0xFF10B981),
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          IconButton(
            tooltip: s.t('shopSettings'),
            onPressed: () async {
              await Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => ShopSettingsScreen(
                    productRepository: widget.productRepository,
                    locale: widget.locale,
                    onLocaleChanged: widget.onLocaleChanged,
                  ),
                ),
              );
              setState(() {});
            },
            icon: const Icon(Icons.settings_outlined),
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              // In-App Price Caution Notification Banner
              _buildPriceCautionBanner(),

              // Top Expandable Bar: Top Selling Products
              _buildTopSellingExpandableBar(theme),
              const SizedBox(height: 8),

              // Date Banner & Shop Sync Pill
              Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.calendar_today_outlined,
                        size: 15, color: Colors.grey.shade600),
                    const SizedBox(width: 8),
                    Text(
                      DateFormat('EEEE, dd MMMM yyyy').format(now),
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey.shade700,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              // Dashboard Metrics: Pending Orders & Procurement Needed
              FutureBuilder<({int pendingCount, int oldPendingCount, int toProcureCount})>(
                future: widget.orderRepository.getPendingAndProcurementStats(),
                builder: (context, snapshot) {
                  final stats = snapshot.data;
                  final pendingCount = stats?.pendingCount ?? 0;
                  final oldPendingCount = stats?.oldPendingCount ?? 0;
                  final toProcureCount = stats?.toProcureCount ?? 0;

                  return Row(
                    children: [
                      // Pending Orders Card
                      Expanded(
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(16),
                            onTap: () async {
                              await Navigator.push(
                                context,
                                MaterialPageRoute<void>(
                                  builder: (_) => HistoryScreen(
                                    customerRepository:
                                        widget.customerRepository,
                                    orderRepository: widget.orderRepository,
                                    productRepository: widget.productRepository,
                                    backupService: widget.backupService,
                                    initialFilter: HistoryFilter.pending,
                                  ),
                                ),
                              );
                              setState(() {});
                            },
                            child: Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: pendingCount > 0
                                    ? const Color(0xFFFFF7ED)
                                    : const Color(0xFFF8FAFC),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: pendingCount > 0
                                      ? (oldPendingCount > 0
                                          ? Colors.red.shade400
                                          : const Color(0xFFFDBA74))
                                      : const Color(0xFFE2E8F0),
                                  width: oldPendingCount > 0 ? 1.5 : 1,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.02),
                                    blurRadius: 6,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.all(6),
                                        decoration: BoxDecoration(
                                          color: pendingCount > 0
                                              ? const Color(0xFFFFEDD5)
                                              : Colors.grey.shade200,
                                          borderRadius:
                                              BorderRadius.circular(8),
                                        ),
                                        child: Icon(
                                          Icons.pending_actions_rounded,
                                          size: 18,
                                          color: pendingCount > 0
                                              ? const Color(0xFFC2410C)
                                              : Colors.grey.shade600,
                                        ),
                                      ),
                                      if (oldPendingCount > 0)
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 6, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: Colors.red.shade100,
                                            borderRadius:
                                                BorderRadius.circular(6),
                                          ),
                                          child: Text(
                                            '>3 days ⚠️',
                                            style: TextStyle(
                                              fontSize: 9,
                                              fontWeight: FontWeight.bold,
                                              color: Colors.red.shade900,
                                            ),
                                          ),
                                        )
                                      else
                                        Icon(Icons.arrow_forward_ios_rounded,
                                            size: 12,
                                            color: Colors.grey.shade400),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    '$pendingCount Pending',
                                    style: TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.bold,
                                      color: pendingCount > 0
                                          ? const Color(0xFF9A3412)
                                          : const Color(0xFF334155),
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    oldPendingCount > 0
                                        ? '$oldPendingCount need immediate close'
                                        : (pendingCount == 0
                                            ? 'All orders closed'
                                            : 'Unclosed bills'),
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: oldPendingCount > 0
                                          ? Colors.red.shade800
                                          : Colors.grey.shade600,
                                      fontWeight: oldPendingCount > 0
                                          ? FontWeight.w700
                                          : FontWeight.normal,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),

                      // Procurement Card
                      Expanded(
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(16),
                            onTap: () async {
                              await Navigator.push(
                                context,
                                MaterialPageRoute<void>(
                                  builder: (_) => ProcurementScreen(
                                    orderRepository: widget.orderRepository,
                                    customerRepository:
                                        widget.customerRepository,
                                    productRepository: widget.productRepository,
                                  ),
                                ),
                              );
                              setState(() {});
                            },
                            child: Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: toProcureCount > 0
                                    ? const Color(0xFFFFF1F2)
                                    : const Color(0xFFF8FAFC),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: toProcureCount > 0
                                      ? const Color(0xFFFDA4AF)
                                      : const Color(0xFFE2E8F0),
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.02),
                                    blurRadius: 6,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.all(6),
                                        decoration: BoxDecoration(
                                          color: toProcureCount > 0
                                              ? const Color(0xFFFFE4E6)
                                              : Colors.grey.shade200,
                                          borderRadius:
                                              BorderRadius.circular(8),
                                        ),
                                        child: Icon(
                                          Icons.inventory_2_outlined,
                                          size: 18,
                                          color: toProcureCount > 0
                                              ? const Color(0xFFBE123C)
                                              : Colors.grey.shade600,
                                        ),
                                      ),
                                      Icon(Icons.arrow_forward_ios_rounded,
                                          size: 12,
                                          color: Colors.grey.shade400),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    '$toProcureCount to Procure',
                                    style: TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.bold,
                                      color: toProcureCount > 0
                                          ? const Color(0xFF9F1239)
                                          : const Color(0xFF334155),
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    toProcureCount == 0
                                        ? 'All items in stock'
                                        : 'Items not given',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: Colors.grey.shade600,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 16),

              // Hero Cards: Create Order (Full-Width in Retail, Side-by-Side with Khata in Wholesale)
              if (isOffline) ...[
                // Retail Mode: Full Width Fast Counter Hero Card
                Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFFD97706), Color(0xFFF59E0B)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFFD97706).withValues(alpha: 0.25),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(20),
                      onTap: () async {
                        await Navigator.push(
                          context,
                          MaterialPageRoute<void>(
                            builder: (_) => CustomerScreen(
                              customerRepository: widget.customerRepository,
                              productRepository: widget.productRepository,
                              orderRepository: widget.orderRepository,
                            ),
                          ),
                        );
                        setState(() {});
                      },
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withValues(alpha: 0.25),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: const Icon(
                                    Icons.point_of_sale_rounded,
                                    color: Colors.white,
                                    size: 26,
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 10, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withValues(alpha: 0.25),
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: const Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        'Instant Checkout',
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 11,
                                        ),
                                      ),
                                      SizedBox(width: 4),
                                      Icon(Icons.arrow_forward_ios,
                                          size: 10, color: Colors.white),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            const Text(
                              'FAST COUNTER BILLING',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 20,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 0.5,
                              ),
                            ),
                            const SizedBox(height: 4),
                            const Text(
                              'Quick walk-in retail sales • Cash & Dynamic UPI QR',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ] else ...[
                // Wholesale Mode: Side-by-Side Create Order & Khata Book
                Row(
                  children: [
                    Expanded(
                      child: Container(
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFF0F766E), Color(0xFF14B8A6)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(18),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFF0F766E).withValues(alpha: 0.25),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(18),
                            onTap: () async {
                              await Navigator.push(
                                context,
                                MaterialPageRoute<void>(
                                  builder: (_) => CustomerScreen(
                                    customerRepository: widget.customerRepository,
                                    productRepository: widget.productRepository,
                                    orderRepository: widget.orderRepository,
                                  ),
                                ),
                              );
                              setState(() {});
                            },
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 14, vertical: 16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.all(8),
                                        decoration: BoxDecoration(
                                          color: Colors.white
                                              .withValues(alpha: 0.2),
                                          borderRadius: BorderRadius.circular(10),
                                        ),
                                        child: const Icon(
                                          Icons.add_shopping_cart,
                                          color: Colors.white,
                                          size: 22,
                                        ),
                                      ),
                                      const Icon(Icons.arrow_forward_ios,
                                          size: 11, color: Colors.white70),
                                    ],
                                  ),
                                  const SizedBox(height: 12),
                                  Text(
                                    s.t('createOrder'),
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 16,
                                      fontWeight: FontWeight.w900,
                                      letterSpacing: 0.3,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    'Wholesale Bill / Cart',
                                    style: TextStyle(
                                      color: Colors.teal.shade50,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Container(
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFF312E81), Color(0xFF4F46E5)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(18),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFF4F46E5).withValues(alpha: 0.25),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(18),
                            onTap: () async {
                              await Navigator.push(
                                context,
                                MaterialPageRoute<void>(
                                  builder: (_) => KhataBookScreen(
                                    customerRepository: widget.customerRepository,
                                    orderRepository: widget.orderRepository,
                                    productRepository: widget.productRepository,
                                  ),
                                ),
                              );
                              setState(() {});
                            },
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 14, vertical: 16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.all(8),
                                        decoration: BoxDecoration(
                                          color: Colors.white
                                              .withValues(alpha: 0.2),
                                          borderRadius: BorderRadius.circular(10),
                                        ),
                                        child: const Icon(
                                          Icons.menu_book_rounded,
                                          color: Colors.white,
                                          size: 22,
                                        ),
                                      ),
                                      const Icon(Icons.arrow_forward_ios,
                                          size: 11, color: Colors.white70),
                                    ],
                                  ),
                                  const SizedBox(height: 12),
                                  const Text(
                                    'KHATA BOOK',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 16,
                                      fontWeight: FontWeight.w900,
                                      letterSpacing: 0.3,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    'Contractor Ledgers',
                                    style: TextStyle(
                                      color: Colors.indigo.shade50,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 16),

              // Secondary Quick Action Row
              Row(
                children: [
                  Expanded(
                    child: Card(
                      child: InkWell(
                        borderRadius: BorderRadius.circular(16),
                        onTap: () async {
                          await Navigator.push(
                            context,
                            MaterialPageRoute<void>(
                              builder: (_) => HistoryScreen(
                                orderRepository: widget.orderRepository,
                                backupService: widget.backupService,
                                customerRepository: widget.customerRepository,
                                productRepository: widget.productRepository,
                              ),
                            ),
                          );
                          setState(() {});
                        },
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: Colors.indigo.shade50,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Icon(Icons.history,
                                    color: Colors.indigo.shade700, size: 22),
                              ),
                              const SizedBox(height: 12),
                              Text(
                                s.t('history'),
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 14,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'View past bills',
                                style: TextStyle(
                                    color: Colors.grey.shade600, fontSize: 11),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Card(
                      child: InkWell(
                        borderRadius: BorderRadius.circular(16),
                        onTap: () async {
                          await Navigator.push(
                            context,
                            MaterialPageRoute<void>(
                              builder: (_) => SimpleProductAdminScreen(
                                productRepository: widget.productRepository,
                              ),
                            ),
                          );
                          setState(() {});
                        },
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      color: Colors.amber.shade50,
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: Icon(Icons.inventory_2_outlined,
                                        color: Colors.amber.shade900, size: 22),
                                  ),
                                  FutureBuilder<int>(
                                    future: widget.productRepository
                                        .getNeedsReviewCount(),
                                    builder: (context, snap) {
                                      final count = snap.data ?? 0;
                                      if (count <= 0) {
                                        return const SizedBox.shrink();
                                      }
                                      return Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 7, vertical: 3),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFFFEF3C7),
                                          borderRadius:
                                              BorderRadius.circular(12),
                                          border: Border.all(
                                              color: const Color(0xFFF59E0B)),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            const Icon(Icons.warning_amber_rounded,
                                                size: 12,
                                                color: Color(0xFFB45309)),
                                            const SizedBox(width: 3),
                                            Text(
                                              '$count to review',
                                              style: const TextStyle(
                                                fontSize: 10,
                                                fontWeight: FontWeight.bold,
                                                color: Color(0xFF92400E),
                                              ),
                                            ),
                                          ],
                                        ),
                                      );
                                    },
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              Text(
                                s.t('manageProducts'),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 14,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'Items & rates',
                                style: TextStyle(
                                    color: Colors.grey.shade600, fontSize: 11),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // Recent Orders Header
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 4,
                        height: 16,
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primary,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'RECENT ORDERS',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          color: Colors.grey.shade800,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ),
                  TextButton(
                    onPressed: () async {
                      await Navigator.push(
                        context,
                        MaterialPageRoute<void>(
                          builder: (_) => HistoryScreen(
                            orderRepository: widget.orderRepository,
                            backupService: widget.backupService,
                            customerRepository: widget.customerRepository,
                            productRepository: widget.productRepository,
                          ),
                        ),
                      );
                      setState(() {});
                    },
                    child: const Text('View All',
                        style: TextStyle(fontWeight: FontWeight.w700)),
                  ),
                ],
              ),
              const SizedBox(height: 8),

              // Orders List
              FutureBuilder<List<OrderSummary>>(
                future: widget.orderRepository.searchOrderSummaries(''),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(
                      child: Padding(
                        padding: EdgeInsets.all(24),
                        child: CircularProgressIndicator(),
                      ),
                    );
                  }
                  final orders =
                      snapshot.data?.take(5).toList() ?? <OrderSummary>[];
                  if (orders.isEmpty) {
                    return Card(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 32),
                        child: Center(
                          child: Column(
                            children: [
                              Icon(Icons.receipt_outlined,
                                  size: 40, color: Colors.grey.shade400),
                              const SizedBox(height: 10),
                              Text(
                                'No recent orders yet',
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 15,
                                  color: Colors.grey.shade700,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Tap "CREATE ORDER" above to make your first bill',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey.shade500,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  }

                  return Column(
                    children: orders.map((order) {
                      final displayTakenBy = (order.takenBy != null &&
                              order.takenBy!.trim().isNotEmpty &&
                              order.takenBy!.trim() != 'Store')
                          ? order.takenBy!.trim()
                          : ShopSyncService.instance.currentUserOrDeviceName;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Card(
                          child: InkWell(
                            borderRadius: BorderRadius.circular(16),
                            onTap: () async {
                              await Navigator.push(
                                context,
                                MaterialPageRoute<void>(
                                  builder: (_) => OrderDetailsScreen(
                                    orderId: order.orderId,
                                    orderRepository: widget.orderRepository,
                                    customerRepository:
                                        widget.customerRepository,
                                    productRepository:
                                        widget.productRepository,
                                  ),
                                ),
                              );
                              setState(() {});
                            },
                            child: Padding(
                              padding: const EdgeInsets.all(14),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 8, vertical: 3),
                                        decoration: BoxDecoration(
                                          color: theme
                                              .colorScheme.primaryContainer
                                              .withValues(alpha: 0.5),
                                          borderRadius:
                                              BorderRadius.circular(6),
                                        ),
                                        child: Text(
                                          order.formattedOrderId,
                                          style: TextStyle(
                                            fontWeight: FontWeight.w800,
                                            fontSize: 12,
                                            color: theme.colorScheme.primary,
                                          ),
                                        ),
                                      ),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 8, vertical: 3),
                                        decoration: BoxDecoration(
                                          color: _statusBgColor(order.status),
                                          borderRadius:
                                              BorderRadius.circular(12),
                                          border: Border.all(
                                            color: _statusColor(order.status)
                                                .withValues(alpha: 0.4),
                                          ),
                                        ),
                                        child: Text(
                                          orderStatusLabel(order.status),
                                          style: TextStyle(
                                            color: _statusColor(order.status),
                                            fontSize: 10,
                                            fontWeight: FontWeight.w800,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 10),
                                  Text(
                                    order.customerName,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 15,
                                    ),
                                  ),
                                  if (!ShopCustomizationService.instance.isPureOfflineMode) ...[
                                    const SizedBox(height: 3),
                                    Row(
                                      children: [
                                        Icon(Icons.person_pin_circle_outlined,
                                            size: 13,
                                            color: Colors.teal.shade700),
                                        const SizedBox(width: 4),
                                        Text(
                                          'Taken by: $displayTakenBy',
                                          style: TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w600,
                                            color: Colors.teal.shade800,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                  const SizedBox(height: 6),
                                  Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        '${order.totalItems} items • ${DateFormat('dd MMM, hh:mm a').format(order.createdAt)}',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.grey.shade600,
                                        ),
                                      ),
                                      if (order.estimateTotal > 0)
                                        Text(
                                          ShopSyncService.instance.canViewBillTotals
                                              ? '₹ ${order.estimateTotal.toStringAsFixed(2)}'
                                              : '₹ ••••',
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w900,
                                            fontSize: 14,
                                            color: Color(0xFF0F766E),
                                          ),
                                        ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPriceCautionBanner() {
    if (_priceCautionBannerDismissed) return const SizedBox.shrink();

    return FutureBuilder<({bool enabled, int days, int count})>(
      future: () async {
        final enabled =
            await AppNotificationService.instance.isPriceCautionEnabled();
        if (!enabled) return (enabled: false, days: 30, count: 0);
        final days =
            await AppNotificationService.instance.getPriceCautionDays();
        final count = await widget.productRepository
            .getStalePriceCount(thresholdDays: days);
        return (enabled: true, days: days, count: count);
      }(),
      builder: (context, snapshot) {
        final data = snapshot.data;
        if (data == null || !data.enabled || data.count <= 0) {
          return const SizedBox.shrink();
        }

        return Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: const Color(0xFFFFFBEB),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFFCD34D)),
            boxShadow: [
              BoxShadow(
                color: Colors.amber.withValues(alpha: 0.08),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: const Color(0xFFF59E0B),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.price_change_outlined,
                    color: Colors.white, size: 18),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: InkWell(
                  onTap: () async {
                    await Navigator.push(
                      context,
                      MaterialPageRoute<void>(
                        builder: (_) => SimpleProductAdminScreen(
                          productRepository: widget.productRepository,
                          initialOnlyStalePrices: true,
                          staleThresholdDays: data.days,
                        ),
                      ),
                    );
                    setState(() {});
                  },
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              '${data.count} Rates Not Updated',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                                color: Color(0xFF92400E),
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 5, vertical: 1),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFDE68A),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              '>${data.days} days',
                              style: const TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF78350F),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      const Text(
                        'Market prices may have changed. Tap to review items.',
                        style: TextStyle(
                          fontSize: 10,
                          color: Color(0xFFB45309),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 4),
              IconButton(
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                icon:
                    const Icon(Icons.close, size: 16, color: Color(0xFF92400E)),
                tooltip: 'Dismiss alert',
                onPressed: () {
                  setState(() => _priceCautionBannerDismissed = true);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildTopSellingExpandableBar(ThemeData theme) {
    return FutureBuilder<List<TopProductStat>>(
      future: DatabaseHelper.instance.getTopSellingProducts(limit: 3),
      builder: (context, snapshot) {
        final list = snapshot.data ?? [];
        if (list.isEmpty) return const SizedBox.shrink();

        final top1 = list.first;

        return Card(
          elevation: 1,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(color: Colors.amber.shade200, width: 1),
          ),
          color: const Color(0xFFFFFBEB),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () {
              setState(() => _isTopSellingExpanded = !_isTopSellingExpanded);
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(5),
                        decoration: BoxDecoration(
                          color: Colors.amber.shade100,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(Icons.local_fire_department_rounded,
                            size: 16, color: Colors.amber.shade900),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _isTopSellingExpanded
                              ? 'TOP SELLING PRODUCTS (FAST MOVERS)'
                              : '🔥 #1 Best Seller: ${top1.itemName} (${top1.totalQuantity % 1 == 0 ? top1.totalQuantity.toInt() : top1.totalQuantity.toStringAsFixed(1)} sold)',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            color: Colors.amber.shade900,
                            letterSpacing: 0.3,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Icon(
                        _isTopSellingExpanded
                            ? Icons.keyboard_arrow_up_rounded
                            : Icons.keyboard_arrow_down_rounded,
                        color: Colors.amber.shade900,
                        size: 20,
                      ),
                    ],
                  ),
                  if (_isTopSellingExpanded) ...[
                    const Divider(height: 16, color: Color(0xFFFDE68A)),
                    ...list.map((item) {
                      final idx = list.indexOf(item);
                      final badge = idx == 0 ? '🥇' : (idx == 1 ? '🥈' : '🥉');
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          children: [
                            Text(badge, style: const TextStyle(fontSize: 15)),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                item.itemName,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                  color: Color(0xFF1E293B),
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            Text(
                              '${item.totalQuantity % 1 == 0 ? item.totalQuantity.toInt() : item.totalQuantity.toStringAsFixed(1)} ${item.unit}',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                                color: Color(0xFF0F766E),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Text(
                              '₹ ${item.totalRevenue.toStringAsFixed(0)}',
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 12,
                                color: Colors.grey.shade800,
                              ),
                            ),
                          ],
                        ),
                      );
                    }),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton.icon(
                          style: TextButton.styleFrom(
                            visualDensity: VisualDensity.compact,
                            foregroundColor: const Color(0xFF0F766E),
                          ),
                          icon: const Icon(Icons.analytics_outlined, size: 15),
                          label: const Text(
                            'View Full Analytics & Revenue →',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute<void>(
                                builder: (_) => const TopSellingScreen(),
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildSideDrawer(BuildContext context, ThemeData theme, AppLocalizations s) {
    final shopName = ShopCustomizationService.instance.shopName;
    final isOffline = ShopCustomizationService.instance.isPureOfflineMode ||
        const bool.fromEnvironment('STANDALONE_LOCAL', defaultValue: false);
    final sync = ShopSyncService.instance;

    return Drawer(
      child: SafeArea(
        child: Column(
          children: [
            // Drawer Header
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFF0F766E), Color(0xFF14B8A6)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const CircleAvatar(
                    radius: 26,
                    backgroundColor: Colors.white,
                    child: Icon(Icons.storefront_rounded,
                        color: Color(0xFF0F766E), size: 30),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    shopName,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      isOffline
                          ? 'Pure Local Offline'
                          : (sync.hasShop
                              ? '${sync.currentShop?.shopCode ?? ''} • ${sync.currentUserOrDeviceName}'
                              : 'Cloud Sync Ready'),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(vertical: 8),
                children: [
                  // Top Selling Section (Expandable)
                  Theme(
                    data: theme.copyWith(dividerColor: Colors.transparent),
                    child: ExpansionTile(
                      initiallyExpanded: true,
                      leading: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.amber.shade50,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(Icons.local_fire_department_rounded,
                            color: Colors.amber.shade800, size: 22),
                      ),
                      title: const Text(
                        'Top Selling Products',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                      ),
                      subtitle: const Text(
                        'Fast moving items & revenue',
                        style: TextStyle(fontSize: 11, color: Colors.grey),
                      ),
                      children: [
                        FutureBuilder<List<TopProductStat>>(
                          future: DatabaseHelper.instance.getTopSellingProducts(limit: 5),
                          builder: (context, snapshot) {
                            if (snapshot.connectionState == ConnectionState.waiting) {
                              return const Padding(
                                padding: EdgeInsets.all(12),
                                child: Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))),
                              );
                            }
                            final list = snapshot.data ?? [];
                            if (list.isEmpty) {
                              return Padding(
                                padding: const EdgeInsets.all(12),
                                child: Text('No sales records yet.', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                              );
                            }
                            return Column(
                              children: [
                                ...list.take(3).map((item) {
                                  final idx = list.indexOf(item);
                                  final badge = idx == 0 ? '🥇' : (idx == 1 ? '🥈' : '🥉');
                                  return ListTile(
                                    dense: true,
                                    leading: Text(badge, style: const TextStyle(fontSize: 16)),
                                    title: Text(item.itemName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13), maxLines: 1, overflow: TextOverflow.ellipsis),
                                    subtitle: Text('${item.totalQuantity % 1 == 0 ? item.totalQuantity.toInt() : item.totalQuantity.toStringAsFixed(1)} ${item.unit} sold', style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                                    trailing: Text('₹ ${item.totalRevenue.toStringAsFixed(0)}', style: const TextStyle(fontWeight: FontWeight.w700, color: Color(0xFF0F766E), fontSize: 12)),
                                  );
                                }),
                                Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                                  child: SizedBox(
                                    width: double.infinity,
                                    child: OutlinedButton.icon(
                                      style: OutlinedButton.styleFrom(
                                        visualDensity: VisualDensity.compact,
                                        side: const BorderSide(color: Color(0xFF0F766E)),
                                      ),
                                      icon: const Icon(Icons.analytics_outlined, size: 16, color: Color(0xFF0F766E)),
                                      label: const Text('View Full Analytics', style: TextStyle(color: Color(0xFF0F766E), fontSize: 12)),
                                      onPressed: () {
                                        Navigator.pop(context);
                                        Navigator.push(context, MaterialPageRoute<void>(builder: (_) => const TopSellingScreen()));
                                      },
                                    ),
                                  ),
                                ),
                              ],
                            );
                          },
                        ),
                      ],
                    ),
                  ),

                  const Divider(),

                  // Quick Features List
                  ListTile(
                    leading: const Icon(Icons.sell_outlined,
                        color: Color(0xFF0F766E)),
                    title: const Text('Quick Price List',
                        style: TextStyle(
                            fontWeight: FontWeight.w600, fontSize: 14)),
                    subtitle: const Text(
                        'Check item prices without starting order',
                        style: TextStyle(fontSize: 11, color: Colors.grey)),
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.push(
                        context,
                        MaterialPageRoute<void>(
                          builder: (_) => PriceListScreen(
                            productRepository: widget.productRepository,
                          ),
                        ),
                      );
                    },
                  ),
                  if (!isOffline) ...[
                    ListTile(
                      leading: const Icon(Icons.menu_book_rounded,
                          color: Color(0xFF0F766E)),
                      title: const Text('Khata Book (Udhaar)',
                          style: TextStyle(
                              fontWeight: FontWeight.w600, fontSize: 14)),
                      subtitle: const Text(
                          'Customer balances & payment reminders',
                          style: TextStyle(fontSize: 11, color: Colors.grey)),
                      onTap: () {
                        Navigator.pop(context);
                        Navigator.push(
                          context,
                          MaterialPageRoute<void>(
                            builder: (_) => KhataBookScreen(
                              customerRepository: widget.customerRepository,
                              orderRepository: widget.orderRepository,
                              productRepository: widget.productRepository,
                            ),
                          ),
                        );
                      },
                    ),
                  ],
                  ListTile(
                    leading: const Icon(Icons.nightlight_round,
                        color: Color(0xFF0F766E)),
                    title: const Text('Evening Closing Report',
                        style: TextStyle(
                            fontWeight: FontWeight.w600, fontSize: 14)),
                    subtitle: const Text(
                        'Day-end business summary & WhatsApp',
                        style: TextStyle(fontSize: 11, color: Colors.grey)),
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.push(
                        context,
                        MaterialPageRoute<void>(
                          builder: (_) => const EveningReportScreen(),
                        ),
                      );
                    },
                  ),
                  const Divider(),
                  ListTile(
                    leading: const Icon(Icons.inventory_2_outlined,
                        color: Color(0xFF0F766E)),
                    title: const Text('Manage Products Catalog', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.push(context, MaterialPageRoute<void>(builder: (_) => SimpleProductAdminScreen(productRepository: widget.productRepository)));
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.receipt_long_outlined, color: Color(0xFF0F766E)),
                    title: const Text('Order History & Bills', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.push(context, MaterialPageRoute<void>(builder: (_) => HistoryScreen(customerRepository: widget.customerRepository, orderRepository: widget.orderRepository, productRepository: widget.productRepository, backupService: widget.backupService)));
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.settings_outlined, color: Color(0xFF0F766E)),
                    title: const Text('Shop Settings & Shortcuts', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.push(context, MaterialPageRoute<void>(builder: (_) => ShopSettingsScreen(productRepository: widget.productRepository, locale: widget.locale, onLocaleChanged: widget.onLocaleChanged)));
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.menu_book_rounded, color: Color(0xFF0F766E)),
                    title: const Text('App Documentation & Manual', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                    subtitle: const Text('Pin-to-pin guide for all app features', style: TextStyle(fontSize: 11, color: Colors.grey)),
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.push(context, MaterialPageRoute<void>(builder: (_) => const AppDocumentationScreen()));
                    },
                  ),
                  if (!isOffline) ...[
                    ListTile(
                      leading: const Icon(Icons.cloud_sync_outlined, color: Color(0xFF0F766E)),
                      title: const Text('Shop Cloud Sync & Staff', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                      onTap: () {
                        Navigator.pop(context);
                        Navigator.push(context, MaterialPageRoute<void>(builder: (_) => const ShopSyncScreen()));
                      },
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
