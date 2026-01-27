import 'package:flutter/material.dart';
import '../../services/points_settings_service.dart';
import '../../widgets/settings_widgets.dart';

/// Page for configuring reviews points settings (Отзывы)
class ReviewsPointsSettingsPage extends StatefulWidget {
  const ReviewsPointsSettingsPage({super.key});

  @override
  State<ReviewsPointsSettingsPage> createState() =>
      _ReviewsPointsSettingsPageState();
}

class _ReviewsPointsSettingsPageState extends State<ReviewsPointsSettingsPage> {
  bool _isLoading = true;
  bool _isSaving = false;

  double _positivePoints = 3;
  double _negativePoints = -5;

  // Gradient colors for this page (amber theme)
  static const _gradientColors = [Color(0xFFf7971e), Color(0xFFffd200)];

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    setState(() => _isLoading = true);
    try {
      final settings = await PointsSettingsService.getReviewsPointsSettings();
      setState(() {
        _positivePoints = settings.positivePoints;
        _negativePoints = settings.negativePoints;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка загрузки настроек: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _saveSettings() async {
    setState(() => _isSaving = true);
    try {
      final result = await PointsSettingsService.saveReviewsPointsSettings(
        positivePoints: _positivePoints,
        negativePoints: _negativePoints,
      );
      if (result != null) {
        setState(() => _isSaving = false);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Row(
                children: [
                  Icon(Icons.check_circle, color: Colors.white),
                  SizedBox(width: 8),
                  Text('Настройки сохранены'),
                ],
              ),
              backgroundColor: Colors.green[400],
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
          SnackBar(content: Text('Ошибка сохранения: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        title: const Text('Баллы за отзывы'),
        backgroundColor: _gradientColors[0],
        elevation: 0,
      ),
      body: _isLoading
          ? Center(child: CircularProgressIndicator(color: _gradientColors[0]))
          : Column(
              children: [
                // Заголовок
                SettingsHeaderCard(
                  icon: Icons.star_rate_outlined,
                  title: 'Отзывы клиентов',
                  subtitle: 'Баллы за положительные и отрицательные отзывы',
                  gradientColors: _gradientColors,
                ),
                // Контент
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Positive points slider
                        SettingsSliderWidget(
                          title: 'Положительный отзыв',
                          subtitle: 'Награда за хороший отзыв клиента',
                          value: _positivePoints,
                          min: 0,
                          max: 10,
                          divisions: 100,
                          onChanged: (value) => setState(() => _positivePoints = value),
                          valueLabel: '+${_positivePoints.toStringAsFixed(1)}',
                          accentColor: Colors.green,
                          icon: Icons.thumb_up_outlined,
                        ),
                        const SizedBox(height: 16),

                        // Negative points slider
                        SettingsSliderWidget(
                          title: 'Отрицательный отзыв',
                          subtitle: 'Штраф за плохой отзыв клиента',
                          value: _negativePoints,
                          min: -10,
                          max: 0,
                          divisions: 100,
                          onChanged: (value) => setState(() => _negativePoints = value),
                          valueLabel: _negativePoints.toStringAsFixed(1),
                          accentColor: Colors.red,
                          icon: Icons.thumb_down_outlined,
                        ),
                        const SizedBox(height: 24),

                        // Preview section
                        SettingsSectionTitle(
                          title: 'Предпросмотр',
                          gradientColors: _gradientColors,
                        ),
                        const SizedBox(height: 12),
                        BinaryPreviewWidget(
                          positiveLabel: 'Положительный',
                          negativeLabel: 'Отрицательный',
                          positivePoints: _positivePoints,
                          negativePoints: _negativePoints,
                          gradientColors: _gradientColors,
                          valueColumnTitle: 'Тип отзыва',
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
