import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shop/database/database_helper.dart';
import 'package:shop/models/customer.dart';
import 'package:shop/models/delivery_partner.dart';
import 'package:shop/models/order.dart';
import 'package:shop/models/product.dart';
import 'package:shop/repositories/customer_repository.dart';
import 'package:shop/repositories/delivery_repository.dart';
import 'package:shop/repositories/order_repository.dart';
import 'package:shop/repositories/product_repository.dart';
import 'package:shop/services/archive_service.dart';
import 'package:shop/services/draft_order_service.dart';
import 'package:shop/services/excel_product_service.dart';
import 'package:shop/services/shop_sync_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late DatabaseHelper dbHelper;
  late CustomerRepository customerRepo;
  late ProductRepository productRepo;
  late OrderRepository orderRepo;
  late DeliveryRepository deliveryRepo;
  var testCounter = 0;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    tempDir = await Directory.systemTemp.createTemp('shop_db_test_');
    testCounter++;
    await DatabaseHelper.instance.close();
    DatabaseHelper.testDbPathOverride =
        p.join(tempDir.path, 'test_shop_$testCounter.db');
    dbHelper = DatabaseHelper.instance;
    customerRepo = CustomerRepository(dbHelper);
    productRepo = ProductRepository(dbHelper);
    orderRepo = OrderRepository(dbHelper);
    deliveryRepo = DeliveryRepository(dbHelper: dbHelper);
    await dbHelper.database;
  });

  tearDown(() async {
    await dbHelper.close();
    DatabaseHelper.testDbPathOverride = null;
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('SQLite Schema, Indexes & Recovery', () {
    test('Creates v10 schema with performance indexes and soft-delete column', () async {
      final db = await dbHelper.database;
      final indexes = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type = 'index'",
      );
      final indexNames = indexes.map((r) => r['name'] as String).toSet();

      expect(indexNames, contains('idx_customer_payments_created_at'));
      expect(indexNames, contains('idx_orders_status'));
      expect(indexNames, contains('idx_order_items_proc_status'));
      expect(indexNames, contains('idx_order_items_product_id'));

      final custCols = await db.rawQuery('PRAGMA table_info(customers)');
      final colNames = custCols.map((r) => r['name'] as String).toSet();
      expect(colNames, contains('is_active'));
    });

    test('Upgrades v9 database to v10 preserving existing data', () async {
      await dbHelper.close();
      final legacyPath = p.join(tempDir.path, 'legacy_v9.db');
      final legacyDb = await openDatabase(
        legacyPath,
        version: 9,
        onCreate: (db, _) async {
          await db.execute('''
            CREATE TABLE customers (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              name TEXT NOT NULL,
              phone TEXT,
              address TEXT,
              credit_limit REAL NOT NULL DEFAULT 0.0,
              created_at TEXT NOT NULL
            )
          ''');
          await db.execute('''
            CREATE TABLE products (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              name TEXT NOT NULL,
              category TEXT NOT NULL,
              is_active INTEGER NOT NULL DEFAULT 1,
              needs_review INTEGER NOT NULL DEFAULT 0,
              configuration TEXT NOT NULL,
              price_updated_at TEXT,
              created_at TEXT NOT NULL
            )
          ''');
          await db.execute('''
            CREATE TABLE product_options (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              product_id INTEGER NOT NULL,
              option_type TEXT NOT NULL,
              option_value TEXT NOT NULL,
              display_order INTEGER NOT NULL DEFAULT 0
            )
          ''');
          await db.execute('''
            CREATE TABLE orders (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              order_number INTEGER,
              cloud_order_id TEXT UNIQUE,
              customer_id INTEGER NOT NULL,
              customer_name_snapshot TEXT NOT NULL,
              customer_phone TEXT,
              taken_by TEXT,
              created_at TEXT NOT NULL,
              status TEXT NOT NULL,
              notes TEXT,
              estimate_total REAL NOT NULL DEFAULT 0,
              paid_amount REAL NOT NULL DEFAULT 0,
              payment_mode TEXT NOT NULL DEFAULT 'unpaid',
              payment_status TEXT NOT NULL DEFAULT 'unpaid',
              delivery_partner_name TEXT,
              box_count INTEGER NOT NULL DEFAULT 0
            )
          ''');
          await db.execute('''
            CREATE TABLE order_items (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              order_id INTEGER NOT NULL,
              product_id INTEGER,
              item_name TEXT NOT NULL,
              quantity_ordered REAL NOT NULL,
              quantity_given REAL NOT NULL,
              unit TEXT NOT NULL,
              unit_price REAL NOT NULL DEFAULT 0.0,
              status TEXT NOT NULL,
              is_other_item INTEGER NOT NULL DEFAULT 0,
              procurement_status TEXT NOT NULL,
              details TEXT,
              notes TEXT,
              product_snapshot TEXT NOT NULL
            )
          ''');
          await db.execute('''
            CREATE TABLE order_item_options (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              order_item_id INTEGER NOT NULL,
              option_name TEXT NOT NULL,
              option_value TEXT NOT NULL
            )
          ''');
          await db.execute('''
            CREATE TABLE customer_payments (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              cloud_payment_id TEXT UNIQUE,
              customer_id INTEGER NOT NULL,
              amount REAL NOT NULL,
              payment_mode TEXT NOT NULL,
              notes TEXT,
              created_at TEXT NOT NULL
            )
          ''');
          await db.insert('customers', {
            'name': 'Legacy Hardware',
            'phone': '9988776655',
            'created_at': DateTime.now().toIso8601String(),
          });
        },
      );
      await legacyDb.close();

      DatabaseHelper.testDbPathOverride = legacyPath;
      final upgraded = await dbHelper.database;
      final custRows = await upgraded.query('customers');
      expect(custRows.length, 1);
      expect(custRows.first['name'], 'Legacy Hardware');
      expect(custRows.first['is_active'], 1);

      final idxRows = await upgraded.rawQuery(
        "SELECT name FROM sqlite_master WHERE type = 'index' AND name = 'idx_orders_status'",
      );
      expect(idxRows, isNotEmpty);
    });

    test('Recovers after failed DB initialization instead of latching broken future', () async {
      await dbHelper.close();
      final dirInsteadOfDb = p.join(tempDir.path, 'dir_not_a_file');
      await Directory(dirInsteadOfDb).create(recursive: true);
      DatabaseHelper.testDbPathOverride = dirInsteadOfDb;
      await expectLater(dbHelper.database, throwsException);

      // Point back to a valid writable path and verify DB initializes cleanly
      DatabaseHelper.testDbPathOverride = p.join(tempDir.path, 'recovered.db');
      final db = await dbHelper.database;
      expect(db.isOpen, isTrue);
    });
  });

  group('OrderRepository Accounting & Procurement Integrity', () {
    test('updateOrderFulfillment preserves ordered estimate_total and updates unit_price', () async {
      final customer = await customerRepo.createCustomer(
        name: 'Ramesh Traders',
        phone: '9876543210',
      );
      final prodId = await productRepo.upsertProduct(
        const Product(
          name: 'Heavy Bolt',
          category: 'Hardware',
          isActive: true,
          configuration: ProductConfiguration(
            steps: [],
            defaultUnit: 'Box',
            basePrice: 100.0,
          ),
        ),
      );

      final draft = DraftOrder(
        customer: customer,
        items: [
          DraftOrderItem(
            productId: prodId,
            itemName: 'Heavy Bolt',
            options: {'size': '10mm'},
            quantity: 10,
            unit: 'Box',
            unitPrice: 100.0,
          ),
        ],
      );
      final breakdown = BillBreakdown.calculate(subtotal: 1000.0, applyGst: true, gstRate: 18.0);
      final orderId = await orderRepo.createOrder(
        draft,
        estimateTotal: breakdown.grandTotal,
        billBreakdown: breakdown,
      );

      var details = await orderRepo.getOrderDetails(orderId);
      expect(details, isNotNull);
      expect(details!.order.estimateTotal, 1180.0);

      // Item awaits procurement (quantityGiven = 0) -> open order must NOT drop to ₹0
      final item = details.items.first;
      await orderRepo.updateOrderFulfillment(
        orderId: orderId,
        items: [item.copyWith(quantityGiven: 0)],
      );

      details = await orderRepo.getOrderDetails(orderId);
      expect(details!.order.status, OrderStatus.pending);
      expect(details.order.estimateTotal, 1180.0);

      // getProcurementItems reads updated unit_price and options
      var procItems = await orderRepo.getProcurementItems();
      expect(procItems.length, 1);
      expect(procItems.first.unitPrice, 100.0);
      expect(procItems.first.options, contains('size: 10mm'));

      // Update unit_price on an unpriced custom item and verify DB unit_price + procurement
      await orderRepo.updateOrderFulfillment(
        orderId: orderId,
        items: [item.copyWith(quantityGiven: 0, unitPrice: 150.0)],
      );
      procItems = await orderRepo.getProcurementItems();
      expect(procItems.first.unitPrice, 150.0);
      details = await orderRepo.getOrderDetails(orderId);
      expect(details!.order.estimateTotal, 1770.0); // 1500 + 18% GST

      // Mark procured on open order completes order with accurate ₹1,770 total
      await orderRepo.markItemAsProcured(itemId: item.id!, orderId: orderId);
      details = await orderRepo.getOrderDetails(orderId);
      expect(details!.order.status, OrderStatus.completed);
      expect(details.order.estimateTotal, 1770.0);
      expect(details.items.first.quantityGiven, 10);
    });

    test('closeOrderWithDeliveredItemsOnly bills delivered goods and post-close procure preserves bill', () async {
      final customer = await customerRepo.createCustomer(
        name: 'Suresh Paints',
        phone: '9123456789',
      );
      final orderId = await orderRepo.createOrder(
        DraftOrder(
          customer: customer,
          items: [
            DraftOrderItem(
              itemName: 'Emulsion 1L',
              options: const {'colour': 'White'},
              quantity: 5,
              unit: 'Can',
              unitPrice: 200.0,
            ),
          ],
        ),
        estimateTotal: 1000.0,
      );

      var details = await orderRepo.getOrderDetails(orderId);
      final item = details!.items.first;

      await orderRepo.updateOrderFulfillment(
        orderId: orderId,
        items: [item.copyWith(quantityGiven: 2)],
      );
      await orderRepo.closeOrderWithDeliveredItemsOnly(orderId: orderId);

      details = await orderRepo.getOrderDetails(orderId);
      expect(details!.order.status, OrderStatus.completed);
      expect(details.order.estimateTotal, 400.0); // Strictly billed for 2 delivered cans

      var procItems = await orderRepo.getProcurementItems();
      expect(procItems.length, 1);
      expect(procItems.first.quantityPending, 3.0);

      // Marking procured later removes item from procurement queue without altering closed bill
      await orderRepo.markAllItemsAsProcured();
      procItems = await orderRepo.getProcurementItems();
      expect(procItems, isEmpty);

      details = await orderRepo.getOrderDetails(orderId);
      expect(details!.order.estimateTotal, 400.0);
      expect(details.items.first.quantityGiven, 2.0);
      expect(details.items.first.procurementStatus, ProcurementStatus.notRequired);
    });
  });

  group('Customer Deletion & Delivery Bounds', () {
    test('CustomerRepository safely handles zero-balance customers with and without history', () async {
      final cleanCust = await customerRepo.createCustomer(
        name: 'Temp Walkin',
        phone: '9000011111',
      );
      await customerRepo.deleteCustomer(cleanCust.id!);
      expect(await customerRepo.getCustomerById(cleanCust.id!), isNull);

      final settledCust = await customerRepo.createCustomer(
        name: 'Settled Hardware',
        phone: '9000022222',
      );
      final oid = await orderRepo.createOrder(
        DraftOrder(
          customer: settledCust,
          items: [
            DraftOrderItem(
              itemName: 'Screw Pack',
              options: const {},
              quantity: 1,
              unit: 'Box',
              unitPrice: 500.0,
            ),
          ],
        ),
        estimateTotal: 500.0,
      );
      await orderRepo.closeOrderWithAllGiven(oid);

      // Unpaid balance must fail deletion
      await expectLater(
        customerRepo.deleteCustomer(settledCust.id!),
        throwsException,
      );

      // Pay full balance -> now ₹0 due; deletion must succeed without FK crash
      await dbHelper.recordOrderPayment(
        orderId: oid,
        paidAmount: 500.0,
        paymentMode: 'Cash',
      );
      await customerRepo.deleteCustomer(settledCust.id!);

      // Hidden from active customer search & settled Khata, while past order history survives
      final activeSearch = await customerRepo.searchCustomers('Settled Hardware');
      expect(activeSearch, isEmpty);
      final khataList = await dbHelper.getCustomerKhataList();
      expect(
        khataList.where((r) => r['customer_id'] == settledCust.id),
        isEmpty,
      );
      final pastDetails = await orderRepo.getOrderDetails(oid);
      expect(pastDetails, isNotNull);
      expect(pastDetails!.order.estimateTotal, 500.0);
    });

    test('DeliverySettlement bounds advance cuts and partial payouts', () {
      // Earned ₹2,000, advance only ₹500 -> cut_full caps cut at ₹500, remaining ₹1,500 paid
      final cutCapped = DeliverySettlement.calculate(
        totalEarned: 2000.0,
        advanceBalance: 500.0,
        settlementMode: 'cut_full',
      );
      expect(cutCapped.cutAmount, 500.0);
      expect(cutCapped.paidAmount, 1500.0);

      // Negative cut is clamped to 0
      final negCut = DeliverySettlement.calculate(
        totalEarned: 1000.0,
        advanceBalance: 400.0,
        settlementMode: 'cut_partial',
        enteredCut: -200.0,
      );
      expect(negCut.cutAmount, 0.0);
      expect(negCut.paidAmount, 1000.0);

      // No advance -> negative paid clamped to 0, excessive paid clamped to totalEarned
      final negPaid = DeliverySettlement.calculate(
        totalEarned: 1000.0,
        advanceBalance: 0.0,
        settlementMode: 'pay_partial',
        enteredPaid: -100.0,
      );
      expect(negPaid.paidAmount, 0.0);

      final overPaid = DeliverySettlement.calculate(
        totalEarned: 1000.0,
        advanceBalance: 0.0,
        settlementMode: 'pay_partial',
        enteredPaid: 2500.0,
      );
      expect(overPaid.paidAmount, 1000.0);
    });

    test('DeliveryRepository.getDeliverySummary filters by locationFilter', () async {
      final pid = await deliveryRepo.addPartner(name: 'Raju Auto');
      final now = DateTime.now();
      await deliveryRepo.addTransaction(
        DeliveryTransaction(
          partnerId: pid,
          txType: DeliveryTxType.perBox,
          location: 'Warangal',
          totalBoxes: 10,
          earnedAmount: 300.0,
          paidAmount: 300.0,
          paymentMode: 'cash',
          createdAt: now,
        ),
      );
      await deliveryRepo.addTransaction(
        DeliveryTransaction(
          partnerId: pid,
          txType: DeliveryTxType.line,
          location: 'Karimnagar',
          totalBoxes: 5,
          earnedAmount: 1000.0,
          paidAmount: 500.0,
          paymentMode: 'upi',
          createdAt: now,
        ),
      );

      final all = await deliveryRepo.getDeliverySummary();
      expect(all['totalEarned'], 1300.0);

      final wgl = await deliveryRepo.getDeliverySummary(locationFilter: 'warangal');
      expect(wgl['totalEarned'], 300.0);
      expect(wgl['totalPaid'], 300.0);
      expect(wgl['totalBoxes'], 10);
    });
  });

  group('Evening Closing, Khata & Analytics Accuracy', () {
    test('Same-day split Cash order payment + Khata UPI recovery does not double-count or overwrite Cash', () async {
      final cust = await customerRepo.createCustomer(
        name: 'Kiran Builders',
        phone: '9888877777',
        address: 'Nizamabad',
      );
      final orderId = await orderRepo.createOrder(
        DraftOrder(
          customer: cust,
          items: [
            DraftOrderItem(
              itemName: 'Cement',
              options: const {},
              quantity: 10,
              unit: 'Bag',
              unitPrice: 100.0,
            ),
          ],
        ),
        estimateTotal: 1000.0,
      );

      // ₹600 paid in Cash on the order, then same-day ₹300 recovered in UPI via Khata, ₹100 by Cheque
      await dbHelper.recordOrderPayment(
        orderId: orderId,
        paidAmount: 600.0,
        paymentMode: 'Cash',
      );
      await dbHelper.recordCustomerKhataPayment(
        customerId: cust.id!,
        amount: 300.0,
        paymentMode: 'upi',
        notes: 'Balanced counter recovery',
      );
      await dbHelper.recordCustomerKhataPayment(
        customerId: cust.id!,
        amount: 100.0,
        paymentMode: 'cheque',
        notes: 'Final cheque',
      );

      final details = await orderRepo.getOrderDetails(orderId);
      expect(details!.order.paymentMode, 'split');
      expect(details.order.paidAmount, 1000.0);

      final closing = await dbHelper.getEveningClosingReport(DateTime.now());
      expect(closing['totalSales'], 1000.0);
      expect(closing['cashSales'], 600.0);
      expect(closing['upiSales'], 300.0);
      expect(closing['otherSales'], 100.0);
      expect(closing['totalCollectedToday'], 1000.0); // Exact! Never 1300 or 1400
      expect(closing['creditSales'], 0.0);

      final collections = await dbHelper.getCollectionsForDate(DateTime.now());
      expect(collections.length, 3);
      for (final row in collections) {
        expect(row['remaining_due'], closeTo(0.0, 0.01));
      }
    });

    test('updateCustomerCreditLimit rejects negative limit', () async {
      final cust = await customerRepo.createCustomer(
        name: 'Credit Test',
        phone: '9777766666',
      );
      await expectLater(
        dbHelper.updateCustomerCreditLimit(cust.id!, -500.0),
        throwsArgumentError,
      );
    });

    test('FIFO DSO avoids M×N Cartesian inflation across multiple bills and payments', () {
      final orders = List.generate(
        5,
        (i) => {
          'customer_id': 1,
          'created_at': DateTime(2026, 1, 1 + i * 10).toIso8601String(),
          'estimate_total': 1000.0,
        },
      );
      final payments = List.generate(
        5,
        (i) => {
          'customer_id': 1,
          'created_at': DateTime(2026, 1, 3 + i * 10).toIso8601String(), // 2 days after each bill
          'amount': 1000.0,
        },
      );

      final dso = DatabaseHelper.computeAverageDsoFromRows(orders, payments);
      expect(dso, isNotNull);
      expect(dso!, closeTo(2.0, 0.05));
    });

    test('getLifetimeBusinessReport filters payWhereClause and leastProducts by staff and location', () async {
      final p1 = await productRepo.upsertProduct(
        const Product(
          name: 'Fast Hammer',
          category: 'Tools',
          isActive: true,
          configuration: ProductConfiguration(steps: [], defaultUnit: 'Piece'),
        ),
      );
      final p2 = await productRepo.upsertProduct(
        const Product(
          name: 'Slow Saw',
          category: 'Tools',
          isActive: true,
          configuration: ProductConfiguration(steps: [], defaultUnit: 'Piece'),
        ),
      );
      final c1 = await customerRepo.createCustomer(
        name: 'Alpha Stores',
        phone: '9666611111',
        address: 'Zone A',
      );
      final c2 = await customerRepo.createCustomer(
        name: 'Beta Stores',
        phone: '9666622222',
        address: 'Zone B',
      );

      final o1 = await orderRepo.createOrder(
        DraftOrder(
          customer: c1,
          items: [
            DraftOrderItem(
              productId: p1,
              itemName: 'Fast Hammer',
              options: const {},
              quantity: 5,
              unit: 'Piece',
              unitPrice: 100,
            ),
          ],
        ),
        estimateTotal: 500,
        takenBy: 'Staff One',
      );
      final o2 = await orderRepo.createOrder(
        DraftOrder(
          customer: c2,
          items: [
            DraftOrderItem(
              productId: p2,
              itemName: 'Slow Saw',
              options: const {},
              quantity: 10,
              unit: 'Piece',
              unitPrice: 200,
            ),
          ],
        ),
        estimateTotal: 2000,
        takenBy: 'Staff Two',
      );

      await dbHelper.recordOrderPayment(orderId: o1, paidAmount: 500, paymentMode: 'cash');
      await dbHelper.recordOrderPayment(orderId: o2, paidAmount: 2000, paymentMode: 'upi');

      final staff1Report = await dbHelper.getLifetimeBusinessReport(staffFilter: 'Staff One');
      expect(staff1Report['totalSales'], 500.0);
      expect(staff1Report['totalCollected'], 500.0);
      final leastForStaff1 =
          (staff1Report['leastProducts'] as List<dynamic>).cast<Map<String, dynamic>>();
      final slowSawQtyForStaff1 = leastForStaff1
          .firstWhere((e) => e['item_name'] == 'Slow Saw')['total_qty'];
      expect((slowSawQtyForStaff1 as num).toDouble(), 0.0);
    });

    test('ShopSyncService.resolveOrCreateOrderCustomer reuses Walk-in/pseudo-phone customer instead of spawning duplicates', () async {
      final db = await dbHelper.database;
      final id1 = await ShopSyncService.resolveOrCreateOrderCustomer(
        db,
        custName: 'Walk-in Customer',
        rawPhone: 'Counter Sale',
      );
      final id2 = await ShopSyncService.resolveOrCreateOrderCustomer(
        db,
        custName: 'Walk-in Customer',
        rawPhone: 'Counter Sale',
      );
      final id3 = await ShopSyncService.resolveOrCreateOrderCustomer(
        db,
        custName: 'Walk-in Customer',
        rawPhone: '',
      );
      expect(id1, equals(id2));
      expect(id2, equals(id3));
    });

    test('SQLite v11 generates UUID cloud_id, manages sync_outbox backoff, and supports batch upsert', () async {
      final cust = await customerRepo.createCustomer(
        name: 'UUID Customer',
        phone: '9112233445',
      );
      expect(cust.cloudId, isNotNull);
      expect(cust.cloudId!.contains('-'), isTrue);

      final count = await productRepo.upsertProductsBatch([
        const Product(
          name: 'Batch Item A',
          category: 'Hardware',
          isActive: true,
          configuration: ProductConfiguration(steps: [], defaultUnit: 'Piece', basePrice: 120),
        ),
        const Product(
          name: 'Batch Item B',
          category: 'Hardware',
          isActive: true,
          configuration: ProductConfiguration(steps: [], defaultUnit: 'Box', basePrice: 450),
        ),
      ]);
      expect(count, 2);

      await ShopSyncService.instance.enqueueOutboxEntry(
        entityType: 'customer',
        localId: cust.id,
        cloudId: cust.cloudId!,
        error: 'Simulated offline error',
      );
      await ShopSyncService.instance.enqueueOutboxEntry(
        entityType: 'customer',
        localId: cust.id,
        cloudId: cust.cloudId!,
        error: 'Retry #1 error',
      );

      final db = await dbHelper.database;
      final outboxRows = await db.query(
        'sync_outbox',
        where: 'cloud_id = ?',
        whereArgs: [cust.cloudId],
      );
      expect(outboxRows.length, 1);
      expect((outboxRows.first['retry_count'] as num).toInt(), 1);
      expect(outboxRows.first['last_error'], 'Retry #1 error');
    });

    test('Typed reporting DTOs, customer-scoped drafts, variant lookup & Excel safety work cleanly', () async {
      // 1. Typed DTO queries
      final c = await customerRepo.createCustomer(name: 'Typed Client', phone: '9887766554');
      final orderId = await orderRepo.createOrder(
        DraftOrder(
          customer: c,
          items: [
            DraftOrderItem(
              productId: null,
              itemName: 'Valve',
              options: const {},
              quantity: 2,
              unit: 'Piece',
              unitPrice: 250,
            ),
          ],
        ),
        estimateTotal: 500,
      );
      await dbHelper.recordOrderPayment(orderId: orderId, paidAmount: 200, paymentMode: 'upi');

      final khataDtos = await dbHelper.getTypedCustomerKhataList();
      expect(khataDtos.any((k) => k.customerId == c.id && k.balanceDue == 300.0), isTrue);
      final ledgerDtos = await dbHelper.getTypedCustomerKhataLedger(c.id!);
      expect(ledgerDtos.any((e) => e.isDebit && !e.isManualDebit), isTrue);
      final closingDto = await dbHelper.getTypedEveningClosingReport(DateTime.now());
      expect(closingDto.upiSales, 200.0);

      // 2. Customer-scoped draft isolation
      final draftService = DraftOrderService();
      await draftService.saveDraft(
        DraftOrder(
          customer: c,
          items: [
            DraftOrderItem(
              productId: null,
              itemName: 'Item For C1',
              options: const {},
              quantity: 1,
              unit: 'Piece',
            ),
          ],
        ),
        customerId: c.id,
      );
      final c2 = Customer(id: (c.id ?? 1) + 99, name: 'Other Customer', createdAt: DateTime.now());
      expect(await draftService.getDraft(customerId: c2.id), isNull);
      expect((await draftService.getDraft(customerId: c.id))?.items.first.itemName, 'Item For C1');

      // 3. Case-insensitive variant price lookup
      const config = ProductConfiguration(
        steps: [],
        variantPrices: {'Red • 1L': 320.0},
      );
      expect(config.lookupVariantPrice('red • 1l'), 320.0);

      // 4. Rejects binary .xls and handles attribute order in .xlsx XML fallback
      final badXls = File(p.join(tempDir.path, 'legacy.xls'));
      await badXls.writeAsBytes([0xD0, 0xCF, 0x11, 0xE0, 0xA1, 0xB1, 0x1A, 0xE1]);
      await expectLater(
        ExcelProductService.parseProductsFromFile(badXls),
        throwsFormatException,
      );

      final archive = Archive();
      final ssBytes = utf8.encode('<sst><si><t>Heavy Hinge</t></si><si><t>Product Name</t></si></sst>');
      final sheetBytes = utf8.encode(
        '<worksheet><sheetData>'
        '<row r="1"><c t="s" r="A1"><v>1</v></c></row>'
        '<row r="2"><c t="s" r="A2"><v>0</v></c></row>'
        '</sheetData></worksheet>',
      );
      archive.addFile(ArchiveFile('xl/sharedStrings.xml', ssBytes.length, ssBytes));
      archive.addFile(ArchiveFile('xl/worksheets/sheet1.xml', sheetBytes.length, sheetBytes));
      final zipBytes = ZipEncoder().encode(archive)!;
      final parsedRows = ExcelProductService.parseXlsxArchive(zipBytes);
      expect(parsedRows.length, 2);
      expect(parsedRows[1][0], 'Heavy Hinge');
    });

    test('ArchiveService downloads and caches GCS archives when base64 payload is empty', () async {
      await customerRepo.createCustomer(name: 'GCS Restored Buyer', phone: '9000112233');
      final db = await dbHelper.database;
      final cols = await db.rawQuery('PRAGMA table_info(storage_archives)');
      expect(cols.map((r) => r['name']).toSet(), contains('gcs_path'));

      final archiveJson = jsonEncode({
        'archiveId': 'arch_gcs_test',
        'records': [
          {
            'collection': 'orders',
            'docId': 'ord_gcs_001',
            'data': {
              'order_number': 77,
              'customer_name_snapshot': 'GCS Restored Buyer',
              'customer_phone': '9000112233',
              'estimate_total': 1850.0,
              'paid_amount': 1850.0,
              'payment_mode': 'cash',
              'payment_status': 'paid',
              'status': 'COMPLETED',
              'created_at': DateTime(2026, 2, 1).toIso8601String(),
              'items': [
                {
                  'item_name': 'Brass Valve',
                  'unit': 'Piece',
                  'unit_price': 185.0,
                  'quantity_ordered': 10.0,
                }
              ],
            },
          }
        ],
      });
      final gzipBytes = Uint8List.fromList(GZipEncoder().encode(utf8.encode(archiveJson))!);

      await db.insert('storage_archives', {
        'archive_id': 'arch_gcs_test',
        'rule_applied': 'age_180d',
        'date_range_start': DateTime(2025, 1, 1).toIso8601String(),
        'date_range_end': DateTime(2026, 1, 1).toIso8601String(),
        'record_count': 1,
        'archived_doc_ids_json': jsonEncode(['ord_gcs_001']),
        'checksum': null,
        'gcs_path': 'shops/TEST/archives/arch_gcs_test.json.gz',
        'compressed_gzip_base64': '',
        'verified': 1,
        'restored_at': null,
        'created_at': DateTime(2026, 2, 2).toIso8601String(),
      });

      final service = ArchiveService(
        dbHelper: dbHelper,
        gcsBytesFetcher: (path) async {
          expect(path, 'shops/TEST/archives/arch_gcs_test.json.gz');
          return gzipBytes;
        },
      );

      final restoredCount = await service.restoreArchive('arch_gcs_test', syncToCloud: false);
      expect(restoredCount, 1);

      final orders = await db.query(
        'orders',
        where: 'cloud_order_id = ?',
        whereArgs: ['ord_gcs_001'],
      );
      expect(orders.length, 1);
      expect(orders.first['customer_name_snapshot'], 'GCS Restored Buyer');

      final cachedArchive = await db.query(
        'storage_archives',
        where: 'archive_id = ?',
        whereArgs: ['arch_gcs_test'],
      );
      expect(
        (cachedArchive.first['compressed_gzip_base64'] as String).isNotEmpty,
        isTrue,
      );
    });

    test('resolveOrCreateOrderCustomer assigns UUIDv4 cloud_id and recovery getters default safely', () async {
      final db = await dbHelper.database;
      final cid = await ShopSyncService.resolveOrCreateOrderCustomer(
        db,
        custName: 'New Sync Buyer',
        rawPhone: '9888777666',
      );
      final rows = await db.query('customers', where: 'id = ?', whereArgs: [cid]);
      expect(rows.length, 1);
      final cloudId = rows.first['cloud_id'] as String?;
      expect(cloudId, isNotNull);
      expect(
        RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$')
            .hasMatch(cloudId!),
        isTrue,
      );
      expect(rows.first['is_active'], 1);
      expect(ShopSyncService.instance.isAnonymousSession, isTrue);
      expect(ShopSyncService.instance.hasRecoveryAccountLinked, isFalse);
      expect(ShopSyncService.instance.recoveryAccountLabel, isNull);
    });

    test('ArchiveService.decodeArchiveRecords resolves GCS-offloaded preview records cleanly', () async {
      final db = await dbHelper.database;
      final archiveJson = jsonEncode({
        'records': [
          {
            'collection': 'orders',
            'docId': 'ord_gcs_preview_1',
            'data': {'customer_name_snapshot': 'Preview Buyer'},
          }
        ],
      });
      final gzipBytes = Uint8List.fromList(GZipEncoder().encode(utf8.encode(archiveJson))!);

      await db.insert('storage_archives', {
        'archive_id': 'arch_gcs_preview',
        'rule_applied': 'age_180d',
        'date_range_start': DateTime(2025, 1, 1).toIso8601String(),
        'date_range_end': DateTime(2026, 1, 1).toIso8601String(),
        'record_count': 1,
        'archived_doc_ids_json': jsonEncode(['ord_gcs_preview_1']),
        'gcs_path': 'shops/TEST/archives/arch_gcs_preview.json.gz',
        'compressed_gzip_base64': '',
        'verified': 1,
        'created_at': DateTime(2026, 2, 2).toIso8601String(),
      });

      final service = ArchiveService(
        dbHelper: dbHelper,
        gcsBytesFetcher: (path) async => gzipBytes,
      );
      final arch = StorageArchiveRecord(
        archiveId: 'arch_gcs_preview',
        ruleApplied: 'age_180d',
        dateRangeStart: DateTime(2025, 1, 1),
        dateRangeEnd: DateTime(2026, 1, 1),
        recordCount: 1,
        archivedDocIds: const ['ord_gcs_preview_1'],
        gcsPath: 'shops/TEST/archives/arch_gcs_preview.json.gz',
        compressedGzipBase64: '',
        verified: true,
        createdAt: DateTime(2026, 2, 2),
      );
      final decoded = await service.decodeArchiveRecords(arch);
      expect(decoded.length, 1);
      expect(decoded.first['docId'], 'ord_gcs_preview_1');
    });

    test('getOrderDetails hydrates batched options and deleted orders/customers stay excluded', () async {
      final db = await dbHelper.database;
      final activeCust = await customerRepo.createCustomer(
        name: 'Active Hardware',
        phone: '9876500001',
      );
      final deletedCust = await customerRepo.createCustomer(
        name: 'Deleted Hardware',
        phone: '9876500002',
      );

      // Soft-delete second customer
      await db.update(
        'customers',
        {
          'is_active': 0,
          'deleted_at': DateTime.now().toIso8601String(),
        },
        where: 'id = ?',
        whereArgs: [deletedCust.id],
      );

      // Soft-deleted phone must not match active lookups
      final deletedMatch =
          await dbHelper.findCustomerIdByNormalizedPhone(db, '9876500002');
      expect(deletedMatch, isNull);

      final resolvedNew = await ShopSyncService.resolveOrCreateOrderCustomer(
        db,
        custName: 'Deleted Hardware',
        rawPhone: '9876500002',
      );
      expect(resolvedNew, isNot(deletedCust.id));

      // Create multi-item order with options to test batched option loading
      final orderId1 = await orderRepo.createOrder(
        DraftOrder(
          customer: activeCust,
          items: [
            DraftOrderItem(
              itemName: 'Paint 1',
              options: const {'brand': 'Asian', 'colour': 'White'},
              quantity: 2,
              unit: 'Litre',
              unitPrice: 500.0,
            ),
            DraftOrderItem(
              itemName: 'Brush',
              options: const {'size': '2 inch'},
              quantity: 3,
              unit: 'Piece',
              unitPrice: 50.0,
            ),
          ],
        ),
      );

      final details = await orderRepo.getOrderDetails(orderId1);
      expect(details, isNotNull);
      expect(details!.items.length, 2);
      expect(details.items[0].options.length, 2);
      expect(details.items[1].options.single.optionValue, '2 inch');

      // Soft-delete an order and confirm it is excluded from Khata, Procurement & Analytics
      final deletedOrderId = await orderRepo.createOrder(
        DraftOrder(
          customer: activeCust,
          items: [
            DraftOrderItem(
              itemName: 'Deleted Cement',
              options: const {},
              quantity: 4,
              unit: 'Bag',
              unitPrice: 400.0,
            ),
          ],
        ),
      );
      await db.update(
        'orders',
        {'deleted_at': DateTime.now().toIso8601String()},
        where: 'id = ?',
        whereArgs: [deletedOrderId],
      );

      final balance = await dbHelper.getCustomerKhataBalance(activeCust.id!);
      expect(balance, closeTo(1150.0, 0.01));

      final evening = await dbHelper.getEveningClosingReport(DateTime.now());
      expect((evening['totalSales'] as num).toDouble(), closeTo(1150.0, 0.01));

      final lifetime = await dbHelper.getLifetimeBusinessReport();
      expect((lifetime['totalSales'] as num).toDouble(), closeTo(1150.0, 0.01));
    });
  });
}
