import 'package:flutter/material.dart';
import '../models/referral_stats_model.dart';
import '../services/referral_service.dart';
import '../../efficiency/widgets/settings_widgets.dart';

/// Страница настроек баллов за приглашения с милестоунами
class ReferralsPointsSettingsPage extends StatefulWidget {
  const ReferralsPointsSettingsPage({super.key});

  @override
  State<ReferralsPointsSettingsPage> createState() =>
      _ReferralsPointsSettingsPageState();
}

class _ReferralsPointsSettingsPageState
    extends State<ReferralsPointsSettingsPage> {
  bool _isLoading = true;
  bool _isSaving = false;
  ReferralsPointsSettings? _settings;

  // Editable values
  double _basePoints = 1;
  double _milestoneThreshold = 0;
  double _milestonePoints = 1;

  // Gradient colors (teal/green theme for referrals)
  static const _gradientColors = [Color(0xFF00897B), Color(0xFF26A69A)];

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    setState(() => _isLoading = true);

    try {
      final settings = await ReferralService.getPointsSettings();
      setState(() {
        _settings = settings;
        _basePoints = settings.basePoints.toDouble();
        _milestoneThreshold = settings.milestoneThreshold.toDouble();
        _milestonePoints = settings.milestonePoints.toDouble();
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
      final settings = ReferralsPointsSettings(
        basePoints: _basePoints.round(),
        milestoneThreshold: _milestoneThreshold.round(),
        milestonePoints: _milestonePoints.round(),
      );

      final success = await ReferralService.updatePointsSettings(settings);

      if (success) {
        setState(() {
          _settings = settings;
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
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
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
        title: const Text('Баллы за приглашения'),
        backgroundColor: _gradientColors[0],
        elevation: 0,
      ),
      body: _isLoading
          ? Center(child: CircularProgressIndicator(color: _gradientColors[0]))
          : Column(
              children: [
                // Заголовок
                SettingsHeaderCard(
                  icon: Icons.person_add_rounded,
                  title: 'Настройка бонусов за приглашения',
                  subtitle:
                      'Базовые баллы + бонус за каждого N-го клиента',
                  gradientColors: _gradientColors,
                ),
                // Контент
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Base points slider
                        SettingsSliderWidget(
                          title: 'Базовые баллы',
                          subtitle: 'Баллы за каждого обычного клиента',
                          value: _basePoints,
                          min: 0,
                          max: 10,
                          divisions: 100,
                          onChanged: (value) =>
                              setState(() => _basePoints = value),
                          valueLabel: _basePoints.toStringAsFixed(1),
                          accentColor: Colors.blue,
                          icon: Icons.star_outline,
                        ),
                        const SizedBox(height: 16),

                        // Milestone threshold slider
                        SettingsSliderWidget(
                          title: 'Каждый N-й клиент',
                          subtitle: _milestoneThreshold.round() == 0
                              ? 'Милестоуны отключены (все получают базовые баллы)'
                              : 'Каждый ${_milestoneThreshold.round()}-й клиент получает бонус ВМЕСТО базовых',
                          value: _milestoneThreshold,
                          min: 0,
                          max: 20,
                          divisions: 20,
                          onChanged: (value) =>
                              setState(() => _milestoneThreshold = value),
                          valueLabel: _milestoneThreshold.round() == 0
                              ? 'Выкл'
                              : _milestoneThreshold.round().toString(),
                          isInteger: true,
                          accentColor: Colors.orange,
                          icon: Icons.military_tech_outlined,
                        ),
                        const SizedBox(height: 16),

                        // Milestone points slider
                        SettingsSliderWidget(
                          title: 'Бонусные баллы',
                          subtitle: 'Баллы за каждого N-го клиента (вместо базовых)',
                          value: _milestonePoints,
                          min: 0,
                          max: 20,
                          divisions: 200,
                          onChanged: (value) =>
                              setState(() => _milestonePoints = value),
                          valueLabel: _milestonePoints.toStringAsFixed(1),
                          accentColor: Colors.green,
                          icon: Icons.emoji_events_outlined,
                        ),
                        const SizedBox(height: 24),

                        // Preview section
                        SettingsSectionTitle(
                          title: 'Предпросмотр расчета баллов',
                          gradientColors: _gradientColors,
                        ),
                        const SizedBox(height: 12),
                        _buildPreview(),
                        const SizedBox(height: 24),

                        // Explanation section
                        _buildExplanationCard(),
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

  Widget _buildPreview() {
    final settings = ReferralsPointsSettings(
      basePoints: _basePoints.round(),
      milestoneThreshold: _milestoneThreshold.round(),
      milestonePoints: _milestonePoints.round(),
    );

    final previewCounts = [5, 10, 15, 20];

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 15,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          // Header
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: _gradientColors,
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.preview,
                  color: Colors.white,
                  size: 24,
                ),
              ),
              const SizedBox(width: 14),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Примеры расчета',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF2D3436),
                      ),
                    ),
                    Text(
                      'Баллы за разное количество клиентов',
                      style: TextStyle(
                        fontSize: 13,
                        color: Color(0xFF636E72),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          // Preview rows
          ...previewCounts.map((count) {
            final points = settings.calculatePoints(count);
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                children: [
                  Container(
                    width: 60,
                    height: 40,
                    decoration: BoxDecoration(
                      color: _gradientColors[0].withOpacity(0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Center(
                      child: Text(
                        '$count',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: _gradientColors[0],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Text(
                    'клиентов',
                    style: TextStyle(
                      fontSize: 14,
                      color: Color(0xFF636E72),
                    ),
                  ),
                  const Spacer(),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: _gradientColors,
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '$points',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(width: 6),
                        const Text(
                          'баллов',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildExplanationCard() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 15,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: Colors.blue.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.info_outline,
                  color: Colors.blue,
                  size: 24,
                ),
              ),
              const SizedBox(width: 14),
              const Text(
                'Как работает расчет',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF2D3436),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _buildExplanationPoint(
            '1',
            'Базовые баллы',
            'За каждого обычного клиента начисляются базовые баллы',
            Colors.blue,
          ),
          const SizedBox(height: 12),
          _buildExplanationPoint(
            '2',
            'Милестоун (N-й клиент)',
            'Каждый N-й клиент получает бонусные баллы ВМЕСТО базовых',
            Colors.orange,
          ),
          const SizedBox(height: 12),
          _buildExplanationPoint(
            '3',
            'Пример',
            'База=1, Каждый 5-й, Бонус=3:\n10 клиентов = (1+1+1+1+3) + (1+1+1+1+3) = 14 баллов',
            Colors.green,
          ),
        ],
      ),
    );
  }

  Widget _buildExplanationPoint(
      String number, String title, String description, Color color) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Center(
            child: Text(
              number,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF2D3436),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                description,
                style: const TextStyle(
                  fontSize: 13,
                  color: Color(0xFF636E72),
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
