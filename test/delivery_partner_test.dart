import 'package:flutter_test/flutter_test.dart';
import 'package:shop/models/delivery_partner.dart';

void main() {
  group('DeliveryPartner & DeliveryTransaction', () {
    test('calculates advance and payable balances accurately', () {
      final now = DateTime(2026, 11, 27);

      // Driver given ₹5000 advance, earned ₹450 -> Advance left = ₹4550
      final withAdvance = DeliveryPartner(
        id: 1,
        name: 'Raju Auto',
        createdAt: now,
        totalEarned: 450.0,
        totalPaid: 5000.0,
      );
      expect(withAdvance.balance, -4550.0);
      expect(withAdvance.advanceBalance, 4550.0);
      expect(withAdvance.payableBalance, 0.0);

      // Driver earned ₹1200, paid ₹500 -> Payable = ₹700
      final withPayable = DeliveryPartner(
        id: 2,
        name: 'Suresh Auto',
        createdAt: now,
        totalEarned: 1200.0,
        totalPaid: 500.0,
      );
      expect(withPayable.balance, 700.0);
      expect(withPayable.advanceBalance, 0.0);
      expect(withPayable.payableBalance, 700.0);
    });

    test('round-trips DeliveryTransaction with rateTiers JSON', () {
      final now = DateTime(2026, 11, 27, 19, 0);
      final tx = DeliveryTransaction(
        id: 10,
        partnerId: 1,
        txType: DeliveryTxType.perBox,
        location: 'Kukatpally',
        totalBoxes: 15,
        rateTiers: const [
          BoxRateTier(boxes: 10, rate: 30.0),
          BoxRateTier(boxes: 5, rate: 40.0),
        ],
        earnedAmount: 500.0,
        paidAmount: 300.0,
        cutAmount: 200.0,
        paymentMode: 'cash',
        description: '10 boxes Ravi Kirana, 5 boxes Balaji',
        createdAt: now,
      );

      final map = tx.toMap();
      final decoded = DeliveryTransaction.fromMap(map);

      expect(decoded.id, 10);
      expect(decoded.partnerId, 1);
      expect(decoded.txType, DeliveryTxType.perBox);
      expect(decoded.location, 'Kukatpally');
      expect(decoded.totalBoxes, 15);
      expect(decoded.rateTiers.length, 2);
      expect(decoded.rateTiers[0].boxes, 10);
      expect(decoded.rateTiers[0].rate, 30.0);
      expect(decoded.rateTiers[0].subtotal, 300.0);
      expect(decoded.rateTiers[1].boxes, 5);
      expect(decoded.rateTiers[1].rate, 40.0);
      expect(decoded.rateTiers[1].subtotal, 200.0);
      expect(decoded.earnedAmount, 500.0);
      expect(decoded.paidAmount, 300.0);
      expect(decoded.cutAmount, 200.0);
      expect(decoded.paymentMode, 'cash');
      expect(decoded.description, '10 boxes Ravi Kirana, 5 boxes Balaji');
    });
  });
}
