import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/constants/api_constants.dart';
import '../../../core/constants/prefs_keys.dart';
import '../models/auth_session.dart';
import '../models/auth_credentials.dart';
import 'secure_storage_service.dart';
import 'device_service.dart';
import 'biometric_service.dart';

/// Результат операции авторизации
class AuthResult {
  final bool success;
  final String? error;
  final AuthSession? session;
  final String? message;

  AuthResult({
    required this.success,
    this.error,
    this.session,
    this.message,
  });

  factory AuthResult.success({AuthSession? session, String? message}) {
    return AuthResult(success: true, session: session, message: message);
  }

  factory AuthResult.failure(String error) {
    return AuthResult(success: false, error: error);
  }
}

/// Главный сервис авторизации
///
/// Управляет всем процессом авторизации:
/// - Запрос OTP-кода через Telegram
/// - Верификация OTP
/// - Создание и проверка PIN-кода
/// - Управление сессиями
/// - Биометрическая авторизация
class AuthService {
  static final AuthService _instance = AuthService._internal();
  factory AuthService() => _instance;
  AuthService._internal();

  final SecureStorageService _storage = SecureStorageService();
  final DeviceService _deviceService = DeviceService();
  final BiometricService _biometricService = BiometricService();

  /// Базовый URL API авторизации
  String get _authApiUrl => '${ApiConstants.serverUrl}/api/auth';

  /// Инициализировать session token из хранилища при старте приложения
  Future<void> initSessionToken() async {
    final session = await _storage.getSession();
    if (session != null && !session.isExpired) {
      ApiConstants.sessionToken = session.sessionToken;
      await _saveSessionTokenToPrefs(session.sessionToken);
    }
  }

  // ==================== OTP (TELEGRAM) ====================

  /// Запрашивает OTP-код для телефона
  ///
  /// Код будет отправлен через Telegram-бота.
  /// Возвращает ссылку на бота для пользователя.
  Future<AuthResult> requestOtp(String phone) async {
    try {
      final normalizedPhone = _normalizePhone(phone);

      final response = await http.post(
        Uri.parse('$_authApiUrl/request-otp'),
        headers: ApiConstants.jsonHeaders,
        body: jsonEncode({'phone': normalizedPhone}),
      ).timeout(ApiConstants.defaultTimeout);

      final data = jsonDecode(response.body) as Map<String, dynamic>;

      if (response.statusCode == 200 && data['success'] == true) {
        final botLink = data['telegramBotLink'] as String?;
        return AuthResult.success(
          message: botLink ?? 'Откройте Telegram-бота @ArabicaAuthBot26_bot',
        );
      } else {
        return AuthResult.failure(
          data['error'] as String? ?? 'Ошибка запроса кода',
        );
      }
    } catch (e) {
      return AuthResult.failure('Ошибка соединения: $e');
    }
  }

  /// Проверяет OTP-код
  ///
  /// Возвращает временный токен регистрации при успехе.
  Future<AuthResult> verifyOtp(String phone, String code) async {
    try {
      final normalizedPhone = _normalizePhone(phone);

      final response = await http.post(
        Uri.parse('$_authApiUrl/verify-otp'),
        headers: ApiConstants.jsonHeaders,
        body: jsonEncode({
          'phone': normalizedPhone,
          'code': code,
        }),
      ).timeout(ApiConstants.defaultTimeout);

      final data = jsonDecode(response.body) as Map<String, dynamic>;

      if (response.statusCode == 200 && data['success'] == true) {
        return AuthResult.success(message: data['registrationToken'] as String?);
      } else {
        return AuthResult.failure(
          data['error'] as String? ?? 'Неверный код',
        );
      }
    } catch (e) {
      return AuthResult.failure('Ошибка проверки кода: $e');
    }
  }

  // ==================== РЕГИСТРАЦИЯ ====================

