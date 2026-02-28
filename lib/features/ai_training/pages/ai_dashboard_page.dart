import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/services/base_http_service.dart';
import '../../../core/utils/logger.dart';
import '../../../core/utils/cache_manager.dart';

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

  // Training state (polling)
  Map<String, dynamic>? _trainStatus; // {status, startedAt, finishedAt, result, error}
  Timer? _pollingTimer;

  // Schedule
  TimeOfDay? _scheduledTime;
  bool _savingSchedule = false;

  // Embedding toggle
  bool _embeddingEnabled = false;
  bool _embeddingToggling = false;

  @override
  void initState() {
    super.initState();
    _loadMetrics();
    _loadTrainStatus();
    _loadSchedule();
    _loadCvSettings();
  }

  @override
  void dispose() {
    _pollingTimer?.cancel();
    super.dispose();
  }

  static const _cacheKey = 'ai_dashboard_metrics';

  Future<void> _loadMetrics() async {
    // Step 1: Show cached data instantly
    final cached = CacheManager.get<Map<String, dynamic>>(_cacheKey);
    if (cached != null && mounted) {
      setState(() {
        _metrics = cached;
        _loading = false;
        _error = null;
      });
    }

    if (_metrics == null && mounted) setState(() { _loading = true; _error = null; });

    try {
      final result = await BaseHttpService.getRaw(
        endpoint: '/api/ai-dashboard/metrics',
      );
      if (!mounted) return;
      if (result != null && result['success'] == true) {
        final systems = result['systems'] as Map<String, dynamic>?;
        setState(() {
          _metrics = systems;
          _loading = false;
        });
        // Step 3: Save to cache
        if (systems != null) CacheManager.set(_cacheKey, systems);
      } else {
        if (_metrics == null && mounted) {
          setState(() {
            _error = 'Не удалось загрузить метрики';
            _loading = false;
          });
        }
      }
    } catch (e) {
      Logger.error('AI Dashboard load error', e);
      if (mounted && _metrics == null) {
        setState(() {
          _error = 'Ошибка: $e';
          _loading = false;
        });
      }
    }
  }

  // ── Training: запуск, polling, статус ──

  Future<void> _loadTrainStatus() async {
    try {
      final result = await BaseHttpService.getRaw(
        endpoint: '/api/ai-dashboard/recount-train-status',
      );
      if (!mounted) return;
      if (result != null) {
        setState(() => _trainStatus = result);
        if (result['status'] == 'running') _startPolling();
      }
    } catch (e) {
      Logger.error('Train status load error', e);
    }
  }

  void _startPolling() {
    _pollingTimer?.cancel();
    _pollingTimer = Timer.periodic(const Duration(seconds: 3), (_) async {
      try {
        final result = await BaseHttpService.getRaw(
          endpoint: '/api/ai-dashboard/recount-train-status',
        );
        if (!mounted) { _pollingTimer?.cancel(); return; }
        if (result != null) {
          setState(() => _trainStatus = result);
          if (result['status'] != 'running') {
            _pollingTimer?.cancel();
            if (result['status'] == 'done') _loadMetrics();
          }
        }
      } catch (e) { Logger.error('AiDashboard', 'Failed to poll training status', e); }
    });
  }

  Future<void> _triggerRecountTraining() async {
    if (_trainStatus?['status'] == 'running') return;
    try {
      final result = await BaseHttpService.postRaw(
        endpoint: '/api/ai-dashboard/trigger-recount-training',
        body: {'epochs': 30},
      );
      if (!mounted) return;
      if (result != null) {
        final state = result['state'] as Map<String, dynamic>?;
        if (state != null) setState(() => _trainStatus = state);
        if (result['started'] == true) _startPolling();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _trainStatus = {'status': 'error', 'error': '$e'});
      }
    }
  }

  // ── Schedule ──

  Future<void> _loadSchedule() async {
    try {
      final result = await BaseHttpService.getRaw(
        endpoint: '/api/ai-dashboard/recount-train-schedule',
      );
      if (!mounted) return;
      final t = result?['scheduledTime'] as String?;
      if (t != null && t.contains(':')) {
        final parts = t.split(':');
        setState(() => _scheduledTime = TimeOfDay(
          hour: int.parse(parts[0]),
          minute: int.parse(parts[1]),
        ));
      }
    } catch (e) {
      Logger.error('Schedule load error', e);
    }
  }

  Future<void> _pickAndSaveSchedule() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _scheduledTime ?? const TimeOfDay(hour: 3, minute: 0),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: const ColorScheme.dark(
            primary: AppColors.gold,
            surface: AppColors.night,
          ),
        ),
        child: child!,
      ),
    );
    if (!mounted || picked == null) return;
    await _saveSchedule(picked);
  }

  Future<void> _clearSchedule() async => _saveSchedule(null);

  Future<void> _saveSchedule(TimeOfDay? time) async {
    if (_savingSchedule) return;
    setState(() => _savingSchedule = true);
    try {
      final timeStr = time != null
          ? '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}'
          : null;
      await BaseHttpService.postRaw(
        endpoint: '/api/ai-dashboard/recount-train-schedule',
        body: {'time': timeStr},
      );
      if (!mounted) return;
      setState(() => _scheduledTime = time);
    } catch (e) {
      Logger.error('Schedule save error', e);
    } finally {
      if (mounted) setState(() => _savingSchedule = false);
    }
  }

  // ── CV Settings (embedding toggle) ──

  Future<void> _loadCvSettings() async {
    try {
      final result = await BaseHttpService.getRaw(
        endpoint: '/api/cigarette-vision/settings',
      );
      if (!mounted) return;
      final settings = result?['settings'] as Map<String, dynamic>?;
      if (settings != null) {
        setState(() {
          _embeddingEnabled = settings['useEmbeddingRecognition'] == true;
        });
      }
    } catch (e) {
      Logger.error('CV settings load error', e);
    }
  }

  Future<void> _toggleEmbedding(bool value) async {
    if (_embeddingToggling) return;
    setState(() => _embeddingToggling = true);
    try {
      await BaseHttpService.putRaw(
        endpoint: '/api/cigarette-vision/settings',
        body: {'useEmbeddingRecognition': value},
      );
      if (!mounted) return;
      setState(() => _embeddingEnabled = value);
    } catch (e) {
      Logger.error('Embedding toggle error', e);
    } finally {
      if (mounted) setState(() => _embeddingToggling = false);
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
            colors: [AppColors.emerald, AppColors.emeraldDark, AppColors.night],
            stops: [0.0, 0.3, 1.0],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              _buildAppBar(),
              Expanded(
                child: _loading
                    ? const Center(child: CircularProgressIndicator(color: AppColors.gold))
                    : _error != null
                        ? _buildError()
                        : RefreshIndicator(
                            onRefresh: _loadMetrics,
                            color: AppColors.gold,
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
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.gold, foregroundColor: AppColors.night),
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
            [AppColors.gold, AppColors.darkGold],
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

        // Cigarette Vision + Пересчёт ИИ (объединённая карточка)
        if (_metrics!['cigaretteVision'] != null)
          _buildRecountAiCard(_metrics!['cigaretteVision'] as Map<String, dynamic>),
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
            AppColors.gold.withOpacity(0.15),
            AppColors.darkGold.withOpacity(0.05),
          ],
        ),
        border: Border.all(color: AppColors.gold.withOpacity(0.25)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Icon(Icons.auto_awesome, color: AppColors.gold, size: 24),
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

  Widget _buildRecountAiCard(Map<String, dynamic> cigMetrics) {
    final modelExists = cigMetrics['modelExists'] == true;
    final pending = cigMetrics['countingPendingSamples'] as int? ?? 0;
    final approved = cigMetrics['countingTrainingSamples'] as int? ?? 0;
    final annotated = cigMetrics['countingAnnotatedSamples'] as int? ?? 0;
    final needMore = annotated < 50 ? (50 - annotated) : 0;
    final accuracy = cigMetrics['accuracy'];
    final totalErrors = cigMetrics['totalErrors'] as int? ?? 0;
    final totalDecisions = cigMetrics['totalDecisions'] as int? ?? 0;
    final productsTracked = cigMetrics['productsTracked'] as int? ?? 0;
    final statusColor = modelExists ? AppColors.success : AppColors.warning;
    const gradientA = AppColors.emerald;
    const gradientB = AppColors.emeraldLight;

    final trainStatus = _trainStatus?['status'] as String? ?? 'idle';
    final isRunning = trainStatus == 'running';
    final isDone = trainStatus == 'done';
    final isError = trainStatus == 'error';

    return Container(
      padding: EdgeInsets.all(14.w),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16.r),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [gradientA.withOpacity(0.15), gradientB.withOpacity(0.05)],
        ),
        border: Border.all(color: gradientA.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Заголовок ──
          Row(
            children: [
              Container(
                width: 36, height: 36,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10.r),
                  gradient: const LinearGradient(colors: [gradientA, gradientB]),
                ),
                child: const Icon(Icons.camera_alt_outlined, color: Colors.white, size: 20),
              ),
              SizedBox(width: 10.w),
              Expanded(
                child: Text(
                  'Cigarette Vision (YOLO)',
                  style: TextStyle(color: Colors.white.withOpacity(0.95), fontSize: 14.sp, fontWeight: FontWeight.w600),
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
                  modelExists ? 'Обучена' : 'Нет модели',
                  style: TextStyle(color: statusColor, fontSize: 10.sp, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          SizedBox(height: 12.h),

          // ── Общие метрики ──
          Wrap(
            spacing: 8.w,
            runSpacing: 6.h,
            children: [
              if (accuracy != null && accuracy is num)
                _buildMetricChip('Точность', '${accuracy.toStringAsFixed(1)}%',
                    accuracy >= 80 ? AppColors.success : AppColors.warning),
              if (productsTracked > 0)
                _buildMetricChip('Товаров', '$productsTracked', Colors.blue),
              if (totalDecisions > 0)
                _buildMetricChip('Решений админа', '$totalDecisions', AppColors.gold),
              if (totalErrors > 0)
                _buildMetricChip('Ошибок ИИ', '$totalErrors', AppColors.error),
            ],
          ),
          SizedBox(height: 10.h),

          // ── Метрики обучения ──
          Wrap(
            spacing: 8.w,
            runSpacing: 6.h,
            children: [
              _buildMetricChip('Ожидают проверки', '$pending', Colors.orange),
              _buildMetricChip('Одобрено', '$approved', Colors.blue[300]!),
              _buildMetricChip('С аннотациями', '$annotated', gradientA),
              if (needMore > 0)
                _buildMetricChip('Нужно ещё', '$needMore', AppColors.warning),
            ],
          ),
          SizedBox(height: 14.h),

          // ── Статус обучения ──
          if (isRunning) ...[
            Row(children: [
              SizedBox(
                width: 14, height: 14,
                child: CircularProgressIndicator(strokeWidth: 2, color: gradientA),
              ),
              SizedBox(width: 8.w),
              Text('Обучение идёт...', style: TextStyle(color: Colors.white70, fontSize: 12.sp)),
            ]),
            SizedBox(height: 6.h),
            ClipRRect(
              borderRadius: BorderRadius.circular(4.r),
              child: LinearProgressIndicator(
                backgroundColor: Colors.white12,
                color: gradientA,
              ),
            ),
            SizedBox(height: 10.h),
          ] else if (isDone) ...[
            _buildTrainResultBanner(
              icon: Icons.check_circle_outline,
              color: AppColors.success,
              text: 'Обучение завершено. '
                  'Изображений: ${_trainStatus?['result']?['totalImages'] ?? '?'}. '
                  'Модель перезагружена: ${_trainStatus?['result']?['modelReloaded'] == true ? 'да' : 'нет'}.',
            ),
            // Метрики точности модели
            Builder(builder: (_) {
              final metrics = _trainStatus?['result']?['metrics'] as Map<String, dynamic>?;
              if (metrics == null) return const SizedBox.shrink();
              final mAP50 = metrics['mAP50'] as num?;
              final precision = metrics['precision'] as num?;
              final recall = metrics['recall'] as num?;
              if (mAP50 == null && precision == null && recall == null) return const SizedBox.shrink();
              return Padding(
                padding: EdgeInsets.only(top: 8.h),
                child: Wrap(
                  spacing: 8.w, runSpacing: 6.h,
                  children: [
                    if (mAP50 != null)
                      _buildMetricChip('mAP50', '${(mAP50 * 100).toStringAsFixed(1)}%',
                          mAP50 > 0.7 ? AppColors.success : mAP50 > 0.5 ? Colors.orange : AppColors.error),
                    if (precision != null)
                      _buildMetricChip('Точность', '${(precision * 100).toStringAsFixed(1)}%', Colors.blue[300]!),
                    if (recall != null)
                      _buildMetricChip('Полнота', '${(recall * 100).toStringAsFixed(1)}%', Colors.teal[300]!),
                  ],
                ),
              );
            }),
            SizedBox(height: 10.h),
          ] else if (isError) ...[
            _buildTrainResultBanner(
              icon: Icons.error_outline,
              color: AppColors.error,
              text: 'Ошибка: ${_trainStatus?['error'] ?? 'неизвестная'}',
            ),
            SizedBox(height: 10.h),
          ],

          // ── Кнопка запуска ──
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: (isRunning || annotated < 5) ? null : _triggerRecountTraining,
              icon: isRunning
                  ? SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.model_training, size: 18),
              label: Text(isRunning ? 'Обучение идёт...' : 'Запустить обучение (30 эпох)'),
              style: ElevatedButton.styleFrom(
                backgroundColor: annotated >= 5 ? AppColors.gold : Colors.grey[700],
                foregroundColor: annotated >= 5 ? AppColors.night : Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10.r)),
                padding: EdgeInsets.symmetric(vertical: 10.h),
              ),
            ),
          ),
          if (annotated < 5)
            Padding(
              padding: EdgeInsets.only(top: 5.h),
              child: Text(
                'Нужно минимум 5 одобренных образцов для обучения',
                style: TextStyle(color: Colors.white38, fontSize: 10.sp),
                textAlign: TextAlign.center,
              ),
            ),

          SizedBox(height: 14.h),
          Divider(color: Colors.white.withOpacity(0.08), height: 1),
          SizedBox(height: 12.h),

          // ── Эмбеддинги (1000+ товаров) ──
          Row(
            children: [
              Icon(Icons.hub_rounded, color: Colors.white38, size: 16),
              SizedBox(width: 6.w),
              Expanded(
                child: Text(
                  'Распознавание 1000+ товаров',
                  style: TextStyle(color: Colors.white54, fontSize: 12.sp, fontWeight: FontWeight.w500),
                ),
              ),
              if (_embeddingToggling)
                SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.gold))
              else
                SizedBox(
                  height: 28,
                  child: Switch(
                    value: _embeddingEnabled,
                    onChanged: _toggleEmbedding,
                    activeColor: AppColors.gold,
                    activeTrackColor: AppColors.gold.withOpacity(0.3),
                    inactiveThumbColor: Colors.white24,
                    inactiveTrackColor: Colors.white.withOpacity(0.08),
                  ),
                ),
            ],
          ),
          if (_embeddingEnabled)
            Padding(
              padding: EdgeInsets.only(top: 4.h, left: 22.w),
              child: Text(
                'Двухэтапное распознавание: YOLO + MobileNet эмбеддинги',
                style: TextStyle(color: AppColors.gold.withOpacity(0.6), fontSize: 10.sp),
              ),
            ),

          SizedBox(height: 14.h),
          Divider(color: Colors.white.withOpacity(0.08), height: 1),
          SizedBox(height: 12.h),

          // ── Расписание ──
          Row(
            children: [
              Icon(Icons.schedule_rounded, color: Colors.white38, size: 16),
              SizedBox(width: 6.w),
              Text(
                'Авто-обучение',
                style: TextStyle(color: Colors.white54, fontSize: 12.sp, fontWeight: FontWeight.w500),
              ),
              const Spacer(),
              if (_savingSchedule)
                SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.gold))
              else if (_scheduledTime != null)
                GestureDetector(
                  onTap: _clearSchedule,
                  child: Icon(Icons.close_rounded, color: Colors.white38, size: 16),
                ),
            ],
          ),
          SizedBox(height: 8.h),
          Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: _pickAndSaveSchedule,
                  child: Container(
                    padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 9.h),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10.r),
                      color: Colors.white.withOpacity(0.05),
                      border: Border.all(
                        color: _scheduledTime != null ? AppColors.gold.withOpacity(0.5) : Colors.white.withOpacity(0.1),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          _scheduledTime != null ? Icons.alarm_on_rounded : Icons.alarm_off_rounded,
                          color: _scheduledTime != null ? AppColors.gold : Colors.white30,
                          size: 18,
                        ),
                        SizedBox(width: 8.w),
                        Text(
                          _scheduledTime != null
                              ? 'Ежедневно в ${_scheduledTime!.hour.toString().padLeft(2, '0')}:${_scheduledTime!.minute.toString().padLeft(2, '0')}'
                              : 'Не задано — нажмите для настройки',
                          style: TextStyle(
                            color: _scheduledTime != null ? Colors.white.withOpacity(0.85) : Colors.white30,
                            fontSize: 12.sp,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTrainResultBanner({
    required IconData icon,
    required Color color,
    required String text,
  }) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 8.h),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8.r),
        color: color.withOpacity(0.08),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 16),
          SizedBox(width: 6.w),
          Expanded(
            child: Text(text, style: TextStyle(color: Colors.white70, fontSize: 11.sp)),
          ),
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
            AppColors.gold.withOpacity(0.15),
            AppColors.darkGold.withOpacity(0.05),
          ],
        ),
        border: Border.all(color: AppColors.gold.withOpacity(0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.calendar_today_outlined, color: AppColors.gold, size: 18),
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
                      : AppColors.gold;

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
