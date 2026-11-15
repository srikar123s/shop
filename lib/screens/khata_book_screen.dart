import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shop/database/database_helper.dart';
import 'package:shop/repositories/customer_repository.dart';
import 'package:shop/repositories/order_repository.dart';
import 'package:shop/repositories/product_repository.dart';
import 'package:shop/screens/customer_orders_screen.dart';
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
  bool _loading = true;
  String _filter = 'due'; // 'due', 'all', 'settled'

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
    if (!mounted) return;
    setState(() {
      _khataList = list;
      _applyFilter();
      _loading = false;
    });
  }

  void _applyFilter() {
    final query = _searchController.text.trim().toLowerCase();
    setState(() {
      _filteredList = _khataList.where((item) {
        final due = (item['balance_due'] as num?)?.toDouble() ?? 0.0;
        if (_filter == 'due' && due <= 0.01) return false;
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
    });
  }

  Future<void> _showReceivePaymentDialog(Map<String, dynamic> item) async {
    final customerId = item['customer_id'] as int;
    final customerName = item['customer_name'] as String;
    final balanceDue = (item['balance_due'] as num?)?.toDouble() ?? 0.0;

    final amountCtrl =
        TextEditingController(text: balanceDue.toStringAsFixed(2));
    final notesCtrl = TextEditingController();
    String paymentMode = 'Cash';

    final received = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDState) => AlertDialog(
          title: Text(
            'Receive Payment - $customerName',
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Current Balance Due: ₹ ${balanceDue.toStringAsFixed(2)}',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.red,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: amountCtrl,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'Amount Received (₹) *',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.currency_rupee),
                ),
                autofocus: true,
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: paymentMode,
                decoration: const InputDecoration(
                  labelText: 'Payment Mode',
                  border: OutlineInputBorder(),
                ),
                items: const [
                  DropdownMenuItem(value: 'Cash', child: Text('Cash')),
                  DropdownMenuItem(value: 'UPI', child: Text('UPI / GPay')),
                  DropdownMenuItem(value: 'Cheque', child: Text('Cheque')),
                  DropdownMenuItem(
                      value: 'Bank Transfer', child: Text('Bank Transfer')),
                ],
                onChanged: (val) {
                  if (val != null) setDState(() => paymentMode = val);
                },
              ),
              const SizedBox(height: 12),
              TextField(
                controller: notesCtrl,
                decoration: const InputDecoration(
                  labelText: 'Notes / Reference (Optional)',
                  border: OutlineInputBorder(),
                  hintText: 'e.g. Paid at counter / GPay ref',
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('CANCEL'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF0F766E),
              ),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('SAVE PAYMENT'),
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

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Received ₹ ${amount.toStringAsFixed(2)} from $customerName via $paymentMode',
          ),
          backgroundColor: Colors.teal,
        ),
      );
      _loadKhata();
    }
  }

  void _sendWhatsAppReminder(Map<String, dynamic> item) {
    final customerName = item['customer_name'] as String;
    final balanceDue = (item['balance_due'] as num?)?.toDouble() ?? 0.0;
    final shopName = ShopCustomizationService.instance.shopName;
    final upiId = ShopCustomizationService.instance.upiId;

    final buffer = StringBuffer();
    buffer.writeln('🙏 *Payment Reminder from $shopName*');
    buffer.writeln('Dear *$customerName*,');
    buffer.writeln(
        'This is a friendly reminder that you have an outstanding bill balance of *₹ ${balanceDue.toStringAsFixed(2)}*.');
    if (upiId.isNotEmpty) {
      buffer.writeln('\nYou can pay via UPI to: *$upiId*');
    }
    buffer.writeln('\nPlease clear the balance at your earliest convenience.');
    buffer.writeln('Thank you for your business! - *$shopName*');

    Share.share(buffer.toString());
  }

  @override
  Widget build(BuildContext context) {
    final currency = NumberFormat.currency(locale: 'en_IN', symbol: '₹ ');

    final totalDue = _khataList.fold<double>(
        0.0, (sum, i) => sum + ((i['balance_due'] as num?)?.toDouble() ?? 0.0));
    final totalCollected = _khataList.fold<double>(
        0.0, (sum, i) => sum + ((i['total_paid'] as num?)?.toDouble() ?? 0.0));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Khata Book (Udhaar Ledger)',
            style: TextStyle(fontWeight: FontWeight.bold)),
      ),
      body: Column(
        children: [
          // Total Balance Due Ribbon
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFF7F1D1D), Color(0xFFB91C1C)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'TOTAL UDHAAR (CREDIT GIVEN)',
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
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      const Text(
                        'Total Collected',
                        style: TextStyle(color: Colors.white70, fontSize: 11),
                      ),
                      Text(
                        currency.format(totalCollected),
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
          ),

          // Search and Filters
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search customer or phone...',
                prefixIcon: const Icon(Icons.search),
                isDense: true,
                suffixIcon: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_searchController.text.isNotEmpty)
                      IconButton(
                        icon: const Icon(Icons.clear, size: 20),
                        onPressed: () {
                          _searchController.clear();
                          _applyFilter();
                        },
                      ),
                    IconButton(
                      tooltip: 'Voice Search',
                      icon: const Icon(Icons.mic, color: Color(0xFF0F766E)),
                      onPressed: () async {
                        final text =
                            await VoiceSearchService.instance.recordSpeech(
                          context,
                          title: 'Search Khata',
                          hint: 'Say customer name (e.g. Srikar)...',
                        );
                        if (text != null && text.trim().isNotEmpty) {
                          _searchController.text = text.trim();
                          _applyFilter();
                        }
                      },
                    ),
                  ],
                ),
              ),
              onChanged: (_) => _applyFilter(),
            ),
          ),

          // Filter Segmented Buttons
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: SizedBox(
              width: double.infinity,
              child: SegmentedButton<String>(
                segments: const [
                  ButtonSegment(
                    value: 'due',
                    label: Text('With Balance Due', style: TextStyle(fontSize: 12)),
                    icon: Icon(Icons.pending_actions_rounded, size: 14),
                  ),
                  ButtonSegment(
                    value: 'all',
                    label: Text('All Customers', style: TextStyle(fontSize: 12)),
                    icon: Icon(Icons.people_alt_outlined, size: 14),
                  ),
                  ButtonSegment(
                    value: 'settled',
                    label: Text('Settled (₹0)', style: TextStyle(fontSize: 12)),
                    icon: Icon(Icons.check_circle_outline, size: 14),
                  ),
                ],
                selected: {_filter},
                onSelectionChanged: (val) {
                  setState(() => _filter = val.first);
                  _applyFilter();
                },
                style: const ButtonStyle(
                  visualDensity: VisualDensity.compact,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),

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
                          final customerId = item['customer_id'] as int;
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
                          final hasDue = balanceDue > 0.01;

                          return Card(
                            elevation: 1,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                              side: BorderSide(
                                color: hasDue
                                    ? Colors.red.shade200
                                    : Colors.green.shade200,
                                width: 1,
                              ),
                            ),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(14),
                              onTap: () async {
                                await Navigator.push(
                                  context,
                                  MaterialPageRoute<void>(
                                    builder: (_) => CustomerOrdersScreen(
                                      customerId: customerId,
                                      customerName: name,
                                      customerPhone: phone,
                                      customerRepository:
                                          widget.customerRepository,
                                      productRepository:
                                          widget.productRepository,
                                      orderRepository: widget.orderRepository,
                                    ),
                                  ),
                                );
                                _loadKhata();
                              },
                              child: Padding(
                                padding: const EdgeInsets.all(14),
                                child: Column(
                                  children: [
                                    Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        CircleAvatar(
                                          radius: 20,
                                          backgroundColor: hasDue
                                              ? Colors.red.shade50
                                              : Colors.green.shade50,
                                          child: Text(
                                            name.isNotEmpty
                                                ? name[0].toUpperCase()
                                                : 'C',
                                            style: TextStyle(
                                              fontWeight: FontWeight.bold,
                                              color: hasDue
                                                  ? Colors.red.shade800
                                                  : Colors.green.shade800,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                name,
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 16,
                                                ),
                                              ),
                                              const SizedBox(height: 2),
                                              if (phone != null &&
                                                  phone.isNotEmpty)
                                                Text(
                                                  '📞 $phone',
                                                  style: TextStyle(
                                                    fontSize: 12,
                                                    color: Colors.grey.shade600,
                                                  ),
                                                ),
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
                                        Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.end,
                                          children: [
                                            Text(
                                              hasDue ? 'BALANCE DUE' : 'SETTLED',
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
                                    if (hasDue) ...[
                                      const Divider(height: 16),
                                      Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.end,
                                        children: [
                                          OutlinedButton.icon(
                                            style: OutlinedButton.styleFrom(
                                              visualDensity:
                                                  VisualDensity.compact,
                                              foregroundColor:
                                                  const Color(0xFF25D366),
                                              side: const BorderSide(
                                                  color: Color(0xFF25D366)),
                                            ),
                                            icon: const Icon(
                                                Icons.chat_outlined,
                                                size: 15),
                                            label: const Text('Reminder',
                                                style: TextStyle(fontSize: 12)),
                                            onPressed: () =>
                                                _sendWhatsAppReminder(item),
                                          ),
                                          const SizedBox(width: 8),
                                          FilledButton.icon(
                                            style: FilledButton.styleFrom(
                                              visualDensity:
                                                  VisualDensity.compact,
                                              backgroundColor:
                                                  const Color(0xFF0F766E),
                                            ),
                                            icon: const Icon(
                                                Icons.payments_outlined,
                                                size: 15),
                                            label: const Text('Receive Payment',
                                                style: TextStyle(fontSize: 12)),
                                            onPressed: () =>
                                                _showReceivePaymentDialog(item),
                                          ),
                                        ],
                                      ),
                                    ],
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
