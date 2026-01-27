import 'package:flutter/material.dart';
import '../../services/points_settings_service.dart';
import '../../widgets/settings_widgets.dart';

/// Page for configuring envelope points settings (Конверт)
class EnvelopePointsSettingsPage extends StatefulWidget {
  const EnvelopePointsSettingsPage({super.key});

  @override
  State<EnvelopePointsSettingsPage> createState() =>
      _EnvelopePointsSettingsPageState();
}

class _EnvelopePointsSettingsPageState
    extends State<EnvelopePointsSettingsPage> {
  bool _isLoading = true;
  bool _isSaving = false;

  // Editable values
  double _submittedPoints = 1.0;
  double _notSubmittedPoints = -3.0;

  // Time window settings
  String _morningStartTime = '08:00';
  String _morningEndTime = '12:00';
  String _eveningStartTime = '08:00';
  String _eveningEndTime = '12:00';

  // Gradient colors for this page (deep orange theme)
  static const _gradientColors = [Color(0xFFff6a00), Color(0xFFee0979)];

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    setState(() => _isLoading = true);

    try {
      final settings =
          await PointsSettingsService.getEnvelopePointsSettings();
      setState(() {
        _submittedPoints = settings.submittedPoints;
        _notSubmittedPoints = settings.notSubmittedPoints;
        _morningStartTime = settings.morningStartTime;
        _morningEndTime = settings.morningEndTime;
        _eveningStartTime = settings.eveningStartTime;
        _eveningEndTime = settings.eveningEndTime;
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
      final result = await PointsSettingsService.saveEnvelopePointsSettings(
        submittedPoints: _submittedPoints,
        notSubmittedPoints: _notSubmittedPoints,
        morningStartTime: _morningStartTime,
        morningEndTime: _morningEndTime,
        eveningStartTime: _eveningStartTime,
        eveningEndTime: _eveningEndTime,
      );

      if (result != null) {
        setState(() {
          _isSaving = false;
        });
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
          SnackBar(
            content: Text('Ошибка сохранения: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        title: const Text('Баллы за конверт'),
        backgroundColor: _gradientColors[0],
        elevation: 0,
      ),
      body: _isLoading
          ? Center(child: CircularProgressIndicator(color: _gradientColors[0]))
          : Column(
              children: [
                // Заголовок
                SettingsHeaderCard(
                  icon: Icons.mail_outlined,
                  title: 'Сдача конверта',
                  subtitle: 'Баллы за сдачу/несдачу конверта в конце смены',
                  gradientColors: _gradientColors,
                ),
                // Контент
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Submitted points slider
                        SettingsSliderWidget(
                          title: 'Конверт сдан',
                          subtitle: 'Награда за сданный конверт',
                          value: _submittedPoints,
                          min: 0,
                          max: 5,
                          divisions: 50,
                          onChanged: (value) => setState(() => _submittedPoints = value),
                          valueLabel: '+${_submittedPoints.toStringAsFixed(1)}',
                          accentColor: Colors.green,
                          icon: Icons.check_circle_outline,
                        ),
                        const SizedBox(height: 16),

                        // Not submitted points slider
                        SettingsSliderWidget(
                          title: 'Конверт не сдан',
                          subtitle: 'Штраф за несданный конверт',
                          value: _notSubmittedPoints,
                          min: -10,
                          max: 0,
                          divisions: 100,
                          onChanged: (value) => setState(() => _notSubmittedPoints = value),
                          valueLabel: _notSubmittedPoints.toStringAsFixed(1),
                          accentColor: Colors.red,
                          icon: Icons.cancel_outlined,
                        ),
                        const SizedBox(height: 24),

                        // Time windows section
                        SettingsSectionTitle(
                          title: 'Временные окна для сдачи конверта',
                          gradientColors: _gradientColors,
                        ),
                        const SizedBox(height: 8),
                        const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          child: Text(
                            'Укажите временное окно на следующий день, в течение которого должен быть сдан конверт',
                            style: TextStyle(
                              fontSize: 13,
                              color: Color(0xFF607D8B),
                              height: 1.4,
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        TimeWindowsSection(
                          windows: [
                            TimeWindowPickerWidget(
                              icon: Icons.wb_sunny_outlined,
                              iconColor: Colors.orange,
                              title: 'После утренней смены',
                              startTime: _morningStartTime,
                              endTime: _morningEndTime,
                              onStartChanged: (time) => setState(() => _morningStartTime = time),
                              onEndChanged: (time) => setState(() => _morningEndTime = time),
                              primaryColor: _gradientColors[0],
                              startLabel: 'Начало',
                              endLabel: 'Дедлайн',
                            ),
                            TimeWindowPickerWidget(
                              icon: Icons.nights_stay_outlined,
                              iconColor: Colors.indigo,
                              title: 'После вечерней смены',
                              startTime: _eveningStartTime,
                              endTime: _eveningEndTime,
                              onStartChanged: (time) => setState(() => _eveningStartTime = time),
                              onEndChanged: (time) => setState(() => _eveningEndTime = time),
                              primaryColor: _gradientColors[0],
                              startLabel: 'Начало',
                              endLabel: 'Дедлайн',
                            ),
                          ],
                        ),
                        const SizedBox(height: 24),

                        // Preview section
                        SettingsSectionTitle(
                          title: 'Предпросмотр',
                          gradientColors: _gradientColors,
                        ),
                        const SizedBox(height: 12),
                        BinaryPreviewWidget(
                          positiveLabel: 'Сдан',
                          negativeLabel: 'Не сдан',
                          positivePoints: _submittedPoints,
                          negativePoints: _notSubmittedPoints,
                          gradientColors: _gradientColors,
                          valueColumnTitle: 'Статус',
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
