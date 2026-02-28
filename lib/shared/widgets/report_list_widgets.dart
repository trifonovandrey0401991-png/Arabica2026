import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_colors.dart';

// ═══════════════════════════════════════════════════
// Утилиты для страниц списков отчётов
// ═══════════════════════════════════════════════════

/// Русские названия месяцев в родительном падеже (для дат: "5 января").
/// Индекс 0 — пустая строка, месяцы начинаются с 1.
const monthNamesGenitive = [
  '', 'января', 'февраля', 'марта', 'апреля', 'мая', 'июня',
  'июля', 'августа', 'сентября', 'октября', 'ноября', 'декабря',
];

/// Русские названия месяцев в именительном падеже (для заголовков: "Январь 2026").
const monthNamesNominative = [
  '', 'Январь', 'Февраль', 'Март', 'Апрель', 'Май', 'Июнь',
  'Июль', 'Август', 'Сентябрь', 'Октябрь', 'Ноябрь', 'Декабрь',
];

/// Форматирование дня: "5 января"
String formatDayGenitive(DateTime day) {
  return '${day.day} ${monthNamesGenitive[day.month]}';
}

/// Понедельник недели, содержащей [date].
DateTime getWeekStart(DateTime date) {
  final weekday = date.weekday; // 1=Mon, 7=Sun
  return DateTime(date.year, date.month, date.day - (weekday - 1));
}

// ═══════════════════════════════════════════════════
// ReportTabButton — кнопка-вкладка для списков отчётов
// ═══════════════════════════════════════════════════

/// Кнопка-вкладка для списков отчётов в Dark Emerald теме.
///
/// Два варианта:
/// - С иконкой: `ReportTabButton(icon: Icons.check, ...)`
/// - Без иконки: `ReportTabButton(label: 'Tab', ...)`
///
/// Дублировалась в 10+ файлах report list pages.
class ReportTabButton extends StatelessWidget {
  final bool isSelected;
  final VoidCallback onTap;
  final String label;
  final int count;
  final Color accentColor;
  final IconData? icon;
  final int badge;

