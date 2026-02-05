import 'package:local_auth/local_auth.dart';
import 'package:flutter/services.dart';

/// Сервис биометрической авторизации
///
/// Работает с:
/// - Отпечатком пальца (Fingerprint)
/// - Распознаванием лица (Face ID)
/// - Другими биометрическими методами устройства
class BiometricService {
  static final BiometricService _instance = BiometricService._internal();
  factory BiometricService() => _instance;
  BiometricService._internal();

  final LocalAuthentication _auth = LocalAuthentication();

  /// Кэш доступности биометрии
  bool? _isAvailableCache;

  /// Проверяет, поддерживает ли устройство биометрию
  Future<bool> isAvailable() async {
    if (_isAvailableCache != null) {
      return _isAvailableCache!;
    }

    try {
      // Проверяем поддержку биометрии устройством
      final canCheckBiometrics = await _auth.canCheckBiometrics;
      final isDeviceSupported = await _auth.isDeviceSupported();

      _isAvailableCache = canCheckBiometrics && isDeviceSupported;
      return _isAvailableCache!;
    } on PlatformException {
      _isAvailableCache = false;
      return false;
    }
  }

  /// Получает список доступных типов биометрии
  Future<List<BiometricType>> getAvailableBiometrics() async {
    try {
      return await _auth.getAvailableBiometrics();
    } on PlatformException {
      return [];
    }
  }

  /// Проверяет, есть ли отпечаток пальца
  Future<bool> hasFingerprint() async {
    final biometrics = await getAvailableBiometrics();
    return biometrics.contains(BiometricType.fingerprint);
  }

  /// Проверяет, есть ли Face ID
  Future<bool> hasFaceId() async {
    final biometrics = await getAvailableBiometrics();
    return biometrics.contains(BiometricType.face);
  }

  /// Запрашивает биометрическую авторизацию
  ///
  /// [reason] - текст, объясняющий зачем нужна авторизация
  /// Возвращает true если авторизация успешна
  Future<bool> authenticate({
    required String reason,
    bool biometricOnly = false,
  }) async {
    try {
      final isAvailable = await this.isAvailable();
      if (!isAvailable) {
        return false;
      }

      final authenticated = await _auth.authenticate(
        localizedReason: reason,
        options: AuthenticationOptions(
          stickyAuth: true,
          biometricOnly: biometricOnly,
          useErrorDialogs: true,
          sensitiveTransaction: true,
        ),
      );

      return authenticated;
    } on PlatformException catch (e) {
      // Обрабатываем специфичные ошибки
      switch (e.code) {
        case 'NotAvailable':
          // Биометрия недоступна
          return false;
        case 'NotEnrolled':
          // Нет зарегистрированных биометрических данных
          return false;
        case 'LockedOut':
          // Слишком много попыток - временная блокировка
          return false;
        case 'PermanentlyLockedOut':
          // Полная блокировка - требуется PIN/пароль устройства
          return false;
        default:
          return false;
      }
    }
  }

  /// Отменяет текущую биометрическую авторизацию
  Future<void> cancelAuthentication() async {
    try {
      await _auth.stopAuthentication();
    } on PlatformException {
      // Игнорируем ошибки отмены
    }
  }

  /// Получает читаемое название доступного типа биометрии
  Future<String> getBiometricTypeName() async {
    final biometrics = await getAvailableBiometrics();

    if (biometrics.contains(BiometricType.face)) {
      return 'Face ID';
    } else if (biometrics.contains(BiometricType.fingerprint)) {
      return 'Отпечаток пальца';
    } else if (biometrics.contains(BiometricType.iris)) {
      return 'Сканер радужки';
    } else if (biometrics.isNotEmpty) {
      return 'Биометрия';
    } else {
      return 'Недоступно';
    }
  }

  /// Получает иконку для типа биометрии
  /// Возвращает код иконки Material Icons
  Future<int> getBiometricIconCode() async {
    final biometrics = await getAvailableBiometrics();

    if (biometrics.contains(BiometricType.face)) {
      return 0xe262; // face icon
    } else if (biometrics.contains(BiometricType.fingerprint)) {
      return 0xe90d; // fingerprint icon
    } else {
      return 0xe8e8; // security icon
    }
  }
}
