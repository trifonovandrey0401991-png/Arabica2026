import 'package:shared_preferences/shared_preferences.dart';

import 'loyalty_service.dart';

class LoyaltyStorage {
  static const _qrKey = 'loyalty_qr';
  static const _pointsKey = 'loyalty_points';
  static const _freeDrinksKey = 'loyalty_free_drinks';
  static const _promoKey = 'loyalty_promo';

  static Future<void> save(LoyaltyInfo info) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_qrKey, info.qr);
    await prefs.setInt(_pointsKey, info.points);
    await prefs.setInt(_freeDrinksKey, info.freeDrinks);
    await prefs.setString(_promoKey, info.promoText);
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

    return LoyaltyInfo(
      name: name,
      phone: phone,
      qr: qr,
      points: prefs.getInt(_pointsKey) ?? 0,
      freeDrinks: prefs.getInt(_freeDrinksKey) ?? 0,
      promoText: prefs.getString(_promoKey) ?? '',
      readyForRedeem: (prefs.getInt(_pointsKey) ?? 0) >= 10,
    );
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_qrKey);
    await prefs.remove(_pointsKey);
    await prefs.remove(_freeDrinksKey);
    await prefs.remove(_promoKey);
  }
}




