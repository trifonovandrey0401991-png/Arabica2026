import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:geolocator/geolocator.dart';
import 'package:flutter/material.dart';
import '../models/attendance_model.dart';
import '../../shops/models/shop_model.dart';
import '../../shops/models/shop_settings_model.dart';
import '../../../core/utils/logger.dart';

class AttendanceService {
  static const String serverUrl = 'https://arabica26.ru';
  static const double checkRadius = 750.0; // Радиус проверки в метрах (среднее между 500 и 1000)

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
      
      Logger.debug('📝 Создание отметки прихода: ${employeeName}, время: ${finalTimestamp.toIso8601String()}');

      final url = '$serverUrl/api/attendance';
      final response = await http.post(
        Uri.parse(url),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(record.toJson()),
      ).timeout(
        const Duration(seconds: 15),
        onTimeout: () {
          throw Exception('Таймаут при отправке отметки');
        },
      );

      if (response.statusCode == 200) {
        final result = jsonDecode(response.body);
        if (result['success'] == true) {
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
            error: result['error'] as String? ?? 'Неизвестная ошибка',
          );
        }
      } else {
        final errorBody = jsonDecode(response.body);
        return AttendanceResult(
          success: false,
          error: errorBody['error'] as String? ?? 'Ошибка сервера: ${response.statusCode}',
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
      final url = '$serverUrl/api/attendance/check?employeeName=${Uri.encodeComponent(employeeName)}';
      final response = await http.get(Uri.parse(url)).timeout(
        const Duration(seconds: 10),
      );

      if (response.statusCode == 200) {
        final result = jsonDecode(response.body);
        return result['hasAttendance'] == true;
      }

      return false;
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
      var url = '$serverUrl/api/attendance?';
      final params = <String>[];

      if (employeeName != null) {
        params.add('employeeName=${Uri.encodeComponent(employeeName)}');
      }
      if (shopAddress != null) {
        params.add('shopAddress=${Uri.encodeComponent(shopAddress)}');
      }
      if (date != null) {
        params.add('date=${date.toIso8601String()}');
      }

      url += params.join('&');
      
      Logger.debug('📥 Запрос отметок прихода: $url');

      final response = await http.get(Uri.parse(url)).timeout(
        const Duration(seconds: 15), // Уменьшено с 30 до 15
      );

      if (response.statusCode == 200) {
        final result = jsonDecode(response.body);
        Logger.debug('📥 Ответ API: success=${result['success']}, records count=${(result['records'] as List<dynamic>?)?.length ?? 0}');
        if (result['success'] == true) {
          final recordsJson = result['records'] as List<dynamic>;
          final records = recordsJson
              .map((json) {
                Logger.debug('📥 Парсинг отметки: employeeName=${json['employeeName']}, timestamp=${json['timestamp']}, timestamp_type=${json['timestamp'].runtimeType}');
                try {
                  final record = AttendanceRecord.fromJson(json);
                  Logger.debug('📥 Загружена отметка: ${record.employeeName}, время: ${record.timestamp.toIso8601String()} (${record.timestamp.hour}:${record.timestamp.minute.toString().padLeft(2, '0')}), UTC: ${record.timestamp.isUtc}');
                  Logger.debug('   timestamp.hour=${record.timestamp.hour}, timestamp.minute=${record.timestamp.minute}');
                  return record;
                } catch (e) {
                  Logger.error('Ошибка парсинга отметки', e);
                  Logger.error('   JSON: $json');
                  rethrow;
                }
              })
              .toList();
          Logger.debug('📥 Всего загружено отметок: ${records.length}');
          return records;
        }
      } else {
        Logger.warning('📥 Ошибка API: statusCode=${response.statusCode}, body=${response.body}');
      }

      return [];
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






