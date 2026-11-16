import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:shop/database/database_helper.dart';
import 'package:shop/repositories/customer_repository.dart';
import 'package:shop/repositories/order_repository.dart';
import 'package:shop/repositories/product_repository.dart';
import 'package:shop/screens/customer_khata_passbook_screen.dart';
import 'package:shop/services/invoice_pdf_service.dart';
import 'package:shop/services/shop_customization_service.dart';
import 'package:shop/services/voice_search_service.dart';

class KhataBookScreen extends StatefulWidget {
  const KhataBookScreen({
    super.key,
    required this.customerRepository,
    required this.orderRepository,
    required this.productRepository,
  });

  final CustomerRepository customerRepository;
  final OrderRepository orderRepository;
  final ProductRepository productRepository;

  @override
  State<KhataBookScreen> createState() => _KhataBookScreenState();
}

class _KhataBookScreenState extends State<KhataBookScreen> {
  final TextEditingController _searchController = TextEditingController();
  List<Map<String, dynamic>> _khataList = [];
  List<Map<String, dynamic>> _filteredList = [];
  Map<String, dynamic> _metrics = {};
  bool _loading = true;
  String _filter = 'due'; // 'due', 'overdue30', 'all', 'settled'
  String _sortBy = 'due_desc'; // 'due_desc', 'ageing_desc', 'name_asc', 'recent'

