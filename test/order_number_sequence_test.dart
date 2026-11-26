import 'package:flutter_test/flutter_test.dart';
import 'package:shop/models/order.dart';

void main() {
  group('Order Sequential Numbering & Multi-Device Sync Tests', () {
    test('OrderEntity displayOrderNumber and formattedOrderId prefers orderNumber over local id', () {
      final order = OrderEntity(
        id: 39, // Phone 2 local auto-increment id
        orderNumber: 34, // Creator / shop sequential order number
        customerId: 1,
        customerNameSnapshot: 'Abhinay',
        createdAt: DateTime(2026, 11, 25, 14, 15),
        status: OrderStatus.pending,
      );

      expect(order.id, 39);
      expect(order.orderNumber, 34);
      expect(order.displayOrderNumber, 34);
      expect(order.formattedOrderId, '#ORD-0034');
    });

    test('OrderEntity falls back to local id when orderNumber is null or 0', () {
      final orderWithNull = OrderEntity(
        id: 12,
        customerId: 1,
        customerNameSnapshot: 'Customer',
        createdAt: DateTime.now(),
        status: OrderStatus.completed,
      );
      expect(orderWithNull.displayOrderNumber, 12);
      expect(orderWithNull.formattedOrderId, '#ORD-0012');

      final orderWithZero = OrderEntity(
        id: 15,
        orderNumber: 0,
        customerId: 1,
        customerNameSnapshot: 'Customer',
        createdAt: DateTime.now(),
        status: OrderStatus.completed,
      );
      expect(orderWithZero.displayOrderNumber, 15);
      expect(orderWithZero.formattedOrderId, '#ORD-0015');
    });

    test('OrderSummary formattedOrderId uses orderNumber when available', () {
      final summaryPhone2 = OrderSummary(
        orderId: 39, // local id on phone 2
        orderNumber: 34, // unified shop order number
        customerId: 5,
        customerName: 'Abhinay',
        createdAt: DateTime.now(),
        totalItems: 7,
        pendingCount: 1,
        status: OrderStatus.pending,
      );

      final summaryPhone1 = OrderSummary(
        orderId: 34, // local id on phone 1
        orderNumber: 34, // unified shop order number
        customerId: 5,
        customerName: 'Abhinay',
        createdAt: DateTime.now(),
        totalItems: 7,
        pendingCount: 1,
        status: OrderStatus.pending,
      );

      expect(summaryPhone2.displayOrderNumber, 34);
      expect(summaryPhone1.displayOrderNumber, 34);
      expect(summaryPhone2.formattedOrderId, '#ORD-0034');
      expect(summaryPhone1.formattedOrderId, '#ORD-0034');
      expect(summaryPhone2.formattedOrderId, summaryPhone1.formattedOrderId);
    });

    test('ProcurementItem formattedOrderId uses orderNumber when available', () {
      final itemPhone2 = ProcurementItem(
        itemId: 101,
        orderId: 39, // local id on phone 2
        orderNumber: 34, // unified shop order number
        customerName: 'Abhinay',
        takenBy: 'Srikar',
        createdAt: DateTime.now(),
        itemName: 'Asian Paints Apex 20L',
        unit: 'Bucket',
        quantityOrdered: 2,
        quantityGiven: 1,
        unitPrice: 3500.0,
      );

      expect(itemPhone2.displayOrderNumber, 34);
      expect(itemPhone2.formattedOrderId, '#ORD-0034');
    });
  });
}
