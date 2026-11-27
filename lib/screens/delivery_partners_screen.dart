import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shop/l10n/app_localizations.dart';
import 'package:shop/models/delivery_partner.dart';
import 'package:shop/repositories/delivery_repository.dart';
import 'package:shop/screens/delivery_partner_passbook_screen.dart';
import 'package:shop/services/shop_sync_service.dart';
import 'package:url_launcher/url_launcher.dart';

class DeliveryPartnersScreen extends StatefulWidget {
  const DeliveryPartnersScreen({
    super.key,
    DeliveryRepository? repository,
  }) : _repository = repository;

  final DeliveryRepository? _repository;

  @override
  State<DeliveryPartnersScreen> createState() => _DeliveryPartnersScreenState();
}

class _DeliveryPartnersScreenState extends State<DeliveryPartnersScreen> {
  late final DeliveryRepository _repo;
  final TextEditingController _searchController = TextEditingController();
  final NumberFormat _currency = NumberFormat('#,##0.##');

  List<DeliveryPartner> _partners = [];
  List<DeliveryPartner> _filtered = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _repo = widget._repository ?? DeliveryRepository();
    ShopSyncService.instance.addListener(_onSyncUpdate);
    _loadPartners();
  }

  @override
  void dispose() {
    ShopSyncService.instance.removeListener(_onSyncUpdate);
    _searchController.dispose();
    super.dispose();
  }

  void _onSyncUpdate() {
    if (mounted) _loadPartners();
  }

  Future<void> _loadPartners() async {
    setState(() => _loading = true);
    final list = await _repo.getPartnersWithSummary();
    if (!mounted) return;
    setState(() {
      _partners = list;
      _applyFilter();
      _loading = false;
    });
  }

  void _applyFilter() {
    final q = _searchController.text.trim().toLowerCase();
    if (q.isEmpty) {
      _filtered = List.of(_partners);
    } else {
      _filtered = _partners.where((p) {
        return p.name.toLowerCase().contains(q) ||
            (p.phone?.toLowerCase().contains(q) ?? false) ||
            (p.vehicleInfo?.toLowerCase().contains(q) ?? false);
      }).toList();
    }
  }

  double get _totalPayable =>
      _partners.fold(0.0, (sum, p) => sum + p.payableBalance);

  double get _totalAdvance =>
      _partners.fold(0.0, (sum, p) => sum + p.advanceBalance);

  Future<void> _showPartnerDialog({DeliveryPartner? existing}) async {
    final nameCtrl = TextEditingController(text: existing?.name ?? '');
    final phoneCtrl = TextEditingController(text: existing?.phone ?? '');
    final vehicleCtrl = TextEditingController(
      text: existing?.vehicleInfo ?? 'Auto',
    );
    final notesCtrl = TextEditingController(text: existing?.notes ?? '');
    final formKey = GlobalKey<FormState>();

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          existing == null ? 'Add Delivery Partner' : 'Edit Delivery Partner',
        ),
        content: SingleChildScrollView(
          child: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: nameCtrl,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    labelText: 'Name *',
                    hintText: 'e.g. Raju Auto',
                    prefixIcon: Icon(Icons.person_outline),
                  ),
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'Enter a name' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: phoneCtrl,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(
                    labelText: 'Phone Number',
                    hintText: 'e.g. 9876543210',
                    prefixIcon: Icon(Icons.phone_outlined),
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: vehicleCtrl,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    labelText: 'Vehicle / Method',
                    hintText: 'e.g. Auto AP09 1234',
                    prefixIcon: Icon(Icons.local_shipping_outlined),
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: notesCtrl,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'Notes (optional)',
                    prefixIcon: Icon(Icons.notes_outlined),
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (formKey.currentState?.validate() ?? false) {
                Navigator.pop(ctx, true);
              }
            },
            child: Text(existing == null ? 'Add' : 'Save'),
          ),
        ],
      ),
    );

    if (saved == true) {
      if (existing == null) {
        await _repo.addPartner(
          name: nameCtrl.text,
          phone: phoneCtrl.text,
          vehicleInfo: vehicleCtrl.text,
          notes: notesCtrl.text,
        );
      } else {
        await _repo.updatePartner(
          existing.copyWith(
            name: nameCtrl.text,
            phone: phoneCtrl.text,
            vehicleInfo: vehicleCtrl.text,
            notes: notesCtrl.text,
          ),
        );
      }
      await _loadPartners();
    }
  }

  Future<void> _callPartner(String phone) async {
    final uri = Uri(scheme: 'tel', path: phone.trim());
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context);
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: Text(
          s.t('deliveryPartners'),
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.person_add_alt_1_rounded),
            tooltip: s.t('addPartner'),
            onPressed: () => _showPartnerDialog(),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showPartnerDialog(),
        icon: const Icon(Icons.person_add_rounded),
        label: Text(s.t('addPartner')),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadPartners,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
                children: [
                  // Summary Banner
                  Row(
                    children: [
                      Expanded(
                        child: _SummaryCard(
                          title: s.t('toPayDrivers'),
                          amount: '₹${_currency.format(_totalPayable)}',
                          color: const Color(0xFFEA580C),
                          bgColor: const Color(0xFFFFF7ED),
                          icon: Icons.account_balance_wallet_outlined,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _SummaryCard(
                          title: s.t('advanceGiven'),
                          amount: '₹${_currency.format(_totalAdvance)}',
                          color: const Color(0xFF0D9488),
                          bgColor: const Color(0xFFF0FDFA),
                          icon: Icons.savings_outlined,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),

                  // Search bar
                  TextField(
                    controller: _searchController,
                    onChanged: (_) => setState(_applyFilter),
                    decoration: InputDecoration(
                      hintText: s.t('searchPartnerHint'),
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: _searchController.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear),
                              onPressed: () {
                                _searchController.clear();
                                setState(_applyFilter);
                              },
                            )
                          : null,
                      filled: true,
                      fillColor: Colors.white,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide(color: Colors.grey.shade300),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide(color: Colors.grey.shade300),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  if (_filtered.isEmpty)
                    Container(
                      padding: const EdgeInsets.all(32),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.grey.shade200),
                      ),
                      child: Column(
                        children: [
                          Icon(
                            Icons.local_shipping_outlined,
                            size: 48,
                            color: Colors.grey.shade400,
                          ),
                          const SizedBox(height: 12),
                          const Text(
                            'No Delivery Partners Yet',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Tap "Add Partner" to add your auto / delivery drivers and track per-box, line trips, and advances.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.grey.shade600,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    )
                  else
                    ..._filtered.map((partner) => _PartnerCard(
                          partner: partner,
                          currency: _currency,
                          onTap: () async {
                            await Navigator.push(
                              context,
                              MaterialPageRoute<void>(
                                builder: (_) => DeliveryPartnerPassbookScreen(
                                  partnerId: partner.id!,
                                  repository: _repo,
                                ),
                              ),
                            );
                            await _loadPartners();
                          },
                          onEdit: () => _showPartnerDialog(existing: partner),
                          onCall: (partner.phone != null &&
                                  partner.phone!.trim().isNotEmpty)
                              ? () => _callPartner(partner.phone!)
                              : null,
                        )),
                ],
              ),
            ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.title,
    required this.amount,
    required this.color,
    required this.bgColor,
    required this.icon,
  });

  final String title;
  final String amount;
  final Color color;
  final Color bgColor;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: color),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: color,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            amount,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w900,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class _PartnerCard extends StatelessWidget {
  const _PartnerCard({
    required this.partner,
    required this.currency,
    required this.onTap,
    required this.onEdit,
    this.onCall,
  });

  final DeliveryPartner partner;
  final NumberFormat currency;
  final VoidCallback onTap;
  final VoidCallback onEdit;
  final VoidCallback? onCall;

  @override
  Widget build(BuildContext context) {
    final bool hasAdvance = partner.advanceBalance > 0;
    final bool hasPayable = partner.payableBalance > 0;
    final Color badgeColor = hasAdvance
        ? const Color(0xFF0D9488)
        : hasPayable
            ? const Color(0xFFEA580C)
            : Colors.grey.shade600;
    final Color badgeBg = hasAdvance
        ? const Color(0xFFF0FDFA)
        : hasPayable
            ? const Color(0xFFFFF7ED)
            : Colors.grey.shade100;
    final String badgeText = hasAdvance
        ? 'Advance: ₹${currency.format(partner.advanceBalance)}'
        : hasPayable
            ? 'To Pay: ₹${currency.format(partner.payableBalance)}'
            : 'Settled (₹0)';

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: Colors.indigo.shade50,
                child: Text(
                  partner.name.isNotEmpty
                      ? partner.name[0].toUpperCase()
                      : 'D',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: Colors.indigo.shade700,
                    fontSize: 18,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      partner.name,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      [
                        if (partner.vehicleInfo != null &&
                            partner.vehicleInfo!.isNotEmpty)
                          partner.vehicleInfo!,
                        if (partner.phone != null && partner.phone!.isNotEmpty)
                          partner.phone!,
                      ].join(' • '),
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade600,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: badgeBg,
                        borderRadius: BorderRadius.circular(20),
                        border:
                            Border.all(color: badgeColor.withValues(alpha: 0.3)),
                      ),
                      child: Text(
                        badgeText,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: badgeColor,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              if (onCall != null)
                IconButton(
                  icon: const Icon(Icons.call_outlined, size: 20),
                  color: Colors.green.shade700,
                  onPressed: onCall,
                ),
              IconButton(
                icon: const Icon(Icons.edit_outlined, size: 20),
                color: Colors.grey.shade600,
                onPressed: onEdit,
              ),
              const Icon(Icons.chevron_right_rounded, color: Colors.grey),
            ],
          ),
        ),
      ),
    );
  }
}
