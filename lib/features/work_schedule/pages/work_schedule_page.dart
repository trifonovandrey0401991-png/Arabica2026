import 'package:flutter/material.dart';
import '../../../core/utils/logger.dart';
import '../models/work_schedule_model.dart';
import '../services/work_schedule_service.dart';
import '../services/shift_transfer_service.dart';
import '../services/schedule_pdf_service.dart';
import '../../employees/services/employee_service.dart';
import '../../employees/services/employee_registration_service.dart';
import '../../shops/models/shop_model.dart';
import '../../shops/models/shop_settings_model.dart';
import '../../shops/services/shop_service.dart';
import '../../employees/pages/employees_page.dart';
import '../work_schedule_validator.dart';
import '../../../shared/dialogs/schedule_validation_dialog.dart';
import '../../employees/pages/employee_schedule_page.dart';
import '../../../shared/dialogs/auto_fill_schedule_dialog.dart';
import '../services/auto_fill_schedule_service.dart';
import '../../../shared/dialogs/shift_edit_dialog.dart';
import '../../../shared/dialogs/schedule_errors_dialog.dart';
import '../../../core/utils/cache_manager.dart';
import '../../../core/utils/disk_cache.dart';
import 'employee_bulk_schedule_dialog.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../../core/theme/app_colors.dart';
import '../widgets/employee_list_tab.dart';
import '../widgets/schedule_toolbar.dart';
import 'period_selection_dialog.dart';
import 'pdf_preview_page.dart';

/// Страница графика работы (для управления графиком сотрудников)
class WorkSchedulePage extends StatefulWidget {
  const WorkSchedulePage({super.key});

  @override
  State<WorkSchedulePage> createState() => _WorkSchedulePageState();
}

