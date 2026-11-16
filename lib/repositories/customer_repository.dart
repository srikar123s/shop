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
      where: normalized.isEmpty ? null : 'name LIKE ?',
      whereArgs: normalized.isEmpty ? null : ['%$normalized%'],
      orderBy: 'name COLLATE NOCASE ASC',
    );
    return result.map(Customer.fromMap).toList();
  }

  Future<Customer?> findByNameAndPhone(String name, String? phone) async {
    final cleanPhone = phone?.replaceAll(RegExp(r'[^0-9+]'), '').trim();
    if (cleanPhone != null && cleanPhone.isNotEmpty) {
      final byPhone = await findByPhone(cleanPhone);
      if (byPhone != null) return byPhone;
    }
    final db = await _databaseHelper.database;
    final result = await db.query(
      'customers',
      where: 'LOWER(TRIM(name)) = ?',
      whereArgs: [name.trim().toLowerCase()],
      limit: 1,
    );
    if (result.isNotEmpty) {
      final c = Customer.fromMap(result.first);
      if (cleanPhone == null ||
          cleanPhone.isEmpty ||
          c.phone == null ||
          c.phone!.trim().isEmpty ||
          c.phone!.replaceAll(RegExp(r'[^0-9+]'), '').trim() == cleanPhone) {
        return c;
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
      if ((cleanPhone != null && cleanPhone != existing.phone) ||
          (address != null &&
              address.trim().isNotEmpty &&
              address != existing.address) ||
          (creditLimit > 0 && creditLimit != existing.creditLimit)) {
        await updateCustomer(
          id: existing.id!,
          name: name.trim().isNotEmpty ? name.trim() : existing.name,
          phone: cleanPhone ?? existing.phone,
          address: address ?? existing.address,
          creditLimit: creditLimit > 0 ? creditLimit : existing.creditLimit,
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
    final normalized = phone.trim();
    if (normalized.isEmpty) return null;
    final db = await _databaseHelper.database;
    final result = await db.query(
      'customers',
      where: 'phone = ?',
      whereArgs: <Object?>[normalized],
      limit: 1,
    );
    return result.isEmpty ? null : Customer.fromMap(result.first);
  }
}
