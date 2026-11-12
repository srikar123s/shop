import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shop/services/shop_sync_service.dart';

class ShopSyncScreen extends StatefulWidget {
  const ShopSyncScreen({super.key});

  @override
  State<ShopSyncScreen> createState() => _ShopSyncScreenState();
}

class _ShopSyncScreenState extends State<ShopSyncScreen> {
  final _syncService = ShopSyncService.instance;

  // Mode: 0 = View / Options, 1 = Create Shop, 2 = Join Shop
  int _activeView = 0;

  // Create Shop Form
  final _createFormKey = GlobalKey<FormState>();
  final _shopNameController = TextEditingController();
  final _ownerNameController = TextEditingController();
  final _ownerPhoneController = TextEditingController();
  final _addressController = TextEditingController();
  final _gstinController = TextEditingController();
  final _gstRateController = TextEditingController(text: '18');

  // Join Shop Form
  final _joinFormKey = GlobalKey<FormState>();
  final _joinCodeController = TextEditingController();
  final _staffNameController = TextEditingController(text: 'Counter 1');

  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _syncService.addListener(_onSyncChanged);
  }

  @override
  void dispose() {
    _syncService.removeListener(_onSyncChanged);
    _shopNameController.dispose();
    _ownerNameController.dispose();
    _ownerPhoneController.dispose();
    _addressController.dispose();
    _gstinController.dispose();
    _gstRateController.dispose();
    _joinCodeController.dispose();
    _staffNameController.dispose();
    super.dispose();
  }

  void _onSyncChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _handleCreateShop() async {
    if (!_createFormKey.currentState!.validate()) return;
    setState(() => _isLoading = true);
    try {
      final gstRate = double.tryParse(_gstRateController.text.trim()) ?? 18.0;
      await _syncService.createShop(
        shopName: _shopNameController.text.trim(),
        ownerName: _ownerNameController.text.trim(),
        ownerPhone: _ownerPhoneController.text.trim(),
        address: _addressController.text.trim(),
        gstin: _gstinController.text.trim(),
        defaultGstRate: gstRate,
      );
      if (mounted) {
        setState(() {
          _activeView = 0;
          _isLoading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Shop created successfully! Code: ${_syncService.currentShop?.shopCode}'),
            backgroundColor: const Color(0xFF0F766E),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error creating shop: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _handleJoinShop() async {
    if (!_joinFormKey.currentState!.validate()) return;
    setState(() => _isLoading = true);
    try {
      final success = await _syncService.joinShop(
        shopCode: _joinCodeController.text.trim(),
        staffName: _staffNameController.text.trim(),
      );
      if (mounted) {
        setState(() => _isLoading = false);
        if (success) {
          setState(() => _activeView = 0);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Successfully joined ${_syncService.currentShop?.shopName}! All data synced.'),
              backgroundColor: const Color(0xFF0F766E),
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(_syncService.statusMessage),
              backgroundColor: Colors.red.shade700,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error joining shop: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _handleManualSync() async {
    setState(() => _isLoading = true);
    try {
      await _syncService.uploadLocalDataToCloud();
      await _syncService.downloadCloudDataToLocal();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('All products, orders, and customer data are fully synced!'),
            backgroundColor: Color(0xFF0F766E),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        final errText = e.toString().contains('permission-denied')
            ? 'Firebase Rules Locked! In Firebase Console -> Firestore Database -> Rules tab, change to "allow read, write: if true;" and click Publish.'
            : 'Sync failed: $e';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(errText),
            backgroundColor: Colors.red.shade800,
            duration: const Duration(seconds: 6),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _handleDisconnect() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Disconnect from Shop?'),
        content: const Text(
          'This will disconnect this phone from live cloud sync. Your local orders and products will remain safe on this phone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('CANCEL'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
            child: const Text('DISCONNECT'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await _syncService.leaveShop();
      if (mounted) {
        setState(() => _activeView = 0);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Disconnected from shop cloud')),
        );
      }
    }
  }

  void _shareShopCode(String code, String shopName) {
    Share.share(
      'Join our shop "$shopName" on Wholesale Shop Notebook app!\n\n'
      '🔑 Shop Code: $code\n\n'
      'Open the app -> Go to Shop Sync -> Enter this code to get all products, prices, and live orders instantly!',
      subject: 'Shop Code for $shopName',
    );
  }

  @override
  Widget build(BuildContext context) {
    final shop = _syncService.currentShop;
    final hasShop = _syncService.hasShop;

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text('Shop Sync & Team Access'),
        backgroundColor: Colors.white,
        elevation: 0,
        actions: [
          if (hasShop)
            IconButton(
              icon: _isLoading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.sync_rounded),
              tooltip: 'Sync Now',
              onPressed: _isLoading ? null : _handleManualSync,
            ),
        ],
      ),
      body: _isLoading && _activeView != 0
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Status Banner
                  _buildStatusBanner(),
                  const SizedBox(height: 18),

                  if (hasShop && _activeView == 0) ...[
                    // Active Shop Details Card
                    _buildActiveShopCard(shop!),
                    const SizedBox(height: 18),

                    // QR Code & Share Card
                    _buildQrAndShareCard(shop),
                    const SizedBox(height: 18),

                    // Device & Role Info Card
                    _buildDeviceRoleCard(shop),
                    const SizedBox(height: 24),

                    // Action Buttons
                    FilledButton.icon(
                      onPressed: _isLoading ? null : _handleManualSync,
                      icon: const Icon(Icons.sync_rounded),
                      label: Text(_isLoading ? 'Syncing...' : 'FORCE SYNC WITH CLOUD NOW'),
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF0F766E),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: _handleDisconnect,
                      icon: const Icon(Icons.logout_rounded, color: Colors.red),
                      label: const Text('DISCONNECT FROM THIS SHOP', style: TextStyle(color: Colors.red)),
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(color: Colors.red.shade300),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ] else if (_activeView == 1) ...[
                    // Create Shop View
                    _buildCreateShopForm(),
                  ] else if (_activeView == 2) ...[
                    // Join Shop View
                    _buildJoinShopForm(),
                  ] else ...[
                    // Options to Create or Join
                    _buildNoShopLanding(),
                  ],

                  const SizedBox(height: 24),
                  // Firebase Cloud Instructions Card
                  _buildCloudSetupHelpCard(),
                ],
              ),
            ),
    );
  }

  Widget _buildStatusBanner() {
    final status = _syncService.status;
    Color bg;
    Color textColor;
    IconData icon;
    String text;

    switch (status) {
      case SyncStatus.connected:
        bg = const Color(0xFFECFDF5);
        textColor = const Color(0xFF065F46);
        icon = Icons.check_circle_rounded;
        text = _syncService.statusMessage;
        break;
      case SyncStatus.syncing:
        bg = const Color(0xFFEFF6FF);
        textColor = const Color(0xFF1E40AF);
        icon = Icons.sync_rounded;
        text = _syncService.statusMessage;
        break;
      case SyncStatus.offline:
        bg = const Color(0xFFFFFBEB);
        textColor = const Color(0xFF92400E);
        icon = Icons.cloud_off_rounded;
        text = _syncService.statusMessage;
        break;
      case SyncStatus.error:
        bg = const Color(0xFFFEF2F2);
        textColor = const Color(0xFF991B1B);
        icon = Icons.error_outline_rounded;
        text = _syncService.statusMessage;
        break;
      default:
        bg = const Color(0xFFF1F5F9);
        textColor = const Color(0xFF475569);
        icon = Icons.info_outline_rounded;
        text = 'Setup cloud sync to share products and live orders with your staff.';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: textColor.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          Icon(icon, color: textColor, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(color: textColor, fontWeight: FontWeight.w600, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActiveShopCard(dynamic shop) {
    final dateFormat = DateFormat('dd MMM yyyy, hh:mm a');
    final lastSync = _syncService.lastSyncTime != null
        ? dateFormat.format(_syncService.lastSyncTime!)
        : 'Not yet';

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: const [
          BoxShadow(color: Color(0x08000000), blurRadius: 10, offset: Offset(0, 4)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFF0F766E).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.storefront_rounded, color: Color(0xFF0F766E), size: 28),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      shop.shopName,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF0F172A),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      shop.isOwner ? '👑 Owner / Master Device' : '👤 Staff / Cashier Device',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: shop.isOwner ? const Color(0xFFB45309) : const Color(0xFF0F766E),
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: _syncService.isConnected ? const Color(0xFFD1FAE5) : const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  _syncService.isConnected ? '● LIVE SYNC' : 'OFFLINE',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: _syncService.isConnected ? const Color(0xFF065F46) : const Color(0xFF64748B),
                  ),
                ),
              ),
            ],
          ),
          const Divider(height: 28, color: Color(0xFFF1F5F9)),
          _buildInfoRow('Owner Phone', shop.ownerPhone.isNotEmpty ? shop.ownerPhone : 'Not provided'),
          if (shop.address.isNotEmpty) _buildInfoRow('Address', shop.address),
          if (shop.gstin.isNotEmpty) _buildInfoRow('GSTIN', shop.gstin),
          _buildInfoRow('Last Synced', lastSync),
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 105,
            child: Text(
              label,
              style: const TextStyle(fontSize: 13, color: Color(0xFF64748B), fontWeight: FontWeight.w500),
            ),
          ),
          const Text(': ', style: TextStyle(color: Color(0xFF64748B))),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: 13, color: Color(0xFF1E293B), fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQrAndShareCard(dynamic shop) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: const [
          BoxShadow(color: Color(0x08000000), blurRadius: 10, offset: Offset(0, 4)),
        ],
      ),
      child: Column(
        children: [
          const Text(
            'Share Shop Access with Staff',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Color(0xFF0F172A)),
          ),
          const SizedBox(height: 6),
          const Text(
            'Staff members can scan this QR or enter the code to join this shop and get all products, prices & live orders.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
          ),
          const SizedBox(height: 16),

          // QR Code Display
          Center(
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFCBD5E1), width: 2),
                boxShadow: const [
                  BoxShadow(color: Color(0x0C000000), blurRadius: 12, offset: Offset(0, 4)),
                ],
              ),
              child: QrImageView(
                data: shop.shopCode,
                version: QrVersions.auto,
                size: 160.0,
                backgroundColor: Colors.white,
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Code Pill with Copy Action
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFCBD5E1)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('SHOP CODE', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Color(0xFF64748B))),
                    Text(
                      shop.shopCode,
                      style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, letterSpacing: 2, color: Color(0xFF0F766E)),
                    ),
                  ],
                ),
                Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.copy_rounded, color: Color(0xFF0F766E)),
                      tooltip: 'Copy Code',
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: shop.shopCode));
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Shop code copied to clipboard!')),
                        );
                      },
                    ),
                    IconButton(
                      icon: const Icon(Icons.share_rounded, color: Color(0xFF0F766E)),
                      tooltip: 'Share via WhatsApp',
                      onPressed: () => _shareShopCode(shop.shopCode, shop.shopName),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDeviceRoleCard(dynamic shop) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        children: [
          const Icon(Icons.devices_other_rounded, color: Color(0xFF64748B), size: 24),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Connected as: ${shop.staffName}',
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: Color(0xFF1E293B)),
                ),
                Text(
                  'Device ID: ${_syncService.deviceId}',
                  style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNoShopLanding() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Welcome Card
        Container(
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF0F766E), Color(0xFF115E59)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(18),
            boxShadow: const [
              BoxShadow(color: Color(0x200F766E), blurRadius: 16, offset: Offset(0, 6)),
            ],
          ),
          child: const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.hub_rounded, color: Colors.white, size: 36),
              SizedBox(height: 12),
              Text(
                'Connect Your Shop Team',
                style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800),
              ),
              SizedBox(height: 6),
              Text(
                'Allow multiple staff members to take orders simultaneously. All products, prices, and order history update in real-time across everyone\'s phones.',
                style: TextStyle(color: Color(0xFFCCFBF1), fontSize: 13, height: 1.4),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),

        // Option 1: Shop Owner
        InkWell(
          onTap: () => setState(() => _activeView = 1),
          borderRadius: BorderRadius.circular(16),
          child: Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFCBD5E1), width: 1.5),
              boxShadow: const [
                BoxShadow(color: Color(0x06000000), blurRadius: 8, offset: Offset(0, 2)),
              ],
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFEF3C7),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(Icons.add_business_rounded, color: Color(0xFFB45309), size: 30),
                ),
                const SizedBox(width: 16),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'I am the Shop Owner',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Color(0xFF0F172A)),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'Create a new shop, generate a Shop Code, and share with your team.',
                        style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.arrow_forward_ios_rounded, size: 16, color: Color(0xFF94A3B8)),
              ],
            ),
          ),
        ),
        const SizedBox(height: 14),

        // Option 2: Staff Member
        InkWell(
          onTap: () => setState(() => _activeView = 2),
          borderRadius: BorderRadius.circular(16),
          child: Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFCBD5E1), width: 1.5),
              boxShadow: const [
                BoxShadow(color: Color(0x06000000), blurRadius: 8, offset: Offset(0, 2)),
              ],
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE0F2FE),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(Icons.group_add_rounded, color: Color(0xFF0369A1), size: 30),
                ),
                const SizedBox(width: 16),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'I am Staff / Worker',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Color(0xFF0F172A)),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'Join an existing shop by entering the 6-character Shop Code or scanning QR.',
                        style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.arrow_forward_ios_rounded, size: 16, color: Color(0xFF94A3B8)),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCreateShopForm() {
    return Form(
      key: _createFormKey,
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back_rounded),
                  onPressed: () => setState(() => _activeView = 0),
                ),
                const SizedBox(width: 4),
                const Text(
                  'Create New Shop (Owner)',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Color(0xFF0F172A)),
                ),
              ],
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _shopNameController,
              decoration: const InputDecoration(
                labelText: 'Shop Name *',
                hintText: 'e.g. Srikar Hardware & Paints',
                prefixIcon: Icon(Icons.storefront_rounded),
                border: OutlineInputBorder(),
              ),
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Please enter your shop name' : null,
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _ownerNameController,
              decoration: const InputDecoration(
                labelText: 'Owner / Contact Person *',
                hintText: 'e.g. Srikar',
                prefixIcon: Icon(Icons.person_rounded),
                border: OutlineInputBorder(),
              ),
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Please enter owner name' : null,
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _ownerPhoneController,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                labelText: 'Phone Number *',
                hintText: 'e.g. 9876543210',
                prefixIcon: Icon(Icons.phone_rounded),
                border: OutlineInputBorder(),
              ),
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Please enter phone number' : null,
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _addressController,
              decoration: const InputDecoration(
                labelText: 'Shop Address (Optional)',
                hintText: 'e.g. Main Road, Hyderabad',
                prefixIcon: Icon(Icons.location_on_rounded),
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  flex: 3,
                  child: TextFormField(
                    controller: _gstinController,
                    textCapitalization: TextCapitalization.characters,
                    decoration: const InputDecoration(
                      labelText: 'GSTIN (Optional)',
                      hintText: 'e.g. 36AAAAA0000A1Z5',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: TextFormField(
                    controller: _gstRateController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'GST %',
                      hintText: '18',
                      suffixText: '%',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _handleCreateShop,
              icon: const Icon(Icons.check_rounded),
              label: const Text('CREATE SHOP & GENERATE CODE'),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF0F766E),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildJoinShopForm() {
    return Form(
      key: _joinFormKey,
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back_rounded),
                  onPressed: () => setState(() => _activeView = 0),
                ),
                const SizedBox(width: 4),
                const Text(
                  'Join Existing Shop (Staff)',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Color(0xFF0F172A)),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Text(
              'Enter the 6-character Shop Code shared by your shop owner (e.g. SH-8492).',
              style: TextStyle(fontSize: 13, color: Color(0xFF64748B)),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _joinCodeController,
              textCapitalization: TextCapitalization.characters,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                letterSpacing: 3,
                color: Color(0xFF0F766E),
              ),
              decoration: const InputDecoration(
                labelText: '6-Character Shop Code *',
                hintText: 'SH-XXXX',
                prefixIcon: Icon(Icons.key_rounded),
                border: OutlineInputBorder(),
              ),
              validator: (v) => (v == null || v.trim().length < 4) ? 'Please enter a valid shop code' : null,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _staffNameController,
              decoration: const InputDecoration(
                labelText: 'Your Name or Counter *',
                hintText: 'e.g. Counter 1, Raju, Warehouse',
                prefixIcon: Icon(Icons.person_pin_rounded),
                border: OutlineInputBorder(),
              ),
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Please enter your name/counter' : null,
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _handleJoinShop,
              icon: const Icon(Icons.cloud_download_rounded),
              label: const Text('CONNECT & SYNC SHOP DATA'),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF0F766E),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCloudSetupHelpCard() {
    return ExpansionTile(
      tilePadding: EdgeInsets.zero,
      shape: const Border(),
      title: const Row(
        children: [
          Icon(Icons.help_outline_rounded, size: 20, color: Color(0xFF64748B)),
          SizedBox(width: 8),
          Text(
            'How Cloud Real-Time Sync Works (Free)',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFF475569)),
          ),
        ],
      ),
      children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFFF1F5F9),
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '1. Firebase Cloud Firestore powers instant syncing between multiple devices with zero server cost on the free tier.\n'
                '2. To activate live cloud sync across all phones, download `google-services.json` from your Firebase project and place it inside the `android/app/` folder.\n'
                '3. Once configured, every order taken by any staff member instantly pops up in Order History across all phones in the shop!\n'
                '4. Offline Safe: When internet is not available, all orders and products stay safely stored on this phone and sync automatically when internet is back.',
                style: TextStyle(fontSize: 12, height: 1.5, color: Color(0xFF334155)),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

