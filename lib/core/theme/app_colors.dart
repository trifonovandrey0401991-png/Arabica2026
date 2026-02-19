import 'package:flutter/material.dart';

/// Централизованная палитра цветов приложения Arabica.
///
/// Использование: `AppColors.emerald`, `AppColors.gold` и т.д.
/// Вместо хардкода `Color(0xFF1A4D4D)`.
class AppColors {
  AppColors._();

  // ═══════════════════════════════════════════════════
  // Dark Emerald Theme (основная тема)
  // ═══════════════════════════════════════════════════
  static const Color emerald = Color(0xFF1A4D4D);
  static const Color emeraldLight = Color(0xFF2A6363);
  static const Color emeraldDark = Color(0xFF0D2E2E);
  static const Color night = Color(0xFF051515);
  static const Color gold = Color(0xFFD4AF37);
  static const Color darkGold = Color(0xFFB8960C);
  static const Color primaryGreen = Color(0xFF004D40);
  static const Color deepEmerald = Color(0xFF0D3030);
  static const Color turquoise = Color(0xFF4ECDC4);

  // ═══════════════════════════════════════════════════
  // AI Training Theme (тёмно-синяя тема)
  // ═══════════════════════════════════════════════════
  static const Color darkNavy = Color(0xFF1A1A2E);
  static const Color navy = Color(0xFF16213E);
  static const Color deepBlue = Color(0xFF0F3460);

  // ═══════════════════════════════════════════════════
  // Semantic / Status
  // ═══════════════════════════════════════════════════
  static const Color success = Color(0xFF4CAF50);
  static const Color successLight = Color(0xFF81C784);
  static const Color error = Color(0xFFEF4444);
  static const Color errorLight = Color(0xFFF87171);
  static const Color warning = Color(0xFFF59E0B);
  static const Color warningLight = Color(0xFFFBBF24);
  static const Color info = Color(0xFF3B82F6);
  static const Color infoLight = Color(0xFF60A5FA);
  static const Color amber = Color(0xFFFFC107);
  static const Color amberLight = Color(0xFFFFD54F);

  // ═══════════════════════════════════════════════════
  // Gradient Colors (AI Training / акценты)
  // ═══════════════════════════════════════════════════
  static const Color indigo = Color(0xFF6366F1);
  static const Color purple = Color(0xFF8B5CF6);
  static const Color purpleLight = Color(0xFFA78BFA);
  static const Color emeraldGreen = Color(0xFF10B981);
  static const Color emeraldGreenLight = Color(0xFF34D399);
  static const Color blue = Color(0xFF42A5F5);

  // ═══════════════════════════════════════════════════
  // MaterialColor palette (для ThemeData)
  // ═══════════════════════════════════════════════════
  static const Color teal50 = Color(0xFFE0F2F1);
  static const Color teal100 = Color(0xFFB2DFDB);
  static const Color teal200 = Color(0xFF80CBC4);
  static const Color teal300 = Color(0xFF4DB6AC);
  static const Color teal400 = Color(0xFF26A69A);
  static const Color teal500 = Color(0xFF009688);
  static const Color teal600 = Color(0xFF00897B);
  static const Color teal700 = Color(0xFF00796B);
  static const Color teal800 = Color(0xFF00695C);

  // ═══════════════════════════════════════════════════
  // Warm Amber / Gold Extended
  // ═══════════════════════════════════════════════════
  static const Color goldLight = Color(0xFFE8C84A);
  static const Color warmAmber = Color(0xFFD4A017);
  static const Color warmAmberLight = Color(0xFFE6B422);

  // ═══════════════════════════════════════════════════
  // UI Misc
  // ═══════════════════════════════════════════════════
  static const Color darkGray = Color(0xFF333333);
  static const Color neutral = Color(0xFF9E9E9E);
}