  /// Простая регистрация без OTP-верификации
  ///
  /// Используется при первичной регистрации:
  /// 1. Пользователь вводит телефон и имя
  /// 2. Создаёт PIN-код
  /// 3. Сессия создаётся сразу
  Future<AuthResult> registerSimple({
    required String phone,
    required String name,
    required String pin,
  }) async {
    try {
      final normalizedPhone = _normalizePhone(phone);
      final deviceId = await _deviceService.getDeviceId();
      final deviceName = await _deviceService.getDeviceName();

      // Отправляем PIN напрямую - сервер сам создаст хеш
      final response = await http.post(
        Uri.parse('$_authApiUrl/register'),
        headers: ApiConstants.jsonHeaders,
        body: jsonEncode({
          'phone': normalizedPhone,
          'name': name,
          'pin': pin,  // Сервер сам хеширует PIN
          'deviceId': deviceId,
          'deviceName': deviceName,
        }),
      ).timeout(ApiConstants.longTimeout);

      final data = jsonDecode(response.body) as Map<String, dynamic>;

      if (response.statusCode == 200 && data['success'] == true) {
        // Сохраняем сессию локально
        final session = AuthSession.fromJson(data['session'] as Map<String, dynamic>);
        await _storage.saveSession(session);

        // Устанавливаем session token для всех API запросов
        ApiConstants.sessionToken = session.sessionToken;
        await _saveSessionTokenToPrefs(session.sessionToken);

        // Создаём локальные credentials для офлайн-входа
        // (сервер больше не возвращает pinHash/salt — безопаснее)
        await _storage.createCredentials(pin);

        return AuthResult.success(session: session);
      } else {
        return AuthResult.failure(
          data['error'] as String? ?? 'Ошибка регистрации',
        );
      }
    } catch (e) {
      return AuthResult.failure('Ошибка регистрации: $e');
    }
  }

  /// Полная регистрация с OTP (используется для сброса PIN через Telegram)
  Future<AuthResult> register({
    required String phone,
    required String name,
    required String pin,
    String? registrationToken,
  }) async {
    try {
      final normalizedPhone = _normalizePhone(phone);
      final deviceId = await _deviceService.getDeviceId();
      final deviceName = await _deviceService.getDeviceName();

      // Создаём хеш PIN-кода
      final salt = SecureStorageService.generateSalt();
      final pinHash = SecureStorageService.hashPin(pin, salt);

      final response = await http.post(
        Uri.parse('$_authApiUrl/register'),
        headers: ApiConstants.jsonHeaders,
        body: jsonEncode({
          'phone': normalizedPhone,
          'name': name,
          'pinHash': pinHash,
          'salt': salt,
          'deviceId': deviceId,
          'deviceName': deviceName,
          'registrationToken': registrationToken,
        }),
      ).timeout(ApiConstants.longTimeout);

      final data = jsonDecode(response.body) as Map<String, dynamic>;

      if (response.statusCode == 200 && data['success'] == true) {
        // Сохраняем сессию локально
        final session = AuthSession.fromJson(data['session'] as Map<String, dynamic>);
        await _storage.saveSession(session);

        // Устанавливаем session token для всех API запросов
        ApiConstants.sessionToken = session.sessionToken;
        await _saveSessionTokenToPrefs(session.sessionToken);

        // Сохраняем credentials локально
        final credentials = AuthCredentials(
          pinHash: pinHash,
          salt: salt,
          createdAt: DateTime.now(),
        );
        await _storage.saveCredentials(credentials);

        return AuthResult.success(session: session);
      } else {
        return AuthResult.failure(
          data['error'] as String? ?? 'Ошибка регистрации',
        );
      }
    } catch (e) {
      return AuthResult.failure('Ошибка регистрации: $e');
    }
  }

  // ==================== ВХОД ====================

  /// Вход на сервере с телефоном и PIN (для входа на новом устройстве)
  ///
  /// Используется когда пользователь уже зарегистрирован на сервере,
  /// но на текущем устройстве нет локальных credentials.
  Future<AuthResult> loginOnServer({
    required String phone,
    required String pin,
  }) async {
    try {
      final normalizedPhone = _normalizePhone(phone);
      final deviceId = await _deviceService.getDeviceId();
      final deviceName = await _deviceService.getDeviceName();

      final response = await http.post(
        Uri.parse('$_authApiUrl/login'),
        headers: ApiConstants.jsonHeaders,
        body: jsonEncode({
          'phone': normalizedPhone,
          'pin': pin,
          'deviceId': deviceId,
          'deviceName': deviceName,
        }),
      ).timeout(ApiConstants.defaultTimeout);

      final data = jsonDecode(response.body) as Map<String, dynamic>;

      if (response.statusCode == 200 && data['success'] == true) {
        // Проверяем обязательные поля от сервера
        final tokenValue = data['sessionToken'];
        final expiresValue = data['expiresAt'];
        if (tokenValue is! String || expiresValue is! int) {
          return AuthResult.failure('Сервер вернул неполные данные сессии');
        }

        // Создаём сессию из ответа сервера
        final session = AuthSession(
          sessionToken: tokenValue,
          phone: normalizedPhone,
          name: data['name'] as String?,
          deviceId: deviceId,
          deviceName: deviceName,
          createdAt: DateTime.now(),
          expiresAt: DateTime.fromMillisecondsSinceEpoch(expiresValue),
          isVerified: true,
        );
        await _storage.saveSession(session);

        // Устанавливаем session token для всех API запросов
        ApiConstants.sessionToken = session.sessionToken;
        await _saveSessionTokenToPrefs(session.sessionToken);

        // Создаём локальные credentials для будущего офлайн-входа
        // Используем тот же PIN для создания локального хеша
        await _storage.createCredentials(pin);

        return AuthResult.success(session: session);
      } else if (response.statusCode == 404) {
        return AuthResult.failure('Пользователь не найден. Необходима регистрация.');
      } else if (response.statusCode == 401) {
        final remaining = data['attemptsRemaining'] as int?;
        if (remaining != null) {
          return AuthResult.failure('Неверный PIN-код. Осталось попыток: $remaining');
        }
        return AuthResult.failure(data['error'] as String? ?? 'Неверный PIN-код');
      } else if (response.statusCode == 423) {
        return AuthResult.failure(data['error'] as String? ?? 'Аккаунт заблокирован');
      } else {
        return AuthResult.failure(data['error'] as String? ?? 'Ошибка входа');
      }
    } catch (e) {
      return AuthResult.failure('Ошибка соединения: $e');
    }
  }

