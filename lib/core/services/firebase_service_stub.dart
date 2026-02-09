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
  static bool _initialized = false;

  /// Инициализация Firebase Messaging (заглушка для веб)
  static Future<void> initialize() async {
    if (_initialized) return;
    Logger.warning('Firebase Messaging недоступен на веб-платформе');
    Logger.info('Push-уведомления будут работать только на мобильных устройствах');
    _initialized = true;
  }

  /// Установить глобальный контекст для навигации
  static void setGlobalContext(BuildContext context) {
    // Заглушка - ничего не делает на веб
  }
}
