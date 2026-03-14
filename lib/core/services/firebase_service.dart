import 'dart:async';
import 'dart:io' show Platform;
// Условный импорт Firebase Messaging: на веб - stub, на мобильных - реальный пакет
import 'package:firebase_messaging/firebase_messaging.dart' if (dart.library.html) 'firebase_service_stub.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/material.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';
import 'package:flutter_callkit_incoming/entities/entities.dart';
import '../theme/app_colors.dart';
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
import '../../features/tasks/pages/task_reports_page.dart';
import '../../features/ai_training/pages/pending_codes_page.dart';
import '../../features/tests/pages/test_notifications_page.dart';
import '../../app/pages/reports_page.dart';
import '../../features/efficiency/pages/my_efficiency_page.dart';
import '../../features/shops/pages/shops_on_map_page.dart';
import '../../features/employee_chat/pages/employee_chats_list_page.dart';
import '../../features/employees/services/user_role_service.dart';
import '../../features/messenger/services/messenger_service.dart';
import '../../features/messenger/pages/messenger_chat_page.dart';
import '../../features/messenger/services/call_service.dart';
import '../../features/messenger/pages/call_page.dart';
import '../../features/auth/pages/device_approval_page.dart';
import '../constants/api_constants.dart';
import '../utils/logger.dart';
// Прямой импорт Firebase Core - доступен на мобильных платформах
// На веб будет ошибка компиляции, но мы проверяем kIsWeb перед использованием
import 'package:firebase_core/firebase_core.dart' as firebase_core;
import 'package:flutter_screenutil/flutter_screenutil.dart';

/// BUG-03: Top-level handler для фоновых сообщений (работает в отдельном изоляте)
/// Используется для обработки data-only сообщений и критических уведомлений
/// (например, verification_revoked) когда приложение не активно.
@pragma('vm:entry-point')
Future<void> _firebaseBackgroundMessageHandler(RemoteMessage message) async {
  final type = message.data['type'] as String?;

  // Для verification_revoked сохраняем флаг — при открытии приложения покажем диалог
  if (type == 'verification_revoked') {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('verification_revoked_pending', true);
    } catch (_) {
      // SharedPreferences может быть недоступен в изоляте — игнорируем
    }
  }

  // Для входящих звонков — показываем системный экран звонка через CallKit
  if (type == 'incoming_call') {
    try {
      final callId = message.data['callId'] as String? ?? '';
      final callerName = message.data['callerName'] as String? ?? 'Неизвестный';
      final callerPhone = message.data['callerPhone'] as String? ?? '';

      // Self-call protection: don't show CallKit if caller is the current user
      final prefs = await SharedPreferences.getInstance();
      final myPhone = prefs.getString('user_phone') ?? '';
      if (myPhone.isNotEmpty && callerPhone.isNotEmpty) {
        final myNorm = myPhone.replaceAll(RegExp(r'[^\d]'), '');
        final callerNorm = callerPhone.replaceAll(RegExp(r'[^\d]'), '');
        if (myNorm == callerNorm) return;
      }

      final params = CallKitParams(
        id: callId,
        nameCaller: callerName,
        appName: 'Арабика',
        handle: callerPhone,
        type: 0, // 0 = audio call
        textAccept: 'Ответить',
        textDecline: 'Отклонить',
        duration: 45000,
        extra: <String, dynamic>{
          'callId': callId,
          'callerPhone': callerPhone,
          'callerName': callerName,
          'offerSdp': message.data['offerSdp'] ?? '',
        },
        android: const AndroidParams(
          isCustomNotification: true,
          isShowLogo: false,
          ringtonePath: 'system_ringtone_default',
          backgroundColor: '#1A4D4D',
          actionColor: '#4CAF50',
          textColor: '#ffffff',
          incomingCallNotificationChannelName: 'Входящий звонок',
          missedCallNotificationChannelName: 'Пропущенный звонок',
          isShowCallID: false,
        ),
        missedCallNotification: const NotificationParams(
          showNotification: true,
          isShowCallback: true,
          subtitle: 'Пропущенный звонок',
          callbackText: 'Перезвонить',
        ),
      );

      await FlutterCallkitIncoming.showCallkitIncoming(params);

      // Save to SharedPreferences — used for cold start call handling + PIN bypass
      await prefs.setString('pending_incoming_call', jsonEncode(message.data));
      await prefs.setInt('pending_incoming_call_time', DateTime.now().millisecondsSinceEpoch);
    } catch (_) {}
  }
}

