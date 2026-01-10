import 'package:flutter/material.dart';

/// Модель настроек магазина для РКО
class ShopSettings {
  final String shopAddress; // Адрес магазина (ключ)
  final String address; // Фактический адрес для РКО
  final String inn; // ИНН
  final String directorName; // Руководитель организации (например, "ИП Горовой Р. В.")
  final int lastDocumentNumber; // Последний номер документа (1-50000)
  
  // Интервалы времени для смен
  final TimeOfDay? morningShiftStart; // Начало утренней смены
  final TimeOfDay? morningShiftEnd; // Конец утренней смены
  final TimeOfDay? dayShiftStart; // Начало дневной смены
  final TimeOfDay? dayShiftEnd; // Конец дневной смены
  final TimeOfDay? nightShiftStart; // Начало ночной смены
  final TimeOfDay? nightShiftEnd; // Конец ночной смены
  
  // Аббревиатуры для смен (для графика работы)
  final String? morningAbbreviation; // Аббревиатура утренней смены (например, "Ост(У)")
  final String? dayAbbreviation; // Аббревиатура дневной смены (например, "Ост(Д)")
  final String? nightAbbreviation; // Аббревиатура ночной смены (например, "Ост(Н)")

  ShopSettings({
    required this.shopAddress,
    required this.address,
    required this.inn,
    required this.directorName,
    this.lastDocumentNumber = 0,
    this.morningShiftStart,
    this.morningShiftEnd,
    this.dayShiftStart,
    this.dayShiftEnd,
    this.nightShiftStart,
    this.nightShiftEnd,
    this.morningAbbreviation,
    this.dayAbbreviation,
    this.nightAbbreviation,
  });

  Map<String, dynamic> toJson() => {
    'shopAddress': shopAddress,
    'address': address,
    'inn': inn,
    'directorName': directorName,
    'lastDocumentNumber': lastDocumentNumber,
    if (morningShiftStart != null) 'morningShiftStart': _timeOfDayToString(morningShiftStart!),
    if (morningShiftEnd != null) 'morningShiftEnd': _timeOfDayToString(morningShiftEnd!),
    if (dayShiftStart != null) 'dayShiftStart': _timeOfDayToString(dayShiftStart!),
    if (dayShiftEnd != null) 'dayShiftEnd': _timeOfDayToString(dayShiftEnd!),
    if (nightShiftStart != null) 'nightShiftStart': _timeOfDayToString(nightShiftStart!),
    if (nightShiftEnd != null) 'nightShiftEnd': _timeOfDayToString(nightShiftEnd!),
    if (morningAbbreviation != null) 'morningAbbreviation': morningAbbreviation,
    if (dayAbbreviation != null) 'dayAbbreviation': dayAbbreviation,
    if (nightAbbreviation != null) 'nightAbbreviation': nightAbbreviation,
  };
  
  static String _timeOfDayToString(TimeOfDay time) {
    return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
  }
  
  static TimeOfDay? _stringToTimeOfDay(String? str) {
    if (str == null || str.isEmpty) return null;
    final parts = str.split(':');
    if (parts.length != 2) return null;
    final hour = int.tryParse(parts[0]);
    final minute = int.tryParse(parts[1]);
    if (hour == null || minute == null) return null;
    return TimeOfDay(hour: hour, minute: minute);
  }

  factory ShopSettings.fromJson(Map<String, dynamic> json) {
    return ShopSettings(
      shopAddress: json['shopAddress'] ?? '',
      address: json['address'] ?? '',
      inn: json['inn'] ?? '',
      directorName: json['directorName'] ?? '',
      lastDocumentNumber: json['lastDocumentNumber'] ?? 0,
      morningShiftStart: _stringToTimeOfDay(json['morningShiftStart']),
      morningShiftEnd: _stringToTimeOfDay(json['morningShiftEnd']),
      dayShiftStart: _stringToTimeOfDay(json['dayShiftStart']),
      dayShiftEnd: _stringToTimeOfDay(json['dayShiftEnd']),
      nightShiftStart: _stringToTimeOfDay(json['nightShiftStart']),
      nightShiftEnd: _stringToTimeOfDay(json['nightShiftEnd']),
      morningAbbreviation: json['morningAbbreviation']?.toString(),
      dayAbbreviation: json['dayAbbreviation']?.toString(),
      nightAbbreviation: json['nightAbbreviation']?.toString(),
    );
  }

  ShopSettings copyWith({
    String? address,
    String? inn,
    String? directorName,
    int? lastDocumentNumber,
    TimeOfDay? morningShiftStart,
    TimeOfDay? morningShiftEnd,
    TimeOfDay? dayShiftStart,
    TimeOfDay? dayShiftEnd,
    TimeOfDay? nightShiftStart,
    TimeOfDay? nightShiftEnd,
    String? morningAbbreviation,
    String? dayAbbreviation,
    String? nightAbbreviation,
  }) {
    return ShopSettings(
      shopAddress: shopAddress,
      address: address ?? this.address,
      inn: inn ?? this.inn,
      directorName: directorName ?? this.directorName,
      lastDocumentNumber: lastDocumentNumber ?? this.lastDocumentNumber,
      morningShiftStart: morningShiftStart ?? this.morningShiftStart,
      morningShiftEnd: morningShiftEnd ?? this.morningShiftEnd,
      dayShiftStart: dayShiftStart ?? this.dayShiftStart,
      dayShiftEnd: dayShiftEnd ?? this.dayShiftEnd,
      nightShiftStart: nightShiftStart ?? this.nightShiftStart,
      nightShiftEnd: nightShiftEnd ?? this.nightShiftEnd,
      morningAbbreviation: morningAbbreviation ?? this.morningAbbreviation,
      dayAbbreviation: dayAbbreviation ?? this.dayAbbreviation,
      nightAbbreviation: nightAbbreviation ?? this.nightAbbreviation,
    );
  }

  /// Получить следующий номер документа (1-50000, затем сброс до 1)
  int getNextDocumentNumber() {
    int next = lastDocumentNumber + 1;
    if (next > 50000) {
      next = 1;
    }
    return next;
  }
}











