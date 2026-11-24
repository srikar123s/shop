import 'dart:convert';

class Product {
  const Product({
    this.id,
    required this.name,
    required this.category,
    required this.isActive,
    required this.configuration,
    this.needsReview = false,
    this.priceUpdatedAt,
    this.createdAt,
  });

  final int? id;
  final String name;
  final String category;
  final bool isActive;
  final ProductConfiguration configuration;
  final bool needsReview;
  final DateTime? priceUpdatedAt;
  final DateTime? createdAt;

  Product copyWith({
    int? id,
    String? name,
    String? category,
    bool? isActive,
    ProductConfiguration? configuration,
    bool? needsReview,
    DateTime? priceUpdatedAt,
    DateTime? createdAt,
  }) {
    return Product(
      id: id ?? this.id,
      name: name ?? this.name,
      category: category ?? this.category,
      isActive: isActive ?? this.isActive,
      configuration: configuration ?? this.configuration,
      needsReview: needsReview ?? this.needsReview,
      priceUpdatedAt: priceUpdatedAt ?? this.priceUpdatedAt,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  Map<String, Object?> toMap() {
    return {
      'id': id,
      'name': name,
      'category': category,
      'is_active': isActive ? 1 : 0,
      'configuration': jsonEncode(configuration.toMap()),
      'needs_review': needsReview ? 1 : 0,
      'price_updated_at': priceUpdatedAt?.toIso8601String(),
      'created_at': createdAt?.toIso8601String() ?? DateTime.now().toIso8601String(),
    };
  }

  factory Product.fromMap(Map<String, Object?> map) {
    final rawIsActive = map['is_active'];
    final bool active = rawIsActive == 1 || rawIsActive == true || rawIsActive == '1' || rawIsActive == null;
    ProductConfiguration config;
    try {
      final rawConfig = map['configuration'];
      if (rawConfig is Map) {
        config = ProductConfiguration.fromMap(Map<String, dynamic>.from(rawConfig));
      } else if (rawConfig is String && rawConfig.trim().isNotEmpty) {
        config = ProductConfiguration.fromMap(jsonDecode(rawConfig) as Map<String, dynamic>);
      } else {
        config = const ProductConfiguration(steps: []);
      }
    } catch (_) {
      config = const ProductConfiguration(steps: []);
    }
    return Product(
      id: map['id'] as int?,
      name: (map['name'] as String?)?.trim() ?? '',
      category: (map['category'] as String?)?.trim() ?? '',
      isActive: active,
      configuration: config,
      needsReview: (map['needs_review'] as int? ?? 0) == 1,
      priceUpdatedAt: map['price_updated_at'] != null
          ? DateTime.tryParse(map['price_updated_at'].toString())
          : null,
      createdAt: map['created_at'] != null
          ? DateTime.tryParse(map['created_at'].toString())
          : null,
    );
  }
}

class ProductConfiguration {
  const ProductConfiguration({
    required this.steps,
    this.defaultUnit,
    this.unitOptions = const <String>[],
    this.basePrice = 0,
    this.unitConversions = const <String, double>{},
    this.variantPrices = const <String, double>{},
  });

  final List<ProductStep> steps;
  final String? defaultUnit;
  final List<String> unitOptions;
  final double basePrice;
  final Map<String, double> unitConversions;
  final Map<String, double> variantPrices;

  ProductConfiguration copyWith({
    List<ProductStep>? steps,
    String? defaultUnit,
    List<String>? unitOptions,
    double? basePrice,
    Map<String, double>? unitConversions,
    Map<String, double>? variantPrices,
  }) {
    return ProductConfiguration(
      steps: steps ?? this.steps,
      defaultUnit: defaultUnit ?? this.defaultUnit,
      unitOptions: unitOptions ?? this.unitOptions,
      basePrice: basePrice ?? this.basePrice,
      unitConversions: unitConversions ?? this.unitConversions,
      variantPrices: variantPrices ?? this.variantPrices,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'steps': steps.map((e) => e.toMap()).toList(),
      'defaultUnit': defaultUnit,
      'unitOptions': unitOptions,
      'basePrice': basePrice,
      'unitConversions': unitConversions,
      'variantPrices': variantPrices,
    };
  }

  factory ProductConfiguration.fromMap(Map<String, dynamic> map) {
    final rawSteps = map['steps'] as List<dynamic>? ?? <dynamic>[];
    return ProductConfiguration(
      steps: rawSteps
          .map((e) => ProductStep.fromMap(e as Map<String, dynamic>))
          .toList(),
      defaultUnit: map['defaultUnit'] as String?,
      unitOptions: (map['unitOptions'] as List<dynamic>? ?? <dynamic>[])
          .map((e) => e as String)
          .toList(),
      basePrice: (map['basePrice'] as num?)?.toDouble() ?? 0,
      unitConversions: ((map['unitConversions'] as Map<dynamic, dynamic>?) ??
              <dynamic, dynamic>{})
          .map((key, value) =>
              MapEntry(key.toString(), (value as num?)?.toDouble() ?? double.tryParse(value?.toString() ?? '') ?? 0.0)),
      variantPrices: ((map['variantPrices'] as Map<dynamic, dynamic>?) ??
              <dynamic, dynamic>{})
          .map((key, value) =>
              MapEntry(key.toString(), (value as num?)?.toDouble() ?? double.tryParse(value?.toString() ?? '') ?? 0.0)),
    );
  }
}

class ProductStep {
  const ProductStep({
    required this.key,
    required this.label,
    required this.type,
    this.values = const <String>[],
  });

  final String key;
  final String label;
  final String type;
  final List<String> values;

  ProductStep copyWith({
    String? key,
    String? label,
    String? type,
    List<String>? values,
  }) {
    return ProductStep(
      key: key ?? this.key,
      label: label ?? this.label,
      type: type ?? this.type,
      values: values ?? this.values,
    );
  }

  Map<String, dynamic> toMap() {
    return {'key': key, 'label': label, 'type': type, 'values': values};
  }

  factory ProductStep.fromMap(Map<String, dynamic> map) {
    return ProductStep(
      key: (map['key'] as String?) ?? '',
      label: (map['label'] as String?) ?? '',
      type: (map['type'] as String?) ?? 'text',
      values: (map['values'] as List<dynamic>? ?? <dynamic>[])
          .map((e) => e.toString())
          .toList(),
    );
  }
}
