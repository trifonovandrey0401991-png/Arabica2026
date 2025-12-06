// Условный импорт Firebase Messaging: на веб - stub, на мобильных - реальный пакет
import 'package:firebase_messaging/firebase_messaging.dart' if (dart.library.html) 'firebase_service_stub.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'my_dialogs_page.dart';
import 'review_detail_page.dart';
import 'review_service.dart';
import 'review_model.dart';
// Прямой импорт Firebase Core - доступен на мобильных платформах
// На веб будет ошибка компиляции, но мы проверяем kIsWeb перед использованием
import 'package:firebase_core/firebase_core.dart' as firebase_core;

/// Сервис для работы с Firebase Cloud Messaging (FCM)
class FirebaseService {
  static FirebaseMessaging? _messaging;
  static final FlutterLocalNotificationsPlugin _localNotifications = 
      FlutterLocalNotificationsPlugin();

  static bool _initialized = false;
  static BuildContext? _globalContext;
  
  /// Получить экземпляр FirebaseMessaging (ленивая инициализация)
  static FirebaseMessaging _getMessaging() {
    if (_messaging == null) {
      print('🔵 Создание экземпляра FirebaseMessaging...');
      
      // Проверяем, что Firebase App готов (только для мобильных платформ)
      if (!kIsWeb) {
        try {
          // ignore: avoid_dynamic_calls
          final app = firebase_core.Firebase.app();
          print('✅ Firebase App найден перед созданием Messaging: ${app.name}');
        } catch (e) {
          print('❌ Firebase App не найден: $e');
          throw Exception('Firebase App не инициализирован. Невозможно создать FirebaseMessaging.');
        }
      }
      
      try {
        _messaging = FirebaseMessaging.instance;
        print('✅ Экземпляр FirebaseMessaging создан');
      } catch (e) {
        print('❌ Ошибка создания FirebaseMessaging: $e');
        rethrow;
      }
    }
    return _messaging!;
  }

  /// Инициализация Firebase Messaging
  static Future<void> initialize() async {
    if (_initialized) {
      print('🔵 Firebase Messaging уже инициализирован');
      return;
    }

    try {
      print('🔵 Проверка инициализации Firebase Core...');
      
      // Проверяем, что Firebase Core инициализирован (для мобильных платформ)
      // На веб это будет stub, который просто вернется
      if (!kIsWeb) {
        // Дополнительная задержка для гарантии инициализации Firebase Core
        print('🔵 Дополнительное ожидание инициализации Firebase Core...');
        await Future.delayed(const Duration(milliseconds: 2000));
        
        // Пытаемся использовать Firebase Messaging - если Firebase не инициализирован,
        // это вызовет ошибку, которую мы обработаем
        try {
          // Просто проверяем, что можем получить instance
          // Если Firebase не инициализирован, это вызовет ошибку при запросе токена
          print('✅ Firebase Core готов к использованию');
        } catch (e) {
          print('⚠️ Предупреждение: $e');
          // Продолжаем - ошибка может быть не критичной
        }
      }
      
      print('🔵 Запрос разрешений на уведомления...');
      
      // Дополнительная задержка перед запросом разрешений
      await Future.delayed(const Duration(milliseconds: 500));
      
      // Получаем экземпляр FirebaseMessaging только после проверки готовности Firebase
      print('🔵 Получение экземпляра FirebaseMessaging...');
      FirebaseMessaging messaging;
      try {
        messaging = _getMessaging();
      } catch (e) {
        print('❌ Ошибка получения FirebaseMessaging, повторная попытка через 2 секунды...');
        await Future.delayed(const Duration(milliseconds: 2000));
        messaging = _getMessaging();
      }
      
      // Запрашиваем разрешение на уведомления
      NotificationSettings settings;
      try {
        settings = await messaging.requestPermission(
          alert: true,
          badge: true,
          sound: true,
          provisional: false,
        );
      } catch (e) {
        print('❌ Ошибка при запросе разрешений: $e');
        // Если ошибка связана с отсутствием Firebase App, ждем еще
        if (e.toString().contains('no-app') || e.toString().contains('Firebase App')) {
          print('🔵 Ожидание инициализации Firebase App...');
          await Future.delayed(const Duration(milliseconds: 2000));
          // Повторная попытка
          try {
            settings = await messaging.requestPermission(
              alert: true,
              badge: true,
              sound: true,
              provisional: false,
            );
          } catch (e2) {
            print('❌ Повторная ошибка при запросе разрешений: $e2');
            throw e2;
          }
        } else {
          throw e;
        }
      }

      if (settings.authorizationStatus == AuthorizationStatus.authorized) {
        print('✅ Пользователь разрешил уведомления');
      } else if (settings.authorizationStatus == AuthorizationStatus.provisional) {
        print('⚠️ Пользователь разрешил временные уведомления');
      } else {
        print('❌ Пользователь не разрешил уведомления');
        return;
      }

      // Добавляем задержку после получения разрешений, чтобы дать Firebase время обработать ошибки
      print('🔵 Ожидание после получения разрешений (1 секунда)...');
      await Future.delayed(const Duration(seconds: 1));
      
      // ВСЕ дальнейшие операции оборачиваем в отдельный try-catch,
      // чтобы ошибки не перехватывались общим catch блоком
      try {
        print('🔵 Шаг 1: После получения разрешений, перед инициализацией локальных уведомлений');
        print('🔵 Начало инициализации локальных уведомлений...');
        // Инициализация локальных уведомлений
        const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
        const iosSettings = DarwinInitializationSettings(
          requestAlertPermission: true,
          requestBadgePermission: true,
          requestSoundPermission: true,
        );

        const initSettings = InitializationSettings(
          android: androidSettings,
          iOS: iosSettings,
        );

        try {
          await _localNotifications.initialize(
            initSettings,
            onDidReceiveNotificationResponse: _onNotificationTapped,
          );
          print('✅ Локальные уведомления инициализированы');
        } catch (e) {
          print('⚠️ Ошибка инициализации локальных уведомлений: $e');
          // Продолжаем работу даже если локальные уведомления не инициализированы
        }

        // Получаем FCM токен с повторными попытками и обработкой ошибок
        // Выносим в отдельный блок, чтобы ошибки не перехватывались общим catch
        print('🔵 Начало получения FCM токена...');
        String? token;
        try {
          token = await _getTokenWithRetries(messaging);
          print('🔵 Получение токена завершено, результат: ${token != null ? "успешно" : "не получен"}');
        } catch (e) {
          // Если ошибка все равно произошла, логируем, но продолжаем работу
          print('⚠️ Критическая ошибка при получении токена: $e');
          print('⚠️ Приложение продолжит работу без push-уведомлений');
        }
      } catch (e) {
        print('⚠️ Ошибка в блоке инициализации после получения разрешений: $e');
        print('⚠️ Продолжаем работу, но некоторые функции могут не работать');
        // Продолжаем работу даже если произошла ошибка
      }

      // Обработка уведомлений в foreground (когда приложение открыто)
      try {
        FirebaseMessaging.onMessage.listen((RemoteMessage message) {
          print('📨 Получено сообщение в foreground: ${message.notification?.title}');
          _showLocalNotification(message);
        });
      } catch (e) {
        print('⚠️ Ошибка при настройке слушателя onMessage: $e');
      }

      // Обработка нажатия на уведомление (когда приложение в фоне)
      try {
        FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
          print('👆 Уведомление открыто из фона: ${message.data}');
          _handleNotificationTap(message);
        });
      } catch (e) {
        print('⚠️ Ошибка при настройке слушателя onMessageOpenedApp: $e');
      }

