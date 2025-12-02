import 'package:flutter/foundation.dart' show kIsWeb;

// Условный импорт Firebase: по умолчанию stub, на мобильных - реальный пакет
import 'firebase_core_stub.dart' as firebase_core if (dart.library.io) 'package:firebase_core/firebase_core.dart';

/// Обертка для Firebase, которая работает на всех платформах
class FirebaseWrapper {
  static Future<void> initializeApp() async {
    if (kIsWeb) {
      // Веб-платформа - Firebase не поддерживается
      print('⚠️ Firebase не поддерживается на веб-платформе');
      return;
    }
    
    // Мобильные платформы - используем реальный Firebase
    try {
      // ignore: avoid_dynamic_calls
      await firebase_core.Firebase.initializeApp();
      print('✅ Firebase инициализирован');
    } catch (e) {
      print('⚠️ Ошибка инициализации Firebase: $e');
      rethrow;
    }
  }
}

