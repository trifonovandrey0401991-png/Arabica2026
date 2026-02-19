import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../services/points_settings_service.dart';
import '../../widgets/settings_widgets.dart';
import '../../widgets/points_settings_scaffold.dart';

/// Page for configuring recount efficiency points settings (Пересчет - баллы эффективности)
/// Не путать с RecountPointsSettingsPage из recount/pages - там настройки баллов верификации фото
class RecountEfficiencyPointsSettingsPage extends StatefulWidget {
  const RecountEfficiencyPointsSettingsPage({super.key});

  @override
  State<RecountEfficiencyPointsSettingsPage> createState() =>
      _RecountEfficiencyPointsSettingsPageState();
}

class _RecountEfficiencyPointsSettingsPageState
    extends State<RecountEfficiencyPointsSettingsPage> {
  // Editable values
  double _minPoints = -3;
  int _zeroThreshold = 7;
  double _maxPoints = 1;

  // Time window settings
  String _morningStartTime = '08:00';
  String _morningEndTime = '14:00';
  String _eveningStartTime = '14:00';
  String _eveningEndTime = '23:00';
  double _missedPenalty = -3.0;
  int _adminReviewTimeout = 2;

  // Gradient colors for this page (teal theme)
  static final _gradientColors = [Color(0xFF00b09b), Color(0xFF96c93d)];

  /// Calculate points using current settings (local calculation)
  double _calculatePoints(int rating) {
    if (rating <= 1) return _minPoints;
    if (rating >= 10) return _maxPoints;

    if (rating <= _zeroThreshold) {
      final range = _zeroThreshold - 1;
      return _minPoints + (0 - _minPoints) * ((rating - 1) / range);
    } else {
      final range = 10 - _zeroThreshold;
      return 0 + (_maxPoints - 0) * ((rating - _zeroThreshold) / range);
    }
  }

  /// Format hours for display
  String _formatHours(int hours) {
    if (hours == 1 || hours == 21) return '$hours час';
    if (hours >= 2 && hours <= 4 || hours >= 22 && hours <= 24) return '$hours часа';
    return '$hours часов';
  }

  @override
  Widget build(BuildContext context) {
    return PointsSettingsScaffold(
      title: 'Баллы за пересчет',
      headerIcon: Icons.inventory_2_outlined,
      headerTitle: 'Оценка пересчета: 1-10',
      headerSubtitle: 'Баллы начисляются при оценке отчета',
      gradientColors: _gradientColors,
      onLoad: () async {
        final settings =
            await PointsSettingsService.getRecountPointsSettings();
        _minPoints = settings.minPoints;
        _zeroThreshold = settings.zeroThreshold;
        _maxPoints = settings.maxPoints;
        _morningStartTime = settings.morningStartTime;
        _morningEndTime = settings.morningEndTime;
        _eveningStartTime = settings.eveningStartTime;
        _eveningEndTime = settings.eveningEndTime;
        _missedPenalty = settings.missedPenalty;
        _adminReviewTimeout = settings.adminReviewTimeout;
      },
      onSave: () async {
        final result = await PointsSettingsService.saveRecountPointsSettings(
          minPoints: _minPoints,
          zeroThreshold: _zeroThreshold,
          maxPoints: _maxPoints,
          morningStartTime: _morningStartTime,
          morningEndTime: _morningEndTime,
          eveningStartTime: _eveningStartTime,
          eveningEndTime: _eveningEndTime,
          missedPenalty: _missedPenalty,
          adminReviewTimeout: _adminReviewTimeout,
        );
        return result != null;
      },
      bodyBuilder: (context) => [
        // Min points slider
        SettingsSliderWidget(
          title: 'Минимальная оценка (1)',
          subtitle: 'Штраф за плохой пересчет',
          value: _minPoints,
          min: -5,
          max: 0,
          divisions: 50,
          onChanged: (value) => setState(() => _minPoints = value),
          valueLabel: _minPoints.toStringAsFixed(1),
          accentColor: Colors.red,
          icon: Icons.remove_circle_outline,
        ),
        SizedBox(height: 16),

        // Zero threshold slider
        SettingsSliderWidget(
          title: 'Нулевая граница',
          subtitle: 'Оценка, дающая 0 баллов',
          value: _zeroThreshold.toDouble(),
          min: 2,
          max: 9,
          divisions: 7,
          onChanged: (value) => setState(() => _zeroThreshold = value.round()),
          valueLabel: _zeroThreshold.toString(),
          isInteger: true,
          accentColor: Colors.orange,
          icon: Icons.adjust,
        ),
        SizedBox(height: 16),

        // Max points slider
        SettingsSliderWidget(
          title: 'Максимальная оценка (10)',
          subtitle: 'Награда за отличный пересчет',
          value: _maxPoints,
          min: 0,
          max: 5,
          divisions: 50,
          onChanged: (value) => setState(() => _maxPoints = value),
          valueLabel: '+${_maxPoints.toStringAsFixed(1)}',
          accentColor: Colors.green,
          icon: Icons.add_circle_outline,
        ),
        SizedBox(height: 24),

        // Time windows section
        SettingsSectionTitle(
          title: 'Временные окна сдачи пересчёта',
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
        SizedBox(height: 24),

        // Missed penalty slider
        SettingsSliderWidget(
          title: 'Штраф за пропуск',
          subtitle: 'Баллы за несданный пересчёт',
          value: _missedPenalty,
          min: -10,
          max: 0,
          divisions: 100,
          onChanged: (value) => setState(() => _missedPenalty = value),
          valueLabel: _missedPenalty.toStringAsFixed(1),
          accentColor: Colors.deepOrange,
          icon: Icons.warning_amber_outlined,
        ),
        SizedBox(height: 24),

        // Admin review timeout section
        SettingsSectionTitle(
          title: 'Время на проверку админом',
          gradientColors: _gradientColors,
        ),
        SizedBox(height: 12),
        _buildAdminReviewTimeoutSection(),
        SizedBox(height: 24),

        // Preview section
        SettingsSectionTitle(
          title: 'Предпросмотр расчета баллов',
          gradientColors: _gradientColors,
        ),
        SizedBox(height: 12),
        RatingPreviewWidget(
          previewRatings: [1, 4, _zeroThreshold, 8, 10],
          calculatePoints: _calculatePoints,
          gradientColors: _gradientColors,
        ),
      ],
    );
  }

  Widget _buildAdminReviewTimeoutSection() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20.r),
        boxShadow: [
          BoxShadow(
            color: Colors.purple.withOpacity(0.1),
            blurRadius: 15,
            offset: Offset(0, 5),
          ),
        ],
      ),
      padding: EdgeInsets.all(20.w),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: Colors.purple.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12.r),
                ),
                child: Icon(Icons.admin_panel_settings, color: Colors.purple, size: 24),
              ),
              SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Таймаут проверки',
                      style: TextStyle(
                        fontSize: 16.sp,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF2D3436),
                      ),
                    ),
                    Text(
                      'Время на оценку отчёта админом',
                      style: TextStyle(
                        fontSize: 12.sp,
                        color: Colors.grey[500],
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 8.h),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Colors.purple, Colors.deepPurple],
                  ),
                  borderRadius: BorderRadius.circular(20.r),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.purple.withOpacity(0.3),
                      blurRadius: 8,
                      offset: Offset(0, 4),
                    ),
                  ],
                ),
                child: Text(
                  _formatHours(_adminReviewTimeout),
                  style: TextStyle(
                    fontSize: 14.sp,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: 20),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: Colors.purple,
              inactiveTrackColor: Colors.purple.withOpacity(0.2),
              thumbColor: Colors.purple,
              overlayColor: Colors.purple.withOpacity(0.2),
              trackHeight: 6,
              thumbShape: RoundSliderThumbShape(enabledThumbRadius: 10),
            ),
            child: Slider(
              value: _adminReviewTimeout.toDouble(),
              min: 1,
              max: 24,
              divisions: 23,
              onChanged: (value) {
                if (mounted) setState(() => _adminReviewTimeout = value.round());
              },
            ),
          ),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 8.w),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('1 ч', style: TextStyle(fontSize: 12.sp, color: Colors.grey[600])),
                Text('6 ч', style: TextStyle(fontSize: 12.sp, color: Colors.grey[600])),
                Text('12 ч', style: TextStyle(fontSize: 12.sp, color: Colors.grey[600])),
                Text('18 ч', style: TextStyle(fontSize: 12.sp, color: Colors.grey[600])),
                Text('24 ч', style: TextStyle(fontSize: 12.sp, color: Colors.grey[600])),
              ],
            ),
          ),
          SizedBox(height: 16),
          Container(
            padding: EdgeInsets.all(12.w),
            decoration: BoxDecoration(
              color: Colors.amber.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12.r),
              border: Border.all(color: Colors.amber.withOpacity(0.3)),
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline, color: Colors.amber[700], size: 20),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Если админ не оценит отчёт за ${_formatHours(_adminReviewTimeout)}, статус изменится на "Отклонено" и сотрудник получит штраф',
                    style: TextStyle(
                      fontSize: 12.sp,
                      color: Colors.amber[900],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
