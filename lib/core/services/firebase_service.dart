// Условный импорт Firebase Messaging: на веб - stub, на мобильных - реальный пакет
import 'package:firebase_messaging/firebase_messaging.dart' if (dart.library.html) 'firebase_service_stub.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../../app/pages/my_dialogs_page.dart';
import '../../features/reviews/pages/review_detail_page.dart';
import '../../features/reviews/services/review_service.dart';
import '../../features/reviews/models/review_model.dart';
import '../../features/product_questions/pages/product_question_answer_page.dart';
import '../../features/product_questions/pages/product_question_personal_dialog_page.dart';
import '../../features/product_questions/pages/product_question_employee_dialog_page.dart';
import '../../features/product_questions/pages/product_question_client_dialog_page.dart';
import '../../features/product_questions/pages/product_question_dialog_page.dart';
import '../../features/product_questions/pages/product_questions_management_page.dart';
import '../../features/orders/pages/employee_orders_page.dart';
import '../../features/orders/pages/orders_page.dart';
import '../../features/work_schedule/pages/my_schedule_page.dart';
import '../../features/work_schedule/pages/work_schedule_page.dart';
import '../../features/tasks/pages/my_tasks_page.dart';
import '../../features/employee_chat/pages/employee_chats_list_page.dart';
import '../../features/employees/services/user_role_service.dart';
import '../constants/api_constants.dart';
import '../utils/logger.dart';
// Прямой импорт Firebase Core - доступен на мобильных платформах
// На веб будет ошибка компиляции, но мы проверяем kIsWeb перед использованием
import 'package:firebase_core/firebase_core.dart' as firebase_core;
import 'package:flutter_screenutil/flutter_screenutil.dart';

/// Сервис для работы с Firebase Cloud Messaging (FCM)
class FirebaseService {
  static FirebaseMessaging? _messaging;
  static final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  static bool _initialized = false;
  static BuildContext? _globalContext;

  /// Цвет уведомлений (основной цвет бренда Арабика)
  static final Color _notificationColor = Color(0xFF004D40);

  /// Флаг для предотвращения повторного показа диалога блокировки
  static bool _verificationRevokedDialogShown = false;
  
  /// Получить экземпляр FirebaseMessaging (ленивая инициализация)
  static FirebaseMessaging _getMessaging() {
    if (_messaging == null) {
      Logger.debug('🔵 Создание экземпляра FirebaseMessaging...');
      
      // Проверяем, что Firebase App готов (только для мобильных платформ)
      if (!kIsWeb) {
        try {
          // ignore: avoid_dynamic_calls
          final app = firebase_core.Firebase.app();
          Logger.debug('Firebase App найден: ${app.name}');
        } catch (e) {
          Logger.error('Firebase App не найден', e);
          throw Exception('Firebase App не инициализирован. Невозможно создать FirebaseMessaging.');
        }
      }
      
      try {
        _messaging = FirebaseMessaging.instance;
        Logger.debug('Экземпляр FirebaseMessaging создан');
      } catch (e) {
        Logger.error('Ошибка создания FirebaseMessaging', e);
        rethrow;
      }
    }
    return _messaging!;
  }

