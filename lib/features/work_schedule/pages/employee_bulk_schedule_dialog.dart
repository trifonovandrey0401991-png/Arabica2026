import 'package:flutter/material.dart';
import '../models/work_schedule_model.dart';
import '../../employees/pages/employees_page.dart' show Employee;
import '../../shops/models/shop_model.dart';
import '../../shops/models/shop_settings_model.dart';

/// Диалог массового редактирования смен сотрудника
/// Строки = магазины, столбцы = дни (каждый день делится на 2 клетки: утро и вечер)
class EmployeeBulkScheduleDialog extends StatefulWidget {
  final Employee employee;
  final DateTime selectedMonth;
  final int startDay;
  final int endDay;
  final List<Shop> shops;
  final WorkSchedule? currentSchedule;
  final Map<String, ShopSettings> shopSettingsCache;

  const EmployeeBulkScheduleDialog({
    super.key,
    required this.employee,
    required this.selectedMonth,
    required this.startDay,
    required this.endDay,
    required this.shops,
    required this.currentSchedule,
    required this.shopSettingsCache,
  });

  @override
  State<EmployeeBulkScheduleDialog> createState() => _EmployeeBulkScheduleDialogState();
}

class _EmployeeBulkScheduleDialogState extends State<EmployeeBulkScheduleDialog> {
  ShiftType _selectedShiftType = ShiftType.morning;
  final Map<String, WorkScheduleEntry> _pendingEntries = {};

  // Цвета для смен
  static const Color _morningColor = Color(0xFFB9F6CA); // салатовый
  static const Color _dayColor = Color(0xFFFFF59D); // светло-жёлтый
  static const Color _eveningColor = Color(0xFFE0E0E0); // светло-серый

  @override
  void initState() {
    super.initState();
    _loadExistingEntries();
  }

  /// Загружает существующие смены сотрудника
  void _loadExistingEntries() {
    if (widget.currentSchedule == null) return;

    for (final entry in widget.currentSchedule!.entries) {
      if (entry.employeeId == widget.employee.id) {
        final key = '${entry.shopAddress}_${entry.date.toIso8601String().split('T')[0]}';
        _pendingEntries[key] = entry;
      }
    }
  }

  /// Получает дни в выбранном периоде
  List<DateTime> _getDaysInPeriod() {
    final days = <DateTime>[];
    for (int d = widget.startDay; d <= widget.endDay; d++) {
      final date = DateTime(widget.selectedMonth.year, widget.selectedMonth.month, d);
      if (date.month == widget.selectedMonth.month) {
        days.add(date);
      }
    }
    return days;
  }

  /// Получает аббревиатуру для смены
  String _getAbbreviation(WorkScheduleEntry entry) {
    final settings = widget.shopSettingsCache[entry.shopAddress];
    if (settings != null) {
      switch (entry.shiftType) {
        case ShiftType.morning:
          final abbr = settings.morningAbbreviation;
          if (abbr != null && abbr.isNotEmpty) return abbr;
          break;
        case ShiftType.day:
          final abbr = settings.dayAbbreviation;
          if (abbr != null && abbr.isNotEmpty) return abbr;
          break;
        case ShiftType.evening:
          final abbr = settings.nightAbbreviation;
          if (abbr != null && abbr.isNotEmpty) return abbr;
          break;
      }
    }
    // Стандартные аббревиатуры
    switch (entry.shiftType) {
      case ShiftType.morning:
        return 'У';
      case ShiftType.day:
        return 'Д';
      case ShiftType.evening:
        return 'В';
    }
  }

  /// Получает цвет ячейки по типу смены
  Color _getCellColor(ShiftType type) {
    switch (type) {
      case ShiftType.morning:
        return _morningColor;
      case ShiftType.day:
        return _dayColor;
      case ShiftType.evening:
        return _eveningColor;
    }
  }

  /// Получает запись для ячейки
  WorkScheduleEntry? _getEntryForCell(String shopAddress, DateTime day) {
    final key = '${shopAddress}_${day.toIso8601String().split('T')[0]}';
    return _pendingEntries[key];
  }

