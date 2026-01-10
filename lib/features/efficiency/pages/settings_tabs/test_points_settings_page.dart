import 'package:flutter/material.dart';
import '../../models/points_settings_model.dart';
import '../../services/points_settings_service.dart';

/// Page for configuring test points settings
class TestPointsSettingsPage extends StatefulWidget {
  const TestPointsSettingsPage({super.key});

  @override
  State<TestPointsSettingsPage> createState() => _TestPointsSettingsPageState();
}

class _TestPointsSettingsPageState extends State<TestPointsSettingsPage> {
  bool _isLoading = true;
  bool _isSaving = false;
  TestPointsSettings? _settings;

  // Editable values
  double _minPoints = -2;
  int _zeroThreshold = 15;
  double _maxPoints = 1;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    setState(() => _isLoading = true);

    try {
      final settings = await PointsSettingsService.getTestPointsSettings();
      setState(() {
        _settings = settings;
        _minPoints = settings.minPoints;
        _zeroThreshold = settings.zeroThreshold;
        _maxPoints = settings.maxPoints;
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
      final result = await PointsSettingsService.saveTestPointsSettings(
        minPoints: _minPoints,
        zeroThreshold: _zeroThreshold,
        maxPoints: _maxPoints,
      );

      if (result != null) {
        setState(() {
          _settings = result;
          _isSaving = false;
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Настройки сохранены'),
              backgroundColor: Colors.green,
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

  /// Calculate points using current settings (local calculation)
  double _calculatePoints(int score) {
    if (score <= 0) return _minPoints;
    if (score >= 20) return _maxPoints;

    if (score <= _zeroThreshold) {
      return _minPoints + (0 - _minPoints) * (score / _zeroThreshold);
    } else {
      final range = 20 - _zeroThreshold;
      return 0 + (_maxPoints - 0) * ((score - _zeroThreshold) / range);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Баллы за тестирование'),
        backgroundColor: const Color(0xFF004D40),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Info card
                  Card(
                    color: Colors.blue[50],
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          Icon(Icons.info_outline, color: Colors.blue[700]),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'Всего вопросов: 20\nПроходной балл: 16 правильных ответов',
                              style: TextStyle(color: Colors.blue[900]),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Min points slider
                  _buildSliderSection(
                    title: 'Минимальные баллы',
                    subtitle: 'Штраф за 0-1 правильных ответов',
                    value: _minPoints,
                    min: -5,
                    max: 0,
                    divisions: 10,
                    onChanged: (value) {
                      setState(() => _minPoints = value);
                    },
                    valueLabel: _minPoints.toStringAsFixed(1),
                  ),
                  const SizedBox(height: 24),

                  // Zero threshold slider
                  _buildSliderSection(
                    title: 'Порог нуля',
                    subtitle: 'Количество правильных ответов для 0 баллов',
                    value: _zeroThreshold.toDouble(),
                    min: 5,
                    max: 19,
                    divisions: 14,
                    onChanged: (value) {
                      setState(() => _zeroThreshold = value.round());
                    },
                    valueLabel: _zeroThreshold.toString(),
                    isInteger: true,
                  ),
                  const SizedBox(height: 24),

                  // Max points slider
                  _buildSliderSection(
                    title: 'Максимальные баллы',
                    subtitle: 'Награда за 20/20 правильных ответов',
                    value: _maxPoints,
                    min: 0,
                    max: 5,
                    divisions: 10,
                    onChanged: (value) {
                      setState(() => _maxPoints = value);
                    },
                    valueLabel: '+${_maxPoints.toStringAsFixed(1)}',
                  ),
                  const SizedBox(height: 32),

                  // Preview section
                  const Text(
                    'Предпросмотр расчета баллов:',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _buildPreviewTable(),
                  const SizedBox(height: 32),

                  // Save button
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _isSaving ? null : _saveSettings,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF004D40),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                      child: _isSaving
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor:
                                    AlwaysStoppedAnimation<Color>(Colors.white),
                              ),
                            )
                          : const Text(
                              'Сохранить',
                              style: TextStyle(
                                  fontSize: 18, fontWeight: FontWeight.bold),
                            ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildSliderSection({
    required String title,
    required String subtitle,
    required double value,
    required double min,
    required double max,
    required int divisions,
    required ValueChanged<double> onChanged,
    required String valueLabel,
    bool isInteger = false,
  }) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        subtitle,
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF004D40),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    valueLabel,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Slider(
              value: value,
              min: min,
              max: max,
              divisions: divisions,
              activeColor: const Color(0xFF004D40),
              onChanged: onChanged,
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  isInteger ? min.toInt().toString() : min.toString(),
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                ),
                Text(
                  isInteger ? max.toInt().toString() : max.toString(),
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPreviewTable() {
    final previewScores = [0, 5, 10, _zeroThreshold, 17, 18, 19, 20];

    return Card(
      elevation: 2,
      child: Table(
        border: TableBorder.all(color: Colors.grey[300]!),
        columnWidths: const {
          0: FlexColumnWidth(1),
          1: FlexColumnWidth(1),
        },
        children: [
          TableRow(
            decoration: BoxDecoration(color: Colors.grey[200]),
            children: const [
              Padding(
                padding: EdgeInsets.all(12),
                child: Text(
                  'Правильных ответов',
                  style: TextStyle(fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
              ),
              Padding(
                padding: EdgeInsets.all(12),
                child: Text(
                  'Баллы эффективности',
                  style: TextStyle(fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ),
          ...previewScores.map((score) {
            final points = _calculatePoints(score);
            final color = points < 0
                ? Colors.red
                : points > 0
                    ? Colors.green
                    : Colors.grey;
            return TableRow(
              children: [
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    '$score / 20',
                    textAlign: TextAlign.center,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    points >= 0
                        ? '+${points.toStringAsFixed(2)}'
                        : points.toStringAsFixed(2),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: color,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            );
          }),
        ],
      ),
    );
  }
}