  /// Вход с PIN-кодом (для повторного входа на том же устройстве)
  Future<AuthResult> loginWithPin(String pin) async {
    // Проверяем блокировку
    final credentials = await _storage.getCredentials();
    if (credentials == null) {
      return AuthResult.failure('PIN-код не установлен');
    }

    if (credentials.isLocked) {
      final remaining = credentials.remainingLockTime!;
      final minutes = remaining.inMinutes;
      return AuthResult.failure(
        'Аккаунт заблокирован. Попробуйте через $minutes мин.',
      );
    }

    // Проверяем PIN
    final isValid = await _storage.verifyPin(pin);
    if (!isValid) {
      await _storage.incrementFailedAttempts();
      final updated = await _storage.getCredentials();
      final remaining = AuthCredentials.maxFailedAttempts - (updated?.failedAttempts ?? 0);

      if (remaining <= 0) {
        return AuthResult.failure(
          'Слишком много попыток. Аккаунт заблокирован на 15 минут.',
        );
      }

      return AuthResult.failure(
        'Неверный PIN-код. Осталось попыток: $remaining',
      );
    }

    // PIN верный - сбрасываем счётчик попыток
    await _storage.resetFailedAttempts();

    // Проверяем и обновляем сессию
    final session = await _storage.getSession();
    if (session == null || session.isExpired) {
      // Сессия истекла - пробуем войти через сервер
      if (session != null && session.phone.isNotEmpty) {
        // Есть телефон - пробуем серверный вход
        return await loginOnServer(phone: session.phone, pin: pin);
      }
      return AuthResult.failure('Сессия истекла. Требуется повторная верификация.');
    }

    // Устанавливаем session token для всех API запросов
    ApiConstants.sessionToken = session.sessionToken;
    unawaited(_saveSessionTokenToPrefs(session.sessionToken));

    // Обновляем lastActivity на сервере (асинхронно)
    _refreshSessionOnServer(session.sessionToken);

    return AuthResult.success(session: session);
  }

  /// Вход с биометрией
  Future<AuthResult> loginWithBiometric() async {
    // Проверяем доступность биометрии
    if (!await _biometricService.isAvailable()) {
      return AuthResult.failure('Биометрия недоступна на этом устройстве');
    }

    // Проверяем, включена ли биометрия
    if (!await _storage.isBiometricEnabled()) {
      return AuthResult.failure('Биометрия не включена');
    }

    // Запрашиваем биометрическую авторизацию
    final authenticated = await _biometricService.authenticate(
      reason: 'Подтвердите личность для входа в приложение',
    );

    if (!authenticated) {
      return AuthResult.failure('Биометрическая авторизация отклонена');
    }

    // Биометрия успешна - проверяем сессию
    final session = await _storage.getSession();
    if (session == null || session.isExpired) {
      return AuthResult.failure('Сессия истекла. Требуется повторная верификация.');
    }

    // Устанавливаем session token для всех API запросов
    ApiConstants.sessionToken = session.sessionToken;
    unawaited(_saveSessionTokenToPrefs(session.sessionToken));

    // Обновляем lastActivity на сервере (асинхронно, как и в loginWithPin)
    _refreshSessionOnServer(session.sessionToken);

    return AuthResult.success(session: session);
  }

  // ==================== СЕССИЯ ====================