  /// Обработка клика по ячейке
  void _onCellTap(Shop shop, DateTime day) {
    final key = '${shop.address}_${day.toIso8601String().split('T')[0]}';

    setState(() {
      // Удаляем смену на этот день если есть (одна смена в день)
      _pendingEntries.removeWhere((k, v) =>
        v.date.year == day.year &&
        v.date.month == day.month &&
        v.date.day == day.day
      );

      // Добавляем новую смену
      _pendingEntries[key] = WorkScheduleEntry(
        id: 'pending_${DateTime.now().millisecondsSinceEpoch}',
        employeeId: widget.employee.id,
        employeeName: widget.employee.name,
        shopAddress: shop.address,
        date: day,
        shiftType: _selectedShiftType,
      );
    });
  }

  /// Проверяет, является ли смена утренней или вечерней
  bool _isEveningShift(ShiftType type) {
    return type == ShiftType.evening;
  }

  String _getMonthName(int month) {
    const months = [
      'января', 'февраля', 'марта', 'апреля', 'мая', 'июня',
      'июля', 'августа', 'сентября', 'октября', 'ноября', 'декабря'
    ];
    return months[month - 1];
  }

  String _getWeekdayName(int weekday) {
    const weekdays = ['Пн', 'Вт', 'Ср', 'Чт', 'Пт', 'Сб', 'Вс'];
    return weekdays[weekday - 1];
  }

