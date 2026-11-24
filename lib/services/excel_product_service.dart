import 'dart:convert';
import 'dart:io';
import 'package:archive/archive.dart';
import 'package:csv/csv.dart';
import 'package:excel/excel.dart' as xl;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shop/models/product.dart';

class ExcelProductService {
  static String normalizeUnit(String raw) {
    final lower = raw.trim().toLowerCase();
    if (lower == 'piece' ||
        lower == 'pieces' ||
        lower == 'pcs' ||
        lower == 'pc' ||
        lower == 'nos' ||
        lower == 'no') {
      return 'Piece';
    }
    if (lower == 'box' || lower == 'boxes' || lower == 'bx') {
      return 'Box';
    }
    if (lower == 'kg' || lower == 'kgs' || lower == 'kilo' || lower == 'kilogram') {
      return 'Kg';
    }
    if (lower == 'litre' ||
        lower == 'litres' ||
        lower == 'liter' ||
        lower == 'liters' ||
        lower == 'l' ||
        lower == 'ltr' ||
        lower == 'ltrs') {
      return 'Litre';
    }
    if (lower == 'packet' ||
        lower == 'packets' ||
        lower == 'pkt' ||
        lower == 'pkts' ||
        lower == 'pack' ||
        lower == 'packs') {
      return 'Packet';
    }
    if (lower == 'feet' || lower == 'feets' || lower == 'ft' || lower == 'foot') {
      return 'Feet';
    }
    if (lower == 'meter' || lower == 'meters' || lower == 'mtr' || lower == 'm') {
      return 'Meter';
    }
    if (lower == 'set' || lower == 'sets') {
      return 'Set';
    }
    if (lower == 'roll' || lower == 'rolls') {
      return 'Roll';
    }
    if (raw.trim().isEmpty) return 'Piece';
    return raw.trim()[0].toUpperCase() + raw.trim().substring(1);
  }

