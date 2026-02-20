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

  // Admin review timeout (hours, 0 = disabled)
  int _adminReviewTimeout = 0;

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
        _adminReviewTimeout = settings.adminReviewTimeout;
      },
      onSave: () async {
        final result = await PointsSettingsService.saveEnvelopePointsSettings(
          submittedPoints: _submittedPoints,
          notSubmittedPoints: _notSubmittedPoints,
          morningStartTime: _morningStartTime,
          morningEndTime: _morningEndTime,
          eveningStartTime: _eveningStartTime,
          eveningEndTime: _eveningEndTime,
          adminReviewTimeout: _adminReviewTimeout,
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

        // Admin review timeout section
        _buildAdminReviewTimeoutSection(),
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

  Widget _buildAdminReviewTimeoutSection() {
    String formatHours(int hours) {
      if (hours == 0) return 'Выкл';
      if (hours == 1 || hours == 21) return '$hours час';
      if (hours >= 2 && hours <= 4 || hours >= 22 && hours <= 24) return '$hours часа';
      return '$hours часов';
    }

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16.r),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
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
                child: Icon(
                  Icons.admin_panel_settings_outlined,
                  color: Colors.purple,
                  size: 24,
                ),
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
                      'Время админу на проверку конверта',
                      style: TextStyle(
                        fontSize: 12.sp,
                        color: Colors.grey,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 8.h),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: _adminReviewTimeout == 0
                        ? [Colors.grey, Colors.grey[600]!]
                        : [Colors.purple, Colors.deepPurple],
                  ),
                  borderRadius: BorderRadius.circular(20.r),
                  boxShadow: [
                    BoxShadow(
                      color: (_adminReviewTimeout == 0 ? Colors.grey : Colors.purple).withOpacity(0.3),
                      blurRadius: 8,
                      offset: Offset(0, 4),
                    ),
                  ],
                ),
                child: Text(
                  formatHours(_adminReviewTimeout),
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
              min: 0,
              max: 24,
              divisions: 24,
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
                Text('Выкл', style: TextStyle(fontSize: 12.sp, color: Colors.grey[600])),
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
              color: _adminReviewTimeout == 0
                  ? Colors.grey.withOpacity(0.1)
                  : Colors.amber.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12.r),
              border: Border.all(
                color: _adminReviewTimeout == 0
                    ? Colors.grey.withOpacity(0.3)
                    : Colors.amber.withOpacity(0.3),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.info_outline,
                  color: _adminReviewTimeout == 0 ? Colors.grey : Colors.amber[700],
                  size: 20,
                ),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _adminReviewTimeout == 0
                        ? 'Таймаут отключён. Конверты на проверке будут ожидать подтверждения бессрочно'
                        : 'Если админ не проверит конверт за ${formatHours(_adminReviewTimeout)}, статус изменится на "Не сдан" и управляющая получит штраф',
                    style: TextStyle(
                      fontSize: 12.sp,
                      color: _adminReviewTimeout == 0 ? Colors.grey[700] : Colors.amber[900],
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
