import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Captures uncaught Flutter/platform errors into bounded local storage and
/// optionally uploads sanitized diagnostics to the active shop's `error_logs`
/// subcollection when authenticated and online.
class AppTelemetryService {
  static const String _localErrorsKey = 'app_telemetry_recent_errors_v1';
  static const String _activeShopCodeKey = 'shop_sync_shop_code';
  static const int _maxLocalEntries = 25;

  final FirebaseFirestore? _firestoreOverride;
  final FirebaseAuth? _authOverride;

  AppTelemetryService({
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
  })  : _firestoreOverride = firestore,
        _authOverride = auth;

  static final AppTelemetryService instance = AppTelemetryService();

  Future<void> recordError(
    Object error,
    StackTrace? stackTrace, {
    String source = 'flutter',
    bool fatal = false,
  }) async {
    final nowIso = DateTime.now().toUtc().toIso8601String();
    final sanitizedMessage = _truncate(_sanitize(error.toString()), 400);
    final sanitizedStack = stackTrace == null
        ? ''
        : _truncate(_sanitize(stackTrace.toString()), 1200);

    final entry = <String, dynamic>{
      'timestamp': nowIso,
      'source': source,
      'fatal': fatal,
      'message': sanitizedMessage,
      'stack': sanitizedStack,
    };

    try {
      await _persistLocally(entry);
    } catch (e) {
      debugPrint('Telemetry local persist skipped: $e');
    }

    try {
      await _uploadIfOnline(entry);
    } catch (e) {
      debugPrint('Telemetry cloud upload skipped: $e');
    }
  }

  Future<List<Map<String, dynamic>>> getRecentErrors() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_localErrorsKey);
    if (raw == null || raw.isEmpty) return [];
    final decoded = jsonDecode(raw);
    if (decoded is! List) return [];
    return decoded
        .whereType<Map>()
        .map((m) => Map<String, dynamic>.from(m))
        .toList();
  }

  Future<void> clearRecentErrors() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_localErrorsKey);
  }

  Future<void> _persistLocally(Map<String, dynamic> entry) async {
    final prefs = await SharedPreferences.getInstance();
    final existing = await getRecentErrors();
    existing.insert(0, entry);
    if (existing.length > _maxLocalEntries) {
      existing.removeRange(_maxLocalEntries, existing.length);
    }
    await prefs.setString(_localErrorsKey, jsonEncode(existing));
  }

  Future<void> _uploadIfOnline(Map<String, dynamic> entry) async {
    final prefs = await SharedPreferences.getInstance();
    final shopCode = prefs.getString(_activeShopCodeKey)?.trim() ?? '';
    if (shopCode.isEmpty) return;

    FirebaseAuth auth;
    FirebaseFirestore firestore;
    try {
      auth = _authOverride ?? FirebaseAuth.instance;
      firestore = _firestoreOverride ?? FirebaseFirestore.instance;
    } catch (_) {
      return;
    }

    final uid = auth.currentUser?.uid;
    if (uid == null || uid.isEmpty) return;

    await firestore
        .collection('shops')
        .doc(shopCode)
        .collection('error_logs')
        .add(<String, dynamic>{
          ...entry,
          'uid': uid,
          'platform': defaultTargetPlatform.name,
          'createdAt': FieldValue.serverTimestamp(),
        })
        .timeout(const Duration(seconds: 4));
  }

  static String _sanitize(String input) {
    // Strip accidental phone numbers (10+ digits) before saving diagnostics.
    return input.replaceAll(RegExp(r'\b\d{10,}\b'), '[REDACTED_NUM]');
  }

  static String _truncate(String input, int maxLen) {
    if (input.length <= maxLen) return input;
    return '${input.substring(0, maxLen)}...';
  }
}
