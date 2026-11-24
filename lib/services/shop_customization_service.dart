import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shop/services/shop_sync_service.dart';

class ShopCustomizationService extends ChangeNotifier {
  ShopCustomizationService._();
  static final ShopCustomizationService instance = ShopCustomizationService._();

  static const String _prefKeyShopName = 'custom_shop_name';
  static const String _prefKeyGlobalShortcuts = 'custom_global_shortcuts';
  static const String _prefKeyProductShortcuts = 'custom_product_shortcuts';
  static const String _prefKeyOfflineMode = 'pref_pure_offline_mode';
  static const String _prefKeyCashierName = 'custom_cashier_name';
  static const String _prefKeyUpiId = 'custom_shop_upi_id';
  static const String _prefKeyShopPhone = 'custom_shop_phone';
  static const String _prefKeyShopAddress = 'custom_shop_address';
  static const String _prefKeyGstin = 'custom_shop_gstin';
  static const String _prefKeyDigitalStamp = 'custom_shop_digital_stamp';

  String _shopName = const bool.fromEnvironment('STANDALONE_LOCAL', defaultValue: false)
      ? 'Shop Retail'
      : 'Shop Wholesale';
  String _cashierName = '';
  String _upiId = '';
  String _shopPhone = '';
  String _shopAddress = '';
  String _gstin = '';
  String _digitalStamp = '';
  List<double> _globalShortcuts =
      const bool.fromEnvironment('STANDALONE_LOCAL', defaultValue: false)
          ? <double>[1.0, 2.0, 5.0, 10.0]
          : <double>[5.0, 10.0, 20.0, 50.0];
  final Map<int, List<double>> _productShortcuts = <int, List<double>>{};
  bool _pureOfflineMode = false;
  bool _isInitialized = false;

  String get cashierName => _cashierName;

  String get shopName {
    if (_shopName.trim().isNotEmpty &&
        _shopName != 'Hardware Shop' &&
        _shopName != 'Shop Retail' &&
        _shopName != 'Shop Wholesale') {
      return _shopName;
    }
    final cloudShopName = ShopSyncService.instance.currentShop?.shopName;
    if (cloudShopName != null && cloudShopName.trim().isNotEmpty) {
      return cloudShopName;
    }
    return _shopName;
  }

  List<double> get globalShortcuts => List<double>.unmodifiable(_globalShortcuts);
  Map<int, List<double>> get productShortcuts => Map<int, List<double>>.unmodifiable(_productShortcuts);
  bool get isPureOfflineMode =>
      const bool.fromEnvironment('STANDALONE_LOCAL', defaultValue: false) ||
      _pureOfflineMode;

