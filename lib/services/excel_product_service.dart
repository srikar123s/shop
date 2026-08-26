import 'dart:convert';
import 'dart:io';
import 'package:archive/archive.dart';
import 'package:csv/csv.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shop/models/product.dart';

class ExcelProductService {
  static String normalizeUnit(String raw) {
    final lower = raw.trim().toLowerCase();
    if (lower == 'piece' || lower == 'pieces' || lower == 'pcs' || lower == 'pc') {
      return 'Piece';
    }
    if (lower == 'box' || lower == 'boxes') {
      return 'Box';
    }
    if (lower == 'kg' || lower == 'kgs') {
      return 'Kg';
    }
    if (lower == 'litre' || lower == 'litres' || lower == 'liter' || lower == 'liters' || lower == 'l') {
      return 'Litre';
    }
    if (lower == 'packet' || lower == 'packets' || lower == 'pkt' || lower == 'pkts') {
      return 'Packet';
    }
    if (lower == 'feet' || lower == 'feets' || lower == 'ft') {
      return 'Feet';
    }
    if (raw.trim().isEmpty) return 'Piece';
    return raw.trim()[0].toUpperCase() + raw.trim().substring(1);
  }

  /// Parses a file (Excel .xlsx / .xls or .csv) matching the exact catalog format.
  static Future<List<Product>> parseProductsFromFile(File file) async {
    final filePath = file.path.toLowerCase();
    final bytes = await file.readAsBytes();

    List<List<String>> rows = [];
    if (filePath.endsWith('.xlsx') || filePath.endsWith('.xls')) {
      try {
        rows = parseXlsxArchive(bytes);
      } catch (_) {
        rows = parseCsvBytes(bytes);
      }
    } else {
      rows = parseCsvBytes(bytes);
    }

    return parseProductsFromRows(rows);
  }

  static List<List<String>> parseCsvBytes(List<int> bytes) {
    final content = String.fromCharCodes(bytes);
    final rawRows = const CsvToListConverter(eol: '\n').convert(content);
    return rawRows
        .map((r) => r.map((c) => c?.toString().trim() ?? '').toList())
        .toList();
  }

  static List<List<String>> parseXlsxArchive(List<int> bytes) {
    final archive = ZipDecoder().decodeBytes(bytes);
    final sharedStrings = <String>[];
    final ssFile = archive.findFile('xl/sharedStrings.xml');
    if (ssFile != null) {
      final content = utf8.decode(ssFile.content as List<int>);
      final tReg = RegExp(r'<t[^>]*>(.*?)</t>', dotAll: true);
      final siReg = RegExp(r'<si>(.*?)</si>', dotAll: true);
      for (final siMatch in siReg.allMatches(content)) {
        final siContent = siMatch.group(1) ?? '';
        final tMatches = tReg.allMatches(siContent);
        final text = tMatches.map((m) => _unescapeXml(m.group(1) ?? '')).join();
        sharedStrings.add(text);
      }
    }

    ArchiveFile? sheetFile;
    for (final file in archive.files) {
      if (file.name.startsWith('xl/worksheets/sheet') &&
          file.name.endsWith('.xml')) {
        sheetFile = file;
        break;
      }
    }
    if (sheetFile == null) return [];

    final sheetXml = utf8.decode(sheetFile.content as List<int>);
    final rows = <List<String>>[];

    final rowRegExp =
        RegExp(r'<row[^>]*r="(\d+)"[^>]*>(.*?)</row>', dotAll: true);
    final cellRegExp =
        RegExp(r'<c[^>]*r="([A-Z]+)\d+"([^>]*)>(.*?)</c>', dotAll: true);
    final valRegExp = RegExp(r'<v>(.*?)</v>', dotAll: true);
    final inlineStrRegExp = RegExp(r'<t[^>]*>(.*?)</t>', dotAll: true);

    for (final rowMatch in rowRegExp.allMatches(sheetXml)) {
      final rowContent = rowMatch.group(2) ?? '';
      final rowValuesMap = <String, String>{};

      for (final cellMatch in cellRegExp.allMatches(rowContent)) {
        final colRef = cellMatch.group(1)!;
        final attrs = cellMatch.group(2) ?? '';
        final cellInner = cellMatch.group(3) ?? '';

        String cellValue = '';
        if (attrs.contains('t="s"')) {
          final vMatch = valRegExp.firstMatch(cellInner);
          if (vMatch != null) {
            final idx = int.tryParse(vMatch.group(1) ?? '');
            if (idx != null && idx < sharedStrings.length) {
              cellValue = sharedStrings[idx];
            }
          }
        } else if (attrs.contains('t="inlineStr"')) {
          final tMatches = inlineStrRegExp.allMatches(cellInner);
          cellValue =
              tMatches.map((m) => _unescapeXml(m.group(1) ?? '')).join();
        } else {
          final vMatch = valRegExp.firstMatch(cellInner);
          if (vMatch != null) {
            cellValue = _unescapeXml(vMatch.group(1) ?? '');
          } else {
            final tMatch = inlineStrRegExp.firstMatch(cellInner);
            if (tMatch != null) {
              cellValue = _unescapeXml(tMatch.group(1) ?? '');
            }
          }
        }

        rowValuesMap[colRef] = cellValue.trim();
      }

      if (rowValuesMap.isNotEmpty) {
        int maxColIdx = 0;
        for (final col in rowValuesMap.keys) {
          final idx = _colRefToIndex(col);
          if (idx > maxColIdx) maxColIdx = idx;
        }
        final rowList = List<String>.filled(maxColIdx + 1, '');
        for (final entry in rowValuesMap.entries) {
          rowList[_colRefToIndex(entry.key)] = entry.value;
        }
        rows.add(rowList);
      }
    }

    return rows;
  }

