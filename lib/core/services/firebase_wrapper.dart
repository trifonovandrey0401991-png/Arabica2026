import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform;

// Прямой импорт Firebase Core - доступен на мобильных платформах
// На веб будет ошибка компиляции, но мы проверяем kIsWeb перед использованием
import 'package:firebase_core/firebase_core.dart' as firebase_core;
import '../utils/logger.dart';

/// Обертка для Firebase, которая работает на всех платформах
class FirebaseWrapper {
  static Future<void> initializeApp() async {
    if (kIsWeb) {
      // Веб-платформа - Firebase не поддерживается
      Logger.warning('Firebase не поддерживается на веб-платформе');
      return;
    }
    
    // Мобильные платформы - используем реальный Firebase
    try {
      Logger.debug('Начало инициализации Firebase Core...');
      Logger.debug('Платформа: $defaultTargetPlatform');
      
      Logger.debug('Вызов Firebase.initializeApp()...');
      try {
        // ignore: avoid_dynamic_calls
        await firebase_core.Firebase.initializeApp();
        Logger.success('Firebase.initializeApp() завершен успешно');
      } catch (initError) {
        Logger.error('Ошибка при вызове Firebase.initializeApp()', initError);
        // Пробуем еще раз с небольшой задержкой
        Logger.debug('Повторная попытка через 500ms...');
        await Future.delayed(const Duration(milliseconds: 500)); // Уменьшено с 2000
        // ignore: avoid_dynamic_calls
        await firebase_core.Firebase.initializeApp();
        Logger.success('Firebase.initializeApp() завершен после повторной попытки');
      }
      
      // Проверяем, что App действительно доступен
      Logger.debug('Проверка доступности Firebase App...');
      int attempts = 0;
      const maxAttempts = 10; // Уменьшено с 30 до 10
      
      while (attempts < maxAttempts) {
        try {
          // ignore: avoid_dynamic_calls
          final app = firebase_core.Firebase.app();
          Logger.success('Firebase App доступен: ${app.name}');
          return; // Успешно инициализирован
        } catch (e) {
          attempts++;
          if (attempts >= maxAttempts) {
            Logger.error('Firebase App не стал доступен после $maxAttempts попыток', e);
            Logger.warning('Продолжаем работу без полной инициализации Firebase App');
            return;
          }
          if (attempts % 3 == 0) {
            Logger.debug('Попытка $attempts/$maxAttempts: Firebase App еще не доступен...');
          }
          await Future.delayed(const Duration(milliseconds: 200)); // Уменьшено с 500
        }
      }
    } catch (e) {
      Logger.error('Критическая ошибка инициализации Firebase', e);
      // Не бросаем исключение - позволяем приложению работать без Firebase
      Logger.warning('Продолжаем работу без Firebase');
    }
  }
}

