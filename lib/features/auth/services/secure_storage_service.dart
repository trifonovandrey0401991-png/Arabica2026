import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:crypto/crypto.dart';
import '../models/auth_session.dart';
import '../models/auth_credentials.dart';

/// Сервис для безопасного хранения данных авторизации
///
/// Использует flutter_secure_storage для шифрованного хранения:
/// - Токена сессии
/// - PIN-кода (в хешированном виде)
/// - ID устройства
/// - Биометрических настроек
class SecureStorageService {
  static final SecureStorageService _instance = SecureStorageService._internal();
  factory SecureStorageService() => _instance;
  SecureStorageService._internal();

  // Ключи для хранения
  static const String _sessionKey = 'auth_session';
  static const String _credentialsKey = 'auth_credentials';
  static const String _deviceIdKey = 'device_id';

  // Настройки хранилища с максимальной защитой
  final FlutterSecureStorage _storage = const FlutterSecureStorage(
    aOptions: AndroidOptions(
      encryptedSharedPreferences: true,
    ),
  );

  // ==================== СЕССИЯ ====================

  /// Сохраняет сессию в зашифрованное хранилище
  Future<void> saveSession(AuthSession session) async {
    final json = jsonEncode(session.toJson());
    await _storage.write(key: _sessionKey, value: json);
  }

  /// Загружает сессию из хранилища
  Future<AuthSession?> getSession() async {
    final json = await _storage.read(key: _sessionKey);
    if (json == null) return null;

    try {
      final map = jsonDecode(json) as Map<String, dynamic>;
      return AuthSession.fromJson(map);
    } catch (e) {
      // Если данные повреждены - удаляем
      await clearSession();
      return null;
    }
  }

  /// Удаляет сессию
  Future<void> clearSession() async {
    await _storage.delete(key: _sessionKey);
  }

  // ==================== PIN-КОД ====================

  /// Сохраняет учётные данные (PIN-код)
  Future<void> saveCredentials(AuthCredentials credentials) async {
    final json = jsonEncode(credentials.toJson());
    await _storage.write(key: _credentialsKey, value: json);
  }

  /// Загружает учётные данные
  Future<AuthCredentials?> getCredentials() async {
    final json = await _storage.read(key: _credentialsKey);
    if (json == null) return null;

    try {
      final map = jsonDecode(json) as Map<String, dynamic>;
      return AuthCredentials.fromJson(map);
    } catch (e) {
      return null;
    }
  }

  /// Удаляет учётные данные
  Future<void> clearCredentials() async {
    await _storage.delete(key: _credentialsKey);
  }

  /// Создаёт хеш PIN-кода с солью
  ///
  /// PIN не хранится в открытом виде - только хеш!
  /// Соль делает хеш уникальным даже для одинаковых PIN-кодов
  static String hashPin(String pin, String salt) {
    final data = utf8.encode(pin + salt);
    final hash = sha256.convert(data);
    return hash.toString();
  }

  /// Генерирует случайную соль для хеширования
  static String generateSalt() {
    final random = DateTime.now().microsecondsSinceEpoch.toString();
    final data = utf8.encode(random);
    final hash = sha256.convert(data);
    return hash.toString().substring(0, 32);
  }

  /// Проверяет PIN-код
  ///
  /// Возвращает true если PIN правильный
  Future<bool> verifyPin(String pin) async {
    final credentials = await getCredentials();
    if (credentials == null) return false;

    final inputHash = hashPin(pin, credentials.salt);
    return inputHash == credentials.pinHash;
  }

  /// Создаёт и сохраняет новые учётные данные с PIN-кодом
  Future<AuthCredentials> createCredentials(String pin) async {
    final salt = generateSalt();
    final pinHash = hashPin(pin, salt);

    final credentials = AuthCredentials(
      pinHash: pinHash,
      salt: salt,
      createdAt: DateTime.now(),
    );

    await saveCredentials(credentials);
    return credentials;
  }

  /// Обновляет счётчик неудачных попыток
  Future<void> incrementFailedAttempts() async {
    final credentials = await getCredentials();
    if (credentials == null) return;

    final newAttempts = credentials.failedAttempts + 1;
    DateTime? lockedUntil;

    // Блокировка после 5 неудачных попыток
    if (newAttempts >= AuthCredentials.maxFailedAttempts) {
      lockedUntil = DateTime.now().add(AuthCredentials.lockoutDuration);
    }

    final updated = credentials.copyWith(
      failedAttempts: newAttempts,
      lockedUntil: lockedUntil,
    );

    await saveCredentials(updated);
  }

  /// Сбрасывает счётчик неудачных попыток
  Future<void> resetFailedAttempts() async {
    final credentials = await getCredentials();
    if (credentials == null) return;

    final updated = credentials.copyWith(
      failedAttempts: 0,
      lockedUntil: null,
    );

    await saveCredentials(updated);
  }

  // ==================== УСТРОЙСТВО ====================

  /// Сохраняет ID устройства
  Future<void> saveDeviceId(String deviceId) async {
    await _storage.write(key: _deviceIdKey, value: deviceId);
  }

  /// Загружает ID устройства
  Future<String?> getDeviceId() async {
    return await _storage.read(key: _deviceIdKey);
  }

  // ==================== БИОМЕТРИЯ ====================

  /// Включает биометрическую авторизацию
  Future<void> enableBiometric() async {
    final credentials = await getCredentials();
    if (credentials == null) return;

    final updated = credentials.copyWith(biometricEnabled: true);
    await saveCredentials(updated);
  }

  /// Выключает биометрическую авторизацию
  Future<void> disableBiometric() async {
    final credentials = await getCredentials();
    if (credentials == null) return;

    final updated = credentials.copyWith(biometricEnabled: false);
    await saveCredentials(updated);
  }

  /// Проверяет, включена ли биометрия
  Future<bool> isBiometricEnabled() async {
    final credentials = await getCredentials();
    return credentials?.biometricEnabled ?? false;
  }

  // ==================== ОБЩИЕ МЕТОДЫ ====================

  /// Полная очистка всех данных авторизации
  Future<void> clearAll() async {
    await _storage.deleteAll();
  }

  /// Проверяет, есть ли сохранённая сессия
  Future<bool> hasSession() async {
    final session = await getSession();
    return session != null && !session.isExpired;
  }

  /// Проверяет, установлен ли PIN-код
  Future<bool> hasPin() async {
    final credentials = await getCredentials();
    return credentials != null;
  }
}
