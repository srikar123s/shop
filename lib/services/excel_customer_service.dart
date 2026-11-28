import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shop/repositories/customer_repository.dart';
import 'package:shop/services/excel_workbook_parser.dart';

class ExcelCustomerRow {
  final int rowNumber;
  final String name;
  final String phone;
  final List<String> phoneNumbers;
  final String? address;
  final double presentBalance;
  final double creditLimit;
  final bool isExisting;
  final int? existingId;
  final String? existingName;
  final String? existingPhone;

  ExcelCustomerRow({
    required this.rowNumber,
    required this.name,
    required this.phone,
    required this.phoneNumbers,
    this.address,
    this.presentBalance = 0.0,
    this.creditLimit = 0.0,
    this.isExisting = false,
    this.existingId,
    this.existingName,
    this.existingPhone,
  });

  bool get hasMultiplePhones => phoneNumbers.length > 1;
}

class ExcelCustomerService {
  /// Parses an uploaded file (.xlsx or .csv) containing customers.
  /// Legacy binary `.xls` workbooks are explicitly rejected.
  static Future<List<ExcelCustomerRow>> parseCustomersFromFile(
    File file,
    CustomerRepository customerRepository,
  ) async {
    final bytes = await file.readAsBytes();
    final rows = ExcelWorkbookParser.parseFileBytes(bytes, file.path);
    return parseCustomersFromRows(rows, customerRepository);
  }

  static List<List<String>> parseCsvBytes(List<int> bytes) =>
      ExcelWorkbookParser.parseCsvBytes(bytes);

  static List<List<String>> parseXlsxArchive(List<int> bytes) =>
      ExcelWorkbookParser.parseXlsxArchive(bytes);

  /// Parses rows with fuzzy column matching and checks against existing customers
  static Future<List<ExcelCustomerRow>> parseCustomersFromRows(
    List<List<String>> rows,
    CustomerRepository customerRepository,
  ) async {
    if (rows.isEmpty) return [];

    // Find header row (first non-empty row)
    int headerRowIndex = 0;
    for (int i = 0; i < rows.length; i++) {
      if (rows[i].any((c) => c.trim().isNotEmpty)) {
        headerRowIndex = i;
        break;
      }
    }

    final rawHeaders =
        rows[headerRowIndex].map((h) => h.trim().toLowerCase()).toList();

    int nameCol = -1;
    final phoneCols = <int>[];
    int addressCol = -1;
    int balanceCol = -1;
    int creditLimitCol = -1;

    for (int c = 0; c < rawHeaders.length; c++) {
      final header = rawHeaders[c];
      if (header.isEmpty) continue;

      // Name / Shop Name
      if (nameCol == -1 &&
          (header.contains('shop') ||
              header.contains('store') ||
              header.contains('firm') ||
              header.contains('party') ||
              header.contains('customer') ||
              header.contains('client') ||
              header == 'name' ||
              header.contains('name') ||
              header.contains('account'))) {
        nameCol = c;
        continue;
      }

      // Phone columns (can match multiple columns, e.g. Phone 1, Phone 2, Mobile)
      if (header.contains('phone') ||
          header.contains('mobile') ||
          header.contains('contact') ||
          header.contains('cell') ||
          header.contains('whatsapp') ||
          header.contains('tel')) {
        phoneCols.add(c);
        continue;
      }

      // Address / Location
      if (addressCol == -1 &&
          (header.contains('location') ||
              header.contains('address') ||
              header.contains('place') ||
              header.contains('city') ||
              header.contains('area') ||
              header.contains('village') ||
              header.contains('town') ||
              header.contains('street') ||
              header.contains('colony') ||
              header.contains('market') ||
              header == 'addr')) {
        addressCol = c;
        continue;
      }

      // Present / Opening Balance
      if (balanceCol == -1 &&
          (header.contains('balance') ||
              header.contains('outstanding') ||
              header.contains('udhaar') ||
              header.contains('due') ||
              header.contains('pending') ||
              header.contains('opening'))) {
        balanceCol = c;
        continue;
      }

      // Credit limit
      if (creditLimitCol == -1 &&
          (header.contains('limit') || header.contains('credit limit'))) {
        creditLimitCol = c;
        continue;
      }
    }

    // Fallbacks if not detected by keywords
    if (nameCol == -1 && rawHeaders.isNotEmpty) nameCol = 0;
    if (phoneCols.isEmpty && rawHeaders.length > 1) phoneCols.add(1);
    if (addressCol == -1 && rawHeaders.length > 2) addressCol = 2;
    if (balanceCol == -1 && rawHeaders.length > 3) balanceCol = 3;

    final customerList = <ExcelCustomerRow>[];

    for (int i = headerRowIndex + 1; i < rows.length; i++) {
      final row = rows[i];
      if (row.isEmpty || row.every((c) => c.trim().isEmpty)) continue;

      final name = nameCol >= 0 && nameCol < row.length ? row[nameCol].trim() : '';
      if (name.isEmpty) continue;

      // Extract phone numbers across all identified phone columns
      final rawPhones = <String>[];
      for (final pCol in phoneCols) {
        if (pCol < row.length && row[pCol].trim().isNotEmpty) {
          rawPhones.add(row[pCol].trim());
        }
      }

      final parsedPhoneNumbers = <String>{};
      for (final rawPhone in rawPhones) {
        final split = _extractPhoneNumbers(rawPhone);
        parsedPhoneNumbers.addAll(split);
      }

      final distinctPhones = parsedPhoneNumbers.toList();
      final combinedPhone = distinctPhones.join(', ');

      // Address
      String? address;
      if (addressCol >= 0 && addressCol < row.length) {
        final rawAddr = row[addressCol].trim();
        if (rawAddr.isNotEmpty) address = rawAddr;
      }

      // Present balance
      double presentBalance = 0.0;
      if (balanceCol >= 0 && balanceCol < row.length) {
        presentBalance = _parseAmount(row[balanceCol]);
      }

      // Credit limit
      double creditLimit = 0.0;
      if (creditLimitCol >= 0 && creditLimitCol < row.length) {
        creditLimit = _parseAmount(row[creditLimitCol]);
      }

      // Check if customer already exists in DB
      final existingCustomer = await customerRepository.findByNameAndPhone(
        name,
        distinctPhones,
      );

      customerList.add(
        ExcelCustomerRow(
          rowNumber: i + 1,
          name: name,
          phone: combinedPhone,
          phoneNumbers: distinctPhones,
          address: address,
          presentBalance: presentBalance,
          creditLimit: creditLimit,
          isExisting: existingCustomer != null,
          existingId: existingCustomer?.id,
          existingName: existingCustomer?.name,
          existingPhone: existingCustomer?.phone,
        ),
      );
    }

    return customerList;
  }

