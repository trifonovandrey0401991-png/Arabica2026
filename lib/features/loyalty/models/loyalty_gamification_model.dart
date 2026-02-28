import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';

/// Значок уровня - может быть иконкой или картинкой
class LevelBadge {
  final String type; // 'icon' или 'image'
  final String value; // название иконки или URL картинки

  const LevelBadge({
    required this.type,
    required this.value,
  });

  factory LevelBadge.fromJson(Map<String, dynamic> json) {
    return LevelBadge(
      type: json['type'] ?? 'icon',
      value: json['value'] ?? 'coffee',
    );
  }

  Map<String, dynamic> toJson() => {
    'type': type,
    'value': value,
  };

  /// Получить иконку Material Icons по названию
  IconData? getIcon() {
    if (type != 'icon') return null;
    return _iconMap[value] ?? Icons.emoji_events;
  }

  static const Map<String, IconData> _iconMap = {
    'coffee': Icons.coffee,
    'favorite': Icons.favorite,
    'star': Icons.star,
    'workspace_premium': Icons.workspace_premium,
    'military_tech': Icons.military_tech,
    'emoji_events': Icons.emoji_events,
    'diamond': Icons.diamond,
    'verified': Icons.verified,
    'grade': Icons.grade,
    'auto_awesome': Icons.auto_awesome,
    'local_cafe': Icons.local_cafe,
    'celebration': Icons.celebration,
    'rocket_launch': Icons.rocket_launch,
    'whatshot': Icons.whatshot,
    'bolt': Icons.bolt,
  };

  /// Список доступных иконок для выбора
  static List<String> get availableIcons => _iconMap.keys.toList();
}

/// Уровень лояльности
class LoyaltyLevel {
  final int id;
  final String name;
  final int minFreeDrinks;
  final int minTotalPoints; // New: threshold in points (fallback: minFreeDrinks * 10)
  final LevelBadge badge;
  final String colorHex;

  const LoyaltyLevel({
    required this.id,
    required this.name,
    required this.minFreeDrinks,
    this.minTotalPoints = 0,
    required this.badge,
    required this.colorHex,
  });

  Color get color {
    try {
      return Color(int.parse(colorHex.replaceFirst('#', '0xFF')));
    } catch (_) {
      return Colors.grey;
    }
  }

  factory LoyaltyLevel.fromJson(Map<String, dynamic> json) {
    final minFreeDrinks = json['minFreeDrinks'] ?? 0;
    return LoyaltyLevel(
      id: json['id'] ?? 1,
      name: json['name'] ?? 'Новичок',
      minFreeDrinks: minFreeDrinks,
      minTotalPoints: json['minTotalPoints'] ?? (minFreeDrinks * 10),
      badge: LevelBadge.fromJson(json['badge'] ?? {}),
      colorHex: json['colorHex'] ?? '#78909C',
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'minFreeDrinks': minFreeDrinks,
    'minTotalPoints': minTotalPoints,
    'badge': badge.toJson(),
    'colorHex': colorHex,
  };

  LoyaltyLevel copyWith({
    int? id,
    String? name,
    int? minFreeDrinks,
    int? minTotalPoints,
    LevelBadge? badge,
    String? colorHex,
  }) {
    return LoyaltyLevel(
      id: id ?? this.id,
      name: name ?? this.name,
      minFreeDrinks: minFreeDrinks ?? this.minFreeDrinks,
      minTotalPoints: minTotalPoints ?? this.minTotalPoints,
      badge: badge ?? this.badge,
      colorHex: colorHex ?? this.colorHex,
    );
  }
}

/// Сектор колеса удачи
class WheelSector {
  final int index;
  final String text;
  final double probability;
  final String colorHex;
  final String prizeType; // 'bonus_points', 'discount', 'free_drink', 'merch'
  final int prizeValue;

  const WheelSector({
    required this.index,
    required this.text,
    required this.probability,
    required this.colorHex,
    required this.prizeType,
    required this.prizeValue,
  });

  Color get color {
    try {
      return Color(int.parse(colorHex.replaceFirst('#', '0xFF')));
    } catch (_) {
      return Colors.grey;
    }
  }

  factory WheelSector.fromJson(Map<String, dynamic> json) {
    return WheelSector(
      index: json['index'] ?? 0,
      text: json['text'] ?? '',
      probability: (json['probability'] ?? 0.1).toDouble(),
      colorHex: json['colorHex'] ?? '#4CAF50',
      prizeType: json['prizeType'] ?? 'bonus_points',
      prizeValue: json['prizeValue'] ?? 1,
    );
  }

