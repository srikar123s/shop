import 'package:flutter/foundation.dart';
import 'dart:async';

import 'package:shop/database/database_helper.dart';
import 'package:shop/models/customer.dart';
import 'package:shop/services/shop_sync_service.dart';

class CustomerRepository {
  const CustomerRepository(this._databaseHelper);

  final DatabaseHelper _databaseHelper;

  Future<List<Customer>> searchCustomers(
    String query, {
    int? limit,
    int? offset,
  }) async {
    final db = await _databaseHelper.database;
    final normalized = query.trim();
    final result = await db.query(
      'customers',
      where: normalized.isEmpty
          ? 'is_active = 1 AND deleted_at IS NULL'
          : 'is_active = 1 AND deleted_at IS NULL AND (name LIKE ? OR phone LIKE ? OR address LIKE ?)',
      whereArgs: normalized.isEmpty
          ? null
          : ['%$normalized%', '%$normalized%', '%$normalized%'],
      orderBy: 'name COLLATE NOCASE ASC',
      limit: limit,
      offset: offset,
    );
    return result.map(Customer.fromMap).toList();
  }

  static String mergePhoneNumbers(String? existingPhone, String? newPhone) {
    final seenCanonical = <String>{};
    final merged = <String>[];

    void addRaw(String? raw) {
      if (raw == null || raw.trim().isEmpty) return;
      for (final p in raw.split(RegExp(r'[,/;&|\n]+'))) {
        final trimmed = p.trim();
        if (trimmed.isEmpty) continue;
        final canonical = Customer.normalizePhoneDigits(trimmed);
        final key = canonical.length >= 6 ? canonical : trimmed;
        if (seenCanonical.add(key)) {
          merged.add(trimmed);
        }
      }
    }

    addRaw(existingPhone);
    addRaw(newPhone);
    return merged.join(', ');
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
        where: 'is_active = 1 AND LOWER(TRIM(name)) = ?',
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
    final trimmedName = name.trim();
    if (trimmedName.isEmpty) {
      throw ArgumentError('Customer name cannot be empty');
    }
    final cleanPhone = phone?.trim().isEmpty == true ? null : phone?.trim();
    final existing = await findByNameAndPhone(trimmedName, cleanPhone);
    if (existing != null) {
      final mergedPhone = mergePhoneNumbers(existing.phone, cleanPhone);
      final newAddress = (address != null && address.trim().isNotEmpty)
          ? address.trim()
          : existing.address;
      final newCredit = creditLimit > 0 ? creditLimit : existing.creditLimit;

      // Only update name if existing name was blank or matches case-insensitively
      final shouldUpdateName = existing.name.trim().isEmpty ||
          existing.name.trim().toLowerCase() == trimmedName.toLowerCase();
      final targetName = shouldUpdateName ? trimmedName : existing.name;

      if (mergedPhone != (existing.phone ?? '') ||
          newAddress != existing.address ||
          newCredit != existing.creditLimit ||
          (shouldUpdateName && targetName != existing.name)) {
        await updateCustomer(
          id: existing.id!,
          name: targetName,
          phone: mergedPhone.isNotEmpty ? mergedPhone : null,
          address: newAddress,
          creditLimit: newCredit,
        );
        final updated = await getCustomerById(existing.id!);
        return updated ?? existing;
      }
      return existing;
    }

    final db = await _databaseHelper.database;
    final now = DateTime.now();
    final customer = Customer(
      cloudId: DatabaseHelper.generateUuidV4(),
      name: trimmedName,
      phone: cleanPhone,
      address: address?.trim().isEmpty == true ? null : address?.trim(),
      creditLimit: creditLimit,
      isActive: true,
      createdAt: now,
      updatedAt: now,
    );

    final id = await db.insert('customers', customer.toMap());
    final savedCustomer = customer.copyWith(id: id);
    unawaited(ShopSyncService.instance.syncCustomer(savedCustomer).catchError((e) {
      debugPrint('Error syncing created customer: $e');
    }));
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
    final existing = await getCustomerById(id);
    final nowIso = DateTime.now().toIso8601String();
    final updates = <String, Object?>{
      'name': name.trim(),
      'phone': phone?.trim().isEmpty == true ? null : phone?.trim(),
      'address': address?.trim().isEmpty == true ? null : address?.trim(),
      'updated_at': nowIso,
    };
    if (existing != null && (existing.cloudId == null || existing.cloudId!.isEmpty)) {
      updates['cloud_id'] = DatabaseHelper.generateUuidV4();
    }
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
      {'customer_name_snapshot': name.trim(), 'updated_at': nowIso},
      where: 'customer_id = ?',
      whereArgs: [id],
    );

