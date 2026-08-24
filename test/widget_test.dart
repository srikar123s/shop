import 'package:flutter_test/flutter_test.dart';
import 'package:shop/models/customer.dart';
import 'package:shop/models/order.dart';

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

  test('draft order serializes to and from map', () {
    final customer = Customer(id: 1, name: 'Srinivas', createdAt: DateTime.now());
    final item = DraftOrderItem(
      productId: 10,
      itemName: 'Welding Rod',
      options: {'brand': 'Brand A'},
      quantity: 5,
      unit: 'Box',
      unitPrice: 250,
      unitFactor: 100,
    );
    final draft = DraftOrder(customer: customer, items: [item], estimateTotal: 1250);

    final map = draft.toMap();
    final restoredDraft = DraftOrder.fromMap(map);

    expect(restoredDraft.customer.name, 'Srinivas');
    expect(restoredDraft.items.length, 1);
    expect(restoredDraft.items.first.itemName, 'Welding Rod');
    expect(restoredDraft.items.first.unitPrice, 250);
    expect(restoredDraft.estimateTotal, 1250);
  });
}