class _WorkSchedulePageState extends State<WorkSchedulePage> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  DateTime _selectedMonth = DateTime.now();
  WorkSchedule? _schedule;
  List<Employee> _employees = [];
  List<Shop> _shops = [];
  bool _isLoading = false;
  String? _error;

  // Выбор периода (числа месяца)
  int _startDay = 1;
  int _endDay = 31;

  // Кэш настроек магазинов для быстрого доступа к аббревиатурам
  Map<String, ShopSettings> _shopSettingsCache = {};

  // Валидация графика
  bool _hasErrors = false;
  int _errorCount = 0;
  ScheduleValidationResult? _validationResult;

  // Контроллеры для синхронной вертикальной прокрутки (frozen column)
  final ScrollController _namesVerticalController = ScrollController();
  final ScrollController _gridVerticalController = ScrollController();
  bool _isSyncingScroll = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(_onTabChanged);
    _loadData();
    _loadAdminUnreadCount();

    // Синхронизация вертикальной прокрутки
    _namesVerticalController.addListener(_syncNamesToGrid);
    _gridVerticalController.addListener(_syncGridToNames);
  }

  void _syncNamesToGrid() {
    if (_isSyncingScroll) return;
    if (!_gridVerticalController.hasClients) return;
    _isSyncingScroll = true;
    _gridVerticalController.jumpTo(_namesVerticalController.offset);
    _isSyncingScroll = false;
  }

  void _syncGridToNames() {
    if (_isSyncingScroll) return;
    if (!_namesVerticalController.hasClients) return;
    _isSyncingScroll = true;
    _namesVerticalController.jumpTo(_gridVerticalController.offset);
    _isSyncingScroll = false;
  }

  @override
  void dispose() {
    _tabController.removeListener(_onTabChanged);
    _tabController.dispose();
    _namesVerticalController.dispose();
    _gridVerticalController.dispose();
    super.dispose();
  }

  void _onTabChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _loadAdminUnreadCount() async {
    try {
      await ShiftTransferService.getAdminUnreadCount();
    } catch (e) {
      Logger.error('Ошибка загрузки счётчика админа', e);
    }
  }

  String get _cacheKey => 'work_schedule_${_selectedMonth.year}_${_selectedMonth.month}';

  Future<void> _loadData() async {
    // Step 1: Show memory-cached data instantly
    final cached = CacheManager.get<Map<String, dynamic>>(_cacheKey);
    if (cached != null && mounted) {
      setState(() {
        _employees = cached['employees'] as List<Employee>;
        _shops = cached['shops'] as List<Shop>;
        _schedule = cached['schedule'] as WorkSchedule?;
        _shopSettingsCache = cached['shopSettings'] as Map<String, ShopSettings>;
        _isLoading = false;
        _error = null;
      });
      _validateCurrentSchedule();
    }

    // Step 1b: If no memory cache, try disk cache (survives restart)
    if (_employees.isEmpty) {
      try {
        final diskData = await DiskCache.read(_cacheKey);
        if (diskData != null && mounted) {
          final employees = (diskData['employees'] as List<dynamic>)
              .map((e) => Employee.fromJson(e as Map<String, dynamic>))
              .toList();
          final shops = (diskData['shops'] as List<dynamic>)
              .map((s) => Shop.fromJson(s as Map<String, dynamic>))
              .toList();
          final schedule = diskData['schedule'] != null
              ? WorkSchedule.fromJson(diskData['schedule'] as Map<String, dynamic>)
              : null;
          final shopSettings = (diskData['shopSettings'] as Map<String, dynamic>?)
              ?.map((k, v) => MapEntry(k, ShopSettings.fromJson(v as Map<String, dynamic>)))
              ?? <String, ShopSettings>{};

          if (employees.isNotEmpty && mounted) {
            setState(() {
              _employees = employees;
              _shops = shops;
              _schedule = schedule;
              _shopSettingsCache = shopSettings;
              _isLoading = false;
              _error = null;
            });
            // Also put into memory cache
            CacheManager.set(_cacheKey, {
              'employees': employees,
              'shops': shops,
              'schedule': schedule,
              'shopSettings': shopSettings,
            }, duration: const Duration(minutes: 30));
            _validateCurrentSchedule();
          }
        }
      } catch (e) {
        Logger.error('Ошибка чтения дискового кэша графика', e);
      }
    }

    if (mounted && _employees.isEmpty) setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      // Step 2: Fetch fresh data from server in background
      List<Employee> employees = [];
      List<Shop> shops = [];
      WorkSchedule? schedule;

      await Future.wait([
        () async {
          try { employees = await EmployeeService.getEmployees(); }
          catch (e) { Logger.error('Ошибка загрузки сотрудников', e); }
        }(),
        () async {
          try { shops = await ShopService.getShopsForCurrentUser(); }
          catch (e) { Logger.error('Ошибка загрузки магазинов', e); }
        }(),
        () async {
          try { schedule = await WorkScheduleService.getSchedule(_selectedMonth); }
          catch (e) { Logger.error('Ошибка загрузки графика', e); }
        }(),
      ]);

      // Фильтруем только верифицированных сотрудников
      employees = await _filterVerifiedEmployees(employees);

      // Загружаем настройки магазинов (зависит от shops)
      await _loadShopSettings(shops);

      if (mounted) {
        setState(() {
          _employees = employees;
          _shops = shops;
          _schedule = schedule;
          _isLoading = false;
        });
        // Step 3: Save to memory + disk cache
        if (shops.isNotEmpty) {
          CacheManager.set(_cacheKey, {
            'employees': employees,
            'shops': shops,
            'schedule': schedule,
            'shopSettings': _shopSettingsCache,
          }, duration: const Duration(minutes: 30));
          // Persist to disk (async, don't block UI)
          DiskCache.write(_cacheKey, {
            'employees': employees.map((e) => e.toJson()).toList(),
            'shops': shops.map((s) => s.toJson()).toList(),
            'schedule': schedule?.toJson(),
            'shopSettings': _shopSettingsCache.map((k, v) => MapEntry(k, v.toJson())),
          });
        }
        // Валидация графика после загрузки
        _validateCurrentSchedule();
      }
    } catch (e) {
      if (mounted && _employees.isEmpty) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  /// Фильтрует список сотрудников, оставляя только верифицированных
  Future<List<Employee>> _filterVerifiedEmployees(List<Employee> employees) async {
    try {
      final registrations = await EmployeeRegistrationService.getAllRegistrations();
      final verifiedPhones = <String>{};
      for (var reg in registrations) {
        if (reg.isVerified) {
          verifiedPhones.add(reg.phone.replaceAll(RegExp(r'[\s\+]'), ''));
        }
      }
      return employees.where((e) {
        if (e.phone == null || e.phone!.isEmpty) return false;
        final phone = e.phone!.replaceAll(RegExp(r'[\s\+]'), '');
        return verifiedPhones.contains(phone);
      }).toList();
    } catch (e) {
      Logger.error('Ошибка фильтрации верификации', e);
      return employees; // При ошибке показываем всех
    }
  }

  Future<void> _selectMonth() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedMonth,
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
      helpText: 'Выберите месяц',
      initialDatePickerMode: DatePickerMode.year,
    );

    if (picked != null) {
      if (!mounted) return;
      setState(() {
        _selectedMonth = DateTime(picked.year, picked.month);
      });
      await _loadData();
    }
  }

  /// Показывает диалог подтверждения очистки графика
  Future<void> _confirmClearSchedule() async {
    Logger.info('🔵 _confirmClearSchedule вызван');

    if (_schedule == null || _schedule!.entries.isEmpty) {
      Logger.warning('График пуст или не загружен');
      return;
    }

    final entryCount = _schedule!.entries.length;
    final monthName = _getMonthName(_selectedMonth.month);

    Logger.info('Запрос подтверждения очистки. Записей: $entryCount, Месяц: $monthName ${_selectedMonth.year}');

    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.emeraldDark,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16.r),
          side: BorderSide(color: Colors.white.withOpacity(0.15)),
        ),
        title: Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.red, size: 32),
            SizedBox(width: 12),
            Expanded(
              child: Text('Подтвердите очистку', style: TextStyle(color: Colors.white.withOpacity(0.95))),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Вы уверены, что хотите удалить ВСЕ смены из графика?',
              style: TextStyle(
                fontSize: 16.sp,
                fontWeight: FontWeight.bold,
                color: Colors.white.withOpacity(0.9),
              ),
            ),
            SizedBox(height: 16),
            Container(
              padding: EdgeInsets.all(12.w),
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.15),
                borderRadius: BorderRadius.circular(8.r),
                border: Border.all(color: Colors.red.withOpacity(0.4)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Месяц: $monthName ${_selectedMonth.year}',
                    style: TextStyle(fontSize: 15.sp, color: Colors.white.withOpacity(0.8)),
                  ),
                  SizedBox(height: 4),
                  Text(
                    'Будет удалено смен: $entryCount',
                    style: TextStyle(
                      fontSize: 15.sp,
                      fontWeight: FontWeight.bold,
                      color: Colors.white.withOpacity(0.9),
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(height: 16),
            Text(
              '⚠️ Это действие НЕОБРАТИМО!',
              style: TextStyle(
                color: Colors.red,
                fontWeight: FontWeight.bold,
                fontSize: 15.sp,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text('Отмена', style: TextStyle(color: Colors.white.withOpacity(0.7))),
          ),
          ElevatedButton(
            onPressed: () {
              Logger.info('🔴 Кнопка "Да, очистить график" в диалоге нажата!');
              Navigator.of(context).pop(true);
              Logger.info('🔴 Navigator.pop(true) вызван');
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red[700],
              foregroundColor: Colors.white,
            ),
            child: Text('Да, очистить график'),
          ),
        ],
      ),
    );

    Logger.info('Результат подтверждения: $confirmed');

    if (confirmed == true) {
      Logger.info('Пользователь подтвердил очистку, вызываем _clearSchedule');
      await _clearSchedule();
    } else {
      Logger.info('Пользователь отменил очистку');
    }
  }

  /// Очищает график работы (удаляет все смены)
  Future<void> _clearSchedule() async {
    if (_schedule == null) return;

    try {
      // Показываем индикатор загрузки
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => Center(
          child: Card(
            color: AppColors.emeraldDark,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16.r),
              side: BorderSide(color: Colors.white.withOpacity(0.15)),
            ),
            child: Padding(
              padding: EdgeInsets.all(24.w),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(color: AppColors.gold),
                  SizedBox(height: 16),
                  Text('Очистка графика...', style: TextStyle(color: Colors.white.withOpacity(0.8))),
                ],
              ),
            ),
          ),
        ),
      );

      Logger.info('Начинаем очистку графика за ${_selectedMonth.month}.${_selectedMonth.year}');

      // Используем новый API для быстрой очистки всего месяца
      final result = await WorkScheduleService.clearMonth(_selectedMonth);

      if (result['success'] == true) {
        final deletedCount = result['deletedCount'] ?? 0;
        Logger.info('График успешно очищен. Удалено смен: $deletedCount');
      } else {
        throw Exception(result['message'] ?? 'Ошибка очистки графика');
      }

      // Закрываем диалог загрузки
      if (mounted) {
        Navigator.of(context).pop();
      }

      // Перезагружаем данные
      await _loadData();

      // Показываем сообщение об успехе
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Icon(Icons.check_circle, color: Colors.white),
                SizedBox(width: 12),
                Expanded(
                  child: Text('График успешно очищен'),
                ),
              ],
            ),
            backgroundColor: Colors.green[700],
            duration: Duration(seconds: 3),
          ),
        );

        // Переключаемся на первую вкладку (График)
        _tabController.animateTo(0);
      }
    } catch (e) {
      Logger.error('Ошибка при очистке графика', e);

      // Закрываем диалог загрузки
      if (mounted) {
        Navigator.of(context).pop();
      }

      // Показываем ошибку
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Icon(Icons.error, color: Colors.white),
                SizedBox(width: 12),
                Expanded(
                  child: Text('Ошибка при очистке графика: $e'),
                ),
              ],
            ),
            backgroundColor: Colors.red[700],
            duration: Duration(seconds: 5),
          ),
        );
      }
    }
  }

  /// Открывает диалог массового редактирования смен для сотрудника
  Future<void> _showEmployeeBulkScheduleDialog(Employee employee) async {
    Logger.info('Открытие диалога массового редактирования смен для: ${employee.name}');

    final result = await showDialog<List<WorkScheduleEntry>>(
      context: context,
      builder: (context) => EmployeeBulkScheduleDialog(
        employee: employee,
        selectedMonth: _selectedMonth,
        startDay: _startDay,
        endDay: _endDay,
        shops: _shops,
        currentSchedule: _schedule,
        shopSettingsCache: _shopSettingsCache,
      ),
    );

    if (result != null && result.isNotEmpty) {
      Logger.info('Сохранение ${result.length} смен для ${employee.name}');

      if (mounted) setState(() => _isLoading = true);

      try {
        // Сначала удаляем все старые смены сотрудника в этом периоде
        if (_schedule != null) {
          final oldEntries = _schedule!.entries.where((e) =>
            e.employeeId == employee.id &&
            e.date.month == _selectedMonth.month &&
            e.date.year == _selectedMonth.year &&
            e.date.day >= _startDay &&
            e.date.day <= _endDay
          ).toList();

          for (final oldEntry in oldEntries) {
            await WorkScheduleService.deleteShift(oldEntry.id, oldEntry.date);
          }
        }

        // Сохраняем все новые смены
        for (final entry in result) {
          await WorkScheduleService.saveShift(entry);
        }

        // Обновляем график
        await _loadData();

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Сохранено ${result.length} смен для ${employee.name}'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } catch (e) {
        Logger.error('Ошибка сохранения смен', e);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Ошибка сохранения: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      } finally {
        if (mounted) {
          setState(() => _isLoading = false);
        }
      }
    }
  }

  Future<void> _editShift(Employee employee, DateTime date) async {
    Logger.debug('_editShift вызван: ${employee.name}, ${date.day}.${date.month}.${date.year}');
    
    WorkScheduleEntry? entryToEdit;
    if (_schedule != null) {
      try {
        entryToEdit = _schedule!.entries.firstWhere(
          (e) => e.employeeId == employee.id &&
                 e.date.year == date.year &&
                 e.date.month == date.month &&
                 e.date.day == date.day,
        );
        Logger.debug('Найдена существующая запись: ${entryToEdit.id}');
      } catch (e) {
        entryToEdit = null;
        Logger.info('Запись не найдена (это нормально для новой смены)');
      }
    }

    Logger.debug('Открываем диалог редактирования смены...');
    Logger.debug('Магазинов доступно: ${_shops.length}');

    try {
      // Собираем все ошибки/предупреждения для этой ячейки
      final cellErrors = _getCellErrors(employee.id, date);

      final result = await showDialog<Map<String, dynamic>>(
        context: context,
        builder: (context) => ShiftEditDialog(
          existingEntry: entryToEdit,
          date: date,
          employee: employee,
          schedule: _schedule!,
          allEmployees: _employees,
          shops: _shops,
          cellErrors: cellErrors,
        ),
      );
      
      Logger.debug('Результат диалога: ${result != null ? result['action'] : 'отменено'}');

      if (result != null) {
        if (result['action'] == 'save') {
          final entry = result['entry'] as WorkScheduleEntry;

          // Валидация перед сохранением
          if (entry.employeeId.isEmpty) {
            Logger.error('КРИТИЧЕСКАЯ ОШИБКА: employeeId пустой!', null);
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Ошибка: не указан сотрудник'),
                  backgroundColor: Colors.red,
                ),
              );
            }
            return;
          }

          Logger.debug('Сохранение смены на сервер:');
          Logger.debug('employeeId: ${entry.employeeId}, employeeName: ${entry.employeeName}');
          Logger.debug('shopAddress: ${entry.shopAddress}, date: ${entry.date}, shiftType: ${entry.shiftType.name}');

          // Проверяем валидацию перед сохранением
          final warnings = _validateShiftBeforeSave(entry);

          // Если есть предупреждения, показываем диалог
          if (warnings.isNotEmpty) {
            final shouldSave = await _showValidationWarning(warnings);
            if (!shouldSave) {
              // Пользователь отменил сохранение
              Logger.info('Пользователь отменил сохранение из-за предупреждений');
              return;
            }
          }

          final success = await WorkScheduleService.saveShift(entry);
          if (success) {
            Logger.success('Смена успешно сохранена на сервер');
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Смена сохранена')),
              );
            }
            await _loadData();
          } else {
            Logger.error('Ошибка сохранения смены на сервер', null);
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Ошибка сохранения смены'),
                  backgroundColor: Colors.red,
                ),
              );
            }
          }
        } else if (result['action'] == 'delete') {
          final entry = result['entry'] as WorkScheduleEntry;
          Logger.debug('Удаление смены: ${entry.id}');
          final success = await WorkScheduleService.deleteShift(entry.id, entry.date);
          if (success) {
            Logger.success('Смена успешно удалена');
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Смена удалена')),
              );
            }
            await _loadData();
          } else {
            Logger.error('Ошибка удаления смены', null);
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Ошибка удаления смены'),
                  backgroundColor: Colors.red,
                ),
              );
            }
          }
        }
      }
    } catch (e) {
      Logger.error('Ошибка при редактировании смены', e);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// Валидация текущего графика
  void _validateCurrentSchedule() {
    if (_schedule == null || _shops.isEmpty) {
      if (mounted) setState(() {
        _hasErrors = false;
        _errorCount = 0;
        _validationResult = null;
      });
      return;
    }

    final startDate = DateTime(_selectedMonth.year, _selectedMonth.month, _startDay);
    final lastDayOfMonth = DateTime(_selectedMonth.year, _selectedMonth.month + 1, 0).day;
    final actualEndDay = _endDay > lastDayOfMonth ? lastDayOfMonth : _endDay;
    final endDate = DateTime(_selectedMonth.year, _selectedMonth.month, actualEndDay);

    _validationResult = WorkScheduleValidator.validateSchedule(
      _schedule!,
      startDate,
      endDate,
      _shops,
    );

    if (mounted) setState(() {
      _hasErrors = _validationResult!.hasErrors;
      _errorCount = _validationResult!.totalCount;
    });

    Logger.debug('Валидация графика: найдено $_errorCount ошибок');
  }

  /// Показать диалог ошибок
  Future<void> _showErrorsDialog() async {
    if (_validationResult == null) {
      _validateCurrentSchedule();
    }

    if (!_hasErrors) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Ошибок в графике не найдено! ✓'),
          backgroundColor: Colors.green,
        ),
      );
      return;
    }

    await showDialog(
      context: context,
      builder: (context) => ScheduleErrorsDialog(
        validationResult: _validationResult!,
        onErrorTap: (error) => _handleErrorTap(error),
      ),
    );
  }

  /// Обработка клика на ошибку в диалоге
  Future<void> _handleErrorTap(ScheduleError error) async {
    Employee? employee;

    if (error.employeeName != null) {
      // Находим сотрудника по имени
      try {
        employee = _employees.firstWhere(
          (e) => e.name == error.employeeName,
        );
      } catch (e) {
        employee = _employees.isNotEmpty ? _employees.first : null;
      }
    } else {
      // Для отсутствующих смен - выбираем первого сотрудника
      employee = _employees.isNotEmpty ? _employees.first : null;
    }

    if (employee == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Не удалось найти сотрудника'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    // Определяем требуемый тип смены на основе ошибки
    ShiftType? requiredShiftType;
    switch (error.type) {
      case ScheduleErrorType.missingMorning:
        requiredShiftType = ShiftType.morning;
        break;
      case ScheduleErrorType.missingEvening:
        requiredShiftType = ShiftType.evening;
        break;
      case ScheduleErrorType.duplicateMorning:
        requiredShiftType = ShiftType.morning;
        break;
      case ScheduleErrorType.duplicateEvening:
        requiredShiftType = ShiftType.evening;
        break;
      case ScheduleErrorType.morningAfterEvening:
      case ScheduleErrorType.eveningAfterMorning:
      case ScheduleErrorType.dayAfterEvening:
        // Для конфликтов используем тип смены из ошибки, если указан
        requiredShiftType = error.shiftType;
        break;
    }

    // Находим магазин по адресу из ошибки
    Shop? requiredShop;
    try {
      requiredShop = _shops.firstWhere(
        (shop) => shop.address == error.shopAddress,
      );
    } catch (e) {
      Logger.error('Магазин не найден по адресу: ${error.shopAddress}', e);
      requiredShop = null;
    }

    // Открываем диалог редактирования с заблокированными полями
    await _editShiftNew(
      employee,
      error.date,
      requiredShiftType: requiredShiftType,
      requiredShop: requiredShop,
    );
  }

  /// Новый метод редактирования смены с использованием ShiftEditDialog
  Future<void> _editShiftNew(
    Employee employee,
    DateTime date, {
    ShiftType? requiredShiftType,
    Shop? requiredShop,
  }) async {
    WorkScheduleEntry? existingEntry;
    if (_schedule != null) {
      try {
        // Если указан требуемый тип смены, ищем запись с этим типом
        if (requiredShiftType != null) {
          existingEntry = _schedule!.entries.firstWhere(
            (e) => e.employeeId == employee.id &&
                   e.date.year == date.year &&
                   e.date.month == date.month &&
                   e.date.day == date.day &&
                   e.shiftType == requiredShiftType,
          );
        } else {
          // Если тип смены не указан, ищем любую запись этого сотрудника на эту дату
          existingEntry = _schedule!.entries.firstWhere(
            (e) => e.employeeId == employee.id &&
                   e.date.year == date.year &&
                   e.date.month == date.month &&
                   e.date.day == date.day,
          );
        }
      } catch (e) {
        existingEntry = null;
      }
    }

    final cellErrors = _getCellErrors(employee.id, date);

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => ShiftEditDialog(
        existingEntry: existingEntry,
        date: date,
        employee: employee,
        schedule: _schedule!,
        allEmployees: _employees,
        shops: _shops,
        requiredShiftType: requiredShiftType,
        requiredShop: requiredShop,
        cellErrors: cellErrors,
      ),
    );

    if (result == null) return;

    final action = result['action'] as String?;
    final entry = result['entry'] as WorkScheduleEntry?;

    if (action == 'save' && entry != null) {
      // Проверяем валидацию перед сохранением
      final warnings = _validateShiftBeforeSave(entry);
      if (warnings.isNotEmpty) {
        final shouldSave = await _showValidationWarning(warnings);
        if (!shouldSave) {
          return;
        }
      }

      final success = await WorkScheduleService.saveShift(entry);
      if (success) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Смена сохранена')),
          );
        }
        await _loadData();
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Ошибка сохранения смены'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } else if (action == 'delete' && entry != null) {
      // Проверяем что ID не пустой
      if (entry.id.isEmpty) {
        Logger.error('Попытка удалить смену с пустым ID', null);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Ошибка: ID смены не найден'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }

      Logger.debug('Удаление смены: ID=${entry.id}, сотрудник=${entry.employeeName}, дата=${entry.date}');
      final success = await WorkScheduleService.deleteShift(entry.id, entry.date);
      if (success) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Смена удалена')),
          );
        }
        await _loadData();
      } else {
        Logger.error('Не удалось удалить смену: ID=${entry.id}', null);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Ошибка удаления смены'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  /// Получить ошибку для конкретной ячейки
  ScheduleError? _getCellError(String employeeId, DateTime day) {
    final errors = _getCellErrors(employeeId, day);
    return errors.isNotEmpty ? errors.first : null;
  }

  /// Получить ВСЕ ошибки и предупреждения для ячейки
  List<ScheduleError> _getCellErrors(String employeeId, DateTime day) {
    if (_validationResult == null) return [];

    final result = <ScheduleError>[];
    final emp = _employees.firstWhere(
      (e) => e.id == employeeId,
      orElse: () => Employee(id: '', name: ''),
    );
    if (emp.name.isEmpty) return [];

    // Критичные ошибки
    for (var error in _validationResult!.criticalErrors) {
      if (error.date.year == day.year &&
          error.date.month == day.month &&
          error.date.day == day.day &&
          error.employeeName != null &&
          emp.name == error.employeeName) {
        result.add(error);
      }
    }

    // Предупреждения
    for (var warning in _validationResult!.warnings) {
      if (warning.date.year == day.year &&
          warning.date.month == day.month &&
          warning.date.day == day.day &&
          warning.employeeName != null &&
          emp.name == warning.employeeName) {
        result.add(warning);
      }
    }

    return result;
  }

  List<DateTime> _getDaysInMonth() {
    final lastDay = DateTime(_selectedMonth.year, _selectedMonth.month + 1, 0);
    final maxDay = lastDay.day;
    final actualStartDay = _startDay.clamp(1, maxDay);
    final actualEndDay = _endDay.clamp(actualStartDay, maxDay);
    
    final days = <DateTime>[];
    for (var i = actualStartDay; i <= actualEndDay; i++) {
      days.add(DateTime(_selectedMonth.year, _selectedMonth.month, i));
    }
    return days;
  }
  
  Future<void> _loadShopSettings(List<Shop> shops) async {
    final Map<String, ShopSettings> settingsCache = {};

    for (var shop in shops) {
      try {
        final settings = await ShopService.getShopSettings(shop.address);
        if (settings != null) {
          settingsCache[shop.address] = settings;
        }
      } catch (e) {
        Logger.error('Ошибка загрузки настроек для магазина ${shop.address}', e);
      }
    }

    if (mounted) {
      setState(() {
        _shopSettingsCache = settingsCache;
      });
    }
  }
  
  String? _getAbbreviationForEntry(WorkScheduleEntry entry) {
    final settings = _shopSettingsCache[entry.shopAddress];
    if (settings == null) return null;
    
    switch (entry.shiftType) {
      case ShiftType.morning:
        return settings.morningAbbreviation;
      case ShiftType.day:
        return settings.dayAbbreviation;
      case ShiftType.evening:
        return settings.nightAbbreviation;
    }
  }
  
  Future<void> _selectPeriod() async {
    final maxDay = DateTime(_selectedMonth.year, _selectedMonth.month + 1, 0).day;
    final result = await showDialog<Map<String, int>>(
      context: context,
      builder: (context) => PeriodSelectionDialog(
        startDay: _startDay,
        endDay: _endDay,
        maxDay: maxDay,
      ),
    );
    
    if (result != null) {
      if (mounted) setState(() {
        _startDay = result['startDay'] ?? 1;
        _endDay = result['endDay'] ?? maxDay;
      });
    }
  }

  WorkScheduleEntry? _getEntryForEmployeeAndDate(String employeeId, DateTime date) {
    if (_schedule == null) return null;
    
    // Используем hasEntry для проверки, чтобы избежать исключений
    if (!_schedule!.hasEntry(employeeId, date)) {
      return null;
    }
    
    try {
      return _schedule!.getEntry(employeeId, date);
    } catch (e) {
      // Если все же произошла ошибка, ищем вручную
      try {
        final dateStr = '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
        return _schedule!.entries.firstWhere(
          (e) => e.employeeId == employeeId && 
                 e.date.toIso8601String().split('T')[0] == dateStr,
        );
      } catch (e2) {
        return null;
      }
    }
  }

  /// Проверяет валидность дня по правилу 1 (наличие утренней и вечерней смен на всех магазинах)
  bool _isDayValid(DateTime day) {
    if (_schedule == null || _shops.isEmpty) return false;
    return WorkScheduleValidator.isDayComplete(day, _shops, _schedule!);
  }

  /// Проверяет конфликты перед сохранением смены
  List<String> _validateShiftBeforeSave(WorkScheduleEntry entry) {
    if (_schedule == null) return [];
    return WorkScheduleValidator.checkShiftConflict(entry, _schedule!);
  }

  /// Показывает диалог с предупреждениями валидации
  Future<bool> _showValidationWarning(List<String> warnings) async {
    if (warnings.isEmpty) return true;
    
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => ScheduleValidationDialog(warnings: warnings),
    );
    
    return result ?? false;
  }

  /// Создаёт кастомную вкладку в стиле Dark Emerald
  Widget _buildCustomTab(int index, IconData icon, String label) {
    final isSelected = _tabController.index == index;
    return Expanded(
      child: GestureDetector(
        onTap: () {
          _tabController.animateTo(index);
          if (mounted) setState(() {});
        },
        child: Container(
          padding: EdgeInsets.symmetric(vertical: 10.h),
          decoration: BoxDecoration(
            color: isSelected ? AppColors.gold.withOpacity(0.2) : Colors.white.withOpacity(0.06),
            borderRadius: BorderRadius.circular(12.r),
            border: Border.all(
              color: isSelected ? AppColors.gold.withOpacity(0.5) : Colors.white.withOpacity(0.1),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 18, color: isSelected ? AppColors.gold : Colors.white.withOpacity(0.6)),
              SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 14.sp,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                  color: isSelected ? AppColors.gold : Colors.white.withOpacity(0.6),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Состояние ошибки
  Widget _buildErrorState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: EdgeInsets.all(24.w),
            decoration: BoxDecoration(
              color: AppColors.emerald.withOpacity(0.3),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.error_outline, size: 64, color: Colors.red.withOpacity(0.7)),
          ),
          SizedBox(height: 20),
          Text(
            'Ошибка: $_error',
            style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 14.sp),
            textAlign: TextAlign.center,
          ),
          SizedBox(height: 16),
          ElevatedButton(
            onPressed: _loadData,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.emerald,
              foregroundColor: Colors.white,
            ),
            child: Text('Повторить'),
          ),
        ],
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
              Padding(
                padding: EdgeInsets.fromLTRB(8.w, 8.h, 8.w, 0),
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
                        child: Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white.withOpacity(0.8), size: 20),
                      ),
                    ),
                    Expanded(
                      child: Center(
                        child: Text(
                          'График работы',
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.95),
                            fontSize: 18.sp,
                            fontWeight: FontWeight.w400,
                            letterSpacing: 1,
                          ),
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
                        child: Icon(Icons.refresh, color: Colors.white.withOpacity(0.8), size: 20),
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(height: 12.h),
              // Custom Tabs
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 16.w),
                child: Row(
                  children: [
                    _buildCustomTab(0, Icons.calendar_month, 'График'),
                    SizedBox(width: 8),
                    _buildCustomTab(1, Icons.people_alt, 'Сотрудники'),
                  ],
                ),
              ),
              SizedBox(height: 12.h),
              // Body
              Expanded(
                child: _isLoading
                    ? Center(child: CircularProgressIndicator(color: AppColors.gold, strokeWidth: 3))
                    : _error != null
                        ? _buildErrorState()
                        : Column(
                            children: [
                              ScheduleToolbar(
                                hasSchedule: _schedule != null,
                                onSelectPeriod: _selectPeriod,
                                onSelectMonth: _selectMonth,
                                onAutoFill: _showAutoFillDialog,
                                onExportPdf: _exportToPdf,
                                onClear: _confirmClearSchedule,
                              ),
                              Expanded(
                                child: TabBarView(
                                  controller: _tabController,
                                  children: [
                                    _schedule == null
                                        ? Center(child: Text('График не загружен', style: TextStyle(color: Colors.white.withOpacity(0.5))))
                                        : _buildCalendarGrid(),
                                    EmployeeListTab(
                                      employees: _employees,
                                      schedule: _schedule,
                                      selectedMonth: _selectedMonth,
                                      onEmployeeTap: _showEmployeeScheduleDialog,
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
              ),
            ],
          ),
        ),
      ),
      floatingActionButton: _schedule != null
          ? FloatingActionButton(
              onPressed: _showErrorsDialog,
              backgroundColor: _hasErrors ? Colors.red : AppColors.emerald,
              foregroundColor: Colors.white,
              child: Badge(
                label: Text('$_errorCount'),
                isLabelVisible: _hasErrors,
                child: Icon(Icons.error_outline),
              ),
            )
          : null,
    );
  }

  Widget _buildCalendarGrid() {
    final days = _getDaysInMonth();
    final employeesByShop = <String, List<Employee>>{};

    // Группируем сотрудников по магазинам (если есть информация о магазине)
    // Пока просто группируем всех вместе
    employeesByShop['Все сотрудники'] = _employees;

    // Подсчёт общего количества смен
    final totalShifts = _schedule?.entries.length ?? 0;

    return Column(
      children: [
        // Компактный заголовок с месяцем и периодом
        Container(
          padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 8.h),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [AppColors.emerald, AppColors.emeraldDark],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: Row(
            children: [
              Icon(
                Icons.calendar_month,
                color: AppColors.gold,
                size: 20,
              ),
              SizedBox(width: 10),
              Text(
                '${_getMonthName(_selectedMonth.month)} ${_selectedMonth.year}',
                style: TextStyle(
                  fontSize: 16.sp,
                  fontWeight: FontWeight.bold,
                  color: Colors.white.withOpacity(0.95),
                ),
              ),
              SizedBox(width: 16),
              Text(
                'Период: $_startDay - $_endDay',
                style: TextStyle(
                  fontSize: 12.sp,
                  color: Colors.white.withOpacity(0.6),
                ),
              ),
              SizedBox(width: 8),
              // Компактная статистика
              Flexible(
                child: Text(
                  '${_employees.length} сотр. | $totalShifts смен | ${_shops.length} маг.',
                  style: TextStyle(
                    fontSize: 11.sp,
                    color: Colors.white.withOpacity(0.5),
                  ),
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.right,
                ),
              ),
            ],
          ),
        ),
        // Календарная сетка с фиксированной колонкой имён
        Expanded(
          child: Row(
            children: [
              // Фиксированная колонка с именами сотрудников
              SizedBox(
                width: 140,
                child: Column(
                  children: [
                    // Заголовок "Сотрудник"
                    Container(
                      height: 48,
                      decoration: BoxDecoration(
                        color: AppColors.emeraldDark,
                        border: Border(
                          bottom: BorderSide(color: Colors.white.withOpacity(0.1), width: 2),
                          right: BorderSide(color: Colors.white.withOpacity(0.1), width: 2),
                        ),
                      ),
                      child: Center(
                        child: Text(
                          'Сотрудник',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13.sp,
                            color: Colors.white.withOpacity(0.9),
                          ),
                        ),
                      ),
                    ),
                    // Список имён сотрудников (ListView.builder — ленивый рендер)
                    Expanded(
                      child: ListView.builder(
                        controller: _namesVerticalController,
                        itemCount: _employees.length,
                        itemExtent: 40,
                        itemBuilder: (context, index) {
                          final employee = _employees[index];
                          final isEven = index % 2 == 0;
                          return InkWell(
                            onTap: () => _showEmployeeBulkScheduleDialog(employee),
                            child: Container(
                              height: 40,
                              decoration: BoxDecoration(
                                color: isEven ? Colors.white.withOpacity(0.04) : Colors.white.withOpacity(0.08),
                                border: Border(
                                  bottom: BorderSide(color: Colors.white.withOpacity(0.06)),
                                  right: BorderSide(color: Colors.white.withOpacity(0.1), width: 2),
                                ),
                              ),
                              padding: EdgeInsets.symmetric(horizontal: 8.w),
                              alignment: Alignment.centerLeft,
                              child: Text(
                                employee.name,
                                style: TextStyle(
                                  fontSize: 12.sp,
                                  color: Colors.white.withOpacity(0.9),
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
              // Скроллируемая часть с датами и ячейками
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: SizedBox(
                    width: days.length * 70.0,
                    child: Column(
                      children: [
                        // Заголовок с датами
                        Container(
                          height: 48,
                          decoration: BoxDecoration(
                            color: AppColors.emeraldDark,
                            border: Border(
                              bottom: BorderSide(color: Colors.white.withOpacity(0.1), width: 2),
                            ),
                          ),
                          child: Row(
                            children: days.map((day) {
                              final isValid = _isDayValid(day);
                              final isWeekend = day.weekday == 6 || day.weekday == 7;
                              return Container(
                                width: 70,
                                decoration: BoxDecoration(
                                  color: isValid
                                      ? AppColors.emerald.withOpacity(0.6)
                                      : isWeekend
                                          ? AppColors.emeraldDark.withOpacity(0.8)
                                          : AppColors.emeraldDark,
                                  border: Border(
                                    right: BorderSide(color: Colors.white.withOpacity(0.06)),
                                  ),
                                ),
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Text(
                                      '${day.day}',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 14.sp,
                                        color: isWeekend ? Colors.red.withOpacity(0.7) : Colors.white.withOpacity(0.9),
                                      ),
                                    ),
                                    Text(
                                      _getWeekdayName(day.weekday),
                                      style: TextStyle(
                                        fontSize: 10.sp,
                                        color: isWeekend ? Colors.red.withOpacity(0.5) : Colors.white.withOpacity(0.5),
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            }).toList(),
                          ),
                        ),
                        // Ячейки со сменами (ListView.builder — ленивый рендер)
                        Expanded(
                          child: ListView.builder(
                            controller: _gridVerticalController,
                            itemCount: _employees.length,
                            itemExtent: 40,
                            itemBuilder: (context, index) {
                              final employee = _employees[index];
                              return SizedBox(
                                height: 40,
                                child: Row(
                                  children: days.map((day) => _buildCell(employee, day)).toList(),
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildCell(Employee employee, DateTime date) {
    final entry = _getEntryForEmployeeAndDate(employee.id, date);
    final isEmpty = entry == null;
    final abbreviation = entry != null ? _getAbbreviationForEntry(entry) : null;
    final employeeIndex = _employees.indexWhere((e) => e.id == employee.id);
    final isEven = employeeIndex % 2 == 0;

    // Получаем ошибку для ячейки из результата валидации
    final cellError = _getCellError(employee.id, date);
    final hasError = cellError != null;

    Color? borderColor;
    Widget? errorIcon;

    if (hasError) {
      if (cellError.isCritical) {
        // Критичная ошибка: красная рамка
        borderColor = Colors.red;
        errorIcon = Icon(Icons.error, color: Colors.red, size: 12);
      } else {
        // Предупреждение: оранжевая рамка
        borderColor = Colors.orange;
        errorIcon = Icon(Icons.warning, color: Colors.orange, size: 12);
      }
    }

    // Цвета фона для смен (тёмные тонированные)
    Color getCellBackgroundColor(ShiftType type) {
      switch (type) {
        case ShiftType.morning:
          return AppColors.successLight.withOpacity(0.3); // зелёный
        case ShiftType.day:
          return Color(0xFFFFF176).withOpacity(0.25); // жёлтый
        case ShiftType.evening:
          return Color(0xFFBDBDBD).withOpacity(0.2); // серый
      }
    }

    return InkWell(
      onTap: () {
        Logger.debug('Клик по клетке: ${employee.name}, ${date.day}.${date.month}.${date.year}');
        _editShift(employee, date);
      },
      child: Container(
        width: 70,
        height: 40,
        decoration: BoxDecoration(
          color: isEmpty
              ? (isEven ? Colors.white.withOpacity(0.02) : Colors.white.withOpacity(0.05))
              : getCellBackgroundColor(entry.shiftType),
          border: Border.all(
            color: hasError
                ? borderColor!
                : (isEmpty ? Colors.white.withOpacity(0.08) : entry.shiftType.color.withOpacity(0.3)),
            width: hasError ? 2.0 : (isEmpty ? 0.5 : 1.0),
          ),
        ),
        child: isEmpty
            ? SizedBox()
            : Stack(
                children: [
                  Center(
                    child: Padding(
                      padding: EdgeInsets.symmetric(horizontal: 2.0.w),
                      child: Text(
                        abbreviation ?? entry.shiftType.label,
                        style: TextStyle(
                          fontSize: 11.sp,
                          fontWeight: FontWeight.bold,
                          color: Colors.white.withOpacity(0.95),
                        ),
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                  // Иконка ошибки/предупреждения
                  if (errorIcon != null)
                    Positioned(
                      top: 1.h,
                      right: 1.w,
                      child: Container(
                        padding: EdgeInsets.all(1.w),
                        decoration: BoxDecoration(
                          color: AppColors.night.withOpacity(0.7),
                          shape: BoxShape.circle,
                        ),
                        child: errorIcon,
                      ),
                    ),
                ],
              ),
      ),
    );
  }

  String _getMonthName(int month) {
    final months = [
      'Январь',
      'Февраль',
      'Март',
      'Апрель',
      'Май',
      'Июнь',
      'Июль',
      'Август',
      'Сентябрь',
      'Октябрь',
      'Ноябрь',
      'Декабрь',
    ];
    return months[month - 1];
  }

  String _getWeekdayName(int weekday) {
    final weekdays = ['Пн', 'Вт', 'Ср', 'Чт', 'Пт', 'Сб', 'Вс'];
    return weekdays[weekday - 1];
  }

  /// Показывает диалог автозаполнения
  Future<void> _showAutoFillDialog() async {
    Logger.info('📋 Нажата кнопка автозаполнения');
    Logger.debug('   График: ${_schedule != null ? "загружен (${_schedule!.entries.length} записей)" : "не загружен"}');
    Logger.debug('   Сотрудников: ${_employees.length}');
    Logger.debug('   Магазинов: ${_shops.length}');

    if (_schedule == null || _employees.isEmpty || _shops.isEmpty) {
      Logger.warning('⚠️ Недостаточно данных для автозаполнения');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Необходимо загрузить график, сотрудников и магазины'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    Logger.info('✅ Все данные загружены, показываем диалог автозаполнения');

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => AutoFillScheduleDialog(
        selectedMonth: _selectedMonth,
        startDay: _startDay,
        endDay: _endDay,
        schedule: _schedule,
        employees: _employees,
        shops: _shops,
        shopSettingsCache: _shopSettingsCache,
      ),
    );

    Logger.info('📥 Диалог закрыт, результат: ${result != null ? "получен" : "null"}');

    if (result != null) {
      Logger.debug('   startDay: ${result['startDay']}, endDay: ${result['endDay']}, replace: ${result['replaceExisting']}');
      await _performAutoFill(result);
    } else {
      Logger.warning('⚠️ Результат диалога = null, автозаполнение не выполнено');
    }
  }

  /// Экспортирует график в PDF
  Future<void> _exportToPdf() async {
    if (_schedule == null || _schedule!.entries.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Нет данных для экспорта'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    // Показываем индикатор загрузки
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => Center(
        child: Card(
          color: AppColors.emeraldDark,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16.r),
            side: BorderSide(color: Colors.white.withOpacity(0.15)),
          ),
          child: Padding(
            padding: EdgeInsets.all(20.w),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(color: AppColors.gold),
                SizedBox(height: 16),
                Text('Создание PDF...', style: TextStyle(color: Colors.white.withOpacity(0.8))),
              ],
            ),
          ),
        ),
      ),
    );

    try {
      // Собираем уникальные имена сотрудников
      final employeeNames = _schedule!.entries
          .map((e) => e.employeeName)
          .toSet()
          .toList()
        ..sort();

      // Собираем аббревиатуры из кэша настроек магазинов
      final abbreviations = <String, Map<ShiftType, String>>{};
      for (final entry in _shopSettingsCache.entries) {
        final shopAddress = entry.key;
        final settings = entry.value;
        abbreviations[shopAddress] = {
          ShiftType.morning: settings.morningAbbreviation ?? 'У',
          ShiftType.day: settings.dayAbbreviation ?? 'Д',
          ShiftType.evening: settings.nightAbbreviation ?? 'В',
        };
      }

      // Генерируем PDF
      final pdfBytes = await SchedulePdfService.generateSchedulePdf(
        schedule: _schedule!,
        employeeNames: employeeNames,
        month: _selectedMonth,
        startDay: _startDay,
        endDay: _endDay,
        abbreviations: abbreviations.isNotEmpty ? abbreviations : null,
      );

      if (mounted) Navigator.pop(context); // Закрываем индикатор

      // Открываем страницу предпросмотра
      final monthNames = [
        'Январь', 'Февраль', 'Март', 'Апрель', 'Май', 'Июнь',
        'Июль', 'Август', 'Сентябрь', 'Октябрь', 'Ноябрь', 'Декабрь'
      ];
      final fileName = 'График_${monthNames[_selectedMonth.month - 1]}_${_selectedMonth.year}.pdf';

      if (mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => SchedulePdfPreviewPage(
              pdfBytes: pdfBytes,
              fileName: fileName,
              title: 'График - ${monthNames[_selectedMonth.month - 1]} ${_selectedMonth.year}',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) Navigator.pop(context);
      Logger.error('Ошибка создания PDF', e);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка создания PDF: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// Выполняет автозаполнение графика
  Future<void> _performAutoFill(Map<String, dynamic> options) async {
    final startDay = options['startDay'] as int;
    final endDay = options['endDay'] as int;
    final replaceExisting = options['replaceExisting'] as bool;

    Logger.info('🔄 Начало автозаполнения: с $startDay по $endDay, заменить=$replaceExisting');
    Logger.debug('   Сотрудников: ${_employees.length}, Магазинов: ${_shops.length}');

    // Показываем индикатор загрузки
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => Center(
        child: Card(
          color: AppColors.emeraldDark,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16.r),
            side: BorderSide(color: Colors.white.withOpacity(0.15)),
          ),
          child: Padding(
            padding: EdgeInsets.all(20.w),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(color: AppColors.gold),
                SizedBox(height: 16),
                Text('Выполняется автозаполнение...', style: TextStyle(color: Colors.white.withOpacity(0.8))),
              ],
            ),
          ),
        ),
      ),
    );

    try {
      // Вычисляем даты начала и конца периода
      final startDate = DateTime(_selectedMonth.year, _selectedMonth.month, startDay);
      final endDate = DateTime(_selectedMonth.year, _selectedMonth.month, endDay);

      // ОПТИМИЗАЦИЯ: Не удаляем смены здесь, AutoFillScheduleService сам фильтрует существующие
      // при replaceExisting=true (строки 35-40 в auto_fill_schedule_service.dart)

      // Выполняем автозаполнение
      final autoFillResult = await AutoFillScheduleService.autoFill(
        startDate: startDate,
        endDate: endDate,
        employees: _employees,
        shops: _shops,
        existingSchedule: _schedule,
        replaceExisting: replaceExisting,
      );

      final newEntries = autoFillResult.entries;
      final autoFillWarnings = autoFillResult.warnings;

      Logger.info('🔄 Автозаполнение создало ${newEntries.length} записей, предупреждений: ${autoFillWarnings.length}');

      // Сохраняем новые смены батчами по 50 записей
      if (newEntries.isNotEmpty) {
        final batchSize = 50;
        int savedCount = 0;

        for (int i = 0; i < newEntries.length; i += batchSize) {
          final batch = newEntries.skip(i).take(batchSize).toList();

          // В первый батч передаём параметры замены
          final success = i == 0 && replaceExisting
              ? await WorkScheduleService.bulkCreateShifts(
                  batch,
                  replaceMode: 'all',
                  startDate: startDate,
                  endDate: endDate,
                )
              : await WorkScheduleService.bulkCreateShifts(batch);

          if (success) {
            savedCount += batch.length;
          } else {
            // Если батч не сохранился, пробуем сохранить по одной
            for (var entry in batch) {
              await WorkScheduleService.saveShift(entry);
              savedCount++;
            }
          }

          // Небольшая задержка между батчами
          await Future.delayed(Duration(milliseconds: 100));
        }

        Logger.success('Сохранено смен: $savedCount из ${newEntries.length}');
      }

      // Закрываем индикатор загрузки
      if (mounted) {
        Navigator.of(context).pop();
      }

      // Обновляем график - принудительно перезагружаем данные
      if (!mounted) return;
      setState(() {
        _isLoading = true;
      });

      await _loadData();

      // Дополнительная проверка - загружаем график еще раз для уверенности
      try {
        final refreshedSchedule = await WorkScheduleService.getSchedule(_selectedMonth);
        if (mounted) {
          setState(() {
            _schedule = refreshedSchedule;
            _isLoading = false;
          });
        }
      } catch (e) {
        Logger.error('Ошибка при обновлении графика', e);
        if (mounted) {
          setState(() {
            _isLoading = false;
          });
        }
      }

      // Показываем результаты
      if (mounted) {
        _showAutoFillResults(newEntries.length, autoFillWarnings);
      }
    } catch (e) {
      // Закрываем индикатор загрузки
      if (mounted) {
        Navigator.of(context).pop();
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка автозаполнения: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// Показывает результаты автозаполнения
  void _showAutoFillResults(int entriesCount, List<String> warnings) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.emeraldDark,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16.r),
          side: BorderSide(color: Colors.white.withOpacity(0.15)),
        ),
        title: Text('Автозаполнение завершено', style: TextStyle(color: Colors.white.withOpacity(0.95))),
        content: SizedBox(
          width: MediaQuery.of(context).size.width * 0.8,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Создано смен: $entriesCount',
                style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 16.sp),
              ),
              if (warnings.isNotEmpty) ...[
                SizedBox(height: 12),
                Text(
                  'Предупреждения (${warnings.length}):',
                  style: TextStyle(
                    color: Colors.orange,
                    fontSize: 14.sp,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                SizedBox(height: 8),
                ConstrainedBox(
                  constraints: BoxConstraints(maxHeight: 200),
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: warnings.length,
                    itemBuilder: (context, index) => Padding(
                      padding: EdgeInsets.only(bottom: 4.h),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.warning, color: Colors.orange, size: 14),
                          SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              warnings[index],
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.6),
                                fontSize: 12.sp,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text('ОК', style: TextStyle(color: AppColors.gold)),
          ),
        ],
      ),
    );
  }

  // Removed dead code: _buildAdminNotificationCard, _buildDetailRow,
  // _approveRequest, _declineRequest, _buildClearStatItem (no call sites)

  /// Показывает диалог со списком смен сотрудника
  void _showEmployeeScheduleDialog(Employee employee) {
    final employeeEntries = _schedule?.entries
        .where((e) => e.employeeId == employee.id)
        .toList() ?? [];

    // Сортируем по дате
    employeeEntries.sort((a, b) => a.date.compareTo(b.date));

    // Фильтруем по выбранному периоду
    final filteredEntries = employeeEntries.where((e) =>
      e.date.day >= _startDay && e.date.day <= _endDay
    ).toList();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.emeraldDark,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16.r),
          side: BorderSide(color: Colors.white.withOpacity(0.15)),
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(
                'График: ${employee.name}',
                style: TextStyle(fontSize: 18.sp, color: Colors.white.withOpacity(0.95)),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            IconButton(
              icon: Icon(Icons.close, color: Colors.white.withOpacity(0.7)),
              onPressed: () => Navigator.pop(context),
            ),
          ],
        ),
        content: SizedBox(
          width: MediaQuery.of(context).size.width * 0.85,
          height: MediaQuery.of(context).size.height * 0.5,
          child: filteredEntries.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.event_busy, size: 64, color: Colors.white.withOpacity(0.3)),
                      SizedBox(height: 16),
                      Text(
                        'Нет смен в выбранном периоде',
                        style: TextStyle(fontSize: 16.sp, color: Colors.white.withOpacity(0.5)),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  shrinkWrap: true,
                  itemCount: filteredEntries.length,
                  itemBuilder: (context, index) {
                    final entry = filteredEntries[index];
                    final shop = _shops.firstWhere(
                      (s) => s.address == entry.shopAddress,
                      orElse: () => Shop(
                        id: '',
                        name: entry.shopAddress,
                        address: entry.shopAddress,
                        icon: Icons.store,
                      ),
                    );
                    final weekday = _getWeekdayName(entry.date.weekday);

                    return Container(
                      margin: EdgeInsets.only(bottom: 8.h),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.06),
                        borderRadius: BorderRadius.circular(10.r),
                        border: Border.all(color: Colors.white.withOpacity(0.1)),
                      ),
                      child: ListTile(
                        leading: Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            color: entry.shiftType.color.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(8.r),
                            border: Border.all(
                              color: entry.shiftType.color.withOpacity(0.5),
                              width: 1,
                            ),
                          ),
                          child: Center(
                            child: Text(
                              '${entry.date.day}',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: entry.shiftType.color,
                                fontSize: 18.sp,
                              ),
                            ),
                          ),
                        ),
                        title: Text(
                          '$weekday, ${entry.date.day}.${entry.date.month.toString().padLeft(2, '0')}',
                          style: TextStyle(fontWeight: FontWeight.w600, color: Colors.white.withOpacity(0.9)),
                        ),
                        subtitle: Text(
                          shop.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: Colors.white.withOpacity(0.5)),
                        ),
                        trailing: Container(
                          padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 6.h),
                          decoration: BoxDecoration(
                            color: entry.shiftType.color.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(16.r),
                            border: Border.all(
                              color: entry.shiftType.color.withOpacity(0.3),
                            ),
                          ),
                          child: Text(
                            entry.shiftType.label,
                            style: TextStyle(
                              color: entry.shiftType.color,
                              fontWeight: FontWeight.w600,
                              fontSize: 12.sp,
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Закрыть', style: TextStyle(color: Colors.white.withOpacity(0.7))),
          ),
          ElevatedButton.icon(
            onPressed: () {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => EmployeeSchedulePage(
                    employee: employee,
                    selectedMonth: _selectedMonth,
                    startDay: _startDay,
                    endDay: _endDay,
                    shops: _shops,
                    schedule: _schedule,
                    shopSettingsCache: _shopSettingsCache,
                    onScheduleUpdated: () => _loadData(),
                  ),
                ),
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.emerald,
              foregroundColor: Colors.white,
            ),
            icon: Icon(Icons.edit),
            label: Text('Редактировать'),
          ),
        ],
      ),
    );
  }

}
