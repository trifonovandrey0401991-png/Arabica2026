import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../features/work_schedule/models/work_schedule_model.dart';
import '../../features/work_schedule/work_schedule_validator.dart';
import '../../features/employees/pages/employees_page.dart';
import '../../features/shops/models/shop_model.dart';
import '../../features/shops/models/shop_settings_model.dart';
import '../../features/shops/services/shop_service.dart';
import '../../core/utils/logger.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

/// Диалог редактирования смены — полноэкранный, тёмная тема
class ShiftEditDialog extends StatefulWidget {
  final WorkScheduleEntry? existingEntry;
  final DateTime date;
  final Employee employee;
  final WorkSchedule schedule;
  final List<Employee> allEmployees;
  final List<Shop> shops;
  final ShiftType? requiredShiftType;
  final Shop? requiredShop;
  final List<ScheduleError> cellErrors;

  const ShiftEditDialog({
    super.key,
    this.existingEntry,
    required this.date,
    required this.employee,
    required this.schedule,
    required this.allEmployees,
    required this.shops,
    this.requiredShiftType,
    this.requiredShop,
    this.cellErrors = const [],
  });

  @override
  State<ShiftEditDialog> createState() => _ShiftEditDialogState();
}

class _ShiftEditDialogState extends State<ShiftEditDialog>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  Employee? _selectedEmployee;
  ShiftType? _selectedShiftType;
  Shop? _selectedShop;
  bool _isLoading = false;
  final Map<String, ShopSettings> _shopSettingsCache = {};

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: widget.cellErrors.isNotEmpty ? 3 : 2,
      vsync: this,
      initialIndex: widget.cellErrors.isNotEmpty ? 2 : 0,
    );

    _selectedEmployee = widget.employee;
    _selectedShiftType = widget.requiredShiftType ??
        widget.existingEntry?.shiftType ??
        ShiftType.morning;

    if (widget.requiredShop != null) {
      _selectedShop = widget.requiredShop;
    } else if (widget.existingEntry != null) {
      _selectedShop = widget.shops.firstWhere(
        (shop) => shop.address == widget.existingEntry!.shopAddress,
        orElse: () => widget.shops.first,
      );
    } else {
      _selectedShop = widget.shops.isNotEmpty ? widget.shops.first : null;
    }

    _loadShopSettings();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadShopSettings() async {
    if (mounted) setState(() => _isLoading = true);

    for (var shop in widget.shops) {
      try {
        final settings = await ShopService.getShopSettings(shop.address);
        if (settings != null) {
          _shopSettingsCache[shop.address] = settings;
        }
      } catch (e) {
        Logger.error('Ошибка загрузки настроек магазина ${shop.address}', e);
      }
    }

    if (mounted) setState(() => _isLoading = false);
  }

  String get _dateFormatted =>
      '${widget.date.day}.${widget.date.month}.${widget.date.year}';

  @override
  Widget build(BuildContext context) {
    return Dialog.fullscreen(
      child: Scaffold(
        backgroundColor: AppColors.emeraldDark,
        appBar: AppBar(
          title: Text(
            widget.employee.name,
            style: TextStyle(
              fontSize: 18.sp,
              fontWeight: FontWeight.w600,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          backgroundColor: AppColors.primaryGreen,
          foregroundColor: Colors.white,
          elevation: 0,
          centerTitle: true,
          leading: IconButton(
            icon: Container(
              padding: EdgeInsets.all(6.w),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.15),
                borderRadius: BorderRadius.circular(10.r),
              ),
              child: Icon(Icons.close_rounded, size: 22),
            ),
            onPressed: () => Navigator.of(context).pop(),
          ),
          bottom: PreferredSize(
            preferredSize: Size.fromHeight(58),
            child: Column(
              children: [
                // Дата под заголовком
                Padding(
                  padding: EdgeInsets.only(bottom: 8),
                  child: Text(
                    _dateFormatted,
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.7),
                      fontSize: 13.sp,
                    ),
                  ),
                ),
                // Табы
                Container(
                  decoration: BoxDecoration(
                    color: AppColors.emeraldDark.withOpacity(0.3),
                  ),
                  child: TabBar(
                    controller: _tabController,
                    labelColor: AppColors.gold,
                    unselectedLabelColor: Colors.white.withOpacity(0.6),
                    indicatorColor: AppColors.gold,
                    indicatorWeight: 3,
                    labelStyle: TextStyle(
                      fontSize: 13.sp,
                      fontWeight: FontWeight.w600,
                    ),
                    isScrollable: true,
                    tabAlignment: TabAlignment.center,
                    tabs: [
                      Tab(text: 'Редактировать'),
                      Tab(text: 'Свободные'),
                      if (widget.cellErrors.isNotEmpty)
                        Tab(
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.warning_rounded, size: 16, color: AppColors.warning),
                              SizedBox(width: 4),
                              Text('Причины'),
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
        body: TabBarView(
          controller: _tabController,
          children: [
            _buildEditTab(),
            _buildAvailableEmployeesTab(),
            if (widget.cellErrors.isNotEmpty) _buildReasonsTab(),
          ],
        ),
      ),
    );
  }

  /// Вкладка редактирования
  Widget _buildEditTab() {
    if (_isLoading) {
      return Center(
        child: CircularProgressIndicator(color: AppColors.gold),
      );
    }

    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            physics: BouncingScrollPhysics(),
            padding: EdgeInsets.all(20.w),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Сотрудник
                _buildFieldLabel('Сотрудник', Icons.person_rounded),
                SizedBox(height: 10),
                _buildStyledDropdown<Employee>(
                  value: _selectedEmployee,
                  items: widget.allEmployees.map((emp) {
                    return DropdownMenuItem<Employee>(
                      value: emp,
                      child: Text(
                        emp.name,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: Colors.white, fontSize: 14.sp),
                      ),
                    );
                  }).toList(),
                  onChanged: (value) {
                    if (mounted) setState(() => _selectedEmployee = value);
                  },
                ),

                SizedBox(height: 24),

                // Тип смены
                Row(
                  children: [
                    _buildFieldLabel('Тип смены', Icons.schedule_rounded),
                    if (widget.requiredShiftType != null) ...[
                      SizedBox(width: 8),
                      Container(
                        padding: EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8.r),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.lock_rounded, size: 12, color: Colors.white.withOpacity(0.5)),
                            SizedBox(width: 4),
                            Text(
                              'заблокировано',
                              style: TextStyle(
                                fontSize: 10.sp,
                                color: Colors.white.withOpacity(0.5),
                                fontStyle: FontStyle.italic,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
                SizedBox(height: 10),
                _buildStyledDropdown<ShiftType>(
                  value: _selectedShiftType,
                  isLocked: widget.requiredShiftType != null,
                  items: ShiftType.values.map((type) {
                    return DropdownMenuItem<ShiftType>(
                      value: type,
                      child: Text(
                        '${type.label} (${type.timeRange})',
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: widget.requiredShiftType != null
                              ? Colors.white.withOpacity(0.4)
                              : Colors.white,
                          fontSize: 14.sp,
                        ),
                      ),
                    );
                  }).toList(),
                  onChanged: widget.requiredShiftType != null
                      ? null
                      : (value) {
                          if (mounted) setState(() => _selectedShiftType = value);
                        },
                ),

                SizedBox(height: 24),

                // Магазин
                Row(
                  children: [
                    _buildFieldLabel('Магазин', Icons.store_rounded),
                    if (widget.requiredShop != null) ...[
                      SizedBox(width: 8),
                      Container(
                        padding: EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8.r),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.lock_rounded, size: 12, color: Colors.white.withOpacity(0.5)),
                            SizedBox(width: 4),
                            Text(
                              'заблокировано',
                              style: TextStyle(
                                fontSize: 10.sp,
                                color: Colors.white.withOpacity(0.5),
                                fontStyle: FontStyle.italic,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
                SizedBox(height: 10),
                _buildStyledDropdown<Shop>(
                  value: _selectedShop,
                  isLocked: widget.requiredShop != null,
                  items: widget.shops.map((shop) {
                    String displayText = shop.name;
                    final settings = _shopSettingsCache[shop.address];
                    if (settings != null && _selectedShiftType != null) {
                      String? abbrev;
                      switch (_selectedShiftType!) {
                        case ShiftType.morning:
                          abbrev = settings.morningAbbreviation;
                          break;
                        case ShiftType.day:
                          abbrev = settings.dayAbbreviation;
                          break;
                        case ShiftType.evening:
                          abbrev = settings.nightAbbreviation;
                          break;
                      }
                      if (abbrev != null && abbrev.isNotEmpty) {
                        displayText = '$displayText ($abbrev)';
                      }
                    }

                    return DropdownMenuItem<Shop>(
                      value: shop,
                      child: Text(
                        displayText,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: widget.requiredShop != null
                              ? Colors.white.withOpacity(0.4)
                              : Colors.white,
                          fontSize: 14.sp,
                        ),
                      ),
                    );
                  }).toList(),
                  onChanged: widget.requiredShop != null
                      ? null
                      : (value) {
                          if (mounted) setState(() => _selectedShop = value);
                        },
                ),
              ],
            ),
          ),
        ),

        // Кнопки внизу
        _buildBottomActions(),
      ],
    );
  }

  /// Метка поля с иконкой
  Widget _buildFieldLabel(String label, IconData icon) {
    return Row(
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: AppColors.primaryGreen.withOpacity(0.3),
            borderRadius: BorderRadius.circular(8.r),
          ),
          child: Icon(icon, color: AppColors.gold, size: 18),
        ),
        SizedBox(width: 10),
        Text(
          label,
          style: TextStyle(
            fontSize: 15.sp,
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
        ),
      ],
    );
  }

  /// Стилизованный dropdown в тёмной теме
  Widget _buildStyledDropdown<T>({
    required T? value,
    required List<DropdownMenuItem<T>> items,
    required ValueChanged<T?>? onChanged,
    bool isLocked = false,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: isLocked
            ? Colors.white.withOpacity(0.05)
            : AppColors.emerald.withOpacity(0.5),
        borderRadius: BorderRadius.circular(12.r),
        border: Border.all(
          color: isLocked
              ? Colors.white.withOpacity(0.1)
              : AppColors.gold.withOpacity(0.3),
          width: 1,
        ),
      ),
      child: DropdownButtonFormField<T>(
        value: value,
        decoration: InputDecoration(
          border: InputBorder.none,
          contentPadding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 12.h),
        ),
        dropdownColor: AppColors.emerald,
        isExpanded: true,
        icon: Icon(
          Icons.keyboard_arrow_down_rounded,
          color: isLocked ? Colors.white.withOpacity(0.3) : AppColors.gold,
        ),
        items: items,
        onChanged: onChanged,
      ),
    );
  }

  /// Нижняя панель с кнопками действий
  Widget _buildBottomActions() {
    return Container(
      padding: EdgeInsets.fromLTRB(20.w, 12.h, 20.w, 20.h),
      decoration: BoxDecoration(
        color: AppColors.emeraldDark,
        border: Border(
          top: BorderSide(color: Colors.white.withOpacity(0.1)),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            // Удалить (если есть существующая смена)
            if (widget.existingEntry != null)
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _deleteShift,
                  icon: Icon(Icons.delete_rounded, size: 18),
                  label: Text('Удалить', style: TextStyle(fontSize: 13.sp)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.error,
                    side: BorderSide(color: AppColors.error.withOpacity(0.5)),
                    padding: EdgeInsets.symmetric(vertical: 14.h),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12.r),
                    ),
                  ),
                ),
              ),
            if (widget.existingEntry != null) SizedBox(width: 12),

            // Сохранить
            Expanded(
              flex: widget.existingEntry != null ? 2 : 1,
              child: ElevatedButton.icon(
                onPressed: _saveShift,
                icon: Icon(Icons.check_rounded, size: 20),
                label: Text(
                  'Сохранить',
                  style: TextStyle(
                    fontSize: 15.sp,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primaryGreen,
                  foregroundColor: Colors.white,
                  padding: EdgeInsets.symmetric(vertical: 14.h),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12.r),
                  ),
                  elevation: 0,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Вкладка свободных сотрудников
  Widget _buildAvailableEmployeesTab() {
    final availableEmployees = _getAvailableEmployees();

    if (availableEmployees.isEmpty) {
      return Center(
        child: Padding(
          padding: EdgeInsets.all(32.w),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.group_off_rounded,
                size: 48,
                color: Colors.white.withOpacity(0.3),
              ),
              SizedBox(height: 16),
              Text(
                'Нет свободных сотрудников',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 16.sp,
                  fontWeight: FontWeight.w600,
                  color: Colors.white.withOpacity(0.7),
                ),
              ),
              SizedBox(height: 8),
              Text(
                'Все сотрудники уже имеют смены на эту дату',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13.sp,
                  color: Colors.white.withOpacity(0.4),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.builder(
      padding: EdgeInsets.all(12.w),
      itemCount: availableEmployees.length,
      itemBuilder: (context, index) {
        final emp = availableEmployees[index];
        final yesterdayStatus = _getYesterdayStatus(emp);
        final priority = _getEmployeePriorityScore(emp);
        final isGood = priority >= 4;

        return Container(
          margin: EdgeInsets.only(bottom: 8.h),
          decoration: BoxDecoration(
            color: AppColors.emerald.withOpacity(0.5),
            borderRadius: BorderRadius.circular(12.r),
            border: Border.all(
              color: isGood
                  ? AppColors.emeraldGreen.withOpacity(0.3)
                  : Colors.white.withOpacity(0.1),
            ),
          ),
          child: ListTile(
            contentPadding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 4.h),
            leading: CircleAvatar(
              backgroundColor: isGood ? AppColors.emeraldGreen : AppColors.primaryGreen,
              foregroundColor: Colors.white,
              child: Text(
                emp.name.length >= 2
                    ? emp.name.substring(0, 2).toUpperCase()
                    : emp.name.substring(0, 1).toUpperCase(),
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13.sp),
              ),
            ),
            title: Text(
              emp.name,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: Colors.white,
                fontSize: 14.sp,
              ),
            ),
            subtitle: Text(
              yesterdayStatus,
              style: TextStyle(
                color: yesterdayStatus.contains('Выходные')
                    ? AppColors.emeraldGreen
                    : AppColors.warning,
                fontSize: 12.sp,
              ),
            ),
            trailing: Container(
              padding: EdgeInsets.all(8.w),
              decoration: BoxDecoration(
                color: AppColors.gold.withOpacity(0.15),
                borderRadius: BorderRadius.circular(8.r),
              ),
              child: Icon(
                Icons.arrow_forward_rounded,
                color: AppColors.gold,
                size: 18,
              ),
            ),
            onTap: () => _replaceEmployeeAndSave(emp),
          ),
        );
      },
    );
  }

  /// Вкладка "Причины" — показывает почему у ячейки восклицательный знак
  Widget _buildReasonsTab() {
    return ListView.builder(
      padding: EdgeInsets.all(16.w),
      itemCount: widget.cellErrors.length,
      itemBuilder: (context, index) {
        final error = widget.cellErrors[index];
        final isCritical = error.isCritical;
        final color = isCritical ? AppColors.error : AppColors.warning;

        return Container(
          margin: EdgeInsets.only(bottom: 12.h),
          padding: EdgeInsets.all(16.w),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(14.r),
            border: Border.all(color: color.withOpacity(0.3)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: color.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(10.r),
                ),
                child: Icon(
                  isCritical ? Icons.error_rounded : Icons.warning_rounded,
                  color: color,
                  size: 20,
                ),
              ),
              SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isCritical ? 'Ошибка' : 'Предупреждение',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 13.sp,
                        color: color,
                      ),
                    ),
                    SizedBox(height: 6),
                    Text(
                      error.displayMessage,
                      style: TextStyle(
                        fontSize: 13.sp,
                        color: Colors.white.withOpacity(0.9),
                      ),
                    ),
                    SizedBox(height: 6),
                    Text(
                      _getErrorExplanation(error),
                      style: TextStyle(
                        fontSize: 11.sp,
                        color: Colors.white.withOpacity(0.5),
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  /// Человекопонятное объяснение ошибки
  String _getErrorExplanation(ScheduleError error) {
    switch (error.type) {
      case ScheduleErrorType.missingMorning:
        return 'В магазине нет утренней смены на эту дату. Назначьте сотрудника.';
      case ScheduleErrorType.missingEvening:
        return 'В магазине нет вечерней смены на эту дату. Назначьте сотрудника.';
      case ScheduleErrorType.duplicateMorning:
        return 'На одну утреннюю смену назначено несколько сотрудников. Удалите лишнюю смену.';
      case ScheduleErrorType.duplicateEvening:
        return 'На одну вечернюю смену назначено несколько сотрудников. Удалите лишнюю смену.';
      case ScheduleErrorType.morningAfterEvening:
        return 'Сотрудник работал в вечернюю смену вчера и стоит в утреннюю сегодня. Это менее 12 часов отдыха.';
      case ScheduleErrorType.eveningAfterMorning:
        return 'Сотрудник работает и утром, и вечером в один день. Это более 16 часов работы.';
      case ScheduleErrorType.dayAfterEvening:
        return 'Сотрудник работал в вечернюю смену вчера и стоит в дневную сегодня. Недостаточно времени для отдыха.';
    }
  }

  /// Получить список свободных сотрудников с сортировкой
  List<Employee> _getAvailableEmployees() {
    final availableEmployees = widget.allEmployees.where((emp) {
      final hasShift = widget.schedule.entries.any((e) {
        if (widget.existingEntry != null && e.id == widget.existingEntry!.id) {
          return false;
        }
        return e.employeeId == emp.id &&
            e.date.year == widget.date.year &&
            e.date.month == widget.date.month &&
            e.date.day == widget.date.day;
      });
      return !hasShift;
    }).toList();

    availableEmployees.sort((a, b) {
      final aScore = _getEmployeePriorityScore(a);
      final bScore = _getEmployeePriorityScore(b);
      return bScore.compareTo(aScore);
    });

    return availableEmployees;
  }

  /// Рассчитать приоритет сотрудника (чем больше - тем лучше подходит)
  int _getEmployeePriorityScore(Employee emp) {
    final yesterday = widget.date.subtract(Duration(days: 1));
    final today = widget.date;
    final tomorrow = widget.date.add(Duration(days: 1));

    final hadYesterday = widget.schedule.entries.any((e) =>
        e.employeeId == emp.id &&
        e.date.year == yesterday.year &&
        e.date.month == yesterday.month &&
        e.date.day == yesterday.day);

    final todayEntries = widget.schedule.entries
        .where((e) =>
            e.employeeId == emp.id &&
            e.date.year == today.year &&
            e.date.month == today.month &&
            e.date.day == today.day)
        .toList();

    final hasToday = todayEntries.isNotEmpty;

    final hasTomorrow = widget.schedule.entries.any((e) =>
        e.employeeId == emp.id &&
        e.date.year == tomorrow.year &&
        e.date.month == tomorrow.month &&
        e.date.day == tomorrow.day);

    if (hasToday && hasTomorrow) return 1;
    if (hasToday) return 2;
    if (hadYesterday && hasTomorrow) return 3;
    if (hadYesterday || hasTomorrow) return 4;
    return 5;
  }

  /// Получить статус вчерашнего/завтрашнего дня для сотрудника
  String _getYesterdayStatus(Employee emp) {
    final yesterday = widget.date.subtract(Duration(days: 1));
    final yesterdayEntry = widget.schedule.entries.firstWhere(
      (e) =>
          e.employeeId == emp.id &&
          e.date.year == yesterday.year &&
          e.date.month == yesterday.month &&
          e.date.day == yesterday.day,
      orElse: () => WorkScheduleEntry(
        id: '',
        employeeId: '',
        employeeName: '',
        shopAddress: '',
        date: DateTime.now(),
        shiftType: ShiftType.morning,
      ),
    );

    final tomorrow = widget.date.add(Duration(days: 1));
    final tomorrowEntry = widget.schedule.entries.firstWhere(
      (e) =>
          e.employeeId == emp.id &&
          e.date.year == tomorrow.year &&
          e.date.month == tomorrow.month &&
          e.date.day == tomorrow.day,
      orElse: () => WorkScheduleEntry(
        id: '',
        employeeId: '',
        employeeName: '',
        shopAddress: '',
        date: DateTime.now(),
        shiftType: ShiftType.morning,
      ),
    );

    final List<String> parts = [];

    if (yesterdayEntry.id.isNotEmpty) {
      parts.add('Вчера: ${yesterdayEntry.shiftType.label}');
    }

    if (tomorrowEntry.id.isNotEmpty) {
      parts.add('Завтра: ${tomorrowEntry.shiftType.label}');
    }

    if (parts.isNotEmpty) {
      return parts.join(' | ');
    }

    return 'Выходные вчера и завтра';
  }

  /// Заменить сотрудника и сохранить
  Future<void> _replaceEmployeeAndSave(Employee newEmployee) async {
    if (_selectedShiftType == null || _selectedShop == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Ошибка: не выбран тип смены или магазин'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    final entry = WorkScheduleEntry(
      id: widget.existingEntry?.id ?? '',
      employeeId: newEmployee.id,
      employeeName: newEmployee.name,
      shopAddress: _selectedShop!.address,
      date: widget.date,
      shiftType: _selectedShiftType!,
    );

    Logger.debug('Замена сотрудника: ${widget.employee.name} → ${newEmployee.name}');
    Logger.debug('Entry ID: ${entry.id}, existingEntry: ${widget.existingEntry?.id}');
    Logger.debug('Тип смены: ${entry.shiftType}, Магазин: ${entry.shopAddress}');

    Navigator.of(context).pop({
      'action': 'save',
      'entry': entry,
    });
  }

  /// Сохранить смену
  void _saveShift() {
    if (_selectedEmployee == null ||
        _selectedShiftType == null ||
        _selectedShop == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Заполните все поля'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    final entry = WorkScheduleEntry(
      id: widget.existingEntry?.id ?? '',
      employeeId: _selectedEmployee!.id,
      employeeName: _selectedEmployee!.name,
      shopAddress: _selectedShop!.address,
      date: widget.date,
      shiftType: _selectedShiftType!,
    );

    Navigator.of(context).pop({
      'action': 'save',
      'entry': entry,
    });
  }

  /// Удалить смену
  Future<void> _deleteShift() async {
    Logger.debug('_deleteShift вызван');

    if (widget.existingEntry == null) {
      Logger.error(
          'Попытка удаления несуществующей смены (existingEntry == null)',
          null);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка: Смена не найдена'),
            backgroundColor: AppColors.error,
          ),
        );
      }
      return;
    }

    Logger.debug(
        'existingEntry: ID="${widget.existingEntry!.id}", employee="${widget.existingEntry!.employeeName}", date=${widget.date}');

    if (widget.existingEntry!.id.isEmpty) {
      Logger.error('ID смены пустой (empty string)', null);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка: ID смены не найден (пустая строка)'),
            backgroundColor: AppColors.error,
          ),
        );
      }
      return;
    }

    Logger.debug(
        'ID смены валиден: "${widget.existingEntry!.id}", показываем диалог подтверждения');

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.emerald,
        title: Text(
          'Подтверждение',
          style: TextStyle(color: Colors.white),
        ),
        content: Text(
          'Удалить смену сотрудника ${widget.existingEntry!.employeeName}?\n'
          'Дата: ${widget.date.day}.${widget.date.month}.${widget.date.year}\n'
          'Смена: ${widget.existingEntry!.shiftType.label}',
          style: TextStyle(color: Colors.white.withOpacity(0.8)),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Logger.debug('Удаление отменено пользователем');
              Navigator.of(context).pop(false);
            },
            child: Text('Отмена', style: TextStyle(color: Colors.white.withOpacity(0.6))),
          ),
          ElevatedButton(
            onPressed: () {
              Logger.debug('Удаление подтверждено пользователем');
              Navigator.of(context).pop(true);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
              foregroundColor: Colors.white,
            ),
            child: Text('Удалить'),
          ),
        ],
      ),
    );

    Logger.debug('Результат диалога подтверждения: $confirmed');

    if (confirmed == true) {
      Logger.debug(
          'Удаление смены подтверждено: ID="${widget.existingEntry!.id}"');
      if (mounted) {
        Logger.debug(
            'Контекст смонтирован, закрываем диалог с action=delete');
        Navigator.of(context).pop({
          'action': 'delete',
          'entry': widget.existingEntry,
        });
      } else {
        Logger.error(
            'Контекст НЕ смонтирован, не можем закрыть диалог!', null);
      }
    } else {
      Logger.debug('Удаление не подтверждено (confirmed != true)');
    }
  }
}
