/// Модель общих настроек пересчёта
/// Определяет пороги для количества фотографий и бонусы/штрафы
class RecountSettings {
  final double defaultPoints;        // Начальные баллы (85)
  final int basePhotos;              // Базовое кол-во фото (3)
  final double stepPoints;           // Шаг в баллах для +1 фото (5)
  final int maxPhotos;               // Максимум фото (20)
  final double correctPhotoBonus;    // Бонус за правильное фото (+0.2)
  final double incorrectPhotoPenalty; // Штраф за неправильное фото (-2.5)
  final int questionsCount;          // Количество вопросов для пересчёта (30)

  RecountSettings({
    this.defaultPoints = 85.0,
    this.basePhotos = 3,
    this.stepPoints = 5.0,
    this.maxPhotos = 20,
    this.correctPhotoBonus = 0.2,
    this.incorrectPhotoPenalty = 2.5,
    this.questionsCount = 30,
  });

  factory RecountSettings.fromJson(Map<String, dynamic> json) {
    return RecountSettings(
      defaultPoints: (json['defaultPoints'] is int)
          ? (json['defaultPoints'] as int).toDouble()
          : (json['defaultPoints'] ?? 85.0).toDouble(),
      basePhotos: json['basePhotos'] ?? 3,
      stepPoints: (json['stepPoints'] is int)
          ? (json['stepPoints'] as int).toDouble()
          : (json['stepPoints'] ?? 5.0).toDouble(),
      maxPhotos: json['maxPhotos'] ?? 20,
      correctPhotoBonus: (json['correctPhotoBonus'] is int)
          ? (json['correctPhotoBonus'] as int).toDouble()
          : (json['correctPhotoBonus'] ?? 0.2).toDouble(),
      incorrectPhotoPenalty: (json['incorrectPhotoPenalty'] is int)
          ? (json['incorrectPhotoPenalty'] as int).toDouble()
          : (json['incorrectPhotoPenalty'] ?? 2.5).toDouble(),
      questionsCount: json['questionsCount'] ?? 30,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'defaultPoints': defaultPoints,
      'basePhotos': basePhotos,
      'stepPoints': stepPoints,
      'maxPhotos': maxPhotos,
      'correctPhotoBonus': correctPhotoBonus,
      'incorrectPhotoPenalty': incorrectPhotoPenalty,
      'questionsCount': questionsCount,
    };
  }

  /// Расчёт требуемого количества фото по баллам
  int calculateRequiredPhotos(double points) {
    if (points >= defaultPoints) return basePhotos;

    final stepsDown = ((defaultPoints - points) / stepPoints).floor();
    final additionalPhotos = stepsDown.clamp(0, maxPhotos - basePhotos);

    return basePhotos + additionalPhotos;
  }

  /// Получить таблицу соответствия баллов и фотографий
  List<Map<String, dynamic>> getPointsPhotoTable() {
    final List<Map<String, dynamic>> table = [];

    for (int photos = basePhotos; photos <= maxPhotos; photos++) {
      final additionalPhotos = photos - basePhotos;
      final minPoints = defaultPoints - (additionalPhotos + 1) * stepPoints + 1;
      final maxPoints = photos == basePhotos
          ? 100.0
          : defaultPoints - additionalPhotos * stepPoints;

      table.add({
        'photos': photos,
        'minPoints': minPoints < 0 ? 0 : minPoints,
        'maxPoints': maxPoints,
      });
    }

    return table;
  }

  RecountSettings copyWith({
    double? defaultPoints,
    int? basePhotos,
    double? stepPoints,
    int? maxPhotos,
    double? correctPhotoBonus,
    double? incorrectPhotoPenalty,
    int? questionsCount,
  }) {
    return RecountSettings(
      defaultPoints: defaultPoints ?? this.defaultPoints,
      basePhotos: basePhotos ?? this.basePhotos,
      stepPoints: stepPoints ?? this.stepPoints,
      maxPhotos: maxPhotos ?? this.maxPhotos,
      correctPhotoBonus: correctPhotoBonus ?? this.correctPhotoBonus,
      incorrectPhotoPenalty: incorrectPhotoPenalty ?? this.incorrectPhotoPenalty,
      questionsCount: questionsCount ?? this.questionsCount,
    );
  }
}

/// Модель для верификации фото в отчёте
class PhotoVerification {
  final int photoIndex;
  final String status; // 'pending', 'approved', 'rejected'
  final String? adminName;
  final DateTime? verifiedAt;
  final double? pointsChange; // +0.2 или -2.5

  PhotoVerification({
    required this.photoIndex,
    required this.status,
    this.adminName,
    this.verifiedAt,
    this.pointsChange,
  });

  factory PhotoVerification.fromJson(Map<String, dynamic> json) {
    return PhotoVerification(
      photoIndex: json['photoIndex'] ?? 0,
      status: json['status'] ?? 'pending',
      adminName: json['adminName'],
      verifiedAt: json['verifiedAt'] != null
          ? DateTime.parse(json['verifiedAt'])
          : null,
      pointsChange: json['pointsChange'] != null
          ? (json['pointsChange'] is int)
              ? (json['pointsChange'] as int).toDouble()
              : json['pointsChange'].toDouble()
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'photoIndex': photoIndex,
      'status': status,
      'adminName': adminName,
      'verifiedAt': verifiedAt?.toIso8601String(),
      'pointsChange': pointsChange,
    };
  }

  bool get isPending => status == 'pending';
  bool get isApproved => status == 'approved';
  bool get isRejected => status == 'rejected';
}