  Map<String, dynamic> toJson() => {
    'index': index,
    'text': text,
    'probability': probability,
    'colorHex': colorHex,
    'prizeType': prizeType,
    'prizeValue': prizeValue,
  };

  WheelSector copyWith({
    int? index,
    String? text,
    double? probability,
    String? colorHex,
    String? prizeType,
    int? prizeValue,
  }) {
    return WheelSector(
      index: index ?? this.index,
      text: text ?? this.text,
      probability: probability ?? this.probability,
      colorHex: colorHex ?? this.colorHex,
      prizeType: prizeType ?? this.prizeType,
      prizeValue: prizeValue ?? this.prizeValue,
    );
  }
}

/// Настройки колеса удачи
class WheelSettings {
  final bool enabled;
  final int freeDrinksPerSpin; // Legacy field, kept for backward compat
  final int pointsPerSpin;     // New: points needed per spin (0 = use freeDrinksPerSpin * 10)
  final List<WheelSector> sectors;

  const WheelSettings({
    required this.enabled,
    required this.freeDrinksPerSpin,
    this.pointsPerSpin = 0,
    required this.sectors,
  });

  /// Effective points per spin (new field or legacy fallback)
  int get effectivePointsPerSpin =>
      pointsPerSpin > 0 ? pointsPerSpin : freeDrinksPerSpin * 10;

  factory WheelSettings.fromJson(Map<String, dynamic> json) {
    return WheelSettings(
      enabled: json['enabled'] ?? true,
      freeDrinksPerSpin: json['freeDrinksPerSpin'] ?? 5,
      pointsPerSpin: json['pointsPerSpin'] ?? 0,
      sectors: (json['sectors'] as List<dynamic>?)
          ?.map((s) => WheelSector.fromJson(s))
          .toList() ?? [],
    );
  }

  Map<String, dynamic> toJson() => {
    'enabled': enabled,
    'freeDrinksPerSpin': freeDrinksPerSpin,
    'pointsPerSpin': pointsPerSpin,
    'sectors': sectors.map((s) => s.toJson()).toList(),
  };

  WheelSettings copyWith({
    bool? enabled,
    int? freeDrinksPerSpin,
    int? pointsPerSpin,
    List<WheelSector>? sectors,
  }) {
    return WheelSettings(
      enabled: enabled ?? this.enabled,
      freeDrinksPerSpin: freeDrinksPerSpin ?? this.freeDrinksPerSpin,
      pointsPerSpin: pointsPerSpin ?? this.pointsPerSpin,
      sectors: sectors ?? this.sectors,
    );
  }
}

/// Все настройки геймификации
class GamificationSettings {
  final List<LoyaltyLevel> levels;
  final WheelSettings wheel;
  final String? updatedAt;

  const GamificationSettings({
    required this.levels,
    required this.wheel,
    this.updatedAt,
  });

  factory GamificationSettings.fromJson(Map<String, dynamic> json) {
    return GamificationSettings(
      levels: (json['levels'] as List<dynamic>?)
          ?.map((l) => LoyaltyLevel.fromJson(l))
          .toList() ?? [],
      wheel: WheelSettings.fromJson(json['wheel'] ?? {}),
      updatedAt: json['updatedAt'],
    );
  }

  Map<String, dynamic> toJson() => {
    'levels': levels.map((l) => l.toJson()).toList(),
    'wheel': wheel.toJson(),
    'updatedAt': updatedAt,
  };

  /// Получить уровень по количеству бесплатных напитков (legacy)
  LoyaltyLevel getLevelForFreeDrinks(int freeDrinks) {
    return getLevelForPoints(freeDrinks * 10);
  }

  /// Получить уровень по totalPointsEarned
  LoyaltyLevel getLevelForPoints(int totalPoints) {
    LoyaltyLevel result = levels.first;
    for (final level in levels) {
      // Use minTotalPoints if set, otherwise fallback to minFreeDrinks * 10
      final threshold = level.minTotalPoints > 0 ? level.minTotalPoints : level.minFreeDrinks * 10;
      if (totalPoints >= threshold) {
        result = level;
      }
    }
    return result;
  }