  Future<void> initialize() async {
    if (_isInitialized) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      _shopName = prefs.getString(_prefKeyShopName) ??
          ShopSyncService.instance.currentShop?.shopName ??
          (isPureOfflineMode ? 'Shop Retail' : 'Shop Wholesale');

      final globalStr = prefs.getString(_prefKeyGlobalShortcuts);
      if (globalStr != null && globalStr.isNotEmpty) {
        try {
          final decoded = (jsonDecode(globalStr) as List<dynamic>)
              .map((e) => (e as num).toDouble())
              .toList();
          if (decoded.isNotEmpty) {
            _globalShortcuts = decoded;
          }
        } catch (_) {}
      }

      final prodStr = prefs.getString(_prefKeyProductShortcuts);
      if (prodStr != null && prodStr.isNotEmpty) {
        try {
          final decodedMap = jsonDecode(prodStr) as Map<String, dynamic>;
          _productShortcuts.clear();
          decodedMap.forEach((k, v) {
            final id = int.tryParse(k);
            if (id != null && v is List) {
              _productShortcuts[id] =
                  v.map((e) => (e as num).toDouble()).toList();
            }
          });
        } catch (_) {}
      }

      _pureOfflineMode = prefs.getBool(_prefKeyOfflineMode) ?? false;
      _cashierName = prefs.getString(_prefKeyCashierName) ?? '';
      _upiId = prefs.getString(_prefKeyUpiId) ?? '';
      _shopPhone = prefs.getString(_prefKeyShopPhone) ?? '';
      _shopAddress = prefs.getString(_prefKeyShopAddress) ?? '';
      _gstin = prefs.getString(_prefKeyGstin) ?? '';
      _digitalStamp = prefs.getString(_prefKeyDigitalStamp) ?? '';
      _isInitialized = true;
      notifyListeners();
    } catch (e) {
      debugPrint('Error initializing ShopCustomizationService: $e');
    }
  }

  Future<void> setCashierName(String name) async {
    _cashierName = name.trim();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefKeyCashierName, _cashierName);
    notifyListeners();
  }

  Future<void> setShopName(String name) async {
    _shopName = name.trim().isEmpty ? 'Hardware Shop' : name.trim();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefKeyShopName, _shopName);

    // Also update current ShopProfile if available
    final current = ShopSyncService.instance.currentShop;
    if (current != null) {
      await ShopSyncService.instance.updateShopName(_shopName);
    }
    notifyListeners();
  }

  Future<void> setGlobalShortcuts(List<double> shortcuts) async {
    if (shortcuts.isEmpty) return;
    _globalShortcuts = List<double>.from(shortcuts)..sort();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        _prefKeyGlobalShortcuts, jsonEncode(_globalShortcuts));
    notifyListeners();
  }

  Future<void> setProductShortcuts(
      List<int> productIds, List<double> shortcuts) async {
    final sorted = List<double>.from(shortcuts)..sort();
    for (final id in productIds) {
      _productShortcuts[id] = sorted;
    }
    final prefs = await SharedPreferences.getInstance();
    final mapToSave = _productShortcuts.map((k, v) => MapEntry(k.toString(), v));
    await prefs.setString(_prefKeyProductShortcuts, jsonEncode(mapToSave));
    notifyListeners();
  }

  Future<void> removeProductShortcuts(List<int> productIds) async {
    for (final id in productIds) {
      _productShortcuts.remove(id);
    }
    final prefs = await SharedPreferences.getInstance();
    final mapToSave = _productShortcuts.map((k, v) => MapEntry(k.toString(), v));
    await prefs.setString(_prefKeyProductShortcuts, jsonEncode(mapToSave));
    notifyListeners();
  }

  List<double> getShortcutsForProduct(int? productId) {
    if (productId != null && _productShortcuts.containsKey(productId)) {
      return _productShortcuts[productId]!;
    }
    return _globalShortcuts;
  }

  String get upiId {
    if (_upiId.isNotEmpty) return _upiId;
    return ShopSyncService.instance.currentShop?.upiId ?? '';
  }

  String get shopPhone {
    if (_shopPhone.isNotEmpty) return _shopPhone;
    return ShopSyncService.instance.currentShop?.ownerPhone ?? '';
  }

  String get shopAddress {
    if (_shopAddress.isNotEmpty) return _shopAddress;
    return ShopSyncService.instance.currentShop?.address ?? '';
  }

  String get gstin {
    if (_gstin.isNotEmpty) return _gstin;
    return ShopSyncService.instance.currentShop?.gstin ?? '';
  }

  String get digitalStamp {
    if (_digitalStamp.isNotEmpty) return _digitalStamp;
    return ShopSyncService.instance.currentShop?.digitalStamp ?? '';
  }

  Future<void> setUpiId(String val) async {
    _upiId = val.trim();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefKeyUpiId, _upiId);
    if (!isPureOfflineMode && ShopSyncService.instance.hasShop) {
      unawaited(ShopSyncService.instance.updateShopProfileDetails(upiId: _upiId));
    }
    notifyListeners();
  }

  Future<void> setShopPhone(String val) async {
    _shopPhone = val.trim();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefKeyShopPhone, _shopPhone);
    if (!isPureOfflineMode && ShopSyncService.instance.hasShop) {
      unawaited(ShopSyncService.instance.updateShopProfileDetails(phone: _shopPhone));
    }
    notifyListeners();
  }

  Future<void> setShopAddress(String val) async {
    _shopAddress = val.trim();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefKeyShopAddress, _shopAddress);
    if (!isPureOfflineMode && ShopSyncService.instance.hasShop) {
      unawaited(ShopSyncService.instance.updateShopProfileDetails(address: _shopAddress));
    }
    notifyListeners();
  }

  Future<void> setGstin(String val) async {
    _gstin = val.trim();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefKeyGstin, _gstin);
    if (!isPureOfflineMode && ShopSyncService.instance.hasShop) {
      unawaited(ShopSyncService.instance.updateShopProfileDetails(gstin: _gstin));
    }
    notifyListeners();
  }

  Future<void> setDigitalStamp(String val) async {
    _digitalStamp = val.trim();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefKeyDigitalStamp, _digitalStamp);
    if (!isPureOfflineMode && ShopSyncService.instance.hasShop) {
      unawaited(ShopSyncService.instance.updateShopProfileDetails(digitalStamp: _digitalStamp));
    }
    notifyListeners();
  }

  Future<void> setPureOfflineMode(bool enabled) async {
    _pureOfflineMode = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefKeyOfflineMode, enabled);
    notifyListeners();
  }
}

