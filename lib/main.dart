import 'dart:async';
import 'dart:ui';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shop/database/database_helper.dart';
import 'package:shop/app_keys.dart';
import 'package:shop/firebase_options.dart';
import 'package:shop/l10n/app_localizations.dart';
import 'package:shop/repositories/customer_repository.dart';
import 'package:shop/repositories/order_repository.dart';
import 'package:shop/repositories/product_repository.dart';
import 'package:shop/screens/home_screen.dart';
import 'package:shop/services/app_notification_service.dart';
import 'package:shop/services/app_telemetry_service.dart';
import 'package:shop/services/backup_service.dart';
import 'package:shop/services/fcm_service.dart';
import 'package:shop/services/shop_customization_service.dart';
import 'package:shop/services/shop_sync_service.dart';
import 'package:shop/services/storage_monitor_service.dart';

const bool kPureOfflineMode =
    bool.fromEnvironment('STANDALONE_LOCAL', defaultValue: false);

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    debugPrint('Flutter Error: ${details.exceptionAsString()}');
    unawaited(
      AppTelemetryService.instance.recordError(
        details.exception,
        details.stack,
        source: 'flutter_framework',
        fatal: true,
      ),
    );
  };

  PlatformDispatcher.instance.onError = (error, stack) {
    debugPrint('Uncaught platform error: $error');
    unawaited(
      AppTelemetryService.instance.recordError(
        error,
        stack,
        source: 'platform_dispatcher',
        fatal: true,
      ),
    );
    return true;
  };

  // Initialize Firebase first when running in Cloud Sync mode so no plugin ever hits [core/no-app].
  if (!kPureOfflineMode) {
    try {
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp(
          options: DefaultFirebaseOptions.currentPlatform,
        );
      }
    } catch (fbErr) {
      debugPrint('Firebase primary init error: $fbErr');
      try {
        if (Firebase.apps.isEmpty) {
          await Firebase.initializeApp();
        }
      } catch (e2) {
        debugPrint('Firebase init fallback: $e2');
      }
    }

    if (Firebase.apps.isNotEmpty) {
      FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
    }
  }

  try {
    await DatabaseHelper.instance.database;
    await ShopCustomizationService.instance.initialize();
    await StorageMonitorService.instance.initialize();
    unawaited(AppNotificationService.instance.initialize().catchError((e) {
      debugPrint('Notification service init error: $e');
    }));
    if (kPureOfflineMode) {
      await ShopCustomizationService.instance.setPureOfflineMode(true);
    } else {
      unawaited(ShopSyncService.instance.initialize().catchError((e) {
        debugPrint('Sync service init error: $e');
      }));
      unawaited(FCMService.instance.initialize().catchError((e) {
        debugPrint('FCM service init error: $e');
      }));
    }
    final preferences = await SharedPreferences.getInstance();
    final languageCode = preferences.getString('language_code') ?? 'en';
    runApp(ShopApp(initialLocale: Locale(languageCode)));
  } catch (error, stack) {
    debugPrint('Fatal application startup error: $error\n$stack');
    runApp(MaterialApp(
      home: Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.error_outline, size: 64, color: Colors.red),
                const SizedBox(height: 16),
                const Text(
                  'Initialization Error',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(
                  'Failed to start the application:\n$error',
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    ));
  }
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
    final themePrimaryColor = kPureOfflineMode
        ? const Color(0xFFD97706) // Bright Amber / Retail Counter Theme
        : const Color(0xFF0F766E); // Deep Emerald / Wholesale Theme

    return MaterialApp(
      navigatorKey: navigatorKey,
      scaffoldMessengerKey: rootMessengerKey,

      title: kPureOfflineMode ? 'Shop Retail' : 'Shop Wholesale',
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
        colorScheme: ColorScheme.fromSeed(
          seedColor: themePrimaryColor,
          primary: themePrimaryColor,
          surface: Colors.white,
          surfaceContainerLowest: Colors.white,
          surfaceContainerLow: const Color(0xFFF8FAFC),
          surfaceContainer: const Color(0xFFF1F5F9),
        ),
        scaffoldBackgroundColor: const Color(0xFFF8FAFC),
        useMaterial3: true,
        appBarTheme: const AppBarTheme(
          centerTitle: false,
          elevation: 0,
          scrolledUnderElevation: 1,
          backgroundColor: Color(0xFFF8FAFC),
          surfaceTintColor: Colors.transparent,
          foregroundColor: Color(0xFF0F172A),
          titleTextStyle: TextStyle(
            color: Color(0xFF0F172A),
            fontSize: 18,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.2,
          ),
          iconTheme: IconThemeData(color: Color(0xFF334155)),
        ),
        cardTheme: CardThemeData(
          elevation: 0,
          margin: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: Color(0xFFE2E8F0), width: 1),
          ),
          color: Colors.white,
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFFCBD5E1), width: 1),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFFE2E8F0), width: 1),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: themePrimaryColor, width: 1.8),
          ),
          labelStyle: const TextStyle(color: Color(0xFF64748B), fontSize: 14),
          hintStyle: const TextStyle(color: Color(0xFF94A3B8), fontSize: 14),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            backgroundColor: themePrimaryColor,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            textStyle:
                const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            foregroundColor: themePrimaryColor,
            side: const BorderSide(color: Color(0xFFCBD5E1), width: 1.2),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
            textStyle:
                const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
          ),
        ),
        dividerTheme: const DividerThemeData(
          color: Color(0xFFE2E8F0),
          thickness: 1,
          space: 16,
        ),
        textTheme: const TextTheme(
          headlineMedium: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w800,
            color: Color(0xFF0F172A),
            letterSpacing: -0.4,
          ),
          titleLarge: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: Color(0xFF0F172A),
            letterSpacing: -0.2,
          ),
          titleMedium: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: Color(0xFF1E293B),
          ),
          bodyLarge: TextStyle(fontSize: 15, color: Color(0xFF334155)),
          bodyMedium: TextStyle(fontSize: 13, color: Color(0xFF475569)),
          labelLarge: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: Color(0xFF0F172A),
            letterSpacing: 0.2,
          ),
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