  /// Получить следующий уровень
  LoyaltyLevel? getNextLevel(int currentLevelId) {
    final index = levels.indexWhere((l) => l.id == currentLevelId);
    if (index >= 0 && index < levels.length - 1) {
      return levels[index + 1];
    }
    return null;
  }

  /// Сколько баллов до следующего уровня
  int? pointsToNextLevel(int totalPoints) {
    for (final level in levels) {
      final threshold = level.minTotalPoints > 0 ? level.minTotalPoints : level.minFreeDrinks * 10;
      if (threshold > totalPoints) {
        return threshold - totalPoints;
      }
    }
    return null; // Максимальный уровень достигнут
  }
}

/// Данные геймификации клиента
class ClientGamificationData {
  final String phone;
  final String? name;
  final int freeDrinksGiven;
  final int totalPointsEarned;
  final int loyaltyPoints; // Current wallet balance
  final LoyaltyLevel currentLevel;
  final List<int> earnedBadges;
  final int wheelSpinsAvailable;
  final int wheelSpinsUsed;
  final int drinksToNextSpin;
  final int pointsToNextSpin;
  final LoyaltyLevel? nextLevel;
  final int? drinksToNextLevel;
  final int? pointsToNextLevel;

  const ClientGamificationData({
    required this.phone,
    this.name,
    required this.freeDrinksGiven,
    required this.totalPointsEarned,
    required this.loyaltyPoints,
    required this.currentLevel,
    required this.earnedBadges,
    required this.wheelSpinsAvailable,
    required this.wheelSpinsUsed,
    required this.drinksToNextSpin,
    required this.pointsToNextSpin,
    this.nextLevel,
    this.drinksToNextLevel,
    this.pointsToNextLevel,
  });

  factory ClientGamificationData.fromJson(Map<String, dynamic> json, GamificationSettings settings) {
    final freeDrinksGiven = json['freeDrinksGiven'] ?? 0;
    final totalPointsEarned = json['totalPointsEarned'] ?? (freeDrinksGiven * 10);

    return ClientGamificationData(
      phone: json['phone'] ?? '',
      name: json['name'],
      freeDrinksGiven: freeDrinksGiven,
      totalPointsEarned: totalPointsEarned,
      loyaltyPoints: json['loyaltyPoints'] ?? 0,
      currentLevel: json['currentLevel'] != null
          ? LoyaltyLevel.fromJson(json['currentLevel'])
          : settings.getLevelForPoints(totalPointsEarned),
      earnedBadges: (json['earnedBadges'] as List<dynamic>?)?.cast<int>() ?? [1],
      wheelSpinsAvailable: json['wheelSpinsAvailable'] ?? 0,
      wheelSpinsUsed: json['wheelSpinsUsed'] ?? 0,
      drinksToNextSpin: json['drinksToNextSpin'] ?? settings.wheel.effectivePointsPerSpin,
      pointsToNextSpin: json['pointsToNextSpin'] ?? settings.wheel.effectivePointsPerSpin,
      nextLevel: json['nextLevel'] != null
          ? LoyaltyLevel.fromJson(json['nextLevel'])
          : null,
      drinksToNextLevel: json['drinksToNextLevel'],
      pointsToNextLevel: json['pointsToNextLevel'],
    );
  }
}

/// Результат прокрутки колеса
class WheelSpinResult {
  final String id;
  final String phone;
  final String? clientName;
  final int sectorIndex;
  final String prize;
  final String prizeType;
  final int prizeValue;
  final DateTime spunAt;
  final bool isProcessed;
  final String? prizeId; // Ссылка на приз клиента

  const WheelSpinResult({
    required this.id,
    required this.phone,
    this.clientName,
    required this.sectorIndex,
    required this.prize,
    required this.prizeType,
    required this.prizeValue,
    required this.spunAt,
    required this.isProcessed,
    this.prizeId,
  });

