import 'package:flutter/foundation.dart' show kIsWeb;

/// Заглушка для Firebase App
class FirebaseApp {
  final String name;
  FirebaseApp(this.name);
}

/// Заглушка для firebase_core на веб-платформе
class Firebase {
  static Future<void> initializeApp() async {
    // Заглушка - ничего не делает на веб
    return;
  }
  
  /// Заглушка для получения Firebase App
  static FirebaseApp app([String name = '[DEFAULT]']) {
    throw UnsupportedError('Firebase App не доступен на этой платформе');
  }
}
