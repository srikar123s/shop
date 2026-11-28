import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:local_auth/local_auth.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shop/l10n/app_localizations.dart';
import 'package:shop/models/delivery_partner.dart';
import 'package:shop/repositories/delivery_repository.dart';
import 'package:shop/services/shop_sync_service.dart';
import 'package:shop/services/voice_search_service.dart';

class DeliveryPartnerPassbookScreen extends StatefulWidget {
  const DeliveryPartnerPassbookScreen({
    super.key,
    required this.partnerId,
    DeliveryRepository? repository,
  }) : _repository = repository;

  final int partnerId;
  final DeliveryRepository? _repository;

  @override
  State<DeliveryPartnerPassbookScreen> createState() =>
      _DeliveryPartnerPassbookScreenState();
}

class _DeliveryPartnerPassbookScreenState
    extends State<DeliveryPartnerPassbookScreen> {
  late final DeliveryRepository _repo;
  final NumberFormat _currency = NumberFormat('#,##0.##');
  final DateFormat _dateFmt = DateFormat('dd MMM yyyy, hh:mm a');

  DeliveryPartner? _partner;
  List<DeliveryTransaction> _transactions = [];
  List<String> _locations = [];
  bool _loading = true;
  bool _isLocked = false;
  final LocalAuthentication _localAuth = LocalAuthentication();

  @override
  void initState() {
    super.initState();
    _repo = widget._repository ?? DeliveryRepository();
    ShopSyncService.instance.addListener(_onSyncUpdate);
    _loadData();
  }

  @override
  void dispose() {
    ShopSyncService.instance.removeListener(_onSyncUpdate);
    super.dispose();
  }

  void _onSyncUpdate() {
    if (mounted) _loadData();
  }

  Future<void> _enableLock() async {
    try {
      final supported = await _localAuth.isDeviceSupported();
      if (!supported) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Please enable a Phone Screen Lock (PIN, Pattern, or Fingerprint) in Settings first.',
            ),
            backgroundColor: Colors.orange,
          ),
        );
        return;
      }
    } catch (_) {}
    if (!mounted) return;
    setState(() => _isLocked = true);
  }

  Future<void> _unlockView() async {
    try {
      final ok = await _localAuth.authenticate(
        localizedReason: 'Verify phone screen lock to unlock',
        options: const AuthenticationOptions(
          biometricOnly: false,
          stickyAuth: true,
        ),
      );
      if (ok && mounted) {
        setState(() => _isLocked = false);
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not verify screen lock: $e')),
      );
    }
  }

  Future<void> _sharePartnerSummary() async {
    final p = _partner;
    if (p == null) return;
    final totalBoxes =
        _transactions.fold<int>(0, (sum, tx) => sum + tx.totalBoxes);
    final statusLine = p.advanceBalance > 0
        ? 'Advance Balance: ₹${_currency.format(p.advanceBalance)}'
        : p.payableBalance > 0
            ? 'Payable Balance: ₹${_currency.format(p.payableBalance)}'
            : 'Settled (₹0)';
    final text = StringBuffer()
      ..writeln('🚚 *${p.name}* — Delivery Summary')
      ..writeln('Total Boxes: $totalBoxes')
      ..writeln('Total Earned: ₹${_currency.format(p.totalEarned)}')
      ..writeln('Total Paid: ₹${_currency.format(p.totalPaid)}')
      ..writeln(statusLine);
    await Share.share(text.toString());
  }

  Future<void> _loadData() async {
    setState(() => _loading = true);
    final results = await Future.wait([
      _repo.getPartnerById(widget.partnerId),
      _repo.getTransactionsForPartner(widget.partnerId),
      _repo.getLocations(),
    ]);
    if (!mounted) return;
    setState(() {
      _partner = results[0] as DeliveryPartner?;
      _transactions = results[1] as List<DeliveryTransaction>;
      _locations = results[2] as List<String>;
      _loading = false;
    });
  }

  void _showAddOptionsSheet() {
    showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Add Delivery / Payment',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 12),
              ListTile(
                leading: CircleAvatar(
                  backgroundColor: Colors.indigo.shade50,
                  child: Icon(Icons.inventory_2_outlined,
                      color: Colors.indigo.shade700),
                ),
                title: const Text('Pay Per Box',
                    style: TextStyle(fontWeight: FontWeight.w700)),
                subtitle: const Text(
                    'Location, total boxes, ₹30 / custom rate breakdown & note'),
                onTap: () {
                  Navigator.pop(ctx);
                  _openPerBoxSheet();
                },
              ),
              ListTile(
                leading: CircleAvatar(
                  backgroundColor: Colors.amber.shade50,
                  child:
                      Icon(Icons.route_outlined, color: Colors.amber.shade800),
                ),
                title: const Text('Pay for Line',
                    style: TextStyle(fontWeight: FontWeight.w700)),
                subtitle:
                    const Text('Full route/line fare (₹700–₹1500) & details'),
                onTap: () {
                  Navigator.pop(ctx);
                  _openLineSheet();
                },
              ),
              ListTile(
                leading: CircleAvatar(
                  backgroundColor: Colors.teal.shade50,
                  child: Icon(Icons.payments_outlined,
                      color: Colors.teal.shade700),
                ),
                title: const Text('Give Advance / Pay Cash',
                    style: TextStyle(fontWeight: FontWeight.w700)),
                subtitle: const Text(
                    'Record ₹3k–₹5k advance or weekend/on-demand payout'),
                onTap: () {
                  Navigator.pop(ctx);
                  _openPayoutSheet();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<String?> _promptNewLocation(BuildContext parentContext) async {
    final ctrl = TextEditingController();
    final String? added;
    try {
      added = await showDialog<String>(
        context: parentContext,
        builder: (ctx) => AlertDialog(
          title: const Text('Add New Location'),
          content: TextField(
            controller: ctrl,
            autofocus: true,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              labelText: 'Location / Area Name',
              hintText: 'e.g. Kukatpally',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                final val = ctrl.text.trim();
                if (val.isNotEmpty) Navigator.pop(ctx, val);
              },
              child: const Text('Add'),
            ),
          ],
        ),
      );
    } finally {
      ctrl.dispose();
    }
    if (added != null && added.trim().isNotEmpty) {
      await _repo.addLocation(added);
      final updated = await _repo.getLocations();
      if (mounted) {
        setState(() => _locations = updated);
      }
      return added.trim();
    }
    return null;
  }

  Future<void> _openPerBoxSheet() async {
    final partner = _partner;
    if (partner == null) return;

    String? selectedLocation;
    final totalBoxesCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    final List<_RateRowControllers> rateRows = [
      _RateRowControllers(boxes: '', rate: '30'),
    ];
    final cutCtrl = TextEditingController();
    final paidCtrl = TextEditingController();

    String settlementMode = partner.advanceBalance > 0
        ? 'cut_full' // cut_full, cut_partial, pay_full
        : 'pay_full'; // pay_full, pay_partial, pay_later
    String paymentMode = 'cash';
    bool manualTotalEdited = false;

    try {
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        builder: (ctx) => StatefulBuilder(
          builder: (ctx, setSheetState) {
            int tierBoxSum = 0;
            double totalEarned = 0.0;
            for (final row in rateRows) {
              final b = int.tryParse(row.boxesCtrl.text.trim()) ?? 0;
              final r = double.tryParse(row.rateCtrl.text.trim()) ?? 0.0;
              tierBoxSum += b;
              totalEarned += b * r;
            }

            if (!manualTotalEdited) {
              totalBoxesCtrl.text = tierBoxSum > 0 ? tierBoxSum.toString() : '';
            }
            final enteredTotalBoxes =
                int.tryParse(totalBoxesCtrl.text.trim()) ?? tierBoxSum;

            final settlement = DeliverySettlement.calculate(
              totalEarned: totalEarned,
              advanceBalance: partner.advanceBalance,
              settlementMode: settlementMode,
              enteredCut: double.tryParse(cutCtrl.text.trim()) ?? 0.0,
              enteredPaid: double.tryParse(paidCtrl.text.trim()) ?? 0.0,
            );
            final cutAmt = settlement.cutAmount;
            final payAmt = settlement.paidAmount;

          return Padding(
            padding: EdgeInsets.fromLTRB(
              16,
              16,
              16,
              MediaQuery.of(ctx).viewInsets.bottom + 20,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Pay Per Box',
                        style: TextStyle(
                            fontSize: 18, fontWeight: FontWeight.w800),
                      ),
                      Text(
                        'Earned: ₹${_currency.format(totalEarned)}',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: Colors.indigo.shade700,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),

                  // Location Picker + Add New Location
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          key: ValueKey('pb_$selectedLocation'),
                          initialValue: _locations.contains(selectedLocation)
                              ? selectedLocation
                              : null,
                          decoration: const InputDecoration(
                            labelText: 'Location',
                            prefixIcon: Icon(Icons.location_on_outlined),
                            border: OutlineInputBorder(),
                          ),
                          hint: const Text('Select location'),
                          items: _locations
                              .map((loc) => DropdownMenuItem(
                                    value: loc,
                                    child: Text(loc),
                                  ))
                              .toList(),
                          onChanged: (val) =>
                              setSheetState(() => selectedLocation = val),
                        ),
                      ),
                      const SizedBox(width: 8),
                      OutlinedButton.icon(
                        onPressed: () async {
                          final added = await _promptNewLocation(ctx);
                          if (added != null) {
                            setSheetState(() => selectedLocation = added);
                          }
                        },
                        icon: const Icon(Icons.add_location_alt_outlined,
                            size: 18),
                        label: const Text('New'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // Total Boxes
                  TextField(
                    controller: totalBoxesCtrl,
                    keyboardType: TextInputType.number,
                    onChanged: (_) =>
                        setSheetState(() => manualTotalEdited = true),
                    decoration: InputDecoration(
                      labelText: 'Total No. of Boxes',
                      hintText: 'e.g. 15',
                      prefixIcon: const Icon(Icons.inventory_2_outlined),
                      border: const OutlineInputBorder(),
                      helperText: (manualTotalEdited &&
                              enteredTotalBoxes != tierBoxSum &&
                              tierBoxSum > 0)
                          ? 'Rate breakdown sums to $tierBoxSum boxes (Total entered: $enteredTotalBoxes)'
                          : null,
                    ),
                  ),
                  const SizedBox(height: 14),

                  // Box Rate Breakdown (₹30 + other ₹X)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Boxes by Rate (₹30 / Other ₹X)',
                        style: TextStyle(
                            fontWeight: FontWeight.w700, fontSize: 13),
                      ),
                      TextButton.icon(
                        onPressed: () => setSheetState(() {
                          rateRows.add(
                            _RateRowControllers(boxes: '', rate: '40'),
                          );
                        }),
                        icon: const Icon(Icons.add, size: 18),
                        label: const Text('Add Rate'),
                      ),
                    ],
                  ),
                  ...List.generate(rateRows.length, (idx) {
                    final row = rateRows[idx];
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: row.boxesCtrl,
                              keyboardType: TextInputType.number,
                              onChanged: (_) => setSheetState(() {}),
                              decoration: const InputDecoration(
                                labelText: 'Boxes',
                                hintText: '0',
                                border: OutlineInputBorder(),
                                isDense: true,
                              ),
                            ),
                          ),
                          const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 8),
                            child: Text('×',
                                style: TextStyle(
                                    fontSize: 16, fontWeight: FontWeight.bold)),
                          ),
                          Expanded(
                            child: TextField(
                              controller: row.rateCtrl,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                      decimal: true),
                              onChanged: (_) => setSheetState(() {}),
                              decoration: const InputDecoration(
                                labelText: 'Rate (₹)',
                                prefixText: '₹',
                                border: OutlineInputBorder(),
                                isDense: true,
                              ),
                            ),
                          ),
                          if (rateRows.length > 1)
                            IconButton(
                              icon: const Icon(Icons.remove_circle_outline,
                                  color: Colors.redAccent),
                              onPressed: () => setSheetState(() {
                                rateRows.removeAt(idx).dispose();
                              }),
                            ),
                        ],
                      ),
                    );
                  }),
                  const SizedBox(height: 8),

                  // Description (Write or Record by Voice)
                  TextField(
                    controller: descCtrl,
                    maxLines: 2,
                    decoration: InputDecoration(
                      labelText: 'Description (Optional)',
                      hintText:
                          'e.g. 6 boxes for Ravi Kirana, 4 for Sri Sai...',
                      border: const OutlineInputBorder(),
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.mic_none_rounded),
                        tooltip: 'Record description',
                        onPressed: () async {
                          final spoken =
                              await VoiceSearchService.instance.recordSpeech(
                            ctx,
                            title: 'Record Delivery Note',
                            hint: 'Say customer names and box counts...',
                          );
                          if (spoken != null && spoken.trim().isNotEmpty) {
                            setSheetState(() {
                              descCtrl.text = descCtrl.text.trim().isEmpty
                                  ? spoken.trim()
                                  : '${descCtrl.text.trim()}, ${spoken.trim()}';
                            });
                          }
                        },
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),

                  // Settlement Today
                  _SettlementSection(
                    partner: partner,
                    totalEarned: totalEarned,
                    settlementMode: settlementMode,
                    paymentMode: paymentMode,
                    cutCtrl: cutCtrl,
                    paidCtrl: paidCtrl,
                    currency: _currency,
                    onModeChanged: (m) => setSheetState(() {
                      settlementMode = m;
                    }),
                    onPaymentMethodChanged: (pm) =>
                        setSheetState(() => paymentMode = pm),
                    onAmountChanged: () => setSheetState(() {}),
                  ),
                  const SizedBox(height: 16),

                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: totalEarned <= 0
                          ? null
                          : () async {
                              final tiers = rateRows
                                  .map((r) => BoxRateTier(
                                        boxes:
                                            int.tryParse(r.boxesCtrl.text) ?? 0,
                                        rate: double.tryParse(r.rateCtrl.text) ??
                                            0.0,
                                      ))
                                  .where((t) => t.boxes > 0 && t.rate > 0)
                                  .toList();

                              final tx = DeliveryTransaction(
                                partnerId: widget.partnerId,
                                txType: DeliveryTxType.perBox,
                                location: selectedLocation,
                                totalBoxes: enteredTotalBoxes,
                                rateTiers: tiers,
                                earnedAmount: totalEarned,
                                paidAmount: payAmt,
                                cutAmount: cutAmt,
                                paymentMode: payAmt > 0 ? paymentMode : 'none',
                                description: descCtrl.text.trim().isEmpty
                                    ? null
                                    : descCtrl.text.trim(),
                                createdAt: DateTime.now(),
                              );
                              await _repo.addTransaction(tx);
                              if (ctx.mounted) Navigator.pop(ctx);
                              await _loadData();
                            },
                      child: const Text('Save Per-Box Entry'),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
    } finally {
      totalBoxesCtrl.dispose();
      descCtrl.dispose();
      cutCtrl.dispose();
      paidCtrl.dispose();
      for (final row in rateRows) {
        row.dispose();
      }
    }
  }

  Future<void> _openLineSheet() async {
    final partner = _partner;
    if (partner == null) return;

    String? selectedLocation;
    final fareCtrl = TextEditingController(text: '1000');
    final boxesCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    final cutCtrl = TextEditingController();
    final paidCtrl = TextEditingController();

    String settlementMode =
        partner.advanceBalance > 0 ? 'cut_full' : 'pay_full';
    String paymentMode = 'cash';

    try {
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        builder: (ctx) => StatefulBuilder(
          builder: (ctx, setSheetState) {
            final totalEarned = double.tryParse(fareCtrl.text.trim()) ?? 0.0;
            final settlement = DeliverySettlement.calculate(
              totalEarned: totalEarned,
              advanceBalance: partner.advanceBalance,
              settlementMode: settlementMode,
              enteredCut: double.tryParse(cutCtrl.text.trim()) ?? 0.0,
              enteredPaid: double.tryParse(paidCtrl.text.trim()) ?? 0.0,
            );
            final cutAmt = settlement.cutAmount;
            final payAmt = settlement.paidAmount;

          return Padding(
            padding: EdgeInsets.fromLTRB(
              16,
              16,
              16,
              MediaQuery.of(ctx).viewInsets.bottom + 20,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Pay for Line',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          key: ValueKey('line_$selectedLocation'),
                          initialValue: _locations.contains(selectedLocation)
                              ? selectedLocation
                              : null,
                          decoration: const InputDecoration(
                            labelText: 'Line / Route Location',
                            prefixIcon: Icon(Icons.route_outlined),
                            border: OutlineInputBorder(),
                          ),
                          hint: const Text('Select route/location'),
                          items: _locations
                              .map((loc) => DropdownMenuItem(
                                    value: loc,
                                    child: Text(loc),
                                  ))
                              .toList(),
                          onChanged: (val) =>
                              setSheetState(() => selectedLocation = val),
                        ),
                      ),
                      const SizedBox(width: 8),
                      OutlinedButton.icon(
                        onPressed: () async {
                          final added = await _promptNewLocation(ctx);
                          if (added != null) {
                            setSheetState(() => selectedLocation = added);
                          }
                        },
                        icon: const Icon(Icons.add_location_alt_outlined,
                            size: 18),
                        label: const Text('New'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: fareCtrl,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    onChanged: (_) => setSheetState(() {}),
                    decoration: const InputDecoration(
                      labelText: 'Line Fare (₹700 – ₹1500)',
                      prefixText: '₹',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: [700, 800, 1000, 1200, 1500].map((amt) {
                      return ActionChip(
                        label: Text('₹$amt'),
                        onPressed: () => setSheetState(
                          () => fareCtrl.text = amt.toString(),
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: boxesCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Total Boxes (optional)',
                      prefixIcon: Icon(Icons.inventory_2_outlined),
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: descCtrl,
                    maxLines: 2,
                    decoration: InputDecoration(
                      labelText: 'Description (Optional)',
                      hintText: 'Shops covered, who accompanied, etc.',
                      border: const OutlineInputBorder(),
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.mic_none_rounded),
                        tooltip: 'Record description',
                        onPressed: () async {
                          final spoken =
                              await VoiceSearchService.instance.recordSpeech(
                            ctx,
                            title: 'Record Line Note',
                            hint: 'Say shops covered or notes...',
                          );
                          if (spoken != null && spoken.trim().isNotEmpty) {
                            setSheetState(() {
                              descCtrl.text = descCtrl.text.trim().isEmpty
                                  ? spoken.trim()
                                  : '${descCtrl.text.trim()}, ${spoken.trim()}';
                            });
                          }
                        },
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  _SettlementSection(
                    partner: partner,
                    totalEarned: totalEarned,
                    settlementMode: settlementMode,
                    paymentMode: paymentMode,
                    cutCtrl: cutCtrl,
                    paidCtrl: paidCtrl,
                    currency: _currency,
                    onModeChanged: (m) =>
                        setSheetState(() => settlementMode = m),
                    onPaymentMethodChanged: (pm) =>
                        setSheetState(() => paymentMode = pm),
                    onAmountChanged: () => setSheetState(() {}),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: totalEarned <= 0
                          ? null
                          : () async {
                              final tx = DeliveryTransaction(
                                partnerId: widget.partnerId,
                                txType: DeliveryTxType.line,
                                location: selectedLocation,
                                totalBoxes:
                                    int.tryParse(boxesCtrl.text.trim()) ?? 0,
                                earnedAmount: totalEarned,
                                paidAmount: payAmt,
                                cutAmount: cutAmt,
                                paymentMode: payAmt > 0 ? paymentMode : 'none',
                                description: descCtrl.text.trim().isEmpty
                                    ? null
                                    : descCtrl.text.trim(),
                                createdAt: DateTime.now(),
                              );
                              await _repo.addTransaction(tx);
                              if (ctx.mounted) Navigator.pop(ctx);
                              await _loadData();
                            },
                      child: const Text('Save Line Entry'),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
    } finally {
      fareCtrl.dispose();
      boxesCtrl.dispose();
      descCtrl.dispose();
      cutCtrl.dispose();
      paidCtrl.dispose();
    }
  }

  Future<void> _openPayoutSheet() async {
    final amountCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    String paymentMode = 'cash';

    try {
      await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) {
          final amt = double.tryParse(amountCtrl.text.trim()) ?? 0.0;
          return Padding(
            padding: EdgeInsets.fromLTRB(
              16,
              16,
              16,
              MediaQuery.of(ctx).viewInsets.bottom + 20,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Give Advance / Pay Cash',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: amountCtrl,
                  autofocus: true,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  onChanged: (_) => setSheetState(() {}),
                  decoration: const InputDecoration(
                    labelText: 'Amount Paid',
                    prefixText: '₹',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: [500, 1000, 3000, 5000].map((v) {
                    return ActionChip(
                      label: Text('₹$v'),
                      onPressed: () =>
                          setSheetState(() => amountCtrl.text = v.toString()),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 12),
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'cash', label: Text('Cash')),
                    ButtonSegment(value: 'upi', label: Text('UPI')),
                  ],
                  selected: {paymentMode},
                  onSelectionChanged: (s) =>
                      setSheetState(() => paymentMode = s.first),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: descCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Note (e.g. Advance, Weekend settlement)',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: amt <= 0
                        ? null
                        : () async {
                            await _repo.addTransaction(
                              DeliveryTransaction(
                                partnerId: widget.partnerId,
                                txType: DeliveryTxType.payout,
                                earnedAmount: 0.0,
                                paidAmount: amt,
                                paymentMode: paymentMode,
                                description: descCtrl.text.trim().isEmpty
                                    ? 'Advance / Payout'
                                    : descCtrl.text.trim(),
                                createdAt: DateTime.now(),
                              ),
                            );
                            if (ctx.mounted) Navigator.pop(ctx);
                            await _loadData();
                          },
                    child: const Text('Save Payment'),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
    } finally {
      amountCtrl.dispose();
      descCtrl.dispose();
    }
  }

  Future<void> _confirmDeleteTx(DeliveryTransaction tx) async {
    if (tx.id == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Transaction?'),
        content: const Text('This will update the driver balance.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await _repo.deleteTransaction(tx.id!);
      await _loadData();
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context);
    final partner = _partner;
    return PopScope(
      canPop: !_isLocked,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _isLocked && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Locked! Tap Unlock at the top to go back.'),
              duration: Duration(seconds: 2),
            ),
          );
        }
      },
      child: Scaffold(
        backgroundColor: const Color(0xFFF8FAFC),
        appBar: AppBar(
          automaticallyImplyLeading: !_isLocked,
          title: Text(
            partner?.name ?? s.t('driverPassbook'),
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
          actions: [
            if (_isLocked)
              TextButton.icon(
                style: TextButton.styleFrom(foregroundColor: Colors.amberAccent),
                icon: const Icon(Icons.lock_rounded, size: 18),
                label: Text(
                  s.t('unlockScreen'),
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                onPressed: _unlockView,
              )
            else ...[
              IconButton(
                tooltip: s.t('lockScreen'),
                icon: const Icon(Icons.lock_open_rounded),
                onPressed: _enableLock,
              ),
              IconButton(
                tooltip: s.t('shareSummary'),
                icon: const Icon(Icons.share_outlined),
                onPressed: _sharePartnerSummary,
              ),
            ],
          ],
        ),
        floatingActionButton: _isLocked
            ? null
            : FloatingActionButton.extended(
                onPressed: _showAddOptionsSheet,
                icon: const Icon(Icons.add),
                label: Text(s.t('add')),
              ),
        body: _loading || partner == null
            ? const Center(child: CircularProgressIndicator())
            : RefreshIndicator(
                onRefresh: _loadData,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
                  children: [
                    if (_isLocked)
                      Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 8),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFEF3C7),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.lock_outline,
                                size: 16, color: Color(0xFF92400E)),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                '${s.t('driverViewLocked')} • ${partner.name}',
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFF92400E),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    _BalanceHeaderCard(partner: partner, currency: _currency),
                    const SizedBox(height: 12),

                    // Quick Add Row
                    if (!_isLocked) ...[
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: _openPerBoxSheet,
                              icon: const Icon(Icons.inventory_2_outlined,
                                  size: 18),
                              label: Text(s.t('perBox')),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: _openLineSheet,
                              icon: const Icon(Icons.route_outlined, size: 18),
                              label: Text(s.t('line')),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: _openPayoutSheet,
                              icon: const Icon(Icons.payments_outlined,
                                  size: 18),
                              label: Text(s.t('advance')),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                    ],

                    Text(
                      s.t('transactions'),
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 8),

                    if (_transactions.isEmpty)
                      Container(
                        padding: const EdgeInsets.all(28),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: Colors.grey.shade200),
                        ),
                        child: const Center(
                          child: Text(
                            'No transactions yet. Tap "+ Add" to record a Per-Box, Line, or Advance entry.',
                            textAlign: TextAlign.center,
                          ),
                        ),
                      )
                    else
                      ..._transactions.map((tx) => _TransactionCard(
                            tx: tx,
                            currency: _currency,
                            dateFmt: _dateFmt,
                            onDelete:
                                _isLocked ? null : () => _confirmDeleteTx(tx),
                          )),
                  ],
                ),
              ),
      ),
    );
  }
}

class _RateRowControllers {
  _RateRowControllers({required String boxes, required String rate})
      : boxesCtrl = TextEditingController(text: boxes),
        rateCtrl = TextEditingController(text: rate);

  final TextEditingController boxesCtrl;
  final TextEditingController rateCtrl;

  void dispose() {
    boxesCtrl.dispose();
    rateCtrl.dispose();
  }
}

class _SettlementSection extends StatelessWidget {
  const _SettlementSection({
    required this.partner,
    required this.totalEarned,
    required this.settlementMode,
    required this.paymentMode,
    required this.cutCtrl,
    required this.paidCtrl,
    required this.currency,
    required this.onModeChanged,
    required this.onPaymentMethodChanged,
    required this.onAmountChanged,
  });

  final DeliveryPartner partner;
  final double totalEarned;
  final String settlementMode;
  final String paymentMode;
  final TextEditingController cutCtrl;
  final TextEditingController paidCtrl;
  final NumberFormat currency;
  final ValueChanged<String> onModeChanged;
  final ValueChanged<String> onPaymentMethodChanged;
  final VoidCallback onAmountChanged;

  @override
  Widget build(BuildContext context) {
    final hasAdvance = partner.advanceBalance > 0;
    final cutAmt = double.tryParse(cutCtrl.text.trim()) ?? 0.0;
    final restToPay = (totalEarned - cutAmt).clamp(0.0, totalEarned);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            hasAdvance
                ? 'Settlement (Advance Available: ₹${currency.format(partner.advanceBalance)})'
                : 'Settlement Today',
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: hasAdvance
                ? [
                    ChoiceChip(
                      label: const Text('Cut Full (Pay ₹0)'),
                      selected: settlementMode == 'cut_full',
                      onSelected: (_) => onModeChanged('cut_full'),
                    ),
                    ChoiceChip(
                      label: const Text('Cut ₹X & Pay Rest'),
                      selected: settlementMode == 'cut_partial',
                      onSelected: (_) => onModeChanged('cut_partial'),
                    ),
                    ChoiceChip(
                      label: const Text('Pay Full Today'),
                      selected: settlementMode == 'pay_full',
                      onSelected: (_) => onModeChanged('pay_full'),
                    ),
                  ]
                : [
                    ChoiceChip(
                      label: const Text('Pay Full Now'),
                      selected: settlementMode == 'pay_full',
                      onSelected: (_) => onModeChanged('pay_full'),
                    ),
                    ChoiceChip(
                      label: const Text('Pay Partial'),
                      selected: settlementMode == 'pay_partial',
                      onSelected: (_) => onModeChanged('pay_partial'),
                    ),
                    ChoiceChip(
                      label: const Text('Pay Later'),
                      selected: settlementMode == 'pay_later',
                      onSelected: (_) => onModeChanged('pay_later'),
                    ),
                  ],
          ),
          if (hasAdvance && settlementMode == 'cut_partial') ...[
            const SizedBox(height: 10),
            TextField(
              controller: cutCtrl,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              onChanged: (_) => onAmountChanged(),
              decoration: InputDecoration(
                labelText: 'Cut from Advance (₹)',
                prefixText: '₹',
                border: const OutlineInputBorder(),
                isDense: true,
                helperText: 'Pay Today: ₹${currency.format(restToPay)}',
              ),
            ),
          ],
          if (!hasAdvance && settlementMode == 'pay_partial') ...[
            const SizedBox(height: 10),
            TextField(
              controller: paidCtrl,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              onChanged: (_) => onAmountChanged(),
              decoration: const InputDecoration(
                labelText: 'Paid Today (₹)',
                prefixText: '₹',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
          ],
          if ((hasAdvance && settlementMode != 'cut_full') ||
              (!hasAdvance && settlementMode != 'pay_later')) ...[
            const SizedBox(height: 10),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'cash', label: Text('Cash')),
                ButtonSegment(value: 'upi', label: Text('UPI')),
              ],
              selected: {paymentMode},
              onSelectionChanged: (s) => onPaymentMethodChanged(s.first),
            ),
          ],
        ],
      ),
    );
  }
}

