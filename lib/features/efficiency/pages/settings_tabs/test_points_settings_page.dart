import 'package:flutter/material.dart';
import '../../models/points_settings_model.dart';
import '../../services/points_settings_service.dart';
import '../../widgets/settings_widgets.dart';

/// Page for configuring test points settings
class TestPointsSettingsPage extends StatefulWidget {
  const TestPointsSettingsPage({super.key});

  @override
  State<TestPointsSettingsPage> createState() => _TestPointsSettingsPageState();
}

class _TestPointsSettingsPageState extends State<TestPointsSettingsPage> {
  bool _isLoading = true;
  bool _isSaving = false;
  TestPointsSettings? _settings;

  // Editable values
  double _minPoints = -2;
  int _zeroThreshold = 15;
  double _maxPoints = 1;

  // Gradient colors for this page
  static const _gradientColors = [Color(0xFF667eea), Color(0xFF764ba2)];

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    setState(() => _isLoading = true);

    try {
      final settings = await PointsSettingsService.getTestPointsSettings();
      setState(() {
        _settings = settings;
        _minPoints = settings.minPoints;
        _zeroThreshold = settings.zeroThreshold;
        _maxPoints = settings.maxPoints;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка загрузки настроек: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _saveSettings() async {
    setState(() => _isSaving = true);

    try {
      final result = await PointsSettingsService.saveTestPointsSettings(
        minPoints: _minPoints,
        zeroThreshold: _zeroThreshold,
        maxPoints: _maxPoints,
      );

      if (result != null) {
        setState(() {
          _settings = result;
          _isSaving = false;
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Настройки сохранены'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } else {
        throw Exception('Не удалось сохранить настройки');
      }
    } catch (e) {
      setState(() => _isSaving = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка сохранения: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

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
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        title: const Text('Баллы за тестирование'),
        backgroundColor: _gradientColors[1],
        elevation: 0,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF667eea)))
          : Column(
              children: [
                // Заголовок
                SettingsHeaderCard(
                  icon: Icons.quiz_outlined,
                  title: 'Всего вопросов: 20',
                  subtitle: 'Проходной балл: 16 правильных',
                  gradientColors: _gradientColors,
                ),
                // Контент
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Min points slider
                        SettingsSliderWidget(
                          title: 'Минимальные баллы',
                          subtitle: 'Штраф за 0-1 правильных ответов',
                          value: _minPoints,
                          min: -5,
                          max: 0,
                          divisions: 10,
                          onChanged: (value) {
                            setState(() => _minPoints = value);
                          },
                          valueLabel: _minPoints.toStringAsFixed(1),
                          accentColor: Colors.red,
                          icon: Icons.remove_circle_outline,
                        ),
                        const SizedBox(height: 16),

                        // Zero threshold slider
                        SettingsSliderWidget(
                          title: 'Порог нуля',
                          subtitle: 'Количество правильных ответов для 0 баллов',
                          value: _zeroThreshold.toDouble(),
                          min: 5,
                          max: 19,
                          divisions: 14,
                          onChanged: (value) {
                            setState(() => _zeroThreshold = value.round());
                          },
                          valueLabel: _zeroThreshold.toString(),
                          isInteger: true,
                          accentColor: Colors.orange,
                          icon: Icons.adjust,
                        ),
                        const SizedBox(height: 16),

                        // Max points slider
                        SettingsSliderWidget(
                          title: 'Максимальные баллы',
                          subtitle: 'Награда за 20/20 правильных ответов',
                          value: _maxPoints,
                          min: 0,
                          max: 5,
                          divisions: 10,
                          onChanged: (value) {
                            setState(() => _maxPoints = value);
                          },
                          valueLabel: '+${_maxPoints.toStringAsFixed(1)}',
                          accentColor: Colors.green,
                          icon: Icons.add_circle_outline,
                        ),
                        const SizedBox(height: 24),

                        // Preview section
                        SettingsSectionTitle(
                          title: 'Предпросмотр расчета баллов',
                          gradientColors: _gradientColors,
                        ),
                        const SizedBox(height: 12),
                        RatingPreviewWidget(
                          previewRatings: _previewScores,
                          calculatePoints: _calculatePoints,
                          gradientColors: _gradientColors,
                          ratingColumnTitle: 'Ответов',
                          ratingFormatter: (score) => '$score / 20',
                        ),
                        const SizedBox(height: 24),

                        // Save button
                        SettingsSaveButton(
                          isSaving: _isSaving,
                          onPressed: _saveSettings,
                          gradientColors: _gradientColors,
                        ),
                        const SizedBox(height: 16),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}
