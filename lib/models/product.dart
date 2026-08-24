import 'dart:convert';

class Product {
  const Product({
    this.id,
    required this.name,
    required this.category,
    required this.isActive,
    required this.configuration,
  });

  final int? id;
  final String name;
  final String category;
  final bool isActive;
  final ProductConfiguration configuration;

  Product copyWith({
    int? id,
    String? name,
    String? category,
    bool? isActive,
    ProductConfiguration? configuration,
  }) {
    return Product(
      id: id ?? this.id,
      name: name ?? this.name,
      category: category ?? this.category,
      isActive: isActive ?? this.isActive,
      configuration: configuration ?? this.configuration,
    );
  }

  Map<String, Object?> toMap() {
    return {
      'id': id,
      'name': name,
      'category': category,
      'is_active': isActive ? 1 : 0,
      'configuration': jsonEncode(configuration.toMap()),
    };
  }

  factory Product.fromMap(Map<String, Object?> map) {
    return Product(
      id: map['id'] as int?,
      name: map['name'] as String,
      category: map['category'] as String,
      isActive: (map['is_active'] as int) == 1,
      configuration: ProductConfiguration.fromMap(
        jsonDecode(map['configuration'] as String) as Map<String, dynamic>,
      ),
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
              MapEntry(key.toString(), (value as num).toDouble())),
      variantPrices: ((map['variantPrices'] as Map<dynamic, dynamic>?) ??
              <dynamic, dynamic>{})
          .map((key, value) =>
              MapEntry(key.toString(), (value as num).toDouble())),
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
      key: map['key'] as String,
      label: map['label'] as String,
      type: map['type'] as String,
      values: (map['values'] as List<dynamic>? ?? <dynamic>[])
          .map((e) => e as String)
          .toList(),
    );
  }
}
