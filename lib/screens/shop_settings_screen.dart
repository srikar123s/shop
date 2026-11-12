import 'package:flutter/material.dart';
import 'package:shop/l10n/app_localizations.dart';
import 'package:shop/repositories/product_repository.dart';
import 'package:shop/screens/shop_sync_screen.dart';
import 'package:shop/screens/simple_product_admin_screen.dart';

class ShopSettingsScreen extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(s.t('shopSettings'))),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        children: <Widget>[
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
                      selected: <String>{locale.languageCode},
                      onSelectionChanged: (selection) =>
                          onLocaleChanged(Locale(selection.first)),
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
                child:
                    Icon(Icons.inventory_2_outlined, color: Colors.teal.shade700),
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
                        productRepository: productRepository),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 20),

          // Shop Cloud Sync & Staff Access
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
              subtitle: const Text(
                  'Share shop code/QR with staff for instant real-time sync',
                  style: TextStyle(fontSize: 12)),
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
                  const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Hardware Shop Billing & Order Manager',
                        style: TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 14),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'Version 1.1.0 • Offline SQLite DB',
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