class _BalanceHeaderCard extends StatelessWidget {
  const _BalanceHeaderCard({required this.partner, required this.currency});

  final DeliveryPartner partner;
  final NumberFormat currency;

  @override
  Widget build(BuildContext context) {
    final bool hasAdvance = partner.advanceBalance > 0;
    final bool hasPayable = partner.payableBalance > 0;
    final Color accent = hasAdvance
        ? const Color(0xFF0D9488)
        : hasPayable
            ? const Color(0xFFEA580C)
            : Colors.indigo;
    final String statusLabel = hasAdvance
        ? 'Advance with Driver'
        : hasPayable
            ? 'Payable to Driver'
            : 'Settled';
    final double displayAmt =
        hasAdvance ? partner.advanceBalance : partner.payableBalance;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: accent.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            statusLabel,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: accent,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '₹${currency.format(displayAmt)}',
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w900,
              color: accent,
            ),
          ),
          const Divider(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Total Earned: ₹${currency.format(partner.totalEarned)}',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
              ),
              Text(
                'Total Paid: ₹${currency.format(partner.totalPaid)}',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _TransactionCard extends StatelessWidget {
  const _TransactionCard({
    required this.tx,
    required this.currency,
    required this.dateFmt,
    this.onDelete,
  });

  final DeliveryTransaction tx;
  final NumberFormat currency;
  final DateFormat dateFmt;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final String typeLabel;
    final Color typeColor;
    switch (tx.txType) {
      case DeliveryTxType.perBox:
        typeLabel = 'PER BOX';
        typeColor = Colors.indigo;
        break;
      case DeliveryTxType.line:
        typeLabel = 'LINE';
        typeColor = Colors.amber.shade800;
        break;
      case DeliveryTxType.payout:
        typeLabel = 'ADVANCE / PAYOUT';
        typeColor = Colors.teal;
        break;
    }

    final tierSummary = tx.rateTiers
        .map((t) => '${t.boxes}×₹${currency.format(t.rate)}')
        .join(', ');

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: typeColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    typeLabel,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      color: typeColor,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                if (tx.location != null && tx.location!.isNotEmpty)
                  Expanded(
                    child: Text(
                      tx.location!,
                      style: const TextStyle(
                          fontWeight: FontWeight.w700, fontSize: 13),
                      overflow: TextOverflow.ellipsis,
                    ),
                  )
                else
                  const Spacer(),
                if (onDelete != null)
                  IconButton(
                    icon: const Icon(Icons.delete_outline, size: 18),
                    color: Colors.grey.shade500,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    onPressed: onDelete,
                  ),
              ],
            ),
            const SizedBox(height: 6),
            if (tx.totalBoxes > 0 || tierSummary.isNotEmpty)
              Text(
                [
                  if (tx.totalBoxes > 0) '${tx.totalBoxes} boxes',
                  if (tierSummary.isNotEmpty) '($tierSummary)',
                ].join(' '),
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey.shade800,
                ),
              ),
            if (tx.description != null && tx.description!.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                tx.description!,
                style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
              ),
            ],
            const SizedBox(height: 8),
            Wrap(
              spacing: 12,
              runSpacing: 4,
              children: [
                if (tx.earnedAmount > 0)
                  Text(
                    'Earned: ₹${currency.format(tx.earnedAmount)}',
                    style: const TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 13),
                  ),
                if (tx.cutAmount > 0)
                  Text(
                    'Cut from Adv: ₹${currency.format(tx.cutAmount)}',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                      color: Colors.orange.shade800,
                    ),
                  ),
                if (tx.paidAmount > 0)
                  Text(
                    'Paid: ₹${currency.format(tx.paidAmount)} (${tx.paymentMode.toUpperCase()})',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                      color: Colors.teal.shade700,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              dateFmt.format(tx.createdAt),
              style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
            ),
          ],
        ),
      ),
    );
  }
}
