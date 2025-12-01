import 'package:flutter/material.dart';
import 'my_dialogs_page.dart';
import 'review_detail_page.dart';
import 'review_service.dart';
import 'review_model.dart';

/// Заглушка FirebaseService для веб-платформы
/// Firebase Messaging не поддерживается на веб-платформе
class FirebaseService {
  static BuildContext? _globalContext;

  /// Инициализация Firebase Messaging (заглушка для веб)
  static Future<void> initialize() async {
    print('⚠️ Firebase Messaging недоступен на веб-платформе');
    print('   Push-уведомления будут работать только на мобильных устройствах');
  }

  /// Установить глобальный контекст для навигации
  static void setGlobalContext(BuildContext context) {
    _globalContext = context;
  }
}

