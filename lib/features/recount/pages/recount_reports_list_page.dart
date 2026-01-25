import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../core/utils/logger.dart';
import '../../../core/services/report_notification_service.dart';
import '../models/recount_report_model.dart';
import '../models/recount_answer_model.dart';
import '../models/pending_recount_model.dart';
import '../models/recount_pivot_model.dart';
import '../services/recount_service.dart';
import '../../shops/models/shop_model.dart';
import '../../efficiency/models/points_settings_model.dart';
import '../../efficiency/services/points_settings_service.dart';
import 'recount_report_view_page.dart';
import 'recount_summary_report_page.dart';

/// Модель строки сводного отчёта (дата + смена) - аналог ShiftSummaryItem
class RecountSummaryItem {
  final DateTime date;
  final String shiftType; // 'morning' | 'evening'
  final String shiftName; // 'Утренняя' | 'Вечерняя'
  final int passedCount;  // Сколько магазинов прошли
  final int totalCount;   // Всего магазинов
  final List<RecountReport> reports; // Отчёты за эту смену

  RecountSummaryItem({
    required this.date,
    required this.shiftType,
    required this.shiftName,
    required this.passedCount,
    required this.totalCount,
    required this.reports,
  });

  String get displayTitle {
    const months = ['', 'января', 'февраля', 'марта', 'апреля', 'мая', 'июня',
                   'июля', 'августа', 'сентября', 'октября', 'ноября', 'декабря'];
    return '${date.day} ${months[date.month]}, $shiftName ($passedCount/$totalCount)';
  }
}

/// Тип группы для иерархической группировки отчётов пересчёта
enum RecountReportGroupType { today, yesterday, day, week, month }

/// Группа отчётов для иерархического отображения
class RecountReportGroup {
  final RecountReportGroupType type;
  final String title;
  final String key;
  final int count;
  final DateTime startDate;
  final List<dynamic> children; // List<RecountReport> или List<RecountReportGroup>

  RecountReportGroup({
    required this.type,
    required this.title,
    required this.key,
    required this.count,
    required this.startDate,
    required this.children,
  });
}

/// Страница со списком отчетов по пересчету с вкладками
class RecountReportsListPage extends StatefulWidget {
  const RecountReportsListPage({super.key});

  @override
  State<RecountReportsListPage> createState() => _RecountReportsListPageState();
}

