import 'package:flutter/material.dart';
import '../../services/points_settings_service.dart';
import '../../widgets/settings_widgets.dart';
import '../../widgets/points_settings_scaffold.dart';

/// Page for configuring attendance points settings (Я на работе)
class AttendancePointsSettingsPage extends StatefulWidget {
  const AttendancePointsSettingsPage({super.key});

  @override
  State<AttendancePointsSettingsPage> createState() =>
      _AttendancePointsSettingsPageState();
}

class _AttendancePointsSettingsPageState
    extends State<AttendancePointsSettingsPage> {
  // Editable values
  double _onTimePoints = 0.5;
  double _latePoints = -1;

  // Time window settings
  String _morningStartTime = '07:00';
  String _morningEndTime = '09:00';
  String _eveningStartTime = '19:00';
  String _eveningEndTime = '21:00';

  // Gradient colors for this page
  static final _gradientColors = [Color(0xFF11998e), Color(0xFF38ef7d)];

  @override
  Widget build(BuildContext context) {
    return PointsSettingsScaffold(
      title: 'Баллы за посещаемость',
      headerIcon: Icons.access_time_outlined,
      headerTitle: 'Я на работе',
      headerSubtitle: 'Баллы начисляются при отметке прихода',
      gradientColors: _gradientColors,
      onLoad: () async {
        final settings =
            await PointsSettingsService.getAttendancePointsSettings();
        _onTimePoints = settings.onTimePoints;
        _latePoints = settings.latePoints;
        _morningStartTime = settings.morningStartTime;
        _morningEndTime = settings.morningEndTime;
        _eveningStartTime = settings.eveningStartTime;
        _eveningEndTime = settings.eveningEndTime;
      },
      onSave: () async {
        final result =
            await PointsSettingsService.saveAttendancePointsSettings(
          onTimePoints: _onTimePoints,
          latePoints: _latePoints,
          morningStartTime: _morningStartTime,
          morningEndTime: _morningEndTime,
          eveningStartTime: _eveningStartTime,
          eveningEndTime: _eveningEndTime,
        );
        return result != null;
      },
      bodyBuilder: (context) => [
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
        SizedBox(height: 16),

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
        SizedBox(height: 24),

        // Time windows section
        SettingsSectionTitle(
          title: 'Временные окна посещаемости',
          gradientColors: _gradientColors,
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
          positiveLabel: 'Вовремя',
          negativeLabel: 'Опоздал',
          positivePoints: _onTimePoints,
          negativePoints: _latePoints,
          gradientColors: _gradientColors,
          valueColumnTitle: 'Статус',
          negativeIcon: Icons.warning_rounded,
          negativeIconColor: Colors.orange,
        ),
      ],
    );
  }
}
