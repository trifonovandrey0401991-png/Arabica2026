import 'package:geolocator/geolocator.dart';
import '../models/attendance_model.dart';
import '../../shops/models/shop_model.dart';
import '../../../core/services/base_http_service.dart';
import '../../../core/constants/api_constants.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/utils/logger.dart';

class AttendanceService {
  static const String _baseEndpoint = ApiConstants.attendanceEndpoint;
  static const double checkRadius = AppConstants.checkInRadius;

  /// Получить текущую геолокацию
  static Future<Position> getCurrentLocation() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      throw Exception('Служба геолокации отключена. Пожалуйста, включите её в настройках.');
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        throw Exception('Разрешение на геолокацию отклонено.');
      }
    }

    if (permission == LocationPermission.deniedForever) {
      throw Exception('Разрешение на геолокацию отклонено навсегда. Включите его в настройках.');
    }

    return await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.high,
    );
  }

  /// Вычислить расстояние между двумя точками в метрах
  static double calculateDistance(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    return Geolocator.distanceBetween(lat1, lon1, lat2, lon2);
  }

  /// Проверить, находится ли сотрудник в радиусе магазина
  static bool isWithinRadius(
    double userLat,
    double userLon,
    double shopLat,
    double shopLon,
  ) {
    final distance = calculateDistance(userLat, userLon, shopLat, shopLon);
    return distance <= checkRadius;
  }

  /// Найти ближайший магазин
  static Shop? findNearestShop(
    double userLat,
    double userLon,
    List<Shop> shops,
  ) {
    Shop? nearestShop;
    double minDistance = double.infinity;

    for (var shop in shops) {
      if (shop.latitude != null && shop.longitude != null) {
        final distance = calculateDistance(
          userLat,
          userLon,
          shop.latitude!,
          shop.longitude!,
        );
        if (distance < minDistance) {
          minDistance = distance;
          nearestShop = shop;
        }
      }
    }

    return nearestShop;
  }

  /// Результат отметки прихода
  static Future<AttendanceResult> markAttendance({
    required String employeeName,
    required String shopAddress,
    required double latitude,
    required double longitude,
    double? distance,
    DateTime? timestamp, // Опциональный timestamp для тестирования
  }) async {
    try {
      final finalTimestamp = timestamp ?? DateTime.now();
      final record = AttendanceRecord(
        id: AttendanceRecord.generateId(employeeName, finalTimestamp),
        employeeName: employeeName,
        shopAddress: shopAddress,
        timestamp: finalTimestamp,
        latitude: latitude,
        longitude: longitude,
        distance: distance,
      );

      Logger.debug('Создание отметки прихода: $employeeName, время: ${finalTimestamp.toIso8601String()}');

      final result = await BaseHttpService.postRaw(
        endpoint: _baseEndpoint,
        body: record.toJson(),
      );

      if (result != null) {
        return AttendanceResult(
          success: true,
          isOnTime: result['isOnTime'] as bool?,
          shiftType: result['shiftType'] as String?,
          lateMinutes: result['lateMinutes'] != null ? (result['lateMinutes'] as num).toInt() : null,
          message: result['message'] as String?,
        );
      } else {
        return AttendanceResult(
          success: false,
          error: 'Не удалось отправить отметку',
        );
      }
    } catch (e) {
      Logger.error('Ошибка отметки прихода', e);
      return AttendanceResult(
        success: false,
        error: e.toString(),
      );
    }
  }

  /// Проверить, была ли уже отметка сегодня
  static Future<bool> hasAttendanceToday(String employeeName) async {
    try {
      final result = await BaseHttpService.getRaw(
        endpoint: '$_baseEndpoint/check',
        queryParams: {'employeeName': employeeName},
        timeout: ApiConstants.shortTimeout,
      );
      return result?['hasAttendance'] == true;
    } catch (e) {
      Logger.error('Ошибка проверки отметки', e);
      return false;
    }
  }

  /// Получить список отметок (для админа)
  static Future<List<AttendanceRecord>> getAttendanceRecords({
    String? employeeName,
    String? shopAddress,
    DateTime? date,
  }) async {
    try {
      final queryParams = <String, String>{};
      if (employeeName != null) queryParams['employeeName'] = employeeName;
      if (shopAddress != null) queryParams['shopAddress'] = shopAddress;
      if (date != null) queryParams['date'] = date.toIso8601String();

      Logger.debug('Запрос отметок прихода');

      final records = await BaseHttpService.getList<AttendanceRecord>(
        endpoint: _baseEndpoint,
        fromJson: (json) {
          Logger.debug('Парсинг отметки: employeeName=${json['employeeName']}, timestamp=${json['timestamp']}');
          return AttendanceRecord.fromJson(json);
        },
        listKey: 'records',
        queryParams: queryParams.isNotEmpty ? queryParams : null,
      );

      Logger.debug('Всего загружено отметок: ${records.length}');
      return records;
    } catch (e) {
      Logger.error('Ошибка загрузки отметок', e);
      return [];
    }
  }
}

/// Результат отметки прихода
class AttendanceResult {
  final bool success;
  final bool? isOnTime;
  final String? shiftType;
  final int? lateMinutes;
  final String? message;
  final String? error;

  AttendanceResult({
    required this.success,
    this.isOnTime,
    this.shiftType,
    this.lateMinutes,
    this.message,
    this.error,
  });
}
