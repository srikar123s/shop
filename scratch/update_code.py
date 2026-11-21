import sys

# 1. Update customer_orders_screen.dart
path1 = r'lib\screens\customer_orders_screen.dart'
with open(path1, 'r', encoding='utf-8') as f:
    c1 = f.read()

target1 = "child: Text(\n                                            order.formattedOrderId,"
replacement1 = "child: Text(\n                                            'Bill #${_orders.length - index} • ${order.formattedOrderId}',"

if target1 in c1:
    c1 = c1.replace(target1, replacement1, 1)
    with open(path1, 'w', encoding='utf-8') as f:
        f.write(c1)
    print("customer_orders_screen updated")
else:
    print("customer_orders_screen target not found")
