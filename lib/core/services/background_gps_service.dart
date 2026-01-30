import 'dart:convert';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';
import '../constants/api_constants.dart';
import '../utils/logger.dart';

/// Название задачи для WorkManager
const String backgroundGpsTaskName = 'backgroundGpsCheck';

/// Callback для WorkManager (должен быть top-level функцией)
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    Logger.debug('[BackgroundGPS] Выполнение фоновой задачи: $task');

    if (task == backgroundGpsTaskName) {
      // Проверка для сотрудников (Я на работе)
      await BackgroundGpsService.checkGpsAndNotify();

      // Проверка геозоны для клиентов (push при приближении к магазину)
      await BackgroundGpsService.checkClientGeofence();
    }

    return true;
  });
}

/// Сервис для фоновой проверки GPS и отправки уведомлений "Я на работе"
///
/// Оптимизирован для экономии батареи:
/// - Проверяет только в рабочие часы (6:00 - 22:00)
/// - Проверяет только для сотрудников (не клиентов)
/// - Сервер дополнительно проверяет расписание и pending отчёты
class BackgroundGpsService {
  static bool _isInitialized = false;

  /// Инициализировать фоновую проверку GPS
  static Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      Logger.debug('[BackgroundGPS] Инициализация WorkManager...');

      await Workmanager().initialize(
        callbackDispatcher,
        isInDebugMode: false,
      );

      // Регистрируем периодическую задачу (минимум 15 минут)
      await Workmanager().registerPeriodicTask(
        'gps-check-task',
        backgroundGpsTaskName,
        frequency: const Duration(minutes: 15),
        constraints: Constraints(
          networkType: NetworkType.connected,
        ),
        existingWorkPolicy: ExistingWorkPolicy.keep,
      );

      _isInitialized = true;
      Logger.success('[BackgroundGPS] WorkManager инициализирован');
    } catch (e) {
      Logger.error('[BackgroundGPS] Ошибка инициализации', e);
    }
  }

  /// Проверить GPS и отправить на сервер
  static Future<void> checkGpsAndNotify() async {
    try {
      // Проверка времени: работаем только с 6:00 до 22:00
      final now = DateTime.now();
      if (now.hour < 6 || now.hour >= 22) {
        Logger.debug('[BackgroundGPS] Вне рабочих часов (${now.hour}:${now.minute}), пропускаем');
        return;
      }

      Logger.debug('[BackgroundGPS] Начало проверки GPS...');

      // Получаем сохранённые данные пользователя
      final prefs = await SharedPreferences.getInstance();
      final phone = prefs.getString('user_phone');
      final employeeName = prefs.getString('user_name');
      final userRole = prefs.getString('user_role');

      if (phone == null || phone.isEmpty) {
        Logger.debug('[BackgroundGPS] Телефон не найден, пропускаем');
        return;
      }

      // Проверяем только для сотрудников (не клиентов)
      if (userRole == 'client') {
        Logger.debug('[BackgroundGPS] Пользователь - клиент, пропускаем');
        return;
      }

      // Проверяем разрешение на геолокацию
      final permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        Logger.debug('[BackgroundGPS] Нет разрешения на геолокацию');
        return;
      }

      // Проверяем включена ли служба геолокации
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        Logger.debug('[BackgroundGPS] Служба геолокации отключена');
        return;
      }

      // Получаем текущую позицию
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 30),
      );

      Logger.debug('[BackgroundGPS] GPS: ${position.latitude}, ${position.longitude}');

      // Отправляем на сервер для проверки всех условий:
      // - Ближайший магазин (< 750м)
      // - Расписание сотрудника на сегодня
      // - Pending отчёты
      // - Настройки времени
      // - Кэш уведомлений (не спамить)
      final response = await http.post(
        Uri.parse('${ApiConstants.serverUrl}/api/attendance/gps-check'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'lat': position.latitude,
          'lng': position.longitude,
          'phone': phone,
          'employeeName': employeeName,
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['notified'] == true) {
          Logger.success('[BackgroundGPS] Push-уведомление отправлено для ${data['shop']}');
        } else {
          Logger.debug('[BackgroundGPS] Уведомление не требуется: ${data['reason']}');
        }
      } else {
        Logger.warning('[BackgroundGPS] Ошибка сервера: ${response.statusCode}');
      }
    } catch (e) {
      Logger.error('[BackgroundGPS] Ошибка проверки GPS', e);
    }
  }

  /// Остановить фоновую проверку
  static Future<void> stop() async {
    try {
      await Workmanager().cancelByUniqueName('gps-check-task');
      _isInitialized = false;
      Logger.debug('[BackgroundGPS] Фоновая проверка остановлена');
    } catch (e) {
      Logger.error('[BackgroundGPS] Ошибка остановки', e);
    }
  }

  /// Запустить проверку вручную (для тестирования)
  static Future<void> runOnce() async {
    await checkGpsAndNotify();
  }

  /// Заглушка для совместимости с предыдущим кодом
  static Future<void> start() async {
    // WorkManager запускается автоматически после initialize()
    Logger.debug('[BackgroundGPS] Фоновая проверка уже запущена');
  }

  /// Проверка геозоны для клиентов
  /// Отправляет push-уведомление если клиент находится в радиусе магазина
  static Future<void> checkClientGeofence() async {
    try {
      Logger.debug('[Geofence] Начало проверки геозоны для клиента...');

      // Получаем сохранённые данные пользователя
      final prefs = await SharedPreferences.getInstance();
      final phone = prefs.getString('user_phone');

      if (phone == null || phone.isEmpty) {
        Logger.debug('[Geofence] Телефон не найден, пропускаем');
        return;
      }

      // Проверяем разрешение на геолокацию
      final permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        Logger.debug('[Geofence] Нет разрешения на геолокацию');
        return;
      }

      // Проверяем включена ли служба геолокации
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        Logger.debug('[Geofence] Служба геолокации отключена');
        return;
      }

      // Получаем текущую позицию (используем medium accuracy для экономии батареи)
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.medium,
        timeLimit: const Duration(seconds: 15),
      );

      Logger.debug('[Geofence] GPS: ${position.latitude}, ${position.longitude}');

      // Отправляем на сервер для проверки геозоны
      final normalizedPhone = phone.replaceAll(RegExp(r'[\s+]'), '');
      final response = await http.post(
        Uri.parse('${ApiConstants.serverUrl}/api/geofence/client-check'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'clientPhone': normalizedPhone,
          'latitude': position.latitude,
          'longitude': position.longitude,
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['triggered'] == true) {
          Logger.success('[Geofence] Push отправлен: ${data['shopAddress']} (${data['distance']}м)');
        } else {
          Logger.debug('[Geofence] Не в радиусе магазина');
        }
      } else {
        Logger.warning('[Geofence] Ошибка сервера: ${response.statusCode}');
      }
    } catch (e) {
      Logger.debug('[Geofence] Ошибка проверки геозоны: $e');
    }
  }
}
