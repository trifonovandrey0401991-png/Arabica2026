import 'package:flutter/material.dart';
import '../../models/points_settings_model.dart';
import '../../services/points_settings_service.dart';

/// Page for configuring shift handover points settings (Сдать смену)
class ShiftHandoverPointsSettingsPage extends StatefulWidget {
  const ShiftHandoverPointsSettingsPage({super.key});

  @override
  State<ShiftHandoverPointsSettingsPage> createState() =>
      _ShiftHandoverPointsSettingsPageState();
}

class _ShiftHandoverPointsSettingsPageState
    extends State<ShiftHandoverPointsSettingsPage> {
  bool _isLoading = true;
  bool _isSaving = false;
  ShiftHandoverPointsSettings? _settings;

  // Editable values for shift handover
  double _minPoints = -3;
  int _zeroThreshold = 7;
  double _maxPoints = 1;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    setState(() => _isLoading = true);

    try {
      final settings =
          await PointsSettingsService.getShiftHandoverPointsSettings();
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
      final result =
          await PointsSettingsService.saveShiftHandoverPointsSettings(
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Баллы за сдачу смены'),
        backgroundColor: const Color(0xFF004D40),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
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
                              'Баллы начисляются при оценке отчета сдачи смены (1-10)',
                              style: TextStyle(color: Colors.blue[900]),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  _buildSliderSection(
                    title: 'Минимальная оценка (1)',
                    subtitle: 'Штраф за плохую сдачу смены',
                    value: _minPoints,
                    min: -5,
                    max: 0,
                    divisions: 50,
                    onChanged: (value) => setState(() => _minPoints = value),
                    valueLabel: _minPoints.toStringAsFixed(1),
                    valueColor: Colors.red,
                  ),
                  const SizedBox(height: 24),
                  _buildSliderSection(
                    title: 'Нулевая граница',
                    subtitle: 'Оценка, дающая 0 баллов',
                    value: _zeroThreshold.toDouble(),
                    min: 2,
                    max: 9,
                    divisions: 7,
                    onChanged: (value) => setState(() => _zeroThreshold = value.round()),
                    valueLabel: _zeroThreshold.toString(),
                    isInteger: true,
                  ),
                  const SizedBox(height: 24),
                  _buildSliderSection(
                    title: 'Максимальная оценка (10)',
                    subtitle: 'Награда за отличную сдачу смены',
                    value: _maxPoints,
                    min: 0,
                    max: 5,
                    divisions: 50,
                    onChanged: (value) => setState(() => _maxPoints = value),
                    valueLabel: '+${_maxPoints.toStringAsFixed(1)}',
                    valueColor: Colors.green,
                  ),
                  const SizedBox(height: 32),
                  const Text(
                    'Предпросмотр расчета баллов:',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  _buildPreviewTable(),
                  const SizedBox(height: 32),
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
                                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                              ),
                            )
                          : const Text(
                              'Сохранить',
                              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
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
    Color? valueColor,
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
                      Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                      Text(subtitle, style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: valueColor ?? const Color(0xFF004D40),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    valueLabel,
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
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
              activeColor: valueColor ?? const Color(0xFF004D40),
              onChanged: onChanged,
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(isInteger ? min.toInt().toString() : min.toString(), style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                Text(isInteger ? max.toInt().toString() : max.toString(), style: TextStyle(fontSize: 12, color: Colors.grey[600])),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPreviewTable() {
    final previewRatings = [1, 4, _zeroThreshold, 8, 10];
    return Card(
      elevation: 2,
      child: Table(
        border: TableBorder.all(color: Colors.grey[300]!),
        columnWidths: const {0: FlexColumnWidth(1), 1: FlexColumnWidth(1)},
        children: [
          TableRow(
            decoration: BoxDecoration(color: Colors.grey[200]),
            children: const [
              Padding(padding: EdgeInsets.all(12), child: Text('Оценка', style: TextStyle(fontWeight: FontWeight.bold), textAlign: TextAlign.center)),
              Padding(padding: EdgeInsets.all(12), child: Text('Баллы эффективности', style: TextStyle(fontWeight: FontWeight.bold), textAlign: TextAlign.center)),
            ],
          ),
          ...previewRatings.map((rating) {
            final points = _calculatePoints(rating);
            final color = points < 0 ? Colors.red : points > 0 ? Colors.green : Colors.grey;
            return TableRow(
              children: [
                Padding(padding: const EdgeInsets.all(12), child: Text('$rating / 10', textAlign: TextAlign.center)),
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    points >= 0 ? '+${points.toStringAsFixed(2)}' : points.toStringAsFixed(2),
                    textAlign: TextAlign.center,
                    style: TextStyle(color: color, fontWeight: FontWeight.bold),
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
