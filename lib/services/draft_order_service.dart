import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shop/models/order.dart';

class DraftOrderService {
  static const String _draftKey = 'current_order_draft';

  String _keyFor(int? customerId) =>
      customerId == null ? _draftKey : '${_draftKey}_$customerId';

  Future<void> saveDraft(DraftOrder draft, {int? customerId}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _keyFor(customerId ?? draft.customer.id),
      jsonEncode(draft.toMap()),
    );
  }

  Future<DraftOrder?> getDraft({int? customerId}) async {
    final prefs = await SharedPreferences.getInstance();
    final jsonStr = prefs.getString(_keyFor(customerId));
    if (jsonStr == null || jsonStr.isEmpty) return null;
    try {
      final map = jsonDecode(jsonStr) as Map<String, dynamic>;
      return DraftOrder.fromMap(map);
    } catch (_) {
      return null;
    }
  }

  Future<void> clearDraft({int? customerId}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyFor(customerId));
  }
}