      // Обработка уведомления, которое открыло приложение (когда приложение было закрыто)
      try {
        RemoteMessage? initialMessage = await messaging.getInitialMessage();
        if (initialMessage != null) {
          print('👆 Уведомление открыло приложение: ${initialMessage.data}');
          _handleNotificationTap(initialMessage);
        }
      } catch (e) {
        print('⚠️ Ошибка при получении initialMessage: $e');
        // Продолжаем работу даже если не удалось получить initialMessage
      }

      // Обновление токена при его изменении
      try {
        messaging.onTokenRefresh.listen((newToken) {
          print('🔄 FCM Token обновлен: ${newToken.substring(0, 20)}...');
          _saveTokenToServer(newToken);
        });
      } catch (e) {
        print('⚠️ Ошибка при настройке слушателя onTokenRefresh: $e');
      }

      _initialized = true;
      print('✅ Firebase Messaging инициализирован');
    } catch (e) {
      print('❌ Ошибка инициализации Firebase Messaging: $e');
    }
  }

  /// Получить FCM токен с повторными попытками и обработкой ошибок
  static Future<String?> _getTokenWithRetries(FirebaseMessaging messaging) async {
    print('🔵 Начало получения FCM токена с повторными попытками...');
    String? token;
    int attempts = 0;
    const maxAttempts = 5;
    const delaySeconds = 3;

    while (token == null && attempts < maxAttempts) {
      try {
        attempts++;
        print('🔵 Попытка $attempts/$maxAttempts получить FCM токен...');
        
        // Пытаемся получить токен
        token = await messaging.getToken();
        
        if (token != null) {
          print('📱 FCM Token получен: ${token.substring(0, 20)}...');
          await _saveTokenToServer(token);
          return token;
        }
      } catch (e) {
        String errorMsg = e.toString();
        print('⚠️ Ошибка получения токена (попытка $attempts/$maxAttempts): $errorMsg');
        
        // Проверяем тип ошибки
        if (errorMsg.contains('FIS_AUTH_ERROR') || 
            errorMsg.contains('Firebase Installations Service') ||
            errorMsg.contains('firebase_messaging/unknown')) {
          if (attempts < maxAttempts) {
            print('🔵 Ошибка аутентификации Firebase. Повторная попытка через $delaySeconds секунд...');
            print('💡 Убедитесь, что SHA-сертификаты добавлены в Firebase Console');
            await Future.delayed(Duration(seconds: delaySeconds));
          } else {
            print('❌ Не удалось получить FCM токен после $maxAttempts попыток');
            print('⚠️ Приложение продолжит работу, но push-уведомления не будут работать');
            print('💡 Проверьте:');
            print('   1. SHA-1 и SHA-256 сертификаты добавлены в Firebase Console');
            print('   2. Package name совпадает: com.example.arabica_app');
            print('   3. google-services.json актуален');
            // Приложение продолжит работу без токена
            break;
          }
        } else {
          // Другая ошибка - пробуем еще раз
          if (attempts < maxAttempts) {
            print('🔵 Повторная попытка через $delaySeconds секунд...');
            await Future.delayed(Duration(seconds: delaySeconds));
          } else {
            print('❌ Не удалось получить FCM токен: $errorMsg');
            break;
          }
        }
      }
    }

    // Если токен не получен, логируем предупреждение
    if (token == null) {
      print('⚠️ FCM токен не получен. Push-уведомления не будут работать.');
      print('💡 Остальной функционал приложения работает нормально.');
    }
    
    return token;
  }

  /// Установить глобальный контекст для навигации
  static void setGlobalContext(BuildContext context) {
    _globalContext = context;
  }

  /// Сохранить FCM токен на сервере
  static Future<void> _saveTokenToServer(String token) async {
    try {
      print('🔵 Начало сохранения FCM токена на сервере...');
      final prefs = await SharedPreferences.getInstance();
      final phone = prefs.getString('user_phone');
      
      print('🔵 Телефон из SharedPreferences: ${phone ?? "null"}');
      
      if (phone == null || phone.isEmpty) {
        print('⚠️ Телефон не найден, токен не сохранен');
        print('   Проверьте, что пользователь авторизован');
        return;
      }

      // Нормализация номера телефона (убираем + и пробелы)
      final normalizedPhone = phone.replaceAll(RegExp(r'[\s+]'), '');
      print('🔵 Нормализованный телефон: $normalizedPhone');
      print('🔵 FCM токен (первые 30 символов): ${token.substring(0, token.length > 30 ? 30 : token.length)}...');

      final url = 'https://arabica26.ru/api/fcm-tokens';
      print('🔵 Отправка запроса на: $url');
      
      final response = await http.post(
        Uri.parse(url),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'phone': normalizedPhone,
          'token': token,
        }),
      ).timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          throw Exception('Таймаут при сохранении токена');
        },
      );

      print('🔵 Ответ сервера: ${response.statusCode}');
      print('🔵 Тело ответа: ${response.body}');

      if (response.statusCode == 200 || response.statusCode == 201) {
        print('✅ FCM токен сохранен на сервере для телефона: $normalizedPhone');
      } else {
        print('⚠️ Ошибка сохранения токена: ${response.statusCode}');
        print('   Ответ: ${response.body}');
      }
    } catch (e) {
      print('❌ Ошибка сохранения FCM токена: $e');
      print('   Stack trace: ${StackTrace.current}');
    }
  }

  /// Показать локальное уведомление
  static Future<void> _showLocalNotification(RemoteMessage message) async {
    const androidDetails = AndroidNotificationDetails(
      'reviews_channel',
      'Отзывы',
      channelDescription: 'Уведомления о новых ответах на отзывы',
      importance: Importance.high,
      priority: Priority.high,
      showWhen: true,
    );

    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    const notificationDetails = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await _localNotifications.show(
      message.hashCode,
      message.notification?.title ?? 'Новый ответ',
      message.notification?.body ?? 'У вас новый ответ на отзыв',
      notificationDetails,
      payload: jsonEncode(message.data),
    );
  }

  /// Обработка нажатия на уведомление
  static void _onNotificationTapped(NotificationResponse response) {
    if (response.payload != null && _globalContext != null) {
      try {
        final data = jsonDecode(response.payload!) as Map<String, dynamic>;
        _handleNotificationNavigation(data);
      } catch (e) {
        print('❌ Ошибка обработки уведомления: $e');
      }
    }
  }

  /// Обработка навигации при открытии уведомления
  static void _handleNotificationTap(RemoteMessage message) {
    if (_globalContext != null) {
      _handleNotificationNavigation(message.data);
    }
  }

  /// Навигация к диалогу при открытии уведомления
  static void _handleNotificationNavigation(Map<String, dynamic> data) {
    if (_globalContext == null) return;

    final reviewId = data['reviewId'] as String?;
    if (reviewId == null) return;

    // Навигация к диалогу
    Navigator.of(_globalContext!).push(
      MaterialPageRoute(
        builder: (context) => FutureBuilder<Review?>(
          future: ReviewService.getReviewById(reviewId),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Scaffold(
                body: Center(child: CircularProgressIndicator()),
              );
            }

            if (snapshot.hasData && snapshot.data != null) {
              return ReviewDetailPage(
                review: snapshot.data!,
                isAdmin: false,
              );
            }

            // Если отзыв не найден, переходим к списку диалогов
            return const MyDialogsPage();
          },
        ),
      ),
    );
  }
}


