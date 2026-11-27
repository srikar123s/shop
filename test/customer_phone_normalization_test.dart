import 'package:flutter_test/flutter_test.dart';
import 'package:shop/models/customer.dart';
import 'package:shop/repositories/customer_repository.dart';

void main() {
  group('Phone normalization and deduplication', () {
    test('normalizes +91, 0, spaces, dashes to same 10-digit number', () {
      expect(Customer.normalizePhoneDigits('9392449356'), '9392449356');
      expect(Customer.normalizePhoneDigits('+91 93924 49356'), '9392449356');
      expect(Customer.normalizePhoneDigits('09392449356'), '9392449356');
      expect(Customer.normalizePhoneDigits('919392449356'), '9392449356');
      expect(Customer.normalizePhoneDigits('93924-49356'), '9392449356');

      expect(Customer.phonesMatch('9392449356', '+91 93924 49356'), isTrue);
      expect(Customer.phonesMatch('09392449356', '+91 93924 49356'), isTrue);
      expect(Customer.phonesMatch('9392449356', '9848618177'), isFalse);
    });

    test('extractNumbers and mergePhoneNumbers deduplicate equivalent formats',
        () {
      expect(
        Customer.extractNumbers('9392449356, +91 93924 49356'),
        ['9392449356'],
      );
      expect(
        CustomerRepository.mergePhoneNumbers('9392449356', '+91 93924 49356'),
        '9392449356',
      );
      expect(
        CustomerRepository.mergePhoneNumbers('9392449356', '09848618177'),
        '9392449356, 09848618177',
      );
    });
  });
}
