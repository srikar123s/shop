import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:shop/database/database_helper.dart';
import 'package:shop/repositories/customer_repository.dart';
import 'package:shop/repositories/order_repository.dart';
import 'package:shop/repositories/product_repository.dart';
import 'package:shop/screens/order_details_screen.dart';
import 'package:shop/services/invoice_pdf_service.dart';
import 'package:shop/services/shop_customization_service.dart';

class CustomerKhataPassbookScreen extends StatefulWidget {
  const CustomerKhataPassbookScreen({
    super.key,
    required this.customerId,
    required this.customerName,
    this.customerPhone,
    required this.customerRepository,
    required this.orderRepository,
    required this.productRepository,
  });

  final int customerId;
  final String customerName;
  final String? customerPhone;
  final CustomerRepository customerRepository;
  final OrderRepository orderRepository;
  final ProductRepository productRepository;

  @override
  State<CustomerKhataPassbookScreen> createState() =>
      _CustomerKhataPassbookScreenState();
}

class _CustomerKhataPassbookScreenState
    extends State<CustomerKhataPassbookScreen> {
  List<Map<String, dynamic>> _ledgerEntries = [];
  bool _loading = true;
  double _totalBilled = 0.0;
  double _totalPaid = 0.0;
  double _totalDue = 0.0;
  String _filterType = 'all'; // 'all', 'debit', 'credit'
  bool _newestFirst = true;

  @override
  void initState() {
    super.initState();
    _loadLedger();
  }

  Future<void> _loadLedger() async {
    setState(() => _loading = true);
    final entries =
        await DatabaseHelper.instance.getCustomerKhataLedger(widget.customerId);

    double billed = 0.0;
    double paid = 0.0;
    for (final e in entries) {
      billed += (e['debit'] as num?)?.toDouble() ?? 0.0;
      paid += (e['credit'] as num?)?.toDouble() ?? 0.0;
    }

    if (!mounted) return;
    setState(() {
      _ledgerEntries = entries;
      _totalBilled = billed;
      _totalPaid = paid;
      _totalDue = (billed - paid) > 0.01 ? (billed - paid) : 0.0;
      _loading = false;
    });
  }

  Future<void> _callCustomer() async {
    final phone = widget.customerPhone;
    if (phone == null || phone.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No phone number for this customer')),
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

  void _showReminderOptions() {
    final shopName = ShopCustomizationService.instance.shopName;
    final upiId = ShopCustomizationService.instance.upiId;
    final dueStr = _totalDue.toStringAsFixed(2);
    final name = widget.customerName;

    final templates = [
      {
        'title': '🌟 Friendly / Gentle Reminder',
        'desc': 'Polite reminder with UPI ID',
        'text':
            '🙏 *Payment Reminder from $shopName*\nDear *$name*,\nThis is a gentle reminder that a balance of *₹ $dueStr* is pending in your account.'
                '${upiId.isNotEmpty ? "\n\nYou can pay via UPI to: *$upiId*" : ""}'
                '\n\nPlease settle at your convenience. Thank you! - *$shopName*',
      },
      {
        'title': '⚠️ Formal Due Notice',
        'desc': 'Clear balance notice for account settlement',
        'text':
            '⚠️ *Account Settlement Notice - $shopName*\nDear *$name*,\nYour outstanding credit balance is *₹ $dueStr*.'
                '${upiId.isNotEmpty ? "\nPay instantly via UPI: *$upiId*" : ""}'
                '\nPlease clear this balance today to keep your credit limit active.\nThank you! - *$shopName*',
      },
      {
        'title': '🚀 Instant UPI Pay Link',
        'desc': 'Deep-link that opens GPay/PhonePe pre-filled',
        'text':
            '💳 *Pay Bill Instantly - $shopName*\nCustomer: *$name*\nAmount Due: *₹ $dueStr*\n'
                '${upiId.isNotEmpty ? "Scan & Pay UPI ID: *$upiId*\nOr click to pay: upi://pay?pa=$upiId&pn=${Uri.encodeComponent(shopName)}&am=$dueStr&cu=INR\n" : ""}'
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
                'Select a message template to send to $name:',
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
                      await _sendWhatsAppMessage(t['text']!);
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

  Future<void> _sendWhatsAppMessage(String text) async {
    final phone = widget.customerPhone;
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

  Future<void> _showReceivePaymentDialog() async {
    final amountCtrl = TextEditingController(
      text: _totalDue > 0
          ? (_totalDue % 1 == 0
              ? _totalDue.toInt().toString()
              : _totalDue.toStringAsFixed(2))
          : '',
    );
    final notesCtrl = TextEditingController();
    String paymentMode = 'Cash';
    bool sendReceiptOnWhatsApp = true;

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
                  'Receive Payment - ${widget.customerName}',
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
                        '₹ ${_totalDue.toStringAsFixed(2)}',
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
                    if (_totalDue > 0)
                      ActionChip(
                        label: Text('Full (₹${_totalDue.toStringAsFixed(0)})'),
                        backgroundColor: Colors.teal.shade50,
                        onPressed: () => setDState(() {
                          amountCtrl.text = _totalDue.toStringAsFixed(2);
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
                  value: sendReceiptOnWhatsApp,
                  onChanged: (val) =>
                      setDState(() => sendReceiptOnWhatsApp = val ?? false),
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
        customerId: widget.customerId,
        amount: amount,
        paymentMode: paymentMode.toLowerCase(),
        notes: notesCtrl.text.trim(),
      );

      await _loadLedger();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Received ₹ ${amount.toStringAsFixed(2)} from ${widget.customerName} via $paymentMode',
          ),
          backgroundColor: Colors.teal,
        ),
      );

      if (sendReceiptOnWhatsApp) {
        final shopName = ShopCustomizationService.instance.shopName;
        final receiptMsg =
            '🙏 *Payment Received with Thanks!*\nReceived: *₹ ${amount.toStringAsFixed(2)}*\nMode: *$paymentMode*\nFrom: *${widget.customerName}*'
            '${notesCtrl.text.trim().isNotEmpty ? "\nNote: ${notesCtrl.text.trim()}" : ""}'
            '\nRemaining Balance: *₹ ${_totalDue.toStringAsFixed(2)}*'
            '\nThank you for your business! - *$shopName*';
        await _sendWhatsAppMessage(receiptMsg);
      }
    }
  }

  Future<void> _showAddManualDebitDialog() async {
    final amountCtrl = TextEditingController();
    final reasonCtrl = TextEditingController();

    final added = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.add_shopping_cart_rounded, color: Colors.red),
            SizedBox(width: 8),
            Text('Add Debit (You Gave / Udhaar)',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Add an old balance, goods taken outside app, or cash lent to this customer.',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: amountCtrl,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Amount (₹) *',
                border: OutlineInputBorder(),
                prefixText: '₹ ',
                isDense: true,
              ),
              autofocus: true,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: reasonCtrl,
              decoration: const InputDecoration(
                labelText: 'Description / Reason *',
                border: OutlineInputBorder(),
                hintText: 'e.g. Old register balance, 2 bags cement',
                isDense: true,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade800),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Add to Khata'),
          ),
        ],
      ),
    );

    if (added == true && mounted) {
      final amount = double.tryParse(amountCtrl.text.trim()) ?? 0.0;
      final desc = reasonCtrl.text.trim().isNotEmpty
          ? reasonCtrl.text.trim()
          : 'Manual Udhaar Entry';
      if (amount <= 0) return;

      await DatabaseHelper.instance.recordManualKhataDebit(
        customerId: widget.customerId,
        amount: amount,
        description: desc,
      );

      await _loadLedger();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Added ₹ $amount to ${widget.customerName} Khata'),
          backgroundColor: Colors.red.shade800,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final currency = NumberFormat.currency(locale: 'en_IN', symbol: '₹ ');
    final entries = _ledgerEntries.where((e) {
      if (_filterType == 'debit' && e['type'] != 'debit') return false;
      if (_filterType == 'credit' && e['type'] != 'credit') return false;
      return true;
    }).toList();

    if (_newestFirst) {
      entries.sort(
          (a, b) => (b['date'] as DateTime).compareTo(a['date'] as DateTime));
    } else {
      entries.sort(
          (a, b) => (a['date'] as DateTime).compareTo(b['date'] as DateTime));
    }

    final hasDue = _totalDue > 0.01;

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.customerName,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
              overflow: TextOverflow.ellipsis,
            ),
            Text(
              widget.customerPhone ?? 'Khata Passbook',
              style: const TextStyle(fontSize: 11, color: Colors.white70),
            ),
          ],
        ),
        actions: [
          if (widget.customerPhone != null &&
              widget.customerPhone!.isNotEmpty) ...[
            IconButton(
              tooltip: 'Call Customer',
              icon: const Icon(Icons.call_outlined),
              onPressed: _callCustomer,
            ),
            IconButton(
              tooltip: 'WhatsApp Reminder',
              icon: const Icon(Icons.chat_outlined),
              onPressed: _showReminderOptions,
            ),
          ],
          IconButton(
            tooltip: 'Share PDF Statement',
            icon: const Icon(Icons.picture_as_pdf_outlined),
            onPressed: () async {
              await InvoicePdfService.instance.shareCustomerKhataStatement(
                customerName: widget.customerName,
                customerPhone: widget.customerPhone,
                ledgerEntries: _ledgerEntries,
                totalDue: _totalDue,
                totalBilled: _totalBilled,
                totalPaid: _totalPaid,
              );
            },
          ),
          IconButton(
            tooltip: 'Print Statement',
            icon: const Icon(Icons.print_outlined),
            onPressed: () async {
              await InvoicePdfService.instance.printCustomerKhataStatement(
                customerName: widget.customerName,
                customerPhone: widget.customerPhone,
                ledgerEntries: _ledgerEntries,
                totalDue: _totalDue,
                totalBilled: _totalBilled,
                totalPaid: _totalPaid,
              );
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // Hero Balance Card
          Container(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: hasDue
                    ? [const Color(0xFF7F1D1D), const Color(0xFFB91C1C)]
                    : [const Color(0xFF065F46), const Color(0xFF047857)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          hasDue ? 'NET BALANCE DUE (PENDING)' : 'ACCOUNT STATUS',
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.5,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          hasDue ? currency.format(_totalDue) : 'ALL SETTLED (₹0)',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 24,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ],
                    ),
                    if (hasDue)
                      FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: const Color(0xFFB91C1C),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 8),
                          visualDensity: VisualDensity.compact,
                        ),
                        icon: const Icon(Icons.chat_outlined, size: 16),
                        label: const Text('Reminder',
                            style: TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 12)),
                        onPressed: _showReminderOptions,
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      Column(
                        children: [
                          const Text('Total Billed',
                              style: TextStyle(
                                  color: Colors.white70, fontSize: 11)),
                          const SizedBox(height: 2),
                          Text(
                            currency.format(_totalBilled),
                            style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 13),
                          ),
                        ],
                      ),
                      Container(width: 1, height: 24, color: Colors.white24),
                      Column(
                        children: [
                          const Text('Total Paid',
                              style: TextStyle(
                                  color: Colors.white70, fontSize: 11)),
                          const SizedBox(height: 2),
                          Text(
                            currency.format(_totalPaid),
                            style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 13),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Filters & Sort Bar
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
            child: Row(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        FilterChip(
                          label: Text('All (${_ledgerEntries.length})'),
                          selected: _filterType == 'all',
                          onSelected: (_) =>
                              setState(() => _filterType = 'all'),
                          visualDensity: VisualDensity.compact,
                        ),
                        const SizedBox(width: 6),
                        FilterChip(
                          label: const Text('Bills (Gave)'),
                          selected: _filterType == 'debit',
                          selectedColor: Colors.red.shade100,
                          onSelected: (_) =>
                              setState(() => _filterType = 'debit'),
                          visualDensity: VisualDensity.compact,
                        ),
                        const SizedBox(width: 6),
                        FilterChip(
                          label: const Text('Payments (Got)'),
                          selected: _filterType == 'credit',
                          selectedColor: Colors.green.shade100,
                          onSelected: (_) =>
                              setState(() => _filterType = 'credit'),
                          visualDensity: VisualDensity.compact,
                        ),
                      ],
                    ),
                  ),
                ),
                IconButton(
                  tooltip: _newestFirst
                      ? 'Sorting: Newest First'
                      : 'Sorting: Oldest First',
                  icon: Icon(
                    _newestFirst
                        ? Icons.arrow_downward_rounded
                        : Icons.arrow_upward_rounded,
                    size: 20,
                  ),
                  onPressed: () =>
                      setState(() => _newestFirst = !_newestFirst),
                ),
              ],
            ),
          ),

          // Passbook Entries List
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : entries.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.menu_book_rounded,
                                size: 52, color: Colors.grey.shade400),
                            const SizedBox(height: 12),
                            Text(
                              'No transactions found for this customer.',
                              style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.grey.shade600),
                            ),
                          ],
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 80),
                        itemCount: entries.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (context, index) {
                          final item = entries[index];
                          final isDebit = item['type'] == 'debit';
                          final title = item['title'] as String? ?? '';
                          final subtitle = item['subtitle'] as String? ?? '';
                          final date = item['date'] as DateTime;
                          final dateStr =
                              DateFormat('dd MMM yyyy, hh:mm a').format(date);
                          final amount =
                              (item['amount'] as num?)?.toDouble() ?? 0.0;
                          final runningBal =
                              (item['running_balance'] as num?)?.toDouble() ??
                                  0.0;
                          final orderId = item['id'] as int?;

                          return Card(
                            elevation: 0.5,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                              side: BorderSide(
                                color: isDebit
                                    ? Colors.red.shade200
                                    : Colors.green.shade200,
                              ),
                            ),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(12),
                              onTap: isDebit && orderId != null
                                  ? () async {
                                      await Navigator.push(
                                        context,
                                        MaterialPageRoute<void>(
                                          builder: (_) => OrderDetailsScreen(
                                            orderId: orderId,
                                            orderRepository:
                                                widget.orderRepository,
                                            customerRepository:
                                                widget.customerRepository,
                                            productRepository:
                                                widget.productRepository,
                                          ),
                                        ),
                                      );
                                      _loadLedger();
                                    }
                                  : null,
                              child: Padding(
                                padding: const EdgeInsets.all(12),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        Row(
                                          children: [
                                            Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                      horizontal: 8,
                                                      vertical: 3),
                                              decoration: BoxDecoration(
                                                color: isDebit
                                                    ? Colors.red.shade50
                                                    : Colors.green.shade50,
                                                borderRadius:
                                                    BorderRadius.circular(6),
                                              ),
                                              child: Text(
                                                isDebit
                                                    ? '🔴 YOU GAVE'
                                                    : '🟢 YOU GOT',
                                                style: TextStyle(
                                                  fontWeight: FontWeight.w900,
                                                  fontSize: 10,
                                                  color: isDebit
                                                      ? Colors.red.shade800
                                                      : Colors.green.shade800,
                                                ),
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            Text(
                                              title,
                                              style: const TextStyle(
                                                fontWeight: FontWeight.bold,
                                                fontSize: 14,
                                              ),
                                            ),
                                          ],
                                        ),
                                        Text(
                                          (isDebit ? '+ ' : '- ') +
                                              currency.format(amount),
                                          style: TextStyle(
                                            fontWeight: FontWeight.w900,
                                            fontSize: 15,
                                            color: isDebit
                                                ? Colors.red.shade800
                                                : Colors.green.shade800,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      subtitle,
                                      style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.grey.shade700),
                                    ),
                                    const SizedBox(height: 6),
                                    Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        Text(
                                          dateStr,
                                          style: TextStyle(
                                              fontSize: 11,
                                              color: Colors.grey.shade500),
                                        ),
                                        Text(
                                          'Balance: ${currency.format(runningBal)}',
                                          style: TextStyle(
                                            fontWeight: FontWeight.w700,
                                            fontSize: 12,
                                            color: runningBal > 0
                                                ? Colors.red.shade900
                                                : Colors.green.shade800,
                                          ),
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

      // Bottom Khatabook Action Bar: YOU GAVE vs YOU GOT
      bottomSheet: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 10,
              offset: const Offset(0, -3),
            ),
          ],
        ),
        child: SafeArea(
          child: Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.red.shade800,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text(
                    'YOU GAVE ₹',
                    style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                        letterSpacing: 0.5),
                  ),
                  onPressed: _showAddManualDebitDialog,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF0F766E),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  icon: const Icon(Icons.arrow_downward_rounded, size: 18),
                  label: const Text(
                    'YOU GOT ₹',
                    style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                        letterSpacing: 0.5),
                  ),
                  onPressed: _showReceivePaymentDialog,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
