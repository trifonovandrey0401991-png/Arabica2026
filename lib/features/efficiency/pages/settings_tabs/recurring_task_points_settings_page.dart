import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../services/points_settings_service.dart';
import '../../widgets/settings_widgets.dart';
import '../../widgets/points_settings_scaffold.dart';

class RecurringTaskPointsSettingsPage extends StatefulWidget {
  const RecurringTaskPointsSettingsPage({super.key});

  @override
  State<RecurringTaskPointsSettingsPage> createState() =>
      _RecurringTaskPointsSettingsPageState();
}

class _RecurringTaskPointsSettingsPageState
    extends State<RecurringTaskPointsSettingsPage> {
  double _completionPoints = 1.0;
  double _penaltyPoints = -3.0;

  // Gradient colors for this page (purple theme)
  static final _gradientColors = [Color(0xFF8E2DE2), Color(0xFF4A00E0)];

  @override
  Widget build(BuildContext context) {
    return PointsSettingsScaffold(
      title: 'Циклические задачи',
      headerIcon: Icons.repeat,
      headerTitle: 'Циклические задачи',
      headerSubtitle: 'Баллы за повторяющиеся задачи',
      gradientColors: _gradientColors,
      popOnSave: true,
      onLoad: () async {
        final settings =
            await PointsSettingsService.getRecurringTaskPointsSettings();
        _completionPoints = settings.completionPoints;
        _penaltyPoints = settings.penaltyPoints;
      },
      onSave: () async {
        await PointsSettingsService.saveRecurringTaskPointsSettings(
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
        SizedBox(height: 24),

        // Info box (orange theme)
        Container(
          padding: EdgeInsets.all(16.w),
          decoration: BoxDecoration(
            color: Colors.orange.withOpacity(0.1),
            borderRadius: BorderRadius.circular(16.r),
            border: Border.all(color: Colors.orange.withOpacity(0.3)),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: Colors.orange.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(10.r),
                ),
                child: Icon(Icons.info_outline, color: Colors.orange,
                    size: 22),
              ),
              SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Циклические задачи повторяются каждую смену. Новые правила будут применяться только к новым задачам.',
                  style: TextStyle(
                    color: Colors.orange[900],
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
          negativeLabel: 'Просрочена',
          positivePoints: _completionPoints,
          negativePoints: _penaltyPoints,
          gradientColors: _gradientColors,
          valueColumnTitle: 'Статус задачи',
        ),
      ],
    );
  }
}
