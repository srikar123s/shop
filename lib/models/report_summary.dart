class KhataCustomerSummary {
  const KhataCustomerSummary({
    required this.customerId,
    required this.customerName,
    this.customerPhone,
    this.customerLocation,
    required this.totalBilled,
    required this.totalPaid,
    required this.balanceDue,
    required this.creditLimit,
    required this.isOverLimit,
    required this.orderCount,
    required this.daysOverdue,
  });

  final int customerId;
  final String customerName;
  final String? customerPhone;
  final String? customerLocation;
  final double totalBilled;
  final double totalPaid;
  final double balanceDue;
  final double creditLimit;
  final bool isOverLimit;
  final int orderCount;
  final int daysOverdue;

  factory KhataCustomerSummary.fromMap(Map<String, dynamic> map) {
    return KhataCustomerSummary(
      customerId: (map['customer_id'] as num?)?.toInt() ?? 0,
      customerName: (map['customer_name'] as String?) ?? 'Customer',
      customerPhone: map['customer_phone'] as String?,
      customerLocation: map['customer_location'] as String?,
      totalBilled: (map['total_billed'] as num?)?.toDouble() ?? 0.0,
      totalPaid: (map['total_paid'] as num?)?.toDouble() ?? 0.0,
      balanceDue: (map['balance_due'] as num?)?.toDouble() ?? 0.0,
      creditLimit: (map['credit_limit'] as num?)?.toDouble() ?? 0.0,
      isOverLimit: map['is_over_limit'] == true,
      orderCount: (map['order_count'] as num?)?.toInt() ?? 0,
      daysOverdue: (map['days_overdue'] as num?)?.toInt() ?? 0,
    );
  }
}

class KhataLedgerEntry {
  const KhataLedgerEntry({
    required this.type,
    required this.id,
    this.orderId,
    this.orderNumber,
    this.billNumber,
    required this.title,
    required this.subtitle,
    required this.date,
    required this.amount,
    required this.runningBalance,
    required this.paymentMode,
    required this.isManualDebit,
  });

  final String type;
  final int id;
  final int? orderId;
  final int? orderNumber;
  final int? billNumber;
  final String title;
  final String subtitle;
  final DateTime date;
  final double amount;
  final double runningBalance;
  final String paymentMode;
  final bool isManualDebit;

  bool get isDebit => type == 'debit';

  factory KhataLedgerEntry.fromMap(Map<String, dynamic> map) {
    final subtitle = (map['subtitle'] as String?) ?? '';
    return KhataLedgerEntry(
      type: (map['type'] as String?) ?? 'debit',
      id: (map['id'] as num?)?.toInt() ?? 0,
      orderId: (map['order_id'] as num?)?.toInt(),
      orderNumber: (map['order_number'] as num?)?.toInt(),
      billNumber: (map['bill_number'] as num?)?.toInt(),
      title: (map['title'] as String?) ?? '',
      subtitle: subtitle,
      date: map['date'] is DateTime
          ? map['date'] as DateTime
          : (DateTime.tryParse(map['date']?.toString() ?? '') ?? DateTime.now()),
      amount: (map['amount'] as num?)?.toDouble() ?? 0.0,
      runningBalance: (map['running_balance'] as num?)?.toDouble() ?? 0.0,
      paymentMode: (map['payment_mode'] as String?) ?? '',
      isManualDebit: map['is_manual_debit'] == true || subtitle.contains('Manual Udhaar'),
    );
  }
}

class EveningClosingSummary {
  const EveningClosingSummary({
    required this.totalTurnover,
    required this.cashSales,
    required this.upiSales,
    required this.otherSales,
    required this.totalCollectedToday,
    required this.udhaarGivenToday,
    required this.completedCount,
    required this.pendingCount,
    required this.totalOrdersCount,
    required this.raw,
  });

  final double totalTurnover;
  final double cashSales;
  final double upiSales;
  final double otherSales;
  final double totalCollectedToday;
  final double udhaarGivenToday;
  final int completedCount;
  final int pendingCount;
  final int totalOrdersCount;
  final Map<String, dynamic> raw;

  factory EveningClosingSummary.fromMap(Map<String, dynamic> map) {
    return EveningClosingSummary(
      totalTurnover: (map['totalTurnover'] as num?)?.toDouble() ?? 0.0,
      cashSales: (map['cashSales'] as num?)?.toDouble() ?? 0.0,
      upiSales: (map['upiSales'] as num?)?.toDouble() ?? 0.0,
      otherSales: (map['otherSales'] as num?)?.toDouble() ?? 0.0,
      totalCollectedToday: (map['totalCollectedToday'] as num?)?.toDouble() ?? 0.0,
      udhaarGivenToday: (map['udhaarGivenToday'] as num?)?.toDouble() ?? 0.0,
      completedCount: (map['completedCount'] as num?)?.toInt() ?? 0,
      pendingCount: (map['pendingCount'] as num?)?.toInt() ?? 0,
      totalOrdersCount: (map['totalOrdersCount'] as num?)?.toInt() ?? 0,
      raw: map,
    );
  }
}

class LifetimeBusinessSummary {
  const LifetimeBusinessSummary({
    required this.totalLifetimeRevenue,
    required this.totalLifetimeCollected,
    required this.totalOrders,
    required this.totalCustomers,
    required this.totalProducts,
    required this.totalMarketDue,
    required this.collectionEfficiencyPct,
    required this.averageDsoDays,
    required this.raw,
  });

  final double totalLifetimeRevenue;
  final double totalLifetimeCollected;
  final int totalOrders;
  final int totalCustomers;
  final int totalProducts;
  final double totalMarketDue;
  final double collectionEfficiencyPct;
  final int averageDsoDays;
  final Map<String, dynamic> raw;

  factory LifetimeBusinessSummary.fromMap(Map<String, dynamic> map) {
    return LifetimeBusinessSummary(
      totalLifetimeRevenue: (map['totalLifetimeRevenue'] as num?)?.toDouble() ?? 0.0,
      totalLifetimeCollected: (map['totalLifetimeCollected'] as num?)?.toDouble() ?? 0.0,
      totalOrders: (map['totalOrders'] as num?)?.toInt() ?? 0,
      totalCustomers: (map['totalCustomers'] as num?)?.toInt() ?? 0,
      totalProducts: (map['totalProducts'] as num?)?.toInt() ?? 0,
      totalMarketDue: (map['totalMarketDue'] as num?)?.toDouble() ?? 0.0,
      collectionEfficiencyPct: (map['collectionEfficiencyPct'] as num?)?.toDouble() ?? 0.0,
      averageDsoDays: (map['averageDsoDays'] as num?)?.toInt() ?? 0,
      raw: map,
    );
  }
}
