import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shop/database/database_helper.dart';
import 'package:shop/l10n/app_localizations.dart';
import 'package:shop/repositories/product_repository.dart';
import 'package:shop/screens/app_documentation_screen.dart';
import 'package:shop/screens/quantity_shortcuts_screen.dart';
import 'package:shop/screens/shop_sync_screen.dart';
import 'package:shop/screens/simple_product_admin_screen.dart';
import 'package:shop/services/app_notification_service.dart';
import 'package:shop/services/shop_customization_service.dart';
import 'package:shop/services/shop_sync_service.dart';

class ShopSettingsScreen extends StatefulWidget {
  const ShopSettingsScreen({
    super.key,
    required this.productRepository,
    required this.locale,
    required this.onLocaleChanged,
  });

  final ProductRepository productRepository;
  final Locale locale;
  final ValueChanged<Locale> onLocaleChanged;

  @override
  State<ShopSettingsScreen> createState() => _ShopSettingsScreenState();
}

class _ShopSettingsScreenState extends State<ShopSettingsScreen> {
  final _customService = ShopCustomizationService.instance;
  bool _remindersEnabled = true;

  // Category specific notification settings
  bool _pendingOrdersEnabled = true;
  String _pendingMode = 'scheduled';
  List<TimeOfDay> _pendingTimes = [
    const TimeOfDay(hour: 10, minute: 0),
    const TimeOfDay(hour: 14, minute: 0),
    const TimeOfDay(hour: 19, minute: 0),
  ];

  bool _procurementEnabled = true;
  List<TimeOfDay> _procurementTimes = [
    const TimeOfDay(hour: 9, minute: 30),
    const TimeOfDay(hour: 17, minute: 30),
  ];

  bool _dailyReportEnabled = true;
  TimeOfDay _dailyReportTime = const TimeOfDay(hour: 21, minute: 0);

  int _priceCautionDays = 30;
  bool _priceCautionEnabled = true;

  @override
  void initState() {
    super.initState();
    _customService.addListener(_onServiceUpdate);
    _loadNotificationPref();
  }

  Future<void> _loadNotificationPref() async {
    final enabled = await AppNotificationService.instance.isEnabled();
    final pendingOn = await AppNotificationService.instance.isPendingOrdersEnabled();
    final pendingMode = await AppNotificationService.instance.getPendingOrdersMode();
    final pendingTimes = await AppNotificationService.instance.getPendingOrdersTimes();
    final procureOn = await AppNotificationService.instance.isProcurementEnabled();
    final procureTimes = await AppNotificationService.instance.getProcurementTimes();
    final dailyOn = await AppNotificationService.instance.isDailyReportEnabled();
    final dailyTime = await AppNotificationService.instance.getDailyReportTime();
    final cautionDays = await AppNotificationService.instance.getPriceCautionDays();
    final cautionEnabled = await AppNotificationService.instance.isPriceCautionEnabled();

    if (mounted) {
      setState(() {
        _remindersEnabled = enabled;
        _pendingOrdersEnabled = pendingOn;
        _pendingMode = pendingMode;
        _pendingTimes = pendingTimes;
        _procurementEnabled = procureOn;
        _procurementTimes = procureTimes;
        _dailyReportEnabled = dailyOn;
        _dailyReportTime = dailyTime;
        _priceCautionDays = cautionDays;
        _priceCautionEnabled = cautionEnabled;
      });
    }
  }

