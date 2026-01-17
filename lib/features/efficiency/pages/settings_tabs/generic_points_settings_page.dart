import 'package:flutter/material.dart';

/// Generic страница настроек баллов
///
/// Параметризованная страница для настройки любого типа баллов эффективности.
/// Заменяет 10+ дублированных страниц settings_tabs/*.
class GenericPointsSettingsPage<T> extends StatefulWidget {
  final String title;
  final String infoText;
  final Future<T> Function() loadSettings;
  final Future<T?> Function({
    required double minPoints,
    required int zeroThreshold,
    required double maxPoints,
  }) saveSettings;
  final double Function(T settings) getMinPoints;
  final int Function(T settings) getZeroThreshold;
  final double Function(T settings) getMaxPoints;
  final double Function(int value, double minPoints, int zeroThreshold, double maxPoints) calculatePoints;
  final String minPointsTitle;
  final String minPointsSubtitle;
  final String zeroThresholdTitle;
  final String zeroThresholdSubtitle;
  final String maxPointsTitle;
  final String maxPointsSubtitle;
  final double minPointsMin;
  final double minPointsMax;
  final int zeroThresholdMin;
  final int zeroThresholdMax;
  final double maxPointsMin;
  final double maxPointsMax;
  final int previewMin;
  final int previewMax;
  final String previewLabel;

  const GenericPointsSettingsPage({
    super.key,
    required this.title,
    required this.infoText,
    required this.loadSettings,
    required this.saveSettings,
    required this.getMinPoints,
    required this.getZeroThreshold,
    required this.getMaxPoints,
    required this.calculatePoints,
    this.minPointsTitle = 'Минимальные баллы',
    this.minPointsSubtitle = 'Штраф за минимальную оценку',
    this.zeroThresholdTitle = 'Порог нуля',
    this.zeroThresholdSubtitle = 'Оценка, при которой баллы = 0',
    this.maxPointsTitle = 'Максимальные баллы',
    this.maxPointsSubtitle = 'Награда за максимальную оценку',
    this.minPointsMin = -5,
    this.minPointsMax = 0,
    this.zeroThresholdMin = 0,
    this.zeroThresholdMax = 20,
    this.maxPointsMin = 0,
    this.maxPointsMax = 5,
    this.previewMin = 1,
    this.previewMax = 10,
    this.previewLabel = 'Оценка',
  });

  @override
  State<GenericPointsSettingsPage<T>> createState() =>
      _GenericPointsSettingsPageState<T>();
}

class _GenericPointsSettingsPageState<T>
    extends State<GenericPointsSettingsPage<T>> {
  bool _isLoading = true;
  bool _isSaving = false;

  // Editable values
  late double _minPoints;
  late int _zeroThreshold;
  late double _maxPoints;

  @override
  void initState() {
    super.initState();
    // Инициализация дефолтными значениями
    _minPoints = widget.minPointsMin;
    _zeroThreshold = (widget.zeroThresholdMin + widget.zeroThresholdMax) ~/ 2;
    _maxPoints = widget.maxPointsMax;
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    setState(() => _isLoading = true);

    try {
      final settings = await widget.loadSettings();
      setState(() {
        _minPoints = widget.getMinPoints(settings);
        _zeroThreshold = widget.getZeroThreshold(settings);
        _maxPoints = widget.getMaxPoints(settings);
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
      final result = await widget.saveSettings(
        minPoints: _minPoints,
        zeroThreshold: _zeroThreshold,
        maxPoints: _maxPoints,
      );

      if (result != null) {
        setState(() {
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
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
                              widget.infoText,
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
                    title: widget.minPointsTitle,
                    subtitle: widget.minPointsSubtitle,
                    value: _minPoints,
                    min: widget.minPointsMin,
                    max: widget.minPointsMax,
                    divisions: ((widget.minPointsMax - widget.minPointsMin) * 2)
                        .toInt(),
                    onChanged: (value) {
                      setState(() => _minPoints = value);
                    },
                  ),
                  const SizedBox(height: 24),

                  // Zero threshold slider
                  _buildSliderSection(
                    title: widget.zeroThresholdTitle,
                    subtitle: widget.zeroThresholdSubtitle,
                    value: _zeroThreshold.toDouble(),
                    min: widget.zeroThresholdMin.toDouble(),
                    max: widget.zeroThresholdMax.toDouble(),
                    divisions: widget.zeroThresholdMax - widget.zeroThresholdMin,
                    isInteger: true,
                    onChanged: (value) {
                      setState(() => _zeroThreshold = value.toInt());
                    },
                  ),
                  const SizedBox(height: 24),

                  // Max points slider
                  _buildSliderSection(
                    title: widget.maxPointsTitle,
                    subtitle: widget.maxPointsSubtitle,
                    value: _maxPoints,
                    min: widget.maxPointsMin,
                    max: widget.maxPointsMax,
                    divisions: ((widget.maxPointsMax - widget.maxPointsMin) * 2)
                        .toInt(),
                    onChanged: (value) {
                      setState(() => _maxPoints = value);
                    },
                  ),
                  const SizedBox(height: 32),

                  // Preview card
                  _buildPreviewCard(),

                  const SizedBox(height: 32),

                  // Save button
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      onPressed: _isSaving ? null : _saveSettings,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF004D40),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: _isSaving
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 2,
                              ),
                            )
                          : const Text(
                              'Сохранить настройки',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: Colors.white,
                              ),
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
    bool isInteger = false,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
        Text(
          subtitle,
          style: TextStyle(
            fontSize: 13,
            color: Colors.grey[600],
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: Slider(
                value: value,
                min: min,
                max: max,
                divisions: divisions,
                label: isInteger
                    ? value.toInt().toString()
                    : value.toStringAsFixed(1),
                activeColor: const Color(0xFF004D40),
                onChanged: onChanged,
              ),
            ),
            Container(
              width: 60,
              alignment: Alignment.centerRight,
              child: Text(
                isInteger
                    ? value.toInt().toString()
                    : value.toStringAsFixed(1),
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF004D40),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildPreviewCard() {
    return Card(
      color: const Color(0xFFE0F2F1),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Предпросмотр баллов',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Color(0xFF004D40),
              ),
            ),
            const SizedBox(height: 16),
            ...List.generate(
              widget.previewMax - widget.previewMin + 1,
              (index) {
                final value = widget.previewMin + index;
                final points = widget.calculatePoints(value, _minPoints, _zeroThreshold, _maxPoints);
                final isPositive = points >= 0;
                final isZero = points == 0;

                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 100,
                        child: Text(
                          '${widget.previewLabel} $value:',
                          style: const TextStyle(fontSize: 14),
                        ),
                      ),
                      Text(
                        isPositive && !isZero
                            ? '+${points.toStringAsFixed(1)}'
                            : points.toStringAsFixed(1),
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: isZero
                              ? Colors.grey[700]
                              : isPositive
                                  ? Colors.green[700]
                                  : Colors.red[700],
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
