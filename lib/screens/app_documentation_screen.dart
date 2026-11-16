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
        subtitle: 'Cloud Sync vs Pure Offline, Owner vs Staff pairing',
        icon: Icons.hub_outlined,
        color: const Color(0xFF0F766E),
        initiallyExpanded: true,
        items: [
          _DocItem(
            topic: 'Two Distinct APK Variants',
            tag: 'CORE ARCHITECTURE',
            details:
                'The system builds into two independent application packages:\n'
                '• Shop Cloud (app-cloud-sync-release.apk): Features live multi-device synchronization, staff pairing, role permissions, and cloud backup.\n'
                '• Shop Local (app-local-offline-release.apk): Pure standalone offline version. Has ZERO cloud, zero sync UI, and zero owner/staff setup for 100% offline usage on a single phone.',
            tip:
                'Both APKs have distinct package IDs and app names so you can install and test both side-by-side on the same phone without conflict.',
          ),
          _DocItem(
            topic: 'Owner vs Staff Roles & Secure Pairing',
            tag: 'SECURITY',
            details:
                'In Cloud mode, the first device to create the shop is the Master / Owner Device (👑).\n'
                'Staff connect by entering the 6-character Shop Code (e.g. SH-MG27) or scanning the QR code.\n'
                'SECURITY SAFEGUARD: Staff devices cannot join automatically. When a staff device requests to join, the Owner receives an approval prompt and must explicitly accept the request.',
          ),
          _DocItem(
            topic: 'Role-Based Permissions Safeguards',
            tag: 'PERMISSIONS',
            details:
                'The Owner can configure permissions for connected staff devices:\n'
                '• Allow Staff to Change Unit Prices (toggle on/off)\n'
                '• Allow Staff to Close Orders (toggle on/off)\n'
                '• Allow Staff to Edit Quantity Step Shortcuts (toggle on/off)\n'
                '• Allow Staff to View Grand Totals (toggle on/off)\n'
                'Staff devices have the QR code and shop code sharing permanently hidden to prevent unauthorized sharing.',
          ),
          _DocItem(
            topic: 'Offline-First SQLite Reliability',
            tag: 'DATABASE',
            details:
                'All customer records, products, categories, bills, and payments are stored in a fast local SQLite database on your phone. Even if your internet disconnects, the app works 100% smoothly without lag. When internet reconnects, all updates automatically sync in the background.',
          ),
        ],
      ),

      // Section 2: Home Screen & Quick Navigation
      _DocSection(
        title: '2. Home Screen & Quick Actions',
        subtitle: 'Side-by-side hero cards, quick price list & drawer',
        icon: Icons.dashboard_customize_outlined,
        color: const Color(0xFF14B8A6),
        items: [
          _DocItem(
            topic: 'Side-by-Side Hero Cards: Create Order & Khata Book',
            tag: 'HOME LAYOUT',
            details:
                'At the top of the Home Screen, two primary action cards are placed side-by-side:\n'
                '• CREATE ORDER (Emerald Card): 1-tap to start a new order, pick a customer, add items, and calculate bills.\n'
                '• KHATA BOOK (Indigo Card): 1-tap direct access to customer udhaar balances, payment collections, and WhatsApp reminders.',
          ),
          _DocItem(
            topic: 'Quick Price List Icon (Top Bar & Sidebar)',
            tag: 'COUNTER UTILITY',
            details:
                'When a customer walks in asking: "How much is 4-inch cutoff wheel?" or "What is the price of 25mm PVC elbow?", staff do not need to create an order.\n'
                'Simply tap the Price Tag icon beside the sync icon (or open it from the sidebar) to instantly search prices and share quotes via WhatsApp.',
          ),
          _DocItem(
            topic: 'Staff Attribution ("Taken by: [Name]")',
            tag: 'ACCOUNTABILITY',
            details:
                'Every bill records the specific staff member or cashier who created it. The staff name is prominently shown directly under the customer name on both Recent Orders and the History screen.',
          ),
        ],
      ),

      // Section 3: Ordering, Voice Search & Smart Cart
      _DocSection(
        title: '3. Order Creation & Smart Cart',
        subtitle: 'Voice search, option matrix, quantity chips & draft auto-save',
        icon: Icons.shopping_cart_checkout_outlined,
        color: const Color(0xFF3B82F6),
        items: [
          _DocItem(
            topic: 'Voice Search for Products, Customers & History',
            tag: 'VOICE AI',
            details:
                'Tap the microphone icon on any search bar (Products, Customers, Price List, History). Speak in Hindi, Telugu, or English (e.g. "cutting wheel", "1 inch elbow", "Suresh"). The app listens with an animated waveform and automatically searches upon silence.',
            tip:
                'Ensure microphone permission is granted in Android settings when prompted.',
          ),
          _DocItem(
            topic: 'Multi-Step Product Options & Pricing Matrix',
            tag: 'CATALOG',
            details:
                'Products can have multiple step options (e.g., Size → Color → Brand). The app computes exact prices based on combinations (e.g. Asian Paints Royale 1L vs 4L, or 1/2" brass valve vs 1" brass valve).',
          ),
          _DocItem(
            topic: 'Quantity Quick-Add Chips (+5, +6, +10, +12)',
            tag: 'SPEED CHECKOUT',
            details:
                'Instead of manually typing numbers, tap quick-step chips (+1, +5, +6, +10, +12, +50, +100). Essential for hardware shops where customers buy items in standard pack sizes.',
          ),
          _DocItem(
            topic: 'Handling Non-Catalog / "Other Items"',
            tag: 'PROCUREMENT',
            details:
                'Need to bill an item not currently in your catalog? Tap "+ Other Item", enter the item name, required quantity, unit, and price. The item is automatically flagged with "Needs Procurement" so your helpers know it must be brought from the warehouse or outside.',
          ),
          _DocItem(
            topic: 'Draft Order Recovery (Zero Lost Bills)',
            tag: 'RELIABILITY',
            details:
                'If you are building a 20-item bill and receive an incoming phone call or accidentally close the app, your cart is automatically preserved. Re-opening the app will prompt: "Draft order restored".',
          ),
        ],
      ),

      // Section 4: Bill Calculation, GST & Charges
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
                'Toggle "Add GST" on any bill. Select standard tax rates (5%, 12%, 18%, 28%) or enter a custom rate. The taxable value, GST amount, and grand total are calculated automatically and printed on invoices.',
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

      // Section 5: Fulfillment, Partial Delivery & Repeat Order
      _DocSection(
        title: '5. Fulfillment & Repeat Orders',
        subtitle: 'Item delivery statuses, partial bill adjustments & 1-tap reorders',
        icon: Icons.fact_check_outlined,
        color: const Color(0xFFEC4899),
        items: [
          _DocItem(
            topic: '1-Tap "Repeat Order" (Duplicate Past Bill)',
            tag: 'PRODUCTIVITY',
            details:
                'When a plumber, electrician, or painter says: "Give me the exact same items I took 3 days ago", open their past order and tap the "Repeat Order" (🔁) icon in the top bar. All items, specifications, and quantities are instantly loaded into a fresh cart in 1 second.',
          ),
          _DocItem(
            topic: 'Item-Level Fulfillment Statuses',
            tag: 'DISPATCH',
            details:
                'Every item has three delivery states:\n'
                '• DELIVERED (Green): All ordered units given to customer.\n'
                '• PARTIALLY GIVEN (Orange): Some units given, remaining pending.\n'
                '• NOT GIVEN (Red): Awaiting warehouse pickup or procurement.',
          ),
          _DocItem(
            topic: 'Partial Delivery Settlement Engine',
            tag: 'INTELLIGENT BILLING',
            details:
                'If a customer ordered 10 items but you only had 6 in stock, closing the order prompts you: "Adjust bill to delivered items only?". Selecting this recalculates the bill to charge only for the 6 items handed over and saves an audit note: "Closed with partial items delivered".',
          ),
        ],
      ),

      // Section 6: Payments, Khata (Udhaar) & Dynamic UPI QR
      _DocSection(
        title: '6. Upgraded Khata Book, Passbook & UPI QR',
        subtitle: 'Complete Udhaar ledger, debt ageing, passbook, PDF statements & WhatsApp reminders',
        icon: Icons.account_balance_wallet_outlined,
        color: const Color(0xFFD97706),
        items: [
          _DocItem(
            topic: 'Customer Khata Passbook (Dual-Tone Ledger)',
            tag: 'PASSBOOK',
            details:
                'Tap on any customer in Khata to open their dedicated Passbook:\n'
                '• 🔴 YOU GAVE: Debit entries for bills & credit given with item count & bill amounts.\n'
                '• 🟢 YOU GOT: Credit entries for cash/UPI/cheque payments received with notes.\n'
                '• Running Balance calculated automatically after every single transaction.\n'
                '• Sticky bottom action bar with "+ YOU GAVE" (manual debit/old balance) and "+ YOU GOT" (quick receive).',
          ),
          _DocItem(
            topic: 'Debt Ageing & Overdue Tracking (> 30 Days)',
            tag: 'AGEING ALERT',
            details:
                'The Khata Book tracks how long debts have been pending:\n'
                '• Smart Badges show exact pending days (e.g. ⚠️ 45 days overdue).\n'
                '• Dashboard displays Total Market Udhaar and Overdue >30 Days metrics.\n'
                '• 1-tap filter for "Overdue >30d" lets you target customers needing urgent recovery.',
          ),
          _DocItem(
            topic: '3 Smart WhatsApp Reminder Templates',
            tag: 'WHATSAPP',
            details:
                'Tap "Remind" on any customer card to choose from 3 tailored templates:\n'
                '1. Friendly / Gentle Reminder: Polite request with your UPI ID.\n'
                '2. Formal Due Notice: Formal account statement with days overdue.\n'
                '3. Instant 1-Tap UPI Pay Link: Pre-filled deep link that opens Google Pay or PhonePe with the exact amount ready to pay.',
          ),
          _DocItem(
            topic: 'Download & Share Customer Statement PDF',
            tag: 'PDF STATEMENT',
            details:
                'Tap "Statement PDF" to generate a professional A4 statement of account for any customer. Includes Shop Header, GSTIN, complete transaction ledger table with running balances, summary box, and an embedded Dynamic UPI QR code for direct scan-and-pay.',
          ),
          _DocItem(
            topic: 'Market Udhaar Summary Report (PDF)',
            tag: 'OWNER REPORT',
            details:
                'Tap the PDF icon on the Khata Book top bar to download or WhatsApp a complete 1-page Market Credit Summary report showing total market outstanding, active debtor count, and table of every customer with their phone and pending balance.',
          ),
          _DocItem(
            topic: 'Instant Dynamic UPI QR Code',
            tag: 'SCAN & PAY',
            details:
                'Tap the "UPI QR" button on any bill. The app generates an official NPCI QR code containing your shop UPI ID and the exact due amount. The customer scans with Google Pay, PhonePe, Paytm, or BHIM to pay instantly without typing numbers.',
            tip:
                'Be sure to set your shop UPI ID in Shop Settings → INVOICE, UPI & DIGITAL STAMP.',
          ),
          _DocItem(
            topic: 'Oldest-First Payment Allocation',
            tag: 'ACCOUNTING',
            details:
                'When a customer pays a lumpsum amount (e.g. ₹5,000 towards an ₹8,000 credit), the app automatically credits and marks the oldest pending bills as PAID first, and leaves remaining balance on the latest bill.',
          ),
        ],
      ),

      // Section 7: Printing, PDF Invoices & Delivery Challans
      _DocSection(
        title: '7. Thermal Printing & PDF Bills',
        subtitle: '58mm thermal rolls, PDF invoices, and delivery challans',
        icon: Icons.print_outlined,
        color: const Color(0xFF0284C7),
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
                'When dispatching goods via auto, rickshaw, or helper, you do not want to reveal prices or profit margins. Tap "Delivery Challan" to generate a dispatch slip showing items, quantities, and customer address only — with prices completely omitted.',
          ),
        ],
      ),

      // Section 8: Analytics & Evening Closing Report
      _DocSection(
        title: '8. Analytics & Evening Reports',
        subtitle: 'Top products, day-end closing report, WhatsApp to owner',
        icon: Icons.analytics_outlined,
        color: const Color(0xFF059669),
        items: [
          _DocItem(
            topic: 'Top Selling Products Analytics',
            tag: 'BUSINESS INSIGHTS',
            details:
                'Available at the top of the Sidebar drawer and as a dedicated screen. View your best-performing inventory filtered by Today, This Week, This Month, or All Time. Toggle sorting between Highest Quantity Sold and Highest Revenue Generated.',
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
                '• 1-Click "Send Day-End Summary via WhatsApp" directly to the Shop Owner.',
          ),
        ],
      ),

      // Section 9: Catalog, Excel Import/Export & Shortcuts
      _DocSection(
        title: '9. Catalog & Excel Spreadsheet Tools',
        subtitle: 'Bulk product upload, quantity step shortcuts & backup',
        icon: Icons.table_chart_outlined,
        color: const Color(0xFF6366F1),
        items: [
          _DocItem(
            topic: 'Excel & CSV Catalog Import / Export',
            tag: 'BULK CATALOG',
            details:
                'Easily upload thousands of hardware items at once using standard Excel (.xlsx) files. The parser handles item names, categories, units, and combination pricing matrices. You can also export your catalog anytime to Excel.',
          ),
          _DocItem(
            topic: 'Custom Quantity Step Shortcuts',
            tag: 'CONFIG',
            details:
                'Configure global quick-add buttons in Shop Settings (e.g. +5, +6, +10, +12). You can also set custom shortcuts for specific products (e.g., pipes sold in 10s vs screws sold in 100s).',
          ),
        ],
      ),

      // Section 10: Shop Settings & Customization
      _DocSection(
        title: '10. Shop Settings & Branding',
        subtitle: 'Shop details, digital stamp, language & data safety',
        icon: Icons.settings_suggest_outlined,
        color: const Color(0xFF475569),
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
                'The settings screen includes granular data controls protected for Owner devices:\n'
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