  static List<Product> parseProductsFromRows(List<List<String>> rows) {
    if (rows.isEmpty) return <Product>[];

    final headers = rows.first.map((h) => h.trim().toLowerCase()).toList();

    int getIdx(List<String> matches) {
      return headers.indexWhere((h) => matches.contains(h));
    }

    final nameIdx = getIdx(['product name', 'name', 'product', 'item']);
    if (nameIdx == -1) return <Product>[];

    final unitIdx = getIdx(['unit', 'default unit']);
    final conversionIdx =
        getIdx(['unit conversion', 'conversion', 'unit conversions']);
    final brandIdx = getIdx(['brands', 'brand']);
    final colourIdx = getIdx(['colours', 'colour', 'colors', 'color']);
    final sizeIdx = getIdx(['sizes', 'size']);
    final typeIdx = getIdx(['types', 'type']);
    final weightIdx = getIdx(['weights', 'weight']);
    final modelIdx = getIdx(['models', 'model']);
    final basePriceIdx = getIdx(['base price', 'rate']);

    final stepIndices = <String, Map<String, dynamic>>{
      'brand': {'idx': brandIdx, 'label': 'Brand'},
      'colour': {'idx': colourIdx, 'label': 'Colour'},
      'size': {'idx': sizeIdx, 'label': 'Size'},
      'type': {'idx': typeIdx, 'label': 'Type'},
      'weight': {'idx': weightIdx, 'label': 'Weight'},
      'model': {'idx': modelIdx, 'label': 'Model'},
    };

    final productMap = <String, Product>{};

    for (int r = 1; r < rows.length; r++) {
      final row = rows[r];
      if (row.length <= nameIdx) continue;

      final name = row[nameIdx].trim();
      if (name.isEmpty) continue;

      final rawDefaultUnit = (unitIdx != -1 && row.length > unitIdx)
          ? row[unitIdx].trim()
          : 'Piece';
      final defaultUnit = normalizeUnit(rawDefaultUnit);

      final unitOptionsSet = <String>{defaultUnit};
      final unitConversions = <String, double>{defaultUnit: 1.0};

      // Parse Unit Conversion string, e.g. "1 Box = 20 Pieces" or "1 Packet = 10 Pieces"
      if (conversionIdx != -1 && row.length > conversionIdx) {
        final rawConv = row[conversionIdx].trim();
        if (rawConv.isNotEmpty) {
          final parts = rawConv.split('=');
          if (parts.length == 2) {
            final left = parts[0].trim();
            final right = parts[1].trim();

            final leftUnitMatch = RegExp(r'1\s+([A-Za-z]+)').firstMatch(left);
            final rightMatch = RegExp(r'([\d.]+)\s*([A-Za-z]+)').firstMatch(right);

            final uLeft = normalizeUnit(leftUnitMatch?.group(1) ??
                (defaultUnit.isNotEmpty ? defaultUnit : 'Box'));
            if (rightMatch != null) {
              final factor = double.tryParse(rightMatch.group(1)!) ?? 1.0;
              final uRight = normalizeUnit(rightMatch.group(2)!);

              unitOptionsSet.add(uLeft);
              unitOptionsSet.add(uRight);

              unitConversions[uLeft] = factor;
              unitConversions.putIfAbsent(uRight, () => 1.0);
            }
          }
        }
      }

      final unitOptions = unitOptionsSet.toList();

      final basePrice = (basePriceIdx != -1 && row.length > basePriceIdx)
          ? double.tryParse(row[basePriceIdx].trim()) ?? 0.0
          : 0.0;

      // Build Steps in standard order
      final steps = <ProductStep>[];
      stepIndices.forEach((key, info) {
        final idx = info['idx'] as int;
        final label = info['label'] as String;
        if (idx != -1 && row.length > idx) {
          final rawVal = row[idx].trim();
          if (rawVal.isNotEmpty) {
            final choices = rawVal
                .split(RegExp(r'[,|]'))
                .map((c) => c.trim())
                .where((c) => c.isNotEmpty)
                .toList();
            if (choices.isNotEmpty) {
              steps.add(ProductStep(
                key: key,
                label: label,
                type: 'select',
                values: choices,
              ));
            }
          }
        }
      });

      // Parse Combination Prices by scanning ALL cells in the row for price assignment patterns:
      // Pattern: "UF + 3.15mm + Steel = 150" or "BOSCH + 4 inch = 55"
      final variantPrices = <String, double>{};
      final priceAssignRegExp = RegExp(r'([^=;:\n]+)\s*[:=]\s*([\d.]+)');

      for (int c = 0; c < row.length; c++) {
        final cellText = row[c].trim();
        if (cellText.isEmpty) continue;
        if (c == conversionIdx) continue; // Skip unit conversion column e.g. "1 Box = 20 Pieces"

        final matches = priceAssignRegExp.allMatches(cellText);
        for (final match in matches) {
          final comboStr = match.group(1)!.trim();
          final priceVal = double.tryParse(match.group(2)!.trim());

          if (comboStr.isNotEmpty && priceVal != null && priceVal > 0) {
            // Check if comboStr is not a unit conversion like "1 Box"
            if (RegExp(r'^\d+\s+[A-Za-z]+$').hasMatch(comboStr)) continue;

            final optionVals = comboStr
                .split(RegExp(r'[\+\•\-]'))
                .map((v) => v.trim())
                .where((v) => v.isNotEmpty)
                .toList();
            final normalizedKey = optionVals.join(' • ');

            variantPrices[normalizedKey] = priceVal;
            variantPrices[normalizedKey.toLowerCase()] = priceVal;
            variantPrices[comboStr] = priceVal;
            variantPrices[comboStr.toLowerCase()] = priceVal;
          }
        }
      }

      final lowerName = name.toLowerCase();
      if (productMap.containsKey(lowerName)) {
        final existing = productMap[lowerName]!;
        final mergedVariantPrices = <String, double>{
          ...existing.configuration.variantPrices,
          ...variantPrices,
        };
        final mergedSteps = <ProductStep>[...existing.configuration.steps];
        for (final newStep in steps) {
          final idx = mergedSteps.indexWhere((s) => s.key == newStep.key);
          if (idx >= 0) {
            final combinedValues = <String>{
              ...mergedSteps[idx].values,
              ...newStep.values
            }.toList();
            mergedSteps[idx] =
                mergedSteps[idx].copyWith(values: combinedValues);
          } else {
            mergedSteps.add(newStep);
          }
        }

        productMap[lowerName] = Product(
          name: name,
          category: 'General',
          isActive: true,
          configuration: ProductConfiguration(
            basePrice:
                basePrice > 0 ? basePrice : existing.configuration.basePrice,
            defaultUnit: defaultUnit.isNotEmpty
                ? defaultUnit
                : existing.configuration.defaultUnit,
            unitOptions: <String>{
              ...existing.configuration.unitOptions,
              ...unitOptions
            }.toList(),
            unitConversions: <String, double>{
              ...existing.configuration.unitConversions,
              ...unitConversions
            },
            steps: mergedSteps,
            variantPrices: mergedVariantPrices,
          ),
        );
      } else {
        productMap[lowerName] = Product(
          name: name,
          category: 'General',
          isActive: true,
          configuration: ProductConfiguration(
            basePrice: basePrice,
            defaultUnit: defaultUnit.isEmpty ? unitOptions.first : defaultUnit,
            unitOptions: unitOptions,
            unitConversions: unitConversions,
            steps: steps,
            variantPrices: variantPrices,
          ),
        );
      }
    }

    return productMap.values.toList();
  }

