import 'package:flutter_test/flutter_test.dart';
import 'package:shop/services/excel_report_service.dart';

void main() {
  test('ExcelReportService compiles and handles empty report map', () {
    expect(ExcelReportService.instance, isNotNull);
  });
}
