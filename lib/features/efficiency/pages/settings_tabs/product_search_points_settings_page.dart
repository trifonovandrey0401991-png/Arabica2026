import 'package:flutter/material.dart';
import '../../models/points_settings_model.dart';
import '../../services/points_settings_service.dart';
import '../../widgets/settings_widgets.dart';

/// Page for configuring product search points settings (Поиск товара)
class ProductSearchPointsSettingsPage extends StatefulWidget {
  const ProductSearchPointsSettingsPage({super.key});

  @override
  State<ProductSearchPointsSettingsPage> createState() =>
      _ProductSearchPointsSettingsPageState();
}

class _ProductSearchPointsSettingsPageState
    extends State<ProductSearchPointsSettingsPage> {
  bool _isLoading = true;
  bool _isSaving = false;
  ProductSearchPointsSettings? _settings;

  double _answeredPoints = 0.2;
  double _notAnsweredPoints = -3;
  int _answerTimeoutMinutes = 30;

  // Gradient colors for this page (cyan theme)
  static const _gradientColors = [Color(0xFF00d2ff), Color(0xFF3a7bd5)];

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    setState(() => _isLoading = true);
    try {
      final settings = await PointsSettingsService.getProductSearchPointsSettings();
      setState(() {
        _settings = settings;
        _answeredPoints = settings.answeredPoints;
        _notAnsweredPoints = settings.notAnsweredPoints;
        _answerTimeoutMinutes = settings.answerTimeoutMinutes;
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
      final result = await PointsSettingsService.saveProductSearchPointsSettings(
        answeredPoints: _answeredPoints,
        notAnsweredPoints: _notAnsweredPoints,
        answerTimeoutMinutes: _answerTimeoutMinutes,
      );
      if (result != null) {
        setState(() { _settings = result; _isSaving = false; });
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
        title: const Text('Баллы за поиск товара'),
        backgroundColor: _gradientColors[0],
        elevation: 0,
      ),
      body: _isLoading
          ? Center(child: CircularProgressIndicator(color: _gradientColors[0]))
          : Column(
              children: [
                // Заголовок
                SettingsHeaderCard(
                  icon: Icons.search_outlined,
                  title: 'Запросы о наличии товара',
                  subtitle: 'Баллы за своевременный ответ клиенту',
                  gradientColors: _gradientColors,
                ),
                // Контент
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Answered points slider
                        SettingsSliderWidget(
                          title: 'Ответил вовремя',
                          subtitle: 'Награда за своевременный ответ',
                          value: _answeredPoints,
                          min: 0,
                          max: 2,
                          divisions: 20,
                          onChanged: (value) => setState(() => _answeredPoints = value),
                          valueLabel: '+${_answeredPoints.toStringAsFixed(1)}',
                          accentColor: Colors.green,
                          icon: Icons.check_circle_outline,
                        ),
                        const SizedBox(height: 16),

                        // Not answered points slider
                        SettingsSliderWidget(
                          title: 'Не ответил',
                          subtitle: 'Штраф за отсутствие ответа',
                          value: _notAnsweredPoints,
                          min: -5,
                          max: 0,
                          divisions: 50,
                          onChanged: (value) => setState(() => _notAnsweredPoints = value),
                          valueLabel: _notAnsweredPoints.toStringAsFixed(1),
                          accentColor: Colors.red,
                          icon: Icons.cancel_outlined,
                        ),
                        const SizedBox(height: 16),

                        // Timeout slider
                        SettingsSliderWidget(
                          title: 'Таймаут ответа',
                          subtitle: 'Сколько минут дается на ответ',
                          value: _answerTimeoutMinutes.toDouble(),
                          min: 5,
                          max: 60,
                          divisions: 11,
                          onChanged: (value) => setState(() => _answerTimeoutMinutes = value.round()),
                          valueLabel: '$_answerTimeoutMinutes мин',
                          accentColor: Colors.blue,
                          icon: Icons.timer_outlined,
                        ),
                        const SizedBox(height: 24),

                        // Preview section
                        SettingsSectionTitle(
                          title: 'Предпросмотр',
                          gradientColors: _gradientColors,
                        ),
                        const SizedBox(height: 12),
                        BinaryPreviewWidget(
                          positiveLabel: 'Ответил',
                          negativeLabel: 'Не ответил',
                          positivePoints: _answeredPoints,
                          negativePoints: _notAnsweredPoints,
                          gradientColors: _gradientColors,
                          valueColumnTitle: 'Статус ответа',
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
