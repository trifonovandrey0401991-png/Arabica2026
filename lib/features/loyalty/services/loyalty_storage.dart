import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

import 'loyalty_service.dart';

class LoyaltyStorage {
  static const _qrKey = 'loyalty_qr';
  static const _pointsKey = 'loyalty_points';
  static const _freeDrinksKey = 'loyalty_free_drinks';
  static const _promoKey = 'loyalty_promo';
  static const _pointsRequiredKey = 'loyalty_points_required';
  static const _drinksToGiveKey = 'loyalty_drinks_to_give';

  // Keys for gamification cache (raw JSON strings)
  static const _gamSettingsKey = 'loyalty_gam_settings';
  static const _gamClientPrefix = 'loyalty_gam_client_';
  static const _gamPrizePrefix = 'loyalty_gam_prize_';

  static Future<void> save(LoyaltyInfo info) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_qrKey, info.qr);
    await prefs.setInt(_pointsKey, info.points);
    await prefs.setInt(_freeDrinksKey, info.freeDrinks);
    await prefs.setString(_promoKey, info.promoText);
    await prefs.setInt(_pointsRequiredKey, info.pointsRequired);
    await prefs.setInt(_drinksToGiveKey, info.drinksToGive);
  }

  static Future<LoyaltyInfo?> read({
    required String name,
    required String phone,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final qr = prefs.getString(_qrKey);
    if (qr == null || qr.isEmpty) {
      return null;
    }

    final points = prefs.getInt(_pointsKey) ?? 0;
    final pointsRequired = prefs.getInt(_pointsRequiredKey);
    final drinksToGive = prefs.getInt(_drinksToGiveKey);

    // Если настройки не сохранены в кэше - возвращаем null, чтобы загрузить с сервера
    if (pointsRequired == null || drinksToGive == null) {
      return null;
    }

    return LoyaltyInfo(
      name: name,
      phone: phone,
      qr: qr,
      points: points,
      freeDrinks: prefs.getInt(_freeDrinksKey) ?? 0,
      promoText: prefs.getString(_promoKey) ?? '',
      readyForRedeem: pointsRequired > 0 && points >= pointsRequired,
      pointsRequired: pointsRequired,
      drinksToGive: drinksToGive,
    );
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_qrKey);
    await prefs.remove(_pointsKey);
    await prefs.remove(_freeDrinksKey);
    await prefs.remove(_promoKey);
    await prefs.remove(_pointsRequiredKey);
    await prefs.remove(_drinksToGiveKey);
  }

  // ===== Gamification cache (raw JSON maps) =====

  static Future<void> saveGamificationSettings(Map<String, dynamic> json) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_gamSettingsKey, jsonEncode(json));
  }

  static Future<Map<String, dynamic>?> readGamificationSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_gamSettingsKey);
      if (raw == null) return null;
      return Map<String, dynamic>.from(jsonDecode(raw) as Map);
    } catch (_) {
      return null;
    }
  }

  static Future<void> saveClientGamificationData(String phone, Map<String, dynamic> json) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('$_gamClientPrefix$phone', jsonEncode(json));
  }

  static Future<Map<String, dynamic>?> readClientGamificationData(String phone) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('$_gamClientPrefix$phone');
      if (raw == null) return null;
      return Map<String, dynamic>.from(jsonDecode(raw) as Map);
    } catch (_) {
      return null;
    }
  }

  static Future<void> saveClientPrize(String phone, Map<String, dynamic>? json) async {
    final prefs = await SharedPreferences.getInstance();
    if (json == null) {
      await prefs.remove('$_gamPrizePrefix$phone');
    } else {
      await prefs.setString('$_gamPrizePrefix$phone', jsonEncode(json));
    }
  }

  static Future<Map<String, dynamic>?> readClientPrize(String phone) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('$_gamPrizePrefix$phone');
      if (raw == null) return null;
      return Map<String, dynamic>.from(jsonDecode(raw) as Map);
    } catch (_) {
      return null;
    }
  }
}




