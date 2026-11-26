import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:shop/database/database_helper.dart';
import 'package:shop/models/customer.dart';
import 'package:shop/repositories/customer_repository.dart';
import 'package:shop/repositories/order_repository.dart';
import 'package:shop/repositories/product_repository.dart';
import 'package:shop/screens/order_receipt_screen.dart';
import 'package:shop/services/invoice_pdf_service.dart';
import 'package:shop/services/shop_customization_service.dart';
import 'package:shop/widgets/phone_picker_modal.dart';

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
  double _creditLimit = 0.0;
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
    final status =
        await DatabaseHelper.instance.getCustomerCreditStatus(widget.customerId);

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
      _totalDue = billed - paid;
      _creditLimit = (status['credit_limit'] as num?)?.toDouble() ?? 0.0;
      _loading = false;
    });
  }

  Future<void> _callCustomer() async {
    final rawPhone = widget.customerPhone;
    if (rawPhone == null || rawPhone.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No phone number for this customer')),
      );
      return;
    }
    final numbers = Customer.extractNumbers(rawPhone);
    if (numbers.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No valid phone number for this customer')),
      );
      return;
    }

    String phoneToCall = numbers.first;
    if (numbers.length > 1) {
      final chosen = await showPhonePickerModal(
        context: context,
        customerName: widget.customerName,
        phoneNumbers: numbers,
        actionTitle: 'Call Customer',
      );
      if (chosen == null) return;
      phoneToCall = chosen;
    }

    final clean = phoneToCall.replaceAll(RegExp(r'[^0-9+]'), '');
    final uri = Uri(scheme: 'tel', path: clean);
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri);
      } else {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not dial $phoneToCall')),
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
    final rawPhone = widget.customerPhone;
    if (rawPhone != null && rawPhone.isNotEmpty) {
      final numbers = Customer.extractNumbers(rawPhone);
      String? phoneToMsg;
      if (numbers.length > 1) {
        phoneToMsg = await showPhonePickerModal(
          context: context,
          customerName: widget.customerName,
          phoneNumbers: numbers,
          actionTitle: 'Send WhatsApp Reminder',
        );
        if (phoneToMsg == null) return;
      } else if (numbers.isNotEmpty) {
        phoneToMsg = numbers.first;
      }

      if (phoneToMsg != null && phoneToMsg.isNotEmpty) {
        final clean = phoneToMsg.replaceAll(RegExp(r'[^0-9]'), '');
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
    bool sendReceiptOnWhatsApp = false;

    try {
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
                  onChanged: (val) => setDState(() {}),
                ),
                Builder(
                  builder: (context) {
                    final entered =
                        double.tryParse(amountCtrl.text.trim()) ?? 0.0;
                    if (entered > _totalDue && _totalDue > 0) {
                      final advance = entered - _totalDue;
                      return Container(
                        margin: const EdgeInsets.only(top: 8),
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.amber.shade50,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.amber.shade300),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(Icons.info_outline,
                                size: 16, color: Colors.amber.shade900),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                'Current due is ₹${_totalDue.toStringAsFixed(2)}. The extra ₹${advance.toStringAsFixed(2)} will be considered as ADVANCE PAYMENT and will be settled with future bills.',
                                style: TextStyle(
                                    fontSize: 11,
                                    color: Colors.amber.shade900,
                                    fontWeight: FontWeight.bold),
                              ),
                            ),
                          ],
                        ),
                      );
                    }
                    return const SizedBox.shrink();
                  },
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
      double amount = double.tryParse(amountCtrl.text.trim()) ?? 0.0;
      if (amount <= 0) return;

      final currentPending = _totalDue > 0.01 ? _totalDue : 0.0;
      if (amount > currentPending) {
        final advance = amount - currentPending;
        final confirmAdvance = await showDialog<String>(
          context: context,
          builder: (actx) => AlertDialog(
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: const Row(
              children: [
                Icon(Icons.account_balance_wallet_outlined,
                    color: Color(0xFF0F766E)),
                SizedBox(width: 8),
                Text('Advance Payment Notice'),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (currentPending > 0) ...[
                  Text('Customer\'s balance due is ₹${currentPending.toStringAsFixed(2)}.'),
                  Text('Entered payment: ₹${amount.toStringAsFixed(2)}.\n'),
                ] else ...[
                  const Text('Customer currently has no pending balance due.\n'),
                ],
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.teal.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.teal.shade200),
                  ),
                  child: Text(
                    currentPending > 0
                        ? 'The remaining amount of ₹${advance.toStringAsFixed(2)} will be considered as ADVANCE PAYMENT and will be settled with future bills.'
                        : 'The full payment of ₹${advance.toStringAsFixed(2)} will be considered as ADVANCE PAYMENT and will be settled with future bills.',
                    style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF0F766E)),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  currentPending > 0
                      ? 'Would you like to accept this advance or cap at the exact balance due?'
                      : 'Accept this advance payment for future orders?',
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(actx, 'cancel'),
                child: const Text('Cancel'),
              ),
              if (currentPending > 0)
                OutlinedButton(
                  onPressed: () => Navigator.pop(actx, 'cap_due'),
                  child: Text('Cap at ₹${currentPending.toStringAsFixed(2)}'),
                ),
              FilledButton(
                style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF0F766E)),
                onPressed: () => Navigator.pop(actx, 'advance'),
                child: Text('Accept ₹${advance.toStringAsFixed(2)} as Advance'),
              ),
            ],
          ),
        );

        if (confirmAdvance == null || confirmAdvance == 'cancel') return;
        if (confirmAdvance == 'cap_due') {
          amount = currentPending;
        }
      }

      final advanceAmt = amount > currentPending ? (amount - currentPending) : 0.0;
      final advanceNote = advanceAmt > 0
          ? 'Includes ₹${advanceAmt.toStringAsFixed(2)} Advance Payment (to settle with future bills)'
          : '';
      final finalNotes = [
        if (notesCtrl.text.trim().isNotEmpty) notesCtrl.text.trim(),
        if (advanceNote.isNotEmpty) advanceNote,
      ].join(' | ');

      await DatabaseHelper.instance.recordCustomerKhataPayment(
        customerId: widget.customerId,
        amount: amount,
        paymentMode: paymentMode.toLowerCase(),
        notes: finalNotes,
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
        final remainingDue = _totalDue - amount;
        final remainingStr = remainingDue <= 0
            ? (remainingDue < 0
                ? '₹ 0.00 (Advance Credit: ₹${(-remainingDue).toStringAsFixed(2)} - will settle with future bills)'
                : '₹ 0.00 (All dues cleared)')
            : '₹ ${remainingDue.toStringAsFixed(2)}';
        final receiptMsg =
            '🙏 *Payment Received with Thanks!*\nReceived: *₹ ${amount.toStringAsFixed(2)}*\nMode: *$paymentMode*\nFrom: *${widget.customerName}*'
            '${finalNotes.isNotEmpty ? "\nNote: $finalNotes" : ""}'
            '\nRemaining Balance: *$remainingStr*'
            '\nThank you for your business! - *$shopName*';
        await _sendWhatsAppMessage(receiptMsg);
      }
    }
  } finally {
    amountCtrl.dispose();
    notesCtrl.dispose();
  }
}

  Future<void> _showAddManualDebitDialog() async {
    final amountCtrl = TextEditingController();
    final reasonCtrl = TextEditingController();

    try {
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
  } finally {
    amountCtrl.dispose();
    reasonCtrl.dispose();
  }
}

  Future<void> _showEditCreditLimitDialog() async {
    final limitCtrl = TextEditingController(
      text: _creditLimit > 0 ? _creditLimit.toStringAsFixed(0) : '',
    );

    try {
      final updated = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.shield_outlined, color: Color(0xFF0F766E)),
            SizedBox(width: 8),
            Text('Set Credit Limit',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Set maximum allowable credit for "${widget.customerName}". The app alerts you whenever a bill or balance exceeds this threshold.',
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: limitCtrl,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Credit Limit (₹)',
                hintText: 'e.g. 25000 (0 for no limit)',
                border: OutlineInputBorder(),
                prefixText: '₹ ',
                isDense: true,
              ),
              autofocus: true,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style:
                FilledButton.styleFrom(backgroundColor: const Color(0xFF0F766E)),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Save Limit'),
          ),
        ],
      ),
    );

    if (updated == true && mounted) {
      final newLimit = double.tryParse(limitCtrl.text.trim()) ?? 0.0;
      await DatabaseHelper.instance.updateCustomerCreditLimit(
        widget.customerId,
        newLimit,
      );
      await _loadLedger();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            newLimit > 0
                ? 'Credit limit updated to ₹ ${newLimit.toStringAsFixed(0)}'
                : 'Credit limit removed (Unlimited credit)',
          ),
          backgroundColor: const Color(0xFF0F766E),
        ),
      );
    }
  } finally {
    limitCtrl.dispose();
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
    final isAdvance = _totalDue < -0.01;
    final advanceAmt = -_totalDue;

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
              widget.customerPhone != null
                  ? (Customer.extractNumbers(widget.customerPhone).isNotEmpty
                      ? Customer.extractNumbers(widget.customerPhone).join(' • ')
                      : widget.customerPhone!)
                  : 'Khata Passbook',
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
                colors: isAdvance
                    ? [const Color(0xFF047857), const Color(0xFF0F766E)]
                    : (hasDue
                        ? [const Color(0xFF0F172A), const Color(0xFF1E293B)]
                        : [const Color(0xFF064E3B), const Color(0xFF0F766E)]),
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
                          isAdvance
                              ? 'ADVANCE BALANCE (CREDIT WITH SHOP)'
                              : (hasDue
                                  ? 'NET BALANCE DUE (PENDING)'
                                  : 'ACCOUNT STATUS'),
                          style: TextStyle(
                            color: isAdvance
                                ? const Color(0xFFCCFBF1)
                                : Colors.white70,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.5,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          isAdvance
                              ? currency.format(advanceAmt)
                              : (hasDue
                                  ? currency.format(_totalDue)
                                  : 'ALL SETTLED (₹0)'),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 24,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        if (isAdvance)
                          const Padding(
                            padding: EdgeInsets.only(top: 2),
                            child: Text(
                              'Auto-settles with future orders and bills',
                              style: TextStyle(
                                  color: Color(0xFFCCFBF1), fontSize: 11),
                            ),
                          ),
                      ],
                    ),
                    if (hasDue)
                      FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: const Color(0xFFE11D48),
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
                    if (isAdvance)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.18),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: Colors.white30),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.account_balance_wallet_rounded,
                                color: Color(0xFFCCFBF1), size: 16),
                            SizedBox(width: 5),
                            Text('Advance Credit',
                                style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12,
                                    color: Colors.white)),
                          ],
                        ),
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
                if (_creditLimit > 0) ...[
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: _totalDue > _creditLimit
                          ? Colors.red.shade900.withValues(alpha: 0.35)
                          : Colors.white.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: _totalDue > _creditLimit
                            ? Colors.redAccent
                            : Colors.white24,
                      ),
                    ),
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  _totalDue > _creditLimit
                                      ? Icons.warning_amber_rounded
                                      : Icons.shield_outlined,
                                  size: 15,
                                  color: Colors.white,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  _totalDue > _creditLimit
                                      ? '⚠️ EXCEEDED BY ₹ ${(_totalDue - _creditLimit).toStringAsFixed(0)}'
                                      : 'Credit Limit: ₹ ${_creditLimit.toStringAsFixed(0)}',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                            InkWell(
                              onTap: _showEditCreditLimitDialog,
                              child: const Padding(
                                padding: EdgeInsets.all(2),
                                child: Text(
                                  'Edit Limit',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 11,
                                    decoration: TextDecoration.underline,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        LinearProgressIndicator(
                          value: (_totalDue / _creditLimit).clamp(0.0, 1.0),
                          backgroundColor: Colors.white24,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            _totalDue > _creditLimit
                                ? Colors.amberAccent
                                : Colors.greenAccent,
                          ),
                          minHeight: 4,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ],
                    ),
                  ),
                ] else ...[
                  const SizedBox(height: 8),
                  InkWell(
                    onTap: _showEditCreditLimitDialog,
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.shield_outlined,
                            size: 14, color: Colors.white70),
                        SizedBox(width: 4),
                        Text(
                          'Set Credit Limit (Optional)',
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: 11,
                            decoration: TextDecoration.underline,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
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
                          final displayOrderNum =
                              (item['order_number'] as num?)?.toInt() ?? orderId;
                          final rawMode = (item['payment_mode'] as String?)?.toUpperCase() ?? '';
                          final modeLabel = rawMode.contains('UPI')
                              ? '📱 UPI'
                              : (rawMode.contains('CASH')
                                  ? '💵 CASH'
                                  : (rawMode.contains('CHEQUE')
                                      ? '🧾 CHEQUE'
                                      : (rawMode.isNotEmpty ? '🏦 $rawMode' : '')));

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
                              onTap: () async {
                                if (isDebit) {
                                  if (orderId != null &&
                                      !subtitle.contains('Manual Udhaar')) {
                                    await Navigator.push(
                                      context,
                                      MaterialPageRoute<void>(
                                        builder: (_) => OrderReceiptScreen(
                                          orderId: orderId,
                                          orderRepository:
                                              widget.orderRepository,
                                          customerRepository:
                                              widget.customerRepository,
                                          productRepository:
                                              widget.productRepository,
                                          customerBillNumber: item['bill_number'] as int?,
                                        ),
                                      ),
                                    );
                                    _loadLedger();
                                  } else {
                                    showDialog<void>(
                                      context: context,
                                      builder: (ctx) => AlertDialog(
                                        shape: RoundedRectangleBorder(
                                            borderRadius:
                                                BorderRadius.circular(16)),
                                        title: const Row(
                                          children: [
                                            Icon(Icons.edit_note_rounded,
                                                color: Color(0xFFBE123C)),
                                            SizedBox(width: 8),
                                            Text('Manual Khata Udhaar',
                                                style: TextStyle(
                                                    fontWeight: FontWeight.bold,
                                                    fontSize: 16)),
                                          ],
                                        ),
                                        content: Column(
                                          mainAxisSize: MainAxisSize.min,
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                                'Customer: ${widget.customerName}',
                                                style: const TextStyle(
                                                    fontWeight:
                                                        FontWeight.w600)),
                                            const SizedBox(height: 6),
                                            Text(
                                              currency.format(amount),
                                              style: const TextStyle(
                                                  fontSize: 20,
                                                  fontWeight: FontWeight.w900,
                                                  color: Color(0xFFBE123C)),
                                            ),
                                            const SizedBox(height: 8),
                                            Text('Details: $subtitle',
                                                style: TextStyle(
                                                    fontSize: 13,
                                                    color:
                                                        Colors.grey.shade700)),
                                            const SizedBox(height: 4),
                                            Text('Date: $dateStr',
                                                style: const TextStyle(
                                                    fontSize: 12,
                                                    color: Colors.grey)),
                                          ],
                                        ),
                                        actions: [
                                          TextButton(
                                            onPressed: () =>
                                                Navigator.pop(ctx),
                                            child: const Text('Close'),
                                          ),
                                        ],
                                      ),
                                    );
                                  }
                                } else {
                                  final pMode = (item['payment_mode'] as String?)?.toUpperCase() ?? 'PAYMENT';
                                  final pNotes = item['notes'] as String? ?? '';
                                  showDialog<void>(
                                    context: context,
                                    builder: (ctx) => AlertDialog(
                                      shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(16)),
                                      title: const Row(
                                        children: [
                                          Icon(Icons.verified_rounded,
                                              color: Color(0xFF0F766E)),
                                          SizedBox(width: 8),
                                          Text('Payment Receipt',
                                              style: TextStyle(
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 16)),
                                        ],
                                      ),
                                      content: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text('Customer: ${widget.customerName}',
                                              style: const TextStyle(
                                                  fontWeight:
                                                      FontWeight.w600)),
                                          const SizedBox(height: 6),
                                          Text(
                                            currency.format(amount),
                                            style: const TextStyle(
                                                fontSize: 22,
                                                fontWeight: FontWeight.w900,
                                                color: Color(0xFF059669)),
                                          ),
                                          const SizedBox(height: 8),
                                          Text('Collected via: $pMode',
                                              style: const TextStyle(
                                                  fontSize: 13,
                                                  fontWeight: FontWeight.bold)),
                                          const SizedBox(height: 4),
                                          Text('Timestamp: $dateStr',
                                              style: const TextStyle(
                                                  fontSize: 12,
                                                  color: Colors.grey)),
                                          if (pNotes.isNotEmpty) ...[
                                            const SizedBox(height: 4),
                                            Text('Reference: $pNotes',
                                                style: const TextStyle(
                                                    fontSize: 12,
                                                    color: Colors.grey)),
                                          ],
                                        ],
                                      ),
                                      actions: [
                                        TextButton(
                                          onPressed: () => Navigator.pop(ctx),
                                          child: const Text('Close'),
                                        ),
                                        FilledButton.icon(
                                          style: FilledButton.styleFrom(
                                              backgroundColor:
                                                  const Color(0xFF25D366)),
                                          icon: const Icon(Icons.chat_outlined,
                                              size: 16),
                                          label: const Text('Share WhatsApp'),
                                          onPressed: () async {
                                            Navigator.pop(ctx);
                                            final shopName =
                                                ShopCustomizationService
                                                    .instance.shopName;
                                            final msg =
                                                '🙏 *Payment Confirmation - $shopName*\nCustomer: *${widget.customerName}*\nAmount Received: *${currency.format(amount)}*\nMode: *$pMode*\nDate: *$dateStr*${pNotes.isNotEmpty ? "\nNote: $pNotes" : ""}\nThank you! - *$shopName*';
                                            await _sendWhatsAppMessage(msg);
                                          },
                                        ),
                                      ],
                                    ),
                                  );
                                }
                              },
                              child: Padding(
                                padding: const EdgeInsets.all(12),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        Expanded(
                                          child: Row(
                                            children: [
                                              Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                        horizontal: 8,
                                                        vertical: 3),
                                                decoration: BoxDecoration(
                                                  color: isDebit
                                                      ? const Color(0xFFFFE4E6)
                                                      : const Color(0xFFD1FAE5),
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
                                                        ? const Color(0xFFBE123C)
                                                        : const Color(0xFF065F46),
                                                  ),
                                                ),
                                              ),
                                              const SizedBox(width: 8),
                                              Expanded(
                                                child: Row(
                                                  children: [
                                                    Flexible(
                                                      child: Text(
                                                        title,
                                                        maxLines: 1,
                                                        overflow:
                                                            TextOverflow.ellipsis,
                                                        style: const TextStyle(
                                                          fontWeight:
                                                              FontWeight.bold,
                                                          fontSize: 13,
                                                        ),
                                                      ),
                                                    ),
                                                    if (orderId != null &&
                                                        isDebit &&
                                                        !subtitle.contains('Manual Udhaar')) ...[
                                                      const SizedBox(width: 6),
                                                      Container(
                                                        padding: const EdgeInsets.symmetric(
                                                            horizontal: 5, vertical: 1.5),
                                                        decoration: BoxDecoration(
                                                          color: Colors.grey.shade100,
                                                          borderRadius: BorderRadius.circular(4),
                                                          border: Border.all(color: Colors.grey.shade300),
                                                        ),
                                                        child: Text(
                                                          '#ORD-${(displayOrderNum ?? orderId).toString().padLeft(4, "0")}',
                                                          style: TextStyle(
                                                            fontSize: 9.5,
                                                            color: Colors.grey.shade700,
                                                            fontWeight: FontWeight.w600,
                                                          ),
                                                        ),
                                                      ),
                                                    ],
                                                    if (modeLabel.isNotEmpty &&
                                                        !isDebit) ...[
                                                      const SizedBox(width: 6),
                                                      Container(
                                                        padding:
                                                            const EdgeInsets
                                                                .symmetric(
                                                                horizontal: 6,
                                                                vertical: 2),
                                                        decoration:
                                                            BoxDecoration(
                                                          color: Colors
                                                              .teal.shade50,
                                                          borderRadius:
                                                              BorderRadius
                                                                  .circular(4),
                                                          border: Border.all(
                                                              color: Colors.teal
                                                                  .shade200,
                                                              width: 0.8),
                                                        ),
                                                        child: Text(
                                                          modeLabel,
                                                          style: TextStyle(
                                                            fontSize: 9,
                                                            fontWeight:
                                                                FontWeight.w800,
                                                            color: Colors
                                                                .teal.shade800,
                                                          ),
                                                        ),
                                                      ),
                                                    ],
                                                  ],
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Text(
                                          (isDebit ? '+ ' : '- ') +
                                              currency.format(amount),
                                          style: TextStyle(
                                            fontWeight: FontWeight.w900,
                                            fontSize: 15,
                                            color: isDebit
                                                ? const Color(0xFFBE123C)
                                                : const Color(0xFF059669),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      subtitle,
                                      style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w500,
                                          color: Colors.grey.shade800),
                                    ),
                                    const SizedBox(height: 6),
                                    Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        Text(
                                          '📅 $dateStr',
                                          style: TextStyle(
                                              fontSize: 11,
                                              color: Colors.grey.shade600),
                                        ),
                                        Row(
                                          children: [
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
                                            if (isDebit &&
                                                orderId != null &&
                                                !subtitle
                                                    .contains('Manual Udhaar')) ...[
                                              const SizedBox(width: 6),
                                              Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                        horizontal: 6,
                                                        vertical: 2),
                                                decoration: BoxDecoration(
                                                  color: Colors.teal.shade50,
                                                  borderRadius:
                                                      BorderRadius.circular(4),
                                                ),
                                                child: const Text(
                                                  'View Bill ➔',
                                                  style: TextStyle(
                                                    fontSize: 10,
                                                    fontWeight: FontWeight.bold,
                                                    color: Color(0xFF0F766E),
                                                  ),
                                                ),
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
