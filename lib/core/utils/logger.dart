import 'package:flutter/foundation.dart';

/// Утилита для логирования (только в debug режиме)
class Logger {
  static void debug(String message) {
    if (kDebugMode) {
      print(message);
    }
  }
  
  static void info(String message) {
    if (kDebugMode) {
      print('ℹ️ $message');
    }
  }
  
  static void warning(String message) {
    if (kDebugMode) {
      print('⚠️ $message');
    }
  }
  
  static void error(String message, [Object? error, StackTrace? stackTrace]) {
    // Ошибки всегда логируем, даже в production
    if (kDebugMode) {
      print('❌ $message');
      if (error != null) {
        print('   Ошибка: $error');
      }
      if (stackTrace != null) {
        print('   Stack trace: $stackTrace');
      }
    } else {
      // В production можно отправлять в crash reporting
      // FirebaseCrashlytics.instance.recordError(error, stackTrace);
    }
  }
  
  static void success(String message) {
    if (kDebugMode) {
      print('✅ $message');
    }
  }

  /// Маскирование телефона для логов (PII protection)
  /// '79001234567' → '7900***67'
  static String maskPhone(String? phone) {
    if (phone == null || phone.isEmpty) return '***';
    if (phone.length <= 6) return '***';
    return '${phone.substring(0, 4)}***${phone.substring(phone.length - 2)}';
  }
}







