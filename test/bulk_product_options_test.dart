import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shop/l10n/app_localizations.dart';
import 'package:shop/models/order.dart';
import 'package:shop/models/product.dart';
import 'package:shop/screens/bulk_product_options_screen.dart';

void main() {
  testWidgets('BulkProductOptionsScreen retains quantities across prefix chips and shows badges',
      (WidgetTester tester) async {
    // Product with 2 steps: "Inch" (prefix step converted to chips) and "Type" (variant)
    final product = Product(
      id: 1,
      name: 'PVC Pipe',
      category: 'Plumbing',
      isActive: true,
      configuration: const ProductConfiguration(
        steps: [
          ProductStep(
            key: 'inch',
            label: 'Inch',
            type: 'select',
            values: ['1/2"', '3/4"', '1"'],
          ),
          ProductStep(
            key: 'type',
            label: 'Type',
            type: 'select',
            values: ['Heavy', 'Light'],
          ),
        ],
        basePrice: 50.0,
      ),
    );

    List<DraftOrderItem>? returnedItems;

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [
          AppLocalizations.delegate,
          DefaultMaterialLocalizations.delegate,
          DefaultWidgetsLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) => Scaffold(
            body: ElevatedButton(
              onPressed: () async {
                returnedItems = await Navigator.push<List<DraftOrderItem>>(
                  context,
                  MaterialPageRoute(
                    builder: (_) => BulkProductOptionsScreen(product: product),
                  ),
                );
              },
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Open screen
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    // Verify chips for 1/2", 3/4", 1" are rendered
    expect(find.text('1/2"'), findsOneWidget);
    expect(find.text('3/4"'), findsOneWidget);
    expect(find.text('1"'), findsOneWidget);

    // Initial state: 1/2" is selected by default.
    // Tap "+10" preset on "Heavy"
    final plus10Finder = find.widgetWithText(InkWell, '+10').first;
    await tester.tap(plus10Finder);
    await tester.pumpAndSettle();

    // Switch prefix chip to 3/4"
    final threeQuarterChip = find.widgetWithText(ChoiceChip, '3/4"');
    await tester.tap(threeQuarterChip);
    await tester.pumpAndSettle();

    // Tap "+5" preset on "Heavy"
    final plus5Finder = find.widgetWithText(InkWell, '+5').first;
    await tester.tap(plus5Finder);
    await tester.pumpAndSettle();

    // Tap the bottom "ADD ITEM (2)" button
    final addButtonFinder = find.widgetWithText(FilledButton, 'ADD ITEM (2)');
    expect(addButtonFinder, findsOneWidget);
    await tester.tap(addButtonFinder);
    await tester.pumpAndSettle();

    // Verify both items were returned
    expect(returnedItems, isNotNull);
    expect(returnedItems!.length, 2);

    final item1 = returnedItems!.firstWhere((i) => i.options['inch'] == '1/2"');
    expect(item1.options['type'], 'Heavy');
    expect(item1.quantity, 10.0);

    final item2 = returnedItems!.firstWhere((i) => i.options['inch'] == '3/4"');
    expect(item2.options['type'], 'Heavy');
    expect(item2.quantity, 5.0);
  });
}
