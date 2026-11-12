import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:shop/models/customer.dart';
import 'package:shop/models/order.dart';

void main() {
  group('Bill Breakdown and Tax Calculations', () {
    test('Default bill with no optional charges calculates subtotal correctly', () {
      final breakdown = BillBreakdown.calculate(
        subtotal: 1000.0,
      );

      expect(breakdown.subtotal, 1000.0);
      expect(breakdown.applyGst, isFalse);
      expect(breakdown.gstRate, 18.0); // Default is 18
      expect(breakdown.gstAmount, 0.0);
      expect(breakdown.otherCharges, isEmpty);
      expect(breakdown.otherChargesTotal, 0.0);
      expect(breakdown.grandTotal, 1000.0);
    });

    test('GST applied with default 18% calculates 18% tax correctly', () {
      final breakdown = BillBreakdown.calculate(
        subtotal: 1000.0,
        applyGst: true,
      );

      expect(breakdown.subtotal, 1000.0);
      expect(breakdown.applyGst, isTrue);
      expect(breakdown.gstRate, 18.0);
      expect(breakdown.gstAmount, 180.0);
      expect(breakdown.grandTotal, 1180.0);
    });

    test('User can change GST rate from 18 to any other percentage', () {
      final breakdown5 = BillBreakdown.calculate(
        subtotal: 1000.0,
        applyGst: true,
        gstRate: 5.0,
      );
      expect(breakdown5.gstRate, 5.0);
      expect(breakdown5.gstAmount, 50.0);
      expect(breakdown5.grandTotal, 1050.0);

      final breakdown12 = BillBreakdown.calculate(
        subtotal: 1000.0,
        applyGst: true,
        gstRate: 12.0,
      );
      expect(breakdown12.gstRate, 12.0);
      expect(breakdown12.gstAmount, 120.0);
      expect(breakdown12.grandTotal, 1120.0);

      final breakdown28 = BillBreakdown.calculate(
        subtotal: 1000.0,
        applyGst: true,
        gstRate: 28.0,
      );
      expect(breakdown28.gstRate, 28.0);
      expect(breakdown28.gstAmount, 280.0);
      expect(breakdown28.grandTotal, 1280.0);
    });

    test('User can specify multiple other charges with custom type and amount', () {
      final charges = [
        const OtherCharge(name: 'Delivery', amount: 150.0),
        const OtherCharge(name: 'Transport', amount: 350.0),
        const OtherCharge(name: 'Labor', amount: 100.0),
      ];

      final breakdown = BillBreakdown.calculate(
        subtotal: 2000.0,
        applyGst: false, // charges are independent of GST
        otherCharges: charges,
      );

      expect(breakdown.subtotal, 2000.0);
      expect(breakdown.otherCharges.length, 3);
      expect(breakdown.otherChargesTotal, 600.0);
      expect(breakdown.grandTotal, 2600.0);
    });

    test('Combined GST (18%) and other charges calculate grand total accurately', () {
      final charges = [
        const OtherCharge(name: 'Delivery Charge', amount: 200.0),
      ];

      final breakdown = BillBreakdown.calculate(
        subtotal: 5000.0,
        applyGst: true,
        gstRate: 18.0,
        otherCharges: charges,
      );

      // Subtotal = 5000
      // GST 18% = 900
      // Delivery = 200
      // Grand Total = 6100
      expect(breakdown.subtotal, 5000.0);
      expect(breakdown.gstAmount, 900.0);
      expect(breakdown.otherChargesTotal, 200.0);
      expect(breakdown.grandTotal, 6100.0);
    });

    test('Serialization and deserialization of BillBreakdown to/from JSON map', () {
      final original = BillBreakdown.calculate(
        subtotal: 3000.0,
        applyGst: true,
        gstRate: 18.0,
        otherCharges: [
          const OtherCharge(name: 'Packaging', amount: 50.0),
        ],
      );

      final map = original.toMap();
      final jsonStr = jsonEncode(map);
      final restored = BillBreakdown.fromJsonString(jsonStr);

      expect(restored, isNotNull);
      expect(restored!.subtotal, 3000.0);
      expect(restored.applyGst, isTrue);
      expect(restored.gstRate, 18.0);
      expect(restored.gstAmount, 540.0);
      expect(restored.otherCharges.length, 1);
      expect(restored.otherCharges.first.name, 'Packaging');
      expect(restored.otherCharges.first.amount, 50.0);
      expect(restored.grandTotal, 3590.0);
    });

    test('DraftOrder retains applyGst, gstRate, and otherCharges across serialization', () {
      final customer = Customer(id: 1, name: 'Srinivas', createdAt: DateTime.now());
      final item = DraftOrderItem(
        productId: 1,
        itemName: 'Asian Paint',
        options: {'colour': 'Red'},
        quantity: 2,
        unit: 'Can',
        unitPrice: 500,
      );

      final draft = DraftOrder(
        customer: customer,
        items: [item],
        estimateTotal: 1230.0,
        applyGst: true,
        gstRate: 18.0,
        otherCharges: [
          const OtherCharge(name: 'Transport', amount: 50.0),
        ],
      );

      final map = draft.toMap();
      final restored = DraftOrder.fromMap(map);

      expect(restored.applyGst, isTrue);
      expect(restored.gstRate, 18.0);
      expect(restored.otherCharges.length, 1);
      expect(restored.otherCharges.first.name, 'Transport');
      expect(restored.otherCharges.first.amount, 50.0);
    });

    test('OrderEntity correctly exposes billBreakdown from notes JSON', () {
      final breakdown = BillBreakdown.calculate(
        subtotal: 1000.0,
        applyGst: true,
        gstRate: 18.0,
        otherCharges: [
          const OtherCharge(name: 'Loading', amount: 100.0),
        ],
      );

      final order = OrderEntity(
        id: 42,
        customerId: 1,
        customerNameSnapshot: 'Ravi',
        createdAt: DateTime.now(),
        status: OrderStatus.pending,
        notes: jsonEncode(breakdown.toMap()),
        estimateTotal: breakdown.grandTotal,
      );

      expect(order.billBreakdown, isNotNull);
      expect(order.billBreakdown!.applyGst, isTrue);
      expect(order.billBreakdown!.gstRate, 18.0);
      expect(order.billBreakdown!.gstAmount, 180.0);
      expect(order.billBreakdown!.otherCharges.first.name, 'Loading');
      expect(order.billBreakdown!.grandTotal, 1280.0);
    });
  });
}

