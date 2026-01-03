import 'dart:convert';
import 'recount_answer_model.dart';

/// Модель отчета пересчета
class RecountReport {
  final String id;
  final String employeeName;
  final String shopAddress;
  final DateTime startedAt;
  final DateTime completedAt;
  final Duration duration;
  final List<RecountAnswer> answers;
  final int? adminRating; // Оценка админа (1-10)
  final String? adminName; // Имя админа, поставившего оценку
  final DateTime? ratedAt; // Время оценки
  final String? status; // "pending" | "rated" | "expired"
  final DateTime? expiredAt; // Когда был просрочен

  RecountReport({
    required this.id,
    required this.employeeName,
    required this.shopAddress,
    required this.startedAt,
    required this.completedAt,
    required this.duration,
    required this.answers,
    this.adminRating,
    this.adminName,
    this.ratedAt,
    this.status,
    this.expiredAt,
  });

  /// Генерировать уникальный ID
  static String generateId(String employeeName, String shopAddress, DateTime createdAt) {
    final dateStr = '${createdAt.year}-${createdAt.month.toString().padLeft(2, '0')}-${createdAt.day.toString().padLeft(2, '0')}';
    final timeStr = '${createdAt.hour.toString().padLeft(2, '0')}-${createdAt.minute.toString().padLeft(2, '0')}-${createdAt.second.toString().padLeft(2, '0')}';
    return 'recount_${employeeName}_${shopAddress}_${dateStr}_$timeStr';
  }

  /// Форматировать длительность в "X минут Y секунд"
  String get formattedDuration {
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds % 60;
    if (minutes > 0) {
      return '$minutes минут${minutes == 1 ? 'а' : minutes < 5 ? 'ы' : ''} $seconds секунд${seconds == 1 ? 'а' : seconds < 5 ? 'ы' : ''}';
    } else {
      return '$seconds секунд${seconds == 1 ? 'а' : seconds < 5 ? 'ы' : ''}';
    }
  }

  /// Проверить, оценен ли отчет
  bool get isRated => adminRating != null;

  /// Проверить, просрочен ли отчет
  bool get isExpired => status == 'expired' || expiredAt != null;

  Map<String, dynamic> toJson() => {
    'id': id,
    'employeeName': employeeName,
    'shopAddress': shopAddress,
    'startedAt': startedAt.toIso8601String(),
    'completedAt': completedAt.toIso8601String(),
    'duration': duration.inSeconds,
    'answers': answers.map((a) => a.toJson()).toList(),
    'adminRating': adminRating,
    'adminName': adminName,
    'ratedAt': ratedAt?.toIso8601String(),
    'status': status,
    'expiredAt': expiredAt?.toIso8601String(),
  };

  factory RecountReport.fromJson(Map<String, dynamic> json) {
    // Обрабатываем даты с fallback на createdAt/savedAt
    DateTime parseDateTime(dynamic value, DateTime? fallback) {
      if (value == null) {
        if (fallback != null) return fallback;
        return DateTime.now(); // Последний fallback
      }
      if (value is String) {
        try {
          return DateTime.parse(value);
        } catch (e) {
          return fallback ?? DateTime.now();
        }
      }
      return fallback ?? DateTime.now();
    }

    final createdAt = json['createdAt'] != null 
        ? (json['createdAt'] is String ? DateTime.parse(json['createdAt']) : null)
        : null;
    final savedAt = json['savedAt'] != null
        ? (json['savedAt'] is String ? DateTime.parse(json['savedAt']) : null)
        : null;

    final startedAt = parseDateTime(json['startedAt'], createdAt);
    final completedAt = parseDateTime(json['completedAt'], savedAt ?? createdAt);

    // Вычисляем duration, если его нет
    Duration duration;
    if (json['duration'] != null) {
      duration = Duration(seconds: json['duration'] is int ? json['duration'] : 0);
    } else if (startedAt != null && completedAt != null) {
      duration = completedAt.difference(startedAt);
    } else {
      duration = Duration.zero;
    }

    return RecountReport(
      id: json['id']?.toString() ?? '',
      employeeName: json['employeeName']?.toString() ?? '',
      shopAddress: json['shopAddress']?.toString() ?? '',
      startedAt: startedAt,
      completedAt: completedAt,
      duration: duration,
      answers: (json['answers'] as List<dynamic>?)
          ?.map((a) => RecountAnswer.fromJson(a as Map<String, dynamic>))
          .toList() ?? [],
      adminRating: json['adminRating'] is int ? json['adminRating'] : null,
      adminName: json['adminName']?.toString(),
      ratedAt: json['ratedAt'] != null && json['ratedAt'] is String
          ? DateTime.tryParse(json['ratedAt'])
          : null,
      status: json['status']?.toString(),
      expiredAt: json['expiredAt'] != null && json['expiredAt'] is String
          ? DateTime.tryParse(json['expiredAt'])
          : null,
    );
  }

  /// Создать копию с обновленной оценкой
  RecountReport copyWith({
    int? adminRating,
    String? adminName,
    DateTime? ratedAt,
    String? status,
    DateTime? expiredAt,
  }) {
    return RecountReport(
      id: id,
      employeeName: employeeName,
      shopAddress: shopAddress,
      startedAt: startedAt,
      completedAt: completedAt,
      duration: duration,
      answers: answers,
      adminRating: adminRating ?? this.adminRating,
      adminName: adminName ?? this.adminName,
      ratedAt: ratedAt ?? this.ratedAt,
      status: status ?? this.status,
      expiredAt: expiredAt ?? this.expiredAt,
    );
  }
}

