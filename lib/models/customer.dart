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

  /// Returns individual phone numbers if customer has multiple (e.g. "9876543210, 9123456789" -> ["9876543210", "9123456789"])
  List<String> get phoneNumbers => extractNumbers(phone);

  /// Helper to extract list of cleaned individual phone numbers from a raw string
  static List<String> extractNumbers(String? raw) {
    if (raw == null || raw.trim().isEmpty) return const [];
    final seenCanonical = <String>{};
    final result = <String>[];
    for (final part in raw.split(RegExp(r'[,/;&|\n]+'))) {
      final trimmed = part.trim();
      if (trimmed.isEmpty) continue;
      final canonical = normalizePhoneDigits(trimmed);
      final key = canonical.length >= 6 ? canonical : trimmed;
      if (seenCanonical.add(key)) {
        result.add(trimmed);
      }
    }
    return result;
  }

  /// Normalizes a phone number to canonical digits so '+91 93924 49356',
  /// '09392449356', '919392449356', and '9392449356' all match.
  static String normalizePhoneDigits(String raw) {
    var digits = raw.replaceAll(RegExp(r'[^0-9]'), '');
    digits = digits.replaceFirst(RegExp(r'^0+'), '');
    if (digits.length > 10) {
      digits = digits.substring(digits.length - 10);
    }
    return digits;
  }

  /// Returns true if two raw phone strings represent the same phone number.
  static bool phonesMatch(String a, String b) {
    final na = normalizePhoneDigits(a);
    final nb = normalizePhoneDigits(b);
    if (na.length < 6 || nb.length < 6) return false;
    return na == nb;
  }

  /// Returns the primary (first) phone number
  String? get primaryPhone {
    final list = phoneNumbers;
    return list.isNotEmpty ? list.first : null;
  }

  /// Whether the customer has more than one phone number registered
  bool get hasMultiplePhones => phoneNumbers.length > 1;

  /// Clean display string for multiple phone numbers
  String get displayPhone => phoneNumbers.isNotEmpty ? phoneNumbers.join(' • ') : (phone ?? '');

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
      name: (map['name'] as String?)?.trim() ?? 'Unknown Customer',
      phone: map['phone'] as String?,
      address: map['address'] as String?,
      creditLimit: (map['credit_limit'] as num?)?.toDouble() ?? 0.0,
      createdAt: DateTime.tryParse(map['created_at']?.toString() ?? '') ?? DateTime.now(),
    );
  }
}
