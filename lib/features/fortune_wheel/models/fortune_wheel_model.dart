import 'dart:ui';

/// Модель сектора колеса удачи
class FortuneWheelSector {
  final int index;
  final String text;
  final double probability;
  final String colorHex;

  FortuneWheelSector({
    required this.index,
    required this.text,
    required this.probability,
    required this.colorHex,
  });

  factory FortuneWheelSector.fromJson(Map<String, dynamic> json) {
    return FortuneWheelSector(
      index: json['index'] ?? 0,
      text: json['text'] ?? '',
      probability: (json['probability'] ?? 0).toDouble(),
      colorHex: json['color'] ?? '#FF6384',
    );
  }

  Map<String, dynamic> toJson() => {
    'index': index,
    'text': text,
    'probability': probability,
    'color': colorHex,
  };

  /// Цвет сектора
  Color get color {
    try {
      final hex = colorHex.replaceFirst('#', '');
      return Color(int.parse('FF$hex', radix: 16));
    } catch (e) {
      return const Color(0xFFFF6384);
    }
  }

  /// Копия с изменениями
  FortuneWheelSector copyWith({
    int? index,
    String? text,
    double? probability,
    String? colorHex,
  }) {
    return FortuneWheelSector(
      index: index ?? this.index,
      text: text ?? this.text,
      probability: probability ?? this.probability,
      colorHex: colorHex ?? this.colorHex,
    );
  }
}

/// Модель настроек колеса
class FortuneWheelSettings {
  final List<FortuneWheelSector> sectors;
  final String? updatedAt;

  FortuneWheelSettings({
    required this.sectors,
    this.updatedAt,
  });

  factory FortuneWheelSettings.fromJson(Map<String, dynamic> json) {
    return FortuneWheelSettings(
      sectors: (json['sectors'] as List?)
          ?.map((e) => FortuneWheelSector.fromJson(e))
          .toList() ?? [],
      updatedAt: json['updatedAt'],
    );
  }

  Map<String, dynamic> toJson() => {
    'sectors': sectors.map((s) => s.toJson()).toList(),
  };
}

/// Модель доступных прокруток
class EmployeeWheelSpins {
  final int availableSpins;
  final String? month;

  EmployeeWheelSpins({
    required this.availableSpins,
    this.month,
  });

  factory EmployeeWheelSpins.fromJson(Map<String, dynamic> json) {
    return EmployeeWheelSpins(
      availableSpins: json['availableSpins'] ?? 0,
      month: json['month'],
    );
  }

  bool get hasSpins => availableSpins > 0;
}

/// Модель результата прокрутки
class WheelSpinResult {
  final FortuneWheelSector sector;
  final int remainingSpins;
  final String recordId;

  WheelSpinResult({
    required this.sector,
    required this.remainingSpins,
    required this.recordId,
  });

  factory WheelSpinResult.fromJson(Map<String, dynamic> json) {
    return WheelSpinResult(
      sector: FortuneWheelSector.fromJson(json['sector']),
      remainingSpins: json['remainingSpins'] ?? 0,
      recordId: json['spinRecord']?['id'] ?? '',
    );
  }
}

/// Модель записи истории прокруток
class WheelSpinRecord {
  final String id;
  final String employeeId;
  final String employeeName;
  final String rewardMonth;
  final int position;
  final int sectorIndex;
  final String prize;
  final DateTime spunAt;
  final bool isProcessed;
  final String? processedBy;
  final DateTime? processedAt;

  WheelSpinRecord({
    required this.id,
    required this.employeeId,
    required this.employeeName,
    required this.rewardMonth,
    required this.position,
    required this.sectorIndex,
    required this.prize,
    required this.spunAt,
    required this.isProcessed,
    this.processedBy,
    this.processedAt,
  });

  factory WheelSpinRecord.fromJson(Map<String, dynamic> json) {
    return WheelSpinRecord(
      id: json['id'] ?? '',
      employeeId: json['employeeId'] ?? '',
      employeeName: json['employeeName'] ?? '',
      rewardMonth: json['rewardMonth'] ?? '',
      position: json['position'] ?? 0,
      sectorIndex: json['sectorIndex'] ?? 0,
      prize: json['prize'] ?? '',
      spunAt: DateTime.tryParse(json['spunAt'] ?? '') ?? DateTime.now(),
      isProcessed: json['isProcessed'] ?? false,
      processedBy: json['processedBy'],
      processedAt: json['processedAt'] != null
          ? DateTime.tryParse(json['processedAt'])
          : null,
    );
  }

  /// Иконка места
  String get positionIcon {
    switch (position) {
      case 1:
        return '🥇';
      case 2:
        return '🥈';
      case 3:
        return '🥉';
      default:
        return '📊';
    }
  }

  /// Форматированная дата
  String get formattedDate {
    return '${spunAt.day.toString().padLeft(2, '0')}.${spunAt.month.toString().padLeft(2, '0')}.${spunAt.year}';
  }

  /// Статус обработки
  String get statusText => isProcessed ? 'Обработано' : 'Ожидает';
}
