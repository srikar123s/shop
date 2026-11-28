import 'package:flutter/foundation.dart';
import 'dart:async';

import 'package:shop/database/database_helper.dart';
import 'package:shop/models/product.dart';
import 'package:shop/services/shop_sync_service.dart';

class ProductRepository {
  const ProductRepository(this._databaseHelper);

  final DatabaseHelper _databaseHelper;

  /// Evaluates singular/plural and root word equivalence between product names.
  static bool isProductMatch(String dbName, String searchName) {
    final a = dbName.trim().toLowerCase();
    final b = searchName.trim().toLowerCase();
    if (a == b) return true;
    if ('${a}s' == b || '${b}s' == a) return true;
    if ('${a}es' == b || '${b}es' == a) return true;
    if (a.endsWith('ies') && b == '${a.substring(0, a.length - 3)}y') return true;
    if (b.endsWith('ies') && a == '${b.substring(0, b.length - 3)}y') return true;
    return false;
  }

  Future<List<Product>> searchProducts(
    String query, {
    int? limit,
    int? offset,
  }) async {
    final db = await _databaseHelper.database;
    final normalized = query.trim().toLowerCase();
    final result = await db.query(
      'products',
      where: normalized.isEmpty
          ? 'is_active = 1 AND deleted_at IS NULL'
          : '''is_active = 1 AND deleted_at IS NULL AND
            (LOWER(name) LIKE ? OR LOWER(category) LIKE ? OR LOWER(configuration) LIKE ?)''',
      whereArgs: normalized.isEmpty
          ? null
          : <Object?>['%$normalized%', '%$normalized%', '%$normalized%'],
      orderBy: 'name COLLATE NOCASE ASC',
      limit: limit,
      offset: offset,
    );
    return result.map(Product.fromMap).toList();
  }

  Future<List<Product>> getAllProducts({
    bool includeInactive = true,
    int? limit,
    int? offset,
  }) async {
    final db = await _databaseHelper.database;
    final result = await db.query(
      'products',
      where: includeInactive ? 'deleted_at IS NULL' : 'is_active = 1 AND deleted_at IS NULL',
      orderBy: 'name COLLATE NOCASE ASC',
      limit: limit,
      offset: offset,
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
      final now = DateTime.now();
      final existingRow = await getProductById(product.id!);
      final effectiveCloudId = (product.cloudId != null && product.cloudId!.isNotEmpty)
          ? product.cloudId!
          : ((existingRow?.cloudId != null && existingRow!.cloudId!.isNotEmpty)
              ? existingRow.cloudId!
              : DatabaseHelper.generateUuidV4());
      final productWithMeta = product.copyWith(
        cloudId: effectiveCloudId,
        priceUpdatedAt: now,
        updatedAt: now,
      );
      final mapData = productWithMeta.toMap();
      final affected = await db.update(
        'products',
        mapData,
        where: 'id = ?',
        whereArgs: [product.id],
      );
      if (affected == 0) {
        await db.insert('products', mapData);
      }
      unawaited(ShopSyncService.instance.syncProduct(productWithMeta).catchError((e) {
        debugPrint('Error syncing product: $e');
      }));
      return product.id!;
    }

    // 2. Check if product with same name already exists using fast query
    final exactMatch = await db.query(
      'products',
      where: 'LOWER(TRIM(name)) = ?',
      whereArgs: [lowerName],
      limit: 1,
    );
    int? matchedId = exactMatch.isNotEmpty ? (exactMatch.first['id'] as int) : null;

    int savedId;
    final nowIso = DateTime.now().toIso8601String();
    if (matchedId != null) {
      final existingCloudId = exactMatch.first['cloud_id'] as String?;
      final effectiveCloudId = (existingCloudId != null && existingCloudId.isNotEmpty)
          ? existingCloudId
          : ((product.cloudId != null && product.cloudId!.isNotEmpty)
              ? product.cloudId!
              : DatabaseHelper.generateUuidV4());
      final mapData = product.toMap();
      await db.update(
        'products',
        {
          'cloud_id': effectiveCloudId,
          'name': trimmedName,
          'category': product.category,
          'is_active': product.isActive ? 1 : 0,
          'configuration': mapData['configuration'],
          'price_updated_at': nowIso,
          'updated_at': nowIso,
          'deleted_at': null,
          'needs_review': product.needsReview ? 1 : 0,
        },
        where: 'id = ?',
        whereArgs: [matchedId],
      );
      savedId = matchedId;
    } else {
      // 3. Otherwise insert as a new product
      final effectiveCloudId = (product.cloudId != null && product.cloudId!.isNotEmpty)
          ? product.cloudId!
          : DatabaseHelper.generateUuidV4();
      savedId = await db.insert('products', {
        ...product.toMap(),
        'cloud_id': effectiveCloudId,
        'name': trimmedName,
        'created_at': nowIso,
        'price_updated_at': nowIso,
        'updated_at': nowIso,
      });
    }

    unawaited(getProductById(savedId).then((p) {
      if (p != null) {
        ShopSyncService.instance.syncProduct(p).catchError((e) {
          debugPrint('Error syncing product $savedId: $e');
        });
      }
    }).catchError((e) {
      debugPrint('Error loading product $savedId for sync: $e');
    }));

    return savedId;
  }