  /// Проверяет текущую сессию
  Future<AuthResult> validateSession() async {
    final session = await _storage.getSession();
    if (session == null) {
      return AuthResult.failure('Нет активной сессии');
    }

    if (session.isExpired) {
      await _storage.clearSession();
      return AuthResult.failure('Сессия истекла');
    }

    // Проверяем сессию на сервере
    try {
      final deviceId = await _deviceService.getDeviceId();

      final response = await http.post(
        Uri.parse('$_authApiUrl/validate-session'),
        headers: {
          ...ApiConstants.jsonHeaders,
          'Authorization': 'Bearer ${session.sessionToken}',
        },
        body: jsonEncode({
          'sessionToken': session.sessionToken,
          'deviceId': deviceId,
        }),
      ).timeout(ApiConstants.shortTimeout);

      final data = jsonDecode(response.body) as Map<String, dynamic>;

      if (response.statusCode == 200 && data['success'] == true) {
        return AuthResult.success(session: session);
      } else {
        // Сессия невалидна на сервере
        await _storage.clearSession();
        return AuthResult.failure('Сессия недействительна');
      }
    } catch (e) {
      // При ошибке сети доверяем локальной сессии
      return AuthResult.success(session: session);
    }
  }

  /// Выход из аккаунта
  Future<void> logout() async {
    final session = await _storage.getSession();

    // Уведомляем сервер о выходе
    if (session != null) {
      try {
        await http.post(
          Uri.parse('$_authApiUrl/logout'),
          headers: {
            ...ApiConstants.jsonHeaders,
            'Authorization': 'Bearer ${session.sessionToken}',
          },
          body: jsonEncode({'sessionToken': session.sessionToken}),
        ).timeout(ApiConstants.shortTimeout);
      } catch (_) {
        // Игнорируем ошибки сети при выходе
      }
    }

    // Очищаем session token
    ApiConstants.sessionToken = null;
    await _saveSessionTokenToPrefs(null);

    // Очищаем локальные данные
    await _storage.clearSession();
    // Credentials НЕ удаляем - PIN остаётся
  }

  /// Полный выход с удалением всех данных
  Future<void> logoutAndClearAll() async {
    await logout();
    await _storage.clearAll();
  }

  // ==================== PIN ====================

  /// Проверяет, установлен ли PIN-код
  Future<bool> hasPin() async {
    return await _storage.hasPin();
  }

  /// Меняет PIN-код (локально + на сервере)
  Future<AuthResult> changePin(String oldPin, String newPin) async {
    // Проверяем старый PIN локально
    final isValid = await _storage.verifyPin(oldPin);
    if (!isValid) {
      return AuthResult.failure('Неверный текущий PIN-код');
    }

    // Обновляем PIN на сервере
    try {
      final response = await http.post(
        Uri.parse('$_authApiUrl/change-pin'),
        headers: ApiConstants.jsonHeaders,
        body: jsonEncode({
          'oldPin': oldPin,
          'newPin': newPin,
        }),
      ).timeout(ApiConstants.defaultTimeout);

      final data = jsonDecode(response.body) as Map<String, dynamic>;

      if (response.statusCode != 200 || data['success'] != true) {
        return AuthResult.failure(
          data['error'] as String? ?? 'Ошибка смены PIN на сервере',
        );
      }
    } catch (e) {
      // Сервер недоступен — обновим локально
      // Продолжаем — обновим локально даже если сервер недоступен
    }

    // Обновляем PIN локально
    await _storage.createCredentials(newPin);

    return AuthResult.success(message: 'PIN-код успешно изменён');
  }

