import 'package:flutter/material.dart';
import '../../models/points_settings_model.dart';
import '../../services/points_settings_service.dart';

/// Page for configuring shift points settings (Пересменка)
class ShiftPointsSettingsPage extends StatefulWidget {
  const ShiftPointsSettingsPage({super.key});

  @override
  State<ShiftPointsSettingsPage> createState() =>
      _ShiftPointsSettingsPageState();
}

class _ShiftPointsSettingsPageState extends State<ShiftPointsSettingsPage> {
  bool _isLoading = true;
  bool _isSaving = false;
  ShiftPointsSettings? _settings;

  // Editable values
  double _minPoints = -3;
  int _zeroThreshold = 7;
  double _maxPoints = 2;

  // Time window settings
  String _morningStartTime = '07:00';
  String _morningEndTime = '13:00';
  String _eveningStartTime = '14:00';
  String _eveningEndTime = '23:00';
  double _missedPenalty = -3.0;
  int _adminReviewTimeout = 2; // Время на проверку админом (1, 2 или 3 часа)

  // Gradient colors for this page (orange theme)
  static const _gradientColors = [Color(0xFFf46b45), Color(0xFFeea849)];

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    setState(() => _isLoading = true);

    try {
      final settings = await PointsSettingsService.getShiftPointsSettings();
      setState(() {
        _settings = settings;
        _minPoints = settings.minPoints;
        _zeroThreshold = settings.zeroThreshold;
        _maxPoints = settings.maxPoints;
        _morningStartTime = settings.morningStartTime;
        _morningEndTime = settings.morningEndTime;
        _eveningStartTime = settings.eveningStartTime;
        _eveningEndTime = settings.eveningEndTime;
        _missedPenalty = settings.missedPenalty;
        _adminReviewTimeout = settings.adminReviewTimeout;
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
      final result = await PointsSettingsService.saveShiftPointsSettings(
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

      if (result != null) {
        setState(() {
          _settings = result;
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
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        title: const Text('Баллы за пересменку'),
        backgroundColor: _gradientColors[0],
        elevation: 0,
      ),
      body: _isLoading
          ? Center(child: CircularProgressIndicator(color: _gradientColors[0]))
          : Column(
              children: [
                // Заголовок
                Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: _gradientColors,
                    ),
                    borderRadius: const BorderRadius.only(
                      bottomLeft: Radius.circular(28),
                      bottomRight: Radius.circular(28),
                    ),
                  ),
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(
                            Icons.swap_horiz_rounded,
                            color: Colors.white,
                            size: 26,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Оценка пересменки: 1-10',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Text(
                                'Баллы начисляются при оценке отчета',
                                style: TextStyle(
                                  color: Colors.white.withOpacity(0.9),
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                // Контент
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Min points slider
                        _buildSliderSection(
                          title: 'Минимальная оценка (1)',
                          subtitle: 'Штраф за плохую пересменку',
                          value: _minPoints,
                          min: -5,
                          max: 0,
                          divisions: 50,
                          onChanged: (value) {
                            setState(() => _minPoints = value);
                          },
                          valueLabel: _minPoints.toStringAsFixed(1),
                          accentColor: Colors.red,
                          icon: Icons.remove_circle_outline,
                        ),
                        const SizedBox(height: 16),

                        // Zero threshold slider
                        _buildSliderSection(
                          title: 'Нулевая граница',
                          subtitle: 'Оценка, дающая 0 баллов',
                          value: _zeroThreshold.toDouble(),
                          min: 2,
                          max: 9,
                          divisions: 7,
                          onChanged: (value) {
                            setState(() => _zeroThreshold = value.round());
                          },
                          valueLabel: _zeroThreshold.toString(),
                          isInteger: true,
                          accentColor: Colors.orange,
                          icon: Icons.adjust,
                        ),
                        const SizedBox(height: 16),

                        // Max points slider
                        _buildSliderSection(
                          title: 'Максимальная оценка (10)',
                          subtitle: 'Награда за отличную пересменку',
                          value: _maxPoints,
                          min: 0,
                          max: 5,
                          divisions: 50,
                          onChanged: (value) {
                            setState(() => _maxPoints = value);
                          },
                          valueLabel: '+${_maxPoints.toStringAsFixed(1)}',
                          accentColor: Colors.green,
                          icon: Icons.add_circle_outline,
                        ),
                        const SizedBox(height: 24),

                        // Time windows section
                        _buildSectionTitle('Временные окна пересменок'),
                        const SizedBox(height: 12),
                        _buildTimeWindowsSection(),
                        const SizedBox(height: 24),

                        // Missed penalty slider
                        _buildSliderSection(
                          title: 'Штраф за пропуск',
                          subtitle: 'Баллы за непройденную пересменку',
                          value: _missedPenalty,
                          min: -10,
                          max: 0,
                          divisions: 100,
                          onChanged: (value) {
                            setState(() => _missedPenalty = value);
                          },
                          valueLabel: _missedPenalty.toStringAsFixed(1),
                          accentColor: Colors.deepOrange,
                          icon: Icons.warning_amber_outlined,
                        ),
                        const SizedBox(height: 24),

                        // Admin review timeout section
                        _buildSectionTitle('Время на проверку админом'),
                        const SizedBox(height: 12),
                        _buildAdminReviewTimeoutSection(),
                        const SizedBox(height: 24),

                        // Preview section
                        _buildSectionTitle('Предпросмотр расчета баллов'),
                        const SizedBox(height: 12),
                        _buildPreviewTable(),
                        const SizedBox(height: 24),

                        // Save button
                        _buildSaveButton(),
                        const SizedBox(height: 16),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Row(
      children: [
        Container(
          width: 4,
          height: 20,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: _gradientColors,
            ),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 10),
        Text(
          title,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: Color(0xFF2D3436),
          ),
        ),
      ],
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
    Color accentColor = const Color(0xFFf46b45),
    IconData icon = Icons.tune,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: accentColor.withOpacity(0.1),
            blurRadius: 15,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Padding(
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
                    color: accentColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, color: accentColor, size: 24),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF2D3436),
                        ),
                      ),
                      Text(
                        subtitle,
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[500],
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  decoration: BoxDecoration(
                    color: accentColor,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: accentColor.withOpacity(0.4),
                        blurRadius: 8,
                        offset: const Offset(0, 4),
                      ),
                    ],
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
            const SizedBox(height: 16),
            SliderTheme(
              data: SliderThemeData(
                activeTrackColor: accentColor,
                inactiveTrackColor: accentColor.withOpacity(0.2),
                thumbColor: accentColor,
                overlayColor: accentColor.withOpacity(0.2),
                trackHeight: 6,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 10),
              ),
              child: Slider(
                value: value,
                min: min,
                max: max,
                divisions: divisions,
                onChanged: onChanged,
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    isInteger ? min.toInt().toString() : min.toString(),
                    style: TextStyle(fontSize: 12, color: Colors.grey[400], fontWeight: FontWeight.w500),
                  ),
                  Text(
                    isInteger ? max.toInt().toString() : max.toString(),
                    style: TextStyle(fontSize: 12, color: Colors.grey[400], fontWeight: FontWeight.w500),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTimeWindowsSection() {
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
          // Morning shift
          _buildTimeWindowRow(
            icon: Icons.wb_sunny_outlined,
            iconColor: Colors.orange,
            title: 'Утренняя смена',
            startTime: _morningStartTime,
            endTime: _morningEndTime,
            onStartChanged: (time) => setState(() => _morningStartTime = time),
            onEndChanged: (time) => setState(() => _morningEndTime = time),
          ),
          const SizedBox(height: 16),
          Divider(color: Colors.grey[200]),
          const SizedBox(height: 16),
          // Evening shift
          _buildTimeWindowRow(
            icon: Icons.nights_stay_outlined,
            iconColor: Colors.indigo,
            title: 'Вечерняя смена',
            startTime: _eveningStartTime,
            endTime: _eveningEndTime,
            onStartChanged: (time) => setState(() => _eveningStartTime = time),
            onEndChanged: (time) => setState(() => _eveningEndTime = time),
          ),
        ],
      ),
    );
  }

  Widget _buildAdminReviewTimeoutSection() {
    // Форматирование часов для отображения
    String formatHours(int hours) {
      if (hours == 1 || hours == 21) return '$hours час';
      if (hours >= 2 && hours <= 4 || hours >= 22 && hours <= 24) return '$hours часа';
      return '$hours часов';
    }

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
                  color: Colors.purple.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.admin_panel_settings_outlined,
                  color: Colors.purple,
                  size: 24,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Таймаут проверки',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF2D3436),
                      ),
                    ),
                    const Text(
                      'Время админу на оценку отчёта',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey,
                      ),
                    ),
                  ],
                ),
              ),
              // Текущее значение
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Colors.purple, Colors.deepPurple],
                  ),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.purple.withOpacity(0.3),
                      blurRadius: 8,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Text(
                  formatHours(_adminReviewTimeout),
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          // Слайдер
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: Colors.purple,
              inactiveTrackColor: Colors.purple.withOpacity(0.2),
              thumbColor: Colors.purple,
              overlayColor: Colors.purple.withOpacity(0.2),
              trackHeight: 6,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 10),
            ),
            child: Slider(
              value: _adminReviewTimeout.toDouble(),
              min: 1,
              max: 24,
              divisions: 23,
              onChanged: (value) {
                setState(() => _adminReviewTimeout = value.round());
              },
            ),
          ),
          // Метки
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('1 ч', style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                Text('6 ч', style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                Text('12 ч', style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                Text('18 ч', style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                Text('24 ч', style: TextStyle(fontSize: 12, color: Colors.grey[600])),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.amber.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.amber.withOpacity(0.3)),
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline, color: Colors.amber[700], size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Если админ не оценит отчёт за ${formatHours(_adminReviewTimeout)}, статус изменится на "Отклонено" и сотрудник получит штраф',
                    style: TextStyle(
                      fontSize: 12,
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

  Widget _buildTimeWindowRow({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String startTime,
    required String endTime,
    required ValueChanged<String> onStartChanged,
    required ValueChanged<String> onEndChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: iconColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: iconColor, size: 22),
            ),
            const SizedBox(width: 12),
            Text(
              title,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Color(0xFF2D3436),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _buildTimePickerButton(
                label: 'Начало',
                time: startTime,
                onChanged: onStartChanged,
                color: Colors.green,
              ),
            ),
            const SizedBox(width: 12),
            Icon(Icons.arrow_forward, color: Colors.grey[400], size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: _buildTimePickerButton(
                label: 'Дедлайн',
                time: endTime,
                onChanged: onEndChanged,
                color: Colors.red,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildTimePickerButton({
    required String label,
    required String time,
    required ValueChanged<String> onChanged,
    required Color color,
  }) {
    return InkWell(
      onTap: () async {
        final parts = time.split(':');
        final initialTime = TimeOfDay(
          hour: int.parse(parts[0]),
          minute: int.parse(parts[1]),
        );

        final picked = await showTimePicker(
          context: context,
          initialTime: initialTime,
          builder: (context, child) {
            return MediaQuery(
              data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
              child: Theme(
                data: Theme.of(context).copyWith(
                  colorScheme: ColorScheme.light(
                    primary: _gradientColors[0],
                    onPrimary: Colors.white,
                    surface: Colors.white,
                    onSurface: Colors.black,
                  ),
                ),
                child: child!,
              ),
            );
          },
        );

        if (picked != null) {
          final newTime = '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}';
          onChanged(newTime);
        }
      },
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Column(
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey[600],
              ),
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.access_time, size: 18, color: color),
                const SizedBox(width: 6),
                Text(
                  time,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPreviewTable() {
    final previewRatings = [1, 4, _zeroThreshold, 8, 10];

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
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Column(
          children: [
            // Header
            Container(
              padding: const EdgeInsets.symmetric(vertical: 14),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: _gradientColors,
                ),
              ),
              child: const Row(
                children: [
                  Expanded(
                    child: Text(
                      'Оценка',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  Expanded(
                    child: Text(
                      'Баллы',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ],
              ),
            ),
            // Rows
            ...previewRatings.asMap().entries.map((entry) {
              final index = entry.key;
              final rating = entry.value;
              final points = _calculatePoints(rating);
              final color = points < 0
                  ? Colors.red
                  : points > 0
                      ? Colors.green
                      : Colors.grey;
              final isLast = index == previewRatings.length - 1;

              return Container(
                decoration: BoxDecoration(
                  color: index.isEven ? Colors.grey[50] : Colors.white,
                  border: isLast
                      ? null
                      : Border(bottom: BorderSide(color: Colors.grey[200]!)),
                ),
                padding: const EdgeInsets.symmetric(vertical: 14),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '$rating / 10',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Container(
                        margin: const EdgeInsets.symmetric(horizontal: 20),
                        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
                        decoration: BoxDecoration(
                          color: color.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          points >= 0
                              ? '+${points.toStringAsFixed(2)}'
                              : points.toStringAsFixed(2),
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: color,
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildSaveButton() {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: _gradientColors,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: _gradientColors[0].withOpacity(0.4),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: ElevatedButton(
        onPressed: _isSaving ? null : _saveSettings,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.transparent,
          shadowColor: Colors.transparent,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        child: _isSaving
            ? const SizedBox(
                height: 24,
                width: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              )
            : const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.save_outlined, size: 22),
                  SizedBox(width: 10),
                  Text(
                    'Сохранить настройки',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
      ),
    );
  }
}
