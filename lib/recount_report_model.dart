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
  };

  factory RecountReport.fromJson(Map<String, dynamic> json) => RecountReport(
    id: json['id'] ?? '',
    employeeName: json['employeeName'] ?? '',
    shopAddress: json['shopAddress'] ?? '',
    startedAt: DateTime.parse(json['startedAt']),
    completedAt: DateTime.parse(json['completedAt']),
    duration: Duration(seconds: json['duration'] ?? 0),
    answers: (json['answers'] as List<dynamic>?)
        ?.map((a) => RecountAnswer.fromJson(a))
        .toList() ?? [],
    adminRating: json['adminRating'],
    adminName: json['adminName'],
    ratedAt: json['ratedAt'] != null ? DateTime.parse(json['ratedAt']) : null,
  );

  /// Создать копию с обновленной оценкой
  RecountReport copyWith({
    int? adminRating,
    String? adminName,
    DateTime? ratedAt,
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
    );
  }
}

