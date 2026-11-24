import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:shop/models/order.dart';
import 'package:shop/repositories/product_repository.dart';

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

    test('ProductRepository.isProductMatch preserves root letters in words like Brass, Glass, Steel', () {
      // Plurals with -s and -es
      expect(ProductRepository.isProductMatch('screw', 'screws'), isTrue);
      expect(ProductRepository.isProductMatch('pipe', 'pipes'), isTrue);
      expect(ProductRepository.isProductMatch('box', 'boxes'), isTrue);
      expect(ProductRepository.isProductMatch('battery', 'batteries'), isTrue);

      // Root words ending in 's' should never falsely match stripped words
      expect(ProductRepository.isProductMatch('brass', 'bra'), isFalse);
      expect(ProductRepository.isProductMatch('glass', 'gla'), isFalse);
      expect(ProductRepository.isProductMatch('brass', 'brass'), isTrue);
      expect(ProductRepository.isProductMatch('stainless steel', 'stainless steel'), isTrue);
    });
  });
}