  /// Parses a file (.xlsx, .xls, or .csv) with fuzzy header detection and auto-grouping
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
    try {
      final content = utf8.decode(bytes);
      final rawRows = const CsvToListConverter(eol: '\n').convert(content);
      return rawRows
          .map((r) => r.map((c) => c?.toString().trim() ?? '').toList())
          .where((r) => r.any((c) => c.isNotEmpty))
          .toList();
    } catch (_) {
      final content = String.fromCharCodes(bytes);
      final rawRows = const CsvToListConverter(eol: '\n').convert(content);
      return rawRows
          .map((r) => r.map((c) => c?.toString().trim() ?? '').toList())
          .where((r) => r.any((c) => c.isNotEmpty))
          .toList();
    }
  }

  static List<List<String>> parseXlsxArchive(List<int> bytes) {
    try {
      final excel = xl.Excel.decodeBytes(bytes);
      final List<List<String>> xlRows = [];
      for (final table in excel.tables.keys) {
        final sheet = excel.tables[table];
        if (sheet == null) continue;
        for (final row in sheet.rows) {
          final rowStrings =
              row.map((cell) => cell?.value?.toString().trim() ?? '').toList();
          if (rowStrings.any((c) => c.isNotEmpty)) {
            xlRows.add(rowStrings);
          }
        }
        if (xlRows.isNotEmpty) break;
      }
      if (xlRows.isNotEmpty) return xlRows;
    } catch (_) {}

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

  /// Upgraded 100x parser supporting both standard multi-option tables
  /// and flat variant rows with auto-grouping and fuzzy column matching
  static List<Product> parseProductsFromRows(List<List<String>> rows) {
    if (rows.isEmpty) return <Product>[];

    // Find header row (first row with at least 1 non-empty cell)
    int headerRowIndex = 0;
    for (int i = 0; i < rows.length; i++) {
      if (rows[i].any((c) => c.trim().isNotEmpty)) {
        headerRowIndex = i;
        break;
      }
    }

    final rawHeaders = rows[headerRowIndex].map((h) => h.trim().toLowerCase()).toList();

    int findHeaderIndex(List<String> variants) {
      for (final v in variants) {
        final idx = rawHeaders.indexWhere((h) => h == v || h.contains(v));
        if (idx != -1) return idx;
      }
      return -1;
    }

    final nameIdx = findHeaderIndex([
      'product name',
      'product_name',
      'product',
      'item name',
      'item_name',
      'item',
      'item description',
      'description',
      'title',
      'name',
    ]);

    if (nameIdx == -1) return <Product>[];

    final categoryIdx = findHeaderIndex([
      'category name',
      'category',
      'group name',
      'group',
      'department',
      'dept',
      'section',
    ]);

    final unitIdx = findHeaderIndex([
      'default unit',
      'unit of measure',
      'uom',
      'unit',
      'packaging',
      'packing',
      'measure',
    ]);

    final conversionIdx = findHeaderIndex([
      'unit conversion',
      'conversion',
      'unit conversions',
      'conversions',
      'packing size',
      'packet conversion',
    ]);

    final basePriceIdx = findHeaderIndex([
      'base price',
      'selling price',
      'unit price',
      'standard rate',
      'rate',
      'price',
      'mrp',
      'cost',
      'amount',
    ]);

    final brandIdx = findHeaderIndex(['brands', 'brand', 'company', 'make', 'mfr']);
    final colourIdx = findHeaderIndex(['colours', 'colour', 'colors', 'color', 'shade']);
    final sizeIdx = findHeaderIndex(['sizes', 'size', 'dimension', 'length', 'gauge']);
    final typeIdx = findHeaderIndex(['types', 'type', 'grade', 'variant']);
    final weightIdx = findHeaderIndex(['weights', 'weight', 'capacity', 'volume']);
    final modelIdx = findHeaderIndex(['models', 'model', 'specification', 'spec']);

    final stepIndices = <String, Map<String, dynamic>>{
      'brand': {'idx': brandIdx, 'label': 'Brand'},
      'colour': {'idx': colourIdx, 'label': 'Colour'},
      'size': {'idx': sizeIdx, 'label': 'Size'},
      'type': {'idx': typeIdx, 'label': 'Type'},
      'weight': {'idx': weightIdx, 'label': 'Weight'},
      'model': {'idx': modelIdx, 'label': 'Model'},
    };

    final productMap = <String, Product>{};

    for (int r = headerRowIndex + 1; r < rows.length; r++) {
      final row = rows[r];
      if (row.length <= nameIdx) continue;

      final name = row[nameIdx].trim();
      if (name.isEmpty) continue;

      final category = (categoryIdx != -1 && row.length > categoryIdx)
          ? (row[categoryIdx].trim().isNotEmpty ? row[categoryIdx].trim() : 'General')
          : 'General';

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
          ? double.tryParse(row[basePriceIdx].replaceAll(RegExp(r'[^\d.]'), '').trim()) ?? 0.0
          : 0.0;

      // Extract row's individual step choices
      final rowStepValues = <String, List<String>>{};
      stepIndices.forEach((key, info) {
        final idx = info['idx'] as int;
        if (idx != -1 && row.length > idx) {
          final rawVal = row[idx].trim();
          if (rawVal.isNotEmpty) {
            final choices = rawVal
                .split(RegExp(r'[,|/]'))
                .map((c) => c.trim())
                .where((c) => c.isNotEmpty)
                .toList();
            if (choices.isNotEmpty) {
              rowStepValues[key] = choices;
            }
          }
        }
      });

      // Parse combination prices from cells e.g. "UF + 3.15mm = 150" or "4 inch = 45"
      final variantPrices = <String, double>{};
      final priceAssignRegExp = RegExp(r'([^=;:\n]+)\s*[:=]\s*([\d.]+)');

      for (int c = 0; c < row.length; c++) {
        final cellText = row[c].trim();
        if (cellText.isEmpty) continue;
        if (c == conversionIdx) continue;

        final matches = priceAssignRegExp.allMatches(cellText);
        for (final match in matches) {
          final comboStr = match.group(1)!.trim();
          final priceVal = double.tryParse(match.group(2)!.trim());

          if (comboStr.isNotEmpty && priceVal != null && priceVal > 0) {
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

      // If this row has specific single values (flat list entry) and a price,
      // map the combination of this row's choices to this row's basePrice!
      if (basePrice > 0 && rowStepValues.isNotEmpty) {
        final singleComboValues = <String>[];
        for (final key in stepIndices.keys) {
          if (rowStepValues.containsKey(key) && rowStepValues[key]!.length == 1) {
            singleComboValues.add(rowStepValues[key]!.first);
          }
        }
        if (singleComboValues.isNotEmpty) {
          final comboKey = singleComboValues.join(' • ');
          variantPrices[comboKey] = basePrice;
          variantPrices[comboKey.toLowerCase()] = basePrice;
          for (final val in singleComboValues) {
            variantPrices[val] = basePrice;
            variantPrices[val.toLowerCase()] = basePrice;
          }
        }
      }

      // Build product steps
      final steps = <ProductStep>[];
      stepIndices.forEach((key, info) {
        final label = info['label'] as String;
        if (rowStepValues.containsKey(key)) {
          steps.add(ProductStep(
            key: key,
            label: label,
            type: 'select',
            values: rowStepValues[key]!,
          ));
        }
      });

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
          id: existing.id,
          name: name,
          category: category != 'General' ? category : existing.category,
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
          category: category,
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

  /// Shares a rich, professional sample CSV template
  static Future<void> shareSampleTemplate() async {
    const csvData = [
      [
        'Product Name',
        'Category',
        'Default Unit',
        'Unit Conversion',
        'Base Price',
        'Brands',
        'Sizes',
        'Colours',
        'Types',
        'Weights',
        'Combination Prices'
      ],
      [
        'Welding Rod',
        'Welding',
        'Box',
        '1 Box = 20 Pieces',
        '140',
        'POWERTEX, UF',
        '3.15mm, 4mm',
        '',
        'Steel, General',
        '',
        'UF + 3.15mm = 150; POWERTEX + 3.15mm = 140'
      ],
      [
        'Cutting Wheel',
        'Abrasives',
        'Piece',
        '1 Box = 25 Pieces',
        '45',
        'BOSCH, POWERTEX',
        '4 inch, 7 inch',
        '',
        '',
        '',
        'BOSCH + 4 inch = 55; BOSCH + 7 inch = 110; POWERTEX + 4 inch = 45'
      ],
      [
        'Wall Paint Primer',
        'Paints',
        'Litre',
        '1 Box = 12 Litre',
        '220',
        'Asian Paints, Berger',
        '1 Litre, 4 Litre, 10 Litre, 20 Litre',
        'White',
        '',
        '',
        '1 Litre = 220; 4 Litre = 820; 10 Litre = 1950; 20 Litre = 3700'
      ],
      [
        'PVC Pipe 4 inch',
        'Plumbing',
        'Feet',
        '1 Bundle = 10 Feet',
        '65',
        'Supreme, Finolex, Ashirvad',
        '10 Feet, 20 Feet',
        'Grey, White',
        'Heavy, Medium',
        '',
        ''
      ],
      [
        'Safety Helmet',
        'Safety Gear',
        'Piece',
        '',
        '180',
        'KARAM',
        '',
        'Yellow, White, Blue',
        '',
        '',
        ''
      ],
      [
        'Metal Paste',
        'Adhesives',
        'Piece',
        '1 Box = 20 Pieces',
        '20',
        '',
        '',
        '',
        '',
        '100g, 250g, 500g',
        '100g = 20; 250g = 40; 500g = 100'
      ],
    ];

    final directory = await getTemporaryDirectory();
    final csvString =
        const ListToCsvConverter(fieldDelimiter: ',').convert(csvData);
    final csvPath = '${directory.path}/sample_shop_products_template.csv';
    final csvFile = File(csvPath);
    await csvFile.writeAsString(csvString);

    await Share.shareXFiles(
      [XFile(csvPath)],
      text: 'Sample Product Catalog Excel/CSV Template for Shop App',
    );
  }
}
