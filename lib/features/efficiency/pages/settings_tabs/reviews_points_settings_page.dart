import 'package:flutter/material.dart';
import '../../services/points_settings_service.dart';
import '../../widgets/settings_widgets.dart';
import '../../widgets/points_settings_scaffold.dart';

/// Page for configuring reviews points settings (Отзывы)
class ReviewsPointsSettingsPage extends StatefulWidget {
  const ReviewsPointsSettingsPage({super.key});

  @override
  State<ReviewsPointsSettingsPage> createState() =>
      _ReviewsPointsSettingsPageState();
}

class _ReviewsPointsSettingsPageState extends State<ReviewsPointsSettingsPage> {
  double _positivePoints = 3;
  double _negativePoints = -5;

  static final _gradientColors = [Color(0xFFf7971e), Color(0xFFffd200)];

  @override
  Widget build(BuildContext context) {
    return PointsSettingsScaffold(
      title: 'Баллы за отзывы',
      headerIcon: Icons.star_rate_outlined,
      headerTitle: 'Отзывы клиентов',
      headerSubtitle: 'Баллы за положительные и отрицательные отзывы',
      gradientColors: _gradientColors,
      onLoad: () async {
        final settings =
            await PointsSettingsService.getReviewsPointsSettings();
        _positivePoints = settings.positivePoints;
        _negativePoints = settings.negativePoints;
      },
      onSave: () async {
        final result = await PointsSettingsService.saveReviewsPointsSettings(
          positivePoints: _positivePoints,
          negativePoints: _negativePoints,
        );
        return result != null;
      },
      bodyBuilder: (context) => [
        SettingsSliderWidget(
          title: 'Положительный отзыв',
          subtitle: 'Награда за хороший отзыв клиента',
          value: _positivePoints,
          min: 0,
          max: 10,
          divisions: 100,
          onChanged: (value) => setState(() => _positivePoints = value),
          valueLabel: '+${_positivePoints.toStringAsFixed(1)}',
          accentColor: Colors.green,
          icon: Icons.thumb_up_outlined,
        ),
        SizedBox(height: 16),
        SettingsSliderWidget(
          title: 'Отрицательный отзыв',
          subtitle: 'Штраф за плохой отзыв клиента',
          value: _negativePoints,
          min: -10,
          max: 0,
          divisions: 100,
          onChanged: (value) => setState(() => _negativePoints = value),
          valueLabel: _negativePoints.toStringAsFixed(1),
          accentColor: Colors.red,
          icon: Icons.thumb_down_outlined,
        ),
        SizedBox(height: 24),
        SettingsSectionTitle(
          title: 'Предпросмотр',
          gradientColors: _gradientColors,
        ),
        SizedBox(height: 12),
        BinaryPreviewWidget(
          positiveLabel: 'Положительный',
          negativeLabel: 'Отрицательный',
          positivePoints: _positivePoints,
          negativePoints: _negativePoints,
          gradientColors: _gradientColors,
          valueColumnTitle: 'Тип отзыва',
        ),
      ],
    );
  }
}
