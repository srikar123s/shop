import 'dart:async';

import 'package:shop/database/database_helper.dart';
import 'package:shop/models/customer.dart';
import 'package:shop/services/shop_sync_service.dart';

class CustomerRepository {
  const CustomerRepository(this._databaseHelper);

  final DatabaseHelper _databaseHelper;

  Future<List<Customer>> searchCustomers(String query) async {
    final db = await _databaseHelper.database;
    final normalized = query.trim();
    final result = await db.query(
      'customers',
      where: normalized.isEmpty ? null : 'name LIKE ? OR phone LIKE ? OR address LIKE ?',
      whereArgs: normalized.isEmpty ? null : ['%$normalized%', '%$normalized%', '%$normalized%'],
      orderBy: 'name COLLATE NOCASE ASC',
    );
    return result.map(Customer.fromMap).toList();
  }

  static String mergePhoneNumbers(String? existingPhone, String? newPhone) {
    final set = <String>{};
    if (existingPhone != null && existingPhone.trim().isNotEmpty) {
      set.addAll(existingPhone
          .split(RegExp(r'[,/;&|\n]+'))
          .map((p) => p.trim())
          .where((p) => p.isNotEmpty));
    }
    if (newPhone != null && newPhone.trim().isNotEmpty) {
      set.addAll(newPhone
          .split(RegExp(r'[,/;&|\n]+'))
          .map((p) => p.trim())
          .where((p) => p.isNotEmpty));
    }
    return set.join(', ');
  }

  Future<Customer?> findByNameAndPhone(String name, [dynamic phone]) async {
    final normalizedName = name.trim().toLowerCase();
    final List<String> inputNumbers = [];

    if (phone is List<String>) {
      for (final p in phone) {
        final clean = p.replaceAll(RegExp(r'[^0-9]'), '').trim();
        if (clean.length >= 6) inputNumbers.add(clean);
      }
    } else if (phone is String && phone.trim().isNotEmpty) {
      inputNumbers.addAll(
        phone
            .split(RegExp(r'[,/;&|\n]+'))
            .map((p) => p.replaceAll(RegExp(r'[^0-9]'), '').trim())
            .where((p) => p.length >= 6),
      );
    }

    // 1. Check if any phone number belongs to an existing customer
    for (final cleanDigits in inputNumbers) {
      final byPhone = await findByPhone(cleanDigits);
      if (byPhone != null) return byPhone;
    }

    // 2. Check by exact name (case-insensitive) ONLY if no phone numbers were provided.
    // If phone numbers were provided and none matched, do NOT conflate different customers
    // who happen to share a common name (e.g. two unrelated customers named "Ramesh").
    if (inputNumbers.isEmpty) {
      final db = await _databaseHelper.database;
      final result = await db.query(
        'customers',
        where: 'LOWER(TRIM(name)) = ?',
        whereArgs: [normalizedName],
        limit: 1,
      );
      if (result.isNotEmpty) {
        return Customer.fromMap(result.first);
      }
    }
    return null;
  }

  Future<Customer> createCustomer({
    required String name,
    String? phone,
    String? address,
    double creditLimit = 0.0,
  }) async {
    final cleanPhone = phone?.trim().isEmpty == true ? null : phone?.trim();
    final existing = await findByNameAndPhone(name, cleanPhone);
    if (existing != null) {
      final mergedPhone = mergePhoneNumbers(existing.phone, cleanPhone);
      final newAddress = (address != null && address.trim().isNotEmpty)
          ? address.trim()
          : existing.address;
      final newCredit = creditLimit > 0 ? creditLimit : existing.creditLimit;

      if (mergedPhone != (existing.phone ?? '') ||
          newAddress != existing.address ||
          newCredit != existing.creditLimit) {
        await updateCustomer(
          id: existing.id!,
          name: name.trim().isNotEmpty ? name.trim() : existing.name,
          phone: mergedPhone.isNotEmpty ? mergedPhone : null,
          address: newAddress,
          creditLimit: newCredit,
        );
        return (await getCustomerById(existing.id!))!;
      }
      return existing;
    }

    final db = await _databaseHelper.database;
    final customer = Customer(
      name: name.trim(),
      phone: cleanPhone,
      address: address?.trim().isEmpty == true ? null : address?.trim(),
      creditLimit: creditLimit,
      createdAt: DateTime.now(),
    );

    final id = await db.insert('customers', customer.toMap());
    final savedCustomer = customer.copyWith(id: id);
    unawaited(ShopSyncService.instance.syncCustomer(savedCustomer));
    return savedCustomer;
  }

  Future<void> updateCustomer({
    required int id,
    required String name,
    String? phone,
    String? address,
    double? creditLimit,
  }) async {
    final db = await _databaseHelper.database;
    final updates = <String, Object?>{
      'name': name.trim(),
      'phone': phone?.trim().isEmpty == true ? null : phone?.trim(),
      'address': address?.trim().isEmpty == true ? null : address?.trim(),
    };
    if (creditLimit != null) {
      updates['credit_limit'] = creditLimit;
    }

    await db.update(
      'customers',
      updates,
      where: 'id = ?',
      whereArgs: [id],
    );
    // Also update order customer_name_snapshot for consistency
    await db.update(
      'orders',
      {'customer_name_snapshot': name.trim()},
      where: 'customer_id = ?',
      whereArgs: [id],
    );

    unawaited(getCustomerById(id).then((c) {
      if (c != null) ShopSyncService.instance.syncCustomer(c);
    }));
  }

  Future<void> deleteCustomer(int id) async {
    final balance = await _databaseHelper.getCustomerKhataBalance(id);
    if (balance.abs() > 0.01) {
      throw Exception('Cannot delete customer with active Khata balance of ₹${balance.toStringAsFixed(2)}');
    }
    final db = await _databaseHelper.database;
    await db.delete(
      'customers',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<Customer?> getCustomerById(int id) async {
    final db = await _databaseHelper.database;
    final result = await db.query(
      'customers',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (result.isEmpty) {
      return null;
    }
    return Customer.fromMap(result.first);
  }

  Future<Customer?> findByPhone(String phone) async {
    final cleanDigits = phone.replaceAll(RegExp(r'[^0-9]'), '').trim();
    if (cleanDigits.isEmpty) return null;
    final db = await _databaseHelper.database;
    // Direct filtered query on phone substring to avoid full-table scan in Dart memory
    final candidates = await db.query(
      'customers',
      where: 'phone LIKE ?',
      whereArgs: ['%$cleanDigits%'],
      limit: 25,
    );
    for (final row in candidates) {
      final c = Customer.fromMap(row);
      for (final p in c.phoneNumbers) {
        final pDigits = p.replaceAll(RegExp(r'[^0-9]'), '').trim();
        if (pDigits.isNotEmpty &&
            (pDigits == cleanDigits ||
                pDigits.endsWith(cleanDigits) ||
                cleanDigits.endsWith(pDigits))) {
          return c;
        }
      }
    }
    return null;
  }
}