  static int _colRefToIndex(String col) {
    int result = 0;
    for (int i = 0; i < col.length; i++) {
      result = result * 26 + (col.codeUnitAt(i) - 64);
    }
    return result - 1;
  }

  static String _unescapeXml(String text) {
    return text
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&amp;', '&')
        .replaceAll('&quot;', '"')
        .replaceAll('&apos;', "'");
  }

  /// Shares the sample template file.
  static Future<void> shareSampleTemplate() async {
    const templateFile =
        r'c:\Users\srikar\OneDrive\Desktop\shop\simple_shop_product_catalog_with_unit_conversion.xlsx';
    final sourceFile = File(templateFile);
    final directory = await getTemporaryDirectory();
    final targetPath =
        '${directory.path}/simple_shop_product_catalog_with_unit_conversion.xlsx';

    if (await sourceFile.exists()) {
      await sourceFile.copy(targetPath);
      await Share.shareXFiles(
        [XFile(targetPath)],
        text: 'Sample Product Catalog Excel Template for Shop App',
      );
      return;
    }

    // Fallback CSV generation if file not found locally
    const csvData = [
      [
        'Product Name',
        'Unit',
        'Unit Conversion',
        'Brands',
        'Colours',
        'Sizes',
        'Types',
        'Weights',
        'Models',
        'Combination Prices',
        'Notes'
      ],
      [
        'Welding Rod',
        'Box',
        '1 Box = 20 Pieces',
        'POWERTEX, UF',
        '',
        '3.15mm, 4mm',
        'Steel, General',
        '',
        '',
        'UF + 3.15mm + Steel = 150; POWERTEX + 3.15mm + Steel = 140',
        ''
      ],
      [
        'Cutting Wheel',
        'Piece',
        '1 Box = 25 Pieces',
        'BOSCH, POWERTEX',
        '',
        '4 inch, 7 inch',
        '',
        '',
        '',
        'BOSCH + 4 inch = 55; BOSCH + 7 inch = 110',
        ''
      ],
      ['Safety Helmet', 'Piece', '', 'KARAM', '', '', '', '', '', '', ''],
      [
        'Paint',
        'Litre',
        '1 Box = 12 Litres',
        '',
        'Red, Blue, Green, White',
        '1 L, 4 L, 10 L, 20 L',
        '',
        '',
        '',
        '',
        'Example only'
      ],
    ];

    final csvString =
        const ListToCsvConverter(fieldDelimiter: ',').convert(csvData);
    final csvPath = '${directory.path}/sample_products_template.csv';
    final csvFile = File(csvPath);
    await csvFile.writeAsString(csvString);

    await Share.shareXFiles(
      [XFile(csvPath)],
      text: 'Sample Product Catalog Template for Shop App',
    );
  }
}