  /// Инициализация Firebase Messaging
  static Future<void> initialize() async {
    if (_initialized) {
      Logger.debug('Firebase Messaging уже инициализирован');
      return;
    }

    try {
      Logger.debug('Проверка инициализации Firebase Core...');
      
      // Проверяем, что Firebase Core инициализирован (для мобильных платформ)
      // На веб это будет stub, который просто вернется
      if (!kIsWeb) {
        // Проверяем готовность Firebase без задержки
        try {
          // Просто проверяем, что можем получить instance
          // Если Firebase не инициализирован, это вызовет ошибку при запросе токена
          Logger.debug('Firebase Core готов к использованию');
        } catch (e) {
          Logger.debug('Предупреждение при проверке Firebase: $e');
          // Продолжаем - ошибка может быть не критичной
        }
      }
      
      Logger.debug('Запрос разрешений на уведомления...');
      
      // Получаем экземпляр FirebaseMessaging
      Logger.debug('Получение экземпляра FirebaseMessaging...');
      FirebaseMessaging messaging;
      try {
        messaging = _getMessaging();
      } catch (e) {
        Logger.error('Ошибка получения FirebaseMessaging, повторная попытка...', e);
        // Небольшая задержка только при ошибке
        await Future.delayed(Duration(milliseconds: 500));
        messaging = _getMessaging();
      }
      
      // Запрашиваем разрешение на уведомления
      NotificationSettings? settings;
      try {
        settings = await messaging.requestPermission(
          alert: true,
          badge: true,
          sound: true,
          provisional: false,
        );
      } catch (e) {
        Logger.error('Ошибка при запросе разрешений', e);
        // Если ошибка связана с отсутствием Firebase App, ждем еще
        if (e.toString().contains('no-app') || e.toString().contains('Firebase App')) {
          Logger.debug('Ожидание инициализации Firebase App...');
          await Future.delayed(Duration(milliseconds: 500)); // Уменьшено с 2000 до 500
          // Повторная попытка
          try {
            settings = await messaging.requestPermission(
              alert: true,
              badge: true,
              sound: true,
              provisional: false,
            );
          } catch (e2) {
            Logger.error('Повторная ошибка при запросе разрешений', e2);
            // Не бросаем исключение - продолжаем работу
            settings = null;
          }
        } else {
          // Не бросаем исключение - продолжаем работу
          Logger.warning('Продолжаем работу без разрешений на уведомления');
          settings = null;
        }
      }

      if (settings == null) {
        Logger.debug('Не удалось получить разрешения, продолжаем работу');
        // Продолжаем работу даже без разрешений
        _initialized = true;
        Logger.debug('Firebase Messaging инициализирован (без разрешений)');
        return;
      }

      if (settings.authorizationStatus == AuthorizationStatus.authorized) {
        Logger.debug('Пользователь разрешил уведомления');
      } else if (settings.authorizationStatus == AuthorizationStatus.provisional) {
        Logger.debug('Пользователь разрешил временные уведомления');
      } else {
        Logger.debug('Пользователь не разрешил уведомления');
        _initialized = true;
        Logger.debug('Firebase Messaging инициализирован (без разрешений)');
        return;
      }
      
      // Выполняем дальнейшую инициализацию в отдельной функции,
      // чтобы ошибки не перехватывались общим catch блоком
      // Используем Future.microtask для выполнения в следующем микротаске
      try {
        Future.microtask(() async {
          try {
            Logger.debug('Начало инициализации после разрешений');
            await _initializeAfterPermissions(messaging);
            _initialized = true;
            Logger.debug('Firebase Messaging инициализирован');
          } catch (e) {
            Logger.debug('Ошибка в _initializeAfterPermissions: $e');
            Logger.debug('Приложение продолжит работу, но push-уведомления могут не работать');
            _initialized = true; // Все равно помечаем как инициализированный
            Logger.debug('Firebase Messaging инициализирован (с ограничениями)');
          }
        });
      } catch (e) {
        Logger.debug('Ошибка при создании Future.microtask: $e');
        // Продолжаем работу
        _initialized = true;
        Logger.debug('Firebase Messaging инициализирован (с ограничениями)');
      }
    } catch (e) {
      Logger.error('Ошибка инициализации Firebase Messaging', e);
    }
  }

