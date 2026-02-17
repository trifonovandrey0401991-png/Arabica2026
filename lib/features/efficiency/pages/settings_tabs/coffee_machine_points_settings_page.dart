import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../services/points_settings_service.dart';
import '../../widgets/settings_widgets.dart';
import '../../widgets/points_settings_scaffold.dart';
import '../../../../core/theme/app_colors.dart';

/// Page for configuring coffee machine counter points settings
class CoffeeMachinePointsSettingsPage extends StatefulWidget {
  const CoffeeMachinePointsSettingsPage({super.key});

  @override
  State<CoffeeMachinePointsSettingsPage> createState() =>
      _CoffeeMachinePointsSettingsPageState();
}

class _CoffeeMachinePointsSettingsPageState
    extends State<CoffeeMachinePointsSettingsPage> {
  // Editable values
  double _submittedPoints = 1.0;
  double _notSubmittedPoints = -3.0;

  // Time window settings
  String _morningStartTime = '07:00';
  String _morningEndTime = '12:00';
  String _eveningStartTime = '14:00';
  String _eveningEndTime = '22:00';

  // Gradient colors for this page (gold theme)
  static final _gradientColors = [AppColors.gold, Color(0xFFF0C850)];

  @override
  Widget build(BuildContext context) {
    return PointsSettingsScaffold(
      title: 'Баллы за счётчик кофе',
      headerIcon: Icons.coffee_outlined,
      headerTitle: 'Счётчик кофемашин',
      headerSubtitle: 'Баллы за сдачу/несдачу показаний счётчика',
      gradientColors: _gradientColors,
      onLoad: () async {
        final settings =
            await PointsSettingsService.getCoffeeMachinePointsSettings();
        _submittedPoints = settings.submittedPoints;
        _notSubmittedPoints = settings.notSubmittedPoints;
        _morningStartTime = settings.morningStartTime;
        _morningEndTime = settings.morningEndTime;
        _eveningStartTime = settings.eveningStartTime;
        _eveningEndTime = settings.eveningEndTime;
      },
      onSave: () async {
        final result =
            await PointsSettingsService.saveCoffeeMachinePointsSettings(
          submittedPoints: _submittedPoints,
          notSubmittedPoints: _notSubmittedPoints,
          morningStartTime: _morningStartTime,
          morningEndTime: _morningEndTime,
          eveningStartTime: _eveningStartTime,
          eveningEndTime: _eveningEndTime,
        );
        return result != null;
      },
      bodyBuilder: (context) => [
        // Submitted points slider
        SettingsSliderWidget(
          title: 'Счётчик сдан',
          subtitle: 'Награда за сданные показания',
          value: _submittedPoints,
          min: 0,
          max: 5,
          divisions: 50,
          onChanged: (value) => setState(() => _submittedPoints = value),
          valueLabel: '+${_submittedPoints.toStringAsFixed(1)}',
          accentColor: Colors.green,
          icon: Icons.check_circle_outline,
        ),
        SizedBox(height: 16),

        // Not submitted points slider
        SettingsSliderWidget(
          title: 'Счётчик не сдан',
          subtitle: 'Штраф за несданные показания',
          value: _notSubmittedPoints,
          min: -10,
          max: 0,
          divisions: 100,
          onChanged: (value) => setState(() => _notSubmittedPoints = value),
          valueLabel: _notSubmittedPoints.toStringAsFixed(1),
          accentColor: Colors.red,
          icon: Icons.cancel_outlined,
        ),
        SizedBox(height: 24),

        // Time windows section
        SettingsSectionTitle(
          title: 'Временные окна для сдачи счётчика',
          gradientColors: _gradientColors,
        ),
        SizedBox(height: 8),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 8.h),
          child: Text(
            'Укажите временное окно, в течение которого сотрудник должен сдать показания счётчика кофемашин',
            style: TextStyle(
              fontSize: 13.sp,
              color: Color(0xFF607D8B),
              height: 1.4,
            ),
          ),
        ),
        SizedBox(height: 12),
        TimeWindowsSection(
          windows: [
            TimeWindowPickerWidget(
              icon: Icons.wb_sunny_outlined,
              iconColor: Colors.orange,
              title: 'Утренняя смена',
              startTime: _morningStartTime,
              endTime: _morningEndTime,
              onStartChanged: (time) =>
                  setState(() => _morningStartTime = time),
              onEndChanged: (time) => setState(() => _morningEndTime = time),
              primaryColor: _gradientColors[0],
              startLabel: 'Начало',
              endLabel: 'Дедлайн',
            ),
            TimeWindowPickerWidget(
              icon: Icons.nights_stay_outlined,
              iconColor: Colors.indigo,
              title: 'Вечерняя смена',
              startTime: _eveningStartTime,
              endTime: _eveningEndTime,
              onStartChanged: (time) =>
                  setState(() => _eveningStartTime = time),
              onEndChanged: (time) => setState(() => _eveningEndTime = time),
              primaryColor: _gradientColors[0],
              startLabel: 'Начало',
              endLabel: 'Дедлайн',
            ),
          ],
        ),
        SizedBox(height: 24),

        // Preview section
        SettingsSectionTitle(
          title: 'Предпросмотр',
          gradientColors: _gradientColors,
        ),
        SizedBox(height: 12),
        BinaryPreviewWidget(
          positiveLabel: 'Сдан',
          negativeLabel: 'Не сдан',
          positivePoints: _submittedPoints,
          negativePoints: _notSubmittedPoints,
          gradientColors: _gradientColors,
          valueColumnTitle: 'Статус',
        ),
      ],
    );
  }
}
