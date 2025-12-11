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

  AttendanceRecord({
    required this.id,
    required this.employeeName,
    required this.shopAddress,
    required this.timestamp,
    required this.latitude,
    required this.longitude,
    this.distance,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'employeeName': employeeName,
    'shopAddress': shopAddress,
    'timestamp': timestamp.toIso8601String(),
    'latitude': latitude,
    'longitude': longitude,
    'distance': distance,
  };

  factory AttendanceRecord.fromJson(Map<String, dynamic> json) => AttendanceRecord(
    id: json['id'] ?? '',
    employeeName: json['employeeName'] ?? '',
    shopAddress: json['shopAddress'] ?? '',
    timestamp: DateTime.parse(json['timestamp']),
    latitude: (json['latitude'] as num).toDouble(),
    longitude: (json['longitude'] as num).toDouble(),
    distance: json['distance'] != null ? (json['distance'] as num).toDouble() : null,
  );

  static String generateId(String employeeName, DateTime timestamp) {
    final dateStr = '${timestamp.year}-${timestamp.month.toString().padLeft(2, '0')}-${timestamp.day.toString().padLeft(2, '0')}';
    return 'attendance_${employeeName}_$dateStr';
  }
}






