import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform;

// Прямой импорт Firebase Core - доступен на мобильных платформах
// На веб будет ошибка компиляции, но мы проверяем kIsWeb перед использованием
import 'package:firebase_core/firebase_core.dart' as firebase_core;

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
      print('🔵 Начало инициализации Firebase Core...');
      print('🔵 Платформа: ${defaultTargetPlatform}');
      
      // Увеличиваем задержку для плагина google-services обработать google-services.json
      print('🔵 Ожидание обработки google-services.json плагином...');
      await Future.delayed(const Duration(milliseconds: 2000));
      
      print('🔵 Вызов Firebase.initializeApp()...');
      try {
        // ignore: avoid_dynamic_calls
        await firebase_core.Firebase.initializeApp();
        print('✅ Firebase.initializeApp() завершен успешно');
      } catch (initError) {
        print('❌ Ошибка при вызове Firebase.initializeApp(): $initError');
        print('   Тип ошибки: ${initError.runtimeType}');
        // Пробуем еще раз с большей задержкой
        print('🔵 Повторная попытка через 2 секунды...');
        await Future.delayed(const Duration(milliseconds: 2000));
        // ignore: avoid_dynamic_calls
        await firebase_core.Firebase.initializeApp();
        print('✅ Firebase.initializeApp() завершен после повторной попытки');
      }
      
      // КРИТИЧЕСКИ ВАЖНО: Проверяем, что App действительно доступен
      print('🔵 Проверка доступности Firebase App...');
      int attempts = 0;
      const maxAttempts = 30; // Увеличиваем количество попыток
      
      while (attempts < maxAttempts) {
        try {
          // ignore: avoid_dynamic_calls
          final app = firebase_core.Firebase.app();
          print('✅ Firebase App доступен: ${app.name} (попытка ${attempts + 1})');
          // Дополнительная задержка для гарантии полной инициализации
          await Future.delayed(const Duration(milliseconds: 1000));
          print('✅ Firebase инициализирован и готов к использованию');
          return; // Успешно инициализирован
        } catch (e) {
          attempts++;
          if (attempts >= maxAttempts) {
            print('❌ Firebase App не стал доступен после $maxAttempts попыток');
            print('   Последняя ошибка: $e');
            print('   Тип ошибки: ${e.runtimeType}');
            // Не бросаем исключение, просто логируем - возможно, это не критично
            print('⚠️ Продолжаем работу без полной инициализации Firebase App');
            return;
          }
          if (attempts % 5 == 0) {
            print('⚠️ Попытка $attempts/$maxAttempts: Firebase App еще не доступен, ожидание...');
          }
          await Future.delayed(const Duration(milliseconds: 500));
        }
      }
    } catch (e) {
      print('❌ Критическая ошибка инициализации Firebase: $e');
      print('   Тип ошибки: ${e.runtimeType}');
      print('   Stack trace: ${StackTrace.current}');
      // Не бросаем исключение - позволяем приложению работать без Firebase
      print('⚠️ Продолжаем работу без Firebase');
    }
  }
}

