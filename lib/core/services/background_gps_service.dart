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
      await BackgroundGpsService.checkGpsAndNotify();
    }

    return true;
  });
}

/// Сервис для фоновой проверки GPS и отправки уведомлений
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
      Logger.debug('[BackgroundGPS] Начало проверки GPS...');

      // Получаем сохранённые данные пользователя
      final prefs = await SharedPreferences.getInstance();
      final phone = prefs.getString('user_phone');
      final employeeName = prefs.getString('user_name');

      if (phone == null || phone.isEmpty) {
        Logger.debug('[BackgroundGPS] Телефон не найден, пропускаем');
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

      // Отправляем на сервер
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
}
