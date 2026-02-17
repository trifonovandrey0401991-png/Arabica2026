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
import '../../shops/services/shop_service.dart';
import '../../efficiency/models/points_settings_model.dart';
import '../../efficiency/services/points_settings_service.dart';
import 'recount_report_view_page.dart';
import 'recount_summary_report_page.dart';
import '../../../shared/widgets/app_cached_image.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../../core/theme/app_colors.dart';

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
    final months = ['', 'января', 'февраля', 'марта', 'апреля', 'мая', 'июня',
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
  static final _monthNamesGenitive = [
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
      final shops = await ShopService.getShopsForCurrentUser();
      _allShops = shops;
      Logger.success('Загружено магазинов (с учётом роли): ${shops.length}');
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
      final serverReports = await RecountService.getReportsForCurrentUser();
      Logger.success('Загружено отчетов с сервера: ${serverReports.length}');

      // Исключаем pending файлы шедулера (они не являются отчётами сотрудников)
      _allReports = serverReports.where((r) => r.status != 'pending').toList();
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
    final thirtyDaysAgo = now.subtract(Duration(days: 30));

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

  /// Не оценённые отчёты (ожидают проверки) - только со статусом review
  List<RecountReport> get _awaitingReports {
    final pending = _allReports.where((r) {
      // Только отчёты со статусом review (реально отправленные сотрудником)
      if (r.status != 'review') return false;
      if (r.isRated) return false;
      return true;
    }).toList();
    return _applyFilters(pending);
  }

  /// Отклонённые отчёты (rejected или expired, исключая pending от шедулера)
  List<RecountReport> get _overdueUnratedReports {
    return _allReports.where((r) {
      if (r.isRated) return false;
      // Только отчёты со статусом rejected или те что реально были отправлены
      if (r.status == 'rejected') return true;
      if (r.status == 'expired') return true;
      // Не показываем pending от шедулера
      if (r.status == 'pending') return false;
      // Для старых отчётов без явного статуса — проверяем по времени
      if (r.status == null || r.status == 'review') return false;
      return false;
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
    return _allReports.map((r) => r.shopAddress).where((a) => a.trim().isNotEmpty).toSet().toList()..sort();
  }

  List<String> get _uniqueEmployees {
    return _allReports.map((r) => r.employeeName).toSet().toList()..sort();
  }

  Future<void> _selectDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate ?? DateTime.now(),
      firstDate: DateTime.now().subtract(Duration(days: 30)),
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
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 12.h),
                child: Row(
                  children: [
                    GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(12.r),
                          border: Border.all(color: Colors.white.withOpacity(0.1)),
                        ),
                        child: Icon(Icons.arrow_back, color: Colors.white, size: 20),
                      ),
                    ),
                    SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Отчеты по пересчету',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 20.sp,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    GestureDetector(
                      onTap: _loadData,
                      child: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(12.r),
                          border: Border.all(color: Colors.white.withOpacity(0.1)),
                        ),
                        child: Icon(Icons.refresh, color: Colors.white, size: 20),
                      ),
                    ),
                  ],
                ),
              ),

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
                    _buildPendingRecountsList(),
                    _buildFailedRecountsList(),
                    _buildReportsList(_awaitingReports, isPending: true),
                    _buildReportsList(_ratedReports, isPending: false),
                    _buildExpiredReportsList(),
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
      padding: EdgeInsets.fromLTRB(12.w, 8.h, 12.w, 8.h),
      child: Column(
        children: [
          // Первый ряд: 3 вкладки
          Row(
            children: [
              _buildTabButton(0, Icons.schedule_rounded, 'Ожидают', _pendingRecounts.length, Colors.orange),
              SizedBox(width: 6),
              _buildTabButton(1, Icons.warning_amber_rounded, 'Не прошли', _failedRecounts.length, Colors.red, badge: _failedRecountsBadgeCount),
              SizedBox(width: 6),
              _buildTabButton(2, Icons.hourglass_empty_rounded, 'Проверка', _awaitingReports.length, Colors.blue),
            ],
          ),
          SizedBox(height: 6),
          // Второй ряд: 2 вкладки
          Row(
            children: [
              _buildTabButton(3, Icons.check_circle_rounded, 'Проверено', _allReports.where((r) => r.isRated).length, Colors.green),
              SizedBox(width: 6),
              _buildTabButton(4, Icons.cancel_rounded, 'Отклонённые', _expiredReports.length + _overdueUnratedReports.length, Colors.grey),
            ],
          ),
          SizedBox(height: 6),
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
                  color: isSelected ? Colors.white : Colors.white70,
                ),
                SizedBox(width: 4),
                Flexible(
                  child: Text(
                    label,
                    style: TextStyle(
                      fontSize: 10.sp,
                      color: isSelected ? Colors.white : Colors.white70,
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

  /// Построение секции фильтров
  Widget _buildFiltersSection() {
    return Container(
      margin: EdgeInsets.symmetric(horizontal: 12.w),
      padding: EdgeInsets.all(12.w),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.06),
        borderRadius: BorderRadius.circular(14.r),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
      ),
      child: Column(
        children: [
          // Магазин
          DropdownButtonFormField<String>(
            value: _selectedShop,
            isExpanded: true,
            dropdownColor: AppColors.emeraldDark,
            style: TextStyle(color: Colors.white.withOpacity(0.9), fontSize: 14.sp),
            decoration: InputDecoration(
              labelText: 'Магазин',
              labelStyle: TextStyle(color: Colors.white.withOpacity(0.5)),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10.r), borderSide: BorderSide(color: Colors.white.withOpacity(0.1))),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10.r), borderSide: BorderSide(color: Colors.white.withOpacity(0.1))),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10.r), borderSide: BorderSide(color: AppColors.gold)),
              contentPadding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 8.h),
            ),
            iconEnabledColor: AppColors.gold,
            items: [
              DropdownMenuItem<String>(
                value: null,
                child: Text('Все магазины', style: TextStyle(color: Colors.white.withOpacity(0.9))),
              ),
              ..._uniqueShops.map((shop) => DropdownMenuItem<String>(
                value: shop,
                child: Text(shop, overflow: TextOverflow.ellipsis, style: TextStyle(color: Colors.white.withOpacity(0.9))),
              )),
            ],
            onChanged: (value) {
              setState(() {
                _selectedShop = value;
              });
            },
          ),
          SizedBox(height: 10),
          // Сотрудник и Дата в одном ряду
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  value: _selectedEmployee,
                  isExpanded: true,
                  dropdownColor: AppColors.emeraldDark,
                  style: TextStyle(color: Colors.white.withOpacity(0.9), fontSize: 14.sp),
                  decoration: InputDecoration(
                    labelText: 'Сотрудник',
                    labelStyle: TextStyle(color: Colors.white.withOpacity(0.5)),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10.r), borderSide: BorderSide(color: Colors.white.withOpacity(0.1))),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10.r), borderSide: BorderSide(color: Colors.white.withOpacity(0.1))),
                    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10.r), borderSide: BorderSide(color: AppColors.gold)),
                    contentPadding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 8.h),
                  ),
                  iconEnabledColor: AppColors.gold,
                  items: [
                    DropdownMenuItem<String>(
                      value: null,
                      child: Text('Все', style: TextStyle(color: Colors.white.withOpacity(0.9))),
                    ),
                    ..._uniqueEmployees.map((employee) => DropdownMenuItem<String>(
                      value: employee,
                      child: Text(employee, overflow: TextOverflow.ellipsis, style: TextStyle(color: Colors.white.withOpacity(0.9))),
                    )),
                  ],
                  onChanged: (value) {
                    setState(() {
                      _selectedEmployee = value;
                    });
                  },
                ),
              ),
              SizedBox(width: 10),
              Expanded(
                child: InkWell(
                  onTap: () => _selectDate(context),
                  borderRadius: BorderRadius.circular(10.r),
                  child: Container(
                    padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 12.h),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10.r),
                      border: Border.all(color: Colors.white.withOpacity(0.1)),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Дата', style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 12.sp)),
                              Text(
                                _selectedDate != null
                                    ? '${_selectedDate!.day}.${_selectedDate!.month}'
                                    : 'Все',
                                style: TextStyle(color: Colors.white.withOpacity(0.9), fontSize: 14.sp),
                              ),
                            ],
                          ),
                        ),
                        Icon(Icons.calendar_today, size: 18, color: AppColors.gold),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
          // Сброс фильтров
          if (_selectedShop != null || _selectedEmployee != null || _selectedDate != null)
            Padding(
              padding: EdgeInsets.only(top: 10.h),
              child: GestureDetector(
                onTap: () {
                  setState(() {
                    _selectedShop = null;
                    _selectedEmployee = null;
                    _selectedDate = null;
                  });
                },
                child: Container(
                  padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 8.h),
                  decoration: BoxDecoration(
                    color: Colors.red.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(10.r),
                    border: Border.all(color: Colors.red.withOpacity(0.3)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.clear, size: 18, color: Colors.red),
                      SizedBox(width: 6),
                      Text('Сбросить фильтры', style: TextStyle(color: Colors.red, fontWeight: FontWeight.w500)),
                    ],
                  ),
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
              color: Colors.white.withOpacity(0.06),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 40, color: Colors.white.withOpacity(0.3)),
          ),
          SizedBox(height: 16),
          Text(
            title,
            style: TextStyle(
              color: Colors.white,
              fontSize: 18.sp,
              fontWeight: FontWeight.bold,
            ),
          ),
          SizedBox(height: 8),
          Text(
            subtitle,
            style: TextStyle(
              color: Colors.white.withOpacity(0.5),
              fontSize: 14.sp,
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
      padding: EdgeInsets.all(12.w),
      itemCount: _pendingRecounts.length,
      itemBuilder: (context, index) {
        final pending = _pendingRecounts[index];
        final isMorning = pending.shiftType == 'morning';

        return Container(
          margin: EdgeInsets.only(bottom: 10.h),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.06),
            borderRadius: BorderRadius.circular(14.r),
            border: Border.all(
              color: isMorning ? Colors.orange.withOpacity(0.3) : Colors.purple.withOpacity(0.3),
            ),
          ),
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
                          ? [Colors.orange.shade400, Colors.amber.shade600]
                          : [Colors.deepPurple.shade400, Colors.purple.shade600],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(14.r),
                  ),
                  child: Icon(
                    isMorning ? Icons.wb_sunny_rounded : Icons.nights_stay_rounded,
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
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      SizedBox(height: 6),
                      Row(
                        children: [
                          Icon(
                            Icons.calendar_today,
                            size: 14,
                            color: Colors.white.withOpacity(0.4),
                          ),
                          SizedBox(width: 4),
                          Text(
                            todayStr,
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.5),
                              fontSize: 13.sp,
                            ),
                          ),
                          SizedBox(width: 10),
                          Container(
                            padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 3.h),
                            decoration: BoxDecoration(
                              color: isMorning ? Colors.blue.withOpacity(0.15) : Colors.purple.withOpacity(0.15),
                              borderRadius: BorderRadius.circular(8.r),
                              border: Border.all(
                                color: isMorning ? Colors.blue.withOpacity(0.3) : Colors.purple.withOpacity(0.3),
                              ),
                            ),
                            child: Text(
                              pending.shiftName,
                              style: TextStyle(
                                color: isMorning ? Colors.blue.shade300 : Colors.purple.shade300,
                                fontWeight: FontWeight.w600,
                                fontSize: 11.sp,
                              ),
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: 6),
                      Container(
                        padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 4.h),
                        decoration: BoxDecoration(
                          color: Colors.orange.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(8.r),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.warning_amber_rounded, size: 14, color: Colors.orange),
                            SizedBox(width: 4),
                            Text(
                              'Пересчёт не проведён',
                              style: TextStyle(
                                color: Colors.orange,
                                fontWeight: FontWeight.w600,
                                fontSize: 12.sp,
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
                    borderRadius: BorderRadius.circular(10.r),
                  ),
                  child: Icon(
                    Icons.schedule_rounded,
                    color: Colors.orange,
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
      padding: EdgeInsets.all(12.w),
      itemCount: _failedRecounts.length,
      itemBuilder: (context, index) {
        final failed = _failedRecounts[index];
        final isMorning = failed.shiftType == 'morning';

        // Получаем дедлайн из настроек
        final deadline = isMorning
            ? (_recountSettings?.morningEndTime ?? '13:00')
            : (_recountSettings?.eveningEndTime ?? '23:00');

        return Container(
          margin: EdgeInsets.only(bottom: 10.h),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.06),
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
                        isMorning ? Icons.wb_sunny_rounded : Icons.nights_stay_rounded,
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
                              color: isMorning ? Colors.orange.withOpacity(0.15) : Colors.indigo.withOpacity(0.15),
                              borderRadius: BorderRadius.circular(6.r),
                            ),
                            child: Text(
                              failed.shiftName,
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
                            'Дедлайн: $deadline',
                            style: TextStyle(fontSize: 12.sp, color: Colors.red[400]),
                          ),
                          if (_recountSettings != null) ...[
                            Spacer(),
                            Container(
                              padding: EdgeInsets.symmetric(horizontal: 6.w, vertical: 2.h),
                              decoration: BoxDecoration(
                                color: Colors.deepOrange.withOpacity(0.15),
                                borderRadius: BorderRadius.circular(4.r),
                              ),
                              child: Text(
                                '${_recountSettings!.missedPenalty.toStringAsFixed(1)} б.',
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
      color: AppColors.gold,
      backgroundColor: AppColors.emeraldDark,
      child: ListView.builder(
        padding: EdgeInsets.all(8.w),
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
                padding: EdgeInsets.only(left: 12.0.w * (depth + 1)),
                child: _buildExpiredReportCard(child),
              );
            }
            return SizedBox.shrink();
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
        margin: EdgeInsets.only(bottom: 10.h, right: 8.w),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.06),
          borderRadius: BorderRadius.circular(14.r),
          border: Border.all(
            color: statusColor.withOpacity(0.3),
          ),
        ),
        child: Padding(
          padding: EdgeInsets.all(14.w),
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
                      borderRadius: BorderRadius.circular(12.r),
                    ),
                    child: Icon(
                      isFromExpiredList ? Icons.cancel_rounded : Icons.access_time_rounded,
                      color: Colors.white,
                      size: 24,
                    ),
                  ),
                  SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          report.shopAddress,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 15.sp,
                            color: Colors.white.withOpacity(0.9),
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        SizedBox(height: 2),
                        Text(
                          report.employeeName,
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.5),
                            fontSize: 13.sp,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    Icons.arrow_forward_ios_rounded,
                    color: Colors.white.withOpacity(0.3),
                    size: 18,
                  ),
                ],
              ),
              SizedBox(height: 12),
              // Информация о дате и времени
              Row(
                children: [
                  _buildInfoChip(
                    Icons.calendar_today_rounded,
                    '${report.completedAt.day}.${report.completedAt.month}.${report.completedAt.year}',
                    Colors.blue,
                  ),
                  SizedBox(width: 8),
                  _buildInfoChip(
                    Icons.access_time_rounded,
                    '${report.completedAt.hour.toString().padLeft(2, '0')}:${report.completedAt.minute.toString().padLeft(2, '0')}',
                    Colors.indigo,
                  ),
                  SizedBox(width: 8),
                  _buildInfoChip(
                    Icons.timer_outlined,
                    report.formattedDuration,
                    Colors.teal,
                  ),
                ],
              ),
              SizedBox(height: 10),
              // Статус просрочки
              Container(
                padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 6.h),
                decoration: BoxDecoration(
                  color: statusColor.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(10.r),
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
                    SizedBox(width: 6),
                    Text(
                      isFromExpiredList && report.expiredAt != null
                          ? 'Просрочен: ${report.expiredAt!.day}.${report.expiredAt!.month}.${report.expiredAt!.year}'
                          : 'Ожидает: $waitingHours ч. (более 5 часов)',
                      style: TextStyle(
                        color: isFromExpiredList ? Colors.red.shade700 : Colors.orange.shade700,
                        fontWeight: FontWeight.w600,
                        fontSize: 12.sp,
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
    final yesterday = today.subtract(Duration(days: 1));
    final weekAgo = today.subtract(Duration(days: 7));

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
    final monthAgo = today.subtract(Duration(days: 30));

    for (final weekStart in sortedWeeks) {
      if (weekStart.isAfter(monthAgo) || weekStart.isAtSameMomentAs(monthAgo)) {
        final weekEnd = weekStart.add(Duration(days: 6));
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
          left: 12.0.w * depth,
          right: 8.w,
          top: 4.h,
          bottom: 4.h,
        ),
        padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 10.h),
        decoration: BoxDecoration(
          color: color.withOpacity(0.15),
          borderRadius: BorderRadius.circular(10.r),
          border: Border.all(color: color.withOpacity(0.4)),
        ),
        child: Row(
          children: [
            Icon(icon, color: color, size: 20),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                group.title,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: color,
                  fontSize: 14.sp,
                ),
              ),
            ),
            Container(
              padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 2.h),
              decoration: BoxDecoration(
                color: color.withOpacity(0.2),
                borderRadius: BorderRadius.circular(12.r),
              ),
              child: Text(
                '${group.count}',
                style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.bold,
                  fontSize: 12.sp,
                ),
              ),
            ),
            SizedBox(width: 8),
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
                padding: EdgeInsets.only(left: 12.0.w * (depth + 1)),
                child: _buildRecountReportCard(child),
              );
            }
            return SizedBox.shrink();
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
        margin: EdgeInsets.only(bottom: 10.h, right: 8.w),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.06),
          borderRadius: BorderRadius.circular(14.r),
          border: Border.all(
            color: statusColor.withOpacity(0.3),
          ),
        ),
        child: Padding(
          padding: EdgeInsets.all(14.w),
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
                      borderRadius: BorderRadius.circular(12.r),
                    ),
                    child: Icon(statusIcon, color: Colors.white, size: 24),
                  ),
                  SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          report.shopAddress,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 15.sp,
                            color: Colors.white.withOpacity(0.9),
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        SizedBox(height: 2),
                        Text(
                          report.employeeName,
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.5),
                            fontSize: 13.sp,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    Icons.arrow_forward_ios_rounded,
                    color: Colors.white.withOpacity(0.3),
                    size: 18,
                  ),
                ],
              ),
              SizedBox(height: 12),
              // Информация о дате и времени
              Row(
                children: [
                  _buildInfoChip(
                    Icons.calendar_today_rounded,
                    '${report.completedAt.day}.${report.completedAt.month}.${report.completedAt.year}',
                    Colors.blue,
                  ),
                  SizedBox(width: 8),
                  _buildInfoChip(
                    Icons.access_time_rounded,
                    '${report.completedAt.hour.toString().padLeft(2, '0')}:${report.completedAt.minute.toString().padLeft(2, '0')}',
                    Colors.indigo,
                  ),
                  SizedBox(width: 8),
                  _buildInfoChip(
                    Icons.timer_outlined,
                    report.formattedDuration,
                    Colors.teal,
                  ),
                ],
              ),
              // Оценка (если есть)
              if (report.isRated) ...[
                SizedBox(height: 10),
                Row(
                  children: [
                    Container(
                      padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 6.h),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            _getRatingColor(report.adminRating!).withOpacity(0.8),
                            _getRatingColor(report.adminRating!),
                          ],
                        ),
                        borderRadius: BorderRadius.circular(10.r),
                        boxShadow: [
                          BoxShadow(
                            color: _getRatingColor(report.adminRating!).withOpacity(0.3),
                            blurRadius: 4,
                            offset: Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.star_rounded, color: Colors.white, size: 18),
                          SizedBox(width: 4),
                          Text(
                            '${report.adminRating}/10',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 14.sp,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (report.adminName != null) ...[
                      SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Проверил: ${report.adminName}',
                          style: TextStyle(
                            fontSize: 12.sp,
                            color: Colors.white.withOpacity(0.5),
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ],
                ),
              ] else ...[
                SizedBox(height: 10),
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 5.h),
                  decoration: BoxDecoration(
                    color: Colors.amber.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(8.r),
                    border: Border.all(color: Colors.amber.withOpacity(0.3)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.hourglass_empty_rounded, size: 14, color: Colors.amber.shade700),
                      SizedBox(width: 4),
                      Text(
                        statusText,
                        style: TextStyle(
                          color: Colors.amber.shade700,
                          fontWeight: FontWeight.w600,
                          fontSize: 12.sp,
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
      padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 4.h),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8.r),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color.withOpacity(0.8)),
          SizedBox(width: 4),
          Text(
            text,
            style: TextStyle(
              color: color,
              fontSize: 11.sp,
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
      color: AppColors.gold,
      backgroundColor: AppColors.emeraldDark,
      child: ListView.builder(
        padding: EdgeInsets.all(8.w),
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
      color: AppColors.gold,
      backgroundColor: AppColors.emeraldDark,
      child: ListView.builder(
        padding: EdgeInsets.all(8.w),
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
                padding: EdgeInsets.only(left: 12.0.w * (depth + 1)),
                child: _buildLateReportCard(child),
              );
            }
            return SizedBox.shrink();
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
        margin: EdgeInsets.only(bottom: 10.h, right: 8.w),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.06),
          borderRadius: BorderRadius.circular(14.r),
          border: Border.all(
            color: Colors.deepPurple.withOpacity(0.3),
          ),
        ),
        child: Padding(
          padding: EdgeInsets.all(14.w),
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
                      borderRadius: BorderRadius.circular(12.r),
                    ),
                    child: Icon(
                      Icons.timer_off_rounded,
                      color: Colors.white,
                      size: 24,
                    ),
                  ),
                  SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          report.shopAddress,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 15.sp,
                            color: Colors.white.withOpacity(0.9),
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        SizedBox(height: 2),
                        Text(
                          report.employeeName,
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.5),
                            fontSize: 13.sp,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    Icons.arrow_forward_ios_rounded,
                    color: Colors.white.withOpacity(0.3),
                    size: 18,
                  ),
                ],
              ),
              SizedBox(height: 12),
              // Информация о дате и времени
              Row(
                children: [
                  _buildInfoChip(
                    Icons.calendar_today_rounded,
                    '${report.completedAt.day}.${report.completedAt.month}.${report.completedAt.year}',
                    Colors.blue,
                  ),
                  SizedBox(width: 8),
                  _buildInfoChip(
                    Icons.access_time_rounded,
                    '${report.completedAt.hour.toString().padLeft(2, '0')}:${report.completedAt.minute.toString().padLeft(2, '0')}',
                    Colors.indigo,
                  ),
                  SizedBox(width: 8),
                  _buildInfoChip(
                    isMorning ? Icons.wb_sunny_rounded : Icons.nights_stay_rounded,
                    shiftName,
                    isMorning ? Colors.orange : Colors.indigo,
                  ),
                ],
              ),
              SizedBox(height: 10),
              // Информация о дедлайне и опоздании
              Row(
                children: [
                  Container(
                    padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 5.h),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.06),
                      borderRadius: BorderRadius.circular(8.r),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.schedule_rounded, size: 14, color: Colors.white.withOpacity(0.5)),
                        SizedBox(width: 4),
                        Text(
                          'Дедлайн: $deadline',
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.5),
                            fontWeight: FontWeight.w500,
                            fontSize: 12.sp,
                          ),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(width: 8),
                  Container(
                    padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 5.h),
                    decoration: BoxDecoration(
                      color: Colors.deepPurple.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(8.r),
                      border: Border.all(color: Colors.deepPurple.withOpacity(0.3)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.timer_off_rounded, size: 14, color: Colors.deepPurple.shade700),
                        SizedBox(width: 4),
                        Text(
                          lateText,
                          style: TextStyle(
                            color: Colors.deepPurple.shade700,
                            fontWeight: FontWeight.w600,
                            fontSize: 12.sp,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              // Оценка (если есть)
              if (report.isRated) ...[
                SizedBox(height: 10),
                Row(
                  children: [
                    Container(
                      padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 6.h),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            _getRatingColor(report.adminRating!).withOpacity(0.8),
                            _getRatingColor(report.adminRating!),
                          ],
                        ),
                        borderRadius: BorderRadius.circular(10.r),
                        boxShadow: [
                          BoxShadow(
                            color: _getRatingColor(report.adminRating!).withOpacity(0.3),
                            blurRadius: 4,
                            offset: Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.star_rounded, color: Colors.white, size: 18),
                          SizedBox(width: 4),
                          Text(
                            '${report.adminRating}/10',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 14.sp,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (report.adminName != null) ...[
                      SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Проверил: ${report.adminName}',
                          style: TextStyle(
                            fontSize: 12.sp,
                            color: Colors.white.withOpacity(0.5),
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
    final yesterday = today.subtract(Duration(days: 1));
    final weekAgo = today.subtract(Duration(days: 7));

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
    final monthAgo = today.subtract(Duration(days: 30));

    for (final weekStart in sortedWeeks) {
      if (weekStart.isAfter(monthAgo) || weekStart.isAtSameMomentAs(monthAgo)) {
        final weekEnd = weekStart.add(Duration(days: 6));
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
      color: AppColors.gold,
      backgroundColor: AppColors.emeraldDark,
      child: ListView.builder(
        padding: EdgeInsets.all(8.w),
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
                padding: EdgeInsets.only(left: 12.0.w * (depth + 1)),
                child: _buildSummaryItemCard(child),
              );
            }
            return SizedBox.shrink();
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
        margin: EdgeInsets.only(bottom: 8.h, right: 8.w),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.06),
          borderRadius: BorderRadius.circular(14.r),
          border: Border.all(
            color: allPassed
                ? Colors.green.withOpacity(0.3)
                : nonePassed
                    ? Colors.red.withOpacity(0.3)
                    : Colors.white.withOpacity(0.1),
          ),
        ),
        child: Padding(
          padding: EdgeInsets.all(12.w),
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
                  borderRadius: BorderRadius.circular(10.r),
                ),
                child: Icon(
                  isMorning ? Icons.wb_sunny : Icons.nights_stay,
                  color: Colors.white,
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
                      item.shiftName,
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14.sp,
                        color: Colors.white.withOpacity(0.9),
                      ),
                    ),
                    SizedBox(height: 2),
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
                padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 5.h),
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
                    fontSize: 12.sp,
                  ),
                ),
              ),
              SizedBox(width: 6),
              Icon(Icons.arrow_forward_ios, size: 14, color: Colors.white.withOpacity(0.3)),
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
      return Center(
        child: Text('—', style: TextStyle(color: Colors.grey, fontSize: 14.sp)),
      );
    }
    if (difference == 0) {
      return Container(
        padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 4.h),
        decoration: BoxDecoration(
          color: Colors.green.withOpacity(0.2),
          borderRadius: BorderRadius.circular(6.r),
        ),
        child: Text(
          '0',
          style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold, fontSize: 13.sp),
          textAlign: TextAlign.center,
        ),
      );
    }

    final isPositive = difference > 0;
    final color = isPositive ? Colors.blue : Colors.red;
    final sign = isPositive ? '+' : '';

    return Container(
      padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 4.h),
      decoration: BoxDecoration(
        color: color.withOpacity(0.2),
        borderRadius: BorderRadius.circular(6.r),
      ),
      child: Text(
        '$sign$difference',
        style: TextStyle(color: color.shade700, fontWeight: FontWeight.bold, fontSize: 13.sp),
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
      builder: (ctx) => Center(child: CircularProgressIndicator(color: AppColors.gold)),
    );

    try {
      // Загружаем отчёты за выбранную дату
      final allReports = await RecountService.getReportsForCurrentUser(date: _pivotDate);

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
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16.r)),
          title: Text(
            productName,
            style: TextStyle(fontSize: 16.sp),
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
                Divider(),

                if (foundReport != null) ...[
                  // Сотрудник
                  _buildDetailRow('Сотрудник', foundReport.employeeName),
                  _buildDetailRow('Время', DateFormat('HH:mm').format(foundReport.completedAt)),
                  _buildDetailRow('Смена', foundReport.shiftType == 'morning' ? 'Утро' : 'Вечер'),
                  _buildDetailRow('Статус', _getStatusLabel(foundReport.status ?? '')),
                  Divider(),
                ],

                if (foundAnswer != null) ...[
                  // Результат
                  _buildDetailRow('По программе', '${foundAnswer.programBalance ?? 0} шт'),
                  _buildDetailRow('По факту', '${foundAnswer.actualBalance ?? foundAnswer.programBalance ?? 0} шт'),
                  _buildDetailRow('Разница', _formatAnswerDifference(foundAnswer)),

                  // Фото если есть
                  if (foundAnswer.photoUrl != null && foundAnswer.photoUrl!.isNotEmpty) ...[
                    SizedBox(height: 12),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8.r),
                      child: AppCachedImage(
                        imageUrl: foundAnswer.photoUrl!,
                        height: 150,
                        width: double.infinity,
                        fit: BoxFit.cover,
                        errorWidget: (_, __, ___) => Container(
                          height: 60,
                          color: Colors.white.withOpacity(0.06),
                          child: Center(
                            child: Icon(Icons.broken_image, color: Colors.white.withOpacity(0.3)),
                          ),
                        ),
                      ),
                    ),
                  ],
                ] else
                  Padding(
                    padding: EdgeInsets.all(8.0.w),
                    child: Text('Данные не найдены', style: TextStyle(color: Colors.grey)),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('Закрыть'),
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
      padding: EdgeInsets.symmetric(vertical: 4.h),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(color: Colors.grey, fontSize: 13.sp)),
          SizedBox(width: 8),
          Flexible(
            child: Text(
              value,
              style: TextStyle(fontWeight: FontWeight.w500, fontSize: 13.sp),
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
            fontSize: 20.sp,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        Text(
          label,
          style: TextStyle(fontSize: 12.sp, color: Colors.white.withOpacity(0.5)),
        ),
      ],
    );
  }

  /// Построить элемент легенды
  Widget _buildLegendItem(String symbol, String label, Color color) {
    return Row(
      children: [
        Container(
          padding: EdgeInsets.symmetric(horizontal: 6.w, vertical: 2.h),
          decoration: BoxDecoration(
            color: color.withOpacity(0.2),
            borderRadius: BorderRadius.circular(4.r),
          ),
          child: Text(
            symbol,
            style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 11.sp),
          ),
        ),
        SizedBox(width: 4),
        Text(label, style: TextStyle(fontSize: 10.sp, color: Colors.white.withOpacity(0.5))),
      ],
    );
  }
}
