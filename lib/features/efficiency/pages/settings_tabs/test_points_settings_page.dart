import 'package:flutter/material.dart';
import '../../services/points_settings_service.dart';
import '../../widgets/settings_widgets.dart';
import '../../widgets/points_settings_scaffold.dart';

/// Page for configuring test points settings
class TestPointsSettingsPage extends StatefulWidget {
  const TestPointsSettingsPage({super.key});

  @override
  State<TestPointsSettingsPage> createState() => _TestPointsSettingsPageState();
}

class _TestPointsSettingsPageState extends State<TestPointsSettingsPage> {
  // Editable values
  double _minPoints = -2;
  int _zeroThreshold = 15;
  double _maxPoints = 1;

  // Gradient colors for this page
  static final _gradientColors = [Color(0xFF667eea), Color(0xFF764ba2)];

  /// Calculate points using current settings (local calculation)
  double _calculatePoints(int score) {
    if (score <= 0) return _minPoints;
    if (score >= 20) return _maxPoints;

    if (score <= _zeroThreshold) {
      return _minPoints + (0 - _minPoints) * (score / _zeroThreshold);
    } else {
      final range = 20 - _zeroThreshold;
      return 0 + (_maxPoints - 0) * ((score - _zeroThreshold) / range);
    }
  }

  /// Get preview scores including dynamic zeroThreshold
  List<int> get _previewScores => [0, 5, 10, _zeroThreshold, 17, 18, 19, 20];

  @override
  Widget build(BuildContext context) {
    return PointsSettingsScaffold(
      title: 'Баллы за тестирование',
      headerIcon: Icons.quiz_outlined,
      headerTitle: 'Всего вопросов: 20',
      headerSubtitle: 'Проходной балл: 16 правильных',
      gradientColors: _gradientColors,
      onLoad: () async {
        final settings = await PointsSettingsService.getTestPointsSettings();
        _minPoints = settings.minPoints;
        _zeroThreshold = settings.zeroThreshold;
        _maxPoints = settings.maxPoints;
      },
      onSave: () async {
        final result = await PointsSettingsService.saveTestPointsSettings(
          minPoints: _minPoints,
          zeroThreshold: _zeroThreshold,
          maxPoints: _maxPoints,
        );
        return result != null;
      },
      bodyBuilder: (context) => [
        // Min points slider
        SettingsSliderWidget(
          title: 'Минимальные баллы',
          subtitle: 'Штраф за 0-1 правильных ответов',
          value: _minPoints,
          min: -5,
          max: 0,
          divisions: 10,
          onChanged: (value) {
            if (mounted) setState(() => _minPoints = value);
          },
          valueLabel: _minPoints.toStringAsFixed(1),
          accentColor: Colors.red,
          icon: Icons.remove_circle_outline,
        ),
        SizedBox(height: 16),

        // Zero threshold slider
        SettingsSliderWidget(
          title: 'Порог нуля',
          subtitle: 'Количество правильных ответов для 0 баллов',
          value: _zeroThreshold.toDouble(),
          min: 5,
          max: 19,
          divisions: 14,
          onChanged: (value) {
            if (mounted) setState(() => _zeroThreshold = value.round());
          },
          valueLabel: _zeroThreshold.toString(),
          isInteger: true,
          accentColor: Colors.orange,
          icon: Icons.adjust,
        ),
        SizedBox(height: 16),

        // Max points slider
        SettingsSliderWidget(
          title: 'Максимальные баллы',
          subtitle: 'Награда за 20/20 правильных ответов',
          value: _maxPoints,
          min: 0,
          max: 5,
          divisions: 10,
          onChanged: (value) {
            if (mounted) setState(() => _maxPoints = value);
          },
          valueLabel: '+${_maxPoints.toStringAsFixed(1)}',
          accentColor: Colors.green,
          icon: Icons.add_circle_outline,
        ),
        SizedBox(height: 24),

        // Preview section
        SettingsSectionTitle(
          title: 'Предпросмотр расчета баллов',
          gradientColors: _gradientColors,
        ),
        SizedBox(height: 12),
        RatingPreviewWidget(
          previewRatings: _previewScores,
          calculatePoints: _calculatePoints,
          gradientColors: _gradientColors,
          ratingColumnTitle: 'Ответов',
          ratingFormatter: (score) => '$score / 20',
        ),
      ],
    );
  }
}