class _RecountReportsListPageState extends State<RecountReportsListPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  String? _selectedShop;
  String? _selectedEmployee;
  DateTime? _selectedDate;
  List<RecountReport> _allReports = [];
  List<Shop> _allShops = [];
  List<PendingRecount> _pendingRecounts = []; // Ожидающие пересчёты (время ещё не истекло)
  List<PendingRecount> _failedRecounts = []; // Просроченные непройденные пересчёты
  List<RecountReport> _expiredReports = [];
  int _failedRecountsBadgeCount = 0; // Badge для вкладки "Не прошли"
  int _summaryBadgeCount = 0; // Badge для вкладки "Отчёт" (непросмотренные)
  List<RecountSummaryItem> _summaryItems = []; // Сводные данные за 30 дней

  // Pivot-таблица для вкладки "Отчёт" (устаревшее, оставлено для совместимости)
  DateTime _pivotDate = DateTime.now();
  RecountPivotTable? _pivotTable;
  bool _isPivotLoading = false;

  // Состояние раскрытия групп для иерархической группировки
  final Map<String, bool> _expandedGroups = {};

  // Настройки времени пересчёта
  RecountPointsSettings? _recountSettings;

  // Названия месяцев в родительном падеже
  static const _monthNamesGenitive = [
    '', 'января', 'февраля', 'марта', 'апреля', 'мая', 'июня',
    'июля', 'августа', 'сентября', 'октября', 'ноября', 'декабря'
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 6, vsync: this);
    _tabController.addListener(_onTabChanged);
    _loadSettings();
    _loadData();
    // Отмечаем все уведомления этого типа как просмотренные
    ReportNotificationService.markAllAsViewed(reportType: ReportType.recount);
  }

  void _onTabChanged() {
    // Когда открываем вкладку "Не прошли" (index 1), обнуляем счётчик
    if (_tabController.index == 1 && _failedRecountsBadgeCount > 0) {
      setState(() {
        _failedRecountsBadgeCount = 0;
      });
    } else if (_tabController.index == 5) {
      // При открытии вкладки "Отчёт" обнуляем счётчик непросмотренных
      if (_summaryBadgeCount > 0) {
        setState(() {
          _summaryBadgeCount = 0;
        });
      }
      // При первом открытии загружаем pivot-таблицу
      if (_pivotTable == null) {
        _loadPivotTable();
      }
    } else {
      // Обновляем UI для подсветки активной вкладки
      setState(() {});
    }
  }

  /// Загрузить pivot-таблицу для выбранной даты
  Future<void> _loadPivotTable() async {
    if (_isPivotLoading) return;

    setState(() {
      _isPivotLoading = true;
    });

    try {
      final table = await RecountService.getPivotTableForDate(_pivotDate);
      setState(() {
        _pivotTable = table;
        _isPivotLoading = false;
      });
    } catch (e) {
      Logger.error('Ошибка загрузки pivot-таблицы', e);
      setState(() {
        _isPivotLoading = false;
      });
    }
  }

  /// Переключить дату pivot-таблицы
  void _changePivotDate(int days) {
    setState(() {
      _pivotDate = _pivotDate.add(Duration(days: days));
      _pivotTable = null;
    });
    _loadPivotTable();
  }

  /// Загрузить настройки пересчёта
  Future<void> _loadSettings() async {
    try {
      final settings = await PointsSettingsService.getRecountPointsSettings();
      setState(() {
        _recountSettings = settings;
      });
    } catch (e) {
      Logger.error('Ошибка загрузки настроек пересчёта', e);
    }
  }

  @override
  void dispose() {
    _tabController.removeListener(_onTabChanged);
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    Logger.info('Загрузка отчетов пересчёта...');

    // Загружаем магазины из API
    try {
      final shops = await Shop.loadShopsFromGoogleSheets();
      _allShops = shops;
      Logger.success('Загружено магазинов: ${shops.length}');
    } catch (e) {
      Logger.error('Ошибка загрузки магазинов', e);
    }

    // Загружаем просроченные отчёты
    try {
      final expiredReports = await RecountService.getExpiredReports();
      _expiredReports = expiredReports;
      Logger.success('Загружено просроченных отчётов: ${expiredReports.length}');
    } catch (e) {
      Logger.error('Ошибка загрузки просроченных отчётов', e);
    }

    // Загружаем отчеты с сервера
    try {
      final serverReports = await RecountService.getReports();
      Logger.success('Загружено отчетов с сервера: ${serverReports.length}');

      _allReports = serverReports;
      _allReports.sort((a, b) => b.completedAt.compareTo(a.completedAt));

      // Загружаем pending и failed пересчёты
      await _loadPendingAndFailedRecounts();
      // Вычисляем сводные данные за 30 дней
      _calculateSummaryItems();

      Logger.success('Всего отчетов: ${_allReports.length}');
      setState(() {});
    } catch (e) {
      Logger.error('Ошибка загрузки отчетов', e);
      // Fallback
      _calculatePendingRecountsFallback();
      _calculateSummaryItems();
      setState(() {});
    }
  }

  /// Определить тип смены по времени отчёта
  String _getShiftType(DateTime dateTime) {
    final hour = dateTime.hour;
    // Утренняя смена: до 14:00
    // Вечерняя смена: после 14:00
    return hour < 14 ? 'morning' : 'evening';
  }

  /// Парсит время из строки формата "HH:MM"
  TimeOfDay _parseTime(String timeStr) {
    final parts = timeStr.split(':');
    return TimeOfDay(
      hour: int.parse(parts[0]),
      minute: parts.length > 1 ? int.parse(parts[1]) : 0,
    );
  }

  /// Вычислить непройденные пересчёты за сегодня (магазин + смена)
  void _calculatePendingRecounts() {
    final today = DateTime.now();
    final todayStr = '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';

    // Используем настройки времени из RecountPointsSettings
    final settings = _recountSettings ?? RecountPointsSettings.defaults();
    final morningStart = _parseTime(settings.morningStartTime);
    final eveningStart = _parseTime(settings.eveningStartTime);

    final currentMinutes = today.hour * 60 + today.minute;
    final morningStartMinutes = morningStart.hour * 60 + morningStart.minute;
    final eveningStartMinutes = eveningStart.hour * 60 + eveningStart.minute;

    // Собираем пройденные пересчёты за сегодня (ключ: магазин_смена)
    final completedRecounts = <String>{};
    for (final report in _allReports) {
      final reportDate = '${report.completedAt.year}-${report.completedAt.month.toString().padLeft(2, '0')}-${report.completedAt.day.toString().padLeft(2, '0')}';
      if (reportDate == todayStr) {
        final shiftType = _getShiftType(report.completedAt);
        final key = '${report.shopAddress.toLowerCase().trim()}_$shiftType';
        completedRecounts.add(key);
      }
    }

    // Формируем список непройденных пересчётов
    _pendingRecounts = [];
    for (final shop in _allShops) {
      final shopKey = shop.address.toLowerCase().trim();

      // Утренняя смена - показываем если текущее время >= morningStartTime
      if (currentMinutes >= morningStartMinutes) {
        final morningKey = '${shopKey}_morning';
        if (!completedRecounts.contains(morningKey)) {
          _pendingRecounts.add(PendingRecount(
            shopAddress: shop.address,
            shiftType: 'morning',
            shiftName: 'Утренняя смена',
          ));
        }
      }

      // Вечерняя смена - показываем если текущее время >= eveningStartTime
      if (currentMinutes >= eveningStartMinutes) {
        final eveningKey = '${shopKey}_evening';
        if (!completedRecounts.contains(eveningKey)) {
          _pendingRecounts.add(PendingRecount(
            shopAddress: shop.address,
            shiftType: 'evening',
            shiftName: 'Вечерняя смена',
          ));
        }
      }
    }

    // Сортируем: сначала по магазину, потом по смене
    _pendingRecounts.sort((a, b) {
      final shopCompare = a.shopAddress.compareTo(b.shopAddress);
      if (shopCompare != 0) return shopCompare;
      // Утренняя смена первой
      return a.shiftType == 'morning' ? -1 : 1;
    });

    Logger.info('Непройденных пересчётов сегодня: ${_pendingRecounts.length}');
  }

  /// Определить текущий активный тип смены (morning/evening) или null если вне интервала
  String? _getCurrentShiftType() {
    if (_recountSettings == null) return null;

    final now = TimeOfDay.now();
    final currentMinutes = now.hour * 60 + now.minute;

    final morningStart = _parseTime(_recountSettings!.morningStartTime);
    final morningEnd = _parseTime(_recountSettings!.morningEndTime);
    final eveningStart = _parseTime(_recountSettings!.eveningStartTime);
    final eveningEnd = _parseTime(_recountSettings!.eveningEndTime);

    final morningStartMinutes = morningStart.hour * 60 + morningStart.minute;
    final morningEndMinutes = morningEnd.hour * 60 + morningEnd.minute;
    final eveningStartMinutes = eveningStart.hour * 60 + eveningStart.minute;
    final eveningEndMinutes = eveningEnd.hour * 60 + eveningEnd.minute;

    // Проверка утреннего интервала (дневной - конец > начала)
    if (_isWithinTimeWindow(currentMinutes, morningStartMinutes, morningEndMinutes)) {
      return 'morning';
    }

    // Проверка вечернего интервала (может быть ночным - конец < начала)
    if (_isWithinTimeWindow(currentMinutes, eveningStartMinutes, eveningEndMinutes)) {
      return 'evening';
    }

    return null;
  }

  /// Проверяет, находится ли время внутри интервала.
  /// Корректно обрабатывает ночные интервалы (когда end < start, например 20:00-06:58)
  bool _isWithinTimeWindow(int currentMinutes, int startMinutes, int endMinutes) {
    // Ночной интервал (конец раньше начала, например 20:00 - 06:58)
    if (endMinutes < startMinutes) {
      // Мы в интервале если: текущее время >= начала ИЛИ текущее время < конца
      return currentMinutes >= startMinutes || currentMinutes < endMinutes;
    }

    // Дневной интервал (например 07:00 - 19:58)
    return currentMinutes >= startMinutes && currentMinutes < endMinutes;
  }

  /// Загрузить pending и failed пересчёты с сервера
  Future<void> _loadPendingAndFailedRecounts() async {
    final today = DateTime.now();
    final todayStr = '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';

    final morningDeadline = _recountSettings?.morningEndTime ?? '13:00';
    final eveningDeadline = _recountSettings?.eveningEndTime ?? '23:00';

    Logger.info('Загрузка pending/failed пересчётов...');

    try {
      final currentShiftType = _getCurrentShiftType();
      Logger.info('Текущий активный интервал: $currentShiftType');

      // Анализируем отчёты за сегодня для определения статусов
      final todayReports = _allReports.where((r) {
        final reportDate = '${r.completedAt.year}-${r.completedAt.month.toString().padLeft(2, '0')}-${r.completedAt.day.toString().padLeft(2, '0')}';
        return reportDate == todayStr;
      }).toList();

      // Собираем пройденные пересчёты за сегодня
      final completedRecounts = <String>{};
      for (final report in todayReports) {
        if (report.status == 'review' || report.status == 'confirmed' || report.isRated) {
          final shiftType = report.shiftType ?? _getShiftType(report.completedAt);
          final key = '${report.shopAddress.toLowerCase().trim()}_$shiftType';
          completedRecounts.add(key);
        }
      }

      // Собираем failed пересчёты
      final failedRecountsList = <PendingRecount>[];
      final pendingRecountsList = <PendingRecount>[];

      for (final shop in _allShops) {
        final shopKey = shop.address.toLowerCase().trim();

        // Проверяем утреннюю смену
        final morningKey = '${shopKey}_morning';
        if (!completedRecounts.contains(morningKey)) {
          final morningEnd = _parseTime(morningDeadline);
          final morningEndMinutes = morningEnd.hour * 60 + morningEnd.minute;
          final currentMinutes = today.hour * 60 + today.minute;

          if (currentMinutes > morningEndMinutes) {
            // Просрочено
            failedRecountsList.add(PendingRecount(
              shopAddress: shop.address,
              shiftType: 'morning',
              shiftName: 'Утренняя смена',
            ));
          } else if (currentShiftType == 'morning') {
            // Ожидает
            pendingRecountsList.add(PendingRecount(
              shopAddress: shop.address,
              shiftType: 'morning',
              shiftName: 'Утренняя смена',
            ));
          }
        }

        // Проверяем вечернюю смену
        final eveningKey = '${shopKey}_evening';
        if (!completedRecounts.contains(eveningKey)) {
          final eveningStart = _parseTime(_recountSettings?.eveningStartTime ?? '20:00');
          final eveningEnd = _parseTime(eveningDeadline);
          final eveningStartMinutes = eveningStart.hour * 60 + eveningStart.minute;
          final eveningEndMinutes = eveningEnd.hour * 60 + eveningEnd.minute;
          final currentMinutes = today.hour * 60 + today.minute;

          // Для ночных интервалов (конец < начала) проверяем иначе
          final isNightInterval = eveningEndMinutes < eveningStartMinutes;
          bool isExpired;
          if (isNightInterval) {
            // Ночной интервал: просрочено когда НЕ внутри окна (время >= конца И время < начала)
            isExpired = currentMinutes >= eveningEndMinutes && currentMinutes < eveningStartMinutes;
          } else {
            // Дневной интервал: просрочено когда время > конца
            isExpired = currentMinutes > eveningEndMinutes;
          }

          if (isExpired) {
            // Просрочено
            failedRecountsList.add(PendingRecount(
              shopAddress: shop.address,
              shiftType: 'evening',
              shiftName: 'Вечерняя смена',
            ));
          } else if (currentShiftType == 'evening') {
            // Ожидает
            pendingRecountsList.add(PendingRecount(
              shopAddress: shop.address,
              shiftType: 'evening',
              shiftName: 'Вечерняя смена',
            ));
          }
        }
      }

      _pendingRecounts = pendingRecountsList;
      _failedRecounts = failedRecountsList;

      // Обновляем счётчик бейджа
      if (_tabController.index != 1) {
        _failedRecountsBadgeCount = _failedRecounts.length;
      }

      // Сортируем
      _pendingRecounts.sort((a, b) {
        final shopCompare = a.shopAddress.compareTo(b.shopAddress);
        if (shopCompare != 0) return shopCompare;
        return a.shiftType == 'morning' ? -1 : 1;
      });

      _failedRecounts.sort((a, b) {
        final shopCompare = a.shopAddress.compareTo(b.shopAddress);
        if (shopCompare != 0) return shopCompare;
        return a.shiftType == 'morning' ? -1 : 1;
      });

      Logger.info('Ожидающих пересчётов: ${_pendingRecounts.length}');
      Logger.info('Просроченных пересчётов: ${_failedRecounts.length}');
    } catch (e) {
      Logger.error('Ошибка загрузки pending/failed', e);
      _calculatePendingRecountsFallback();
    }
  }

  /// Fallback: локальное вычисление pending (старый метод)
  void _calculatePendingRecountsFallback() {
    _calculatePendingRecounts();
    _failedRecounts = [];
    _failedRecountsBadgeCount = 0;
  }

  /// Вычислить сводные данные за последние 30 дней
  void _calculateSummaryItems() {
    final now = DateTime.now();
    final thirtyDaysAgo = now.subtract(const Duration(days: 30));

    _summaryItems = [];

    // Группируем отчёты по дням и сменам
    Map<String, List<RecountReport>> grouped = {};

    for (final report in _allReports) {
      if (report.completedAt.isBefore(thirtyDaysAgo)) continue;

      final dateKey = '${report.completedAt.year}-${report.completedAt.month.toString().padLeft(2, '0')}-${report.completedAt.day.toString().padLeft(2, '0')}';
      final shiftType = report.shiftType ?? _getShiftType(report.completedAt);
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
      _summaryItems.add(RecountSummaryItem(
        date: date,
        shiftType: 'morning',
        shiftName: 'Утренняя',
        passedCount: morningReports.length,
        totalCount: _allShops.length,
        reports: morningReports,
      ));

      // Вечерняя смена
      final eveningKey = '${dateKey}_evening';
      final eveningReports = grouped[eveningKey] ?? [];
      _summaryItems.add(RecountSummaryItem(
        date: date,
        shiftType: 'evening',
        shiftName: 'Вечерняя',
        passedCount: eveningReports.length,
        totalCount: _allShops.length,
        reports: eveningReports,
      ));
    }

    // Считаем непросмотренные (сегодняшние с проблемами - не все прошли)
    // Но если пользователь уже на вкладке "Отчёт", не показываем badge
    if (_tabController.index != 5) {
      final today = DateTime(now.year, now.month, now.day);
      _summaryBadgeCount = _summaryItems.where((item) {
        final itemDay = DateTime(item.date.year, item.date.month, item.date.day);
        // Считаем только сегодняшние смены, где есть данные и не все прошли
        return itemDay == today &&
               item.passedCount > 0 &&
               item.passedCount < item.totalCount;
      }).length;
    }

    Logger.info('Сводных записей за 30 дней: ${_summaryItems.length}, непросмотренных: $_summaryBadgeCount');
  }

  List<RecountReport> _applyFilters(List<RecountReport> reports) {
    var filtered = reports;

    if (_selectedShop != null) {
      filtered = filtered.where((r) => r.shopAddress == _selectedShop).toList();
    }

    if (_selectedEmployee != null) {
      filtered = filtered.where((r) => r.employeeName == _selectedEmployee).toList();
    }

    if (_selectedDate != null) {
      filtered = filtered.where((r) {
        return r.completedAt.year == _selectedDate!.year &&
               r.completedAt.month == _selectedDate!.month &&
               r.completedAt.day == _selectedDate!.day;
      }).toList();
    }

    return filtered;
  }

  /// Не оценённые отчёты (ожидают проверки) - только менее 5 часов
  List<RecountReport> get _awaitingReports {
    final now = DateTime.now();
    final pending = _allReports.where((r) {
      if (r.isRated) return false;
      if (r.isExpired) return false;
      // Показываем только отчёты, которые ожидают менее 5 часов
      final hours = now.difference(r.completedAt).inHours;
      return hours < 5;
    }).toList();
    return _applyFilters(pending);
  }

  /// Отчёты, которые ожидают более 5 часов (не оценённые)
  List<RecountReport> get _overdueUnratedReports {
    final now = DateTime.now();
    return _allReports.where((r) {
      if (r.isRated) return false;
      if (r.isExpired) return true; // Просроченные тоже включаем
      final hours = now.difference(r.completedAt).inHours;
      return hours >= 5;
    }).toList();
  }

  /// Оценённые отчёты
  List<RecountReport> get _ratedReports {
    final rated = _allReports.where((r) => r.isRated).toList();
    return _applyFilters(rated);
  }

  /// Отчёты, сданные НЕ В СРОК (за пределами временных окон из настроек)
  List<RecountReport> get _lateReports {
    final settings = _recountSettings ?? RecountPointsSettings.defaults();

    // Парсим временные окна
    final morningEnd = _parseTime(settings.morningEndTime);
    final eveningEnd = _parseTime(settings.eveningEndTime);

    final morningEndMinutes = morningEnd.hour * 60 + morningEnd.minute;
    final eveningEndMinutes = eveningEnd.hour * 60 + eveningEnd.minute;

    final late = _allReports.where((report) {
      final reportMinutes = report.completedAt.hour * 60 + report.completedAt.minute;
      final shiftType = _getShiftType(report.completedAt);

      if (shiftType == 'morning') {
        // Утренний пересчёт должен быть сдан до morningEndTime
        return reportMinutes > morningEndMinutes;
      } else {
        // Вечерний пересчёт должен быть сдан до eveningEndTime
        return reportMinutes > eveningEndMinutes;
      }
    }).toList();

    return _applyFilters(late);
  }

  List<String> get _uniqueShops {
    return _allReports.map((r) => r.shopAddress).toSet().toList()..sort();
  }

  List<String> get _uniqueEmployees {
    return _allReports.map((r) => r.employeeName).toSet().toList()..sort();
  }

  Future<void> _selectDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate ?? DateTime.now(),
      firstDate: DateTime.now().subtract(const Duration(days: 30)),
      lastDate: DateTime.now(),
    );
    if (picked != null) {
      setState(() {
        _selectedDate = picked;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Отчеты по пересчету'),
        backgroundColor: const Color(0xFF00695C),
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadData,
            tooltip: 'Обновить',
          ),
        ],
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              const Color(0xFF00695C),
              const Color(0xFF004D40).withOpacity(0.9),
            ],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              // Кастомные вкладки 2x2
              _buildCustomTabs(),

              // Фильтры (только для вкладок с отчётами, не для "Ожидают" и "Не прошли")
              if (_tabController.index >= 2)
                _buildFiltersSection(),

              // Вкладки с отчётами
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    // Вкладка 0: "Ожидают" - непройденные пересчёты (время ещё не истекло)
                    _buildPendingRecountsList(),
                    // Вкладка 1: "Не прошли" - просроченные пересчёты
                    _buildFailedRecountsList(),
                    // Вкладка 2: "Проверка" - отчёты ожидают оценки
                    _buildReportsList(_awaitingReports, isPending: true),
                    // Вкладка 3: "Проверено" - оценённые отчёты
                    _buildReportsList(_ratedReports, isPending: false),
                    // Вкладка 4: "Отклонённые" (просроченные + не оценённые вовремя)
                    _buildExpiredReportsList(),
                    // Вкладка 5: "Отчёт" - сводные данные за 30 дней
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

  /// Построение кастомных вкладок 3+2+1 (аналогично пересменкам)
  Widget _buildCustomTabs() {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: Column(
        children: [
          // Первый ряд: 3 вкладки
          Row(
            children: [
              _buildTabButton(0, Icons.schedule_rounded, 'Ожидают', _pendingRecounts.length, Colors.orange),
              const SizedBox(width: 6),
              _buildTabButton(1, Icons.warning_amber_rounded, 'Не прошли', _failedRecounts.length, Colors.red, badge: _failedRecountsBadgeCount),
              const SizedBox(width: 6),
              _buildTabButton(2, Icons.hourglass_empty_rounded, 'Проверка', _awaitingReports.length, Colors.blue),
            ],
          ),
          const SizedBox(height: 6),
          // Второй ряд: 2 вкладки
          Row(
            children: [
              _buildTabButton(3, Icons.check_circle_rounded, 'Проверено', _allReports.where((r) => r.isRated).length, Colors.green),
              const SizedBox(width: 6),
              _buildTabButton(4, Icons.cancel_rounded, 'Отклонённые', _expiredReports.length + _overdueUnratedReports.length, Colors.grey),
            ],
          ),
          const SizedBox(height: 6),
          // Третий ряд: 1 вкладка "Отчёт" (pivot-таблица)
          Row(
            children: [
              _buildTabButton(5, Icons.table_chart_rounded, 'Отчёт', _summaryItems.where((i) => i.passedCount > 0).length, Colors.deepPurple, badge: _summaryBadgeCount),
            ],
          ),
        ],
      ),
    );
  }

  /// Построение одной кнопки-вкладки с опциональным badge
  Widget _buildTabButton(int index, IconData icon, String label, int count, Color accentColor, {int badge = 0}) {
    final isSelected = _tabController.index == index;

    return Expanded(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            _tabController.animateTo(index);
            setState(() {});
          },
          borderRadius: BorderRadius.circular(10),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
            decoration: BoxDecoration(
              gradient: isSelected
                  ? LinearGradient(
                      colors: [accentColor.withOpacity(0.8), accentColor],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    )
                  : null,
              color: isSelected ? null : Colors.white.withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: isSelected ? accentColor : Colors.white30,
                width: isSelected ? 2 : 1,
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  icon,
                  size: 14,
                  color: isSelected ? Colors.white : Colors.white70,
                ),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(
                    label,
                    style: TextStyle(
                      fontSize: 10,
                      color: isSelected ? Colors.white : Colors.white70,
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 4),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                  decoration: BoxDecoration(
                    color: isSelected ? Colors.white.withOpacity(0.3) : accentColor.withOpacity(0.4),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    '$count',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: isSelected ? Colors.white : accentColor,
                    ),
                  ),
                ),
                if (badge > 0) ...[
                  const SizedBox(width: 2),
                  Container(
                    padding: const EdgeInsets.all(4),
                    decoration: const BoxDecoration(
                      color: Colors.red,
                      shape: BoxShape.circle,
                    ),
                    child: Text(
                      '$badge',
                      style: const TextStyle(
                        fontSize: 8,
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

  /// Построение секции фильтров
  Widget _buildFiltersSection() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.95),
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          // Магазин
          DropdownButtonFormField<String>(
            value: _selectedShop,
            isExpanded: true,
            decoration: InputDecoration(
              labelText: 'Магазин',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            ),
            items: [
              const DropdownMenuItem<String>(
                value: null,
                child: Text('Все магазины'),
              ),
              ..._uniqueShops.map((shop) => DropdownMenuItem<String>(
                value: shop,
                child: Text(shop, overflow: TextOverflow.ellipsis),
              )),
            ],
            onChanged: (value) {
              setState(() {
                _selectedShop = value;
              });
            },
          ),
          const SizedBox(height: 10),
          // Сотрудник и Дата в одном ряду
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  value: _selectedEmployee,
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: 'Сотрудник',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                  items: [
                    const DropdownMenuItem<String>(
                      value: null,
                      child: Text('Все'),
                    ),
                    ..._uniqueEmployees.map((employee) => DropdownMenuItem<String>(
                      value: employee,
                      child: Text(employee, overflow: TextOverflow.ellipsis),
                    )),
                  ],
                  onChanged: (value) {
                    setState(() {
                      _selectedEmployee = value;
                    });
                  },
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: InkWell(
                  onTap: () => _selectDate(context),
                  borderRadius: BorderRadius.circular(10),
                  child: InputDecorator(
                    decoration: InputDecoration(
                      labelText: 'Дата',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      suffixIcon: const Icon(Icons.calendar_today, size: 18),
                    ),
                    child: Text(
                      _selectedDate != null
                          ? '${_selectedDate!.day}.${_selectedDate!.month}'
                          : 'Все',
                      style: const TextStyle(fontSize: 14),
                    ),
                  ),
                ),
              ),
            ],
          ),
          // Сброс фильтров
          if (_selectedShop != null || _selectedEmployee != null || _selectedDate != null)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: OutlinedButton.icon(
                onPressed: () {
                  setState(() {
                    _selectedShop = null;
                    _selectedEmployee = null;
                    _selectedDate = null;
                  });
                },
                icon: const Icon(Icons.clear, size: 18),
                label: const Text('Сбросить фильтры'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.grey[700],
                  side: BorderSide(color: Colors.grey[400]!),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// Виджет пустого состояния
  Widget _buildEmptyState({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
  }) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: color.withOpacity(0.2),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Icon(icon, size: 40, color: color),
          ),
          const SizedBox(height: 16),
          Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            subtitle,
            style: TextStyle(
              color: Colors.white.withOpacity(0.7),
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }

  /// Виджет для списка непройденных пересчётов
  Widget _buildPendingRecountsList() {
    if (_pendingRecounts.isEmpty) {
      return _buildEmptyState(
        icon: Icons.check_circle_outline,
        title: 'Все пересчёты пройдены!',
        subtitle: 'Нет непройденных пересчётов на данный момент',
        color: Colors.green,
      );
    }

    final today = DateTime.now();
    final todayStr = '${today.day}.${today.month}.${today.year}';

    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: _pendingRecounts.length,
      itemBuilder: (context, index) {
        final pending = _pendingRecounts[index];
        final isMorning = pending.shiftType == 'morning';

        return Container(
          margin: const EdgeInsets.only(bottom: 10),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: isMorning
                  ? [Colors.orange.shade50, Colors.amber.shade50]
                  : [Colors.deepPurple.shade50, Colors.purple.shade50],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isMorning ? Colors.orange.withOpacity(0.4) : Colors.purple.withOpacity(0.4),
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: (isMorning ? Colors.orange : Colors.purple).withOpacity(0.15),
                blurRadius: 8,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                // Иконка смены
                Container(
                  width: 50,
                  height: 50,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: isMorning
                          ? [Colors.orange.shade400, Colors.amber.shade600]
                          : [Colors.deepPurple.shade400, Colors.purple.shade600],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: [
                      BoxShadow(
                        color: (isMorning ? Colors.orange : Colors.purple).withOpacity(0.4),
                        blurRadius: 6,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Icon(
                    isMorning ? Icons.wb_sunny_rounded : Icons.nights_stay_rounded,
                    color: Colors.white,
                    size: 26,
                  ),
                ),
                const SizedBox(width: 14),
                // Информация
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        pending.shopAddress,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                          color: Colors.black87,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Icon(
                            Icons.calendar_today,
                            size: 14,
                            color: Colors.grey.shade600,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            todayStr,
                            style: TextStyle(
                              color: Colors.grey.shade700,
                              fontSize: 13,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: isMorning ? Colors.blue.withOpacity(0.15) : Colors.purple.withOpacity(0.15),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: isMorning ? Colors.blue.withOpacity(0.3) : Colors.purple.withOpacity(0.3),
                              ),
                            ),
                            child: Text(
                              pending.shiftName,
                              style: TextStyle(
                                color: isMorning ? Colors.blue.shade700 : Colors.purple.shade700,
                                fontWeight: FontWeight.w600,
                                fontSize: 11,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.orange.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.warning_amber_rounded, size: 14, color: Colors.orange.shade700),
                            const SizedBox(width: 4),
                            Text(
                              'Пересчёт не проведён',
                              style: TextStyle(
                                color: Colors.orange.shade700,
                                fontWeight: FontWeight.w600,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                // Индикатор
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: Colors.orange.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    Icons.schedule_rounded,
                    color: Colors.orange.shade700,
                    size: 22,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// Виджет для списка просроченных (непройденных) пересчётов
  Widget _buildFailedRecountsList() {
    if (_failedRecounts.isEmpty) {
      return _buildEmptyState(
        icon: Icons.thumb_up_rounded,
        title: 'Нет просроченных пересчётов',
        subtitle: 'Все пересчёты пройдены вовремя',
        color: Colors.green,
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: _failedRecounts.length,
      itemBuilder: (context, index) {
        final failed = _failedRecounts[index];
        final isMorning = failed.shiftType == 'morning';

        // Получаем дедлайн из настроек
        final deadline = isMorning
            ? (_recountSettings?.morningEndTime ?? '13:00')
            : (_recountSettings?.eveningEndTime ?? '23:00');

        return Container(
          margin: const EdgeInsets.only(bottom: 10),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [Colors.red.shade50, Colors.white],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.red.shade200),
            boxShadow: [
              BoxShadow(
                color: Colors.red.withOpacity(0.15),
                blurRadius: 8,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.all(14),
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
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.red.withOpacity(0.3),
                        blurRadius: 6,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Icon(
                        isMorning ? Icons.wb_sunny_rounded : Icons.nights_stay_rounded,
                        color: Colors.white,
                        size: 24,
                      ),
                      Positioned(
                        right: 0,
                        bottom: 0,
                        child: Container(
                          padding: const EdgeInsets.all(2),
                          decoration: const BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.error, color: Colors.red, size: 14),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 14),
                // Информация
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        failed.shopAddress,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: isMorning ? Colors.orange.withOpacity(0.2) : Colors.indigo.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              failed.shiftName,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: isMorning ? Colors.orange.shade800 : Colors.indigo.shade800,
                              ),
                            ),
                          ),
                          const Spacer(),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: Colors.red,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Text(
                              'ПРОСРОЧЕНО',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Icon(Icons.access_time, size: 14, color: Colors.red[400]),
                          const SizedBox(width: 4),
                          Text(
                            'Дедлайн: $deadline',
                            style: TextStyle(fontSize: 12, color: Colors.red[600]),
                          ),
                          if (_recountSettings != null) ...[
                            const Spacer(),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.deepOrange.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                '${_recountSettings!.missedPenalty.toStringAsFixed(1)} б.',
                                style: const TextStyle(
                                  fontSize: 11,
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

  /// Виджет для списка просроченных (не оценённых) отчётов
  Widget _buildExpiredReportsList() {
    // Объединяем просроченные с сервера и отчеты ожидающие более 5 часов
    final allUnrated = [
      ..._expiredReports,
      ..._overdueUnratedReports,
    ];

    // Сортируем по дате (новые сначала)
    allUnrated.sort((a, b) => b.completedAt.compareTo(a.completedAt));

    // Убираем дубликаты по ID
    final Map<String, RecountReport> uniqueReports = {};
    for (final report in allUnrated) {
      uniqueReports[report.id] = report;
    }
    final reports = uniqueReports.values.toList();
    reports.sort((a, b) => b.completedAt.compareTo(a.completedAt));

    // Используем иерархическую группировку
    final groups = _groupRecountReports(reports, 'expired');
    return _buildGroupedExpiredList(groups);
  }

  /// Построить группированный список просроченных отчётов
  Widget _buildGroupedExpiredList(List<RecountReportGroup> groups) {
    if (groups.isEmpty) {
      return _buildEmptyState(
        icon: Icons.thumb_up_rounded,
        title: 'Нет не оценённых отчётов',
        subtitle: 'Все отчёты были оценены вовремя',
        color: Colors.green,
      );
    }

    return RefreshIndicator(
      onRefresh: _loadData,
      child: ListView.builder(
        padding: const EdgeInsets.all(8),
        itemCount: groups.length,
        itemBuilder: (context, index) {
          return _buildExpiredGroupTile(groups[index], 0);
        },
      ),
    );
  }

  /// Плитка группы просроченных отчётов с дочерними элементами
  Widget _buildExpiredGroupTile(RecountReportGroup group, int depth) {
    final isExpanded = _expandedGroups[group.key] ?? false;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildGroupHeader(group, depth),
        if (isExpanded)
          ...group.children.map((child) {
            if (child is RecountReportGroup) {
              return _buildExpiredGroupTile(child, depth + 1);
            } else if (child is RecountReport) {
              return Padding(
                padding: EdgeInsets.only(left: 12.0 * (depth + 1)),
                child: _buildExpiredReportCard(child),
              );
            }
            return const SizedBox.shrink();
          }),
      ],
    );
  }

  /// Карточка просроченного отчёта
  Widget _buildExpiredReportCard(RecountReport report) {
    final now = DateTime.now();
    final waitingHours = now.difference(report.completedAt).inHours;
    final isFromExpiredList = report.isExpired || report.expiredAt != null;
    final statusColor = isFromExpiredList ? Colors.red : Colors.orange;

    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => RecountReportViewPage(
              report: report,
              isReadOnly: true,
              onReportUpdated: () {
                _loadData();
              },
            ),
          ),
        );
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 10, right: 8),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: isFromExpiredList
                ? [Colors.red.shade50, Colors.pink.shade50]
                : [Colors.orange.shade50, Colors.amber.shade50],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: statusColor.withOpacity(0.4),
            width: 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: statusColor.withOpacity(0.15),
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Заголовок с иконкой
              Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: isFromExpiredList
                            ? [Colors.red.shade400, Colors.red.shade600]
                            : [Colors.orange.shade400, Colors.orange.shade600],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: statusColor.withOpacity(0.4),
                          blurRadius: 6,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Icon(
                      isFromExpiredList ? Icons.cancel_rounded : Icons.access_time_rounded,
                      color: Colors.white,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          report.shopAddress,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                            color: Colors.black87,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          report.employeeName,
                          style: TextStyle(
                            color: Colors.grey.shade600,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    Icons.arrow_forward_ios_rounded,
                    color: Colors.grey.shade400,
                    size: 18,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              // Информация о дате и времени
              Row(
                children: [
                  _buildInfoChip(
                    Icons.calendar_today_rounded,
                    '${report.completedAt.day}.${report.completedAt.month}.${report.completedAt.year}',
                    Colors.blue,
                  ),
                  const SizedBox(width: 8),
                  _buildInfoChip(
                    Icons.access_time_rounded,
                    '${report.completedAt.hour.toString().padLeft(2, '0')}:${report.completedAt.minute.toString().padLeft(2, '0')}',
                    Colors.indigo,
                  ),
                  const SizedBox(width: 8),
                  _buildInfoChip(
                    Icons.timer_outlined,
                    report.formattedDuration,
                    Colors.teal,
                  ),
                ],
              ),
              const SizedBox(height: 10),
              // Статус просрочки
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: statusColor.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: statusColor.withOpacity(0.3)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      isFromExpiredList ? Icons.error_rounded : Icons.schedule_rounded,
                      size: 16,
                      color: isFromExpiredList ? Colors.red.shade700 : Colors.orange.shade700,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      isFromExpiredList && report.expiredAt != null
                          ? 'Просрочен: ${report.expiredAt!.day}.${report.expiredAt!.month}.${report.expiredAt!.year}'
                          : 'Ожидает: $waitingHours ч. (более 5 часов)',
                      style: TextStyle(
                        color: isFromExpiredList ? Colors.red.shade700 : Colors.orange.shade700,
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Color _getRatingColor(int rating) {
    if (rating <= 3) return Colors.red;
    if (rating <= 5) return Colors.orange;
    if (rating <= 7) return Colors.amber.shade700;
    return Colors.green;
  }

  /// Получить начало недели для указанной даты
  DateTime _getWeekStart(DateTime date) {
    final weekday = date.weekday;
    return DateTime(date.year, date.month, date.day).subtract(Duration(days: weekday - 1));
  }

  /// Форматировать название дня
  String _formatDayTitle(DateTime day) {
    return '${day.day} ${_monthNamesGenitive[day.month]}';
  }

  /// Получить цвет для типа группы
  Color _getGroupColor(RecountReportGroupType type) {
    switch (type) {
      case RecountReportGroupType.today:
        return Colors.green;
      case RecountReportGroupType.yesterday:
        return Colors.blue;
      case RecountReportGroupType.day:
        return Colors.orange;
      case RecountReportGroupType.week:
        return Colors.purple;
      case RecountReportGroupType.month:
        return Colors.indigo;
    }
  }

  /// Получить иконку для типа группы
  IconData _getGroupIcon(RecountReportGroupType type) {
    switch (type) {
      case RecountReportGroupType.today:
        return Icons.today;
      case RecountReportGroupType.yesterday:
        return Icons.history;
      case RecountReportGroupType.day:
        return Icons.calendar_today;
      case RecountReportGroupType.week:
        return Icons.date_range;
      case RecountReportGroupType.month:
        return Icons.calendar_month;
    }
  }

  /// Группировка отчётов по дате для иерархического отображения
  List<RecountReportGroup> _groupRecountReports(List<RecountReport> reports, String prefix) {
    if (reports.isEmpty) return [];

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final weekAgo = today.subtract(const Duration(days: 7));

    List<RecountReportGroup> result = [];

    // Группируем по дням
    Map<DateTime, List<RecountReport>> byDay = {};
    for (final report in reports) {
      final day = DateTime(report.completedAt.year, report.completedAt.month, report.completedAt.day);
      byDay.putIfAbsent(day, () => []).add(report);
    }

    final sortedDays = byDay.keys.toList()..sort((a, b) => b.compareTo(a));

    // Сегодня (раскрыто по умолчанию)
    if (byDay.containsKey(today)) {
      final key = '${prefix}_today';
      _expandedGroups.putIfAbsent(key, () => true);
      result.add(RecountReportGroup(
        type: RecountReportGroupType.today,
        title: 'Сегодня',
        key: key,
        count: byDay[today]!.length,
        startDate: today,
        children: byDay[today]!,
      ));
    }

    // Вчера (свёрнуто)
    if (byDay.containsKey(yesterday)) {
      final key = '${prefix}_yesterday';
      _expandedGroups.putIfAbsent(key, () => false);
      result.add(RecountReportGroup(
        type: RecountReportGroupType.yesterday,
        title: 'Вчера',
        key: key,
        count: byDay[yesterday]!.length,
        startDate: yesterday,
        children: byDay[yesterday]!,
      ));
    }

    // Дни 2-6 дней назад (отдельные группы)
    for (final day in sortedDays) {
      if (day == today || day == yesterday) continue;
      if (day.isAfter(weekAgo) || day.isAtSameMomentAs(weekAgo)) {
        final key = '${prefix}_day_${day.toIso8601String()}';
        _expandedGroups.putIfAbsent(key, () => false);
        result.add(RecountReportGroup(
          type: RecountReportGroupType.day,
          title: _formatDayTitle(day),
          key: key,
          count: byDay[day]!.length,
          startDate: day,
          children: byDay[day]!,
        ));
      }
    }

    // Группируем старые отчёты по неделям
    Map<DateTime, List<RecountReport>> byWeek = {};
    for (final day in sortedDays) {
      if (day.isBefore(weekAgo)) {
        final weekStart = _getWeekStart(day);
        byWeek.putIfAbsent(weekStart, () => []).addAll(byDay[day]!);
      }
    }

    final sortedWeeks = byWeek.keys.toList()..sort((a, b) => b.compareTo(a));
    final monthAgo = today.subtract(const Duration(days: 30));

    for (final weekStart in sortedWeeks) {
      if (weekStart.isAfter(monthAgo) || weekStart.isAtSameMomentAs(monthAgo)) {
        final weekEnd = weekStart.add(const Duration(days: 6));
        final key = '${prefix}_week_${weekStart.toIso8601String()}';
        _expandedGroups.putIfAbsent(key, () => false);
        result.add(RecountReportGroup(
          type: RecountReportGroupType.week,
          title: '${_formatDayTitle(weekStart)} - ${_formatDayTitle(weekEnd)}',
          key: key,
          count: byWeek[weekStart]!.length,
          startDate: weekStart,
          children: byWeek[weekStart]!,
        ));
      }
    }

    // Группируем очень старые отчёты по месяцам
    Map<String, List<RecountReport>> byMonth = {};
    for (final weekStart in sortedWeeks) {
      if (weekStart.isBefore(monthAgo)) {
        final monthKey = '${weekStart.year}-${weekStart.month}';
        byMonth.putIfAbsent(monthKey, () => []).addAll(byWeek[weekStart]!);
      }
    }

    final sortedMonths = byMonth.keys.toList()..sort((a, b) => b.compareTo(a));
    for (final monthKey in sortedMonths) {
      final parts = monthKey.split('-');
      final year = int.parse(parts[0]);
      final month = int.parse(parts[1]);
      final monthStart = DateTime(year, month, 1);
      final key = '${prefix}_month_$monthKey';
      _expandedGroups.putIfAbsent(key, () => false);
      result.add(RecountReportGroup(
        type: RecountReportGroupType.month,
        title: '${_monthNamesGenitive[month].replaceFirst(_monthNamesGenitive[month][0], _monthNamesGenitive[month][0].toUpperCase())} $year',
        key: key,
        count: byMonth[monthKey]!.length,
        startDate: monthStart,
        children: byMonth[monthKey]!,
      ));
    }

    return result;
  }

  /// Заголовок группы
  Widget _buildGroupHeader(RecountReportGroup group, int depth) {
    final color = _getGroupColor(group.type);
    final icon = _getGroupIcon(group.type);
    final isExpanded = _expandedGroups[group.key] ?? false;

    return GestureDetector(
      onTap: () {
        setState(() {
          _expandedGroups[group.key] = !isExpanded;
        });
      },
      child: Container(
        margin: EdgeInsets.only(
          left: 12.0 * depth,
          right: 8,
          top: 4,
          bottom: 4,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: color.withOpacity(0.15),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withOpacity(0.4)),
        ),
        child: Row(
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                group.title,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: color,
                  fontSize: 14,
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: color.withOpacity(0.2),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                '${group.count}',
                style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              isExpanded ? Icons.expand_less : Icons.expand_more,
              color: color,
            ),
          ],
        ),
      ),
    );
  }

  /// Плитка группы с дочерними элементами
  Widget _buildRecountGroupTile(RecountReportGroup group, int depth) {
    final isExpanded = _expandedGroups[group.key] ?? false;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildGroupHeader(group, depth),
        if (isExpanded)
          ...group.children.map((child) {
            if (child is RecountReportGroup) {
              return _buildRecountGroupTile(child, depth + 1);
            } else if (child is RecountReport) {
              return Padding(
                padding: EdgeInsets.only(left: 12.0 * (depth + 1)),
                child: _buildRecountReportCard(child),
              );
            }
            return const SizedBox.shrink();
          }),
      ],
    );
  }

  /// Карточка отчёта пересчёта
  Widget _buildRecountReportCard(RecountReport report) {
    final statusColor = report.isRated ? Colors.green : Colors.amber;
    final statusIcon = report.isRated ? Icons.check_circle_rounded : Icons.hourglass_empty_rounded;
    final statusText = report.isRated ? 'Оценён' : 'Ожидает оценки';

    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => RecountReportViewPage(
              report: report,
              onReportUpdated: () {
                _loadData();
              },
            ),
          ),
        );
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 10, right: 8),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: report.isRated
                ? [Colors.green.shade50, Colors.teal.shade50]
                : [Colors.amber.shade50, Colors.orange.shade50],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: statusColor.withOpacity(0.4),
            width: 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: statusColor.withOpacity(0.15),
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Заголовок с иконкой и статусом
              Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: report.isRated
                            ? [Colors.green.shade400, Colors.teal.shade600]
                            : [Colors.amber.shade400, Colors.orange.shade600],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: statusColor.withOpacity(0.4),
                          blurRadius: 6,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Icon(statusIcon, color: Colors.white, size: 24),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          report.shopAddress,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                            color: Colors.black87,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          report.employeeName,
                          style: TextStyle(
                            color: Colors.grey.shade600,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    Icons.arrow_forward_ios_rounded,
                    color: Colors.grey.shade400,
                    size: 18,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              // Информация о дате и времени
              Row(
                children: [
                  _buildInfoChip(
                    Icons.calendar_today_rounded,
                    '${report.completedAt.day}.${report.completedAt.month}.${report.completedAt.year}',
                    Colors.blue,
                  ),
                  const SizedBox(width: 8),
                  _buildInfoChip(
                    Icons.access_time_rounded,
                    '${report.completedAt.hour.toString().padLeft(2, '0')}:${report.completedAt.minute.toString().padLeft(2, '0')}',
                    Colors.indigo,
                  ),
                  const SizedBox(width: 8),
                  _buildInfoChip(
                    Icons.timer_outlined,
                    report.formattedDuration,
                    Colors.teal,
                  ),
                ],
              ),
              // Оценка (если есть)
              if (report.isRated) ...[
                const SizedBox(height: 10),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            _getRatingColor(report.adminRating!).withOpacity(0.8),
                            _getRatingColor(report.adminRating!),
                          ],
                        ),
                        borderRadius: BorderRadius.circular(10),
                        boxShadow: [
                          BoxShadow(
                            color: _getRatingColor(report.adminRating!).withOpacity(0.3),
                            blurRadius: 4,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.star_rounded, color: Colors.white, size: 18),
                          const SizedBox(width: 4),
                          Text(
                            '${report.adminRating}/10',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (report.adminName != null) ...[
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Проверил: ${report.adminName}',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade600,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ],
                ),
              ] else ...[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: Colors.amber.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.amber.withOpacity(0.3)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.hourglass_empty_rounded, size: 14, color: Colors.amber.shade700),
                      const SizedBox(width: 4),
                      Text(
                        statusText,
                        style: TextStyle(
                          color: Colors.amber.shade700,
                          fontWeight: FontWeight.w600,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// Вспомогательный чип для отображения информации
  Widget _buildInfoChip(IconData icon, String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color.withOpacity(0.8)),
          const SizedBox(width: 4),
          Text(
            text,
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  /// Построить группированный список
  Widget _buildGroupedList(List<RecountReportGroup> groups, String emptyMessage) {
    if (groups.isEmpty) {
      return _buildEmptyState(
        icon: Icons.inbox_rounded,
        title: emptyMessage,
        subtitle: 'Отчёты появятся здесь после загрузки',
        color: Colors.grey,
      );
    }

    return RefreshIndicator(
      onRefresh: _loadData,
      child: ListView.builder(
        padding: const EdgeInsets.all(8),
        itemCount: groups.length,
        itemBuilder: (context, index) {
          return _buildRecountGroupTile(groups[index], 0);
        },
      ),
    );
  }

  Widget _buildReportsList(List<RecountReport> reports, {required bool isPending}) {
    final emptyMessage = isPending ? 'Нет отчётов, ожидающих оценки' : 'Нет оценённых отчётов';
    final prefix = isPending ? 'awaiting' : 'rated';
    final groups = _groupRecountReports(reports, prefix);
    return _buildGroupedList(groups, emptyMessage);
  }

  /// Виджет для списка отчётов, сданных НЕ В СРОК
  Widget _buildLateReportsList() {
    final reports = _lateReports;
    final groups = _groupRecountReports(reports, 'late');

    if (groups.isEmpty) {
      return _buildEmptyState(
        icon: Icons.thumb_up_rounded,
        title: 'Все пересчёты в срок!',
        subtitle: 'Нет отчётов, сданных позже дедлайна',
        color: Colors.green,
      );
    }

    return RefreshIndicator(
      onRefresh: _loadData,
      child: ListView.builder(
        padding: const EdgeInsets.all(8),
        itemCount: groups.length,
        itemBuilder: (context, index) {
          return _buildLateGroupTile(groups[index], 0);
        },
      ),
    );
  }

  /// Плитка группы отчётов "Не в срок" с дочерними элементами
  Widget _buildLateGroupTile(RecountReportGroup group, int depth) {
    final isExpanded = _expandedGroups[group.key] ?? false;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildGroupHeader(group, depth),
        if (isExpanded)
          ...group.children.map((child) {
            if (child is RecountReportGroup) {
              return _buildLateGroupTile(child, depth + 1);
            } else if (child is RecountReport) {
              return Padding(
                padding: EdgeInsets.only(left: 12.0 * (depth + 1)),
                child: _buildLateReportCard(child),
              );
            }
            return const SizedBox.shrink();
          }),
      ],
    );
  }

  /// Карточка отчёта, сданного НЕ В СРОК
  Widget _buildLateReportCard(RecountReport report) {
    final settings = _recountSettings ?? RecountPointsSettings.defaults();
    final shiftType = _getShiftType(report.completedAt);
    final isMorning = shiftType == 'morning';

    // Определяем дедлайн для этой смены
    final deadline = isMorning ? settings.morningEndTime : settings.eveningEndTime;
    final shiftName = isMorning ? 'Утренняя' : 'Вечерняя';

    // Вычисляем опоздание
    final deadlineParts = deadline.split(':');
    final deadlineMinutes = int.parse(deadlineParts[0]) * 60 + int.parse(deadlineParts[1]);
    final reportMinutes = report.completedAt.hour * 60 + report.completedAt.minute;
    final lateMinutes = reportMinutes - deadlineMinutes;
    final lateHours = lateMinutes ~/ 60;
    final lateRemainingMinutes = lateMinutes % 60;
    final lateText = lateHours > 0
        ? 'Опоздание: $lateHours ч. $lateRemainingMinutes мин.'
        : 'Опоздание: $lateMinutes мин.';

    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => RecountReportViewPage(
              report: report,
              onReportUpdated: () {
                _loadData();
              },
            ),
          ),
        );
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 10, right: 8),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [Colors.deepPurple.shade50, Colors.purple.shade50],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: Colors.deepPurple.withOpacity(0.4),
            width: 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.deepPurple.withOpacity(0.15),
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Заголовок с иконкой
              Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Colors.deepPurple.shade400, Colors.purple.shade600],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.deepPurple.withOpacity(0.4),
                          blurRadius: 6,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.timer_off_rounded,
                      color: Colors.white,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          report.shopAddress,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                            color: Colors.black87,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          report.employeeName,
                          style: TextStyle(
                            color: Colors.grey.shade600,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    Icons.arrow_forward_ios_rounded,
                    color: Colors.grey.shade400,
                    size: 18,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              // Информация о дате и времени
              Row(
                children: [
                  _buildInfoChip(
                    Icons.calendar_today_rounded,
                    '${report.completedAt.day}.${report.completedAt.month}.${report.completedAt.year}',
                    Colors.blue,
                  ),
                  const SizedBox(width: 8),
                  _buildInfoChip(
                    Icons.access_time_rounded,
                    '${report.completedAt.hour.toString().padLeft(2, '0')}:${report.completedAt.minute.toString().padLeft(2, '0')}',
                    Colors.indigo,
                  ),
                  const SizedBox(width: 8),
                  _buildInfoChip(
                    isMorning ? Icons.wb_sunny_rounded : Icons.nights_stay_rounded,
                    shiftName,
                    isMorning ? Colors.orange : Colors.indigo,
                  ),
                ],
              ),
              const SizedBox(height: 10),
              // Информация о дедлайне и опоздании
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: Colors.grey.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.schedule_rounded, size: 14, color: Colors.grey.shade700),
                        const SizedBox(width: 4),
                        Text(
                          'Дедлайн: $deadline',
                          style: TextStyle(
                            color: Colors.grey.shade700,
                            fontWeight: FontWeight.w500,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: Colors.deepPurple.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.deepPurple.withOpacity(0.3)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.timer_off_rounded, size: 14, color: Colors.deepPurple.shade700),
                        const SizedBox(width: 4),
                        Text(
                          lateText,
                          style: TextStyle(
                            color: Colors.deepPurple.shade700,
                            fontWeight: FontWeight.w600,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              // Оценка (если есть)
              if (report.isRated) ...[
                const SizedBox(height: 10),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            _getRatingColor(report.adminRating!).withOpacity(0.8),
                            _getRatingColor(report.adminRating!),
                          ],
                        ),
                        borderRadius: BorderRadius.circular(10),
                        boxShadow: [
                          BoxShadow(
                            color: _getRatingColor(report.adminRating!).withOpacity(0.3),
                            blurRadius: 4,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.star_rounded, color: Colors.white, size: 18),
                          const SizedBox(width: 4),
                          Text(
                            '${report.adminRating}/10',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (report.adminName != null) ...[
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Проверил: ${report.adminName}',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade600,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  // ============================================================
  // СВОДНЫЙ ОТЧЁТ ЗА 30 ДНЕЙ (ИЕРАРХИЧЕСКИЙ СПИСОК)
  // ============================================================

  /// Проверить, является ли дата сегодняшней
  bool _isToday(DateTime date) {
    final now = DateTime.now();
    return date.year == now.year && date.month == now.month && date.day == now.day;
  }

  /// Группировка сводных отчётов по дате для иерархического отображения
  List<RecountReportGroup> _groupSummaryItems(List<RecountSummaryItem> items, String prefix) {
    if (items.isEmpty) return [];

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final weekAgo = today.subtract(const Duration(days: 7));

    List<RecountReportGroup> result = [];

    // Группируем по дням
    Map<DateTime, List<RecountSummaryItem>> byDay = {};
    for (final item in items) {
      final day = DateTime(item.date.year, item.date.month, item.date.day);
      byDay.putIfAbsent(day, () => []).add(item);
    }

    final sortedDays = byDay.keys.toList()..sort((a, b) => b.compareTo(a));

    // Сегодня (раскрыто по умолчанию)
    if (byDay.containsKey(today)) {
      final key = '${prefix}_today';
      _expandedGroups.putIfAbsent(key, () => true);
      result.add(RecountReportGroup(
        type: RecountReportGroupType.today,
        title: 'Сегодня',
        key: key,
        count: byDay[today]!.length,
        startDate: today,
        children: byDay[today]!,
      ));
    }

    // Вчера (свёрнуто)
    if (byDay.containsKey(yesterday)) {
      final key = '${prefix}_yesterday';
      _expandedGroups.putIfAbsent(key, () => false);
      result.add(RecountReportGroup(
        type: RecountReportGroupType.yesterday,
        title: 'Вчера',
        key: key,
        count: byDay[yesterday]!.length,
        startDate: yesterday,
        children: byDay[yesterday]!,
      ));
    }

    // Дни 2-6 дней назад (отдельные группы)
    for (final day in sortedDays) {
      if (day == today || day == yesterday) continue;
      if (day.isAfter(weekAgo) || day.isAtSameMomentAs(weekAgo)) {
        final key = '${prefix}_day_${day.toIso8601String()}';
        _expandedGroups.putIfAbsent(key, () => false);
        result.add(RecountReportGroup(
          type: RecountReportGroupType.day,
          title: _formatDayTitle(day),
          key: key,
          count: byDay[day]!.length,
          startDate: day,
          children: byDay[day]!,
        ));
      }
    }

    // Группируем старые записи по неделям
    Map<DateTime, List<RecountSummaryItem>> byWeek = {};
    for (final day in sortedDays) {
      if (day.isBefore(weekAgo)) {
        final weekStart = _getWeekStart(day);
        byWeek.putIfAbsent(weekStart, () => []).addAll(byDay[day]!);
      }
    }

    final sortedWeeks = byWeek.keys.toList()..sort((a, b) => b.compareTo(a));
    final monthAgo = today.subtract(const Duration(days: 30));

    for (final weekStart in sortedWeeks) {
      if (weekStart.isAfter(monthAgo) || weekStart.isAtSameMomentAs(monthAgo)) {
        final weekEnd = weekStart.add(const Duration(days: 6));
        final key = '${prefix}_week_${weekStart.toIso8601String()}';
        _expandedGroups.putIfAbsent(key, () => false);
        result.add(RecountReportGroup(
          type: RecountReportGroupType.week,
          title: '${_formatDayTitle(weekStart)} - ${_formatDayTitle(weekEnd)}',
          key: key,
          count: byWeek[weekStart]!.length,
          startDate: weekStart,
          children: byWeek[weekStart]!,
        ));
      }
    }

    // Группируем очень старые записи по месяцам
    Map<String, List<RecountSummaryItem>> byMonth = {};
    for (final weekStart in sortedWeeks) {
      if (weekStart.isBefore(monthAgo)) {
        final monthKey = '${weekStart.year}-${weekStart.month}';
        byMonth.putIfAbsent(monthKey, () => []).addAll(byWeek[weekStart]!);
      }
    }

    final sortedMonths = byMonth.keys.toList()..sort((a, b) => b.compareTo(a));
    for (final monthKey in sortedMonths) {
      final parts = monthKey.split('-');
      final year = int.parse(parts[0]);
      final month = int.parse(parts[1]);
      final monthStart = DateTime(year, month, 1);
      final key = '${prefix}_month_$monthKey';
      _expandedGroups.putIfAbsent(key, () => false);
      result.add(RecountReportGroup(
        type: RecountReportGroupType.month,
        title: '${_monthNamesGenitive[month].replaceFirst(_monthNamesGenitive[month][0], _monthNamesGenitive[month][0].toUpperCase())} $year',
        key: key,
        count: byMonth[monthKey]!.length,
        startDate: monthStart,
        children: byMonth[monthKey]!,
      ));
    }

    return result;
  }

  /// Построить список сводных отчётов (иерархический)
  Widget _buildSummaryReportsList() {
    if (_summaryItems.isEmpty) {
      return _buildEmptyState(
        icon: Icons.table_chart_outlined,
        title: 'Нет данных за последние 30 дней',
        subtitle: 'Сводные отчёты появятся здесь',
        color: Colors.deepPurple,
      );
    }

    final groups = _groupSummaryItems(_summaryItems, 'summary');

    return RefreshIndicator(
      onRefresh: _loadData,
      child: ListView.builder(
        padding: const EdgeInsets.all(8),
        itemCount: groups.length,
        itemBuilder: (context, index) {
          return _buildSummaryGroupTile(groups[index], 0);
        },
      ),
    );
  }

  /// Плитка группы сводных отчётов с дочерними элементами
  Widget _buildSummaryGroupTile(RecountReportGroup group, int depth) {
    final isExpanded = _expandedGroups[group.key] ?? false;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildGroupHeader(group, depth),
        if (isExpanded)
          ...group.children.map((child) {
            if (child is RecountReportGroup) {
              return _buildSummaryGroupTile(child, depth + 1);
            } else if (child is RecountSummaryItem) {
              return Padding(
                padding: EdgeInsets.only(left: 12.0 * (depth + 1)),
                child: _buildSummaryItemCard(child),
              );
            }
            return const SizedBox.shrink();
          }),
      ],
    );
  }

  /// Карточка сводного отчёта (смена за день)
  Widget _buildSummaryItemCard(RecountSummaryItem item) {
    final allPassed = item.passedCount == item.totalCount && item.totalCount > 0;
    final nonePassed = item.passedCount == 0;
    final isMorning = item.shiftType == 'morning';

    return GestureDetector(
      onTap: () => _openSummaryReport(item),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8, right: 8),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: allPassed
                ? [Colors.green.shade50, Colors.white]
                : nonePassed
                    ? [Colors.red.shade50, Colors.white]
                    : [Colors.white, Colors.white],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: allPassed
                ? Colors.green.withOpacity(0.4)
                : nonePassed
                    ? Colors.red.withOpacity(0.3)
                    : Colors.grey.withOpacity(0.2),
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              // Иконка смены
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: isMorning
                        ? [Colors.orange.shade300, Colors.orange.shade600]
                        : [Colors.indigo.shade300, Colors.indigo.shade600],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: [
                    BoxShadow(
                      color: (isMorning ? Colors.orange : Colors.indigo).withOpacity(0.3),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Icon(
                  isMorning ? Icons.wb_sunny : Icons.nights_stay,
                  color: Colors.white,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              // Информация
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.shiftName,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                        color: Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      allPassed
                          ? 'Все магазины прошли'
                          : nonePassed
                              ? 'Никто не прошёл'
                              : 'Не прошли: ${item.totalCount - item.passedCount}',
                      style: TextStyle(
                        fontSize: 12,
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
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: allPassed
                      ? Colors.green
                      : nonePassed
                          ? Colors.red.shade400
                          : Colors.deepPurple,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '${item.passedCount}/${item.totalCount}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              const Icon(Icons.arrow_forward_ios, size: 14, color: Colors.grey),
            ],
          ),
        ),
      ),
    );
  }

  /// Открыть страницу сводного отчёта (pivot-таблица)
  void _openSummaryReport(RecountSummaryItem item) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => RecountSummaryReportPage(
          date: item.date,
          shiftType: item.shiftType,
          shiftName: item.shiftName,
          reports: item.reports,
          allShops: _allShops,
        ),
      ),
    );
  }

  /// Построить ячейку с разницей
  Widget _buildDifferenceCell(int? difference) {
    if (difference == null) {
      return const Center(
        child: Text('—', style: TextStyle(color: Colors.grey, fontSize: 14)),
      );
    }
    if (difference == 0) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.green.withOpacity(0.2),
          borderRadius: BorderRadius.circular(6),
        ),
        child: const Text(
          '0',
          style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold, fontSize: 13),
          textAlign: TextAlign.center,
        ),
      );
    }

    final isPositive = difference > 0;
    final color = isPositive ? Colors.blue : Colors.red;
    final sign = isPositive ? '+' : '';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.2),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        '$sign$difference',
        style: TextStyle(color: color.shade700, fontWeight: FontWeight.bold, fontSize: 13),
        textAlign: TextAlign.center,
      ),
    );
  }

  /// Показать диалог с деталями отчёта по товару и магазину
  void _showReportDetailDialog(RecountPivotShop shop, String productName) async {
    // Показываем индикатор загрузки
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const Center(child: CircularProgressIndicator()),
    );

    try {
      // Загружаем отчёты за выбранную дату
      final allReports = await RecountService.getReports(date: _pivotDate);

      // Фильтруем по магазину
      final shopReports = allReports.where((r) => r.shopAddress == shop.shopId).toList();

      // Находим ответ по товару
      RecountAnswer? foundAnswer;
      RecountReport? foundReport;

      for (final report in shopReports) {
        for (final answer in report.answers) {
          if (answer.question == productName) {
            foundAnswer = answer;
            foundReport = report;
            break;
          }
        }
        if (foundAnswer != null) break;
      }

      if (!mounted) return;
      Navigator.pop(context); // Закрываем индикатор загрузки

      // Показываем диалог с деталями
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text(
            productName,
            style: const TextStyle(fontSize: 16),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Магазин
                _buildDetailRow('Магазин', shop.shopAddress ?? shop.shopName),
                const Divider(),

                if (foundReport != null) ...[
                  // Сотрудник
                  _buildDetailRow('Сотрудник', foundReport.employeeName),
                  _buildDetailRow('Время', DateFormat('HH:mm').format(foundReport.completedAt)),
                  _buildDetailRow('Смена', foundReport.shiftType == 'morning' ? 'Утро' : 'Вечер'),
                  _buildDetailRow('Статус', _getStatusLabel(foundReport.status ?? '')),
                  const Divider(),
                ],

                if (foundAnswer != null) ...[
                  // Результат
                  _buildDetailRow('По программе', '${foundAnswer.programBalance ?? 0} шт'),
                  _buildDetailRow('По факту', '${foundAnswer.actualBalance ?? foundAnswer.programBalance ?? 0} шт'),
                  _buildDetailRow('Разница', _formatAnswerDifference(foundAnswer)),

                  // Фото если есть
                  if (foundAnswer.photoUrl != null && foundAnswer.photoUrl!.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.network(
                        foundAnswer.photoUrl!,
                        height: 150,
                        width: double.infinity,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Container(
                          height: 60,
                          color: Colors.grey.shade200,
                          child: const Center(
                            child: Icon(Icons.broken_image, color: Colors.grey),
                          ),
                        ),
                      ),
                    ),
                  ],
                ] else
                  const Padding(
                    padding: EdgeInsets.all(8.0),
                    child: Text('Данные не найдены', style: TextStyle(color: Colors.grey)),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Закрыть'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context); // Закрываем индикатор загрузки
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка загрузки: $e')),
      );
    }
  }

  /// Построить строку деталей
  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(color: Colors.grey, fontSize: 13)),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13),
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }

  /// Форматировать разницу из ответа
  String _formatAnswerDifference(RecountAnswer answer) {
    if (answer.isMatching) return '0 (сходится)';
    if (answer.moreBy != null && answer.moreBy! > 0) return '+${answer.moreBy} (больше)';
    if (answer.lessBy != null && answer.lessBy! > 0) return '-${answer.lessBy} (меньше)';
    if (answer.difference != null && answer.difference != 0) {
      final sign = answer.difference! > 0 ? '+' : '';
      return '$sign${answer.difference}';
    }
    return '0';
  }

  /// Получить текстовый статус
  String _getStatusLabel(String status) {
    switch (status) {
      case 'pending': return 'Ожидает';
      case 'review': return 'На проверке';
      case 'confirmed': return 'Проверено';
      case 'failed': return 'Не прошёл';
      case 'rejected': return 'Отклонён';
      default: return status;
    }
  }

  /// Построить элемент статистики
  Widget _buildStatItem(String label, String value, Color color) {
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        Text(
          label,
          style: const TextStyle(fontSize: 12, color: Colors.grey),
        ),
      ],
    );
  }

  /// Построить элемент легенды
  Widget _buildLegendItem(String symbol, String label, Color color) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: color.withOpacity(0.2),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            symbol,
            style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 11),
          ),
        ),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(fontSize: 10, color: Colors.grey)),
      ],
    );
  }
}
