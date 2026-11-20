import 'package:flutter/material.dart';

class AppDocumentationScreen extends StatefulWidget {
  const AppDocumentationScreen({super.key});

  @override
  State<AppDocumentationScreen> createState() => _AppDocumentationScreenState();
}

class _AppDocumentationScreenState extends State<AppDocumentationScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sections = _getDocSections();
    final filteredSections = _searchQuery.isEmpty
        ? sections
        : sections.where((sec) {
            final matchesTitle =
                sec.title.toLowerCase().contains(_searchQuery.toLowerCase());
            final matchesContent = sec.items.any((item) =>
                item.topic.toLowerCase().contains(_searchQuery.toLowerCase()) ||
                item.details.toLowerCase().contains(_searchQuery.toLowerCase()));
            return matchesTitle || matchesContent;
          }).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'App Documentation',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
            ),
            Text(
              'Complete Pin-to-Pin Feature & Operation Guide',
              style: TextStyle(fontSize: 11, color: Colors.white70),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          // Search & Filter Header
          Container(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            decoration: BoxDecoration(
              color: const Color(0xFF0F766E).withValues(alpha: 0.05),
              border: Border(
                bottom: BorderSide(color: Colors.grey.shade200),
              ),
            ),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search features, terms (e.g. UPI, Print, Udhaar, Sync)...',
                hintStyle: TextStyle(fontSize: 13, color: Colors.grey.shade500),
                prefixIcon: const Icon(Icons.search, size: 20),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 18),
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _searchQuery = '');
                        },
                      )
                    : null,
                filled: true,
                fillColor: Colors.white,
                contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 16),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.grey.shade300),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.grey.shade300),
                ),
              ),
              onChanged: (val) => setState(() => _searchQuery = val.trim()),
            ),
          ),

          // Content List
          Expanded(
            child: filteredSections.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.search_off_rounded,
                              size: 48, color: Colors.grey.shade400),
                          const SizedBox(height: 12),
                          Text(
                            'No documentation matches "$_searchQuery"',
                            style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Colors.grey.shade700),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Try searching for terms like "khata", "qr", "bluetooth", "gst", or "sync".',
                            style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: filteredSections.length,
                    itemBuilder: (context, index) {
                      final sec = filteredSections[index];
                      return _buildSectionCard(sec, theme);
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionCard(_DocSection sec, ThemeData theme) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      clipBehavior: Clip.antiAlias,
      child: Theme(
        data: theme.copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: _searchQuery.isNotEmpty || sec.initiallyExpanded,
          leading: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: sec.color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(sec.icon, color: sec.color, size: 22),
          ),
          title: Text(
            sec.title,
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
          ),
          subtitle: Text(
            sec.subtitle,
            style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
          ),
          children: sec.items.map((item) {
            return Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 14),
              decoration: BoxDecoration(
                border: Border(
                  top: BorderSide(color: Colors.grey.shade100),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          color: sec.color,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          item.topic,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13.5,
                          ),
                        ),
                      ),
                      if (item.tag != null)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.grey.shade100,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: Colors.grey.shade300),
                          ),
                          child: Text(
                            item.tag!,
                            style: TextStyle(
                              fontSize: 9.5,
                              fontWeight: FontWeight.bold,
                              color: Colors.grey.shade700,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Padding(
                    padding: const EdgeInsets.only(left: 14),
                    child: Text(
                      item.details,
                      style: TextStyle(
                        fontSize: 12.5,
                        color: Colors.grey.shade800,
                        height: 1.45,
                      ),
                    ),
                  ),
                  if (item.tip != null) ...[
                    const SizedBox(height: 8),
                    Container(
                      margin: const EdgeInsets.only(left: 14),
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.amber.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.amber.shade200),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.lightbulb_outline,
                              size: 16, color: Colors.amber.shade900),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              item.tip!,
                              style: TextStyle(
                                fontSize: 11.5,
                                color: const Color(0xFF451A03),
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  List<_DocSection> _getDocSections() {
    return [
      // Section 1: Dual Variants & Architecture
      _DocSection(
        title: '1. App Architecture & Dual APKs',
        subtitle: 'Shop Wholesale (Cloud) vs Shop Retail (Local), Master & Partner devices',
        icon: Icons.hub_outlined,
        color: const Color(0xFF0F766E),
        initiallyExpanded: true,
        items: [
          _DocItem(
            topic: 'Two Distinct Production APKs',
            tag: 'CORE ARCHITECTURE',
            details:
                'The system builds into two independent, production-ready applications:\n'
                '• Shop Wholesale (app-wholesale-cloud-release.apk): Features live multi-device synchronization, family Master/Partner pairing, Khata Book, wholesale cart, procurement tracking, and cloud backup.\n'
                '• Shop Retail (app-retail-local-release.apk): Pure standalone offline version. Built with zero cloud overhead, zero sync UI, and maximum counter checkout speed for 100% offline usage on a single phone.',
            tip:
                'Both APKs have distinct package IDs and app names so you can install and run both side-by-side on the same phone without conflict.',
          ),
          _DocItem(
            topic: 'Family Device Roles: Master Device & Partner Member',
            tag: 'SECURITY & FAMILY',
            details:
                'Designed for family-operated shops without rigid corporate hierarchy:\n'
                '• Master Device (👑): The primary shop phone that sets up the store and configures settings.\n'
                '• Partner Device / Family Member (👥): Family members (e.g. Srikar, Sridevi, Amma) connect via the 6-character Shop Code (e.g. SH-MG27) or QR code.\n'
                'SECURITY SAFEGUARD: Partner devices cannot join silently. When a family member requests to join, the Master Device receives an approval prompt and must explicitly accept.',
          ),
          _DocItem(
            topic: 'Collaborative Role Permissions',
            tag: 'PERMISSIONS',
            details:
                'The Master Device can tailor access for connected partner devices:\n'
                '• Allow Changing Unit Prices (toggle on/off)\n'
                '• Allow Closing Counter Orders (toggle on/off)\n'
                '• Allow Editing Quantity Step Shortcuts (toggle on/off)\n'
                '• Allow Viewing Grand Totals (toggle on/off)\n'
                'Partner devices have shop code sharing controls hidden to prevent unauthorized distribution.',
          ),
          _DocItem(
            topic: 'Offline-First SQLite Reliability',
            tag: 'DATABASE',
            details:
                'All customer records, products, categories, bills, and payments are stored in a fast local SQLite database on your device. Counter billing works 100% smoothly with zero lag even with no internet connection. When network is restored, all data automatically synchronizes in the background.',
          ),
        ],
      ),

      // Section 2: Home Screen & Live Dashboard Metrics
      _DocSection(
        title: '2. Home Screen & Live Dashboard Cards',
        subtitle: 'Pending bills card, procurement counter, stale price alerts & drawer',
        icon: Icons.dashboard_customize_outlined,
        color: const Color(0xFF14B8A6),
        items: [
          _DocItem(
            topic: 'Live Dashboard Metrics: Pending Orders & Procurement Cards',
            tag: 'DASHBOARD CARDS',
            details:
                'Prominently positioned under the date header for instant counter visibility:\n'
                '• 📋 Pending Orders Card: Shows live count of open counter bills. Displays an amber/red ">3 days ⚠️" badge with "X need immediate close" if orders are stale. Tapping it opens History filtered directly to Pending/Open bills.\n'
                '• 📦 Procurement Card: Shows live count of items needing warehouse pickup or external purchase ("X to Procure" or "All fulfilled 🎉"). Tapping it opens the Procurement List directly.',
          ),
          _DocItem(
            topic: 'Market Price Stale Caution Banner',
            tag: 'PRICE CAUTION',
            details:
                'Hardware prices fluctuate frequently in current market conditions. If product prices have not been reviewed for more than X days (configurable in Settings, default 30 days), an attention banner appears directly beneath the top header: "⚠️ Some product prices have not been updated in over 30 days. Tap to review." Tapping it navigates straight to Manage Products.',
          ),
          _DocItem(
            topic: 'Side-by-Side Hero Cards: Create Order & Khata Book',
            tag: 'QUICK ACTIONS',
            details:
                'Large dual-color buttons for rapid counter operation:\n'
                '• CREATE ORDER (Emerald Card): 1-tap to start a new wholesale bill, choose customer, and add items.\n'
                '• KHATA BOOK (Indigo Card): 1-tap direct access to customer udhaar ledgers, payment collections, and WhatsApp reminders.',
          ),
          _DocItem(
            topic: 'Catalog Review Indicator on Manage Products',
            tag: 'REVIEW BADGE',
            details:
                'When non-catalog items are added on-the-fly during order creation, the Manage Products card on the Home Screen displays an amber review indicator alerting family members to check and configure pricing.',
          ),
          _DocItem(
            topic: 'Family Member Attribution ("Taken by: [Name]")',
            tag: 'ATTRIBUTION',
            details:
                'Every bill records the specific family member who took the order (e.g. "Taken by: sridevi" or "Taken by: Srikar"). The member name is shown on Recent Orders, Order Details, and History.',
          ),
        ],
      ),

      // Section 3: Ordering, Smart Search & Auto-Cataloging
      _DocSection(
        title: '3. Order Creation, Search & Auto-Cataloging',
        subtitle: 'Case-insensitive search, inline catalog addition, voice AI & draft recovery',
        icon: Icons.shopping_cart_checkout_outlined,
        color: const Color(0xFF3B82F6),
        items: [
          _DocItem(
            topic: 'Case-Insensitive Search with Inline Auto-Cataloging',
            tag: 'SMART SEARCH',
            details:
                'Search treats uppercase and lowercase identically (e.g. "paint", "Paint", "PAINT" match the same items).\n'
                'AUTO-CATALOGING: When a customer asks for an unlisted product, typing the name in the search bar immediately displays an inline "Add [Item Name] to Cart & Catalog" button. The item is added to the cart AND automatically saved into your product catalog with a "Needs Review" flag for later pricing setup.',
          ),
          _DocItem(
            topic: 'Voice Search for Products, Customers & History',
            tag: 'VOICE AI',
            details:
                'Tap the microphone icon on any search bar. Speak in Telugu, Hindi, or English (e.g. "10 piece cut off wheel", "Red Paint 1L", "Kamal Sai"). The app animates an audio waveform and auto-searches upon silence — perfect when hands have dust or paint.',
          ),
          _DocItem(
            topic: 'Multi-Step Product Options & Pricing Matrix',
            tag: 'CATALOG MATRIX',
            details:
                'Supports hierarchical product configurations (e.g., Size → Colour → Brand). The app computes exact prices based on the selected matrix (e.g. Paints: Red 1L vs Red 10L, or Cut-off Wheels: 4" Steel vs 14" Steel).',
          ),
          _DocItem(
            topic: 'Quantity Quick-Add Chips (+1, +5, +6, +10, +12, +50)',
            tag: 'SPEED CHECKOUT',
            details:
                'Tap quick-step buttons instead of opening the keyboard. Essential for hardware items sold in standard cartons, dozens, or bundles.',
          ),
          _DocItem(
            topic: 'Draft Order Recovery (Zero Lost Bills)',
            tag: 'RELIABILITY',
            details:
                'If you are preparing a large order and answer an incoming phone call or the app closes, your complete cart is saved automatically. Re-opening prompts: "Draft order restored".',
          ),
        ],
      ),

      // Section 4: Billing, Discounts & Tax Engine
      _DocSection(
        title: '4. Billing, Discounts & Tax Engine',
        subtitle: 'GST rates, flat/percent discounts, extra charges & grand total',
        icon: Icons.calculate_outlined,
        color: const Color(0xFF8B5CF6),
        items: [
          _DocItem(
            topic: 'Tax & GST Calculation',
            tag: 'GST ENGINE',
            details:
                'Toggle "Add GST" on any bill. Select standard tax rates (5%, 12%, 18%, 28%) or enter a custom rate. The taxable value, GST amount, and grand total are calculated automatically and itemized on invoices.',
          ),
          _DocItem(
            topic: 'Discounts (Flat ₹ or Percentage %)',
            tag: 'DISCOUNTS',
            details:
                'Apply discounts as either Flat Rupee amounts (e.g. -₹150 off total) or Percentage (e.g. -5% for regular contractors). Taxes recalculate based on the post-discount taxable amount.',
          ),
          _DocItem(
            topic: 'Additional Charges (Delivery, Loading, Cutting)',
            tag: 'CHARGES',
            details:
                'Add custom charges with descriptions (e.g. Auto Delivery ₹200, Loading Hamali ₹100, Pipe Cutting ₹50). Each extra charge is clearly itemized on the printed invoice.',
          ),
        ],
      ),

      // Section 5: Fulfillment & 90/10 Shortage Cutting
      _DocSection(
        title: '5. Fulfillment & Intentional Less Stock (90/10 Case)',
        subtitle: 'Dual-linked counters, shortage cutting, partial closing & repeat orders',
        icon: Icons.fact_check_outlined,
        color: const Color(0xFFEC4899),
        items: [
          _DocItem(
            topic: 'Dual-Linked Fulfillment Controls (GIVEN ⇄ NOT GIVEN)',
            tag: 'FULFILLMENT UI',
            details:
                'Each order item features two synchronised counter cards:\n'
                '• GIVEN: Number of units handed over to the customer.\n'
                '• NOT GIVEN (SHORT): Number of units remaining.\n'
                'Adjusting one automatically updates the other in real-time.',
          ),
          _DocItem(
            topic: '1-Tap Quick Adjustment Chips',
            tag: 'SPEED CONTROLS',
            details:
                'Instant adjustment chips above each item:\n'
                '• [All Given]: Fulfills 100% of the ordered quantity.\n'
                '• [1 Short], [2 Short], [5 Short]: Instantly marks standard shortage.\n'
                '• [None Given]: Sets given to 0 when item is completely out of stock.',
          ),
          _DocItem(
            topic: '90/10 Case: "✂ Finalize at X (Don\'t Procure / Cut Shortage)"',
            tag: 'SHORTAGE CUTTING',
            details:
                'Solves the practical scenario where the shop intentionally delivers fewer items (e.g. customer ordered 12, but you only give 7 and agree not to supply the rest):\n'
                '• Tapping "✂ Finalize at 7 (Don\'t Procure / Cut Shortage)" prompts a confirmation dialog.\n'
                '• Automatically adjusts quantity ordered to 7, quantity given to 7, and drops the 5-item shortage from Procurement.\n'
                '• Recalculates the bill total strictly for the 7 delivered units and marks the item satisfied.',
          ),
          _DocItem(
            topic: 'Order Closing Partial Settlement ("Adjust Bill for Given Items & Close")',
            tag: 'ORDER CLOSING',
            details:
                'When closing an order with unfulfilled items, tapping "Adjust Bill for Given Items & Close" automatically commits current counter values, adjusts item quantities to match what was given, cancels pending godown shortages, and produces a finalized bill with zero discrepancies.',
          ),
          _DocItem(
            topic: '1-Tap "Repeat Order" (Duplicate Past Bill)',
            tag: 'PRODUCTIVITY',
            details:
                'When a regular contractor asks for the exact same materials they took last week, open their past order and tap the "Repeat Order" (🔁) icon in the top bar. All items, specifications, and quantities load into a fresh cart in 1 second.',
          ),
        ],
      ),

      // Section 6: Khata Book & Locked Read-Only Bills
      _DocSection(
        title: '6. Khata Book (Udhaar) & Locked Read-Only Bills',
        subtitle: 'Immutable closed bills, receipt view, debt ageing & WhatsApp reminders',
        icon: Icons.account_balance_wallet_outlined,
        color: const Color(0xFFD97706),
        items: [
          _DocItem(
            topic: 'Locked Read-Only Bills Once in Khata Book',
            tag: 'AUDIT SECURITY',
            details:
                'Once an order is closed and posted to Khata Book, it is permanently locked against modifications or tampering.\n'
                'When viewing a customer\'s transactions in Khata Book, tapping on a bill opens an authentic read-only receipt view (styled like the WhatsApp receipt photo) clearly stating:\n'
                '• Item names, quantities, and rates.\n'
                '• Amounts collected outside via Cash or UPI with exact timestamps.\n'
                '• Final balance due (Udhaar).',
          ),
          _DocItem(
            topic: 'Customer Khata Passbook (Dual-Tone Ledger)',
            tag: 'PASSBOOK',
            details:
                'Dedicated customer ledger screen:\n'
                '• 🔴 YOU GAVE: Debit entries for delivered goods and manual credits.\n'
                '• 🟢 YOU GOT: Credit entries for cash/UPI payments received.\n'
                '• Running Balance calculated automatically after every entry.\n'
                '• Quick action buttons for "+ YOU GAVE" and "+ YOU GOT".',
          ),
          _DocItem(
            topic: 'Debt Ageing & Overdue Tracking (> 30 Days)',
            tag: 'AGEING ALERT',
            details:
                'Tracks outstanding balances by age:\n'
                '• Badges show exact overdue duration (e.g. ⚠️ 45 days overdue).\n'
                '• Dashboard displays Total Market Udhaar and Overdue >30 Days metrics.\n'
                '• 1-tap filter for "Overdue >30d" for prioritized collection follow-ups.',
          ),
          _DocItem(
            topic: 'WhatsApp Reminders with Direct UPI Pay Link',
            tag: 'WHATSAPP RECOVERY',
            details:
                'Tap "Remind" on any customer card to send an instant WhatsApp notice with an embedded UPI payment link. Contractors tap the link to open GPay/PhonePe with the exact amount pre-filled.',
          ),
          _DocItem(
            topic: 'Download & Share Customer Statement PDF',
            tag: 'PDF STATEMENT',
            details:
                'Generates an A4 PDF statement of account complete with Shop Header, GSTIN, chronological ledger table, running balance, and embedded Dynamic UPI QR code.',
          ),
          _DocItem(
            topic: 'Dynamic NPCI UPI QR Code',
            tag: 'SCAN & PAY',
            details:
                'Tap "UPI QR" on any bill. Generates a standard NPCI QR code containing your shop UPI ID and exact due amount. Customers scan with Google Pay, PhonePe, Paytm, or BHIM to pay instantly without typing numbers.',
          ),
        ],
      ),

      // Section 7: Procurement Management & Godown Workflow
      _DocSection(
        title: '7. Procurement Management & Godown System',
        subtitle: 'Item shortages, mark as procured, godown buying list & shortage cancel',
        icon: Icons.inventory_2_outlined,
        color: const Color(0xFF0284C7),
        items: [
          _DocItem(
            topic: 'Centralized Procurement List Screen',
            tag: 'GODOWN TRACKING',
            details:
                'Aggregates every shortage across all active orders into a single purchase list:\n'
                '• Grouped by product category (Paints, Hardware, Tools).\n'
                '• Displays exact shortage quantity, customer name, order number, and creator.\n'
                '• Live search bar to search by product name, customer, or order ID.',
          ),
          _DocItem(
            topic: '1-Tap "Mark as Procured" & "Mark All as Procured"',
            tag: 'STOCK REPLENISHMENT',
            details:
                'When goods arrive from the distributor or warehouse:\n'
                '• Tap "Mark as Procured" on any item to instantly mark it delivered.\n'
                '• Tap "Mark All as Procured" in the top bar to fulfill all pending shortages in one tap.\n'
                '• If all items of an order are fulfilled, the order automatically transitions to Completed.',
          ),
          _DocItem(
            topic: '✂ Cut Shortage Directly from Procurement',
            tag: 'SUPPLIER UNAVAILABLE',
            details:
                'If a distributor no longer has an item in stock, tap "✂ Cut Shortage" directly inside the Procurement List. The item is removed from the procurement list and the customer\'s bill is automatically adjusted.',
          ),
        ],
      ),

      // Section 8: Notification & Reminder Engine
      _DocSection(
        title: '8. Automated Notifications & Alert Timers',
        subtitle: 'Daily background reminders, procurement alerts & configurable timers',
        icon: Icons.notifications_active_outlined,
        color: const Color(0xFFD97706),
        items: [
          _DocItem(
            topic: 'Daily Multi-Schedule Background Notifications',
            tag: 'DAILY ALERTS',
            details:
                'The app runs an intelligent background notification engine sending alerts at key business hours (e.g. 7:00 AM morning briefing, 1:00 PM afternoon check, 9:00 PM shop closing):\n'
                '• Pending Orders Alert: "You have X unclosed bills waiting at the counter."\n'
                '• Stale Orders Alert: "X orders taken >3 days ago need immediate closing."\n'
                '• Procurement Alert: "X items need procurement. Tap to open Procurement List."',
          ),
          _DocItem(
            topic: 'Configurable Notification Timers in Settings',
            tag: 'CUSTOM TIMING',
            details:
                'In Shop Settings under NOTIFICATIONS & REMINDERS, customize:\n'
                '• Preferred alert hours (e.g. Morning 7 AM, Afternoon 1 PM, Evening 9 PM).\n'
                '• Enable / disable procurement alerts or pending order reminders.\n'
                '• Stale Order Threshold (configure days before an order is marked overdue).\n'
                '• Price Caution Days (configure days before unupdated prices trigger a caution).',
          ),
        ],
      ),

      // Section 9: Thermal Printing & PDF Invoices
      _DocSection(
        title: '9. Thermal Printing & PDF Bills',
        subtitle: '58mm thermal rolls, PDF invoices, and delivery challans',
        icon: Icons.print_outlined,
        color: const Color(0xFF475569),
        items: [
          _DocItem(
            topic: 'Direct Bluetooth Thermal Printer Support (58mm)',
            tag: 'HARDWARE',
            details:
                'Print clean, compact 2-inch (58mm) roll receipts directly to portable Bluetooth POS printers. Includes shop header, item table with quantities, GST breakdown, grand total, and visit again note.',
          ),
          _DocItem(
            topic: 'Shareable PDF Invoices',
            tag: 'DIGITAL BILLS',
            details:
                'Generate professional A4 PDF invoices complete with your Shop Name, Address, Phone, GSTIN, detailed line items, and your custom Digital Stamp / Authorized Signatory.',
          ),
          _DocItem(
            topic: 'Delivery Challan (No-Price Dispatch Slip)',
            tag: 'LOGISTICS',
            details:
                'When dispatching goods via auto, rickshaw, or helper, tap "Delivery Challan" to generate a dispatch slip showing items, quantities, and customer address with prices completely omitted.',
          ),
        ],
      ),

      // Section 10: Analytics & Evening Reports
      _DocSection(
        title: '10. Analytics & Evening Reports',
        subtitle: 'Top products, day-end closing report, WhatsApp to family',
        icon: Icons.analytics_outlined,
        color: const Color(0xFF059669),
        items: [
          _DocItem(
            topic: 'Top Selling Products Analytics',
            tag: 'BUSINESS INSIGHTS',
            details:
                'View your best-performing inventory filtered by Today, This Week, This Month, or All Time. Toggle sorting between Highest Quantity Sold and Highest Revenue Generated.',
          ),
          _DocItem(
            topic: 'Evening Shop Closing Report (Day-End WhatsApp)',
            tag: 'CLOSING REPORT',
            details:
                'At shop closing time (e.g. 9:30 PM), open the Evening Closing Report from the sidebar drawer. It automatically computes:\n'
                '• Total Daily Turnover (₹)\n'
                '• Breakdown by Cash (₹) vs UPI (₹) vs Udhaar (₹)\n'
                '• Completed vs Pending Orders\n'
                '• Top Selling Item of the Day\n'
                '• 1-Click "Send Day-End Summary via WhatsApp" directly to family members.',
          ),
        ],
      ),

      // Section 11: Catalog & Excel Tools
      _DocSection(
        title: '11. Catalog & Excel Spreadsheet Tools',
        subtitle: 'Bulk product upload, quantity step shortcuts & backup',
        icon: Icons.table_chart_outlined,
        color: const Color(0xFF6366F1),
        items: [
          _DocItem(
            topic: 'Excel & CSV Catalog Import / Export',
            tag: 'BULK CATALOG',
            details:
                'Upload thousands of hardware items at once using standard Excel (.xlsx) files. The parser handles item names, categories, units, and combination pricing matrices. Export catalog anytime to Excel.',
          ),
          _DocItem(
            topic: 'Custom Quantity Step Shortcuts',
            tag: 'CONFIG',
            details:
                'Configure global quick-add buttons in Shop Settings (e.g. +5, +6, +10, +12). Custom shortcuts can also be set for specific products.',
          ),
        ],
      ),

      // Section 12: Shop Settings & Branding
      _DocSection(
        title: '12. Shop Settings, Digital Stamp & Data Safety',
        subtitle: 'Shop details, digital stamp, notification timers, language & safety',
        icon: Icons.settings_suggest_outlined,
        color: const Color(0xFF334155),
        items: [
          _DocItem(
            topic: 'Branding: Name, Phone, Address, GSTIN & UPI ID',
            tag: 'CUSTOMIZATION',
            details:
                'Set your official shop contact information in Shop Settings. All values automatically appear on the top header, PDF invoices, thermal printouts, and UPI payment QR codes.',
          ),
          _DocItem(
            topic: 'Digital Stamp & Authorized Signatory',
            tag: 'LEGAL BRANDING',
            details:
                'Configure your round stamp or signature line (e.g. "Authorized Signatory / For YKR Traders"). Automatically embedded at the bottom right of all PDF invoices.',
          ),
          _DocItem(
            topic: 'Multi-Language Interface',
            tag: 'LOCALIZATION',
            details:
                'Switch the entire application display language between English, Telugu, Hindi, and other regional languages anytime without restarting the app.',
          ),
          _DocItem(
            topic: 'Data Safety & Reset Controls',
            tag: 'SAFETY CONTROLS',
            details:
                'Settings includes protected data safety controls:\n'
                '• Clear Past Orders (keeps catalog and customer list safe)\n'
                '• Clear Products Catalog (keeps orders safe)\n'
                '• Reset All Shop Data (factory reset with double confirmation).',
          ),
        ],
      ),
    ];
  }
}

class _DocSection {
  const _DocSection({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.items,
    this.initiallyExpanded = false,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final List<_DocItem> items;
  final bool initiallyExpanded;
}

class _DocItem {
  const _DocItem({
    required this.topic,
    required this.details,
    this.tag,
    this.tip,
  });

  final String topic;
  final String details;
  final String? tag;
  final String? tip;
}