  /// Extracts clean individual phone numbers from an Excel string cell,
  /// cleaning trailing `.0`, scientific notation, and splitting multiple numbers
  static List<String> _extractPhoneNumbers(String raw) {
    if (raw.trim().isEmpty) return [];

    // Check for scientific notation like 9.87654E+09
    if (RegExp(r'^\d+\.?\d*e\+\d+$', caseSensitive: false).hasMatch(raw.trim())) {
      final d = double.tryParse(raw.trim());
      if (d != null) {
        raw = d.toStringAsFixed(0);
      }
    }

    // Split multiple numbers in a single cell (e.g. "9876543210, 9123456789" or "9876543210 / 9123456789")
    final segments = raw.split(RegExp(r'[,/;&|\n\\]+'));
    final results = <String>[];

    for (var seg in segments) {
      seg = seg.trim();
      // Remove Excel trailing .0 (e.g. "9876543210.0")
      if (seg.endsWith('.0')) {
        seg = seg.substring(0, seg.length - 2);
      }

      // Keep only digits and plus sign for international formatting
      final clean = seg.replaceAll(RegExp(r'[^0-9+]'), '');
      if (clean.length >= 6) {
        results.add(clean);
      }
    }

    return results;
  }

  /// Parses monetary amounts supporting ₹, commas, Dr/Cr
  static double _parseAmount(String raw) {
    if (raw.trim().isEmpty) return 0.0;
    final lower = raw.trim().toLowerCase();
    final isCredit = lower.contains('cr') || (raw.trim().startsWith('(') && raw.trim().endsWith(')'));
    String clean = raw.trim()
        .replaceAll('₹', '')
        .replaceAll(',', '')
        .replaceAll(' ', '')
        .replaceAll('(', '')
        .replaceAll(')', '');
    clean = clean.replaceAll(RegExp(r'[a-zA-Z]'), '');
    final amount = double.tryParse(clean) ?? 0.0;
    return isCredit ? -amount : amount;
  }

  /// Exports sample customer import template CSV and opens share sheet
  static Future<void> shareSampleCustomerTemplate() async {
    const csvContent =
        'Shop / Customer Name,Primary Phone,Alternate Phone,Location / Address,Present Balance (Udhaar ₹),Credit Limit (₹)\n'
        'Balaji Traders,9876543210,9123456789,Main Market,12500,50000\n'
        'Sri Sai Kirana,9440123456,,Gandhi Road,4200,25000\n'
        'Lakshmi Supermarket,"9885012345, 9885098765",,Station Road,0,100000\n'
        'Maruti Hardware,9849011223,,Near Bus Stand,8750,0\n';

    final tempDir = await getTemporaryDirectory();
    final file = File('${tempDir.path}/customer_import_sample_template.csv');
    await file.writeAsString(csvContent);

    await Share.shareXFiles(
      [XFile(file.path)],
      text: 'Sample Customer Import Template (.csv / .xlsx format)',
    );
  }
}