/// Сервис для работы с Firebase Cloud Messaging (FCM)
class FirebaseService {
  static FirebaseMessaging? _messaging;
  static final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  static bool _initialized = false;

  /// Global navigator key — never goes stale after navigation (replaces _globalContext)
  static final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

  // StreamSubscriptions stored for proper cancellation (Task 31: prevent memory leak)
  static StreamSubscription<RemoteMessage>? _onMessageSub;
  static StreamSubscription<RemoteMessage>? _onMessageOpenedAppSub;
  static StreamSubscription<String>? _onTokenRefreshSub;

  /// Callback для мгновенного обновления бейджа заказов при получении push
  static VoidCallback? onOrderPushReceived;

  /// Resolve messenger sender name from phone book (set by MessengerShellPage)
  static String? Function(String phone)? resolveMessengerName;

  /// Цвет уведомлений (основной цвет бренда Арабика)
  static final Color _notificationColor = AppColors.primaryGreen;

  /// Флаг для предотвращения повторного показа диалога блокировки
  static bool _verificationRevokedDialogShown = false;

  /// Буфер для уведомления, пришедшего до готовности navigatorKey (BUG-01: cold start)
  static Map<String, dynamic>? _pendingNotificationData;

  /// Кеш FCM токена — используется в resaveToken когда getToken() может вернуть null
  static String? _cachedFcmToken;
  
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

      // iOS: показывать уведомления даже когда приложение на переднем плане
      if (!kIsWeb && Platform.isIOS) {
        await messaging.setForegroundNotificationPresentationOptions(
          alert: true,
          badge: true,
          sound: true,
        );
        Logger.debug('iOS foreground notification options установлены');
      }

      // Инициализация слушателей и получение токена
      try {
        await _initializeAfterPermissions(messaging);
        _initialized = true;
        Logger.debug('Firebase Messaging полностью инициализирован');
      } catch (e) {
        Logger.debug('Ошибка в _initializeAfterPermissions: $e');
        Logger.debug('Приложение продолжит работу, но push-уведомления могут не работать');
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

    // BUG-03: регистрация background message handler
    try {
      FirebaseMessaging.onBackgroundMessage(_firebaseBackgroundMessageHandler);
      Logger.debug('Background message handler зарегистрирован');
    } catch (e) {
      Logger.debug('Ошибка регистрации background handler: $e');
    }

    // NotificationService.initialize() is always called first from main.dart and
    // registers the authoritative onDidReceiveNotificationResponse callback.
    // Calling _localNotifications.initialize() here a second time would overwrite
    // that callback with a less complete one (Task 32 fix: no double initialization).
    // _localNotifications.show() works without a second initialize() because the
    // native plugin is already initialized by NotificationService.
    Logger.debug('Локальные уведомления уже инициализированы через NotificationService');

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
      _onMessageSub?.cancel();
      _onMessageSub = FirebaseMessaging.onMessage.listen((RemoteMessage message) async {
        Logger.debug('Получено сообщение в foreground: ${message.notification?.title}');

        // Проверяем тип уведомления - если верификация отозвана, сразу показываем диалог
        final type = message.data['type'] as String?;
        if (type == 'verification_revoked') {
          Logger.debug('Получено уведомление об отзыве верификации в foreground');
          _showVerificationRevokedDialog();
          return;
        }

        // Входящий звонок в foreground (WS был отключён, FCM пришёл вместо него)
        if (type == 'incoming_call') {
          Logger.debug('📞 FCM incoming_call в foreground — показываем через CallKit + CallService');
          final callId = message.data['callId'] as String?;
          final callerPhone = message.data['callerPhone'] as String?;
          final callerName = message.data['callerName'] as String?;
          final offerSdp = message.data['offerSdp'] as String?;
          if (callId != null && callerPhone != null && offerSdp != null) {
            // Self-call protection
            final prefsCheck = await SharedPreferences.getInstance();
            final myPhone = (prefsCheck.getString('user_phone') ?? '').replaceAll(RegExp(r'[^\d]'), '');
            final callerNorm = callerPhone.replaceAll(RegExp(r'[^\d]'), '');
            if (myPhone.isNotEmpty && myPhone == callerNorm) {
              Logger.debug('📞 Self-call blocked in FCM foreground handler');
              return;
            }
            // Set up call state so answer can proceed
            CallService.instance.handleFcmIncomingCall(
              callId: callId,
              callerPhone: callerPhone,
              callerName: callerName ?? callerPhone,
              offerSdp: offerSdp,
            );
          }
          return;
        }

        // Мгновенное обновление бейджа заказов при получении push
        if (type == 'new_order' || type == 'order_unconfirmed' || type == 'order_status' || type == 'order_rejected') {
          onOrderPushReceived?.call();
        }

        _showLocalNotification(message);
      });
    } catch (e) {
      Logger.debug('Ошибка при настройке слушателя onMessage: $e');
    }

