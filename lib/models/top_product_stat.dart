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
      itemName: (map['item_name'] ?? map['itemName'] as String?) ?? 'Unknown Item',
      productId: (map['product_id'] ?? map['productId']) as int?,
      unit: (map['unit'] as String?) ?? 'Piece',
      totalQuantity: ((map['total_quantity'] ?? map['totalQuantity']) as num?)?.toDouble() ?? 0.0,
      totalRevenue: ((map['total_revenue'] ?? map['totalRevenue']) as num?)?.toDouble() ?? 0.0,
      orderCount: ((map['order_count'] ?? map['orderCount']) as num?)?.toInt() ?? 0,
    );
  }
}
