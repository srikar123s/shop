import 'package:flutter/material.dart';
import 'package:shop/l10n/app_localizations.dart';
import 'package:shop/repositories/customer_repository.dart';
import 'package:shop/repositories/order_repository.dart';
import 'package:shop/repositories/product_repository.dart';
import 'package:shop/screens/customer_screen.dart';
import 'package:shop/screens/history_screen.dart';
import 'package:shop/screens/shop_settings_screen.dart';
import 'package:shop/services/backup_service.dart';
import 'package:shop/widgets/large_action_button.dart';

class HomeScreen extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(s.t('appTitle')),
        centerTitle: true,
        actions: <Widget>[
          IconButton(
            tooltip: s.t('shopSettings'),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => ShopSettingsScreen(
                    productRepository: productRepository,
                    locale: locale,
                    onLocaleChanged: onLocaleChanged,
                  ),
                ),
              );
            },
            icon: const Icon(Icons.settings),
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Text(
                s.t('appTitle'),
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 8),
              const Text('Fast, simple order management'),
              const SizedBox(height: 32),
              LargeActionButton(
                label: s.t('createOrder'),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute<void>(
                      builder: (_) => CustomerScreen(
                        customerRepository: customerRepository,
                        productRepository: productRepository,
                        orderRepository: orderRepository,
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 24),
              LargeActionButton(
                label: s.t('history'),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute<void>(
                      builder: (_) => HistoryScreen(
                        orderRepository: orderRepository,
                        backupService: backupService,
                        customerRepository: customerRepository,
                        productRepository: productRepository,
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
