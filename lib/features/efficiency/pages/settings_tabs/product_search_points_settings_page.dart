import 'package:flutter/material.dart';
import '../../services/points_settings_service.dart';
import '../../widgets/settings_widgets.dart';
import '../../widgets/points_settings_scaffold.dart';

/// Page for configuring product search points settings (Поиск товара)
class ProductSearchPointsSettingsPage extends StatefulWidget {
  const ProductSearchPointsSettingsPage({super.key});

  @override
  State<ProductSearchPointsSettingsPage> createState() =>
      _ProductSearchPointsSettingsPageState();
}

class _ProductSearchPointsSettingsPageState
    extends State<ProductSearchPointsSettingsPage> {
  double _answeredPoints = 0.2;
  double _notAnsweredPoints = -3;
  int _answerTimeoutMinutes = 30;

  // Gradient colors for this page (cyan theme)
  static final _gradientColors = [Color(0xFF00d2ff), Color(0xFF3a7bd5)];

  @override
  Widget build(BuildContext context) {
    return PointsSettingsScaffold(
      title: 'Баллы за поиск товара',
      headerIcon: Icons.search_outlined,
      headerTitle: 'Запросы о наличии товара',
      headerSubtitle: 'Баллы за своевременный ответ клиенту',
      gradientColors: _gradientColors,
      onLoad: () async {
        final settings =
            await PointsSettingsService.getProductSearchPointsSettings();
        _answeredPoints = settings.answeredPoints;
        _notAnsweredPoints = settings.notAnsweredPoints;
        _answerTimeoutMinutes = settings.answerTimeoutMinutes;
      },
      onSave: () async {
        final result =
            await PointsSettingsService.saveProductSearchPointsSettings(
          answeredPoints: _answeredPoints,
          notAnsweredPoints: _notAnsweredPoints,
          answerTimeoutMinutes: _answerTimeoutMinutes,
        );
        return result != null;
      },
      bodyBuilder: (context) => [
        // Answered points slider
        SettingsSliderWidget(
          title: 'Ответил вовремя',
          subtitle: 'Награда за своевременный ответ',
          value: _answeredPoints,
          min: 0,
          max: 2,
          divisions: 20,
          onChanged: (value) => setState(() => _answeredPoints = value),
          valueLabel: '+${_answeredPoints.toStringAsFixed(1)}',
          accentColor: Colors.green,
          icon: Icons.check_circle_outline,
        ),
        SizedBox(height: 16),

        // Not answered points slider
        SettingsSliderWidget(
          title: 'Не ответил',
          subtitle: 'Штраф за отсутствие ответа',
          value: _notAnsweredPoints,
          min: -5,
          max: 0,
          divisions: 50,
          onChanged: (value) => setState(() => _notAnsweredPoints = value),
          valueLabel: _notAnsweredPoints.toStringAsFixed(1),
          accentColor: Colors.red,
          icon: Icons.cancel_outlined,
        ),
        SizedBox(height: 16),

        // Timeout slider
        SettingsSliderWidget(
          title: 'Таймаут ответа',
          subtitle: 'Сколько минут дается на ответ',
          value: _answerTimeoutMinutes.toDouble(),
          min: 5,
          max: 60,
          divisions: 11,
          onChanged: (value) =>
              setState(() => _answerTimeoutMinutes = value.round()),
          valueLabel: '$_answerTimeoutMinutes мин',
          accentColor: Colors.blue,
          icon: Icons.timer_outlined,
        ),
        SizedBox(height: 24),

        // Preview section
        SettingsSectionTitle(
          title: 'Предпросмотр',
          gradientColors: _gradientColors,
        ),
        SizedBox(height: 12),
        BinaryPreviewWidget(
          positiveLabel: 'Ответил',
          negativeLabel: 'Не ответил',
          positivePoints: _answeredPoints,
          negativePoints: _notAnsweredPoints,
          gradientColors: _gradientColors,
          valueColumnTitle: 'Статус ответа',
        ),
      ],
    );
  }
}