    // Обработка нажатия на уведомление (когда приложение в фоне)
    try {
      _onMessageOpenedAppSub?.cancel();
      _onMessageOpenedAppSub = FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
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
      _onTokenRefreshSub?.cancel();
      _onTokenRefreshSub = messaging.onTokenRefresh.listen((newToken) {
        Logger.debug('FCM Token обновлен');
        _cachedFcmToken = newToken;
        _saveTokenToServer(newToken);
      });
    } catch (e) {
      Logger.debug('Ошибка при настройке слушателя onTokenRefresh: $e');
    }
  }

  /// Получить FCM токен с повторными попытками и обработкой ошибок
  static Future<String?> _getTokenWithRetries(FirebaseMessaging messaging) async {
    Logger.debug('Начало получения FCM токена с повторными попытками...');

    // На iOS FCM требует APNS токен. Ждём его явно перед запросом FCM токена.
    if (!kIsWeb && Platform.isIOS) {
      Logger.debug('iOS: ожидание APNS токена...');
      String? apnsToken;
      for (int i = 0; i < 5; i++) {
        apnsToken = await messaging.getAPNSToken();
        if (apnsToken != null) {
          Logger.debug('iOS: APNS токен получен');
          break;
        }
        Logger.debug('iOS: APNS токен ещё не готов, попытка ${i + 1}/5...');
        await Future.delayed(const Duration(seconds: 2));
      }
      if (apnsToken == null) {
        Logger.warning('iOS: APNS токен не получен — FCM токен не будет доступен');
      }
    }

    String? token;
    int attempts = 0;
    final maxAttempts = 3;
    final delaySeconds = 2;

    while (token == null && attempts < maxAttempts) {
      try {
        attempts++;
        Logger.debug('Попытка $attempts/$maxAttempts получить FCM токен...');

        // Пытаемся получить токен
        token = await messaging.getToken();

        if (token != null) {
          Logger.debug('FCM Token получен');
          _cachedFcmToken = token;
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

  /// Установить глобальный контекст для навигации (сохранено для обратной совместимости)
  static void setGlobalContext(BuildContext context) {
    // Navigator is now resolved via navigatorKey — context argument no longer stored
    // BUG-01: обработать буферизованное уведомление из cold start
    if (_pendingNotificationData != null) {
      final data = _pendingNotificationData!;
      _pendingNotificationData = null;
      Logger.debug('Обработка буферизованного уведомления после установки контекста');
      Future.microtask(() => _handleNotificationNavigation(data));
    }
    // BUG-03: проверить флаг verification_revoked из фонового handler
    Future.microtask(() => checkPendingVerificationRevoked());
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
      final status = settings.authorizationStatus;
      Logger.debug('[Firebase] Notification status: $status');
      return status == AuthorizationStatus.authorized ||
          status == AuthorizationStatus.provisional;
    } catch (e) {
      Logger.error('Ошибка проверки разрешений уведомлений', e);
      return false;
    }
  }

  /// BUG-03: Проверить флаг verification_revoked, установленный в фоновом handler
  /// Вызывается при открытии приложения для показа диалога блокировки
  static Future<void> checkPendingVerificationRevoked() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final pending = prefs.getBool('verification_revoked_pending') ?? false;
      if (pending) {
        await prefs.remove('verification_revoked_pending');
        _showVerificationRevokedDialog();
      }
    } catch (e) {
      Logger.debug('Ошибка проверки pending verification_revoked: $e');
    }
  }

  /// Публичный метод для повторного сохранения токена после входа пользователя
  /// Вызывается когда user_phone становится доступным в SharedPreferences.
  /// Критически важен при смене устройства — сервер мог удалить старый токен.
  static Future<void> resaveToken() async {
    try {
      Logger.debug('Повторное сохранение FCM токена после входа...');

      // Проверяем, что phone доступен
      final prefs = await SharedPreferences.getInstance();
      final phone = prefs.getString('user_phone');
      if (phone == null || phone.isEmpty) {
        Logger.warning('resaveToken: user_phone не найден в SharedPreferences');
        return;
      }
      Logger.debug('resaveToken: phone найден (${Logger.maskPhone(phone)})');

      // Если messaging не инициализирован — пробуем получить инстанс
      if (_messaging == null) {
        try {
          _messaging = FirebaseMessaging.instance;
          Logger.debug('FirebaseMessaging инстанс получен в resaveToken');
        } catch (e) {
          Logger.debug('FirebaseMessaging недоступен: $e');
          return;
        }
      }

      // На iOS ждём APNS токен перед запросом FCM токена
      if (!kIsWeb && Platform.isIOS) {
        String? apnsToken = await _messaging!.getAPNSToken();
        if (apnsToken == null) {
          Logger.debug('resaveToken: APNS токен не готов, ждём...');
          for (int i = 0; i < 3; i++) {
            await Future.delayed(const Duration(seconds: 2));
            apnsToken = await _messaging!.getAPNSToken();
            if (apnsToken != null) break;
          }
          if (apnsToken == null) {
            Logger.warning('resaveToken: APNS токен не получен — FCM недоступен');
          }
        }
      }

      String? token = await _messaging!.getToken();

      // Если getToken вернул null — используем кешированный токен
      if (token == null && _cachedFcmToken != null) {
        Logger.debug('resaveToken: getToken() вернул null, используем кешированный токен');
        token = _cachedFcmToken;
      }

      if (token != null) {
        _cachedFcmToken = token;
        Logger.debug('FCM токен получен для пересохранения');
        await _saveTokenToServer(token);
      } else {
        Logger.warning('FCM токен не получен при resaveToken (и кеш пуст)');
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

    // Global mute check for messenger notifications (sound off, notification still shown)
    bool messengerMuted = false;
    if (type == 'messenger_message') {
      final convId = message.data['conversationId'] as String?;
      if (convId != null) {
        final prefs = await SharedPreferences.getInstance();
        if (convId.startsWith('private_') && (prefs.getBool('messenger_mute_chats') ?? false)) {
          messengerMuted = true;
        } else if (convId.startsWith('group_') && (prefs.getBool('messenger_mute_groups') ?? false)) {
          messengerMuted = true;
        } else if (convId.startsWith('channel_') && (prefs.getBool('messenger_mute_channels') ?? false)) {
          messengerMuted = true;
        }
      }
    }

    AndroidNotificationDetails androidDetails;
    if (type == 'new_order' || type == 'order_status' || type == 'order_unconfirmed' || type == 'order_rejected') {
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
    } else if (type == 'product_question_created' || type == 'product_question_answered' ||
               type == 'product_question' || type == 'product_answer' ||
               type == 'personal_dialog_employee_message' || type == 'personal_dialog_client_message') {
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
               type.startsWith('recurring_task_') ||
               type == 'test_assigned')) {
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
    } else if (type == 'report_notification' || type == 'report_status_changed' ||
               type == 'shift_confirmed' || type == 'recount_confirmed' ||
               type == 'shift_handover_penalty') {
      // Канал для отчётов (пересменка, пересчёт, сдать смену и т.д.)
      androidDetails = AndroidNotificationDetails(
        'reports_channel',
        'Отчёты',
        channelDescription: 'Уведомления об отчётах',
        importance: Importance.high,
        priority: Priority.high,
        showWhen: true,
        icon: '@drawable/ic_launcher_foreground',
        color: _notificationColor,
        largeIcon: DrawableResourceAndroidBitmap('@mipmap/ic_launcher'),
      );
    } else if (type == 'management_message') {
      // Канал для связи с руководством
      androidDetails = AndroidNotificationDetails(
        'management_channel',
        'Связь с руководством',
        channelDescription: 'Сообщения от руководства',
        importance: Importance.high,
        priority: Priority.high,
        showWhen: true,
        icon: '@drawable/ic_launcher_foreground',
        color: _notificationColor,
        largeIcon: DrawableResourceAndroidBitmap('@mipmap/ic_launcher'),
      );
    } else if (type == 'schedule_updated') {
      // Канал для графика работы
      androidDetails = AndroidNotificationDetails(
        'schedule_channel',
        'График работы',
        channelDescription: 'Уведомления об изменениях графика',
        importance: Importance.high,
        priority: Priority.high,
        showWhen: true,
        icon: '@drawable/ic_launcher_foreground',
        color: _notificationColor,
        largeIcon: DrawableResourceAndroidBitmap('@mipmap/ic_launcher'),
      );
    } else if (type == 'geofence' || type == 'attendance_reminder') {
      // Канал для геолокации и посещаемости
      androidDetails = AndroidNotificationDetails(
        'location_channel',
        'Геолокация',
        channelDescription: 'Уведомления о геолокации и посещаемости',
        importance: Importance.high,
        priority: Priority.high,
        showWhen: true,
        icon: '@drawable/ic_launcher_foreground',
        color: _notificationColor,
        largeIcon: DrawableResourceAndroidBitmap('@mipmap/ic_launcher'),
      );
    } else if (type == 'new_pending_codes') {
      // Канал для мастер-каталога
      androidDetails = AndroidNotificationDetails(
        'master_catalog_channel',
        'Мастер-каталог',
        channelDescription: 'Уведомления о новых кодах товаров',
        importance: Importance.high,
        priority: Priority.high,
        showWhen: true,
        icon: '@drawable/ic_launcher_foreground',
        color: _notificationColor,
        largeIcon: DrawableResourceAndroidBitmap('@mipmap/ic_launcher'),
      );
    } else if (type == 'messenger_message') {
      // Messenger channel with mute support
      androidDetails = AndroidNotificationDetails(
        messengerMuted ? 'messenger_silent_channel' : 'messenger_channel',
        messengerMuted ? 'Мессенджер (без звука)' : 'Мессенджер',
        channelDescription: 'Уведомления мессенджера',
        importance: messengerMuted ? Importance.low : Importance.high,
        priority: messengerMuted ? Priority.low : Priority.high,
        playSound: !messengerMuted,
        enableVibration: !messengerMuted,
        showWhen: true,
        icon: '@drawable/ic_launcher_foreground',
        color: _notificationColor,
        largeIcon: DrawableResourceAndroidBitmap('@mipmap/ic_launcher'),
      );
    } else if (message.data.containsKey('reviewId')) {
      // Уведомление об отзыве (legacy-формат без поля type)
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
    } else {
      // Общий канал для неизвестных типов
      androidDetails = AndroidNotificationDetails(
        'general_channel',
        'Общие уведомления',
        channelDescription: 'Прочие уведомления',
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
      presentSound: !messengerMuted,
    );

    final notificationDetails = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    // BUG-04: уникальный ID на основе messageId (уникален от FCM), не message.hashCode
    final notificationId = (message.messageId?.hashCode ??
        DateTime.now().microsecondsSinceEpoch).abs() % 2147483647;

    // For messenger messages, resolve sender name:
    // 1. Phone book name (if in contacts)
    // 2. Phone number (if private chat, not in contacts)
    // 3. Server-sent name (if group, not in contacts)
    String title = message.notification?.title ?? 'Уведомление';
    if (type == 'messenger_message' && resolveMessengerName != null) {
      final senderPhone = message.data['senderPhone'] as String?;
      if (senderPhone != null) {
        final bookName = resolveMessengerName!(senderPhone);
        if (bookName != null) {
          title = bookName;
        } else {
          final convId = message.data['conversationId'] as String?;
          if (convId != null && convId.startsWith('private_')) {
            title = senderPhone;
          }
          // group/channel → keep server-sent profile name
        }
      }
    }

    await _localNotifications.show(
      notificationId,
      title,
      message.notification?.body ?? '',
      notificationDetails,
      payload: jsonEncode(message.data),
    );
  }

  /// Обработка навигации при открытии уведомления
  static void _handleNotificationTap(RemoteMessage message) {
    if (navigatorKey.currentState != null) {
      _handleNotificationNavigation(message.data);
    }
  }

  /// Показать блокирующий диалог при отзыве верификации
  static void _showVerificationRevokedDialog() {
    if (navigatorKey.currentContext == null || _verificationRevokedDialogShown) return;

    _verificationRevokedDialogShown = true;
    Logger.debug('Показываем диалог блокировки - верификация отозвана');

    showDialog(
      context: navigatorKey.currentContext!,
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
                  backgroundColor: AppColors.primaryGreen,
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
    if (navigatorKey.currentState == null) {
      // BUG-01: сохраняем данные до готовности navigatorKey
      _pendingNotificationData = Map<String, dynamic>.from(data);
      Logger.debug('Navigator ещё не готов, уведомление сохранено в буфер');
      return;
    }

    try {
    final type = data['type'] as String?;

    // Обработка уведомления об отзыве верификации - показываем блокирующий диалог
    if (type == 'verification_revoked') {
      _showVerificationRevokedDialog();
      return;
    }

    // Обработка уведомлений о заказах — проверяем роль пользователя
    if (type == 'new_order' || type == 'order_status' || type == 'order_rejected' || type == 'order_unconfirmed') {
      final userRole = await UserRoleService.loadUserRole();
      final isStaff = userRole != null && userRole.isEmployeeOrAdmin;
      final nav = navigatorKey.currentState;
      if (nav == null) return;

      if ((type == 'new_order' || type == 'order_unconfirmed') && isStaff) {
        // Сотрудник/админ → страница управления заказами
        nav.push(
          MaterialPageRoute(
            builder: (context) => EmployeeOrdersPage(),
          ),
        );
      } else {
        // Клиент (или статус заказа) → страница "Мои заказы"
        nav.push(
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
          navigatorKey.currentState?.push(
            MaterialPageRoute(
              builder: (context) => const ProductQuestionsManagementPage(),
            ),
          );
        } else {
          navigatorKey.currentState?.push(
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
          navigatorKey.currentState?.push(
            MaterialPageRoute(
              builder: (context) => const ProductQuestionsManagementPage(),
            ),
          );
        } else {
          navigatorKey.currentState?.push(
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

      if (questionId != null && questionId.isNotEmpty && navigatorKey.currentState != null) {
        navigatorKey.currentState?.push(
          MaterialPageRoute(
            builder: (context) => ProductQuestionDialogPage(
              questionId: questionId,
            ),
          ),
        );
      } else if (navigatorKey.currentState != null) {
        // Fallback: общий клиентский чат
        navigatorKey.currentState?.push(
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
        navigatorKey.currentState?.push(
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
        navigatorKey.currentState?.push(
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
      navigatorKey.currentState?.push(
        MaterialPageRoute(
          builder: (context) => MyTasksPage(),
        ),
      );
      return;
    }

    // Обработка уведомлений о просроченных задачах для админа → отчёты по задачам
    if (type == 'task_expired_admin' || type == 'recurring_task_expired_admin') {
      navigatorKey.currentState?.push(
        MaterialPageRoute(
          builder: (context) => const TaskReportsPage(),
        ),
      );
      return;
    }

    // Обработка уведомлений чата сотрудников
    if (type == 'employee_chat') {
      navigatorKey.currentState?.push(
        MaterialPageRoute(
          builder: (context) => EmployeeChatsListPage(),
        ),
      );
      return;
    }

    // Обработка уведомлений от руководства (рассылка и личные сообщения)
    if (type == 'management_message') {
      navigatorKey.currentState?.push(
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
        navigatorKey.currentState?.push(
          MaterialPageRoute(
            builder: (context) => WorkSchedulePage(),
          ),
        );
        return;
      }

      // Для сотрудника - переход к мой график (Note: можно добавить initialTab для открытия вкладки "Заявки")
      if (action == 'view_request') {
        navigatorKey.currentState?.push(
          MaterialPageRoute(
            builder: (context) => MySchedulePage(),
          ),
        );
        return;
      }

      // При одобрении - переход к графику
      if (action == 'view_schedule') {
        navigatorKey.currentState?.push(
          MaterialPageRoute(
            builder: (context) => MySchedulePage(),
          ),
        );
        return;
      }
    }

    // Обработка уведомления об обновлении графика → мой график
    if (type == 'schedule_updated') {
      navigatorKey.currentState?.push(
        MaterialPageRoute(
          builder: (context) => MySchedulePage(),
        ),
      );
      return;
    }

    // Обработка уведомления о назначении теста → страница тестов
    if (type == 'test_assigned') {
      navigatorKey.currentState?.push(
        MaterialPageRoute(
          builder: (context) => const TestNotificationsPage(),
        ),
      );
      return;
    }

    // Обработка уведомления о новом отчёте (для админов) → страница отчётов
    if (type == 'report_notification') {
      navigatorKey.currentState?.push(
        MaterialPageRoute(
          builder: (context) => const ReportsPage(),
        ),
      );
      return;
    }

    // Обработка уведомления о новых кодах (для админов) → страница ожидающих кодов
    if (type == 'new_pending_codes') {
      navigatorKey.currentState?.push(
        MaterialPageRoute(
          builder: (context) => const PendingCodesPage(),
        ),
      );
      return;
    }

    // Обработка уведомлений о бонусах и штрафах → Моя эффективность
    if (type == 'bonus_penalty') {
      navigatorKey.currentState?.push(
        MaterialPageRoute(
          builder: (context) => const MyEfficiencyPage(),
        ),
      );
      return;
    }

    // Обработка уведомлений мессенджера → открываем конкретный чат
    if (type == 'messenger_message') {
      final conversationId = data['conversationId'] as String?;
      if (conversationId != null && conversationId.isNotEmpty) {
        _openMessengerConversation(conversationId);
      }
      return;
    }

    // Входящий звонок — открываем экран звонка
    if (type == 'incoming_call') {
      Logger.debug('📞 Открываем CallPage из уведомления');
      if (CallService.instance.state == CallState.incoming) {
        // WS или foreground FCM уже настроили состояние
        final call = CallService.instance.currentCall;
        if (call != null) {
          navigatorKey.currentState?.push(
            MaterialPageRoute(builder: (_) => CallPage(callInfo: call)),
          );
        }
      } else {
        // Приложение было закрыто — восстанавливаем из данных уведомления
        final callId = data['callId'] as String?;
        final callerPhone = data['callerPhone'] as String?;
        final callerName = data['callerName'] as String?;
        final offerSdp = data['offerSdp'] as String?;
        if (callId != null && callerPhone != null && offerSdp != null) {
          CallService.instance.handleFcmIncomingCall(
            callId: callId,
            callerPhone: callerPhone,
            callerName: callerName ?? callerPhone,
            offerSdp: offerSdp,
          );
          final call = CallService.instance.currentCall;
          if (call != null) {
            navigatorKey.currentState?.push(
              MaterialPageRoute(builder: (_) => CallPage(callInfo: call)),
            );
          }
        }
      }
      return;
    }

    // Геозона: клиент рядом с магазином → открываем карту кофеен
    if (type == 'geofence') {
      navigatorKey.currentState?.push(
        MaterialPageRoute(
          builder: (context) => const ShopsOnMapPage(),
        ),
      );
      return;
    }

    // Device binding: developer taps "device approval request" notification
    if (type == 'device_approval_request') {
      navigatorKey.currentState?.push(
        MaterialPageRoute(
          builder: (context) => const DeviceApprovalPage(),
        ),
      );
      return;
    }

    // Device binding: user's device was approved
    if (type == 'device_approved') {
      final ctx = navigatorKey.currentContext;
      if (ctx != null) {
        ScaffoldMessenger.of(ctx).showSnackBar(
          SnackBar(
            content: Text('Ваше устройство подтверждено! Войдите снова.'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 5),
          ),
        );
      }
      return;
    }

    // Device binding: user's device was rejected
    if (type == 'device_rejected') {
      final ctx = navigatorKey.currentContext;
      if (ctx != null) {
        ScaffoldMessenger.of(ctx).showSnackBar(
          SnackBar(
            content: Text('Запрос на новое устройство отклонён.'),
            backgroundColor: Colors.red,
            duration: Duration(seconds: 5),
          ),
        );
      }
      return;
    }

    // Обработка уведомлений об отзывах (старая логика)
    final reviewId = data['reviewId'] as String?;
    if (reviewId != null) {
      // Навигация к диалогу
      navigatorKey.currentState?.push(
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
    } catch (e) {
      Logger.debug('Ошибка навигации из push-уведомления: $e');
    }
  }

  /// Открыть конкретный чат мессенджера по conversationId
  static Future<void> _openMessengerConversation(String conversationId) async {
    final prefs = await SharedPreferences.getInstance();
    final myPhone = prefs.getString('user_phone') ?? '';
    final myName = prefs.getString('employee_name') ?? prefs.getString('user_name') ?? '';
    if (myPhone.isEmpty) return;

    final conversation = await MessengerService.getConversation(conversationId);
    if (conversation == null) return;

    if (navigatorKey.currentState == null) return;
    navigatorKey.currentState?.push(
      MaterialPageRoute(
        builder: (_) => MessengerChatPage(
          conversation: conversation,
          userPhone: myPhone,
          userName: myName,
        ),
      ),
    );
  }
}