  const ReportTabButton({
    super.key,
    required this.isSelected,
    required this.onTap,
    required this.label,
    required this.count,
    this.accentColor = Colors.white,
    this.icon,
    this.badge = 0,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10.r),
          child: Container(
            padding: EdgeInsets.symmetric(vertical: 6.h, horizontal: 4.w),
            decoration: BoxDecoration(
              gradient: isSelected
                  ? LinearGradient(
                      colors: [
                        accentColor.withOpacity(0.8),
                        accentColor,
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    )
                  : null,
              color: isSelected ? null : Colors.white.withOpacity(0.06),
              borderRadius: BorderRadius.circular(10.r),
              border: Border.all(
                color: isSelected
                    ? accentColor
                    : Colors.white.withOpacity(0.1),
                width: isSelected ? 2 : 1,
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (icon != null) ...[
                  Icon(
                    icon,
                    size: 14,
                    color: isSelected
                        ? Colors.white
                        : Colors.white.withOpacity(0.5),
                  ),
                  SizedBox(width: 4),
                ],
                Flexible(
                  child: Text(
                    label,
                    style: TextStyle(
                      fontSize: 10.sp,
                      color: isSelected
                          ? Colors.white
                          : Colors.white.withOpacity(0.5),
                      fontWeight:
                          isSelected ? FontWeight.bold : FontWeight.normal,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                SizedBox(width: 4),
                Container(
                  padding:
                      EdgeInsets.symmetric(horizontal: 5.w, vertical: 1.h),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? Colors.white.withOpacity(0.3)
                        : accentColor.withOpacity(0.4),
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
}

// ═══════════════════════════════════════════════════
// ReportGroupType — тип группировки отчётов
// ═══════════════════════════════════════════════════

/// Тип группировки отчётов по дате.
enum ReportGroupType { today, yesterday, day, week, month }

/// Группа отчётов с заголовком и типом.
class ReportGroup<T> {
  final ReportGroupType type;
  final String title;
  final List<T> reports;
  final DateTime? date;

  ReportGroup({
    required this.type,
    required this.title,
    required this.reports,
    this.date,
  });
}

/// Группирует отчёты по дате (сегодня, вчера, день, неделя, месяц).
///
/// [getDate] — извлекает дату из отчёта.
/// Возвращает список групп, отсортированных от новых к старым.
List<ReportGroup<T>> groupReportsByDate<T>(
  List<T> reports,
  DateTime Function(T) getDate,
) {
  if (reports.isEmpty) return [];

  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final yesterday = today.subtract(Duration(days: 1));

  final todayReports = <T>[];
  final yesterdayReports = <T>[];
  final dayGroups = <String, List<T>>{};
  final weekGroups = <String, List<T>>{};
  final monthGroups = <String, List<T>>{};

  for (final report in reports) {
    final date = getDate(report);
    final reportDay = DateTime(date.year, date.month, date.day);

    if (reportDay == today) {
      todayReports.add(report);
    } else if (reportDay == yesterday) {
      yesterdayReports.add(report);
    } else if (today.difference(reportDay).inDays < 7) {
      final key = formatDayGenitive(reportDay);
      dayGroups.putIfAbsent(key, () => []).add(report);
    } else if (today.difference(reportDay).inDays < 30) {
      final ws = getWeekStart(reportDay);
      final we = ws.add(Duration(days: 6));
      final key =
          'Неделя ${ws.day}-${we.day} ${monthNamesGenitive[ws.month]}';
      weekGroups.putIfAbsent(key, () => []).add(report);
    } else {
      final key =
          '${monthNamesNominative[date.month]} ${date.year}';
      monthGroups.putIfAbsent(key, () => []).add(report);
    }
  }

  final result = <ReportGroup<T>>[];

  if (todayReports.isNotEmpty) {
    result.add(ReportGroup(
      type: ReportGroupType.today,
      title: 'Сегодня',
      reports: todayReports,
    ));
  }
  if (yesterdayReports.isNotEmpty) {
    result.add(ReportGroup(
      type: ReportGroupType.yesterday,
      title: 'Вчера',
      reports: yesterdayReports,
    ));
  }
  for (final entry in dayGroups.entries) {
    result.add(ReportGroup(
      type: ReportGroupType.day,
      title: entry.key,
      reports: entry.value,
    ));
  }
  for (final entry in weekGroups.entries) {
    result.add(ReportGroup(
      type: ReportGroupType.week,
      title: entry.key,
      reports: entry.value,
    ));
  }
  for (final entry in monthGroups.entries) {
    result.add(ReportGroup(
      type: ReportGroupType.month,
      title: entry.key,
      reports: entry.value,
    ));
  }

  return result;
}

/// Иконка и цвет для типа группы отчётов.
IconData getGroupIcon(ReportGroupType type) {
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

Color getGroupColor(ReportGroupType type) {
  switch (type) {
    case ReportGroupType.today:
      return Colors.green;
    case ReportGroupType.yesterday:
      return Colors.blue;
    case ReportGroupType.day:
      return Colors.cyan;
    case ReportGroupType.week:
      return Colors.orange;
    case ReportGroupType.month:
      return Colors.purple;
  }
}

// ═══════════════════════════════════════════════════
// ReportEmptyState — пустое состояние списка отчётов
// ═══════════════════════════════════════════════════

/// Виджет пустого состояния для списков отчётов.
///
/// Показывает иконку в круге, заголовок и (опционально) подзаголовок.
/// Использование:
/// ```dart
/// ReportEmptyState(
///   icon: Icons.description_outlined,
///   title: 'Нет отчётов',
///   subtitle: 'Отчёты появятся после первой пересменки',
/// )
/// ```
class ReportEmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final Color? color;

  const ReportEmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final circleColor = color ?? Colors.white.withOpacity(0.15);

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 64.w,
            height: 64.h,
            decoration: BoxDecoration(
              color: circleColor,
              shape: BoxShape.circle,
            ),
            child: Icon(
              icon,
              size: 32.sp,
              color: Colors.white.withOpacity(0.4),
            ),
          ),
          SizedBox(height: 16.h),
          Text(
            title,
            style: TextStyle(
              fontSize: 14.sp,
              color: Colors.white,
            ),
            textAlign: TextAlign.center,
          ),
          if (subtitle != null) ...[
            SizedBox(height: 6.h),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 32.w),
              child: Text(
                subtitle!,
                style: TextStyle(
                  fontSize: 12.sp,
                  color: Colors.white54,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════
// ReportFiltersWidget — фильтры для списков отчётов
// ═══════════════════════════════════════════════════

/// Панель фильтров для страниц со списками отчётов.
///
/// Содержит выпадающий список магазинов, выпадающий список сотрудников,
/// кнопку выбора даты и кнопку сброса всех фильтров.
///
/// Использование:
/// ```dart
/// ReportFiltersWidget(
///   shops: ['Магазин 1', 'Магазин 2'],
///   employees: ['Иванов', 'Петров'],
///   selectedShop: _selectedShop,
///   selectedEmployee: _selectedEmployee,
///   selectedDate: _selectedDate,
///   onShopChanged: (v) => setState(() => _selectedShop = v),
///   onEmployeeChanged: (v) => setState(() => _selectedEmployee = v),
///   onDateChanged: (v) => setState(() => _selectedDate = v),
///   onReset: () => setState(() {
///     _selectedShop = null;
///     _selectedEmployee = null;
///     _selectedDate = null;
///   }),
/// )
/// ```
class ReportFiltersWidget extends StatelessWidget {
  final List<String> shops;
  final List<String> employees;
  final String? selectedShop;
  final String? selectedEmployee;
  final DateTime? selectedDate;
  final ValueChanged<String?> onShopChanged;
  final ValueChanged<String?> onEmployeeChanged;
  final ValueChanged<DateTime?> onDateChanged;
  final VoidCallback onReset;

  const ReportFiltersWidget({
    super.key,
    required this.shops,
    required this.employees,
    this.selectedShop,
    this.selectedEmployee,
    this.selectedDate,
    required this.onShopChanged,
    required this.onEmployeeChanged,
    required this.onDateChanged,
    required this.onReset,
  });

  bool get _hasActiveFilters =>
      selectedShop != null || selectedEmployee != null || selectedDate != null;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(12.w),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.04),
        borderRadius: BorderRadius.circular(12.r),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Row 1: Shop dropdown + Date picker
          Row(
            children: [
              Expanded(child: _buildShopDropdown()),
              SizedBox(width: 8.w),
              _buildDateButton(context),
            ],
          ),
          SizedBox(height: 8.h),
          // Row 2: Employee dropdown + Reset button
          Row(
            children: [
              Expanded(child: _buildEmployeeDropdown()),
              SizedBox(width: 8.w),
              _buildResetButton(),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildShopDropdown() {
    return _buildDropdown<String?>(
      value: selectedShop,
      icon: Icons.store,
      hint: 'Все магазины',
      items: [
        DropdownMenuItem<String?>(
          value: null,
          child: Text(
            'Все магазины',
            style: TextStyle(fontSize: 12.sp, color: Colors.white),
          ),
        ),
        ...shops.map((shop) => DropdownMenuItem<String?>(
              value: shop,
              child: Text(
                shop,
                style: TextStyle(fontSize: 12.sp, color: Colors.white),
                overflow: TextOverflow.ellipsis,
              ),
            )),
      ],
      onChanged: onShopChanged,
    );
  }

  Widget _buildEmployeeDropdown() {
    return _buildDropdown<String?>(
      value: selectedEmployee,
      icon: Icons.person,
      hint: 'Все сотрудники',
      items: [
        DropdownMenuItem<String?>(
          value: null,
          child: Text(
            'Все сотрудники',
            style: TextStyle(fontSize: 12.sp, color: Colors.white),
          ),
        ),
        ...employees.map((emp) => DropdownMenuItem<String?>(
              value: emp,
              child: Text(
                emp,
                style: TextStyle(fontSize: 12.sp, color: Colors.white),
                overflow: TextOverflow.ellipsis,
              ),
            )),
      ],
      onChanged: onEmployeeChanged,
    );
  }

  Widget _buildDropdown<T>({
    required T value,
    required IconData icon,
    required String hint,
    required List<DropdownMenuItem<T>> items,
    required ValueChanged<T?> onChanged,
  }) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 8.w),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.08),
        borderRadius: BorderRadius.circular(8.r),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: value,
          isExpanded: true,
          dropdownColor: AppColors.emeraldDark,
          icon: Icon(
            Icons.arrow_drop_down,
            color: Colors.white.withOpacity(0.5),
            size: 20.sp,
          ),
          hint: Row(
            children: [
              Icon(icon, size: 14.sp, color: Colors.white.withOpacity(0.5)),
              SizedBox(width: 6.w),
              Text(
                hint,
                style: TextStyle(
                  fontSize: 12.sp,
                  color: Colors.white.withOpacity(0.5),
                ),
              ),
            ],
          ),
          selectedItemBuilder: (context) => items.map((item) {
            return Row(
              children: [
                Icon(icon, size: 14.sp, color: Colors.white.withOpacity(0.7)),
                SizedBox(width: 6.w),
                Expanded(child: item.child),
              ],
            );
          }).toList(),
          items: items,
          onChanged: onChanged,
        ),
      ),
    );
  }

  Widget _buildDateButton(BuildContext context) {
    final hasDate = selectedDate != null;
    final label = hasDate ? DateFormat('dd.MM').format(selectedDate!) : null;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () async {
          final picked = await showDatePicker(
            context: context,
            initialDate: selectedDate ?? DateTime.now(),
            firstDate: DateTime(2024),
            lastDate: DateTime.now(),
            builder: (context, child) {
              return Theme(
                data: Theme.of(context).copyWith(
                  colorScheme: ColorScheme.dark(
                    primary: AppColors.emerald,
                    onPrimary: Colors.white,
                    surface: AppColors.emeraldDark,
                    onSurface: Colors.white,
                  ),
                  dialogBackgroundColor: AppColors.night,
                ),
                child: child!,
              );
            },
          );
          onDateChanged(picked);
        },
        borderRadius: BorderRadius.circular(8.r),
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 8.h),
          decoration: BoxDecoration(
            color: hasDate
                ? AppColors.emerald.withOpacity(0.3)
                : Colors.white.withOpacity(0.08),
            borderRadius: BorderRadius.circular(8.r),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.calendar_today,
                size: 14.sp,
                color: hasDate ? Colors.white : Colors.white.withOpacity(0.5),
              ),
              if (label != null) ...[
                SizedBox(width: 4.w),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12.sp,
                    color: Colors.white,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildResetButton() {
    return AnimatedOpacity(
      opacity: _hasActiveFilters ? 1.0 : 0.0,
      duration: const Duration(milliseconds: 200),
      child: IgnorePointer(
        ignoring: !_hasActiveFilters,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onReset,
            borderRadius: BorderRadius.circular(8.r),
            child: Container(
              padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 8.h),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.08),
                borderRadius: BorderRadius.circular(8.r),
              ),
              child: Icon(
                Icons.clear,
                size: 16.sp,
                color: Colors.white.withOpacity(0.7),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