  Future<void> _pickTime({
    required TimeOfDay current,
    required ValueChanged<TimeOfDay> onSaved,
  }) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: current,
    );
    if (!mounted) return;
    if (picked != null) {
      onSaved(picked);
      setState(() {});
    }
  }

  void _syncNotificationSchedule() {
    if (ShopSyncService.instance.isConnected) {
      unawaited(ShopSyncService.instance.syncNotificationSettingsToCloud());
    }
  }

  Future<void> _addPendingTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: const TimeOfDay(hour: 12, minute: 0),
    );
    if (!mounted) return;
    if (picked != null) {
      _pendingTimes.add(picked);
      _pendingTimes.sort((a, b) => (a.hour * 60 + a.minute).compareTo(b.hour * 60 + b.minute));
      await AppNotificationService.instance.setPendingOrdersTimes(_pendingTimes);
      _syncNotificationSchedule();
      if (!mounted) return;
      setState(() {});
    }
  }

  Future<void> _removePendingTime(int index) async {
    if (index >= 0 && index < _pendingTimes.length) {
      _pendingTimes.removeAt(index);
      await AppNotificationService.instance.setPendingOrdersTimes(_pendingTimes);
      _syncNotificationSchedule();
      if (!mounted) return;
      setState(() {});
    }
  }

  Future<void> _addProcureTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: const TimeOfDay(hour: 16, minute: 0),
    );
    if (!mounted) return;
    if (picked != null) {
      _procurementTimes.add(picked);
      _procurementTimes.sort((a, b) => (a.hour * 60 + a.minute).compareTo(b.hour * 60 + b.minute));
      await AppNotificationService.instance.setProcurementTimes(_procurementTimes);
      _syncNotificationSchedule();
      if (!mounted) return;
      setState(() {});
    }
  }

  Future<void> _removeProcureTime(int index) async {
    if (index >= 0 && index < _procurementTimes.length) {
      _procurementTimes.removeAt(index);
      await AppNotificationService.instance.setProcurementTimes(_procurementTimes);
      _syncNotificationSchedule();
      if (!mounted) return;
      setState(() {});
    }
  }

  @override
  void dispose() {
    _customService.removeListener(_onServiceUpdate);
    super.dispose();
  }

  void _onServiceUpdate() {
    if (mounted) setState(() {});
  }

  String _formatTimeOfDay(TimeOfDay time) {
    final now = DateTime.now();
    final dt = DateTime(now.year, now.month, now.day, time.hour, time.minute);
    return DateFormat('hh:mm a').format(dt);
  }

  Future<void> _editShopNameDialog() async {
    final controller = TextEditingController(text: _customService.shopName);
    try {
      final saved = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Change Shop Name',
              style: TextStyle(fontWeight: FontWeight.bold)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'This shop name will appear on the top bar, WhatsApp shares, and printed/image receipts.',
                style: TextStyle(fontSize: 13, color: Colors.grey),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                decoration: const InputDecoration(
                  labelText: 'Shop Name',
                  hintText: 'e.g. Sri Sai Hardware, YKR Traders',
                  border: OutlineInputBorder(),
                ),
                autofocus: true,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('CANCEL'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF0F766E),
              ),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('SAVE'),
            ),
          ],
        ),
      );

      final text = controller.text.trim();
      if (saved == true && text.isNotEmpty) {
        await _customService.setShopName(text);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Shop name updated to "$text"!'),
              backgroundColor: const Color(0xFF0F766E),
            ),
          );
        }
      }
    } finally {
      controller.dispose();
    }
  }

  Future<void> _editFieldDialog({
    required String title,
    required String label,
    required String initialValue,
    required Future<void> Function(String) onSave,
    String? hint,
    TextInputType? keyboardType,
  }) async {
    final controller = TextEditingController(text: initialValue);
    try {
      final saved = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
          content: TextField(
            controller: controller,
            keyboardType: keyboardType,
            decoration: InputDecoration(
              labelText: label,
              hintText: hint,
              border: const OutlineInputBorder(),
            ),
            autofocus: true,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('CANCEL'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF0F766E),
              ),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('SAVE'),
            ),
          ],
        ),
      );

      final text = controller.text.trim();
      if (saved == true) {
        await onSave(text);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('$title updated!'),
              backgroundColor: const Color(0xFF0F766E),
            ),
          );
        }
      }
    } finally {
      controller.dispose();
    }
  }

  Future<void> _clearOrderHistoryDialog() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear All Order History?'),
        content: const Text(
          'This will permanently delete all past orders and billing receipts.\n\nYour Products Catalog and Customer List will remain safe.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('CANCEL'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('CLEAR ORDERS'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      await DatabaseHelper.instance.clearOrderHistory();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('All past order history cleared successfully.'),
          backgroundColor: Colors.teal,
        ),
      );
    }
  }

  Future<void> _clearProductsCatalogDialog() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear Products Catalog?'),
        content: const Text(
          'This will permanently delete all products and items from your catalog.\n\nYour Past Orders and Customer List will remain safe.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('CANCEL'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('CLEAR PRODUCTS'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      await DatabaseHelper.instance.clearProductsCatalog();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Products catalog cleared.'),
          backgroundColor: Colors.teal,
        ),
      );
    }
  }

  Future<void> _resetAllShopDataDialog() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reset All Shop Data?'),
        content: const Text(
          'CAUTION: This will delete ALL orders, ALL products, and ALL customers.\n\nThe app will reset to its initial clean state.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('CANCEL'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade900),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('RESET EVERYTHING'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      await DatabaseHelper.instance.resetAllShopData();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('All shop data has been reset.'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final globalShortcuts = _customService.globalShortcuts;
    final shortcutLabels = globalShortcuts
        .map((c) => '+${c % 1 == 0 ? c.toInt() : c}')
        .join('  ');

    return Scaffold(
      appBar: AppBar(title: Text(s.t('shopSettings'))),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        children: <Widget>[
          // Shop Name & Branding
          Text(
            'SHOP BRANDING & IDENTITY',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: Colors.grey.shade700,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 8),
          Card(
            child: ListTile(
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              leading: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFF0F766E).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.storefront_rounded,
                    color: Color(0xFF0F766E), size: 24),
              ),
              title: Text(
                _customService.shopName,
                style:
                    const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              subtitle: const Text(
                'Shown in header, receipts, and order estimates',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
              trailing: FilledButton.tonal(
                style: FilledButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                ),
                onPressed: _editShopNameDialog,
                child: const Text('Change'),
              ),
            ),
          ),
          const SizedBox(height: 20),

          // Invoice, UPI & Digital Stamp
          Text(
            'INVOICE, UPI & DIGITAL STAMP',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: Colors.grey.shade700,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 8),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.phone_outlined,
                      color: Color(0xFF0F766E)),
                  title: const Text('Shop Phone Number',
                      style:
                          TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                  subtitle: Text(
                    _customService.shopPhone.isNotEmpty
                        ? _customService.shopPhone
                        : 'Not set (tap to add)',
                    style: TextStyle(
                        fontSize: 12,
                        color: _customService.shopPhone.isNotEmpty
                            ? Colors.black87
                            : Colors.grey),
                  ),
                  trailing: const Icon(Icons.chevron_right, color: Colors.grey),
                  onTap: () => _editFieldDialog(
                    title: 'Shop Phone Number',
                    label: 'Phone / WhatsApp',
                    hint: 'e.g. 9392449356',
                    initialValue: _customService.shopPhone,
                    keyboardType: TextInputType.phone,
                    onSave: _customService.setShopPhone,
                  ),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.location_on_outlined,
                      color: Color(0xFF0F766E)),
                  title: const Text('Shop Address',
                      style:
                          TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                  subtitle: Text(
                    _customService.shopAddress.isNotEmpty
                        ? _customService.shopAddress
                        : 'Not set (tap to add)',
                    style: TextStyle(
                        fontSize: 12,
                        color: _customService.shopAddress.isNotEmpty
                            ? Colors.black87
                            : Colors.grey),
                  ),
                  trailing: const Icon(Icons.chevron_right, color: Colors.grey),
                  onTap: () => _editFieldDialog(
                    title: 'Shop Address',
                    label: 'Address Line',
                    hint: 'e.g. Main Bazaar, Beside Old Bus Stand',
                    initialValue: _customService.shopAddress,
                    onSave: _customService.setShopAddress,
                  ),
                ),
                const Divider(height: 1),
                ListTile(
                  leading:
                      const Icon(Icons.qr_code_2, color: Color(0xFF0F766E)),
                  title: const Text('UPI ID (GPay / PhonePe / Paytm)',
                      style:
                          TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                  subtitle: Text(
                    _customService.upiId.isNotEmpty
                        ? _customService.upiId
                        : 'Not set (tap to add for dynamic QR codes)',
                    style: TextStyle(
                        fontSize: 12,
                        color: _customService.upiId.isNotEmpty
                            ? Colors.black87
                            : Colors.grey),
                  ),
                  trailing: const Icon(Icons.chevron_right, color: Colors.grey),
                  onTap: () {
                    if (!ShopSyncService.instance.isOwner) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Permission Denied: Only Shop Owner can edit UPI Payment settings.'),
                          backgroundColor: Colors.red,
                        ),
                      );
                      return;
                    }
                    _editFieldDialog(
                      title: 'UPI ID for Scan & Pay',
                      label: 'UPI ID (e.g. 9392449356@ybl)',
                      hint: 'merchant@oksbi or 9876543210@paytm',
                      initialValue: _customService.upiId,
                      onSave: _customService.setUpiId,
                    );
                  },
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.verified_outlined,
                      color: Color(0xFF0F766E)),
                  title: const Text('GSTIN (Tax ID - Optional)',
                      style:
                          TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                  subtitle: Text(
                    _customService.gstin.isNotEmpty
                        ? _customService.gstin
                        : 'Not set (tap to add)',
                    style: TextStyle(
                        fontSize: 12,
                        color: _customService.gstin.isNotEmpty
                            ? Colors.black87
                            : Colors.grey),
                  ),
                  trailing: const Icon(Icons.chevron_right, color: Colors.grey),
                  onTap: () => _editFieldDialog(
                    title: 'GSTIN Number',
                    label: '15-digit GSTIN',
                    hint: 'e.g. 36AAACG1234F1Z5',
                    initialValue: _customService.gstin,
                    onSave: _customService.setGstin,
                  ),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.approval_outlined,
                      color: Color(0xFF0F766E)),
                  title: const Text('Digital Stamp & Signatory',
                      style:
                          TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                  subtitle: Text(
                    _customService.digitalStamp.isNotEmpty
                        ? _customService.digitalStamp
                        : 'Default: Authorized Signatory / For ${_customService.shopName}',
                    style: const TextStyle(fontSize: 12, color: Colors.black87),
                  ),
                  trailing: const Icon(Icons.chevron_right, color: Colors.grey),
                  onTap: () => _editFieldDialog(
                    title: 'Digital Stamp Text',
                    label: 'Stamp / Signatory Line',
                    hint:
                        'e.g. Authorized Signatory / For ${_customService.shopName}',
                    initialValue: _customService.digitalStamp,
                    onSave: _customService.setDigitalStamp,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Quantity Step Shortcuts (+ chips)
          Text(
            'ORDERING SHORTCUTS',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: Colors.grey.shade700,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 8),
          Card(
            child: ListTile(
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              leading: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.amber.shade50,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(Icons.touch_app_rounded,
                    color: Colors.amber.shade900, size: 24),
              ),
              title: const Text(
                'Quantity Step Shortcuts (+ chips)',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              subtitle: Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  'Default: $shortcutLabels\nTap to configure for all or specific items',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                ),
              ),
              trailing: const Icon(Icons.chevron_right, color: Colors.grey),
              onTap: () {
                if (!ShopSyncService.instance.canChangeShortcuts) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                          'Permission Denied: Only Master Device can modify quantity shortcuts.'),
                      backgroundColor: Colors.red,
                    ),
                  );
                  return;
                }
                Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) => QuantityShortcutsScreen(
                      productRepository: widget.productRepository,
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 20),

          // Language Preferences
          Text(
            s.t('language').toUpperCase(),
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: Colors.grey.shade700,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.translate,
                          color: theme.colorScheme.primary, size: 20),
                      const SizedBox(width: 10),
                      const Text(
                        'Display Language',
                        style: TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 15),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: SegmentedButton<String>(
                      segments: const <ButtonSegment<String>>[
                        ButtonSegment<String>(
                          value: 'en',
                          label: Text('English',
                              style: TextStyle(fontWeight: FontWeight.w700)),
                          icon: Icon(Icons.language, size: 16),
                        ),
                        ButtonSegment<String>(
                          value: 'te',
                          label: Text('తెలుగు',
                              style: TextStyle(fontWeight: FontWeight.w700)),
                        ),
                      ],
                      selected: <String>{widget.locale.languageCode},
                      onSelectionChanged: (selection) =>
                          widget.onLocaleChanged(Locale(selection.first)),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),

          // Order & Procurement Reminders
          Text(
            'ORDER & PROCUREMENT NOTIFICATIONS',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: Colors.grey.shade700,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 8),
          Card(
            child: Column(
              children: [
                SwitchListTile(
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  secondary: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.teal.shade50,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(Icons.notifications_active_outlined,
                        color: Colors.teal.shade700),
                  ),
                  title: const Text(
                    'Shop Reminders & Notifications',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: const Text(
                    'Automated alerts for pending orders, procurement, and daily summaries.',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                  value: _remindersEnabled,
                  onChanged: (val) async {
                    await AppNotificationService.instance.setEnabled(val);
                    _syncNotificationSchedule();
                    if (!mounted) return;
                    setState(() => _remindersEnabled = val);
                  },
                ),
                if (_remindersEnabled) ...[
                  const Divider(height: 1),

                  // SECTION 1: PENDING ORDERS NOTIFICATIONS
                  Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.assignment_outlined,
                                size: 20, color: Colors.teal.shade800),
                            const SizedBox(width: 8),
                            const Expanded(
                              child: Text(
                                'Pending Orders Reminders',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF0F766E),
                                ),
                              ),
                            ),
                            Switch(
                              value: _pendingOrdersEnabled,
                              onChanged: (val) async {
                                await AppNotificationService.instance
                                    .setPendingOrdersEnabled(val);
                                _syncNotificationSchedule();
                                if (!mounted) return;
                                setState(() => _pendingOrdersEnabled = val);
                              },
                            ),
                          ],
                        ),
                        if (_pendingOrdersEnabled) ...[
                          const SizedBox(height: 6),
                          const Text(
                            'Reminder Frequency:',
                            style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: Colors.grey),
                          ),
                          const SizedBox(height: 6),
                          Wrap(
                            spacing: 8,
                            runSpacing: 6,
                            children: [
                              ChoiceChip(
                                label: const Text('Custom Times / Day'),
                                selected: _pendingMode == 'scheduled',
                                onSelected: (sel) async {
                                  if (sel) {
                                    await AppNotificationService.instance
                                        .setPendingOrdersMode('scheduled');
                                    _syncNotificationSchedule();
                                    if (!mounted) return;
                                    setState(() => _pendingMode = 'scheduled');
                                  }
                                },
                              ),
                              ChoiceChip(
                                label: const Text('Every 1 Hour'),
                                selected: _pendingMode == 'hourly',
                                onSelected: (sel) async {
                                  if (sel) {
                                    await AppNotificationService.instance
                                        .setPendingOrdersMode('hourly');
                                    _syncNotificationSchedule();
                                    if (!mounted) return;
                                    setState(() => _pendingMode = 'hourly');
                                  }
                                },
                              ),
                              ChoiceChip(
                                label: const Text('Every 2 Hours'),
                                selected: _pendingMode == 'two_hours',
                                onSelected: (sel) async {
                                  if (sel) {
                                    await AppNotificationService.instance
                                        .setPendingOrdersMode('two_hours');
                                    _syncNotificationSchedule();
                                    if (!mounted) return;
                                    setState(() => _pendingMode = 'two_hours');
                                  }
                                },
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          if (_pendingMode == 'scheduled') ...[
                            Text(
                              'Alert Times (${_pendingTimes.length} times set):',
                              style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.black87),
                            ),
                            const SizedBox(height: 6),
                            Wrap(
                              spacing: 8,
                              runSpacing: 6,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                for (int i = 0; i < _pendingTimes.length; i++)
                                  InputChip(
                                    avatar: const Icon(Icons.access_time,
                                        size: 16, color: Color(0xFF0F766E)),
                                    label: Text(
                                        _formatTimeOfDay(_pendingTimes[i])),
                                    onDeleted: () => _removePendingTime(i),
                                    deleteIconColor: Colors.red.shade400,
                                    onPressed: () => _pickTime(
                                      current: _pendingTimes[i],
                                      onSaved: (t) async {
                                        _pendingTimes[i] = t;
                                        _pendingTimes.sort((a, b) =>
                                            (a.hour * 60 + a.minute).compareTo(
                                                b.hour * 60 + b.minute));
                                        await AppNotificationService.instance
                                            .setPendingOrdersTimes(
                                                _pendingTimes);
                                        _syncNotificationSchedule();
                                        if (!mounted) return;
                                        setState(() {});
                                      },
                                    ),
                                  ),
                                ActionChip(
                                  avatar: const Icon(Icons.add_alarm,
                                      size: 16, color: Color(0xFF0F766E)),
                                  label: const Text('+ Add Time'),
                                  onPressed: _addPendingTime,
                                ),
                              ],
                            ),
                          ] else ...[
                            Text(
                              _pendingMode == 'hourly'
                                  ? '• Fires every 1 hour during shop hours (7:00 AM - 9:00 PM).'
                                  : '• Fires every 2 hours during shop hours (7:00 AM - 9:00 PM).',
                              style: TextStyle(
                                  fontSize: 11, color: Colors.grey.shade600),
                            ),
                          ],
                        ],
                      ],
                    ),
                  ),

                  const Divider(height: 1),

                  // SECTION 2: PROCUREMENT LIST NOTIFICATIONS
                  Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.inventory_2_outlined,
                                size: 20, color: Colors.indigo.shade700),
                            const SizedBox(width: 8),
                            const Expanded(
                              child: Text(
                                'Procurement List Reminders',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF3730A3),
                                ),
                              ),
                            ),
                            Switch(
                              value: _procurementEnabled,
                              onChanged: (val) async {
                                await AppNotificationService.instance
                                    .setProcurementEnabled(val);
                                _syncNotificationSchedule();
                                if (!mounted) return;
                                setState(() => _procurementEnabled = val);
                              },
                            ),
                          ],
                        ),
                        if (_procurementEnabled) ...[
                          const SizedBox(height: 6),
                          Text(
                            'Procurement Alert Times (${_procurementTimes.length} times set):',
                            style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: Colors.black87),
                          ),
                          const SizedBox(height: 6),
                          Wrap(
                            spacing: 8,
                            runSpacing: 6,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              for (int i = 0; i < _procurementTimes.length; i++)
                                InputChip(
                                  avatar: const Icon(Icons.alarm,
                                      size: 16, color: Color(0xFF3730A3)),
                                  label: Text(
                                      _formatTimeOfDay(_procurementTimes[i])),
                                  onDeleted: () => _removeProcureTime(i),
                                  deleteIconColor: Colors.red.shade400,
                                  onPressed: () => _pickTime(
                                    current: _procurementTimes[i],
                                    onSaved: (t) async {
                                      _procurementTimes[i] = t;
                                      _procurementTimes.sort((a, b) =>
                                          (a.hour * 60 + a.minute).compareTo(
                                              b.hour * 60 + b.minute));
                                      await AppNotificationService.instance
                                          .setProcurementTimes(
                                              _procurementTimes);
                                      _syncNotificationSchedule();
                                      if (!mounted) return;
                                      setState(() {});
                                    },
                                  ),
                                ),
                              ActionChip(
                                avatar: const Icon(Icons.add_alarm,
                                    size: 16, color: Color(0xFF3730A3)),
                                label: const Text('+ Add Time'),
                                onPressed: _addProcureTime,
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),

                  const Divider(height: 1),

                  // SECTION 3: DAILY BUSINESS CLOSING REPORT
                  Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.assessment_outlined,
                                size: 20, color: Colors.deepOrange.shade700),
                            const SizedBox(width: 8),
                            const Expanded(
                              child: Text(
                                'Daily Business Summary Report',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFFC2410C),
                                ),
                              ),
                            ),
                            Switch(
                              value: _dailyReportEnabled,
                              onChanged: (val) async {
                                await AppNotificationService.instance
                                    .setDailyReportEnabled(val);
                                _syncNotificationSchedule();
                                if (!mounted) return;
                                setState(() => _dailyReportEnabled = val);
                              },
                            ),
                          ],
                        ),
                        if (_dailyReportEnabled) ...[
                          const SizedBox(height: 6),
                          const Text(
                            'Daily report summarizes total sales, completed orders, and collections.',
                            style: TextStyle(fontSize: 11, color: Colors.grey),
                          ),
                          const SizedBox(height: 6),
                          ActionChip(
                            avatar: const Icon(Icons.nightlight_round,
                                size: 16, color: Color(0xFFC2410C)),
                            label: Text(
                                'Report Time: ${_formatTimeOfDay(_dailyReportTime)} (Tap to edit)'),
                            onPressed: () => _pickTime(
                              current: _dailyReportTime,
                              onSaved: (t) async {
                                _dailyReportTime = t;
                                await AppNotificationService.instance
                                    .setDailyReportTime(t);
                                _syncNotificationSchedule();
                                if (!mounted) return;
                                setState(() {});
                              },
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),

                  const Divider(height: 1),
                  ListTile(
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    leading: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.amber.shade50,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(Icons.price_change_outlined,
                          color: Colors.amber.shade900, size: 22),
                    ),
                    title: const Text(
                      'Market Price Caution Alert',
                      style:
                          TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                    subtitle: const Text(
                      'Warns when product rates haven\'t been updated for market price changes',
                      style: TextStyle(fontSize: 11, color: Colors.grey),
                    ),
                    trailing: Switch(
                      value: _priceCautionEnabled,
                      onChanged: (val) async {
                        await AppNotificationService.instance
                            .setPriceCautionEnabled(val);
                        if (!mounted) return;
                        setState(() => _priceCautionEnabled = val);
                      },
                    ),
                  ),
                  if (_priceCautionEnabled) ...[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text(
                                'Caution alert if price not updated for:',
                                style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFF92400E)),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFFEF3C7),
                                  borderRadius: BorderRadius.circular(6),
                                  border:
                                      Border.all(color: const Color(0xFFF59E0B)),
                                ),
                                child: Text(
                                  '$_priceCautionDays Days',
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 11,
                                      color: Color(0xFFB45309)),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: [15, 30, 45, 60, 90].map((d) {
                              return ChoiceChip(
                                label: Text(
                                    '$d Days${d == 30 ? ' (Default)' : ''}'),
                                selected: _priceCautionDays == d,
                                onSelected: (sel) async {
                                  if (sel) {
                                    await AppNotificationService.instance
                                        .setPriceCautionDays(d);
                                    if (!mounted) return;
                                    setState(() => _priceCautionDays = d);
                                  }
                                },
                              );
                            }).toList(),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
                const Divider(height: 1),
                ListTile(
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child:
                        Icon(Icons.send_rounded, color: Colors.blue.shade700),
                  ),
                  title: const Text('Send Test Notification Now',
                      style:
                          TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                  subtitle: const Text(
                    'Triggers the pending orders / procurement notification immediately',
                    style: TextStyle(fontSize: 11, color: Colors.grey),
                  ),
                  trailing: TextButton.icon(
                    icon: const Icon(Icons.notifications, size: 16),
                    label: const Text('Test'),
                    onPressed: () async {
                      await AppNotificationService.instance
                          .checkAndNotify(force: true);
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                                'Test reminder notification sent! Check your notification bar.'),
                            backgroundColor: Colors.teal,
                          ),
                        );
                      }
                    },
                  ),
                ),
                const Divider(height: 1),
                ListTile(
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.teal.shade50,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(Icons.alarm, color: Colors.teal.shade700),
                  ),
                  title: const Text('Test Closed-App Alarm (30s delay)',
                      style:
                          TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                  subtitle: const Text(
                    'Schedules native OS alarm in 30 seconds. Close or lock app to verify!',
                    style: TextStyle(fontSize: 11, color: Colors.grey),
                  ),
                  trailing: FilledButton.tonal(
                    style: FilledButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                    ),
                    child: const Text('Test 30s'),
                    onPressed: () async {
                      await AppNotificationService.instance
                          .scheduleTestBackgroundAlarm();
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                                '⏰ Alarm scheduled for 30s from now! Close the app or lock your phone to test.'),
                            backgroundColor: Color(0xFF0F766E),
                            duration: Duration(seconds: 4),
                          ),
                        );
                      }
                    },
                  ),
                ),
                const Divider(height: 1),
                ListTile(
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.amber.shade50,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(Icons.battery_charging_full_rounded,
                        color: Colors.amber.shade800),
                  ),
                  title: const Text('Autostart & Battery Saver Guide',
                      style:
                          TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                  subtitle: const Text(
                    'Ensure alarms ring when app is closed on Xiaomi, Vivo, Samsung, Realme devices.',
                    style: TextStyle(fontSize: 11, color: Colors.grey),
                  ),
                  trailing: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                    ),
                    onPressed: _showBatteryGuideDialog,
                    child: const Text('Guide'),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Inventory & Catalog
          Text(
            'INVENTORY & CATALOG',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: Colors.grey.shade700,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 8),
          Card(
            child: ListTile(
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              leading: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.teal.shade50,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(Icons.inventory_2_outlined,
                    color: Colors.teal.shade700),
              ),
              title: Text(
                s.t('manageProducts'),
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              subtitle: Text(
                s.t('manageProductsHint'),
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
              ),
              trailing: const Icon(Icons.chevron_right, color: Colors.grey),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) => SimpleProductAdminScreen(
                        productRepository: widget.productRepository),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 20),

          // Shop Cloud Sync & Staff Access
          if (!_customService.isPureOfflineMode &&
              !const bool.fromEnvironment('STANDALONE_LOCAL',
                  defaultValue: false)) ...[
            Text(
              'SHOP CLOUD SYNC & TEAM',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: Colors.grey.shade700,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 8),
            Card(
              child: ListTile(
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.indigo.shade50,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(Icons.cloud_sync_rounded,
                      color: Colors.indigo.shade700),
                ),
                title: const Text('Shop Sync & Partner Devices',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Text(
                  ShopSyncService.instance.hasShop
                      ? 'Connected to ${ShopSyncService.instance.currentShop?.shopName} (${ShopSyncService.instance.currentShop?.shopCode})'
                      : 'Pair & sync products and live orders with family / partner devices',
                  style: const TextStyle(fontSize: 12),
                ),
                trailing: const Icon(Icons.chevron_right, color: Colors.grey),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute<void>(
                      builder: (_) => const ShopSyncScreen(),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 20),
          ],

          // Data Management & Clear (Master Device / Local Only)
          if (const bool.fromEnvironment('STANDALONE_LOCAL',
                  defaultValue: false) ||
              _customService.isPureOfflineMode ||
              !ShopSyncService.instance.hasShop ||
              ShopSyncService.instance.currentShop?.isOwner == true) ...[
            Text(
              'DATA MANAGEMENT & CLEAR',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: Colors.red.shade800,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 8),
            Card(
              child: Column(
                children: [
                  ListTile(
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    leading: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.amber.shade50,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(Icons.receipt_long_outlined,
                          color: Colors.amber.shade800),
                    ),
                    title: const Text('Clear Past Order History',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: const Text(
                      'Delete all past orders and bills. Products and customers remain safe.',
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                    trailing: FilledButton.tonal(
                      style: FilledButton.styleFrom(
                        foregroundColor: Colors.red.shade800,
                        backgroundColor: Colors.red.shade50,
                        visualDensity: VisualDensity.compact,
                      ),
                      onPressed: _clearOrderHistoryDialog,
                      child: const Text('Clear Orders'),
                    ),
                  ),
                  const Divider(height: 1),
                  ListTile(
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    leading: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.orange.shade50,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(Icons.inventory_2_outlined,
                          color: Colors.orange.shade800),
                    ),
                    title: const Text('Clear Products Catalog',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: const Text(
                      'Delete all products from inventory. Past orders remain safe.',
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                    trailing: FilledButton.tonal(
                      style: FilledButton.styleFrom(
                        foregroundColor: Colors.red.shade800,
                        backgroundColor: Colors.red.shade50,
                        visualDensity: VisualDensity.compact,
                      ),
                      onPressed: _clearProductsCatalogDialog,
                      child: const Text('Clear Catalog'),
                    ),
                  ),
                  const Divider(height: 1),
                  ListTile(
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    leading: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.red.shade50,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child:
                          const Icon(Icons.delete_forever, color: Colors.red),
                    ),
                    title: const Text('Reset All Shop Data',
                        style: TextStyle(
                            fontWeight: FontWeight.bold, color: Colors.red)),
                    subtitle: const Text(
                      'Factory reset: delete all orders, products, and customers.',
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                    trailing: FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.red.shade700,
                        visualDensity: VisualDensity.compact,
                      ),
                      onPressed: _resetAllShopDataDialog,
                      child: const Text('Reset All'),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
          ],

          // Documentation & User Manual
          Text(
            'HELP & MANUAL',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: Colors.grey.shade700,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 8),
          Card(
            child: ListTile(
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              leading: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFF0F766E).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.menu_book_rounded,
                    color: Color(0xFF0F766E), size: 24),
              ),
              title: const Text(
                'App Documentation & User Manual',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
              ),
              subtitle: const Text(
                'Detailed pin-to-pin guide for orders, khata, sync, thermal printing & settings',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
              trailing: const Icon(Icons.chevron_right, color: Colors.grey),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) => const AppDocumentationScreen(),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 20),

          // App Details
          Text(
            'ABOUT',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: Colors.grey.shade700,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(Icons.info_outline, color: Colors.blue.shade700),
                  ),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _customService.shopName,
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 14),
                      ),
                      const SizedBox(height: 2),
                      const Text(
                        'Version 1.2.0 • Offline SQLite DB & Cloud Ready',
                        style: TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showBatteryGuideDialog() {
    showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 30),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFCCFBF1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.battery_saver, color: Color(0xFF0F766E)),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'Ensure Closed-App Notifications Ring',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              const Text(
                'Phones with aggressive power-saving (Xiaomi HyperOS/MIUI, Vivo FuntouchOS, Samsung OneUI, Realme) can delay alarms when apps are swiped away. Follow these 3 quick steps:',
                style: TextStyle(fontSize: 12, color: Colors.black87),
              ),
              const SizedBox(height: 12),
              _buildGuideStep('1', 'Long-press the Shop app icon on your home screen > Tap "App Info" (ⓘ).'),
              const SizedBox(height: 8),
              _buildGuideStep('2', 'Tap Battery / Battery Saver > Choose "Unrestricted" or "No restrictions".'),
              const SizedBox(height: 8),
              _buildGuideStep('3', 'Enable "Autostart" / "Allow background activity" if your phone shows this option.'),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF0F766E),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  icon: const Icon(Icons.check, size: 18),
                  label: const Text('GOT IT'),
                  onPressed: () => Navigator.pop(ctx),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildGuideStep(String number, String text) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 22,
          height: 22,
          alignment: Alignment.center,
          decoration: const BoxDecoration(
            color: Color(0xFF0F766E),
            shape: BoxShape.circle,
          ),
          child: Text(
            number,
            style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(text, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
        ),
      ],
    );
  }
}
