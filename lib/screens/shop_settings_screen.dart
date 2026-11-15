import 'package:flutter/material.dart';
import 'package:shop/database/database_helper.dart';
import 'package:shop/l10n/app_localizations.dart';
import 'package:shop/repositories/product_repository.dart';
import 'package:shop/screens/app_documentation_screen.dart';
import 'package:shop/screens/quantity_shortcuts_screen.dart';
import 'package:shop/screens/shop_sync_screen.dart';
import 'package:shop/screens/simple_product_admin_screen.dart';
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

  @override
  void initState() {
    super.initState();
    _customService.addListener(_onServiceUpdate);
  }

  @override
  void dispose() {
    _customService.removeListener(_onServiceUpdate);
    super.dispose();
  }

  void _onServiceUpdate() {
    if (mounted) setState(() {});
  }

  Future<void> _editShopNameDialog() async {
    final controller = TextEditingController(text: _customService.shopName);
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

    if (saved == true && controller.text.trim().isNotEmpty) {
      await _customService.setShopName(controller.text.trim());
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Shop name updated to "${controller.text.trim()}"!'),
            backgroundColor: const Color(0xFF0F766E),
          ),
        );
      }
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

    if (saved == true) {
      await onSave(controller.text.trim());
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$title updated!'),
            backgroundColor: const Color(0xFF0F766E),
          ),
        );
      }
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
                  onTap: () => _editFieldDialog(
                    title: 'UPI ID for Scan & Pay',
                    label: 'UPI ID (e.g. 9392449356@ybl)',
                    hint: 'merchant@oksbi or 9876543210@paytm',
                    initialValue: _customService.upiId,
                    onSave: _customService.setUpiId,
                  ),
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
                          'Permission Denied: Only shop owner can modify quantity shortcuts.'),
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
                title: const Text('Shop Sync & Staff Sharing',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Text(
                  ShopSyncService.instance.hasShop
                      ? 'Connected to ${ShopSyncService.instance.currentShop?.shopName} (${ShopSyncService.instance.currentShop?.shopCode})'
                      : 'Share shop code/QR with staff for instant real-time sync',
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

          // Data Management & Clear (Owner / Local Only)
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
}
