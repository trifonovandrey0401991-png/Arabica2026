import 'package:flutter/material.dart';
import '../../models/points_settings_model.dart';
import '../../services/points_settings_service.dart';
import '../../widgets/settings_widgets.dart';

/// Page for configuring attendance points settings (Я на работе)
class AttendancePointsSettingsPage extends StatefulWidget {
  const AttendancePointsSettingsPage({super.key});

  @override
  State<AttendancePointsSettingsPage> createState() =>
      _AttendancePointsSettingsPageState();
}

class _AttendancePointsSettingsPageState
    extends State<AttendancePointsSettingsPage> {
  bool _isLoading = true;
  bool _isSaving = false;
  AttendancePointsSettings? _settings;

  // Editable values
  double _onTimePoints = 0.5;
  double _latePoints = -1;

  // Time window settings
  String _morningStartTime = '07:00';
  String _morningEndTime = '09:00';
  String _eveningStartTime = '19:00';
  String _eveningEndTime = '21:00';

  // Gradient colors for this page
  static const _gradientColors = [Color(0xFF11998e), Color(0xFF38ef7d)];

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    setState(() => _isLoading = true);

    try {
      final settings =
          await PointsSettingsService.getAttendancePointsSettings();
      setState(() {
        _settings = settings;
        _onTimePoints = settings.onTimePoints;
        _latePoints = settings.latePoints;
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
      final result = await PointsSettingsService.saveAttendancePointsSettings(
        onTimePoints: _onTimePoints,
        latePoints: _latePoints,
        morningStartTime: _morningStartTime,
        morningEndTime: _morningEndTime,
        eveningStartTime: _eveningStartTime,
        eveningEndTime: _eveningEndTime,
      );

      if (result != null) {
        setState(() {
          _settings = result;
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
        title: const Text('Баллы за посещаемость'),
        backgroundColor: _gradientColors[0],
        elevation: 0,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF11998e)))
          : Column(
              children: [
                // Заголовок
                SettingsHeaderCard(
                  icon: Icons.access_time_outlined,
                  title: 'Я на работе',
                  subtitle: 'Баллы начисляются при отметке прихода',
                  gradientColors: _gradientColors,
                ),
                // Контент
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // On time points slider
                        SettingsSliderWidget(
                          title: 'Пришел вовремя',
                          subtitle: 'Награда за приход без опоздания',
                          value: _onTimePoints,
                          min: 0,
                          max: 2,
                          divisions: 20,
                          onChanged: (value) => setState(() => _onTimePoints = value),
                          valueLabel: '+${_onTimePoints.toStringAsFixed(1)}',
                          accentColor: Colors.green,
                          icon: Icons.check_circle_outline,
                        ),
                        const SizedBox(height: 16),

                        // Late points slider
                        SettingsSliderWidget(
                          title: 'Опоздал',
                          subtitle: 'Штраф за опоздание',
                          value: _latePoints,
                          min: -3,
                          max: 0,
                          divisions: 30,
                          onChanged: (value) => setState(() => _latePoints = value),
                          valueLabel: _latePoints.toStringAsFixed(1),
                          accentColor: Colors.red,
                          icon: Icons.access_time_filled,
                        ),
                        const SizedBox(height: 24),

                        // Time windows section
                        SettingsSectionTitle(
                          title: 'Временные окна посещаемости',
                          gradientColors: _gradientColors,
                        ),
                        const SizedBox(height: 12),
                        TimeWindowsSection(
                          windows: [
                            TimeWindowPickerWidget(
                              icon: Icons.wb_sunny_outlined,
                              iconColor: Colors.orange,
                              title: 'Утренняя смена',
                              startTime: _morningStartTime,
                              endTime: _morningEndTime,
                              onStartChanged: (time) => setState(() => _morningStartTime = time),
                              onEndChanged: (time) => setState(() => _morningEndTime = time),
                              primaryColor: _gradientColors[0],
                            ),
                            TimeWindowPickerWidget(
                              icon: Icons.nights_stay_outlined,
                              iconColor: Colors.indigo,
                              title: 'Вечерняя смена',
                              startTime: _eveningStartTime,
                              endTime: _eveningEndTime,
                              onStartChanged: (time) => setState(() => _eveningStartTime = time),
                              onEndChanged: (time) => setState(() => _eveningEndTime = time),
                              primaryColor: _gradientColors[0],
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
                          positiveLabel: 'Вовремя',
                          negativeLabel: 'Опоздал',
                          positivePoints: _onTimePoints,
                          negativePoints: _latePoints,
                          gradientColors: _gradientColors,
                          valueColumnTitle: 'Статус',
                          negativeIcon: Icons.warning_rounded,
                          negativeIconColor: Colors.orange,
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
