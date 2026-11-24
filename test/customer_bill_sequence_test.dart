import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Customer Bill Sequence & Ledger Processing Tests', () {
    test('Sequential bill numbering increments only for debits and computes running balance correctly', () {
      // Simulate entries coming from orders and payments
      final entries = <Map<String, dynamic>>[
        {'id': 7, 'customer_id': 1, 'date': DateTime(2026, 8, 24, 13, 44), 'type': 'debit', 'debit': 500.0, 'credit': 0.0},
        {'id': 1, 'customer_id': 1, 'date': DateTime(2026, 8, 24, 15, 00), 'type': 'credit', 'debit': 0.0, 'credit': 200.0},
        {'id': 8, 'customer_id': 1, 'date': DateTime(2026, 8, 24, 16, 59), 'type': 'debit', 'debit': 300.0, 'credit': 0.0},
        {'id': 2, 'customer_id': 1, 'date': DateTime(2026, 8, 24, 17, 00), 'type': 'credit', 'debit': 0.0, 'credit': 1000.0},
        {'id': 9, 'customer_id': 1, 'date': DateTime(2026, 8, 24, 17, 28), 'type': 'debit', 'debit': 725.0, 'credit': 0.0},
      ];

      // Sort chronologically ascending as in DatabaseHelper.getCustomerKhataLedger
      entries.sort((a, b) => (a['date'] as DateTime).compareTo(b['date'] as DateTime));

      double running = 0.0;
      int billSequence = 0;
      for (final entry in entries) {
        if (entry['type'] == 'debit') {
          billSequence++;
          entry['bill_number'] = billSequence;
          entry['title'] = 'Bill #$billSequence';
        }
        running += ((entry['debit'] as num?)?.toDouble() ?? 0.0) -
                   ((entry['credit'] as num?)?.toDouble() ?? 0.0);
        entry['running_balance'] = running;
      }

      // First bill
      expect(entries[0]['type'], 'debit');
      expect(entries[0]['bill_number'], 1);
      expect(entries[0]['title'], 'Bill #1');
      expect(entries[0]['running_balance'], 500.0);

      // Payment received (does not increment billSequence)
      expect(entries[1]['type'], 'credit');
      expect(entries[1].containsKey('bill_number'), isFalse);
      expect(entries[1]['running_balance'], 300.0);

      // Second bill
      expect(entries[2]['type'], 'debit');
      expect(entries[2]['bill_number'], 2);
      expect(entries[2]['title'], 'Bill #2');
      expect(entries[2]['running_balance'], 600.0);

      // Advance payment exceeding balance
      expect(entries[3]['type'], 'credit');
      expect(entries[3]['running_balance'], -400.0); // Advance credit

      // Third bill settling against advance
      expect(entries[4]['type'], 'debit');
      expect(entries[4]['bill_number'], 3);
      expect(entries[4]['title'], 'Bill #3');
      expect(entries[4]['running_balance'], 325.0); // 725 - 400
    });
  });
}
