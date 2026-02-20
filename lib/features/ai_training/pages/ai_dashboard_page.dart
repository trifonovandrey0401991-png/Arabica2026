import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/services/base_http_service.dart';
import '../../../core/utils/logger.dart';

/// Страница ДашБорд AI — метрики всех AI-систем
class AiDashboardPage extends StatefulWidget {
  const AiDashboardPage({super.key});

  @override
  State<AiDashboardPage> createState() => _AiDashboardPageState();
}

class _AiDashboardPageState extends State<AiDashboardPage> {
  bool _loading = true;
  String? _error;
  Map<String, dynamic>? _metrics;

  @override
  void initState() {
    super.initState();
    _loadMetrics();
  }

  Future<void> _loadMetrics() async {
    if (mounted) setState(() { _loading = true; _error = null; });
    try {
      final result = await BaseHttpService.getRaw(
        endpoint: '/api/ai-dashboard/metrics',
      );
      if (!mounted) return;
      if (result != null && result['success'] == true) {
        setState(() {
          _metrics = result['systems'] as Map<String, dynamic>?;
          _loading = false;
        });
      } else {
        setState(() {
          _error = 'Не удалось загрузить метрики';
          _loading = false;
        });
      }
    } catch (e) {
      Logger.error('AI Dashboard load error', e);
      if (mounted) {
        setState(() {
          _error = 'Ошибка: $e';
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.night,
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [AppColors.darkNavy, AppColors.navy, Color(0xFF0A0A1A)],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              _buildAppBar(),
              Expanded(
                child: _loading
                    ? const Center(child: CircularProgressIndicator(color: AppColors.indigo))
                    : _error != null
                        ? _buildError()
                        : RefreshIndicator(
                            onRefresh: _loadMetrics,
                            color: AppColors.indigo,
                            child: _buildContent(),
                          ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAppBar() {
    return Padding(
      padding: EdgeInsets.fromLTRB(12.w, 6.h, 12.w, 0),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.08),
                borderRadius: BorderRadius.circular(14.r),
                border: Border.all(color: Colors.white.withOpacity(0.1)),
              ),
              child: Icon(Icons.arrow_back_ios_new_rounded,
                  color: Colors.white.withOpacity(0.8), size: 20),
            ),
          ),
          Expanded(
            child: Center(
              child: Text(
                'ДашБорд AI',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.95),
                  fontSize: 18.sp,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1,
                ),
              ),
            ),
          ),
          GestureDetector(
            onTap: _loadMetrics,
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.08),
                borderRadius: BorderRadius.circular(14.r),
                border: Border.all(color: Colors.white.withOpacity(0.1)),
              ),
              child: Icon(Icons.refresh_rounded,
                  color: Colors.white.withOpacity(0.8), size: 20),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.error_outline, color: AppColors.error, size: 48),
          SizedBox(height: 12.h),
          Text(_error!, style: TextStyle(color: Colors.white70, fontSize: 14.sp)),
          SizedBox(height: 16.h),
          ElevatedButton(
            onPressed: _loadMetrics,
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.indigo),
            child: const Text('Повторить'),
          ),
        ],
      ),
    );
  }

  Widget _buildContent() {
    if (_metrics == null) return const SizedBox.shrink();

    final systems = [
      _metrics!['zReport'],
      _metrics!['coffeeMachine'],
      _metrics!['cigaretteVision'],
      _metrics!['shiftAi'],
    ];

    return ListView(
      padding: EdgeInsets.fromLTRB(12.w, 12.h, 12.w, 24.h),
      children: [
        // Общая сводка
        _buildOverallSummary(systems),
        SizedBox(height: 16.h),

        // Z-Report OCR
        if (_metrics!['zReport'] != null)
          _buildSystemCard(
            _metrics!['zReport'] as Map<String, dynamic>,
            Icons.receipt_long_outlined,
            [AppColors.indigo, AppColors.purple],
          ),
        SizedBox(height: 12.h),

        // Coffee Machine OCR
        if (_metrics!['coffeeMachine'] != null)
          _buildSystemCard(
            _metrics!['coffeeMachine'] as Map<String, dynamic>,
            Icons.coffee_outlined,
            [AppColors.emeraldGreen, AppColors.emeraldGreenLight],
          ),
        SizedBox(height: 12.h),

        // Cigarette Vision
        if (_metrics!['cigaretteVision'] != null)
          _buildSystemCard(
            _metrics!['cigaretteVision'] as Map<String, dynamic>,
            Icons.camera_alt_outlined,
            [AppColors.warning, AppColors.warningLight],
          ),
        SizedBox(height: 12.h),

        // Shift AI
        if (_metrics!['shiftAi'] != null)
          _buildSystemCard(
            _metrics!['shiftAi'] as Map<String, dynamic>,
            Icons.verified_outlined,
            [AppColors.info, AppColors.infoLight],
          ),

        // Day-of-week коэффициенты
        if (_metrics!['zReport']?['dowCoefficients'] != null) ...[
          SizedBox(height: 16.h),
          _buildDowCard(_metrics!['zReport']['dowCoefficients'] as Map<String, dynamic>),
        ],
      ],
    );
  }

  Widget _buildOverallSummary(List<dynamic> systems) {
    int activeCount = 0;
    double totalAccuracy = 0;
    int accuracyCount = 0;

    for (final sys in systems) {
      if (sys == null) continue;
      final m = sys as Map<String, dynamic>;
      if (m['status'] == 'active') activeCount++;
      final acc = m['accuracy'];
      if (acc != null && acc is num) {
        totalAccuracy += acc;
        accuracyCount++;
      }
    }

    final avgAccuracy = accuracyCount > 0 ? totalAccuracy / accuracyCount : null;

    return Container(
      padding: EdgeInsets.all(16.w),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16.r),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppColors.indigo.withOpacity(0.2),
            AppColors.purple.withOpacity(0.1),
          ],
        ),
        border: Border.all(color: AppColors.indigo.withOpacity(0.3)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Icon(Icons.auto_awesome, color: AppColors.indigo, size: 24),
              SizedBox(width: 8.w),
              Text(
                'Общая сводка',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.95),
                  fontSize: 16.sp,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          SizedBox(height: 12.h),
          Row(
            children: [
              Expanded(child: _buildMiniMetric('Систем активно', '$activeCount/4', AppColors.success)),
              SizedBox(width: 8.w),
              Expanded(
                child: _buildMiniMetric(
                  'Средняя точность',
                  avgAccuracy != null ? '${avgAccuracy.toStringAsFixed(1)}%' : 'N/A',
                  avgAccuracy != null && avgAccuracy >= 80 ? AppColors.success : AppColors.warning,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMiniMetric(String label, String value, Color color) {
    return Container(
      padding: EdgeInsets.symmetric(vertical: 10.h, horizontal: 8.w),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12.r),
        color: color.withOpacity(0.1),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Column(
        children: [
          Text(
            value,
            style: TextStyle(color: color, fontSize: 18.sp, fontWeight: FontWeight.w700),
          ),
          SizedBox(height: 4.h),
          Text(
            label,
            style: TextStyle(color: Colors.white54, fontSize: 10.sp),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildSystemCard(
    Map<String, dynamic> system,
    IconData icon,
    List<Color> gradientColors,
  ) {
    final name = system['name'] as String? ?? 'Unknown';
    final status = system['status'] as String? ?? 'unknown';
    final accuracy = system['accuracy'];

    final isActive = status == 'active';
    final statusText = _statusText(status);
    final statusColor = isActive ? AppColors.success : AppColors.warning;

    // Собираем метрики
    final metrics = <MapEntry<String, String>>[];

    if (accuracy != null && accuracy is num) {
      metrics.add(MapEntry('Точность', '${accuracy.toStringAsFixed(1)}%'));
    } else if (accuracy is Map) {
      // Z-Report: { totalSum: 85.7, cashSum: 90.2 }
      final ts = accuracy['totalSum'];
      final cs = accuracy['cashSum'];
      if (ts != null) metrics.add(MapEntry('Выручка (точн.)', '${(ts as num).toStringAsFixed(1)}%'));
      if (cs != null) metrics.add(MapEntry('Наличные (точн.)', '${(cs as num).toStringAsFixed(1)}%'));
    }

    if (system['trainingSamples'] != null) {
      metrics.add(MapEntry('Обуч. образцов', '${system['trainingSamples']}'));
    }
    if (system['trainingImages'] != null) {
      metrics.add(MapEntry('Обуч. изображений', '${system['trainingImages']}'));
    }
    if (system['totalReadings'] != null) {
      metrics.add(MapEntry('Всего считываний', '${system['totalReadings']}'));
    }
    if (system['avgError'] != null && (system['avgError'] as num) > 0) {
      metrics.add(MapEntry('Средняя ошибка', '${system['avgError']}'));
    }
    if (system['totalReports'] != null) {
      metrics.add(MapEntry('Отчётов', '${system['totalReports']}'));
    }
    if (system['shopCount'] != null) {
      metrics.add(MapEntry('Магазинов', '${system['shopCount']}'));
    }
    if (system['machineCount'] != null) {
      metrics.add(MapEntry('Машин', '${system['machineCount']}'));
    }

    // Shift AI specific
    if (system['totalAnnotations'] != null) {
      metrics.add(MapEntry('Аннотаций', '${system['totalAnnotations']}'));
    }
    if (system['approved'] != null) {
      metrics.add(MapEntry('Подтверждено', '${system['approved']}'));
    }
    if (system['rejected'] != null) {
      metrics.add(MapEntry('Отклонено', '${system['rejected']}'));
    }

    // Cigarette specific
    if (system['totalErrors'] != null && (system['totalErrors'] as num) > 0) {
      metrics.add(MapEntry('Ошибок ИИ', '${system['totalErrors']}'));
    }
    if (system['totalDecisions'] != null && (system['totalDecisions'] as num) > 0) {
      metrics.add(MapEntry('Решений админа', '${system['totalDecisions']}'));
    }
    if (system['modelExists'] != null) {
      metrics.add(MapEntry('Модель', system['modelExists'] == true ? 'Обучена' : 'Нет'));
    }

    return Container(
      padding: EdgeInsets.all(14.w),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16.r),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            gradientColors[0].withOpacity(0.15),
            gradientColors[1].withOpacity(0.05),
          ],
        ),
        border: Border.all(color: gradientColors[0].withOpacity(0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10.r),
                  gradient: LinearGradient(colors: gradientColors),
                ),
                child: Icon(icon, color: Colors.white, size: 20),
              ),
              SizedBox(width: 10.w),
              Expanded(
                child: Text(
                  name,
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.95),
                    fontSize: 14.sp,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Container(
                padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 3.h),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8.r),
                  color: statusColor.withOpacity(0.15),
                  border: Border.all(color: statusColor.withOpacity(0.4)),
                ),
                child: Text(
                  statusText,
                  style: TextStyle(color: statusColor, fontSize: 10.sp, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),

          if (metrics.isNotEmpty) ...[
            SizedBox(height: 12.h),
            // Metrics grid
            Wrap(
              spacing: 8.w,
              runSpacing: 6.h,
              children: metrics.map((e) => _buildMetricChip(e.key, e.value, gradientColors[0])).toList(),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildMetricChip(String label, String value, Color color) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 5.h),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8.r),
        color: Colors.white.withOpacity(0.05),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$label: ',
            style: TextStyle(color: Colors.white54, fontSize: 10.sp),
          ),
          Text(
            value,
            style: TextStyle(color: color, fontSize: 11.sp, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }

  Widget _buildDowCard(Map<String, dynamic> coefficients) {
    final dayNames = ['Вс', 'Пн', 'Вт', 'Ср', 'Чт', 'Пт', 'Сб'];
    final today = DateTime.now().weekday % 7; // DateTime.weekday: 1=Mon..7=Sun → 0=Sun

    return Container(
      padding: EdgeInsets.all(14.w),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16.r),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppColors.indigo.withOpacity(0.15),
            AppColors.purple.withOpacity(0.05),
          ],
        ),
        border: Border.all(color: AppColors.indigo.withOpacity(0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.calendar_today_outlined, color: AppColors.indigo, size: 18),
              SizedBox(width: 8.w),
              Text(
                'Коэффициенты по дням недели',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.9),
                  fontSize: 13.sp,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          SizedBox(height: 4.h),
          Text(
            'Насколько выручка отличается от средней в каждый день',
            style: TextStyle(color: Colors.white38, fontSize: 10.sp),
          ),
          SizedBox(height: 12.h),
          Row(
            children: List.generate(7, (i) {
              final coeff = (coefficients['$i'] as num?)?.toDouble() ?? 1.0;
              final isToday = i == today;
              final isHigh = coeff > 1.05;
              final isLow = coeff < 0.95;
              final barColor = isHigh
                  ? AppColors.success
                  : isLow
                      ? AppColors.warning
                      : AppColors.indigo;

              // Нормализация высоты бара (0.5 → 0%, 1.5 → 100%)
              final barHeight = ((coeff - 0.5) / 1.0).clamp(0.1, 1.0) * 60;

              return Expanded(
                child: Container(
                  margin: EdgeInsets.symmetric(horizontal: 2.w),
                  decoration: isToday
                      ? BoxDecoration(
                          borderRadius: BorderRadius.circular(8.r),
                          border: Border.all(color: Colors.white.withOpacity(0.2)),
                          color: Colors.white.withOpacity(0.05),
                        )
                      : null,
                  padding: EdgeInsets.symmetric(vertical: 4.h),
                  child: Column(
                    children: [
                      Text(
                        '${(coeff * 100).round()}%',
                        style: TextStyle(
                          color: barColor,
                          fontSize: 9.sp,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      SizedBox(height: 4.h),
                      Container(
                        width: 14.w,
                        height: barHeight,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(4.r),
                          color: barColor.withOpacity(0.6),
                        ),
                      ),
                      SizedBox(height: 4.h),
                      Text(
                        dayNames[i],
                        style: TextStyle(
                          color: isToday ? Colors.white : Colors.white54,
                          fontSize: 10.sp,
                          fontWeight: isToday ? FontWeight.w700 : FontWeight.w400,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }),
          ),
        ],
      ),
    );
  }

  String _statusText(String status) {
    switch (status) {
      case 'active':
        return 'Активна';
      case 'no_data':
        return 'Нет данных';
      case 'model_missing':
        return 'Нет модели';
      case 'error':
        return 'Ошибка';
      default:
        return status;
    }
  }
}
