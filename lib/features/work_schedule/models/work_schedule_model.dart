import 'package:flutter/material.dart';

/// Тип смены
enum ShiftType {
  morning, // Утро: 08:00-16:00
  day,     // День: 12:00-20:00
  evening, // Вечер: 16:00-00:00
}

extension ShiftTypeExtension on ShiftType {
  String get label {
    switch (this) {
      case ShiftType.morning:
        return 'Утро';
      case ShiftType.day:
        return 'День';
      case ShiftType.evening:
        return 'Вечер';
    }
  }

  String get timeRange {
    switch (this) {
      case ShiftType.morning:
        return '08:00-16:00';
      case ShiftType.day:
        return '12:00-20:00';
      case ShiftType.evening:
        return '16:00-00:00';
    }
  }

  TimeOfDay get startTime {
    switch (this) {
      case ShiftType.morning:
        return const TimeOfDay(hour: 8, minute: 0);
      case ShiftType.day:
        return const TimeOfDay(hour: 12, minute: 0);
      case ShiftType.evening:
        return const TimeOfDay(hour: 16, minute: 0);
    }
  }

  TimeOfDay get endTime {
    switch (this) {
      case ShiftType.morning:
        return const TimeOfDay(hour: 16, minute: 0);
      case ShiftType.day:
        return const TimeOfDay(hour: 20, minute: 0);
      case ShiftType.evening:
        return const TimeOfDay(hour: 0, minute: 0); // Полночь следующего дня
    }
  }

  Color get color {
    switch (this) {
      case ShiftType.morning:
        return Colors.green;
      case ShiftType.day:
        return Colors.blue;
      case ShiftType.evening:
        return Colors.orange;
    }
  }

  static ShiftType? fromString(String value) {
    switch (value.toLowerCase()) {
      case 'morning':
      case 'утро':
        return ShiftType.morning;
      case 'day':
      case 'день':
        return ShiftType.day;
      case 'evening':
      case 'вечер':
        return ShiftType.evening;
      default:
        return null;
    }
  }
}

/// Запись о смене сотрудника
class WorkScheduleEntry {
  final String id;
  final String employeeId;
  final String employeeName;
  final String shopAddress;
  final DateTime date;
  final ShiftType shiftType;

  WorkScheduleEntry({
    required this.id,
    required this.employeeId,
    required this.employeeName,
    required this.shopAddress,
    required this.date,
    required this.shiftType,
  });

  factory WorkScheduleEntry.fromJson(Map<String, dynamic> json) {
    return WorkScheduleEntry(
      id: json['id'] ?? '',
      employeeId: json['employeeId'] ?? '',
      employeeName: json['employeeName'] ?? '',
      shopAddress: json['shopAddress'] ?? '',
      date: DateTime.parse(json['date']),
      shiftType: ShiftTypeExtension.fromString(json['shiftType'] ?? '') ?? ShiftType.morning,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'employeeId': employeeId,
      'employeeName': employeeName,
      'shopAddress': shopAddress,
      'date': date.toIso8601String().split('T')[0], // YYYY-MM-DD
      'shiftType': shiftType.name,
    };
  }

  WorkScheduleEntry copyWith({
    String? id,
    String? employeeId,
    String? employeeName,
    String? shopAddress,
    DateTime? date,
    ShiftType? shiftType,
  }) {
    return WorkScheduleEntry(
      id: id ?? this.id,
      employeeId: employeeId ?? this.employeeId,
      employeeName: employeeName ?? this.employeeName,
      shopAddress: shopAddress ?? this.shopAddress,
      date: date ?? this.date,
      shiftType: shiftType ?? this.shiftType,
    );
  }
}

/// График работы на месяц
class WorkSchedule {
  final DateTime month; // Год и месяц
  final List<WorkScheduleEntry> entries;

  WorkSchedule({
    required this.month,
    required this.entries,
  });

  factory WorkSchedule.fromJson(Map<String, dynamic> json) {
    final monthStr = json['month'] as String;
    final year = int.parse(monthStr.split('-')[0]);
    final month = int.parse(monthStr.split('-')[1]);
    
    return WorkSchedule(
      month: DateTime(year, month),
      entries: (json['entries'] as List<dynamic>?)
          ?.map((e) => WorkScheduleEntry.fromJson(e as Map<String, dynamic>))
          .toList() ?? [],
    );
  }

  Map<String, dynamic> toJson() {
    final monthStr = '${month.year}-${month.month.toString().padLeft(2, '0')}';
    return {
      'month': monthStr,
      'entries': entries.map((e) => e.toJson()).toList(),
    };
  }

  /// Получить запись для конкретного сотрудника и даты
  WorkScheduleEntry? getEntry(String employeeId, DateTime date) {
    final dateStr = '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
    return entries.firstWhere(
      (e) => e.employeeId == employeeId && 
             e.date.toIso8601String().split('T')[0] == dateStr,
      orElse: () => throw StateError('Entry not found'),
    );
  }

  /// Проверить, есть ли запись для сотрудника и даты
  bool hasEntry(String employeeId, DateTime date) {
    try {
      getEntry(employeeId, date);
      return true;
    } catch (e) {
      return false;
    }
  }
}

/// Шаблон графика для массового заполнения
class ScheduleTemplate {
  final String id;
  final String name;
  final List<WorkScheduleEntry> entries; // Обычно неделя

  ScheduleTemplate({
    required this.id,
    required this.name,
    required this.entries,
  });

  factory ScheduleTemplate.fromJson(Map<String, dynamic> json) {
    return ScheduleTemplate(
      id: json['id'] ?? '',
      name: json['name'] ?? '',
      entries: (json['entries'] as List<dynamic>?)
          ?.map((e) => WorkScheduleEntry.fromJson(e as Map<String, dynamic>))
          .toList() ?? [],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'entries': entries.map((e) => e.toJson()).toList(),
    };
  }
}


