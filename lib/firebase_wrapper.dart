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
      print('🔵 Ожидание обработки google-services.json плагином...');
      // Задержка для плагина google-services обработать google-services.json
      await Future.delayed(const Duration(milliseconds: 1000));
      
      print('🔵 Вызов Firebase.initializeApp()...');
      // ignore: avoid_dynamic_calls
      await firebase_core.Firebase.initializeApp();
      print('✅ Firebase.initializeApp() завершен');
      
      // КРИТИЧЕСКИ ВАЖНО: Проверяем, что App действительно доступен
      print('🔵 Проверка доступности Firebase App...');
      int attempts = 0;
      const maxAttempts = 20;
      
      while (attempts < maxAttempts) {
        try {
          // ignore: avoid_dynamic_calls
          final app = firebase_core.Firebase.app();
          print('✅ Firebase App доступен: ${app.name} (попытка ${attempts + 1})');
          // Дополнительная задержка для гарантии полной инициализации
          await Future.delayed(const Duration(milliseconds: 500));
          print('✅ Firebase инициализирован и готов к использованию');
          return; // Успешно инициализирован
        } catch (e) {
          attempts++;
          if (attempts >= maxAttempts) {
            print('❌ Firebase App не стал доступен после $maxAttempts попыток');
            print('   Последняя ошибка: $e');
            throw Exception('Firebase App не инициализирован после $maxAttempts попыток');
          }
          print('⚠️ Попытка $attempts/$maxAttempts: Firebase App еще не доступен, ожидание...');
          await Future.delayed(const Duration(milliseconds: 300));
        }
      }
    } catch (e) {
      print('❌ Ошибка инициализации Firebase: $e');
      rethrow;
    }
  }
}

