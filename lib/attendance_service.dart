import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:geolocator/geolocator.dart';
import 'attendance_model.dart';
import 'shop_model.dart';

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

  /// Отметить приход на работу
  static Future<bool> markAttendance({
    required String employeeName,
    required String shopAddress,
    required double latitude,
    required double longitude,
    double? distance,
  }) async {
    try {
      final timestamp = DateTime.now();
      final record = AttendanceRecord(
        id: AttendanceRecord.generateId(employeeName, timestamp),
        employeeName: employeeName,
        shopAddress: shopAddress,
        timestamp: timestamp,
        latitude: latitude,
        longitude: longitude,
        distance: distance,
      );

      final url = '$serverUrl/api/attendance';
      final response = await http.post(
        Uri.parse(url),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(record.toJson()),
      ).timeout(
        const Duration(seconds: 30),
        onTimeout: () {
          throw Exception('Таймаут при отправке отметки');
        },
      );

      if (response.statusCode == 200) {
        final result = jsonDecode(response.body);
        return result['success'] == true;
      }

      return false;
    } catch (e) {
      print('❌ Ошибка отметки прихода: $e');
      return false;
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
      print('❌ Ошибка проверки отметки: $e');
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

      final response = await http.get(Uri.parse(url)).timeout(
        const Duration(seconds: 30),
      );

      if (response.statusCode == 200) {
        final result = jsonDecode(response.body);
        if (result['success'] == true) {
          final recordsJson = result['records'] as List<dynamic>;
          return recordsJson
              .map((json) => AttendanceRecord.fromJson(json))
              .toList();
        }
      }

      return [];
    } catch (e) {
      print('❌ Ошибка загрузки отметок: $e');
      return [];
    }
  }
}





