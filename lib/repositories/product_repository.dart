import 'package:shop/database/database_helper.dart';
import 'package:shop/models/product.dart';

class ProductRepository {
  const ProductRepository(this._databaseHelper);

  final DatabaseHelper _databaseHelper;

  Future<List<Product>> searchProducts(String query) async {
    final db = await _databaseHelper.database;
    final normalized = query.trim();
    final result = await db.query(
      'products',
      where: normalized.isEmpty
          ? 'is_active = 1'
          : '''is_active = 1 AND
            (name LIKE ? OR category LIKE ? OR configuration LIKE ?)''',
      whereArgs: normalized.isEmpty
          ? null
          : <Object?>['%$normalized%', '%$normalized%', '%$normalized%'],
      orderBy: 'name COLLATE NOCASE ASC',
    );
    return result.map(Product.fromMap).toList();
  }

  Future<List<Product>> getAllProducts({bool includeInactive = true}) async {
    final db = await _databaseHelper.database;
    final result = await db.query(
      'products',
      where: includeInactive ? null : 'is_active = 1',
      orderBy: 'name COLLATE NOCASE ASC',
    );
    return result.map(Product.fromMap).toList();
  }

  /// Returns products ordered most often, based on saved order history.
  Future<List<Product>> getFrequentlyUsedProducts({int limit = 4}) async {
    final db = await _databaseHelper.database;
    final result = await db.rawQuery('''
      SELECT products.*
      FROM products
      INNER JOIN order_items ON order_items.product_id = products.id
      WHERE products.is_active = 1
      GROUP BY products.id
      ORDER BY COUNT(order_items.id) DESC, products.name COLLATE NOCASE ASC
      LIMIT ?
    ''', <Object?>[limit]);
    return result.map(Product.fromMap).toList();
  }

  Future<Product?> getProductById(int id) async {
    final db = await _databaseHelper.database;
    final result = await db.query(
      'products',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (result.isEmpty) {
      return null;
    }
    return Product.fromMap(result.first);
  }

  Future<int> upsertProduct(Product product) async {
    final db = await _databaseHelper.database;
    if (product.id == null) {
      return db.insert('products', {
        ...product.toMap(),
        'created_at': DateTime.now().toIso8601String(),
      });
    }
    await db.update(
      'products',
      product.toMap(),
      where: 'id = ?',
      whereArgs: [product.id],
    );
    return product.id!;
  }

  Future<void> setProductActive(int id, bool isActive) async {
    final db = await _databaseHelper.database;
    await db.update(
      'products',
      {'is_active': isActive ? 1 : 0},
      where: 'id = ?',
      whereArgs: [id],
    );
  }
}
