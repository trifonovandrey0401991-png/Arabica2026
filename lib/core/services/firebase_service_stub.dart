import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import '../utils/logger.dart';

/// Заглушки для типов Firebase на веб-платформе
class FirebaseMessaging {
  static FirebaseMessaging get instance => FirebaseMessaging();
  
  Future<NotificationSettings> requestPermission({
    bool? alert,
    bool? badge,
    bool? sound,
    bool? provisional,
  }) async {
    return NotificationSettings();
  }
  
  Future<String?> getToken() async => null;
  
  Stream<String> get onTokenRefresh => const Stream<String>.empty();
  Stream<RemoteMessage> get onMessage => const Stream<RemoteMessage>.empty();
  Stream<RemoteMessage> get onMessageOpenedApp => const Stream<RemoteMessage>.empty();
  
  Future<RemoteMessage?> getInitialMessage() async => null;
}

class NotificationSettings {
  AuthorizationStatus get authorizationStatus => AuthorizationStatus.denied;
}

enum AuthorizationStatus {
  authorized,
  denied,
  notDetermined,
  provisional,
}

class RemoteMessage {
  RemoteNotification? get notification => null;
  Map<String, dynamic> get data => {};
}

class RemoteNotification {
  String? get title => null;
  String? get body => null;
}

/// Заглушка FirebaseService для веб-платформы
/// Firebase Messaging не поддерживается на веб-платформе
class FirebaseService {
  static final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  static final FlutterLocalNotificationsPlugin _localNotifications = 
      FlutterLocalNotificationsPlugin();

  static bool _initialized = false;
  static BuildContext? _globalContext;

  /// Инициализация Firebase Messaging (заглушка для веб)
  static Future<void> initialize() async {
    if (_initialized) return;
    Logger.warning('Firebase Messaging недоступен на веб-платформе');
    Logger.info('Push-уведомления будут работать только на мобильных устройствах');
    _initialized = true;
  }

  /// Установить глобальный контекст для навигации
  static void setGlobalContext(BuildContext context) {
    _globalContext = context;
  }

  /// Сохранить FCM токен на сервере (заглушка)
  static Future<void> _saveTokenToServer(String token) async {
    // Заглушка - ничего не делает на веб
  }

  /// Показать локальное уведомление (заглушка)
  static Future<void> _showLocalNotification(RemoteMessage message) async {
    // Заглушка - ничего не делает на веб
  }

  /// Обработка нажатия на уведомление (заглушка)
  static void _onNotificationTapped(NotificationResponse response) {
    // Заглушка - ничего не делает на веб
  }

  /// Обработка навигации при открытии уведомления (заглушка)
  static void _handleNotificationTap(RemoteMessage message) {
    // Заглушка - ничего не делает на веб
  }

  /// Навигация к диалогу при открытии уведомления (заглушка)
  static void _handleNotificationNavigation(Map<String, dynamic> data) {
    // Заглушка - ничего не делает на веб
  }
}
