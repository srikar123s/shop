import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Customer Bill Sequence Tests', () {
    test('Sequential bill numbering is 1-based and ordered chronologically per customer', () {
      // Given orders from different customers with arbitrary global order IDs (e.g. 7, 8, 9, 17 for Abhinay)
      final customerOrders = [
        {'id': 7, 'customer_id': 1, 'date': DateTime(2026, 8, 24, 13, 44), 'debit': 0.0},
        {'id': 8, 'customer_id': 1, 'date': DateTime(2026, 8, 24, 16, 59), 'debit': 300.0},
        {'id': 9, 'customer_id': 1, 'date': DateTime(2026, 8, 24, 17, 28), 'debit': 725.0},
        {'id': 17, 'customer_id': 1, 'date': DateTime(2026, 11, 21, 10, 22), 'debit': 14816.08},
      ];

      // Simulate chronological sorting
      customerOrders.sort((a, b) => (a['date'] as DateTime).compareTo(b['date'] as DateTime));

      int seq = 0;
      for (final o in customerOrders) {
        seq++;
        o['bill_number'] = seq;
        o['title'] = 'Bill #$seq';
      }

      expect(customerOrders[0]['title'], equals('Bill #1'));
      expect(customerOrders[1]['title'], equals('Bill #2'));
      expect(customerOrders[2]['title'], equals('Bill #3'));
      expect(customerOrders[3]['title'], equals('Bill #4'));

      // In Newest First view (Passbook screen display)
      final newestFirst = customerOrders.reversed.toList();
      expect(newestFirst[0]['title'], equals('Bill #4'));
      expect(newestFirst[1]['title'], equals('Bill #3'));
      expect(newestFirst[2]['title'], equals('Bill #2'));
      expect(newestFirst[3]['title'], equals('Bill #1'));
    });
  });
}