  @override
  void initState() {
    super.initState();
    _loadKhata();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadKhata() async {
    setState(() => _loading = true);
    final list = await DatabaseHelper.instance.getCustomerKhataList();
    final metrics = await DatabaseHelper.instance.getKhataSummaryMetrics();
    if (!mounted) return;
    setState(() {
      _khataList = list;
      _metrics = metrics;
      _applyFilterAndSort();
      _loading = false;
    });
  }

  void _applyFilterAndSort() {
    final query = _searchController.text.trim().toLowerCase();
    var list = _khataList.where((item) {
      final due = (item['balance_due'] as num?)?.toDouble() ?? 0.0;
      final days = (item['days_overdue'] as num?)?.toInt() ?? 0;

      if (_filter == 'due' && due <= 0.01) return false;
      if (_filter == 'overdue30' && (due <= 0.01 || days < 30)) return false;
      if (_filter == 'settled' && due > 0.01) return false;

      final name = (item['customer_name'] as String?)?.toLowerCase() ?? '';
      final phone = (item['customer_phone'] as String?)?.toLowerCase() ?? '';
      if (query.isNotEmpty &&
          !name.contains(query) &&
          !phone.contains(query)) {
        return false;
      }
      return true;
    }).toList();

    // Sort list
    if (_sortBy == 'due_desc') {
      list.sort((a, b) {
        final dueA = (a['balance_due'] as num?)?.toDouble() ?? 0.0;
        final dueB = (b['balance_due'] as num?)?.toDouble() ?? 0.0;
        return dueB.compareTo(dueA);
      });
    } else if (_sortBy == 'ageing_desc') {
      list.sort((a, b) {
        final daysA = (a['days_overdue'] as num?)?.toInt() ?? 0;
        final daysB = (b['days_overdue'] as num?)?.toInt() ?? 0;
        return daysB.compareTo(daysA);
      });
    } else if (_sortBy == 'name_asc') {
      list.sort((a, b) {
        final nameA = (a['customer_name'] as String? ?? '').toLowerCase();
        final nameB = (b['customer_name'] as String? ?? '').toLowerCase();
        return nameA.compareTo(nameB);
      });
    }

    setState(() {
      _filteredList = list;
    });
  }

  Future<void> _callCustomer(String? phone) async {
    if (phone == null || phone.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No phone number recorded for this customer')),
      );
      return;
    }
    final clean = phone.replaceAll(RegExp(r'[^0-9+]'), '');
    final uri = Uri(scheme: 'tel', path: clean);
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri);
      } else {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    } catch (_) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not dial $phone')),
      );
    }
  }

  Future<void> _sendWhatsAppMessage(String? phone, String text) async {
    if (phone != null && phone.isNotEmpty) {
      final clean = phone.replaceAll(RegExp(r'[^0-9]'), '');
      final fullPhone = clean.length == 10 ? '91$clean' : clean;
      final uri = Uri.parse(
          'https://wa.me/$fullPhone?text=${Uri.encodeComponent(text)}');
      try {
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
          return;
        }
      } catch (_) {}
    }
    // Fallback to SharePlus
    await Share.share(text);
  }

  void _showWhatsAppReminderOptions(Map<String, dynamic> item) {
    final customerName = item['customer_name'] as String;
    final customerPhone = item['customer_phone'] as String?;
    final balanceDue = (item['balance_due'] as num?)?.toDouble() ?? 0.0;
    final days = (item['days_overdue'] as num?)?.toInt() ?? 0;
    final shopName = ShopCustomizationService.instance.shopName;
    final upiId = ShopCustomizationService.instance.upiId;
    final dueStr = balanceDue.toStringAsFixed(2);

    final templates = [
      {
        'title': '🌟 Friendly / Gentle Reminder',
        'desc': 'Polite reminder with UPI ID',
        'text':
            '🙏 *Payment Reminder from $shopName*\nDear *$customerName*,\nThis is a gentle reminder that a balance of *₹ $dueStr* is pending in your account.'
                '${upiId.isNotEmpty ? "\n\nYou can pay via UPI to: *$upiId*" : ""}'
                '\n\nPlease settle at your earliest convenience. Thank you! - *$shopName*',
      },
      {
        'title': '⚠️ Overdue Notice (${days > 0 ? "$days days pending" : "Urgent"})',
        'desc': 'For older pending balances',
        'text':
            '⚠️ *Account Due Notice - $shopName*\nDear *$customerName*,\nYour bill balance of *₹ $dueStr* has been pending for *$days days*.'
                '${upiId.isNotEmpty ? "\nPay instantly via UPI: *$upiId*" : ""}'
                '\nPlease clear this balance today to avoid disruption in credit supply.\nThank you! - *$shopName*',
      },
      {
        'title': '🚀 Instant 1-Tap UPI Link',
        'desc': 'Opens GPay/PhonePe with exact amount pre-filled',
        'text':
            '💳 *Pay Bill Instantly - $shopName*\nCustomer: *$customerName*\nAmount Due: *₹ $dueStr*\n'
                '${upiId.isNotEmpty ? "Scan & Pay UPI ID: *$upiId*\nClick to pay now: upi://pay?pa=$upiId&pn=${Uri.encodeComponent(shopName)}&am=$dueStr&cu=INR\n" : ""}'
                'Thank you! - *$shopName*',
      },
    ];

    showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.chat_outlined, color: Color(0xFF25D366)),
                      SizedBox(width: 8),
                      Text(
                        'Send WhatsApp Reminder',
                        style: TextStyle(
                            fontSize: 17, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                'Select reminder template for $customerName (Due: ₹ $dueStr):',
                style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
              ),
              const SizedBox(height: 14),
              ...templates.map((t) {
                return Card(
                  margin: const EdgeInsets.only(bottom: 10),
                  elevation: 0,
                  color: Colors.grey.shade50,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(color: Colors.grey.shade300),
                  ),
                  child: ListTile(
                    title: Text(t['title']!,
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 14)),
                    subtitle: Text(t['desc']!,
                        style: const TextStyle(fontSize: 12)),
                    trailing: const Icon(Icons.send_rounded,
                        color: Color(0xFF25D366), size: 20),
                    onTap: () async {
                      Navigator.pop(ctx);
                      await _sendWhatsAppMessage(customerPhone, t['text']!);
                    },
                  ),
                );
              }),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showQuickReceivePaymentDialog(Map<String, dynamic> item) async {
    final customerId = item['customer_id'] as int;
    final customerName = item['customer_name'] as String;
    final customerPhone = item['customer_phone'] as String?;
    final balanceDue = (item['balance_due'] as num?)?.toDouble() ?? 0.0;

    final amountCtrl = TextEditingController(
      text: balanceDue > 0
          ? (balanceDue % 1 == 0
              ? balanceDue.toInt().toString()
              : balanceDue.toStringAsFixed(2))
          : '',
    );
    final notesCtrl = TextEditingController();
    String paymentMode = 'Cash';
    bool sendWhatsAppReceipt = true;

    final received = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDState) => AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: Colors.teal.shade50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.payments_outlined,
                    color: Color(0xFF0F766E), size: 22),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Receive Payment - $customerName',
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 16),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.red.shade200),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Total Balance Due:',
                          style: TextStyle(
                              fontSize: 12, fontWeight: FontWeight.bold)),
                      Text(
                        '₹ ${balanceDue.toStringAsFixed(2)}',
                        style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: Colors.red.shade800),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),

                // Quick Amount Chips
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    if (balanceDue > 0)
                      ActionChip(
                        label: Text('Full (₹${balanceDue.toStringAsFixed(0)})'),
                        backgroundColor: Colors.teal.shade50,
                        onPressed: () => setDState(() {
                          amountCtrl.text = balanceDue.toStringAsFixed(2);
                        }),
                      ),
                    ActionChip(
                      label: const Text('₹500'),
                      onPressed: () => setDState(() => amountCtrl.text = '500'),
                    ),
                    ActionChip(
                      label: const Text('₹1,000'),
                      onPressed: () =>
                          setDState(() => amountCtrl.text = '1000'),
                    ),
                    ActionChip(
                      label: const Text('₹2,000'),
                      onPressed: () =>
                          setDState(() => amountCtrl.text = '2000'),
                    ),
                    ActionChip(
                      label: const Text('₹5,000'),
                      onPressed: () =>
                          setDState(() => amountCtrl.text = '5000'),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                TextField(
                  controller: amountCtrl,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: 'Amount Received (₹) *',
                    border: OutlineInputBorder(),
                    prefixText: '₹ ',
                    isDense: true,
                  ),
                  autofocus: true,
                ),
                const SizedBox(height: 14),

                const Text('Payment Mode:',
                    style:
                        TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  children: [
                    'Cash',
                    'UPI',
                    'Cheque',
                    'Bank Transfer',
                  ].map((mode) {
                    final isSel = paymentMode == mode;
                    return ChoiceChip(
                      label: Text(mode),
                      selected: isSel,
                      selectedColor: const Color(0xFF0F766E),
                      labelStyle: TextStyle(
                        color: isSel ? Colors.white : Colors.black87,
                        fontWeight:
                            isSel ? FontWeight.bold : FontWeight.normal,
                      ),
                      onSelected: (val) {
                        if (val) setDState(() => paymentMode = mode);
                      },
                    );
                  }).toList(),
                ),
                const SizedBox(height: 12),

                TextField(
                  controller: notesCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Notes / Reference (Optional)',
                    border: OutlineInputBorder(),
                    hintText: 'e.g. Paid at counter / GPay ref',
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 10),

                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  visualDensity: VisualDensity.compact,
                  title: const Text('Send WhatsApp confirmation receipt',
                      style: TextStyle(fontSize: 12)),
                  value: sendWhatsAppReceipt,
                  onChanged: (val) =>
                      setDState(() => sendWhatsAppReceipt = val ?? false),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF0F766E),
              ),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Save Payment'),
            ),
          ],
        ),
      ),
    );

    if (received == true && mounted) {
      final amount = double.tryParse(amountCtrl.text.trim()) ?? 0.0;
      if (amount <= 0) return;

      await DatabaseHelper.instance.recordCustomerKhataPayment(
        customerId: customerId,
        amount: amount,
        paymentMode: paymentMode.toLowerCase(),
        notes: notesCtrl.text.trim(),
      );

      await _loadKhata();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Received ₹ ${amount.toStringAsFixed(2)} from $customerName via $paymentMode',
          ),
          backgroundColor: Colors.teal,
        ),
      );

      if (sendWhatsAppReceipt) {
        final shopName = ShopCustomizationService.instance.shopName;
        final newDue = (balanceDue - amount) > 0 ? (balanceDue - amount) : 0.0;
        final receiptMsg =
            '🙏 *Payment Received with Thanks!*\nReceived: *₹ ${amount.toStringAsFixed(2)}*\nMode: *$paymentMode*\nFrom: *$customerName*'
            '${notesCtrl.text.trim().isNotEmpty ? "\nNote: ${notesCtrl.text.trim()}" : ""}'
            '\nRemaining Balance: *₹ ${newDue.toStringAsFixed(2)}*'
            '\nThank you for your business! - *$shopName*';
        await _sendWhatsAppMessage(customerPhone, receiptMsg);
      }
    }
  }

  void _openCustomerPassbook(Map<String, dynamic> item) async {
    final customerId = item['customer_id'] as int;
    final name = item['customer_name'] as String;
    final phone = item['customer_phone'] as String?;

    await Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => CustomerKhataPassbookScreen(
          customerId: customerId,
          customerName: name,
          customerPhone: phone,
          customerRepository: widget.customerRepository,
          orderRepository: widget.orderRepository,
          productRepository: widget.productRepository,
        ),
      ),
    );
    _loadKhata();
  }

  Future<void> _shareCustomerStatement(Map<String, dynamic> item) async {
    final customerId = item['customer_id'] as int;
    final name = item['customer_name'] as String;
    final phone = item['customer_phone'] as String?;
    final totalDue = (item['balance_due'] as num?)?.toDouble() ?? 0.0;
    final totalBilled = (item['total_billed'] as num?)?.toDouble() ?? 0.0;
    final totalPaid = (item['total_paid'] as num?)?.toDouble() ?? 0.0;

    final entries =
        await DatabaseHelper.instance.getCustomerKhataLedger(customerId);

    await InvoicePdfService.instance.shareCustomerKhataStatement(
      customerName: name,
      customerPhone: phone,
      ledgerEntries: entries,
      totalDue: totalDue,
      totalBilled: totalBilled,
      totalPaid: totalPaid,
    );
  }

  Future<void> _exportMarketSummary() async {
    await InvoicePdfService.instance.shareKhataMarketSummary(
      _khataList,
      _metrics,
    );
  }

  @override
  Widget build(BuildContext context) {
    final currency = NumberFormat.currency(locale: 'en_IN', symbol: '₹ ');

    final totalDue = (_metrics['totalMarketDue'] as num?)?.toDouble() ?? 0.0;
    final overdue30 = (_metrics['overdue30Days'] as num?)?.toDouble() ?? 0.0;
    final collectedToday =
        (_metrics['collectedToday'] as num?)?.toDouble() ?? 0.0;
    final dueCount = (_metrics['dueCustomersCount'] as num?)?.toInt() ?? 0;
    final settledCount =
        (_metrics['settledCustomersCount'] as num?)?.toInt() ?? 0;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Khata Book (Udhaar Ledger)',
            style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            tooltip: 'Export Market Report (PDF)',
            icon: const Icon(Icons.picture_as_pdf_outlined),
            onPressed: _exportMarketSummary,
          ),
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _loadKhata,
          ),
        ],
      ),
      body: Column(
        children: [
          // Total Balance Due Financial Dashboard Banner
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFF7F1D1D), Color(0xFFB91C1C)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'TOTAL MARKET UDHAAR (OUTSTANDING)',
                          style: TextStyle(
                            color: Color(0xFFFEE2E2),
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.5,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          currency.format(totalDue),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 24,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ],
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          const Text(
                            'Active Borrowers',
                            style:
                                TextStyle(color: Colors.white70, fontSize: 10),
                          ),
                          Text(
                            '$dueCount Customers',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),

                // 3 Quick Analytics Stat Badges
                Row(
                  children: [
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              '⚠️ Overdue >30d',
                              style: TextStyle(
                                  color: Color(0xFFFCA5A5), fontSize: 10),
                            ),
                            Text(
                              currency.format(overdue30),
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              '🟢 Today\'s Recovery',
                              style: TextStyle(
                                  color: Color(0xFF86EFAC), fontSize: 10),
                            ),
                            Text(
                              currency.format(collectedToday),
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              '✅ Settled (₹0)',
                              style: TextStyle(
                                  color: Color(0xFFE2E8F0), fontSize: 10),
                            ),
                            Text(
                              '$settledCount Accounts',
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Search and Sort Row
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      hintText: 'Search customer name or phone...',
                      prefixIcon: const Icon(Icons.search, size: 20),
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                          vertical: 10, horizontal: 12),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      suffixIcon: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (_searchController.text.isNotEmpty)
                            IconButton(
                              icon: const Icon(Icons.clear, size: 18),
                              onPressed: () {
                                _searchController.clear();
                                _applyFilterAndSort();
                              },
                            ),
                          IconButton(
                            tooltip: 'Voice Search',
                            icon: const Icon(Icons.mic,
                                color: Color(0xFF0F766E), size: 20),
                            onPressed: () async {
                              final text = await VoiceSearchService.instance
                                  .recordSpeech(
                                context,
                                title: 'Search Khata',
                                hint: 'Say customer name (e.g. Srikar)...',
                              );
                              if (text != null && text.trim().isNotEmpty) {
                                _searchController.text = text.trim();
                                _applyFilterAndSort();
                              }
                            },
                          ),
                        ],
                      ),
                    ),
                    onChanged: (_) => _applyFilterAndSort(),
                  ),
                ),
                const SizedBox(width: 8),
                PopupMenuButton<String>(
                  tooltip: 'Sort List',
                  icon: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey.shade400),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.sort_rounded, size: 20),
                  ),
                  onSelected: (val) {
                    setState(() => _sortBy = val);
                    _applyFilterAndSort();
                  },
                  itemBuilder: (ctx) => const [
                    PopupMenuItem(
                      value: 'due_desc',
                      child: Text('Highest Due First'),
                    ),
                    PopupMenuItem(
                      value: 'ageing_desc',
                      child: Text('Oldest Pending (Ageing)'),
                    ),
                    PopupMenuItem(
                      value: 'name_asc',
                      child: Text('Customer Name (A - Z)'),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Filter Segmented Buttons
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  ChoiceChip(
                    label: Text('With Balance ($dueCount)'),
                    selected: _filter == 'due',
                    selectedColor: Colors.red.shade100,
                    onSelected: (val) {
                      if (val) {
                        setState(() => _filter = 'due');
                        _applyFilterAndSort();
                      }
                    },
                    visualDensity: VisualDensity.compact,
                  ),
                  const SizedBox(width: 6),
                  ChoiceChip(
                    label: const Text('⚠️ Overdue >30d'),
                    selected: _filter == 'overdue30',
                    selectedColor: Colors.amber.shade100,
                    onSelected: (val) {
                      if (val) {
                        setState(() => _filter = 'overdue30');
                        _applyFilterAndSort();
                      }
                    },
                    visualDensity: VisualDensity.compact,
                  ),
                  const SizedBox(width: 6),
                  ChoiceChip(
                    label: Text('All Customers (${_khataList.length})'),
                    selected: _filter == 'all',
                    onSelected: (val) {
                      if (val) {
                        setState(() => _filter = 'all');
                        _applyFilterAndSort();
                      }
                    },
                    visualDensity: VisualDensity.compact,
                  ),
                  const SizedBox(width: 6),
                  ChoiceChip(
                    label: Text('Settled ($settledCount)'),
                    selected: _filter == 'settled',
                    selectedColor: Colors.green.shade100,
                    onSelected: (val) {
                      if (val) {
                        setState(() => _filter = 'settled');
                        _applyFilterAndSort();
                      }
                    },
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 6),

          // Customers Khata List
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _filteredList.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.account_balance_wallet_outlined,
                                size: 54, color: Colors.grey.shade400),
                            const SizedBox(height: 12),
                            Text(
                              _filter == 'due'
                                  ? 'No pending balance! All Khata is settled.'
                                  : 'No customers found in Khata.',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                                color: Colors.grey.shade700,
                              ),
                            ),
                          ],
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                        itemCount: _filteredList.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (context, index) {
                          final item = _filteredList[index];
                          final name = item['customer_name'] as String;
                          final phone = item['customer_phone'] as String?;
                          final totalBilled =
                              (item['total_billed'] as num?)?.toDouble() ?? 0.0;
                          final totalPaid =
                              (item['total_paid'] as num?)?.toDouble() ?? 0.0;
                          final balanceDue =
                              (item['balance_due'] as num?)?.toDouble() ?? 0.0;
                          final orderCount =
                              (item['order_count'] as num?)?.toInt() ?? 0;
                          final daysOverdue =
                              (item['days_overdue'] as num?)?.toInt() ?? 0;
                          final hasDue = balanceDue > 0.01;

                          return Card(
                            elevation: 1,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                              side: BorderSide(
                                color: hasDue
                                    ? (daysOverdue >= 30
                                        ? Colors.red.shade400
                                        : Colors.red.shade200)
                                    : Colors.green.shade200,
                                width: hasDue && daysOverdue >= 30 ? 1.5 : 1,
                              ),
                            ),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(14),
                              onTap: () => _openCustomerPassbook(item),
                              child: Padding(
                                padding: const EdgeInsets.all(12),
                                child: Column(
                                  children: [
                                    Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        CircleAvatar(
                                          radius: 20,
                                          backgroundColor: hasDue
                                              ? (daysOverdue >= 30
                                                  ? Colors.red.shade100
                                                  : Colors.orange.shade100)
                                              : Colors.green.shade100,
                                          child: Text(
                                            name.isNotEmpty
                                                ? name[0].toUpperCase()
                                                : 'C',
                                            style: TextStyle(
                                              fontWeight: FontWeight.bold,
                                              color: hasDue
                                                  ? (daysOverdue >= 30
                                                      ? Colors.red.shade900
                                                      : Colors.orange.shade900)
                                                  : Colors.green.shade900,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Row(
                                                children: [
                                                  Expanded(
                                                    child: Text(
                                                      name,
                                                      style: const TextStyle(
                                                        fontWeight:
                                                            FontWeight.bold,
                                                        fontSize: 16,
                                                      ),
                                                      overflow:
                                                          TextOverflow.ellipsis,
                                                    ),
                                                  ),
                                                  if (hasDue &&
                                                      daysOverdue > 0)
                                                    Container(
                                                      padding: const EdgeInsets
                                                          .symmetric(
                                                          horizontal: 6,
                                                          vertical: 2),
                                                      decoration: BoxDecoration(
                                                        color: daysOverdue >= 30
                                                            ? Colors
                                                                .red.shade50
                                                            : Colors
                                                                .orange.shade50,
                                                        borderRadius:
                                                            BorderRadius
                                                                .circular(6),
                                                        border: Border.all(
                                                          color: daysOverdue >=
                                                                  30
                                                              ? Colors
                                                                  .red.shade300
                                                              : Colors.orange
                                                                  .shade300,
                                                        ),
                                                      ),
                                                      child: Text(
                                                        daysOverdue >= 30
                                                            ? '⚠️ $daysOverdue d'
                                                            : '⏱️ $daysOverdue d',
                                                        style: TextStyle(
                                                          fontSize: 10,
                                                          fontWeight:
                                                              FontWeight.bold,
                                                          color: daysOverdue >=
                                                                  30
                                                              ? Colors
                                                                  .red.shade800
                                                              : Colors.orange
                                                                  .shade800,
                                                        ),
                                                      ),
                                                    ),
                                                ],
                                              ),
                                              const SizedBox(height: 2),
                                              if (phone != null &&
                                                  phone.isNotEmpty)
                                                Row(
                                                  children: [
                                                    Text(
                                                      phone,
                                                      style: TextStyle(
                                                        fontSize: 12,
                                                        color: Colors
                                                            .grey.shade600,
                                                      ),
                                                    ),
                                                    const SizedBox(width: 4),
                                                    InkWell(
                                                      onTap: () =>
                                                          _callCustomer(phone),
                                                      child: const Padding(
                                                        padding:
                                                            EdgeInsets.all(2),
                                                        child: Icon(
                                                          Icons.phone,
                                                          size: 13,
                                                          color:
                                                              Color(0xFF0F766E),
                                                        ),
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              const SizedBox(height: 2),
                                              Text(
                                                '$orderCount orders • Billed: ₹ ${totalBilled.toStringAsFixed(0)} • Paid: ₹ ${totalPaid.toStringAsFixed(0)}',
                                                style: TextStyle(
                                                  fontSize: 11,
                                                  color: Colors.grey.shade600,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.end,
                                          children: [
                                            Text(
                                              hasDue
                                                  ? 'BALANCE DUE'
                                                  : 'SETTLED',
                                              style: TextStyle(
                                                fontSize: 10,
                                                fontWeight: FontWeight.w800,
                                                color: hasDue
                                                    ? Colors.red.shade800
                                                    : Colors.green.shade800,
                                              ),
                                            ),
                                            const SizedBox(height: 2),
                                            Text(
                                              currency.format(balanceDue),
                                              style: TextStyle(
                                                fontSize: 16,
                                                fontWeight: FontWeight.w900,
                                                color: hasDue
                                                    ? Colors.red.shade800
                                                    : Colors.green.shade800,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                    const Divider(height: 14),

                                    // Action Toolbar on Each Card
                                    Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        // Left: Open Passbook indicator
                                        TextButton.icon(
                                          style: TextButton.styleFrom(
                                            visualDensity:
                                                VisualDensity.compact,
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 6),
                                            foregroundColor: Colors.blueGrey,
                                          ),
                                          icon: const Icon(
                                              Icons.menu_book_outlined,
                                              size: 15),
                                          label: const Text('Passbook',
                                              style: TextStyle(fontSize: 12)),
                                          onPressed: () =>
                                              _openCustomerPassbook(item),
                                        ),

                                        // Right: Actions
                                        Row(
                                          children: [
                                            IconButton(
                                              tooltip: 'Statement PDF',
                                              icon: const Icon(
                                                Icons.picture_as_pdf_outlined,
                                                size: 18,
                                                color: Colors.blueGrey,
                                              ),
                                              visualDensity:
                                                  VisualDensity.compact,
                                              onPressed: () =>
                                                  _shareCustomerStatement(item),
                                            ),
                                            if (hasDue) ...[
                                              OutlinedButton.icon(
                                                style: OutlinedButton.styleFrom(
                                                  visualDensity:
                                                      VisualDensity.compact,
                                                  padding: const EdgeInsets
                                                      .symmetric(
                                                      horizontal: 8,
                                                      vertical: 4),
                                                  foregroundColor:
                                                      const Color(0xFF25D366),
                                                  side: const BorderSide(
                                                      color: Color(0xFF25D366)),
                                                ),
                                                icon: const Icon(
                                                    Icons.chat_outlined,
                                                    size: 14),
                                                label: const Text('Remind',
                                                    style: TextStyle(
                                                        fontSize: 12)),
                                                onPressed: () =>
                                                    _showWhatsAppReminderOptions(
                                                        item),
                                              ),
                                              const SizedBox(width: 6),
                                              FilledButton.icon(
                                                style: FilledButton.styleFrom(
                                                  visualDensity:
                                                      VisualDensity.compact,
                                                  padding: const EdgeInsets
                                                      .symmetric(
                                                      horizontal: 10,
                                                      vertical: 4),
                                                  backgroundColor:
                                                      const Color(0xFF0F766E),
                                                ),
                                                icon: const Icon(
                                                    Icons.payments_outlined,
                                                    size: 14),
                                                label: const Text('Receive ₹',
                                                    style: TextStyle(
                                                        fontSize: 12)),
                                                onPressed: () =>
                                                    _showQuickReceivePaymentDialog(
                                                        item),
                                              ),
                                            ],
                                          ],
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}
