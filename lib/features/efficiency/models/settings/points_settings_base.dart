/// Базовый класс для всех настроек баллов эффективности
///
/// Определяет общий интерфейс для всех типов настроек баллов.
/// Каждый наследник должен реализовать метод расчёта баллов.
abstract class PointsSettingsBase {
  /// Уникальный идентификатор настроек
  String get id;

  /// Категория настроек (shift, recount, attendance, etc.)
  String get category;

  /// Дата создания
  DateTime? get createdAt;

  /// Дата обновления
  DateTime? get updatedAt;

  /// Конвертация в JSON для сохранения на сервер
  Map<String, dynamic> toJson();
}

/// Миксин для настроек с временными окнами (утренняя/вечерняя смена)
///
/// Используется для: Shift, Recount, ShiftHandover, RKO, Attendance
mixin TimeWindowSettings {
  /// Начало утренней смены (формат "HH:mm")
  String get morningStartTime;

  /// Конец утренней смены / дедлайн (формат "HH:mm")
  String get morningEndTime;

  /// Начало вечерней смены (формат "HH:mm")
  String get eveningStartTime;

  /// Конец вечерней смены / дедлайн (формат "HH:mm")
  String get eveningEndTime;

  /// Штраф за пропуск
  double get missedPenalty;
}

/// Миксин для настроек с рейтингом 1-10 и интерполяцией
///
/// Используется для: Shift, Recount, ShiftHandover
mixin RatingBasedSettings {
  /// Минимальный рейтинг (обычно 1)
  int get minRating;

  /// Максимальный рейтинг (обычно 10)
  int get maxRating;

  /// Баллы за минимальный рейтинг (обычно отрицательные)
  double get minPoints;

  /// Порог нулевых баллов (рейтинг, при котором баллы = 0)
  int get zeroThreshold;

  /// Баллы за максимальный рейтинг
  double get maxPoints;

  /// Время на проверку админом (в часах)
  int get adminReviewTimeout;

  /// Расчёт баллов с линейной интерполяцией
  ///
  /// Логика:
  /// - rating <= minRating → minPoints
  /// - rating >= maxRating → maxPoints
  /// - rating <= zeroThreshold → интерполяция от minPoints до 0
  /// - rating > zeroThreshold → интерполяция от 0 до maxPoints
  double calculatePointsFromRating(int rating) {
    if (rating <= minRating) return minPoints;
    if (rating >= maxRating) return maxPoints;

    if (rating <= zeroThreshold) {
      // Интерполяция от minPoints до 0 (rating: minRating -> zeroThreshold)
      final range = zeroThreshold - minRating;
      if (range == 0) return 0;
      return minPoints + (0 - minPoints) * ((rating - minRating) / range);
    } else {
      // Интерполяция от 0 до maxPoints (rating: zeroThreshold -> maxRating)
      final range = maxRating - zeroThreshold;
      if (range == 0) return maxPoints;
      return 0 + (maxPoints - 0) * ((rating - zeroThreshold) / range);
    }
  }
}

/// Миксин для простых настроек с двумя значениями (положительный/отрицательный)
///
/// Используется для: Reviews, ProductSearch, Orders, Envelope
mixin BinarySettings {
  /// Баллы за положительный результат
  double get positivePoints;

  /// Баллы за отрицательный результат
  double get negativePoints;

  /// Расчёт баллов на основе булевого значения
  double calculatePointsFromBool(bool isPositive) {
    return isPositive ? positivePoints : negativePoints;
  }
}
