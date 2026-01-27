import 'package:flutter/material.dart';
import '../../models/points_settings_model.dart';
import '../../services/points_settings_service.dart';
import '../../widgets/settings_widgets.dart';

/// Page for configuring RKO points settings (РКО)
class RkoPointsSettingsPage extends StatefulWidget {
  const RkoPointsSettingsPage({super.key});

  @override
  State<RkoPointsSettingsPage> createState() => _RkoPointsSettingsPageState();
}

class _RkoPointsSettingsPageState extends State<RkoPointsSettingsPage> {
  bool _isLoading = true;
  bool _isSaving = false;
  RkoPointsSettings? _settings;

  // Editable values for RKO
  double _hasRkoPoints = 1;
  double _noRkoPoints = -3;

  // Time window settings
  String _morningStartTime = '07:00';
  String _morningEndTime = '14:00';
  String _eveningStartTime = '14:00';
  String _eveningEndTime = '23:00';
  double _missedPenalty = -3.0;

  // Gradient colors for this page (indigo theme)
  static const _gradientColors = [Color(0xFF4776E6), Color(0xFF8E54E9)];

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    setState(() => _isLoading = true);

    try {
      final settings = await PointsSettingsService.getRkoPointsSettings();
      setState(() {
        _settings = settings;
        _hasRkoPoints = settings.hasRkoPoints;
        _noRkoPoints = settings.noRkoPoints;
        _morningStartTime = settings.morningStartTime;
        _morningEndTime = settings.morningEndTime;
        _eveningStartTime = settings.eveningStartTime;
        _eveningEndTime = settings.eveningEndTime;
        _missedPenalty = settings.missedPenalty;
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
      final result = await PointsSettingsService.saveRkoPointsSettings(
        hasRkoPoints: _hasRkoPoints,
        noRkoPoints: _noRkoPoints,
        morningStartTime: _morningStartTime,
        morningEndTime: _morningEndTime,
        eveningStartTime: _eveningStartTime,
        eveningEndTime: _eveningEndTime,
        missedPenalty: _missedPenalty,
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
        title: const Text('Баллы за РКО'),
        backgroundColor: _gradientColors[0],
        elevation: 0,
      ),
      body: _isLoading
          ? Center(child: CircularProgressIndicator(color: _gradientColors[0]))
          : Column(
              children: [
                // Заголовок
                SettingsHeaderCard(
                  icon: Icons.receipt_long_outlined,
                  title: 'РКО (Расходно-кассовый ордер)',
                  subtitle: 'Баллы за наличие или отсутствие РКО',
                  gradientColors: _gradientColors,
                ),
                // Контент
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Has RKO points slider
                        SettingsSliderWidget(
                          title: 'Есть РКО',
                          subtitle: 'Награда за наличие РКО',
                          value: _hasRkoPoints,
                          min: 0,
                          max: 5,
                          divisions: 50,
                          onChanged: (value) => setState(() => _hasRkoPoints = value),
                          valueLabel: '+${_hasRkoPoints.toStringAsFixed(1)}',
                          accentColor: Colors.green,
                          icon: Icons.check_circle_outline,
                        ),
                        const SizedBox(height: 16),

                        // No RKO points slider
                        SettingsSliderWidget(
                          title: 'Нет РКО',
                          subtitle: 'Штраф за отсутствие РКО',
                          value: _noRkoPoints,
                          min: -5,
                          max: 0,
                          divisions: 50,
                          onChanged: (value) => setState(() => _noRkoPoints = value),
                          valueLabel: _noRkoPoints.toStringAsFixed(1),
                          accentColor: Colors.red,
                          icon: Icons.cancel_outlined,
                        ),
                        const SizedBox(height: 24),

                        // Time windows section
                        SettingsSectionTitle(
                          title: 'Временные окна для РКО',
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

                        // Missed penalty slider
                        SettingsSliderWidget(
                          title: 'Штраф за пропуск',
                          subtitle: 'Баллы за несданное РКО',
                          value: _missedPenalty,
                          min: -10,
                          max: 0,
                          divisions: 100,
                          onChanged: (value) => setState(() => _missedPenalty = value),
                          valueLabel: _missedPenalty.toStringAsFixed(1),
                          accentColor: Colors.deepOrange,
                          icon: Icons.warning_amber_outlined,
                        ),
                        const SizedBox(height: 24),

                        // Preview section
                        SettingsSectionTitle(
                          title: 'Предпросмотр',
                          gradientColors: _gradientColors,
                        ),
                        const SizedBox(height: 12),
                        BinaryPreviewWidget(
                          positiveLabel: 'Есть РКО',
                          negativeLabel: 'Нет РКО',
                          positivePoints: _hasRkoPoints,
                          negativePoints: _noRkoPoints,
                          gradientColors: _gradientColors,
                          valueColumnTitle: 'Статус РКО',
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