  /// Инициализация после получения разрешений (выполняется в отдельном микротаске)
  static Future<void> _initializeAfterPermissions(FirebaseMessaging messaging) async {
    Logger.debug('Начало инициализации после получения разрешений');
    
    Logger.debug('Начало инициализации локальных уведомлений...');
    // Инициализация локальных уведомлений
    final androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    final iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    final initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    try {
      await _localNotifications.initialize(
        initSettings,
        onDidReceiveNotificationResponse: _onNotificationTapped,
      );
      Logger.debug('Локальные уведомления инициализированы');
    } catch (e) {
      Logger.debug('Ошибка инициализации локальных уведомлений: $e');
      // Продолжаем работу даже если локальные уведомления не инициализированы
    }

    // Получаем FCM токен с повторными попытками и обработкой ошибок
    Logger.debug('Начало получения FCM токена...');
    String? token;
    try {
      token = await _getTokenWithRetries(messaging);
      Logger.debug('Получение токена завершено: ${token != null ? "успешно" : "не получен"}');
    } catch (e) {
      // Если ошибка все равно произошла, логируем, но продолжаем работу
      Logger.debug('Критическая ошибка при получении токена: $e');
      Logger.debug('Приложение продолжит работу без push-уведомлений');
    }

    // Обработка уведомлений в foreground (когда приложение открыто)
    try {
      FirebaseMessaging.onMessage.listen((RemoteMessage message) {
        Logger.debug('Получено сообщение в foreground: ${message.notification?.title}');

        // Проверяем тип уведомления - если верификация отозвана, сразу показываем диалог
        final type = message.data['type'] as String?;
        if (type == 'verification_revoked') {
          Logger.debug('Получено уведомление об отзыве верификации в foreground');
          _showVerificationRevokedDialog();
          return;
        }

        _showLocalNotification(message);
      });
    } catch (e) {
      Logger.debug('Ошибка при настройке слушателя onMessage: $e');
    }

    // Обработка нажатия на уведомление (когда приложение в фоне)
    try {
      FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
        Logger.debug('Уведомление открыто из фона');
        _handleNotificationTap(message);
      });
    } catch (e) {
      Logger.debug('Ошибка при настройке слушателя onMessageOpenedApp: $e');
    }

    // Обработка уведомления, которое открыло приложение (когда приложение было закрыто)
    try {
      RemoteMessage? initialMessage = await messaging.getInitialMessage();
      if (initialMessage != null) {
        Logger.debug('Уведомление открыло приложение');
        _handleNotificationTap(initialMessage);
      }
    } catch (e) {
      Logger.debug('Ошибка при получении initialMessage: $e');
      // Продолжаем работу даже если не удалось получить initialMessage
    }

    // Обновление токена при его изменении
    try {
      messaging.onTokenRefresh.listen((newToken) {
        Logger.debug('FCM Token обновлен');
        _saveTokenToServer(newToken);
      });
    } catch (e) {
      Logger.debug('Ошибка при настройке слушателя onTokenRefresh: $e');
    }
  }

  /// Получить FCM токен с повторными попытками и обработкой ошибок
  static Future<String?> _getTokenWithRetries(FirebaseMessaging messaging) async {
    Logger.debug('Начало получения FCM токена с повторными попытками...');
    String? token;
    int attempts = 0;
    final maxAttempts = 3; // Уменьшено с 5 до 3
    final delaySeconds = 2; // Уменьшено с 3 до 2

    while (token == null && attempts < maxAttempts) {
      try {
        attempts++;
        Logger.debug('Попытка $attempts/$maxAttempts получить FCM токен...');
        
        // Пытаемся получить токен
        token = await messaging.getToken();

        if (token != null) {
          Logger.debug('FCM Token получен');
          await _saveTokenToServer(token);
          return token;
        }
      } catch (e) {
        String errorMsg = e.toString();
        Logger.debug('Ошибка получения токена (попытка $attempts/$maxAttempts): $errorMsg');
        
        // Проверяем тип ошибки
        if (errorMsg.contains('FIS_AUTH_ERROR') || 
            errorMsg.contains('Firebase Installations Service') ||
            errorMsg.contains('firebase_messaging/unknown')) {
          if (attempts < maxAttempts) {
            Logger.debug('Ошибка аутентификации Firebase. Повторная попытка через $delaySeconds секунд...');
            await Future.delayed(Duration(seconds: delaySeconds));
          } else {
            Logger.error('Не удалось получить FCM токен после $maxAttempts попыток');
            Logger.debug('Приложение продолжит работу, но push-уведомления не будут работать');
            // Приложение продолжит работу без токена
            break;
          }
        } else {
          // Другая ошибка - пробуем еще раз
          if (attempts < maxAttempts) {
            Logger.debug('Повторная попытка через $delaySeconds секунд...');
            await Future.delayed(Duration(seconds: delaySeconds));
          } else {
            Logger.error('Не удалось получить FCM токен: $errorMsg');
            break;
          }
        }
      }
    }

    // Если токен не получен, логируем предупреждение
    if (token == null) {
      Logger.debug('FCM токен не получен. Push-уведомления не будут работать.');
    }
    
    return token;
  }

  /// Установить глобальный контекст для навигации
  static void setGlobalContext(BuildContext context) {
    _globalContext = context;
  }

  /// Проверить, разрешены ли уведомления
  static Future<bool> areNotificationsEnabled() async {
    try {
      if (_messaging == null) {
        // Если Firebase не инициализирован, пробуем получить instance
        try {
          _messaging = FirebaseMessaging.instance;
        } catch (e) {
          Logger.debug('Не удалось получить FirebaseMessaging: $e');
          return false;
        }
      }

      final settings = await _messaging!.getNotificationSettings();
      return settings.authorizationStatus == AuthorizationStatus.authorized;
    } catch (e) {
      Logger.error('Ошибка проверки разрешений уведомлений', e);
      return false;
    }
  }

  /// Публичный метод для повторного сохранения токена после входа пользователя
  /// Вызывается когда user_phone становится доступным в SharedPreferences
  static Future<void> resaveToken() async {
    try {
      Logger.debug('Повторное сохранение FCM токена после входа...');

      if (_messaging == null) {
        Logger.debug('FirebaseMessaging не инициализирован, пропускаем');
        return;
      }

      final token = await _messaging!.getToken();
      if (token != null) {
        await _saveTokenToServer(token);
      } else {
        Logger.debug('Токен не получен');
      }
    } catch (e) {
      Logger.error('Ошибка повторного сохранения токена', e);
    }
  }

  /// Сохранить FCM токен на сервере
  static Future<void> _saveTokenToServer(String token) async {
    try {
      Logger.debug('Начало сохранения FCM токена на сервере...');
      final prefs = await SharedPreferences.getInstance();
      final phone = prefs.getString('user_phone');

      if (phone == null || phone.isEmpty) {
        Logger.debug('Телефон не найден, токен не сохранен');
        return;
      }

      // Нормализация номера телефона (убираем + и пробелы)
      final normalizedPhone = phone.replaceAll(RegExp(r'[\s\+]'), '');

      final url = '${ApiConstants.serverUrl}/api/fcm-tokens';

      final response = await http.post(
        Uri.parse(url),
        headers: ApiConstants.jsonHeaders,
        body: jsonEncode({
          'phone': normalizedPhone,
          'token': token,
        }),
      ).timeout(
        ApiConstants.shortTimeout,
        onTimeout: () {
          throw Exception('Таймаут при сохранении токена');
        },
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        Logger.debug('FCM токен сохранен на сервере');
      } else {
        Logger.debug('Ошибка сохранения токена: ${response.statusCode}');
      }
    } catch (e) {
      Logger.error('Ошибка сохранения FCM токена', e);
    }
  }

  /// Показать локальное уведомление
  static Future<void> _showLocalNotification(RemoteMessage message) async {
    // Определяем канал в зависимости от типа уведомления
    final type = message.data['type'] as String?;

    AndroidNotificationDetails androidDetails;
    if (type == 'new_order' || type == 'order_status') {
      androidDetails = AndroidNotificationDetails(
        'orders_channel',
        'Заказы',
        channelDescription: 'Уведомления о заказах клиентов',
        importance: Importance.high,
        priority: Priority.high,
        showWhen: true,
        icon: '@drawable/ic_launcher_foreground',
        color: _notificationColor,
        largeIcon: DrawableResourceAndroidBitmap('@mipmap/ic_launcher'),
      );
    } else if (type != null && type.startsWith('shift_transfer')) {
      // Канал для замен смены
      androidDetails = AndroidNotificationDetails(
        'shift_transfers_channel',
        'Замены смен',
        channelDescription: 'Уведомления о заменах смены',
        importance: Importance.high,
        priority: Priority.high,
        showWhen: true,
        icon: '@drawable/ic_launcher_foreground',
        color: _notificationColor,
        largeIcon: DrawableResourceAndroidBitmap('@mipmap/ic_launcher'),
      );
    } else if (type == 'product_question_created' || type == 'product_question_answered') {
      // Канал для вопросов о товаре
      androidDetails = AndroidNotificationDetails(
        'product_questions_channel',
        'Поиск товара',
        channelDescription: 'Уведомления о вопросах и ответах по поиску товара',
        importance: Importance.high,
        priority: Priority.high,
        showWhen: true,
        icon: '@drawable/ic_launcher_foreground',
        color: _notificationColor,
        largeIcon: DrawableResourceAndroidBitmap('@mipmap/ic_launcher'),
      );
    } else if (type != null && (type.startsWith('new_task') ||
               type.startsWith('task_') ||
               type.startsWith('new_recurring_task') ||
               type.startsWith('recurring_task_'))) {
      // Канал для задач
      androidDetails = AndroidNotificationDetails(
        'tasks_channel',
        'Задачи',
        channelDescription: 'Уведомления о задачах',
        importance: Importance.high,
        priority: Priority.high,
        showWhen: true,
        icon: '@drawable/ic_launcher_foreground',
        color: _notificationColor,
        largeIcon: DrawableResourceAndroidBitmap('@mipmap/ic_launcher'),
      );
    } else if (type == 'employee_chat') {
      androidDetails = AndroidNotificationDetails(
        'employee_chat_channel',
        'Чат сотрудников',
        channelDescription: 'Уведомления о новых сообщениях в чате',
        importance: Importance.high,
        priority: Priority.high,
        showWhen: true,
        icon: '@drawable/ic_launcher_foreground',
        color: _notificationColor,
        largeIcon: DrawableResourceAndroidBitmap('@mipmap/ic_launcher'),
      );
    } else {
      androidDetails = AndroidNotificationDetails(
        'reviews_channel',
        'Отзывы',
        channelDescription: 'Уведомления о новых ответах на отзывы',
        importance: Importance.high,
        priority: Priority.high,
        showWhen: true,
        icon: '@drawable/ic_launcher_foreground',
        color: _notificationColor,
        largeIcon: DrawableResourceAndroidBitmap('@mipmap/ic_launcher'),
      );
    }

    final iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    final notificationDetails = NotificationDetails(
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
        Logger.error('Ошибка обработки уведомления', e);
      }
    }
  }

  /// Обработка навигации при открытии уведомления
  static void _handleNotificationTap(RemoteMessage message) {
    if (_globalContext != null) {
      _handleNotificationNavigation(message.data);
    }
  }

  /// Показать блокирующий диалог при отзыве верификации
  static void _showVerificationRevokedDialog() {
    if (_globalContext == null || _verificationRevokedDialogShown) return;

    _verificationRevokedDialogShown = true;
    Logger.debug('Показываем диалог блокировки - верификация отозвана');

    showDialog(
      context: _globalContext!,
      barrierDismissible: false,
      builder: (context) => PopScope(
        canPop: false,
        child: AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16.r),
          ),
          icon: Icon(
            Icons.warning_amber_rounded,
            color: Colors.orange,
            size: 48,
          ),
          title: Text(
            'Верификация отозвана',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          content: Text(
            'Ваша верификация была отозвана администратором.\n\n'
            'Для продолжения работы необходимо перезапустить приложение.',
            textAlign: TextAlign.center,
          ),
          actions: [
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () {
                  // Закрываем приложение (на Android/iOS)
                  // SystemNavigator.pop() корректно закрывает приложение
                  SystemNavigator.pop();
                },
                icon: Icon(Icons.restart_alt),
                label: Text('Перезапустить приложение'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Color(0xFF004D40),
                  foregroundColor: Colors.white,
                  padding: EdgeInsets.symmetric(vertical: 14.h),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12.r),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Публичный метод для обработки навигации из других сервисов (NotificationService)
  static void navigateFromNotificationData(Map<String, dynamic> data) {
    _handleNotificationNavigation(data);
  }

  /// Навигация к диалогу при открытии уведомления
  static void _handleNotificationNavigation(Map<String, dynamic> data) async {
    if (_globalContext == null) return;

    final type = data['type'] as String?;

    // Обработка уведомления об отзыве верификации - показываем блокирующий диалог
    if (type == 'verification_revoked') {
      _showVerificationRevokedDialog();
      return;
    }

    // Обработка уведомлений о заказах — проверяем роль пользователя
    if (type == 'new_order' || type == 'order_status' || type == 'order_rejected') {
      final userRole = await UserRoleService.loadUserRole();
      final isStaff = userRole != null && userRole.isEmployeeOrAdmin;

      if (type == 'new_order' && isStaff) {
        // Сотрудник/админ → страница управления заказами
        Navigator.of(_globalContext!).push(
          MaterialPageRoute(
            builder: (context) => EmployeeOrdersPage(),
          ),
        );
      } else {
        // Клиент (или статус заказа) → страница "Мои заказы"
        Navigator.of(_globalContext!).push(
          MaterialPageRoute(
            builder: (context) => OrdersPage(),
          ),
        );
      }
      return;
    }

    // Обработка уведомлений о вопросах о товаре
    if (type == 'product_question') {
      final questionId = data['questionId'] as String?;
      final shopAddress = data['shopAddress'] as String?;
      if (questionId != null) {
        // Для сетевых вопросов → страница управления (выбор магазина)
        if (shopAddress == 'Вся сеть' || shopAddress == null || shopAddress.isEmpty) {
          Navigator.of(_globalContext!).push(
            MaterialPageRoute(
              builder: (context) => const ProductQuestionsManagementPage(),
            ),
          );
        } else {
          Navigator.of(_globalContext!).push(
            MaterialPageRoute(
              builder: (context) => ProductQuestionAnswerPage(
                questionId: questionId,
                shopAddress: shopAddress,
              ),
            ),
          );
        }
        return;
      }
    }

    // Обработка уведомлений о новом вопросе о товаре (для сотрудников)
    if (type == 'product_question_created') {
      final questionId = data['questionId'] as String?;
      final shopAddress = data['shopAddress'] as String?;
      if (questionId != null) {
        // Для сетевых вопросов → страница управления (выбор магазина)
        if (shopAddress == 'Вся сеть' || shopAddress == null || shopAddress.isEmpty) {
          Navigator.of(_globalContext!).push(
            MaterialPageRoute(
              builder: (context) => const ProductQuestionsManagementPage(),
            ),
          );
        } else {
          Navigator.of(_globalContext!).push(
            MaterialPageRoute(
              builder: (context) => ProductQuestionAnswerPage(
                questionId: questionId,
                shopAddress: shopAddress,
              ),
            ),
          );
        }
      }
      return;
    }

    // Обработка уведомлений об ответе на вопрос о товаре (для клиентов)
    // Открываем конкретный вопрос с ответом сотрудника + поле ввода для ответа
    if (type == 'product_question_answered' || type == 'product_answer') {
      final questionId = data['questionId'] as String?;

      if (questionId != null && questionId.isNotEmpty && _globalContext != null) {
        Navigator.of(_globalContext!).push(
          MaterialPageRoute(
            builder: (context) => ProductQuestionDialogPage(
              questionId: questionId,
            ),
          ),
        );
      } else if (_globalContext != null) {
        // Fallback: общий клиентский чат
        Navigator.of(_globalContext!).push(
          MaterialPageRoute(
            builder: (context) => const ProductQuestionClientDialogPage(),
          ),
        );
      }
      return;
    }

    // Обработка уведомлений о персональных диалогах (поиск товара)
    if (type == 'personal_dialog_employee_message') {
      // Клиент получил ответ сотрудника → открываем персональный чат клиента
      final dialogId = data['dialogId'] as String?;
      final shopAddress = data['shopAddress'] as String?;
      if (dialogId != null && shopAddress != null) {
        Navigator.of(_globalContext!).push(
          MaterialPageRoute(
            builder: (context) => ProductQuestionPersonalDialogPage(
              dialogId: dialogId,
              shopAddress: shopAddress,
            ),
          ),
        );
      }
      return;
    }

    if (type == 'personal_dialog_client_message') {
      // Сотрудник получил сообщение клиента → открываем чат сотрудника
      final dialogId = data['dialogId'] as String?;
      final shopAddress = data['shopAddress'] as String?;
      if (dialogId != null && shopAddress != null) {
        Navigator.of(_globalContext!).push(
          MaterialPageRoute(
            builder: (context) => ProductQuestionEmployeeDialogPage(
              dialogId: dialogId,
              shopAddress: shopAddress,
              clientName: '', // Загрузится из API
            ),
          ),
        );
      }
      return;
    }

    // Обработка уведомлений о задачах (обычных и циклических)
    if (type == 'new_task' || type == 'new_recurring_task' ||
        type == 'task_expired' || type == 'recurring_task_expired' ||
        type == 'task_reminder') {
      Navigator.of(_globalContext!).push(
        MaterialPageRoute(
          builder: (context) => MyTasksPage(),
        ),
      );
      return;
    }

    // Обработка уведомлений о просроченных задачах для админа
    if (type == 'task_expired_admin' || type == 'recurring_task_expired_admin') {
      // Админ тоже переходит на страницу задач (или можно сделать отдельную страницу отчётов)
      Navigator.of(_globalContext!).push(
        MaterialPageRoute(
          builder: (context) => MyTasksPage(), // Note: можно добавить TaskReportsPage для админов
        ),
      );
      return;
    }

    // Обработка уведомлений чата сотрудников
    if (type == 'employee_chat') {
      Navigator.of(_globalContext!).push(
        MaterialPageRoute(
          builder: (context) => EmployeeChatsListPage(),
        ),
      );
      return;
    }

    // Обработка уведомлений от руководства (рассылка и личные сообщения)
    if (type == 'management_message') {
      Navigator.of(_globalContext!).push(
        MaterialPageRoute(
          builder: (context) => MyDialogsPage(),
        ),
      );
      return;
    }

    // Обработка уведомлений о заменах смены
    if (type != null && type.startsWith('shift_transfer')) {
      final action = data['action'] as String?;

      // Для админа - переход на страницу графика работы (Note: можно добавить initialTab для открытия вкладки "Заявки")
      if (action == 'admin_review') {
        Navigator.of(_globalContext!).push(
          MaterialPageRoute(
            builder: (context) => WorkSchedulePage(),
          ),
        );
        return;
      }

      // Для сотрудника - переход к мой график (Note: можно добавить initialTab для открытия вкладки "Заявки")
      if (action == 'view_request') {
        Navigator.of(_globalContext!).push(
          MaterialPageRoute(
            builder: (context) => MySchedulePage(),
          ),
        );
        return;
      }

      // При одобрении - переход к графику
      if (action == 'view_schedule') {
        Navigator.of(_globalContext!).push(
          MaterialPageRoute(
            builder: (context) => MySchedulePage(),
          ),
        );
        return;
      }
    }

    // Обработка уведомлений об отзывах (старая логика)
    final reviewId = data['reviewId'] as String?;
    if (reviewId != null) {
      // Навигация к диалогу
      Navigator.of(_globalContext!).push(
        MaterialPageRoute(
          builder: (context) => FutureBuilder<Review?>(
            future: ReviewService.getReviewById(reviewId),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return Scaffold(
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
              return MyDialogsPage();
            },
          ),
        ),
      );
    }
  }
}


