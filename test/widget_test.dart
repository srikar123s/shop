import 'package:flutter_test/flutter_test.dart';
import 'package:shop/models/customer.dart';

void main() {
  test('customer serializes its stored fields', () {
    final customer = Customer(
      id: 1,
      name: 'Ravi',
      phone: '9876543210',
      createdAt: DateTime.utc(2026, 8, 23),
    );

    final restored = Customer.fromMap(customer.toMap());

    expect(restored.id, 1);
    expect(restored.name, 'Ravi');
    expect(restored.phone, '9876543210');
  });
}
