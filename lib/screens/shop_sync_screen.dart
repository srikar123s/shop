import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shop/models/shop_profile.dart';
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
                    if (_syncService.isPendingApproval) ...[
                      _buildPendingApprovalView(shop!),
                    ] else ...[
                      // Active Shop Details Card
                      _buildActiveShopCard(shop!),
                      const SizedBox(height: 18),

                      // QR Code & Share Card (OWNER ONLY!)
                      if (shop.isOwner) ...[
                        _buildQrAndShareCard(shop),
                        const SizedBox(height: 18),
                      ],

                      // Device & Role Info Card
                      _buildDeviceRoleCard(shop),
                      const SizedBox(height: 18),

                      // Connected Staff & Permissions (Owner manages staff; Staff sees permissions overview)
                      if (shop.isOwner) ...[
                        _buildConnectedDevicesCard(shop),
                        const SizedBox(height: 24),
                      ] else ...[
                        _buildStaffPermissionsOverviewCard(),
                        const SizedBox(height: 24),
                      ],

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
                    ],
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
      case SyncStatus.pendingApproval:
        bg = const Color(0xFFFEF3C7);
        textColor = const Color(0xFF92400E);
        icon = Icons.hourglass_top_rounded;
        text = 'Join Request Pending: Waiting for Master Device to approve...';
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
        text = 'Setup cloud sync to share products and live orders with partner devices.';
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
                      shop.isOwner ? '👑 Master Device (Primary Phone)' : '🤝 Partner Device (Family Member)',
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
          _buildInfoRow('Contact Phone', shop.ownerPhone.isNotEmpty ? shop.ownerPhone : 'Not provided'),
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
            'Pair Family & Partner Devices',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Color(0xFF0F172A)),
          ),
          const SizedBox(height: 6),
          const Text(
            'Family members and partners can scan this QR or enter the code to join this shop and get all products, prices & live orders.',
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
    final isOwner = shop.isOwner;
    final displayName = isOwner
        ? (shop.ownerName.isNotEmpty ? shop.ownerName : 'Master Device')
        : (shop.staffName.isNotEmpty ? shop.staffName : 'Partner Device');
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 18,
            backgroundColor:
                isOwner ? Colors.amber.shade100 : Colors.teal.shade100,
            child: Icon(
              isOwner ? Icons.admin_panel_settings : Icons.person,
              color: isOwner ? Colors.amber.shade900 : Colors.teal.shade800,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Connected as: $displayName (${isOwner ? "Master Device" : "Partner Device"})',
                  style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                      color: Color(0xFF1E293B)),
                ),
                Text(
                  'Device ID: ${_syncService.deviceId}',
                  style:
                      const TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPendingApprovalView(ShopProfile shop) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFFDE68A), width: 2),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0C000000),
            blurRadius: 16,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: const BoxDecoration(
              color: Color(0xFFFEF3C7),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.hourglass_top_rounded,
              color: Color(0xFFD97706),
              size: 48,
            ),
          ),
          const SizedBox(height: 18),
          const Text(
            'Join Request Pending Approval',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: Color(0xFF0F172A),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Waiting for the Master Device (${shop.ownerName.isNotEmpty ? shop.ownerName : "Primary Phone"}) to approve your join request.',
            textAlign: TextAlign.center,
            style: TextStyle(
                fontSize: 13, color: Colors.grey.shade700, height: 1.4),
          ),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Column(
              children: [
                _buildPendingInfoRow('Shop Name', shop.shopName),
                const Divider(height: 16),
                _buildPendingInfoRow('Your Member Name', shop.staffName),
                const Divider(height: 16),
                _buildPendingInfoRow('Device ID', _syncService.deviceId),
                const Divider(height: 16),
                _buildPendingInfoRow('Status', '⏳ PENDING MASTER APPROVAL',
                    color: const Color(0xFFD97706)),
              ],
            ),
          ),
          const SizedBox(height: 20),
          const SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(
              strokeWidth: 2.5,
              color: Color(0xFFD97706),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'This screen will automatically update when the Master Device approves your device.',
            textAlign: TextAlign.center,
            style: TextStyle(
                fontSize: 12,
                color: Colors.grey.shade500,
                fontStyle: FontStyle.italic),
          ),
          const SizedBox(height: 20),
          OutlinedButton.icon(
            onPressed: _handleDisconnect,
            icon: const Icon(Icons.close_rounded, color: Colors.red),
            label: const Text('CANCEL JOIN REQUEST',
                style: TextStyle(color: Colors.red)),
            style: OutlinedButton.styleFrom(
              side: BorderSide(color: Colors.red.shade300),
              padding:
                  const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPendingInfoRow(String label, String value, {Color? color}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label,
            style: const TextStyle(fontSize: 13, color: Color(0xFF64748B))),
        Text(
          value,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.bold,
            color: color ?? const Color(0xFF0F172A),
          ),
        ),
      ],
    );
  }

  Widget _buildConnectedDevicesCard(dynamic shop) {
    return StreamBuilder<List<StaffDevice>>(
      stream: _syncService.streamConnectedDevices(),
      builder: (context, snapshot) {
        final devices = snapshot.data ?? [];
        final pendingDevices =
            devices.where((d) => d.isPending && !d.isOwner).toList();
        final approvedDevices =
            devices.where((d) => d.isApproved || d.isOwner).toList();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // PENDING REQUESTS SECTION
            if (pendingDevices.isNotEmpty) ...[
              Container(
                margin: const EdgeInsets.only(bottom: 16),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFFBEB),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFF59E0B), width: 1.5),
                  boxShadow: const [
                    BoxShadow(
                        color: Color(0x0A000000),
                        blurRadius: 10,
                        offset: Offset(0, 4)),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFDE68A),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(Icons.person_add_rounded,
                              color: Color(0xFFB45309), size: 22),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Pending Join Requests (${pendingDevices.length})',
                                style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF92400E)),
                              ),
                              const Text(
                                'Partner devices waiting for your approval to connect to this shop.',
                                style: TextStyle(
                                    fontSize: 12, color: Color(0xFF78350F)),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    ...pendingDevices
                        .map((pDev) => _buildPendingRequestItem(pDev)),
                  ],
                ),
              ),
            ],

            // CONNECTED PARTNER DEVICES CARD
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFE2E8F0)),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x08000000),
                    blurRadius: 10,
                    offset: Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: const Color(0xFF0F766E)
                                  .withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(Icons.people_alt_rounded,
                                color: Color(0xFF0F766E), size: 20),
                          ),
                          const SizedBox(width: 10),
                          const Text(
                            'Connected Partner Devices',
                            style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF0F172A)),
                          ),
                        ],
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: const Color(0xFFD1FAE5),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          '${approvedDevices.length} Connected',
                          style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF065F46)),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (approvedDevices.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Text(
                        'No other devices connected yet. Partners can scan the QR code above or enter code "${shop.shopCode}" to send a join request.',
                        style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade600,
                            fontStyle: FontStyle.italic),
                      ),
                    )
                  else
                    ...approvedDevices.map(
                        (device) => _buildApprovedDeviceItem(device, shop)),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildPendingRequestItem(StaffDevice device) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFFDE68A)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: const Color(0xFFFEF3C7),
                child: const Icon(Icons.person_outline,
                    color: Color(0xFFB45309), size: 20),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      device.staffName.isNotEmpty
                          ? device.staffName
                          : 'New Staff Member',
                      style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                          color: Color(0xFF0F172A)),
                    ),
                    Text(
                      'Device ID: ${device.deviceId}',
                      style:
                          TextStyle(fontSize: 11, color: Colors.grey.shade600),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: () async {
                    await _syncService.approveStaffDevice(device.deviceId);
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                              'Accepted ${device.staffName}! Device is now synced.'),
                          backgroundColor: const Color(0xFF0F766E),
                        ),
                      );
                    }
                  },
                  icon: const Icon(Icons.check, size: 16),
                  label: const Text('ACCEPT REQUEST'),
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF0F766E),
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8)),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () async {
                    await _syncService.rejectStaffDevice(device.deviceId);
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                              'Declined join request from ${device.staffName}.'),
                          backgroundColor: Colors.red.shade700,
                        ),
                      );
                    }
                  },
                  icon: const Icon(Icons.close, size: 16, color: Colors.red),
                  label:
                      const Text('DECLINE', style: TextStyle(color: Colors.red)),
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: Colors.red.shade300),
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8)),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildApprovedDeviceItem(StaffDevice device, dynamic shop) {
    final isCurrentDevice = device.deviceId == _syncService.deviceId;
    final isOwnerDevice = device.role == 'owner';

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isCurrentDevice
            ? const Color(0xFFF0FDF4)
            : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isCurrentDevice
              ? const Color(0xFF86EFAC)
              : const Color(0xFFE2E8F0),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 16,
                backgroundColor: isOwnerDevice
                    ? Colors.amber.shade100
                    : Colors.teal.shade100,
                child: Icon(
                  isOwnerDevice ? Icons.admin_panel_settings : Icons.person,
                  size: 18,
                  color: isOwnerDevice
                      ? Colors.amber.shade900
                      : Colors.teal.shade800,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            device.staffName.isNotEmpty
                                ? device.staffName
                                : (isOwnerDevice ? 'Owner' : 'Staff Counter'),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                        ),
                        if (isCurrentDevice) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 1),
                            decoration: BoxDecoration(
                              color: const Color(0xFFDCFCE7),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Text('THIS DEVICE',
                                style: TextStyle(
                                    fontSize: 9,
                                    fontWeight: FontWeight.w800,
                                    color: Color(0xFF166534))),
                          ),
                        ],
                      ],
                    ),
                    Text(
                      'ID: ${device.deviceId} • ${isOwnerDevice ? "Owner / Master" : "Staff Member"}',
                      style:
                          TextStyle(fontSize: 11, color: Colors.grey.shade600),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (shop.isOwner && !isOwnerDevice) ...[
            const Divider(height: 16),
            const Text(
              'Owner Controls & Permissions:',
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF475569)),
            ),
            const SizedBox(height: 4),
            SwitchListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: const Text('Allow Changing Prices in Bills',
                  style: TextStyle(fontSize: 12)),
              value: device.canChangePrice,
              onChanged: (val) {
                _syncService.updateDevicePermission(
                  targetDeviceId: device.deviceId,
                  permissionKey: 'canChangePrice',
                  value: val,
                );
              },
            ),
            SwitchListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: const Text('Allow Adding & Editing Products',
                  style: TextStyle(fontSize: 12)),
              value: device.canManageProducts,
              onChanged: (val) {
                _syncService.updateDevicePermission(
                  targetDeviceId: device.deviceId,
                  permissionKey: 'canManageProducts',
                  value: val,
                );
              },
            ),
            SwitchListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: const Text('Allow Completing & Closing Orders',
                  style: TextStyle(fontSize: 12)),
              value: device.canCloseOrders,
              onChanged: (val) {
                _syncService.updateDevicePermission(
                  targetDeviceId: device.deviceId,
                  permissionKey: 'canCloseOrders',
                  value: val,
                );
              },
            ),
            SwitchListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: const Text(
                  'Allow Editing Ordering Shortcuts (+5, +6, etc.)',
                  style: TextStyle(fontSize: 12)),
              value: device.canChangeShortcuts,
              onChanged: (val) {
                _syncService.updateDevicePermission(
                  targetDeviceId: device.deviceId,
                  permissionKey: 'canChangeShortcuts',
                  value: val,
                );
              },
            ),
            SwitchListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: const Text('Allow Viewing Total Bill Values & Revenue',
                  style: TextStyle(fontSize: 12)),
              value: device.canViewBillTotals,
              onChanged: (val) {
                _syncService.updateDevicePermission(
                  targetDeviceId: device.deviceId,
                  permissionKey: 'canViewBillTotals',
                  value: val,
                );
              },
            ),
            const SizedBox(height: 4),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: () async {
                  final confirm = await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: Text('Remove ${device.staffName}?'),
                      content: Text(
                          'This will revoke access for ${device.staffName} and disconnect their device from this shop.'),
                      actions: [
                        TextButton(
                            onPressed: () => Navigator.pop(ctx, false),
                            child: const Text('CANCEL')),
                        FilledButton(
                          onPressed: () => Navigator.pop(ctx, true),
                          style: FilledButton.styleFrom(
                              backgroundColor: Colors.red),
                          child: const Text('REMOVE'),
                        ),
                      ],
                    ),
                  );
                  if (confirm == true) {
                    await _syncService.revokeStaffDevice(device.deviceId);
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                            content: Text(
                                'Revoked access for ${device.staffName}')),
                      );
                    }
                  }
                },
                icon: const Icon(Icons.person_remove_rounded,
                    color: Colors.red, size: 16),
                label: const Text('Revoke Access / Remove Staff',
                    style: TextStyle(color: Colors.red, fontSize: 12)),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildStaffPermissionsOverviewCard() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: const [
          BoxShadow(
              color: Color(0x08000000), blurRadius: 10, offset: Offset(0, 4)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFF0F766E).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.verified_user_rounded,
                    color: Color(0xFF0F766E), size: 20),
              ),
              const SizedBox(width: 10),
              const Text(
                'Your Partner Device Permissions',
                style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF0F172A)),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Permissions configured and managed by shop owner.',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
          ),
          const SizedBox(height: 14),
          _buildPermissionStatusRow(
              'Change Prices in Bills', _syncService.canChangePrice),
          _buildPermissionStatusRow(
              'Add & Edit Products', _syncService.canManageProducts),
          _buildPermissionStatusRow(
              'Close & Complete Orders', _syncService.canCloseOrders),
          _buildPermissionStatusRow(
              'Edit Quantity Shortcuts', _syncService.canChangeShortcuts),
          _buildPermissionStatusRow(
              'View Bill Totals & Sales', _syncService.canViewBillTotals),
        ],
      ),
    );
  }

  Widget _buildPermissionStatusRow(String label, bool allowed) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: const TextStyle(fontSize: 13, color: Color(0xFF334155))),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color:
                  allowed ? const Color(0xFFDCFCE7) : const Color(0xFFFEE2E2),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              allowed ? 'ALLOWED' : 'RESTRICTED',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.bold,
                color: allowed
                    ? const Color(0xFF166534)
                    : const Color(0xFF991B1B),
              ),
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
                        '👑 Master Device (Primary Phone)',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Color(0xFF0F172A)),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'Create a new shop database, generate a Shop Code, and pair partner devices.',
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

        // Option 2: Partner Member
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
                        '🤝 Partner Device (Family Member)',
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
                  'Join Existing Shop (Partner Device)',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Color(0xFF0F172A)),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Text(
              'Enter the 6-character Shop Code shared by your Master Device (e.g. SH-8492).',
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
                hintText: 'e.g. Sridevi, Srikar, Counter 1',
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