  /// Сбрасывает PIN-код через OTP
  ///
  /// Отправляет raw PIN на сервер, сервер сам создаёт хеш.
  /// Возвращает сессию при успехе.
  Future<AuthResult> resetPin(String phone, String newPin, String registrationToken) async {
    try {
      final normalizedPhone = _normalizePhone(phone);
      final deviceId = await _deviceService.getDeviceId();
      final deviceName = await _deviceService.getDeviceName();

      final response = await http.post(
        Uri.parse('$_authApiUrl/reset-pin'),
        headers: ApiConstants.jsonHeaders,
        body: jsonEncode({
          'phone': normalizedPhone,
          'pin': newPin,  // Сервер сам хеширует PIN
          'registrationToken': registrationToken,
          'deviceId': deviceId,
          'deviceName': deviceName,
        }),
      ).timeout(ApiConstants.defaultTimeout);

      final data = jsonDecode(response.body) as Map<String, dynamic>;

      if (response.statusCode == 200 && data['success'] == true) {
        // Проверяем обязательные поля от сервера
        final tokenValue = data['sessionToken'];
        final expiresValue = data['expiresAt'];
        if (tokenValue is! String || expiresValue is! int) {
          return AuthResult.failure('Сервер вернул неполные данные сессии');
        }

        // Создаём локальные credentials для офлайн-входа
        await _storage.createCredentials(newPin);

        // Создаём сессию из ответа сервера
        final session = AuthSession(
          sessionToken: tokenValue,
          phone: normalizedPhone,
          deviceId: deviceId,
          deviceName: deviceName,
          createdAt: DateTime.now(),
          expiresAt: DateTime.fromMillisecondsSinceEpoch(expiresValue),
          isVerified: true,
        );
        await _storage.saveSession(session);

        // Устанавливаем session token для всех API запросов
        ApiConstants.sessionToken = session.sessionToken;
        await _saveSessionTokenToPrefs(session.sessionToken);

        return AuthResult.success(session: session, message: 'PIN-код успешно сброшен');
      } else {
        return AuthResult.failure(
          data['error'] as String? ?? 'Ошибка сброса PIN-кода',
        );
      }
    } catch (e) {
      return AuthResult.failure('Ошибка сброса PIN-кода: $e');
    }
  }

  // ==================== БИОМЕТРИЯ ====================

  /// Проверяет, доступна ли биометрия
  Future<bool> isBiometricAvailable() async {
    return await _biometricService.isAvailable();
  }

  /// Включает биометрическую авторизацию
  Future<AuthResult> enableBiometric() async {
    if (!await _biometricService.isAvailable()) {
      return AuthResult.failure('Биометрия недоступна на этом устройстве');
    }

    // Подтверждаем биометрией
    final authenticated = await _biometricService.authenticate(
      reason: 'Подтвердите личность для включения биометрии',
    );

    if (!authenticated) {
      return AuthResult.failure('Биометрическая авторизация отклонена');
    }

    await _storage.enableBiometric();
    return AuthResult.success(message: 'Биометрия включена');
  }

  /// Выключает биометрическую авторизацию
  Future<void> disableBiometric() async {
    await _storage.disableBiometric();
  }

  /// Проверяет, включена ли биометрия
  Future<bool> isBiometricEnabled() async {
    return await _storage.isBiometricEnabled();
  }

  // ==================== ВСПОМОГАТЕЛЬНЫЕ МЕТОДЫ ====================

  /// Нормализует номер телефона
  String _normalizePhone(String phone) {
    return phone.replaceAll(RegExp(r'[\s\+]'), '');
  }

  /// Обновляет сессию на сервере (фоновая операция)
  Future<void> _refreshSessionOnServer(String sessionToken) async {
    try {
      await http.post(
        Uri.parse('$_authApiUrl/refresh-session'),
        headers: {
          ...ApiConstants.jsonHeaders,
          'Authorization': 'Bearer $sessionToken',
        },
        body: jsonEncode({'sessionToken': sessionToken}),
      ).timeout(ApiConstants.shortTimeout);
    } catch (_) {
      // Игнорируем ошибки обновления
    }
  }

  /// Сохраняет session token в SharedPreferences для фоновых задач WorkManager.
  /// WorkManager запускается в отдельном Dart-изоляте, где static-переменные
  /// ApiConstants._sessionToken = null. SharedPreferences доступны из любого изолята.
  Future<void> _saveSessionTokenToPrefs(String? token) async {
    final prefs = await SharedPreferences.getInstance();
    if (token != null) {
      await prefs.setString(PrefsKeys.sessionToken, token);
    } else {
      await prefs.remove(PrefsKeys.sessionToken);
    }
  }

  /// Получает текущую сессию (если есть)
  Future<AuthSession?> getCurrentSession() async {
    return await _storage.getSession();
  }

  /// Проверяет, авторизован ли пользователь
  Future<bool> isAuthenticated() async {
    final session = await _storage.getSession();
    return session != null && !session.isExpired;
  }

  /// Получает статус авторизации для отображения
  Future<Map<String, dynamic>> getAuthStatus() async {
    final hasSession = await _storage.hasSession();
    final hasPin = await _storage.hasPin();
    final biometricAvailable = await _biometricService.isAvailable();
    final biometricEnabled = await _storage.isBiometricEnabled();
    final credentials = await _storage.getCredentials();

    return {
      'hasSession': hasSession,
      'hasPin': hasPin,
      'biometricAvailable': biometricAvailable,
      'biometricEnabled': biometricEnabled,
      'isLocked': credentials?.isLocked ?? false,
      'failedAttempts': credentials?.failedAttempts ?? 0,
    };
  }
}
