import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:shop/services/excel_product_service.dart';

void main() {
  test('excel file parsing unit normalization and combination prices', () async {
    final file = File(r'c:\Users\srikar\OneDrive\Desktop\shop\simple_shop_product_catalog_with_unit_conversion.xlsx');
    final products = await ExcelProductService.parseProductsFromFile(file);

    expect(products.isNotEmpty, isTrue);

    final weldingRod = products.firstWhere((p) => p.name == 'Welding Rod');
    expect(weldingRod.configuration.unitOptions, containsAll(['Box', 'Piece']));
    expect(weldingRod.configuration.unitOptions.contains('Pieces'), isFalse);
    expect(weldingRod.configuration.variantPrices.isNotEmpty, isTrue);
  });
}
