class Customer {
  const Customer({
    this.id,
    required this.name,
    this.phone,
    this.address,
    this.creditLimit = 0.0,
    required this.createdAt,
  });

  final int? id;
  final String name;
  final String? phone;
  final String? address;
  final double creditLimit;
  final DateTime createdAt;

  Customer copyWith({
    int? id,
    String? name,
    String? phone,
    String? address,
    double? creditLimit,
    DateTime? createdAt,
  }) {
    return Customer(
      id: id ?? this.id,
      name: name ?? this.name,
      phone: phone ?? this.phone,
      address: address ?? this.address,
      creditLimit: creditLimit ?? this.creditLimit,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  Map<String, Object?> toMap() {
    return {
      'id': id,
      'name': name,
      'phone': phone,
      'address': address,
      'credit_limit': creditLimit,
      'created_at': createdAt.toIso8601String(),
    };
  }

  factory Customer.fromMap(Map<String, Object?> map) {
    return Customer(
      id: map['id'] as int?,
      name: map['name'] as String,
      phone: map['phone'] as String?,
      address: map['address'] as String?,
      creditLimit: (map['credit_limit'] as num?)?.toDouble() ?? 0.0,
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }
}
