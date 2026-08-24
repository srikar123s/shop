import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shop/models/order.dart';

class DraftOrderService {
  static const String _draftKey = 'current_order_draft';

  Future<void> saveDraft(DraftOrder draft) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_draftKey, jsonEncode(draft.toMap()));
  }

  Future<DraftOrder?> getDraft() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonStr = prefs.getString(_draftKey);
    if (jsonStr == null || jsonStr.isEmpty) return null;
    try {
      final map = jsonDecode(jsonStr) as Map<String, dynamic>;
      return DraftOrder.fromMap(map);
    } catch (_) {
      return null;
    }
  }

  Future<void> clearDraft() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_draftKey);
  }
}
