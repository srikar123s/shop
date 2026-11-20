import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:shop/models/customer.dart';
import 'package:shop/repositories/customer_repository.dart';
import 'package:shop/services/excel_customer_service.dart';
import 'package:shop/services/excel_product_service.dart';

class MockCustomerRepository implements CustomerRepository {
  final List<Customer> customers = [];

  @override
  Future<Customer> createCustomer({
    required String name,
    String? phone,
    String? address,
    double creditLimit = 0.0,
  }) async {
    final customer = Customer(
      id: customers.length + 1,
      name: name,
      phone: phone,
      address: address,
      creditLimit: creditLimit,
      createdAt: DateTime.now(),
    );
    customers.add(customer);
    return customer;
  }

  @override
  Future<Customer?> findByNameAndPhone(String name, [dynamic phone]) async {
    final lowerName = name.trim().toLowerCase();
    final List<String> phones = [];
    if (phone is List<String>) {
      phones.addAll(phone);
    } else if (phone is String && phone.isNotEmpty) {
      phones.addAll(Customer.extractNumbers(phone));
    }
    for (final c in customers) {
      if (c.name.trim().toLowerCase() == lowerName) return c;
      if (phones.isNotEmpty) {
        final existingNums = c.phoneNumbers;
        for (final p in phones) {
          if (existingNums.contains(p)) return c;
        }
      }
    }
    return null;
  }

  @override
  Future<Customer?> findByPhone(String phone) async {
    return customers.cast<Customer?>().firstWhere(
      (c) => c?.phoneNumbers.contains(phone) ?? false,
      orElse: () => null,
    );
  }

  @override
  Future<Customer?> getCustomerById(int id) async => null;

  @override
  Future<List<Customer>> searchCustomers(String query) async => customers;

  @override
  Future<void> updateCustomer({
    required int id,
    required String name,
    String? phone,
    String? address,
    double? creditLimit,
  }) async {}

  @override
  Future<void> deleteCustomer(int id) async {}
}

void main() {
  group('Customer Phone and Excel Import Tests', () {
    test('Customer.extractNumbers parses various delimiters and formats', () {
      // Single number
      expect(Customer.extractNumbers('9876543210'), equals(['9876543210']));

      // Comma separated
      expect(
        Customer.extractNumbers('9876543210, 9123456789'),
        equals(['9876543210', '9123456789']),
      );

      // Slash separated
      expect(
        Customer.extractNumbers('9876543210 / 9123456789'),
        equals(['9876543210', '9123456789']),
      );

      // Semicolon and pipe separated
      expect(
        Customer.extractNumbers('9876543210; 9123456789 | 9345678901'),
        equals(['9876543210', '9123456789', '9345678901']),
      );

      // Deduplication
      expect(
        Customer.extractNumbers('9876543210, 9876543210'),
        equals(['9876543210']),
      );

      // Customer model helpers
      final customer = Customer(
        name: 'Test Shop',
        phone: '9876543210, 9123456789',
        createdAt: DateTime.now(),
      );
      expect(customer.hasMultiplePhones, isTrue);
      expect(customer.primaryPhone, equals('9876543210'));
      expect(customer.displayPhone, equals('9876543210 • 9123456789'));
    });

    test('ExcelCustomerService parses rows with multi-phone and balance detection', () async {
      final repo = MockCustomerRepository();
      // Pre-add one customer to test matching
      await repo.createCustomer(
        name: 'Existing Store',
        phone: '9998887770',
        address: 'Old Town',
      );

      final rows = [
        ['Shop Name', 'Phone 1', 'Phone 2', 'Location', 'Present Balance', 'Credit Limit'],
        ['Balaji Traders', '9876543210.0', '9123456789', 'Main Market', '12500 Dr', '50000'],
        ['Sri Sai Kirana', '9440123456, 9440998877', '', 'Gandhi Road', '₹ 4,200', '25000'],
        ['Existing Store', '9998887770', '9888777666', 'New Market', '3500', '0'],
      ];

      final results = await ExcelCustomerService.parseCustomersFromRows(rows, repo);

      expect(results.length, equals(3));

      // 1. Balaji Traders: multi-phone from separate columns, cleaned trailing .0, balance 12500
      final balaji = results[0];
      expect(balaji.name, equals('Balaji Traders'));
      expect(balaji.phoneNumbers, equals(['9876543210', '9123456789']));
      expect(balaji.phone, equals('9876543210, 9123456789'));
      expect(balaji.hasMultiplePhones, isTrue);
      expect(balaji.address, equals('Main Market'));
      expect(balaji.presentBalance, equals(12500.0));
      expect(balaji.creditLimit, equals(50000.0));
      expect(balaji.isExisting, isFalse);

      // 2. Sri Sai Kirana: multi-phone from single comma cell, balance ₹ 4,200
      final sriSai = results[1];
      expect(sriSai.name, equals('Sri Sai Kirana'));
      expect(sriSai.phoneNumbers, equals(['9440123456', '9440998877']));
      expect(sriSai.hasMultiplePhones, isTrue);
      expect(sriSai.presentBalance, equals(4200.0));
      expect(sriSai.creditLimit, equals(25000.0));
      expect(sriSai.isExisting, isFalse);

      // 3. Existing Store: matched against mock repository
      final existing = results[2];
      expect(existing.name, equals('Existing Store'));
      expect(existing.isExisting, isTrue);
      expect(existing.phoneNumbers, containsAll(['9998887770', '9888777666']));
    });
  });

  test('excel file parsing unit normalization and combination prices', () async {
    final file = File(r'c:\Users\srikar\OneDrive\Desktop\shop\simple_shop_product_catalog_with_unit_conversion.xlsx');
    if (!file.existsSync()) {
      return;
    }
    final products = await ExcelProductService.parseProductsFromFile(file);

    expect(products.isNotEmpty, isTrue);

    final weldingRod = products.firstWhere((p) => p.name == 'Welding Rod');
    expect(weldingRod.configuration.unitOptions, containsAll(['Box', 'Piece']));
    expect(weldingRod.configuration.unitOptions.contains('Pieces'), isFalse);
    expect(weldingRod.configuration.variantPrices.isNotEmpty, isTrue);
  });
}
