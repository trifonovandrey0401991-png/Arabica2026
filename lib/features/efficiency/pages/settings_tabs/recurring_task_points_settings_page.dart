import 'package:flutter/material.dart';
import '../../services/points_settings_service.dart';
import '../../widgets/settings_widgets.dart';
import '../../../../core/utils/logger.dart';

class RecurringTaskPointsSettingsPage extends StatefulWidget {
  const RecurringTaskPointsSettingsPage({super.key});

  @override
  State<RecurringTaskPointsSettingsPage> createState() => _RecurringTaskPointsSettingsPageState();
}

class _RecurringTaskPointsSettingsPageState extends State<RecurringTaskPointsSettingsPage> {
  bool _isLoading = false;
  bool _isSaving = false;

  double _completionPoints = 1.0;
  double _penaltyPoints = -3.0;

  // Gradient colors for this page (purple theme)
  static const _gradientColors = [Color(0xFF8E2DE2), Color(0xFF4A00E0)];

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    setState(() => _isLoading = true);
    try {
      final settings = await PointsSettingsService.getRecurringTaskPointsSettings();
      setState(() {
        _completionPoints = settings.completionPoints;
        _penaltyPoints = settings.penaltyPoints;
      });
    } catch (e) {
      Logger.error('Ошибка загрузки настроек циклических задач', e);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка загрузки: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _saveSettings() async {
    setState(() => _isSaving = true);
    try {
      await PointsSettingsService.saveRecurringTaskPointsSettings(
        completionPoints: _completionPoints,
        penaltyPoints: _penaltyPoints,
      );

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
        Navigator.pop(context);
      }
    } catch (e) {
      Logger.error('Ошибка сохранения настроек циклических задач', e);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка сохранения: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        title: const Text('Циклические задачи'),
        backgroundColor: _gradientColors[0],
        elevation: 0,
      ),
      body: _isLoading
          ? Center(child: CircularProgressIndicator(color: _gradientColors[0]))
          : Column(
              children: [
                // Заголовок
                SettingsHeaderCard(
                  icon: Icons.repeat,
                  title: 'Циклические задачи',
                  subtitle: 'Баллы за повторяющиеся задачи',
                  gradientColors: _gradientColors,
                ),
                // Контент
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Completion points slider
                        SettingsSliderWidget(
                          title: 'Премия за выполнение',
                          subtitle: 'Баллы за выполненную задачу',
                          value: _completionPoints,
                          min: 0,
                          max: 10,
                          divisions: 100,
                          onChanged: (value) => setState(() => _completionPoints = value),
                          valueLabel: '+${_completionPoints.toStringAsFixed(1)}',
                          accentColor: Colors.green,
                          icon: Icons.check_circle_outline,
                        ),
                        const SizedBox(height: 16),

                        // Penalty points slider
                        SettingsSliderWidget(
                          title: 'Штраф за невыполнение',
                          subtitle: 'Баллы за просроченную задачу',
                          value: _penaltyPoints,
                          min: -10,
                          max: 0,
                          divisions: 100,
                          onChanged: (value) => setState(() => _penaltyPoints = value),
                          valueLabel: _penaltyPoints.toStringAsFixed(1),
                          accentColor: Colors.red,
                          icon: Icons.cancel_outlined,
                        ),
                        const SizedBox(height: 24),

                        // Info box (уникальный для этой страницы - оранжевый)
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.orange.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: Colors.orange.withOpacity(0.3)),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 40,
                                height: 40,
                                decoration: BoxDecoration(
                                  color: Colors.orange.withOpacity(0.2),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: const Icon(Icons.info_outline, color: Colors.orange, size: 22),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  'Циклические задачи повторяются каждую смену. Новые правила будут применяться только к новым задачам.',
                                  style: TextStyle(
                                    color: Colors.orange[900],
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 24),

                        // Preview section
                        SettingsSectionTitle(
                          title: 'Предпросмотр',
                          gradientColors: _gradientColors,
                        ),
                        const SizedBox(height: 12),
                        BinaryPreviewWidget(
                          positiveLabel: 'Выполнена',
                          negativeLabel: 'Просрочена',
                          positivePoints: _completionPoints,
                          negativePoints: _penaltyPoints,
                          gradientColors: _gradientColors,
                          valueColumnTitle: 'Статус задачи',
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