  @override
  Widget build(BuildContext context) {
    final days = _getDaysInPeriod();

    return Dialog(
      insetPadding: const EdgeInsets.all(16),
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.95,
          maxHeight: MediaQuery.of(context).size.height * 0.9,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Заголовок
            _buildHeader(),
            // Панель выбора смены
            _buildShiftSelector(),
            const Divider(height: 1),
            // Таблица
            Expanded(
              child: _buildScheduleTable(days),
            ),
            const Divider(height: 1),
            // Кнопки
            _buildActions(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: const BoxDecoration(
        color: Color(0xFF004D40),
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(4),
          topRight: Radius.circular(4),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'График смен: ${widget.employee.name}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  'Период: ${widget.startDay} - ${widget.endDay} ${_getMonthName(widget.selectedMonth.month)} ${widget.selectedMonth.year}',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.8),
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, color: Colors.white),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }

  Widget _buildShiftSelector() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
      color: Colors.grey[100],
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text(
              'Смена: ',
              style: TextStyle(fontWeight: FontWeight.w500, fontSize: 13),
            ),
            const SizedBox(width: 8),
            ...ShiftType.values.map((type) {
              final isSelected = type == _selectedShiftType;
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: isSelected ? _getCellColor(type) : Colors.white,
                    foregroundColor: Colors.black,
                    elevation: isSelected ? 4 : 1,
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    minimumSize: const Size(60, 32),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(6),
                      side: BorderSide(
                        color: isSelected ? type.color : Colors.grey[300]!,
                        width: isSelected ? 2 : 1,
                      ),
                    ),
                  ),
                  onPressed: () => setState(() => _selectedShiftType = type),
                  child: Text(
                    type.label,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildScheduleTable(List<DateTime> days) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Заголовок с днями
            _buildHeaderRow(days),
            // Строки магазинов
            ...widget.shops.map((shop) => _buildShopRow(shop, days)),
          ],
        ),
      ),
    );
  }

  Widget _buildHeaderRow(List<DateTime> days) {
    return Row(
      children: [
        // Колонка "Магазин"
        Container(
          width: 150,
          height: 60,
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.grey[300],
            border: Border.all(color: Colors.grey[400]!),
          ),
          alignment: Alignment.center,
          child: const Text(
            'Магазин',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
          ),
        ),
        // Колонки дней
        ...days.map((day) {
          final isWeekend = day.weekday == 6 || day.weekday == 7;
          return Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              color: isWeekend ? Colors.orange[50] : Colors.grey[200],
              border: Border.all(color: Colors.grey[400]!),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  '${day.day}',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    color: isWeekend ? Colors.orange[800] : Colors.black,
                  ),
                ),
                Text(
                  _getWeekdayName(day.weekday),
                  style: TextStyle(
                    fontSize: 10,
                    color: isWeekend ? Colors.orange[600] : Colors.grey[600],
                  ),
                ),
                const SizedBox(height: 2),
                // Подзаголовки У и В
                Row(
                  children: [
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 1),
                        decoration: BoxDecoration(
                          color: _morningColor.withOpacity(0.5),
                          border: Border(right: BorderSide(color: Colors.grey[400]!)),
                        ),
                        child: const Center(
                          child: Text('У', style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold)),
                        ),
                      ),
                    ),
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 1),
                        color: _eveningColor.withOpacity(0.5),
                        child: const Center(
                          child: Text('В', style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold)),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          );
        }),
      ],
    );
  }

  Widget _buildShopRow(Shop shop, List<DateTime> days) {
    return Row(
      children: [
        // Название магазина
        Container(
          width: 150,
          height: 40,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border.all(color: Colors.grey[300]!),
          ),
          alignment: Alignment.centerLeft,
          child: Text(
            shop.address,
            style: const TextStyle(fontSize: 11),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        // Ячейки дней (делятся на 2)
        ...days.map((day) => _buildDayCell(shop, day)),
      ],
    );
  }

  Widget _buildDayCell(Shop shop, DateTime day) {
    final entry = _getEntryForCell(shop.address, day);
    final hasShift = entry != null;

    // Определяем, какая половина занята
    final isEvening = hasShift && _isEveningShift(entry.shiftType);
    final isMorningOrDay = hasShift && !_isEveningShift(entry.shiftType);

    return Container(
      width: 60,
      height: 40,
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey[300]!),
      ),
      child: Row(
        children: [
          // Утренняя/дневная половина
          Expanded(
            child: InkWell(
              onTap: () => _onCellTap(shop, day),
              child: Container(
                decoration: BoxDecoration(
                  color: isMorningOrDay ? _getCellColor(entry!.shiftType) : Colors.white,
                  border: Border(right: BorderSide(color: Colors.grey[300]!, width: 0.5)),
                ),
                child: Center(
                  child: isMorningOrDay
                    ? Text(
                        _getAbbreviation(entry!),
                        style: const TextStyle(
                          fontSize: 8,
                          fontWeight: FontWeight.bold,
                          color: Colors.black,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.clip,
                      )
                    : null,
                ),
              ),
            ),
          ),
          // Вечерняя половина
          Expanded(
            child: InkWell(
              onTap: () {
                // При клике на вечернюю половину - ставим вечернюю смену
                setState(() {
                  final key = '${shop.address}_${day.toIso8601String().split('T')[0]}';

                  // Удаляем смену на этот день если есть
                  _pendingEntries.removeWhere((k, v) =>
                    v.date.year == day.year &&
                    v.date.month == day.month &&
                    v.date.day == day.day
                  );

                  // Ставим вечернюю смену при клике на правую половину
                  _pendingEntries[key] = WorkScheduleEntry(
                    id: 'pending_${DateTime.now().millisecondsSinceEpoch}',
                    employeeId: widget.employee.id,
                    employeeName: widget.employee.name,
                    shopAddress: shop.address,
                    date: day,
                    shiftType: ShiftType.evening,
                  );
                });
              },
              child: Container(
                color: isEvening ? _getCellColor(entry!.shiftType) : Colors.white,
                child: Center(
                  child: isEvening
                    ? Text(
                        _getAbbreviation(entry!),
                        style: const TextStyle(
                          fontSize: 8,
                          fontWeight: FontWeight.bold,
                          color: Colors.black,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.clip,
                      )
                    : null,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActions() {
    return Container(
      padding: const EdgeInsets.all(16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Отмена'),
          ),
          const SizedBox(width: 12),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF004D40),
              foregroundColor: Colors.white,
            ),
            onPressed: () {
              // Возвращаем список записей
              Navigator.of(context).pop(_pendingEntries.values.toList());
            },
            child: const Text('Сохранить'),
          ),
        ],
      ),
    );
  }
}
