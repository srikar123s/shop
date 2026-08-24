import 'package:shop/database/database_helper.dart';
import 'package:shop/models/customer.dart';

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

  Future<Customer> createCustomer({
    required String name,
    String? phone,
    String? address,
  }) async {
    final db = await _databaseHelper.database;
    final customer = Customer(
      name: name.trim(),
      phone: phone?.trim().isEmpty == true ? null : phone?.trim(),
      address: address?.trim().isEmpty == true ? null : address?.trim(),
      createdAt: DateTime.now(),
    );

    final id = await db.insert('customers', customer.toMap());
    return customer.copyWith(id: id);
  }

  Future<void> updateCustomer({
    required int id,
    required String name,
    String? phone,
    String? address,
  }) async {
    final db = await _databaseHelper.database;
    await db.update(
      'customers',
      {
        'name': name.trim(),
        'phone': phone?.trim().isEmpty == true ? null : phone?.trim(),
        'address': address?.trim().isEmpty == true ? null : address?.trim(),
      },
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
