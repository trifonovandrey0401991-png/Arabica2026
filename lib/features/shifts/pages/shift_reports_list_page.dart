import 'package:flutter/material.dart';
import '../../../core/utils/cache_manager.dart';
import '../models/shift_report_model.dart';
import '../models/pending_shift_report_model.dart';
import '../services/shift_report_service.dart';
import 'shift_report_view_page.dart';
import 'shift_summary_report_page.dart';
import '../../../core/utils/logger.dart';
import '../../../core/services/report_notification_service.dart';
import '../../../features/shops/models/shop_model.dart';
import '../../../features/shops/services/shop_service.dart';
import '../../../features/efficiency/models/points_settings_model.dart';
import '../../../features/efficiency/services/points_settings_service.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../../core/theme/app_colors.dart';

/// Модель строки сводного отчёта (дата + смена)
class ShiftSummaryItem {
  final DateTime date;
  final String shiftType; // 'morning' | 'evening'
  final String shiftName; // 'Утренняя' | 'Вечерняя'
  final int passedCount;  // Сколько магазинов прошли
  final int totalCount;   // Всего магазинов
  final List<ShiftReport> reports; // Отчёты за эту смену

  ShiftSummaryItem({
    required this.date,
    required this.shiftType,
    required this.shiftName,
    required this.passedCount,
    required this.totalCount,
    required this.reports,
  });

  String get displayTitle {
    final months = ['', 'января', 'февраля', 'марта', 'апреля', 'мая', 'июня',
                   'июля', 'августа', 'сентября', 'октября', 'ноября', 'декабря'];
    return '${date.day} ${months[date.month]}, $shiftName ($passedCount/$totalCount)';
  }
}

/// Тип группы для иерархической группировки отчётов
enum ReportGroupType { today, yesterday, day, week, month }

/// Группа отчётов для иерархического отображения
class ReportGroup {
  final ReportGroupType type;
  final String title;
  final String key; // Уникальный ключ для хранения состояния
  final int count;
  final DateTime startDate;
  final List<dynamic> children; // List<ShiftReport> или List<ReportGroup>

  ReportGroup({
    required this.type,
    required this.title,
    required this.key,
    required this.count,
    required this.startDate,
    required this.children,
  });
}

/// Страница со списком отчетов по пересменкам с вкладками
class ShiftReportsListPage extends StatefulWidget {
  const ShiftReportsListPage({super.key});

  @override
  State<ShiftReportsListPage> createState() => _ShiftReportsListPageState();
}

