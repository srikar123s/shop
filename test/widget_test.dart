import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shop/database/database_helper.dart';
import 'package:shop/l10n/app_localizations.dart';
import 'package:shop/models/customer.dart';
import 'package:shop/models/order.dart';
import 'package:shop/repositories/customer_repository.dart';
import 'package:shop/repositories/order_repository.dart';
import 'package:shop/repositories/product_repository.dart';
import 'package:shop/screens/khata_book_screen.dart';
import 'package:shop/screens/order_preview_screen.dart';
import 'package:shop/screens/simple_product_admin_screen.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Widget _wrapLocalized(Widget child, {Locale locale = const Locale('en')}) {
  return MaterialApp(
    locale: locale,
    supportedLocales: AppLocalizations.supportedLocales,
    localizationsDelegates: [
      AppLocalizations.delegate,
      if (locale.languageCode == 'en') ...const [
        DefaultMaterialLocalizations.delegate,
        DefaultWidgetsLocalizations.delegate,
      ] else ...const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
    ],
    home: child,
  );
}

Future<void> _pumpAndLetFfiSettle(WidgetTester tester) async {
  for (var i = 0; i < 3; i++) {
    await tester.pump();
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 250));
    });
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  var dbCounter = 0;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    tempDir = await Directory.systemTemp.createTemp('shop_widget_test_');
    dbCounter++;
    await DatabaseHelper.instance.close();
    DatabaseHelper.testDbPathOverride =
        p.join(tempDir.path, 'widget_test_$dbCounter.db');
    await DatabaseHelper.instance.database;
  });

  tearDown(() async {
    await DatabaseHelper.instance.close();
    DatabaseHelper.testDbPathOverride = null;
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('customer serializes its stored fields', () {
    final customer = Customer(
      id: 1,
      name: 'Ravi',
      phone: '9876543210',
      createdAt: DateTime.utc(2026, 8, 23),
    );

    final restored = Customer.fromMap(customer.toMap());

    expect(restored.id, 1);
    expect(restored.name, 'Ravi');
    expect(restored.phone, '9876543210');
  });

  test('draft order serializes to and from map', () {
    final customer = Customer(id: 1, name: 'Srinivas', createdAt: DateTime.now());
    final item = DraftOrderItem(
      productId: 10,
      itemName: 'Welding Rod',
      options: {'brand': 'Brand A'},
      quantity: 5,
      unit: 'Box',
      unitPrice: 250,
      unitFactor: 100,
    );
    final draft = DraftOrder(customer: customer, items: [item], estimateTotal: 1250);

    final map = draft.toMap();
    final restoredDraft = DraftOrder.fromMap(map);

    expect(restoredDraft.customer.name, 'Srinivas');
    expect(restoredDraft.items.length, 1);
    expect(restoredDraft.items.first.itemName, 'Welding Rod');
    expect(restoredDraft.items.first.unitPrice, 250);
    expect(restoredDraft.estimateTotal, 1250);
  });

  testWidgets('OrderPreviewScreen renders draft item and Telugu localization',
      (tester) async {
    final orderRepo = OrderRepository(DatabaseHelper.instance);
    final customer = Customer(
      id: 1,
      name: 'Srikar Hardware',
      phone: '9999988888',
      createdAt: DateTime.now(),
    );
    final draft = DraftOrder(
      customer: customer,
      items: [
        DraftOrderItem(
          productId: 1,
          itemName: 'Welding Rod',
          options: const {'brand': 'Ador'},
          quantity: 2,
          unit: 'Box',
          unitPrice: 300,
          unitFactor: 1,
        ),
      ],
      estimateTotal: 600,
    );

    await tester.pumpWidget(
      _wrapLocalized(
        OrderPreviewScreen(draftOrder: draft, orderRepository: orderRepo),
        locale: const Locale('te'),
      ),
    );
    await _pumpAndLetFfiSettle(tester);

    expect(find.textContaining('Welding Rod'), findsWidgets);
    expect(find.text('ఆర్డర్ ప్రివ్యూ'), findsOneWidget);
  });

  testWidgets('KhataBookScreen renders localized title from FFI database',
      (tester) async {
    final db = DatabaseHelper.instance;
    await tester.pumpWidget(
      _wrapLocalized(
        KhataBookScreen(
          customerRepository: CustomerRepository(db),
          orderRepository: OrderRepository(db),
          productRepository: ProductRepository(db),
        ),
        locale: const Locale('te'),
      ),
    );
    await _pumpAndLetFfiSettle(tester);

    expect(find.text('ఖాతా బుక్ (ఉధార్ లెడ్జర్)'), findsOneWidget);
    expect(find.text('మొత్తం మార్కెట్ ఉధార్ (బాకీ)'), findsOneWidget);
  });

  testWidgets('SimpleProductAdminScreen renders localized header and search field',
      (tester) async {
    final db = DatabaseHelper.instance;
    await tester.pumpWidget(
      _wrapLocalized(
        SimpleProductAdminScreen(productRepository: ProductRepository(db)),
        locale: const Locale('en'),
      ),
    );
    await _pumpAndLetFfiSettle(tester);

    expect(tester.takeException(), isNull);
    expect(find.text('Manage products'), findsOneWidget);
    expect(find.text('IMPORT EXCEL'), findsOneWidget);
  });
}
