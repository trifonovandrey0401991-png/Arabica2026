import 'package:device_info_plus/device_info_plus.dart';
import 'package:crypto/crypto.dart';
import 'dart:convert';
import 'dart:io';

import 'secure_storage_service.dart';

/// Сервис для работы с информацией об устройстве
///
/// Генерирует уникальный ID устройства для:
/// - Привязки сессии к устройству
/// - Определения новых устройств
/// - Безопасности (предотвращение кражи сессий)
class DeviceService {
  static final DeviceService _instance = DeviceService._internal();
  factory DeviceService() => _instance;
  DeviceService._internal();

  final DeviceInfoPlugin _deviceInfo = DeviceInfoPlugin();
  final SecureStorageService _storage = SecureStorageService();

  String? _cachedDeviceId;
  String? _cachedDeviceName;

  /// Получает уникальный ID устройства
  ///
  /// ID генерируется из характеристик устройства и сохраняется.
  /// При переустановке приложения ID может измениться.
  Future<String> getDeviceId() async {
    // Проверяем кэш
    if (_cachedDeviceId != null) {
      return _cachedDeviceId!;
    }

    // Проверяем сохранённый ID
    final savedId = await _storage.getDeviceId();
    if (savedId != null) {
      _cachedDeviceId = savedId;
      return savedId;
    }

    // Генерируем новый ID
    final newId = await _generateDeviceId();
    await _storage.saveDeviceId(newId);
    _cachedDeviceId = newId;

    return newId;
  }

  /// Получает читаемое название устройства
  ///
  /// Пример: "Samsung Galaxy S21" или "Pixel 6 Pro"
  Future<String> getDeviceName() async {
    if (_cachedDeviceName != null) {
      return _cachedDeviceName!;
    }

    try {
      if (Platform.isAndroid) {
        final info = await _deviceInfo.androidInfo;
        _cachedDeviceName = '${info.brand} ${info.model}';
      } else if (Platform.isIOS) {
        final info = await _deviceInfo.iosInfo;
        _cachedDeviceName = info.utsname.machine;
      } else {
        _cachedDeviceName = 'Unknown Device';
      }
    } catch (e) {
      _cachedDeviceName = 'Unknown Device';
    }

    return _cachedDeviceName!;
  }

  /// Получает информацию об устройстве
  Future<Map<String, String>> getDeviceInfo() async {
    final deviceId = await getDeviceId();
    final deviceName = await getDeviceName();

    final info = <String, String>{
      'deviceId': deviceId,
      'deviceName': deviceName,
    };

    try {
      if (Platform.isAndroid) {
        final androidInfo = await _deviceInfo.androidInfo;
        info['platform'] = 'Android';
        info['version'] = androidInfo.version.release;
        info['sdk'] = androidInfo.version.sdkInt.toString();
        info['manufacturer'] = androidInfo.manufacturer;
        info['model'] = androidInfo.model;
      } else if (Platform.isIOS) {
        final iosInfo = await _deviceInfo.iosInfo;
        info['platform'] = 'iOS';
        info['version'] = iosInfo.systemVersion;
        info['model'] = iosInfo.model;
      }
    } catch (e) {
      info['platform'] = 'Unknown';
    }

    return info;
  }

  /// Генерирует уникальный ID на основе характеристик устройства
  Future<String> _generateDeviceId() async {
    final buffer = StringBuffer();

    try {
      if (Platform.isAndroid) {
        final info = await _deviceInfo.androidInfo;
        buffer.write(info.id); // Android ID
        buffer.write(info.brand);
        buffer.write(info.device);
        buffer.write(info.model);
        buffer.write(info.product);
        buffer.write(info.hardware);
      } else if (Platform.isIOS) {
        final info = await _deviceInfo.iosInfo;
        buffer.write(info.identifierForVendor ?? '');
        buffer.write(info.model);
        buffer.write(info.systemVersion);
        buffer.write(info.utsname.machine);
      }
    } catch (e) {
      // Fallback: используем случайные данные
      buffer.write(DateTime.now().microsecondsSinceEpoch);
    }

    // Добавляем соль для уникальности
    buffer.write(DateTime.now().millisecondsSinceEpoch);

    // Хешируем для получения стабильного ID
    final data = utf8.encode(buffer.toString());
    final hash = sha256.convert(data);

    return hash.toString();
  }

  /// Проверяет, совпадает ли текущее устройство с сохранённым ID
  Future<bool> isCurrentDevice(String deviceId) async {
    final currentId = await getDeviceId();
    return currentId == deviceId;
  }
}