  /// Inserts or updates a batch of products inside a single SQLite transaction
  /// and pushes them using Firestore batch commits (or sync_outbox if offline).
  Future<int> upsertProductsBatch(List<Product> products) async {
    if (products.isEmpty) return 0;
    final db = await _databaseHelper.database;
    final now = DateTime.now();
    final nowIso = now.toIso8601String();
    final savedProducts = <Product>[];

    await db.transaction((txn) async {
      for (final product in products) {
        final trimmedName = product.name.trim();
        if (trimmedName.isEmpty) continue;
        final lowerName = trimmedName.toLowerCase();

        final existing = await txn.query(
          'products',
          columns: ['id', 'cloud_id', 'created_at'],
          where: 'LOWER(TRIM(name)) = ?',
          whereArgs: [lowerName],
          limit: 1,
        );

        final mapData = product.toMap();
        if (existing.isNotEmpty) {
          final id = (existing.first['id'] as num).toInt();
          final existingCloudId = existing.first['cloud_id'] as String?;
          final cloudId = (existingCloudId != null && existingCloudId.isNotEmpty)
              ? existingCloudId
              : ((product.cloudId != null && product.cloudId!.isNotEmpty)
                  ? product.cloudId!
                  : DatabaseHelper.generateUuidV4());
          await txn.update(
            'products',
            {
              'cloud_id': cloudId,
              'name': trimmedName,
              'category': product.category,
              'is_active': product.isActive ? 1 : 0,
              'configuration': mapData['configuration'],
              'price_updated_at': nowIso,
              'updated_at': nowIso,
              'deleted_at': null,
              'needs_review': product.needsReview ? 1 : 0,
            },
            where: 'id = ?',
            whereArgs: [id],
          );
          savedProducts.add(product.copyWith(
            id: id,
            cloudId: cloudId,
            priceUpdatedAt: now,
            updatedAt: now,
            createdAt: DateTime.tryParse(existing.first['created_at']?.toString() ?? '') ?? now,
          ));
        } else {
          final cloudId = (product.cloudId != null && product.cloudId!.isNotEmpty)
              ? product.cloudId!
              : DatabaseHelper.generateUuidV4();
          final id = await txn.insert('products', {
            ...mapData,
            'cloud_id': cloudId,
            'name': trimmedName,
            'created_at': nowIso,
            'price_updated_at': nowIso,
            'updated_at': nowIso,
          });
          savedProducts.add(product.copyWith(
            id: id,
            cloudId: cloudId,
            priceUpdatedAt: now,
            updatedAt: now,
            createdAt: now,
          ));
        }
      }
    });

    unawaited(ShopSyncService.instance.syncProductsBatch(savedProducts).catchError((e) {
      debugPrint('Error batch syncing products: $e');
    }));
    return savedProducts.length;
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
      {
        'needs_review': 0,
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [id],
    );
    unawaited(getProductById(id).then((p) {
      if (p != null) {
        ShopSyncService.instance.syncProduct(p).catchError((e) {
          debugPrint('Error syncing reviewed product: $e');
        });
      }
    }).catchError((e) {
      debugPrint('Error getting reviewed product: $e');
    }));
  }

  Future<int> getStalePriceCount({int thresholdDays = 30}) async {
    final db = await _databaseHelper.database;
    final cutoff = DateTime.now().subtract(Duration(days: thresholdDays)).toIso8601String();
    final res = await db.rawQuery('''
      SELECT COUNT(*) as count FROM products
      WHERE is_active = 1 AND deleted_at IS NULL
        AND (
          COALESCE(price_updated_at, created_at) < ?
          OR (price_updated_at IS NULL AND created_at IS NULL)
        )
    ''', [cutoff]);
    if (res.isNotEmpty && res.first['count'] != null) {
      return (res.first['count'] as num).toInt();
    }
    return 0;
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
      {'price_updated_at': nowIso, 'updated_at': nowIso},
      where: 'id = ?',
      whereArgs: [id],
    );
    unawaited(getProductById(id).then((p) {
      if (p != null) {
        ShopSyncService.instance.syncProduct(p).catchError((e) {
          debugPrint('Error syncing confirmed product: $e');
        });
      }
    }).catchError((e) {
      debugPrint('Error fetching product for confirm sync: $e');
    }));
  }

  Future<void> setProductActive(int id, bool isActive) async {
    final db = await _databaseHelper.database;
    await db.update(
      'products',
      {
        'is_active': isActive ? 1 : 0,
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [id],
    );
    unawaited(getProductById(id).then((p) {
      if (p != null) {
        ShopSyncService.instance.syncProduct(p).catchError((e) {
          debugPrint('Error syncing active product: $e');
        });
      }
    }).catchError((e) {
      debugPrint('Error fetching product for active sync: $e');
    }));
  }

  Future<void> deleteProduct(int id) async {
    final db = await _databaseHelper.database;
    String? cloudId;
    await db.transaction((txn) async {
      final rows = await txn.query(
        'products',
        columns: ['cloud_id'],
        where: 'id = ?',
        whereArgs: [id],
        limit: 1,
      );
      cloudId = rows.isNotEmpty ? rows.first['cloud_id'] as String? : null;
      await txn.delete(
        'product_options',
        where: 'product_id = ?',
        whereArgs: [id],
      );
      await txn.delete(
        'products',
        where: 'id = ?',
        whereArgs: [id],
      );
    });
    if (cloudId != null && cloudId!.isNotEmpty) {
      unawaited(ShopSyncService.instance.deleteProductFromCloud(cloudId!).catchError((e) {
        debugPrint('Error propagating product delete tombstone: $e');
      }));
    }
  }

  Future<void> deleteAllProducts() async {
    final db = await _databaseHelper.database;
    final rows = await db.query('products', columns: ['cloud_id']);
    await db.transaction((txn) async {
      await txn.delete('product_options');
      await txn.delete('products');
    });
    for (final r in rows) {
      final cid = r['cloud_id'] as String?;
      if (cid != null && cid.isNotEmpty) {
        unawaited(ShopSyncService.instance.deleteProductFromCloud(cid).catchError((e) {
          debugPrint('Error propagating product delete tombstone: $e');
        }));
      }
    }
  }
}
