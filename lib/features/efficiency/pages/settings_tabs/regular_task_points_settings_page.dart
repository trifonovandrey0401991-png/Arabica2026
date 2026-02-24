import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../services/points_settings_service.dart';
import '../../widgets/settings_widgets.dart';
import '../../widgets/points_settings_scaffold.dart';

class RegularTaskPointsSettingsPage extends StatefulWidget {
  const RegularTaskPointsSettingsPage({super.key});

  @override
  State<RegularTaskPointsSettingsPage> createState() =>
      _RegularTaskPointsSettingsPageState();
}

class _RegularTaskPointsSettingsPageState
    extends State<RegularTaskPointsSettingsPage> {
  double _completionPoints = 1.0;
  double _penaltyPoints = -3.0;

  // Gradient colors for this page (blue theme)
  static final _gradientColors = [Color(0xFF667eea), Color(0xFF764ba2)];

  @override
  Widget build(BuildContext context) {
    return PointsSettingsScaffold(
      title: 'Обычные задачи',
      headerIcon: Icons.task_alt,
      headerTitle: 'Обычные задачи',
      headerSubtitle: 'Баллы за выполнение/невыполнение задач',
      gradientColors: _gradientColors,
      popOnSave: true,
      onLoad: () async {
        final settings =
            await PointsSettingsService.getRegularTaskPointsSettings();
        _completionPoints = settings.completionPoints;
        _penaltyPoints = settings.penaltyPoints;
      },
      onSave: () async {
        await PointsSettingsService.saveRegularTaskPointsSettings(
          completionPoints: _completionPoints,
          penaltyPoints: _penaltyPoints,
        );
        return true;
      },
      bodyBuilder: (context) => [
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
        SizedBox(height: 16),

        // Penalty points slider
        SettingsSliderWidget(
          title: 'Штраф за невыполнение',
          subtitle: 'Баллы за просроченную/отклонённую задачу',
          value: _penaltyPoints,
          min: -10,
          max: 0,
          divisions: 100,
          onChanged: (value) => setState(() => _penaltyPoints = value),
          valueLabel: _penaltyPoints.toStringAsFixed(1),
          accentColor: Colors.red,
          icon: Icons.cancel_outlined,
        ),
        SizedBox(height: 24),

        // Info box
        Container(
          padding: EdgeInsets.all(16.w),
          decoration: BoxDecoration(
            color: Colors.blue.withOpacity(0.1),
            borderRadius: BorderRadius.circular(16.r),
            border: Border.all(color: Colors.blue.withOpacity(0.3)),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: Colors.blue.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(10.r),
                ),
                child:
                    Icon(Icons.info_outline, color: Colors.blue, size: 22),
              ),
              SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Новые правила будут применяться только к новым задачам. Существующие задачи сохранят прежние баллы.',
                  style: TextStyle(
                    color: Colors.blue[300],
                    fontSize: 13.sp,
                  ),
                ),
              ),
            ],
          ),
        ),
        SizedBox(height: 24),

        // Preview section
        SettingsSectionTitle(
          title: 'Предпросмотр',
          gradientColors: _gradientColors,
        ),
        SizedBox(height: 12),
        BinaryPreviewWidget(
          positiveLabel: 'Выполнена',
          negativeLabel: 'Не выполнена',
          positivePoints: _completionPoints,
          negativePoints: _penaltyPoints,
          gradientColors: _gradientColors,
          valueColumnTitle: 'Статус задачи',
        ),
      ],
    );
  }
}
