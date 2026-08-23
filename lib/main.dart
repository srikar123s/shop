import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shop/database/database_helper.dart';
import 'package:shop/l10n/app_localizations.dart';
import 'package:shop/repositories/customer_repository.dart';
import 'package:shop/repositories/order_repository.dart';
import 'package:shop/repositories/product_repository.dart';
import 'package:shop/screens/home_screen.dart';
import 'package:shop/services/backup_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await DatabaseHelper.instance.database;
  final preferences = await SharedPreferences.getInstance();
  final languageCode = preferences.getString('language_code') ?? 'en';
  runApp(ShopApp(initialLocale: Locale(languageCode)));
}

class ShopApp extends StatefulWidget {
  const ShopApp({super.key, required this.initialLocale});

  final Locale initialLocale;

  @override
  State<ShopApp> createState() => _ShopAppState();
}

class _ShopAppState extends State<ShopApp> {
  late Locale _locale;

  @override
  void initState() {
    super.initState();
    _locale = widget.initialLocale;
  }

  Future<void> _setLocale(Locale locale) async {
    setState(() {
      _locale = locale;
    });
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString('language_code', locale.languageCode);
  }

  @override
  Widget build(BuildContext context) {
    final database = DatabaseHelper.instance;
    final customerRepository = CustomerRepository(database);
    final productRepository = ProductRepository(database);
    final orderRepository = OrderRepository(database);
    final backupService = BackupService(database);

    return MaterialApp(
      title: 'Hardware Shop',
      debugShowCheckedModeBanner: false,
      locale: _locale,
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF0F766E)),
        scaffoldBackgroundColor: const Color(0xFFF5F7FA),
        useMaterial3: true,
        appBarTheme: const AppBarTheme(
          centerTitle: false,
          elevation: 0,
          scrolledUnderElevation: 1,
          backgroundColor: Color(0xFFF5F7FA),
          surfaceTintColor: Colors.transparent,
        ),
        cardTheme: CardThemeData(
          elevation: 0,
          margin: EdgeInsets.zero,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          color: Colors.white,
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide.none,
          ),
        ),
        textTheme: const TextTheme(
          headlineMedium: TextStyle(fontSize: 26, fontWeight: FontWeight.w800),
          titleLarge: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
          bodyLarge: TextStyle(fontSize: 16),
          bodyMedium: TextStyle(fontSize: 14),
          labelLarge: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
        ),
      ),
      home: HomeScreen(
        customerRepository: customerRepository,
        productRepository: productRepository,
        orderRepository: orderRepository,
        backupService: backupService,
        locale: _locale,
        onLocaleChanged: _setLocale,
      ),
    );
  }
}
