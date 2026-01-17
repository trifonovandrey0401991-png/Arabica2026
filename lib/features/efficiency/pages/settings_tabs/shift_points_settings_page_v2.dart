import 'package:flutter/material.dart';
import '../../models/points_settings_model.dart';
import '../../services/points_settings_service.dart';
import 'generic_points_settings_page.dart';

/// Новая версия страницы настроек баллов за пересменку
/// Использует generic компонент вместо дублирования кода
///
/// Сравните с shift_points_settings_page.dart (396 строк) - эта версия всего ~90 строк!
class ShiftPointsSettingsPageV2 extends StatelessWidget {
  const ShiftPointsSettingsPageV2({super.key});

  /// Расчёт баллов для preview (локальная логика)
  static double _calculatePoints(
    int rating,
    double minPoints,
    int zeroThreshold,
    double maxPoints,
  ) {
    if (rating <= 1) return minPoints;
    if (rating >= 10) return maxPoints;

    if (rating <= zeroThreshold) {
      // Interpolate from minPoints to 0 (rating: 1 -> zeroThreshold)
      final range = zeroThreshold - 1;
      return minPoints + (0 - minPoints) * ((rating - 1) / range);
    } else {
      // Interpolate from 0 to maxPoints (rating: zeroThreshold -> 10)
      final range = 10 - zeroThreshold;
      return 0 + (maxPoints - 0) * ((rating - zeroThreshold) / range);
    }
  }

  @override
  Widget build(BuildContext context) {
    return GenericPointsSettingsPage<ShiftPointsSettings>(
      title: 'Баллы за пересменку',
      infoText: 'Баллы начисляются при оценке отчета пересменки (1-10)',

      // Загрузка настроек
      loadSettings: PointsSettingsService.getShiftPointsSettings,

      // Сохранение настроек
      saveSettings: PointsSettingsService.saveShiftPointsSettings,

      // Геттеры для извлечения значений из объекта настроек
      getMinPoints: (settings) => settings.minPoints,
      getZeroThreshold: (settings) => settings.zeroThreshold,
      getMaxPoints: (settings) => settings.maxPoints,

      // Функция расчёта баллов для preview
      calculatePoints: _calculatePoints,

      // Настройки UI для минимальных баллов
      minPointsTitle: 'Минимальная оценка (1)',
      minPointsSubtitle: 'Штраф за плохую пересменку',
      minPointsMin: -5,
      minPointsMax: 0,

      // Настройки UI для порога нуля
      zeroThresholdTitle: 'Порог нулевых баллов',
      zeroThresholdSubtitle: 'При какой оценке баллы = 0',
      zeroThresholdMin: 1,
      zeroThresholdMax: 10,

      // Настройки UI для максимальных баллов
      maxPointsTitle: 'Максимальная оценка (10)',
      maxPointsSubtitle: 'Награда за отличную пересменку',
      maxPointsMin: 0,
      maxPointsMax: 5,

      // Настройки preview
      previewMin: 1,
      previewMax: 10,
      previewLabel: 'Оценка',
    );
  }
}

