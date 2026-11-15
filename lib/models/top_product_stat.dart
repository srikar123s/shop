class TopProductStat {
  const TopProductStat({
    required this.itemName,
    this.productId,
    this.unit = 'Piece',
    required this.totalQuantity,
    required this.totalRevenue,
    required this.orderCount,
  });

  final String itemName;
  final int? productId;
  final String unit;
  final double totalQuantity;
  final double totalRevenue;
  final int orderCount;

  factory TopProductStat.fromMap(Map<String, dynamic> map) {
    return TopProductStat(
      itemName: (map['item_name'] as String?) ?? 'Unknown Item',
      productId: map['product_id'] as int?,
      unit: (map['unit'] as String?) ?? 'Piece',
      totalQuantity: (map['total_quantity'] as num?)?.toDouble() ?? 0.0,
      totalRevenue: (map['total_revenue'] as num?)?.toDouble() ?? 0.0,
      orderCount: (map['order_count'] as num?)?.toInt() ?? 0,
    );
  }
}