class _ShiftReportsListPageState extends State<ShiftReportsListPage>
    with SingleTickerProviderStateMixin {

  late TabController _tabController;
  bool _isLoading = true;
  Future<List<String>> _shopsFuture = Future.value([]);
  String? _selectedShop;
  String? _selectedEmployee;
  DateTime? _selectedDate;
  List<ShiftReport> _allReports = [];
  List<PendingShiftReport> _pendingShifts = [];
  List<PendingShiftReport> _failedShifts = []; // Просроченные непройденные пересменки
  List<ShiftReport> _expiredReports = [];
  List<Shop> _allShops = [];
  ShiftPointsSettings? _shiftSettings;
  int _failedShiftsBadgeCount = 0;
  List<ShiftSummaryItem> _summaryItems = []; // Сводные данные за 30 дней

  // Состояние раскрытия групп (ключ = уникальный идентификатор группы)
  final Map<String, bool> _expandedGroups = {};

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 6, vsync: this);
    _tabController.addListener(_onTabChanged);
    _loadData();
    // Отмечаем все уведомления этого типа как просмотренные
    ReportNotificationService.markAllAsViewed(reportType: ReportType.shiftHandover);
  }

  void _onTabChanged() {
    // Когда открываем вкладку "Не прошли" (index 1), обнуляем счётчик
    if (_tabController.index == 1 && _failedShiftsBadgeCount > 0) {
      if (mounted) setState(() {
        _failedShiftsBadgeCount = 0;
      });
    } else {
      // Обновляем UI для подсветки активной вкладки
      if (mounted) setState(() {});
    }
  }

  @override
  void dispose() {
    _tabController.removeListener(_onTabChanged);
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    Logger.info('Загрузка отчетов пересменки...');

    // Step 1: Show cached data instantly
    final cached = CacheManager.get<Map<String, dynamic>>('reports_shifts');
    if (cached != null && mounted) {
      _allReports = cached['allReports'] as List<ShiftReport>;
      _allShops = cached['allShops'] as List<Shop>;
      _pendingShifts = cached['pendingShifts'] as List<PendingShiftReport>;
      _failedShifts = cached['failedShifts'] as List<PendingShiftReport>;
      _expiredReports = cached['expiredReports'] as List<ShiftReport>;
      _shiftSettings = cached['shiftSettings'] as ShiftPointsSettings?;
      _summaryItems = cached['summaryItems'] as List<ShiftSummaryItem>;
      _isLoading = false;
      setState(() {});
    }

    // Step 2: Fetch fresh data (6 parallel requests)
    ShiftPointsSettings? settings;
    List<Shop> shops = [];
    List<ShiftReport> serverReports = [];
    List<ShiftReport> expiredReports = [];
    List<ShiftReport> localReports = [];
    List<ShiftReport> pendingReports = [];

    await Future.wait([
      () async {
        try { settings = await PointsSettingsService.getShiftPointsSettings(); }
        catch (e) { Logger.error('Ошибка загрузки настроек пересменки', e); }
      }(),
      () async {
        try { shops = await ShopService.getShopsForCurrentUser(); }
        catch (e) { Logger.error('Ошибка загрузки магазинов', e); }
      }(),
      () async {
        try { serverReports = await ShiftReportService.getReportsForCurrentUser(); }
        catch (e) { Logger.error('Ошибка загрузки отчетов с сервера', e); }
      }(),
      () async {
        try { expiredReports = await ShiftReportService.getExpiredReportsForCurrentUser(); }
        catch (e) { Logger.error('Ошибка загрузки просроченных отчётов', e); }
      }(),
      () async {
        try { localReports = await ShiftReport.loadAllReports(); }
        catch (e) { Logger.error('Ошибка загрузки локальных отчетов', e); }
      }(),
      () async {
        try { pendingReports = await ShiftReportService.getPendingReportsForCurrentUser(); }
        catch (e) { Logger.error('Ошибка загрузки pending отчётов', e); }
      }(),
    ]);

    if (settings != null) {
      _shiftSettings = settings;
    }

    _allShops = shops;
    _expiredReports = expiredReports;

    final Map<String, ShiftReport> reportsMap = {};
    for (var report in localReports) {
      reportsMap[report.id] = report;
    }
    for (var report in serverReports) {
      reportsMap[report.id] = report;
    }
    _allReports = reportsMap.values.toList();
    _allReports.sort((a, b) => b.createdAt.compareTo(a.createdAt));

    final addresses = <String>{};
    for (var report in _allReports) {
      if (report.shopAddress.trim().isNotEmpty) addresses.add(report.shopAddress);
    }
    _shopsFuture = Future.value(addresses.toList()..sort());

    _processPendingAndFailed(pendingReports);
    _calculateSummaryItems();

    Logger.success('Загружено: ${_allReports.length} отчётов, ${shops.length} магазинов, ${_pendingShifts.length} pending, ${_failedShifts.length} failed');
    if (!mounted) return;
    setState(() {
      _isLoading = false;
    });

    // Step 3: Save to cache
    CacheManager.set('reports_shifts', {
      'allReports': _allReports,
      'allShops': _allShops,
      'pendingShifts': _pendingShifts,
      'failedShifts': _failedShifts,
      'expiredReports': _expiredReports,
      'shiftSettings': _shiftSettings,
      'summaryItems': _summaryItems,
    });
  }

  /// Определить тип смены по времени отчёта
  String _getShiftType(DateTime time) {
    final hour = time.hour;
    // Утренняя смена: 7:00 - 13:59
    // Вечерняя смена: 14:00 - 23:59 и 0:00 - 6:59
    if (hour >= 7 && hour < 14) {
      return 'morning';
    }
    return 'evening';
  }

  /// Определить текущий активный тип смены (morning/evening) или null если вне интервала
  String? _getCurrentShiftType() {
    if (_shiftSettings == null) return null;

    final now = TimeOfDay.now();
    final currentMinutes = now.hour * 60 + now.minute;

    // Парсим время из настроек
    TimeOfDay parseTime(String timeStr) {
      final parts = timeStr.split(':');
      return TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1]));
    }

    final morningStartMinutes = _timeToMinutes(parseTime(_shiftSettings!.morningStartTime));
    final morningEndMinutes = _timeToMinutes(parseTime(_shiftSettings!.morningEndTime));
    final eveningStartMinutes = _timeToMinutes(parseTime(_shiftSettings!.eveningStartTime));
    final eveningEndMinutes = _timeToMinutes(parseTime(_shiftSettings!.eveningEndTime));

    if (_isInTimeRange(currentMinutes, morningStartMinutes, morningEndMinutes)) {
      return 'morning';
    } else if (_isInTimeRange(currentMinutes, eveningStartMinutes, eveningEndMinutes)) {
      return 'evening';
    }

    return null; // Вне интервалов
  }

  int _timeToMinutes(TimeOfDay time) => time.hour * 60 + time.minute;

  /// Проверка попадания в интервал с поддержкой перехода через полночь
  /// Например: start=23:01 (1381), end=13:00 (780) — переход через полночь
  bool _isInTimeRange(int current, int start, int end) {
    if (start <= end) {
      // Обычный интервал (например 14:00 - 23:00)
      return current >= start && current < end;
    } else {
      // Интервал через полночь (например 23:01 - 13:00)
      return current >= start || current < end;
    }
  }

  /// Обработка pending и failed отчётов из уже загруженных данных (без доп. запросов)
  void _processPendingAndFailed(List<ShiftReport> pendingReports) {
    final today = DateTime.now();
    final todayStr = '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';

    final morningDeadline = _shiftSettings?.morningEndTime ?? '13:00';
    final eveningDeadline = _shiftSettings?.eveningEndTime ?? '23:00';
    final currentShiftType = _getCurrentShiftType();

    // Фильтруем pending только для текущего интервала
    final filteredPending = currentShiftType != null
        ? pendingReports.where((r) => r.shiftType == currentShiftType).toList()
        : <ShiftReport>[];

    // Failed берём из уже загруженных _allReports (за сегодня)
    final failedReports = _allReports.where((r) {
      if (r.status != 'failed') return false;
      final local = r.createdAt.toLocal();
      return local.year == today.year && local.month == today.month && local.day == today.day;
    }).toList();

    // Конвертируем в PendingShiftReport
    _pendingShifts = filteredPending.map((report) {
      final isMorning = report.shiftType == 'morning';
      return PendingShiftReport(
        id: report.id,
        shopAddress: report.shopAddress,
        shiftType: report.shiftType ?? 'morning',
        shiftLabel: isMorning ? 'Утро' : 'Вечер',
        date: todayStr,
        deadline: isMorning ? morningDeadline : eveningDeadline,
        status: 'pending',
        createdAt: report.createdAt,
      );
    }).toList();

    _failedShifts = failedReports.map((report) {
      final isMorning = report.shiftType == 'morning';
      return PendingShiftReport(
        id: report.id,
        shopAddress: report.shopAddress,
        shiftType: report.shiftType ?? 'morning',
        shiftLabel: isMorning ? 'Утро' : 'Вечер',
        date: todayStr,
        deadline: isMorning ? morningDeadline : eveningDeadline,
        status: 'failed',
        createdAt: report.createdAt,
      );
    }).toList();

    if (_tabController.index != 1) {
      _failedShiftsBadgeCount = _failedShifts.length;
    }

    _pendingShifts.sort((a, b) {
      final shopCompare = a.shopAddress.compareTo(b.shopAddress);
      if (shopCompare != 0) return shopCompare;
      return a.shiftType == 'morning' ? -1 : 1;
    });

    _failedShifts.sort((a, b) {
      final shopCompare = a.shopAddress.compareTo(b.shopAddress);
      if (shopCompare != 0) return shopCompare;
      return a.shiftType == 'morning' ? -1 : 1;
    });
  }

  /// Fallback: локальное вычисление pending (если сервер недоступен)
  void _calculatePendingShiftsFallback() {
    final today = DateTime.now();
    final todayStr = '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';

    final morningDeadline = _shiftSettings?.morningEndTime ?? '13:00';
    final eveningDeadline = _shiftSettings?.eveningEndTime ?? '23:00';

    Logger.info('[Fallback] Вычисление непройденных пересменок. Магазинов: ${_allShops.length}');

    // Собираем пройденные пересменки за сегодня
    final completedShifts = <String>{};
    for (final report in _allReports) {
      final localCreated = report.createdAt.toLocal();
      final reportDate = '${localCreated.year}-${localCreated.month.toString().padLeft(2, '0')}-${localCreated.day.toString().padLeft(2, '0')}';
      if (reportDate == todayStr && (report.status == 'review' || report.status == 'confirmed')) {
        final shiftType = report.shiftType ?? _getShiftType(localCreated);
        final key = '${report.shopAddress.toLowerCase().trim()}_$shiftType';
        completedShifts.add(key);
      }
    }

    // Определяем текущий активный интервал
    final currentShiftType = _getCurrentShiftType();
    final allPending = <PendingShiftReport>[];

    for (final shop in _allShops) {
      final shopKey = shop.address.toLowerCase().trim();

      // Только для текущего активного интервала
      if (currentShiftType == 'morning') {
        final morningKey = '${shopKey}_morning';
        if (!completedShifts.contains(morningKey)) {
          allPending.add(PendingShiftReport(
            id: 'pending_${shop.id}_morning',
            shopAddress: shop.address,
            shiftType: 'morning',
            shiftLabel: 'Утро',
            date: todayStr,
            deadline: morningDeadline,
            status: 'pending',
            createdAt: today,
          ));
        }
      } else if (currentShiftType == 'evening') {
        final eveningKey = '${shopKey}_evening';
        if (!completedShifts.contains(eveningKey)) {
          allPending.add(PendingShiftReport(
            id: 'pending_${shop.id}_evening',
            shopAddress: shop.address,
            shiftType: 'evening',
            shiftLabel: 'Вечер',
            date: todayStr,
            deadline: eveningDeadline,
            status: 'pending',
            createdAt: today,
          ));
        }
      }
    }

    _pendingShifts = allPending;
    _failedShifts = []; // В fallback режиме failed загружаем отдельно

    if (_tabController.index != 1) {
      _failedShiftsBadgeCount = _failedShifts.length;
    }

    _pendingShifts.sort((a, b) => a.shopAddress.compareTo(b.shopAddress));
    Logger.info('[Fallback] Ожидающих: ${_pendingShifts.length}');
  }

  /// Устаревший метод для совместимости (теперь вызывает fallback)
  void _calculatePendingShifts() {
    _calculatePendingShiftsFallback();
  }

  /// Вычислить сводные данные за последние 30 дней
  void _calculateSummaryItems() {
    final now = DateTime.now();
    final thirtyDaysAgo = now.subtract(Duration(days: 30));

    _summaryItems = [];

    // Группируем отчёты по дням и сменам
    Map<String, List<ShiftReport>> grouped = {};

    for (final report in _allReports) {
      if (report.createdAt.isBefore(thirtyDaysAgo)) continue;

      final localCreated = report.createdAt.toLocal();
      final dateKey = '${localCreated.year}-${localCreated.month.toString().padLeft(2, '0')}-${localCreated.day.toString().padLeft(2, '0')}';
      final shiftType = report.shiftType ?? _getShiftType(localCreated);
      final key = '${dateKey}_$shiftType';

      grouped.putIfAbsent(key, () => []).add(report);
    }

    // Создаём строки для каждого дня и смены за 30 дней
    for (int i = 0; i < 30; i++) {
      final date = DateTime(now.year, now.month, now.day).subtract(Duration(days: i));
      final dateKey = '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

      // Утренняя смена
      final morningKey = '${dateKey}_morning';
      final morningReports = grouped[morningKey] ?? [];
      final morningPassed = morningReports.where((r) =>
        r.status != 'pending' && r.status != 'failed' && r.employeeName.isNotEmpty
      ).length;
      _summaryItems.add(ShiftSummaryItem(
        date: date,
        shiftType: 'morning',
        shiftName: 'Утренняя',
        passedCount: morningPassed,
        totalCount: _allShops.length,
        reports: morningReports,
      ));

      // Вечерняя смена
      final eveningKey = '${dateKey}_evening';
      final eveningReports = grouped[eveningKey] ?? [];
      final eveningPassed = eveningReports.where((r) =>
        r.status != 'pending' && r.status != 'failed' && r.employeeName.isNotEmpty
      ).length;
      _summaryItems.add(ShiftSummaryItem(
        date: date,
        shiftType: 'evening',
        shiftName: 'Вечерняя',
        passedCount: eveningPassed,
        totalCount: _allShops.length,
        reports: eveningReports,
      ));
    }

    Logger.info('Сводных записей за 30 дней: ${_summaryItems.length}');
  }

  List<ShiftReport> _applyFilters(List<ShiftReport> reports) {
    if (_selectedShop == null && _selectedEmployee == null && _selectedDate == null) {
      return reports;
    }

    return reports.where((r) {
      if (_selectedShop != null && r.shopAddress != _selectedShop) return false;
      if (_selectedEmployee != null && r.employeeName != _selectedEmployee) return false;
      if (_selectedDate != null) {
        final local = r.createdAt.toLocal();
        if (local.year != _selectedDate!.year ||
            local.month != _selectedDate!.month ||
            local.day != _selectedDate!.day) return false;
      }
      return true;
    }).toList();
  }

  /// Неподтверждённые отчёты (ожидают проверки) - только менее 5 часов
  List<ShiftReport> get _awaitingReports {
    final now = DateTime.now();
    final pending = _allReports.where((r) {
      // Исключаем подтверждённые
      if (r.isConfirmed) return false;
      // Исключаем отчёты с пустым именем сотрудника (созданные scheduler'ом)
      if (r.employeeName.isEmpty) return false;
      // Исключаем pending/failed отчёты (созданные scheduler'ом для ожидания)
      if (r.status == 'pending' || r.status == 'failed') return false;
      // Показываем отчёты со статусом "review" или null (старые отчёты без статуса)
      // status == null или status == 'review' - это реальные отчёты на проверке
      // Показываем только отчёты, которые ожидают менее 5 часов (с момента submittedAt)
      final submissionTime = r.submittedAt ?? r.createdAt;
      final hours = now.difference(submissionTime).inHours;
      return hours < 5;
    }).toList();
    return _applyFilters(pending);
  }

  /// Отчёты, которые ожидают более 5 часов (не подтверждённые)
  List<ShiftReport> get _overdueUnconfirmedReports {
    final now = DateTime.now();
    return _allReports.where((r) {
      if (r.isConfirmed) return false;
      // Исключаем pending/failed отчёты (созданные scheduler'ом)
      if (r.status == 'pending' || r.status == 'failed') return false;
      // Исключаем отчёты с пустым именем сотрудника
      if (r.employeeName.isEmpty) return false;
      // Используем submittedAt для подсчёта времени ожидания
      final submissionTime = r.submittedAt ?? r.createdAt;
      final hours = now.difference(submissionTime).inHours;
      return hours >= 5;
    }).toList();
  }

  /// Подтверждённые отчёты
  List<ShiftReport> get _confirmedReports {
    final confirmed = _allReports.where((r) => r.isConfirmed).toList();
    return _applyFilters(confirmed);
  }

  List<String> get _uniqueEmployees {
    return _allReports.map((r) => r.employeeName).toSet().toList()..sort();
  }

  Future<void> _selectDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate ?? DateTime.now(),
      firstDate: DateTime.now().subtract(Duration(days: 7)),
      lastDate: DateTime.now(),
    );
    if (picked != null && mounted) {
      if (mounted) setState(() {
        _selectedDate = picked;
      });
    }
  }

  /// Custom AppBar
  Widget _buildAppBar(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(8.w, 8.h, 8.w, 4.h),
      child: Row(
        children: [
          Container(
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.08),
              borderRadius: BorderRadius.circular(12.r),
              border: Border.all(color: Colors.white.withOpacity(0.1)),
            ),
            child: IconButton(
              icon: Icon(Icons.arrow_back_ios_new, color: Colors.white.withOpacity(0.8), size: 20),
              onPressed: () => Navigator.pop(context),
            ),
          ),
          SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Отчёты по пересменкам',
                  style: TextStyle(color: Colors.white, fontSize: 18.sp, fontWeight: FontWeight.w600),
                ),
                Text(
                  'Всего отчётов: ${_allReports.length}',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.5),
                    fontSize: 13.sp,
                  ),
                ),
              ],
            ),
          ),
          Container(
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.08),
              borderRadius: BorderRadius.circular(12.r),
              border: Border.all(color: Colors.white.withOpacity(0.1)),
            ),
            child: IconButton(
              icon: Icon(Icons.refresh, color: Colors.white.withOpacity(0.8), size: 20),
              onPressed: _loadData,
              tooltip: 'Обновить',
            ),
          ),
        ],
      ),
    );
  }

  /// Построение двухрядных вкладок (3 сверху, 2 снизу)
  Widget _buildTwoRowTabs() {
    return Container(
      padding: EdgeInsets.fromLTRB(8.w, 0.h, 8.w, 8.h),
      child: Column(
        children: [
          // Первый ряд: 3 вкладки
          Row(
            children: [
              _buildTabButton(0, Icons.schedule, 'Ожидают', _pendingShifts.length, Colors.orange),
              SizedBox(width: 6),
              _buildTabButton(1, Icons.warning_amber, 'Не прошли', _failedShifts.length, Colors.red, badge: _failedShiftsBadgeCount),
              SizedBox(width: 6),
              _buildTabButton(2, Icons.hourglass_empty, 'Проверка', _awaitingReports.length, Colors.blue),
            ],
          ),
          SizedBox(height: 6),
          // Второй ряд: 2 вкладки
          Row(
            children: [
              _buildTabButton(3, Icons.check_circle, 'Подтверждённые', _allReports.where((r) => r.isConfirmed).length, Colors.green),
              SizedBox(width: 6),
              _buildTabButton(4, Icons.cancel, 'Отклонённые', _expiredReports.length + _overdueUnconfirmedReports.length, Colors.grey),
            ],
          ),
          SizedBox(height: 6),
          // Третий ряд: 1 вкладка "Отчёт"
          Row(
            children: [
              _buildTabButton(5, Icons.table_chart, 'Отчёт', _summaryItems.where((s) => s.passedCount > 0).length, Colors.deepPurple),
            ],
          ),
        ],
      ),
    );
  }

  /// Построение одной кнопки-вкладки (компактная версия)
  Widget _buildTabButton(int index, IconData icon, String label, int count, Color accentColor, {int badge = 0}) {
    final isSelected = _tabController.index == index;

    return Expanded(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            _tabController.animateTo(index);
            if (mounted) setState(() {});
          },
          borderRadius: BorderRadius.circular(10.r),
          child: Container(
            padding: EdgeInsets.symmetric(vertical: 6.h, horizontal: 4.w),
            decoration: BoxDecoration(
              gradient: isSelected
                  ? LinearGradient(
                      colors: [accentColor.withOpacity(0.8), accentColor],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    )
                  : null,
              color: isSelected ? null : Colors.white.withOpacity(0.06),
              borderRadius: BorderRadius.circular(10.r),
              border: Border.all(
                color: isSelected ? accentColor : Colors.white.withOpacity(0.1),
                width: isSelected ? 2 : 1,
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  icon,
                  size: 14,
                  color: isSelected ? Colors.white : Colors.white.withOpacity(0.5),
                ),
                SizedBox(width: 4),
                Flexible(
                  child: Text(
                    label,
                    style: TextStyle(
                      fontSize: 10.sp,
                      color: isSelected ? Colors.white : Colors.white.withOpacity(0.5),
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                SizedBox(width: 4),
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 5.w, vertical: 1.h),
                  decoration: BoxDecoration(
                    color: isSelected ? Colors.white.withOpacity(0.3) : accentColor.withOpacity(0.4),
                    borderRadius: BorderRadius.circular(6.r),
                  ),
                  child: Text(
                    '$count',
                    style: TextStyle(
                      fontSize: 10.sp,
                      fontWeight: FontWeight.bold,
                      color: isSelected ? Colors.white : accentColor,
                    ),
                  ),
                ),
                if (badge > 0) ...[
                  SizedBox(width: 2),
                  Container(
                    padding: EdgeInsets.all(4.w),
                    decoration: BoxDecoration(
                      color: Colors.red,
                      shape: BoxShape.circle,
                    ),
                    child: Text(
                      '$badge',
                      style: TextStyle(
                        fontSize: 8.sp,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Секция фильтров
  Widget _buildFiltersSection() {
    return Container(
      margin: EdgeInsets.symmetric(horizontal: 12.w, vertical: 8.h),
      padding: EdgeInsets.all(12.w),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.06),
        borderRadius: BorderRadius.circular(14.r),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
      ),
      child: Column(
        children: [
          // Компактная строка фильтров
          Row(
            children: [
              // Магазин
              Expanded(
                child: FutureBuilder<List<String>>(
                  future: _shopsFuture,
                  builder: (context, snapshot) {
                    if (snapshot.hasData) {
                      return _buildCompactDropdown(
                        icon: Icons.store,
                        value: _selectedShop,
                        hint: 'Магазин',
                        items: snapshot.data!,
                        onChanged: (v) => setState(() => _selectedShop = v),
                      );
                    }
                    return SizedBox();
                  },
                ),
              ),
              SizedBox(width: 8),
              // Дата
              _buildDateButton(),
            ],
          ),
          SizedBox(height: 8),
          // Сотрудник + сброс
          Row(
            children: [
              Expanded(
                child: _buildCompactDropdown(
                  icon: Icons.person,
                  value: _selectedEmployee,
                  hint: 'Сотрудник',
                  items: _uniqueEmployees,
                  onChanged: (v) => setState(() => _selectedEmployee = v),
                ),
              ),
              if (_selectedShop != null || _selectedEmployee != null || _selectedDate != null) ...[
                SizedBox(width: 8),
                _buildResetButton(),
              ],
            ],
          ),
        ],
      ),
    );
  }

  /// Компактный dropdown
  Widget _buildCompactDropdown({
    required IconData icon,
    required String? value,
    required String hint,
    required List<String> items,
    required ValueChanged<String?> onChanged,
  }) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 4.h),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.06),
        borderRadius: BorderRadius.circular(10.r),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          isExpanded: true,
          dropdownColor: AppColors.emeraldDark,
          icon: Icon(Icons.arrow_drop_down, color: AppColors.gold),
          hint: Row(
            children: [
              Icon(icon, size: 18, color: Colors.white.withOpacity(0.5)),
              SizedBox(width: 8),
              Text(hint, style: TextStyle(fontSize: 13.sp, color: Colors.white.withOpacity(0.5))),
            ],
          ),
          selectedItemBuilder: (context) {
            return [
              Row(
                children: [
                  Icon(icon, size: 18, color: AppColors.gold),
                  SizedBox(width: 8),
                  Expanded(child: Text('Все', style: TextStyle(fontSize: 13.sp, color: Colors.white.withOpacity(0.9)))),
                ],
              ),
              ...items.map((item) => Row(
                children: [
                  Icon(icon, size: 18, color: AppColors.gold),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      item,
                      style: TextStyle(fontSize: 13.sp, color: Colors.white.withOpacity(0.9)),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              )),
            ];
          },
          items: [
            DropdownMenuItem<String>(value: null, child: Text('Все $hint', style: TextStyle(color: Colors.white.withOpacity(0.9)))),
            ...items.map((item) => DropdownMenuItem(value: item, child: Text(item, style: TextStyle(color: Colors.white.withOpacity(0.9))))),
          ],
          onChanged: onChanged,
        ),
      ),
    );
  }

  /// Кнопка выбора даты
  Widget _buildDateButton() {
    return InkWell(
      onTap: () => _selectDate(context),
      borderRadius: BorderRadius.circular(10.r),
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 12.h),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.06),
          borderRadius: BorderRadius.circular(10.r),
          border: Border.all(color: Colors.white.withOpacity(0.1)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.calendar_today, size: 18, color: AppColors.gold),
            SizedBox(width: 8),
            Text(
              _selectedDate == null
                  ? 'Дата'
                  : '${_selectedDate!.day}.${_selectedDate!.month}',
              style: TextStyle(fontSize: 13.sp, color: Colors.white.withOpacity(0.9)),
            ),
          ],
        ),
      ),
    );
  }

  /// Кнопка сброса фильтров
  Widget _buildResetButton() {
    return InkWell(
      onTap: () {
        if (mounted) setState(() {
          _selectedShop = null;
          _selectedEmployee = null;
          _selectedDate = null;
        });
      },
      borderRadius: BorderRadius.circular(10.r),
      child: Container(
        padding: EdgeInsets.all(10.w),
        decoration: BoxDecoration(
          color: Colors.red.withOpacity(0.8),
          borderRadius: BorderRadius.circular(10.r),
        ),
        child: Icon(Icons.clear, size: 20, color: Colors.white),
      ),
    );
  }

  /// Красивый пустой стейт
  Widget _buildEmptyState({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
  }) {
    return Center(
      child: Padding(
        padding: EdgeInsets.all(32.w),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: color.withOpacity(0.15),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 40, color: color),
            ),
            SizedBox(height: 20),
            Text(
              title,
              style: TextStyle(
                color: Colors.white.withOpacity(0.9),
                fontSize: 18.sp,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
            SizedBox(height: 8),
            Text(
              subtitle,
              style: TextStyle(
                color: Colors.white.withOpacity(0.5),
                fontSize: 14.sp,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.night,
      body: Container(
        decoration: BoxDecoration(
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
              // Custom AppBar
              _buildAppBar(context),
              // Вкладки
              _buildTwoRowTabs(),
              // Фильтры (только для вкладок с отчётами, не для "Ожидают" и "Не прошли")
              if (_tabController.index >= 2) _buildFiltersSection(),

              // Вкладки с отчётами
              Expanded(
                child: _isLoading
                    ? Center(child: CircularProgressIndicator(color: AppColors.gold))
                    : TabBarView(
                  controller: _tabController,
                  children: [
                    _buildPendingShiftsList(),
                    _buildFailedShiftsList(),
                    _buildReportsList(_awaitingReports, isPending: true),
                    _buildGroupedReportsList(_confirmedReports, isConfirmed: true),
                    _buildGroupedReportsList([..._expiredReports, ..._overdueUnconfirmedReports], isConfirmed: false),
                    _buildSummaryReportsList(),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Виджет для списка непройденных пересменок (ещё не просроченных)
  Widget _buildPendingShiftsList() {
    if (_pendingShifts.isEmpty) {
      return _buildEmptyState(
        icon: Icons.check_circle_outline,
        title: 'Нет ожидающих пересменок',
        subtitle: 'Все пересменки пройдены или просрочены',
        color: Colors.green,
      );
    }

    return ListView.builder(
      padding: EdgeInsets.all(12.w),
      itemCount: _pendingShifts.length,
      itemBuilder: (context, index) {
        final pending = _pendingShifts[index];
        final isMorning = pending.shiftType == 'morning';
        final shiftColor = isMorning ? Colors.orange : Colors.indigo;

        return Container(
          margin: EdgeInsets.only(bottom: 10.h),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.06),
            borderRadius: BorderRadius.circular(14.r),
            border: Border.all(color: Colors.white.withOpacity(0.1)),
          ),
          child: Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(14.r),
            child: InkWell(
              borderRadius: BorderRadius.circular(14.r),
              onTap: () {},
              child: Padding(
                padding: EdgeInsets.all(14.w),
                child: Row(
                  children: [
                    // Иконка смены
                    Container(
                      width: 50,
                      height: 50,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: isMorning
                              ? [Colors.orange.shade300, Colors.orange.shade600]
                              : [Colors.indigo.shade300, Colors.indigo.shade600],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(14.r),
                      ),
                      child: Icon(
                        isMorning ? Icons.wb_sunny : Icons.nights_stay,
                        color: Colors.white,
                        size: 26,
                      ),
                    ),
                    SizedBox(width: 14),
                    // Информация
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            pending.shopAddress,
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 15.sp,
                              color: Colors.white.withOpacity(0.9),
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          SizedBox(height: 6),
                          Row(
                            children: [
                              Container(
                                padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 4.h),
                                decoration: BoxDecoration(
                                  color: shiftColor.withOpacity(0.2),
                                  borderRadius: BorderRadius.circular(8.r),
                                  border: Border.all(color: shiftColor.withOpacity(0.3)),
                                ),
                                child: Text(
                                  pending.shiftLabel,
                                  style: TextStyle(
                                    fontSize: 12.sp,
                                    fontWeight: FontWeight.bold,
                                    color: shiftColor,
                                  ),
                                ),
                              ),
                              SizedBox(width: 8),
                              Icon(Icons.access_time, size: 14, color: Colors.white.withOpacity(0.5)),
                              SizedBox(width: 4),
                              Text(
                                'до ${pending.deadline}',
                                style: TextStyle(
                                  fontSize: 12.sp,
                                  color: Colors.white.withOpacity(0.5),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    // Статус
                    Container(
                      padding: EdgeInsets.all(8.w),
                      decoration: BoxDecoration(
                        color: Colors.orange.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(10.r),
                      ),
                      child: Icon(
                        Icons.schedule,
                        color: Colors.orange,
                        size: 24,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  /// Виджет для списка просроченных (непройденных) пересменок
  Widget _buildFailedShiftsList() {
    if (_failedShifts.isEmpty) {
      return _buildEmptyState(
        icon: Icons.thumb_up,
        title: 'Нет просроченных пересменок',
        subtitle: 'Все пересменки пройдены вовремя',
        color: Colors.green,
      );
    }

    return ListView.builder(
      padding: EdgeInsets.all(12.w),
      itemCount: _failedShifts.length,
      itemBuilder: (context, index) {
        final failed = _failedShifts[index];
        final isMorning = failed.shiftType == 'morning';

        return Container(
          margin: EdgeInsets.only(bottom: 10.h),
          decoration: BoxDecoration(
            color: Colors.red.withOpacity(0.08),
            borderRadius: BorderRadius.circular(14.r),
            border: Border.all(color: Colors.red.withOpacity(0.3)),
          ),
          child: Padding(
            padding: EdgeInsets.all(14.w),
            child: Row(
              children: [
                // Иконка с предупреждением
                Container(
                  width: 50,
                  height: 50,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Colors.red.shade400, Colors.red.shade700],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(14.r),
                  ),
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Icon(
                        isMorning ? Icons.wb_sunny : Icons.nights_stay,
                        color: Colors.white,
                        size: 24,
                      ),
                      Positioned(
                        right: 0.w,
                        bottom: 0.h,
                        child: Container(
                          padding: EdgeInsets.all(2.w),
                          decoration: BoxDecoration(
                            color: AppColors.emeraldDark,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(Icons.error, color: Colors.red, size: 14),
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(width: 14),
                // Информация
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        failed.shopAddress,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15.sp,
                          color: Colors.white.withOpacity(0.9),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      SizedBox(height: 6),
                      Row(
                        children: [
                          Container(
                            padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 3.h),
                            decoration: BoxDecoration(
                              color: isMorning ? Colors.orange.withOpacity(0.2) : Colors.indigo.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(6.r),
                            ),
                            child: Text(
                              failed.shiftLabel,
                              style: TextStyle(
                                fontSize: 11.sp,
                                fontWeight: FontWeight.bold,
                                color: isMorning ? Colors.orange : Colors.indigo.shade300,
                              ),
                            ),
                          ),
                          Spacer(),
                          Container(
                            padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 3.h),
                            decoration: BoxDecoration(
                              color: Colors.red,
                              borderRadius: BorderRadius.circular(6.r),
                            ),
                            child: Text(
                              'ПРОСРОЧЕНО',
                              style: TextStyle(
                                fontSize: 10.sp,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: 6),
                      Row(
                        children: [
                          Icon(Icons.access_time, size: 14, color: Colors.red[400]),
                          SizedBox(width: 4),
                          Text(
                            'Дедлайн: ${failed.deadline}',
                            style: TextStyle(fontSize: 12.sp, color: Colors.red[400]),
                          ),
                          if (_shiftSettings != null) ...[
                            Spacer(),
                            Container(
                              padding: EdgeInsets.symmetric(horizontal: 6.w, vertical: 2.h),
                              decoration: BoxDecoration(
                                color: Colors.deepOrange.withOpacity(0.15),
                                borderRadius: BorderRadius.circular(4.r),
                              ),
                              child: Text(
                                '${_shiftSettings!.missedPenalty.toStringAsFixed(1)} б.',
                                style: TextStyle(
                                  fontSize: 11.sp,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.deepOrange,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// Виджет для списка просроченных (не подтверждённых) отчётов
  Widget _buildExpiredReportsList() {
    // Объединяем просроченные с сервера и отчеты ожидающие более 5 часов
    final allUnconfirmed = [
      ..._expiredReports,
      ..._overdueUnconfirmedReports,
    ];

    // Сортируем по дате создания (новые сначала)
    allUnconfirmed.sort((a, b) => b.createdAt.compareTo(a.createdAt));

    // Убираем дубликаты по ID
    final Map<String, ShiftReport> uniqueReports = {};
    for (final report in allUnconfirmed) {
      uniqueReports[report.id] = report;
    }
    final reports = uniqueReports.values.toList();
    reports.sort((a, b) => b.createdAt.compareTo(a.createdAt));

    if (reports.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.thumb_up, size: 64, color: Colors.white.withOpacity(0.5)),
            SizedBox(height: 16),
            Text(
              'Нет не подтверждённых отчётов',
              style: TextStyle(color: Colors.white.withOpacity(0.9), fontSize: 18.sp),
            ),
            SizedBox(height: 8),
            Text(
              'Все отчёты были проверены вовремя',
              style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 14.sp),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: EdgeInsets.all(16.w),
      itemCount: reports.length,
      itemBuilder: (context, index) {
        final report = reports[index];
        final now = DateTime.now();
        final waitingHours = now.difference(report.createdAt).inHours;
        final isFromExpiredList = report.isExpired || report.expiredAt != null;

        return Container(
          margin: EdgeInsets.only(bottom: 12.h),
          decoration: BoxDecoration(
            color: Colors.red.withOpacity(0.08),
            borderRadius: BorderRadius.circular(14.r),
            border: Border.all(color: Colors.red.withOpacity(0.2)),
          ),
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: isFromExpiredList ? Colors.red : Colors.orange,
              child: Icon(
                isFromExpiredList ? Icons.cancel : Icons.access_time,
                color: Colors.white,
              ),
            ),
            title: Text(
              report.shopAddress,
              style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white.withOpacity(0.9)),
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Сотрудник: ${report.employeeName}', style: TextStyle(color: Colors.white.withOpacity(0.5))),
                Builder(builder: (_) {
                  final lc = report.createdAt.toLocal();
                  return Text(
                    'Сдан: ${lc.day}.${lc.month}.${lc.year} '
                    '${lc.hour}:${lc.minute.toString().padLeft(2, '0')}',
                    style: TextStyle(color: Colors.white.withOpacity(0.5)),
                  );
                }),
                if (isFromExpiredList && report.expiredAt != null)
                  Text(
                    'Просрочен: ${report.expiredAt!.day}.${report.expiredAt!.month}.${report.expiredAt!.year}',
                    style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
                  )
                else
                  Text(
                    'Ожидает: $waitingHours ч. (более 5 часов)',
                    style: TextStyle(color: Colors.orange, fontWeight: FontWeight.bold),
                  ),
                Text('Вопросов: ${report.answers.length}', style: TextStyle(color: Colors.white.withOpacity(0.5))),
              ],
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.visibility, color: Colors.white.withOpacity(0.5)),
                SizedBox(width: 8),
                Icon(Icons.arrow_forward_ios, color: Colors.white.withOpacity(0.5)),
              ],
            ),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => ShiftReportViewPage(
                    report: report,
                    isReadOnly: true, // Только просмотр
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }

  Color _getRatingColor(int rating) {
    if (rating <= 3) return Colors.red;
    if (rating <= 5) return Colors.orange;
    if (rating <= 7) return Colors.amber.shade700;
    return Colors.green;
  }

  Widget _buildReportsList(List<ShiftReport> reports, {required bool isPending}) {
    if (reports.isEmpty) {
      return Center(
        child: Text(
          isPending ? 'Нет отчётов, ожидающих подтверждения' : 'Нет подтверждённых отчётов',
          style: TextStyle(color: Colors.white.withOpacity(0.9), fontSize: 18.sp),
        ),
      );
    }

    return ListView.builder(
      padding: EdgeInsets.all(16.w),
      itemCount: reports.length,
      itemBuilder: (context, index) {
        final report = reports[index];
        final status = report.verificationStatus;

        Widget statusIcon;
        if (status == 'confirmed') {
          statusIcon = Icon(
            Icons.check_circle,
            color: Colors.green,
            size: 24,
          );
        } else if (status == 'not_verified') {
          statusIcon = Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.cancel,
                color: Colors.red,
                size: 24,
              ),
              SizedBox(width: 4),
              Text(
                'не проверено',
                style: TextStyle(
                  color: Colors.red,
                  fontSize: 12.sp,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          );
        } else {
          statusIcon = Icon(
            Icons.hourglass_empty,
            color: Colors.orange,
            size: 24,
          );
        }

        return Container(
          margin: EdgeInsets.only(bottom: 12.h),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.06),
            borderRadius: BorderRadius.circular(14.r),
            border: Border.all(color: Colors.white.withOpacity(0.1)),
          ),
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: report.isConfirmed ? Colors.green : AppColors.emerald,
              child: Icon(
                report.isConfirmed ? Icons.check : Icons.receipt_long,
                color: Colors.white,
              ),
            ),
            title: Text(
              report.shopAddress,
              style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white.withOpacity(0.9)),
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Сотрудник: ${report.employeeName}', style: TextStyle(color: Colors.white.withOpacity(0.5))),
                Builder(builder: (_) {
                  final lc = report.createdAt.toLocal();
                  return Text(
                    '${lc.day}.${lc.month}.${lc.year} '
                    '${lc.hour}:${lc.minute.toString().padLeft(2, '0')}',
                    style: TextStyle(color: Colors.white.withOpacity(0.5)),
                  );
                }),
                Text('Вопросов: ${report.answers.length}', style: TextStyle(color: Colors.white.withOpacity(0.5))),
                if (report.isConfirmed && report.confirmedAt != null) ...[
                  Row(
                    children: [
                      Text(
                        'Подтверждено: ',
                        style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold),
                      ),
                      Flexible(
                        child: Text(
                          '${report.confirmedAt!.day}.${report.confirmedAt!.month}.${report.confirmedAt!.year} '
                          '${report.confirmedAt!.hour}:${report.confirmedAt!.minute.toString().padLeft(2, '0')}',
                          style: TextStyle(color: Colors.green),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  if (report.rating != null)
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text('Оценка: ', style: TextStyle(fontSize: 13.sp, color: Colors.white.withOpacity(0.5))),
                            Container(
                              padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 2.h),
                              decoration: BoxDecoration(
                                color: _getRatingColor(report.rating!),
                                borderRadius: BorderRadius.circular(8.r),
                              ),
                              child: Text(
                                '${report.rating}',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13.sp,
                                ),
                              ),
                            ),
                          ],
                        ),
                        if (report.confirmedByAdmin != null)
                          Text(
                            'Проверил: ${report.confirmedByAdmin}',
                            style: TextStyle(fontSize: 12.sp, color: Colors.white.withOpacity(0.5)),
                            overflow: TextOverflow.ellipsis,
                          ),
                      ],
                    ),
                ],
              ],
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                statusIcon,
                SizedBox(width: 8),
                Icon(Icons.arrow_forward_ios, color: Colors.white.withOpacity(0.5)),
              ],
            ),
            onTap: () async {
              final allReports = await ShiftReport.loadAllReports();

              if (!mounted) return;

              final updatedReport = allReports.firstWhere(
                (r) => r.id == report.id,
                orElse: () => report,
              );

              if (!context.mounted) return;
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => ShiftReportViewPage(
                    report: updatedReport,
                  ),
                ),
              ).then((_) {
                _loadData();
              });
            },
          ),
        );
      },
    );
  }

  // ============================================================
  // ИЕРАРХИЧЕСКАЯ ГРУППИРОВКА ОТЧЁТОВ
  // ============================================================

  /// Названия месяцев в родительном падеже
  static final _monthNamesGenitive = [
    '', 'января', 'февраля', 'марта', 'апреля', 'мая', 'июня',
    'июля', 'августа', 'сентября', 'октября', 'ноября', 'декабря'
  ];

  /// Названия месяцев в именительном падеже
  static final _monthNamesNominative = [
    '', 'Январь', 'Февраль', 'Март', 'Апрель', 'Май', 'Июнь',
    'Июль', 'Август', 'Сентябрь', 'Октябрь', 'Ноябрь', 'Декабрь'
  ];

  /// Получить начало недели (понедельник)
  DateTime _getWeekStart(DateTime date) {
    final weekday = date.weekday; // Пн=1, Вс=7
    return DateTime(date.year, date.month, date.day).subtract(Duration(days: weekday - 1));
  }

  /// Форматировать название дня
  String _formatDayTitle(DateTime day) {
    return '${day.day} ${_monthNamesGenitive[day.month]}';
  }

  /// Группировать отчёты по времени
  List<ReportGroup> _groupReports(List<ShiftReport> reports) {
    if (reports.isEmpty) return [];

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(Duration(days: 1));
    final weekAgo = today.subtract(Duration(days: 7));

    List<ReportGroup> result = [];

    // Группируем по дням (конвертируем UTC в локальное время)
    Map<DateTime, List<ShiftReport>> byDay = {};
    for (final report in reports) {
      final local = report.createdAt.toLocal();
      final day = DateTime(local.year, local.month, local.day);
      byDay.putIfAbsent(day, () => []).add(report);
    }

    // Сортируем дни (новые первые)
    final sortedDays = byDay.keys.toList()..sort((a, b) => b.compareTo(a));

    // Сегодня - по умолчанию развёрнуто
    if (byDay.containsKey(today)) {
      final key = 'today';
      _expandedGroups.putIfAbsent(key, () => true); // По умолчанию развёрнуто
      result.add(ReportGroup(
        type: ReportGroupType.today,
        title: 'Сегодня',
        key: key,
        count: byDay[today]!.length,
        startDate: today,
        children: byDay[today]!,
      ));
    }

    // Вчера
    if (byDay.containsKey(yesterday)) {
      final key = 'yesterday';
      _expandedGroups.putIfAbsent(key, () => false);
      result.add(ReportGroup(
        type: ReportGroupType.yesterday,
        title: 'Вчера (${yesterday.day})',
        key: key,
        count: byDay[yesterday]!.length,
        startDate: yesterday,
        children: byDay[yesterday]!,
      ));
    }

    // Дни 2-6 дней назад (отдельные строки)
    for (final day in sortedDays) {
      if (day == today || day == yesterday) continue;
      if (day.isAfter(weekAgo) || day == weekAgo) {
        final key = 'day_${day.year}_${day.month}_${day.day}';
        _expandedGroups.putIfAbsent(key, () => false);
        result.add(ReportGroup(
          type: ReportGroupType.day,
          title: _formatDayTitle(day),
          key: key,
          count: byDay[day]!.length,
          startDate: day,
          children: byDay[day]!,
        ));
      }
    }

    // Недели и месяцы (7+ дней назад)
    Map<String, Map<String, Map<DateTime, List<ShiftReport>>>> byMonthWeek = {};

    for (final day in sortedDays) {
      if (day == today || day == yesterday) continue;
      if (day.isAfter(weekAgo) || day == weekAgo) continue;

      final monthKey = '${day.year}-${day.month.toString().padLeft(2, '0')}';
      final weekStart = _getWeekStart(day);
      final weekKey = '${weekStart.year}-${weekStart.month.toString().padLeft(2, '0')}-${weekStart.day.toString().padLeft(2, '0')}';

      byMonthWeek.putIfAbsent(monthKey, () => {});
      byMonthWeek[monthKey]!.putIfAbsent(weekKey, () => {});
      byMonthWeek[monthKey]![weekKey]![day] = byDay[day]!;
    }

    final currentMonth = '${now.year}-${now.month.toString().padLeft(2, '0')}';

    // Сортируем месяцы (новые первые)
    final sortedMonths = byMonthWeek.keys.toList()..sort((a, b) => b.compareTo(a));

    for (final monthKey in sortedMonths) {
      final weeks = byMonthWeek[monthKey]!;
      final sortedWeeks = weeks.keys.toList()..sort((a, b) => b.compareTo(a));

      if (monthKey == currentMonth) {
        // Текущий месяц - показываем недели напрямую
        for (final weekKey in sortedWeeks) {
          final weekDays = weeks[weekKey]!;
          final sortedWeekDays = weekDays.keys.toList()..sort((a, b) => b.compareTo(a));

          // Создаём дни внутри недели
          final dayGroups = sortedWeekDays.map((day) {
            final dayKey = 'week_${weekKey}_day_${day.year}_${day.month}_${day.day}';
            _expandedGroups.putIfAbsent(dayKey, () => false);
            return ReportGroup(
              type: ReportGroupType.day,
              title: _formatDayTitle(day),
              key: dayKey,
              count: weekDays[day]!.length,
              startDate: day,
              children: weekDays[day]!,
            );
          }).toList();

          final weekStart = _getWeekStart(sortedWeekDays.last);
          final weekEnd = weekStart.add(Duration(days: 6));
          final totalCount = dayGroups.fold(0, (sum, d) => sum + d.count);

          final wKey = 'week_$weekKey';
          _expandedGroups.putIfAbsent(wKey, () => false);
          result.add(ReportGroup(
            type: ReportGroupType.week,
            title: 'Неделя ${weekStart.day}-${weekEnd.day} ${_monthNamesGenitive[weekStart.month]}',
            key: wKey,
            count: totalCount,
            startDate: weekStart,
            children: dayGroups,
          ));
        }
      } else {
        // Прошлый месяц - группируем всё в месяц
        final parts = monthKey.split('-');
        final monthDate = DateTime(int.parse(parts[0]), int.parse(parts[1]));

        final allWeeks = sortedWeeks.map((weekKey) {
          final weekDays = weeks[weekKey]!;
          final sortedWeekDays = weekDays.keys.toList()..sort((a, b) => b.compareTo(a));

          final dayGroups = sortedWeekDays.map((day) {
            final dayKey = 'month_${monthKey}_week_${weekKey}_day_${day.year}_${day.month}_${day.day}';
            _expandedGroups.putIfAbsent(dayKey, () => false);
            return ReportGroup(
              type: ReportGroupType.day,
              title: _formatDayTitle(day),
              key: dayKey,
              count: weekDays[day]!.length,
              startDate: day,
              children: weekDays[day]!,
            );
          }).toList();

          final weekStart = _getWeekStart(sortedWeekDays.last);
          final weekEnd = weekStart.add(Duration(days: 6));
          final totalCount = dayGroups.fold(0, (sum, d) => sum + d.count);

          final wKey = 'month_${monthKey}_week_$weekKey';
          _expandedGroups.putIfAbsent(wKey, () => false);
          return ReportGroup(
            type: ReportGroupType.week,
            title: 'Неделя ${weekStart.day}-${weekEnd.day}',
            key: wKey,
            count: totalCount,
            startDate: weekStart,
            children: dayGroups,
          );
        }).toList();

        final monthTotalCount = allWeeks.fold(0, (sum, w) => sum + w.count);

        final mKey = 'month_$monthKey';
        _expandedGroups.putIfAbsent(mKey, () => false);
        result.add(ReportGroup(
          type: ReportGroupType.month,
          title: '${_monthNamesNominative[monthDate.month]} ${monthDate.year}',
          key: mKey,
          count: monthTotalCount,
          startDate: monthDate,
          children: allWeeks,
        ));
      }
    }

    return result;
  }

  /// Получить цвет для типа группы
  Color _getGroupColor(ReportGroupType type) {
    switch (type) {
      case ReportGroupType.today:
        return Colors.green;
      case ReportGroupType.yesterday:
        return Colors.blue;
      case ReportGroupType.day:
        return Colors.orange;
      case ReportGroupType.week:
        return Colors.purple;
      case ReportGroupType.month:
        return Colors.indigo;
    }
  }

  /// Получить иконку для типа группы
  IconData _getGroupIcon(ReportGroupType type) {
    switch (type) {
      case ReportGroupType.today:
        return Icons.today;
      case ReportGroupType.yesterday:
        return Icons.history;
      case ReportGroupType.day:
        return Icons.calendar_today;
      case ReportGroupType.week:
        return Icons.date_range;
      case ReportGroupType.month:
        return Icons.calendar_month;
    }
  }

  /// Построить сгруппированный список отчётов
  Widget _buildGroupedReportsList(List<ShiftReport> reports, {required bool isConfirmed}) {
    final groups = _groupReports(reports);

    if (groups.isEmpty) {
      return _buildEmptyState(
        icon: isConfirmed ? Icons.check_circle_outline : Icons.cancel_outlined,
        title: isConfirmed ? 'Нет подтверждённых отчётов' : 'Нет отклонённых отчётов',
        subtitle: isConfirmed
            ? 'Подтверждённые отчёты появятся здесь'
            : 'Отклонённые отчёты появятся здесь',
        color: isConfirmed ? Colors.green : Colors.grey,
      );
    }

    return ListView.builder(
      padding: EdgeInsets.all(12.w),
      itemCount: groups.length,
      itemBuilder: (context, index) => _buildGroupTile(groups[index], 0),
    );
  }

  /// Рекурсивно построить плитку группы
  Widget _buildGroupTile(ReportGroup group, int depth) {
    final isExpanded = _expandedGroups[group.key] ?? false;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Заголовок группы
        _buildGroupHeader(group, depth),

        // Дети (если развёрнуто)
        if (isExpanded)
          ...group.children.map((child) {
            if (child is ReportGroup) {
              return Padding(
                padding: EdgeInsets.only(left: 12.0.w * (depth + 1)),
                child: _buildGroupTile(child, depth + 1),
              );
            } else if (child is ShiftReport) {
              return Padding(
                padding: EdgeInsets.only(left: 12.0.w * (depth + 1)),
                child: _buildReportCard(child),
              );
            }
            return SizedBox();
          }),
      ],
    );
  }

  /// Построить заголовок группы
  Widget _buildGroupHeader(ReportGroup group, int depth) {
    final color = _getGroupColor(group.type);
    final icon = _getGroupIcon(group.type);
    final isExpanded = _expandedGroups[group.key] ?? false;

    return GestureDetector(
      onTap: () {
        if (mounted) setState(() {
          _expandedGroups[group.key] = !isExpanded;
        });
      },
      child: Container(
        margin: EdgeInsets.only(bottom: 8.h),
        padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 10.h),
        decoration: BoxDecoration(
          color: isExpanded ? color.withOpacity(0.15) : Colors.white.withOpacity(0.06),
          borderRadius: BorderRadius.circular(12.r),
          border: Border.all(
            color: isExpanded ? color : Colors.white.withOpacity(0.1),
            width: isExpanded ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            // Стрелка разворачивания
            AnimatedRotation(
              turns: isExpanded ? 0.25 : 0,
              duration: Duration(milliseconds: 200),
              child: Icon(
                Icons.chevron_right,
                color: isExpanded ? color : Colors.white.withOpacity(0.5),
                size: 24,
              ),
            ),
            SizedBox(width: 8),
            // Иконка типа
            Container(
              padding: EdgeInsets.all(6.w),
              decoration: BoxDecoration(
                color: color.withOpacity(0.15),
                borderRadius: BorderRadius.circular(8.r),
              ),
              child: Icon(icon, color: color, size: 18),
            ),
            SizedBox(width: 10),
            // Название
            Expanded(
              child: Text(
                group.title,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14.sp,
                  color: isExpanded ? color : Colors.white.withOpacity(0.9),
                ),
              ),
            ),
            // Счётчик
            Container(
              padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 4.h),
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(12.r),
              ),
              child: Text(
                '${group.count}',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 13.sp,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Построить карточку отчёта
  Widget _buildReportCard(ShiftReport report) {
    final isConfirmed = report.isConfirmed;

    return GestureDetector(
      onTap: () async {
        final allReports = await ShiftReport.loadAllReports();
        if (!mounted) return;

        final updatedReport = allReports.firstWhere(
          (r) => r.id == report.id,
          orElse: () => report,
        );

        if (!context.mounted) return;
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => ShiftReportViewPage(report: updatedReport),
          ),
        ).then((_) => _loadData());
      },
      child: Container(
        margin: EdgeInsets.only(bottom: 8.h),
        padding: EdgeInsets.all(12.w),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.06),
          borderRadius: BorderRadius.circular(14.r),
          border: Border.all(
            color: isConfirmed ? Colors.green.withOpacity(0.3) : Colors.white.withOpacity(0.1),
          ),
        ),
        child: Row(
          children: [
            // Иконка
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: isConfirmed ? Colors.green.withOpacity(0.15) : Colors.white.withOpacity(0.08),
                borderRadius: BorderRadius.circular(10.r),
              ),
              child: Icon(
                isConfirmed ? Icons.check_circle : Icons.receipt_long,
                color: isConfirmed ? Colors.green : Colors.white.withOpacity(0.5),
                size: 22,
              ),
            ),
            SizedBox(width: 12),
            // Информация
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    report.shopAddress,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14.sp,
                      color: Colors.white.withOpacity(0.9),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(Icons.person, size: 14, color: Colors.white.withOpacity(0.5)),
                      SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          report.employeeName,
                          style: TextStyle(fontSize: 12.sp, color: Colors.white.withOpacity(0.5)),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Builder(builder: (_) {
                        final lc = report.createdAt.toLocal();
                        return Text(
                          '${lc.hour}:${lc.minute.toString().padLeft(2, '0')}',
                          style: TextStyle(fontSize: 12.sp, color: Colors.white.withOpacity(0.5)),
                        );
                      }),
                    ],
                  ),
                  if (isConfirmed && report.rating != null) ...[
                    SizedBox(height: 4),
                    Row(
                      children: [
                        Text('Оценка: ', style: TextStyle(fontSize: 12.sp, color: Colors.white.withOpacity(0.5))),
                        Container(
                          padding: EdgeInsets.symmetric(horizontal: 6.w, vertical: 2.h),
                          decoration: BoxDecoration(
                            color: _getRatingColor(report.rating!),
                            borderRadius: BorderRadius.circular(6.r),
                          ),
                          child: Text(
                            '${report.rating}',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 11.sp,
                            ),
                          ),
                        ),
                        if (report.confirmedByAdmin != null) ...[
                          Spacer(),
                          Text(
                            report.confirmedByAdmin!,
                            style: TextStyle(fontSize: 11.sp, color: Colors.white.withOpacity(0.5)),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ],
                    ),
                  ],
                ],
              ),
            ),
            // Стрелка
            Icon(Icons.chevron_right, color: Colors.white.withOpacity(0.5)),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // СВОДНЫЙ ОТЧЁТ ЗА 30 ДНЕЙ
  // ============================================================

  /// Проверить, является ли дата сегодняшней
  bool _isToday(DateTime date) {
    final now = DateTime.now();
    return date.year == now.year && date.month == now.month && date.day == now.day;
  }

  /// Построить список сводных отчётов за 30 дней
  Widget _buildSummaryReportsList() {
    if (_summaryItems.isEmpty) {
      return _buildEmptyState(
        icon: Icons.table_chart_outlined,
        title: 'Нет данных за последние 30 дней',
        subtitle: 'Сводные отчёты появятся здесь',
        color: Colors.deepPurple,
      );
    }

    return ListView.builder(
      padding: EdgeInsets.all(12.w),
      itemCount: _summaryItems.length,
      itemBuilder: (context, index) {
        final item = _summaryItems[index];
        final isToday = _isToday(item.date);
        final allPassed = item.passedCount == item.totalCount && item.totalCount > 0;
        final nonePassed = item.passedCount == 0;
        final isMorning = item.shiftType == 'morning';

        return Container(
          margin: EdgeInsets.only(bottom: 8.h),
          decoration: BoxDecoration(
            color: allPassed
                ? Colors.green.withOpacity(0.08)
                : nonePassed
                    ? Colors.red.withOpacity(0.08)
                    : Colors.white.withOpacity(0.06),
            borderRadius: BorderRadius.circular(14.r),
            border: Border.all(
              color: allPassed
                  ? Colors.green.withOpacity(0.3)
                  : nonePassed
                      ? Colors.red.withOpacity(0.2)
                      : Colors.white.withOpacity(0.1),
              width: isToday ? 2 : 1,
            ),
          ),
          child: Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(14.r),
            child: InkWell(
              borderRadius: BorderRadius.circular(14.r),
              onTap: () => _openSummaryReport(item),
              child: Padding(
                padding: EdgeInsets.all(12.w),
                child: Row(
                  children: [
                    // Иконка смены
                    Container(
                      width: 46,
                      height: 46,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: isMorning
                              ? [Colors.orange.shade300, Colors.orange.shade600]
                              : [Colors.indigo.shade300, Colors.indigo.shade600],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(12.r),
                      ),
                      child: Icon(
                        isMorning ? Icons.wb_sunny : Icons.nights_stay,
                        color: Colors.white,
                        size: 24,
                      ),
                    ),
                    SizedBox(width: 12),
                    // Информация
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item.displayTitle,
                            style: TextStyle(
                              fontWeight: isToday ? FontWeight.bold : FontWeight.w600,
                              fontSize: 14.sp,
                              color: Colors.white.withOpacity(0.9),
                            ),
                          ),
                          SizedBox(height: 4),
                          Text(
                            allPassed
                                ? 'Все магазины прошли'
                                : nonePassed
                                    ? 'Никто не прошёл'
                                    : 'Не прошли: ${item.totalCount - item.passedCount}',
                            style: TextStyle(
                              fontSize: 12.sp,
                              color: allPassed
                                  ? Colors.green
                                  : nonePassed
                                      ? Colors.red
                                      : Colors.orange,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                    // Бейдж с количеством
                    Container(
                      padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 6.h),
                      decoration: BoxDecoration(
                        color: allPassed
                            ? Colors.green
                            : nonePassed
                                ? Colors.red.shade400
                                : Colors.deepPurple,
                        borderRadius: BorderRadius.circular(10.r),
                      ),
                      child: Text(
                        '${item.passedCount}/${item.totalCount}',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 13.sp,
                        ),
                      ),
                    ),
                    SizedBox(width: 8),
                    Icon(Icons.arrow_forward_ios, size: 16, color: Colors.white.withOpacity(0.5)),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  /// Открыть страницу сводного отчёта
  void _openSummaryReport(ShiftSummaryItem item) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ShiftSummaryReportPage(
          date: item.date,
          shiftType: item.shiftType,
          shiftName: item.shiftName,
          reports: item.reports,
          allShops: _allShops,
        ),
      ),
    );
  }
}
