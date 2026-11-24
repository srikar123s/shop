import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:shop/models/order.dart';

void main() {
  group('OrderItemEntity & Procurement Tests', () {
    test('OrderItemEntity calculates unitPrice from productSnapshot', () {
      final snapshot = jsonEncode({
        'id': 5,
        'name': 'Brass Screws 1/2 inch',
        'unitPrice': 15.5,
      });

      final item = OrderItemEntity(
        id: 1,
        orderId: 10,
        productId: 5,
        itemName: 'Brass Screws 1/2 inch',
        quantityOrdered: 20.0,
        quantityGiven: 20.0,
        unit: 'Pcs',
        status: ItemStatus.given,
        isOtherItem: false,
        procurementStatus: ProcurementStatus.notRequired,
        productSnapshot: snapshot,
      );

      expect(item.unitPrice, 15.5);
      expect(item.quantityOrdered, 20.0);
      expect(item.quantityGiven, 20.0);
      expect(item.status, ItemStatus.given);
      expect(item.quantityPending, 0.0);
    });

    test('OrderEntity serialization and payment helper fields', () {
      final now = DateTime.now();
      final order = OrderEntity(
        id: 101,
        customerId: 12,
        customerNameSnapshot: 'Ramesh Patel',
        customerPhone: '9876543210',
        createdAt: now,
        status: OrderStatus.completed,
        estimateTotal: 1500.0,
        paidAmount: 1500.0,
        paymentMode: 'UPI',
        paymentStatus: 'PAID',
      );

      expect(order.paidAmount, 1500.0);
      expect(order.paymentMode, 'UPI');
      expect(order.paymentStatus, 'PAID');
      expect(order.dueAmount, 0.0);
      expect(order.isFullyPaid, isTrue);
    });

    test('Singular / plural word matching preserves root letters in words like Brass, Glass, Steel', () {
      bool isProductMatch(String dbName, String searchName) {
        final a = dbName.trim().toLowerCase();
        final b = searchName.trim().toLowerCase();
        if (a == b) return true;
        if ('${a}s' == b || '${b}s' == a) return true;
        if ('${a}es' == b || '${b}es' == a) return true;
        if (a.endsWith('ies') && b == '${a.substring(0, a.length - 3)}y') return true;
        if (b.endsWith('ies') && a == '${b.substring(0, b.length - 3)}y') return true;
        return false;
      }

      // Plurals with -s and -es
      expect(isProductMatch('screw', 'screws'), isTrue);
      expect(isProductMatch('pipe', 'pipes'), isTrue);
      expect(isProductMatch('box', 'boxes'), isTrue);
      expect(isProductMatch('battery', 'batteries'), isTrue);

      // Root words ending in 's' should never falsely match stripped words
      expect(isProductMatch('brass', 'bra'), isFalse);
      expect(isProductMatch('glass', 'gla'), isFalse);
      expect(isProductMatch('brass', 'brass'), isTrue);
      expect(isProductMatch('stainless steel', 'stainless steel'), isTrue);
    });
  });
}
