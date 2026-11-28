import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:csv/csv.dart';
import 'package:xml/xml.dart';

/// Shared workbook parsing helpers for `.xlsx` (XML DOM via `package:xml`)
/// and `.csv` imports, with strict rejection of legacy binary `.xls` files.
class ExcelWorkbookParser {
  static final RegExp _colLettersRegExp = RegExp(r'^([A-Za-z]+)');

  /// Returns true if [bytes] begins with the OLE2/BIFF Compound File Binary
  /// signature (`D0 CF 11 E0`) used by legacy `.xls` workbooks.
  static bool isLegacyBinaryXls(List<int> bytes) {
    return bytes.length >= 4 &&
        bytes[0] == 0xD0 &&
        bytes[1] == 0xCF &&
        bytes[2] == 0x11 &&
        bytes[3] == 0xE0;
  }

  /// Parses an `.xlsx` byte buffer using proper XML DOM parsing (`XmlDocument`)
  /// so attribute ordering, quoting style, self-closing empty cells, rich-text
  /// runs, and XML entity escaping are handled accurately.
  static List<List<String>> parseXlsxArchive(List<int> bytes) {
    final archive = ZipDecoder().decodeBytes(bytes);

    final sharedStrings = <String>[];
    final ssFile = _findArchiveEntry(archive, 'xl/sharedStrings.xml');
    if (ssFile != null) {
      final ssXml = utf8.decode(ssFile.content as List<int>);
      final ssDoc = XmlDocument.parse(ssXml);
      for (final si in ssDoc.findAllElements('si')) {
        final text = si.findAllElements('t').map((t) => t.innerText).join();
        sharedStrings.add(text);
      }
    }

    ArchiveFile? sheetFile =
        _findArchiveEntry(archive, 'xl/worksheets/sheet1.xml');
    if (sheetFile == null) {
      for (final file in archive.files) {
        final lower = file.name.toLowerCase();
        if (lower.startsWith('xl/worksheets/sheet') && lower.endsWith('.xml')) {
          sheetFile = file;
          break;
        }
      }
    }
    if (sheetFile == null) return const [];

    final sheetXml = utf8.decode(sheetFile.content as List<int>);
    final sheetDoc = XmlDocument.parse(sheetXml);
    final rows = <List<String>>[];

    for (final rowEl in sheetDoc.findAllElements('row')) {
      final rowValuesByIndex = <int, String>{};
      int nextSequentialCol = 0;

      for (final cellEl in rowEl.findElements('c')) {
        final refAttr = cellEl.getAttribute('r') ?? '';
        final refMatch = _colLettersRegExp.firstMatch(refAttr);
        final colIdx = refMatch != null
            ? colRefToIndex(refMatch.group(1)!.toUpperCase())
            : nextSequentialCol;
        nextSequentialCol = colIdx + 1;

        final cellType = cellEl.getAttribute('t') ?? '';
        String cellValue = '';

        if (cellType == 's') {
          final vText = cellEl.getElement('v')?.innerText.trim() ?? '';
          final idx = int.tryParse(vText);
          if (idx != null && idx >= 0 && idx < sharedStrings.length) {
            cellValue = sharedStrings[idx];
          }
        } else if (cellType == 'inlineStr') {
          cellValue =
              cellEl.findAllElements('t').map((t) => t.innerText).join();
        } else {
          final vEl = cellEl.getElement('v');
          if (vEl != null) {
            cellValue = vEl.innerText;
          } else {
            final tEls = cellEl.findAllElements('t');
            if (tEls.isNotEmpty) {
              cellValue = tEls.map((t) => t.innerText).join();
            }
          }
        }

        rowValuesByIndex[colIdx] = cellValue.trim();
      }

      if (rowValuesByIndex.isNotEmpty) {
        var maxColIdx = 0;
        for (final idx in rowValuesByIndex.keys) {
          if (idx > maxColIdx) maxColIdx = idx;
        }
        final rowList = List<String>.filled(maxColIdx + 1, '');
        for (final entry in rowValuesByIndex.entries) {
          rowList[entry.key] = entry.value;
        }
        rows.add(rowList);
      }
    }

    return rows;
  }

  /// Parses CSV bytes (handling UTF-8 BOM, CRLF/LF line endings, and Latin-1 fallback).
  static List<List<String>> parseCsvBytes(List<int> bytes) {
    String decodeCsvText(List<int> raw) {
      try {
        return utf8.decode(raw);
      } catch (_) {
        return String.fromCharCodes(raw);
      }
    }

    var content = decodeCsvText(bytes);
    if (content.startsWith('\uFEFF')) {
      content = content.substring(1);
    }
    content = content.replaceAll('\r\n', '\n').replaceAll('\r', '\n');

    final rawRows = const CsvToListConverter(eol: '\n').convert(content);
    return rawRows
        .map((r) => r.map((c) => c?.toString().trim() ?? '').toList())
        .where((r) => r.any((c) => c.isNotEmpty))
        .toList();
  }

  /// Parses either `.xlsx` or `.csv` file bytes from [filePath], rejecting `.xls` files.
  static List<List<String>> parseFileBytes(List<int> bytes, String filePath) {
    final lowerPath = filePath.toLowerCase().trim();
    if (isLegacyBinaryXls(bytes) || lowerPath.endsWith('.xls')) {
      throw const FormatException(
        'Legacy .xls files are not supported. Please Save As .xlsx or .csv and upload again.',
      );
    }
    if (lowerPath.endsWith('.xlsx')) {
      return parseXlsxArchive(bytes);
    }
    return parseCsvBytes(bytes);
  }

  static int colRefToIndex(String col) {
    var result = 0;
    for (var i = 0; i < col.length; i++) {
      result = result * 26 + (col.codeUnitAt(i) - 64);
    }
    return result - 1;
  }

  static ArchiveFile? _findArchiveEntry(Archive archive, String targetPath) {
    final lowerTarget = targetPath.toLowerCase();
    for (final file in archive.files) {
      if (file.name.toLowerCase() == lowerTarget) {
        return file;
      }
    }
    return null;
  }
}
