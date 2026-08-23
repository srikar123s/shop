import 'package:flutter/material.dart';
import 'package:shop/l10n/app_localizations.dart';
import 'package:shop/repositories/product_repository.dart';
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
    return Scaffold(
      appBar: AppBar(title: Text(s.t('shopSettings'))),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          Text(s.t('language'),
              style:
                  const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          SegmentedButton<String>(
            segments: const <ButtonSegment<String>>[
              ButtonSegment<String>(value: 'en', label: Text('English')),
              ButtonSegment<String>(value: 'te', label: Text('తెలుగు')),
            ],
            selected: <String>{locale.languageCode},
            onSelectionChanged: (selection) =>
                onLocaleChanged(Locale(selection.first)),
          ),
          const SizedBox(height: 24),
          ListTile(
            leading: const Icon(Icons.inventory_2_outlined),
            title: Text(s.t('manageProducts')),
            subtitle: Text(s.t('manageProductsHint')),
            trailing: const Icon(Icons.chevron_right),
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
        ],
      ),
    );
  }
}