    unawaited(getCustomerById(id).then((c) {
      if (c != null) {
        ShopSyncService.instance.syncCustomer(c).catchError((e) {
          debugPrint('Error syncing updated customer: $e');
        });
      }
    }).catchError((e) {
      debugPrint('Error fetching updated customer for sync: $e');
    }));
  }

  Future<void> deleteCustomer(int id) async {
    final balance = await _databaseHelper.getCustomerKhataBalance(id);
    if (balance.abs() > 0.01) {
      throw Exception('Cannot delete customer with active Khata balance of ₹${balance.toStringAsFixed(2)}');
    }
    final db = await _databaseHelper.database;
    String? cloudId;
    bool softArchived = false;
    await db.transaction((txn) async {
      final custRows = await txn.query(
        'customers',
        columns: ['cloud_id'],
        where: 'id = ?',
        whereArgs: [id],
        limit: 1,
      );
      cloudId = custRows.isNotEmpty ? custRows.first['cloud_id'] as String? : null;

      final orderCheck = await txn.query(
        'orders',
        columns: ['id'],
        where: 'customer_id = ?',
        whereArgs: [id],
        limit: 1,
      );
      final payCheck = await txn.query(
        'customer_payments',
        columns: ['id'],
        where: 'customer_id = ?',
        whereArgs: [id],
        limit: 1,
      );
      final nowIso = DateTime.now().toIso8601String();
      if (orderCheck.isEmpty && payCheck.isEmpty) {
        await txn.delete(
          'customers',
          where: 'id = ?',
          whereArgs: [id],
        );
      } else {
        softArchived = true;
        // Archive/hide settled customer record so historical orders keep valid FK links
        await txn.update(
          'customers',
          {
            'is_active': 0,
            'deleted_at': nowIso,
            'updated_at': nowIso,
          },
          where: 'id = ?',
          whereArgs: [id],
        );
      }
    });

    if (softArchived) {
      final archived = await getCustomerById(id);
      if (archived != null) {
        unawaited(ShopSyncService.instance.syncCustomer(archived).catchError((e) {
          debugPrint('Error syncing archived customer: $e');
        }));
      }
    } else if (cloudId != null && cloudId!.isNotEmpty) {
      unawaited(ShopSyncService.instance.deleteCustomerFromCloud(cloudId!).catchError((e) {
        debugPrint('Error propagating customer delete tombstone: $e');
      }));
    }
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
    final canonical = Customer.normalizePhoneDigits(phone);
    if (canonical.length < 6) return null;
    final db = await _databaseHelper.database;
    final tail = canonical.length >= 6
        ? canonical.substring(canonical.length - 6)
        : canonical;
    // Strip spaces, dashes, and '+' in SQL so '+91 93924 49356' matches '9392449356'
    final candidates = await db.query(
      'customers',
      where:
          "is_active = 1 AND REPLACE(REPLACE(REPLACE(COALESCE(phone, ''), ' ', ''), '-', ''), '+', '') LIKE ?",
      whereArgs: ['%$tail%'],
      limit: 50,
    );
    for (final row in candidates) {
      final c = Customer.fromMap(row);
      for (final p in c.phoneNumbers) {
        if (Customer.phonesMatch(p, phone)) {
          return c;
        }
      }
    }
    return null;
  }
}
