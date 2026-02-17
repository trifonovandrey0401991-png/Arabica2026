import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../services/points_settings_service.dart';
import '../../widgets/settings_widgets.dart';
import '../../widgets/points_settings_scaffold.dart';

/// Page for configuring envelope points settings (Конверт)
class EnvelopePointsSettingsPage extends StatefulWidget {
  const EnvelopePointsSettingsPage({super.key});

  @override
  State<EnvelopePointsSettingsPage> createState() =>
      _EnvelopePointsSettingsPageState();
}

class _EnvelopePointsSettingsPageState
    extends State<EnvelopePointsSettingsPage> {
  // Editable values
  double _submittedPoints = 1.0;
  double _notSubmittedPoints = -3.0;

  // Time window settings
  String _morningStartTime = '08:00';
  String _morningEndTime = '12:00';
  String _eveningStartTime = '08:00';
  String _eveningEndTime = '12:00';

  // Gradient colors for this page (deep orange theme)
  static final _gradientColors = [Color(0xFFff6a00), Color(0xFFee0979)];

  @override
  Widget build(BuildContext context) {
    return PointsSettingsScaffold(
      title: 'Баллы за конверт',
      headerIcon: Icons.mail_outlined,
      headerTitle: 'Сдача конверта',
      headerSubtitle: 'Баллы за сдачу/несдачу конверта в конце смены',
      gradientColors: _gradientColors,
      onLoad: () async {
        final settings =
            await PointsSettingsService.getEnvelopePointsSettings();
        _submittedPoints = settings.submittedPoints;
        _notSubmittedPoints = settings.notSubmittedPoints;
        _morningStartTime = settings.morningStartTime;
        _morningEndTime = settings.morningEndTime;
        _eveningStartTime = settings.eveningStartTime;
        _eveningEndTime = settings.eveningEndTime;
      },
      onSave: () async {
        final result = await PointsSettingsService.saveEnvelopePointsSettings(
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
        SizedBox(height: 16),

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
        SizedBox(height: 24),

        // Time windows section
        SettingsSectionTitle(
          title: 'Временные окна для сдачи конверта',
          gradientColors: _gradientColors,
        ),
        SizedBox(height: 8),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 8.h),
          child: Text(
            'Укажите временное окно на следующий день, в течение которого должен быть сдан конверт',
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
              title: 'После утренней смены',
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
              title: 'После вечерней смены',
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