  factory WheelSpinResult.fromJson(Map<String, dynamic> json) {
    return WheelSpinResult(
      id: json['id'] ?? '',
      phone: json['phone'] ?? '',
      clientName: json['clientName'],
      sectorIndex: json['sectorIndex'] ?? 0,
      prize: json['prize'] ?? '',
      prizeType: json['prizeType'] ?? '',
      prizeValue: json['prizeValue'] ?? 0,
      spunAt: DateTime.tryParse(json['spunAt'] ?? '') ?? DateTime.now(),
      isProcessed: json['isProcessed'] ?? false,
      prizeId: json['prizeId'],
    );
  }
}

/// Статус приза клиента
enum ClientPrizeStatus {
  pending,  // Ожидает выдачи
  issued,   // Выдан
}

/// Приз клиента от колеса удачи
class ClientPrize {
  final String id;
  final String clientPhone;
  final String clientName;
  final String prize;        // Текст приза
  final String prizeType;    // bonus_points, discount, free_drink, merch
  final int prizeValue;
  final DateTime spinDate;
  final ClientPrizeStatus status;
  final String qrToken;
  final bool qrUsed;
  final String? issuedBy;
  final String? issuedByName;
  final DateTime? issuedAt;

  const ClientPrize({
    required this.id,
    required this.clientPhone,
    required this.clientName,
    required this.prize,
    required this.prizeType,
    required this.prizeValue,
    required this.spinDate,
    required this.status,
    required this.qrToken,
    required this.qrUsed,
    this.issuedBy,
    this.issuedByName,
    this.issuedAt,
  });

  factory ClientPrize.fromJson(Map<String, dynamic> json) {
    return ClientPrize(
      id: json['id'] ?? '',
      clientPhone: json['clientPhone'] ?? '',
      clientName: json['clientName'] ?? 'Клиент',
      prize: json['prize'] ?? '',
      prizeType: json['prizeType'] ?? '',
      prizeValue: json['prizeValue'] ?? 0,
      spinDate: DateTime.tryParse(json['spinDate'] ?? '') ?? DateTime.now(),
      status: json['status'] == 'issued'
          ? ClientPrizeStatus.issued
          : ClientPrizeStatus.pending,
      qrToken: json['qrToken'] ?? '',
      qrUsed: json['qrUsed'] ?? false,
      issuedBy: json['issuedBy'],
      issuedByName: json['issuedByName'],
      issuedAt: json['issuedAt'] != null
          ? DateTime.tryParse(json['issuedAt'])
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'clientPhone': clientPhone,
    'clientName': clientName,
    'prize': prize,
    'prizeType': prizeType,
    'prizeValue': prizeValue,
    'spinDate': spinDate.toIso8601String(),
    'status': status == ClientPrizeStatus.issued ? 'issued' : 'pending',
    'qrToken': qrToken,
    'qrUsed': qrUsed,
    'issuedBy': issuedBy,
    'issuedByName': issuedByName,
    'issuedAt': issuedAt?.toIso8601String(),
  };

  /// Является ли приз ожидающим выдачи
  bool get isPending => status == ClientPrizeStatus.pending;

  /// Получить иконку для типа приза
  IconData get prizeIcon {
    switch (prizeType) {
      case 'bonus_points':
        return Icons.stars;
      case 'discount':
        return Icons.percent;
      case 'free_drink':
        return Icons.local_cafe;
      case 'merch':
        return Icons.card_giftcard;
      default:
        return Icons.emoji_events;
    }
  }

  /// Получить цвет для типа приза
  Color get prizeColor {
    switch (prizeType) {
      case 'bonus_points':
        return AppColors.success;
      case 'discount':
        return const Color(0xFF2196F3);
      case 'free_drink':
        return const Color(0xFFFF9800);
      case 'merch':
        return const Color(0xFF9C27B0);
      default:
        return const Color(0xFF795548);
    }
  }

  ClientPrize copyWith({
    String? id,
    String? clientPhone,
    String? clientName,
    String? prize,
    String? prizeType,
    int? prizeValue,
    DateTime? spinDate,
    ClientPrizeStatus? status,
    String? qrToken,
    bool? qrUsed,
    String? issuedBy,
    String? issuedByName,
    DateTime? issuedAt,
  }) {
    return ClientPrize(
      id: id ?? this.id,
      clientPhone: clientPhone ?? this.clientPhone,
      clientName: clientName ?? this.clientName,
      prize: prize ?? this.prize,
      prizeType: prizeType ?? this.prizeType,
      prizeValue: prizeValue ?? this.prizeValue,
      spinDate: spinDate ?? this.spinDate,
      status: status ?? this.status,
      qrToken: qrToken ?? this.qrToken,
      qrUsed: qrUsed ?? this.qrUsed,
      issuedBy: issuedBy ?? this.issuedBy,
      issuedByName: issuedByName ?? this.issuedByName,
      issuedAt: issuedAt ?? this.issuedAt,
    );
  }
}
