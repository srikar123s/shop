import 'dart:async';

import 'package:shop/database/database_helper.dart';
import 'package:shop/models/product.dart';
import 'package:shop/services/shop_sync_service.dart';

class ProductRepository {
  const ProductRepository(this._databaseHelper);

  final DatabaseHelper _databaseHelper;

  Future<List<Product>> searchProducts(String query) async {
    final db = await _databaseHelper.database;
    final normalized = query.trim().toLowerCase();
    final result = await db.query(
      'products',
      where: normalized.isEmpty
          ? 'is_active = 1'
          : '''is_active = 1 AND
            (LOWER(name) LIKE ? OR LOWER(category) LIKE ? OR LOWER(configuration) LIKE ?)''',
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
    final trimmedName = product.name.trim();
    final lowerName = trimmedName.toLowerCase();

    // 1. If product ID is explicitly specified, update by ID
    if (product.id != null) {
      final mapData = product.toMap();
      mapData['price_updated_at'] = DateTime.now().toIso8601String();
      await db.update(
        'products',
        mapData,
        where: 'id = ?',
        whereArgs: [product.id],
      );
      return product.id!;
    }

    // 2. Check if product with same or singular/plural name already exists
    final existingRows = await db.query('products');
    int? matchedId;
    for (final row in existingRows) {
      final dbName = (row['name'] as String).trim().toLowerCase();
      if (dbName == lowerName) {
        matchedId = row['id'] as int;
        break;
      }
      // Check singular/plural match (e.g., Paint vs Paints, Welding Rod vs Welding Rods)
      if ('${dbName}s' == lowerName ||
          '${lowerName}s' == dbName ||
          (dbName.length > 3 &&
              lowerName.length > 3 &&
              dbName.replaceAll('s', '') == lowerName.replaceAll('s', ''))) {
        matchedId = row['id'] as int;
        break;
      }
    }

    int savedId;
    if (matchedId != null) {
      final mapData = product.toMap();
      await db.update(
        'products',
        {
          'name': trimmedName,
          'category': product.category,
          'configuration': mapData['configuration'],
          'price_updated_at': DateTime.now().toIso8601String(),
          'needs_review': product.needsReview ? 1 : 0,
        },
        where: 'id = ?',
        whereArgs: [matchedId],
      );
      savedId = matchedId;
    } else {
      // 3. Otherwise insert as a new product
      savedId = await db.insert('products', {
        ...product.toMap(),
        'name': trimmedName,
        'created_at': DateTime.now().toIso8601String(),
        'price_updated_at': DateTime.now().toIso8601String(),
      });
    }

    unawaited(getProductById(savedId).then((p) {
      if (p != null) ShopSyncService.instance.syncProduct(p);
    }));

    return savedId;
  }

  Future<int> getNeedsReviewCount() async {
    final db = await _databaseHelper.database;
    final res = await db.rawQuery(
      'SELECT COUNT(*) as count FROM products WHERE needs_review = 1 AND is_active = 1',
    );
    if (res.isNotEmpty && res.first['count'] != null) {
      return (res.first['count'] as num).toInt();
    }
    return 0;
  }

  Future<void> markProductReviewed(int id) async {
    final db = await _databaseHelper.database;
    await db.update(
      'products',
      {'needs_review': 0},
      where: 'id = ?',
      whereArgs: [id],
    );
    unawaited(getProductById(id).then((p) {
      if (p != null) ShopSyncService.instance.syncProduct(p);
    }));
  }

  Future<int> getStalePriceCount({int thresholdDays = 30}) async {
    final products = await getStalePricedProducts(thresholdDays: thresholdDays);
    return products.length;
  }

  Future<List<Product>> getStalePricedProducts({int thresholdDays = 30}) async {
    final all = await getAllProducts(includeInactive: false);
    final cutoff = DateTime.now().subtract(Duration(days: thresholdDays));
    return all.where((p) {
      final lastDate = p.priceUpdatedAt ?? p.createdAt;
      if (lastDate == null) return true;
      return lastDate.isBefore(cutoff);
    }).toList();
  }

  Future<void> confirmProductPrice(int id) async {
    final db = await _databaseHelper.database;
    final nowIso = DateTime.now().toIso8601String();
    await db.update(
      'products',
      {'price_updated_at': nowIso},
      where: 'id = ?',
      whereArgs: [id],
    );
    unawaited(getProductById(id).then((p) {
      if (p != null) ShopSyncService.instance.syncProduct(p);
    }));
  }

  Future<void> setProductActive(int id, bool isActive) async {
    final db = await _databaseHelper.database;
    await db.update(
      'products',
      {'is_active': isActive ? 1 : 0},
      where: 'id = ?',
      whereArgs: [id],
    );
    unawaited(getProductById(id).then((p) {
      if (p != null) ShopSyncService.instance.syncProduct(p);
    }));
  }

  Future<void> deleteProduct(int id) async {
    final db = await _databaseHelper.database;
    await db.delete(
      'products',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> deleteAllProducts() async {
    final db = await _databaseHelper.database;
    await db.delete('products');
  }
}
