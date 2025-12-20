import 'dart:convert';

/// Модель записи прихода на работу
class AttendanceRecord {
  final String id;
  final String employeeName;
  final String shopAddress;
  final DateTime timestamp;
  final double latitude;
  final double longitude;
  final double? distance; // Расстояние до магазина в метрах
  final bool? isOnTime; // Пришел ли вовремя (true - вовремя, false - опоздал, null - вне смены)
  final String? shiftType; // Тип смены: 'morning', 'day', 'night', или null если вне смены
  final int? lateMinutes; // Количество минут опоздания (если опоздал)

  AttendanceRecord({
    required this.id,
    required this.employeeName,
    required this.shopAddress,
    required this.timestamp,
    required this.latitude,
    required this.longitude,
    this.distance,
    this.isOnTime,
    this.shiftType,
    this.lateMinutes,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'employeeName': employeeName,
    'shopAddress': shopAddress,
    'timestamp': timestamp.toIso8601String(),
    'latitude': latitude,
    'longitude': longitude,
    'distance': distance,
    if (isOnTime != null) 'isOnTime': isOnTime,
    if (shiftType != null) 'shiftType': shiftType,
    if (lateMinutes != null) 'lateMinutes': lateMinutes,
  };

  factory AttendanceRecord.fromJson(Map<String, dynamic> json) {
    // Безопасный парсинг lateMinutes
    int? parseLateMinutes(dynamic value) {
      if (value == null) return null;
      if (value is int) return value;
      if (value is num) return value.toInt();
      return null;
    }

    // Безопасный парсинг latitude/longitude
    double parseDouble(dynamic value, double defaultValue) {
      if (value == null) return defaultValue;
      if (value is double) return value;
      if (value is num) return value.toDouble();
      return defaultValue;
    }

    return AttendanceRecord(
      id: json['id'] ?? '',
      employeeName: json['employeeName'] ?? '',
      shopAddress: json['shopAddress'] ?? '',
      timestamp: DateTime.parse(json['timestamp']),
      latitude: parseDouble(json['latitude'], 0.0),
      longitude: parseDouble(json['longitude'], 0.0),
      distance: json['distance'] != null ? parseDouble(json['distance'], 0.0) : null,
      isOnTime: json['isOnTime'] as bool?,
      shiftType: json['shiftType'] as String?,
      lateMinutes: parseLateMinutes(json['lateMinutes']),
    );
  }

  static String generateId(String employeeName, DateTime timestamp) {
    final dateStr = '${timestamp.year}-${timestamp.month.toString().padLeft(2, '0')}-${timestamp.day.toString().padLeft(2, '0')}';
    return 'attendance_${employeeName}_$dateStr';
  }
}












