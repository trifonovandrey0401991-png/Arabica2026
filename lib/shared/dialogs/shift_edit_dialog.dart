import 'package:flutter/material.dart';
import '../../features/work_schedule/models/work_schedule_model.dart';
import '../../features/employees/pages/employees_page.dart';
import '../../features/shops/models/shop_model.dart';
import '../../features/shops/models/shop_settings_model.dart';
import '../../features/shops/services/shop_service.dart';
import '../../core/utils/logger.dart';

/// Диалог редактирования смены с двумя вкладками
class ShiftEditDialog extends StatefulWidget {
  final WorkScheduleEntry? existingEntry;
  final DateTime date;
  final Employee employee;
  final WorkSchedule schedule;
  final List<Employee> allEmployees;
  final List<Shop> shops;
  final ShiftType? requiredShiftType; // Если указан - тип смены блокируется
  final Shop? requiredShop; // Если указан - магазин блокируется

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
  });

  @override
  State<ShiftEditDialog> createState() => _ShiftEditDialogState();
}

class _ShiftEditDialogState extends State<ShiftEditDialog>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  // Состояние вкладки редактирования
  Employee? _selectedEmployee;
  ShiftType? _selectedShiftType;
  Shop? _selectedShop;
  bool _isLoading = false;
  Map<String, ShopSettings> _shopSettingsCache = {};

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);

    // Инициализируем значения
    _selectedEmployee = widget.employee;

    // Используем requiredShiftType если задан, иначе из существующей записи или morning по умолчанию
    _selectedShiftType = widget.requiredShiftType ??
                         widget.existingEntry?.shiftType ??
                         ShiftType.morning;

    // Используем requiredShop если задан, иначе находим магазин из существующей записи
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
    setState(() => _isLoading = true);

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

    setState(() => _isLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          Expanded(
            child: Text(
              '${widget.employee.name} - ${widget.date.day}.${widget.date.month}.${widget.date.year}',
              style: const TextStyle(fontSize: 18),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
      content: SizedBox(
        width: MediaQuery.of(context).size.width * 0.85,
        height: MediaQuery.of(context).size.height * 0.7,
        child: Column(
          children: [
            TabBar(
              controller: _tabController,
              labelColor: const Color(0xFF004D40),
              tabs: const [
                Tab(text: 'Редактировать'),
                Tab(text: 'Свободные сотрудники'),
              ],
            ),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildEditTab(),
                  _buildAvailableEmployeesTab(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Вкладка редактирования
  Widget _buildEditTab() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Сотрудник:',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<Employee>(
            value: _selectedEmployee,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
            ),
            isExpanded: true,
            items: widget.allEmployees.map((emp) {
              return DropdownMenuItem<Employee>(
                value: emp,
                child: Text(
                  emp.name,
                  overflow: TextOverflow.ellipsis,
                ),
              );
            }).toList(),
            onChanged: (value) {
              setState(() {
                _selectedEmployee = value;
              });
            },
          ),
          const SizedBox(height: 24),

          Row(
            children: [
              const Text(
                'Тип смены:',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              if (widget.requiredShiftType != null) ...[
                const SizedBox(width: 8),
                const Icon(Icons.lock, size: 16, color: Colors.grey),
                const SizedBox(width: 4),
                const Text(
                  '(заблокировано)',
                  style: TextStyle(fontSize: 12, color: Colors.grey, fontStyle: FontStyle.italic),
                ),
              ],
            ],
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<ShiftType>(
            value: _selectedShiftType,
            decoration: InputDecoration(
              border: const OutlineInputBorder(),
              filled: widget.requiredShiftType != null,
              fillColor: widget.requiredShiftType != null ? Colors.grey[200] : null,
            ),
            isExpanded: true,
            items: ShiftType.values.map((type) {
              return DropdownMenuItem<ShiftType>(
                value: type,
                child: Text(
                  '${type.label} (${type.timeRange})',
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: widget.requiredShiftType != null ? Colors.grey[700] : null,
                  ),
                ),
              );
            }).toList(),
            onChanged: widget.requiredShiftType != null ? null : (value) {
              setState(() {
                _selectedShiftType = value;
              });
            },
          ),
          const SizedBox(height: 24),

          Row(
            children: [
              const Text(
                'Магазин:',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              if (widget.requiredShop != null) ...[
                const SizedBox(width: 8),
                const Icon(Icons.lock, size: 16, color: Colors.grey),
                const SizedBox(width: 4),
                const Text(
                  '(заблокировано)',
                  style: TextStyle(fontSize: 12, color: Colors.grey, fontStyle: FontStyle.italic),
                ),
              ],
            ],
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<Shop>(
            value: _selectedShop,
            decoration: InputDecoration(
              border: const OutlineInputBorder(),
              filled: widget.requiredShop != null,
              fillColor: widget.requiredShop != null ? Colors.grey[200] : null,
            ),
            isExpanded: true,
            items: widget.shops.map((shop) {
              // Получаем аббревиатуру из кэша
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
                    color: widget.requiredShop != null ? Colors.grey[700] : null,
                  ),
                ),
              );
            }).toList(),
            onChanged: widget.requiredShop != null ? null : (value) {
              setState(() {
                _selectedShop = value;
              });
            },
          ),
          const SizedBox(height: 32),

          // Кнопки действий
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              if (widget.existingEntry != null)
                TextButton.icon(
                  onPressed: _deleteShift,
                  icon: const Icon(Icons.delete, color: Colors.red),
                  label: const Text('Удалить смену', style: TextStyle(color: Colors.red)),
                ),
              const Spacer(),
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Отмена'),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: _saveShift,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF004D40),
                  foregroundColor: Colors.white,
                ),
                child: const Text('Сохранить'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Вкладка свободных сотрудников
  Widget _buildAvailableEmployeesTab() {
    final availableEmployees = _getAvailableEmployees();

    if (availableEmployees.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(16.0),
          child: Text(
            'Нет свободных сотрудников на эту дату.\nВсе сотрудники уже имеют смены.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 16),
          ),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(8),
      itemCount: availableEmployees.length,
      itemBuilder: (context, index) {
        final emp = availableEmployees[index];
        final yesterdayStatus = _getYesterdayStatus(emp);

        return Card(
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: const Color(0xFF004D40),
              foregroundColor: Colors.white,
              child: Text(
                emp.name.length >= 2
                  ? emp.name.substring(0, 2).toUpperCase()
                  : emp.name.substring(0, 1).toUpperCase(),
              ),
            ),
            title: Text(
              emp.name,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            subtitle: Text(
              yesterdayStatus,
              style: TextStyle(
                color: yesterdayStatus.contains('Работал')
                  ? Colors.orange
                  : Colors.green,
              ),
            ),
            trailing: const Icon(Icons.arrow_forward),
            onTap: () => _replaceEmployeeAndSave(emp),
          ),
        );
      },
    );
  }

  /// Получить список свободных сотрудников с сортировкой
  List<Employee> _getAvailableEmployees() {
    final availableEmployees = widget.allEmployees.where((emp) {
      // Проверяем: нет ли смены в этот день
      // ИСКЛЮЧЕНИЕ: если это редактирование существующей смены,
      // то исключаем из проверки только ту смену, которую редактируем
      final hasShift = widget.schedule.entries.any((e) {
        // Если это та же смена, которую редактируем - не считаем её
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

    // Сортируем по приоритету (от лучшего к худшему):
    // 5 (ЛУЧШИЙ): Выходной вчера И выходной завтра
    // 4: Работал вчера ИЛИ будет завтра (но не оба)
    // 3: Работал вчера И будет завтра
    // 2: Работает сегодня (другая смена)
    // 1 (ХУДШИЙ): Работает сегодня И завтра
    availableEmployees.sort((a, b) {
      final aScore = _getEmployeePriorityScore(a);
      final bScore = _getEmployeePriorityScore(b);
      return bScore.compareTo(aScore); // От большего к меньшему (лучшие вверху)
    });

    return availableEmployees;
  }

  /// Рассчитать приоритет сотрудника (чем больше - тем лучше подходит)
  int _getEmployeePriorityScore(Employee emp) {
    final yesterday = widget.date.subtract(const Duration(days: 1));
    final today = widget.date;
    final tomorrow = widget.date.add(const Duration(days: 1));

    // Проверяем вчера
    final hadYesterday = widget.schedule.entries.any((e) =>
      e.employeeId == emp.id &&
      e.date.year == yesterday.year &&
      e.date.month == yesterday.month &&
      e.date.day == yesterday.day
    );

    // Проверяем сегодня (другие смены кроме той, которую редактируем)
    final todayEntries = widget.schedule.entries.where((e) =>
      e.employeeId == emp.id &&
      e.date.year == today.year &&
      e.date.month == today.month &&
      e.date.day == today.day
    ).toList();

    final hasToday = todayEntries.isNotEmpty;

    // Проверяем завтра
    final hasTomorrow = widget.schedule.entries.any((e) =>
      e.employeeId == emp.id &&
      e.date.year == tomorrow.year &&
      e.date.month == tomorrow.month &&
      e.date.day == tomorrow.day
    );

    // Приоритет 1 (ХУДШИЙ): Работает сегодня (вечер) и завтра
    if (hasToday && hasTomorrow) return 1;

    // Приоритет 2: Работает сегодня
    if (hasToday) return 2;

    // Приоритет 3: Работал вчера и будет завтра (но сегодня свободен)
    if (hadYesterday && hasTomorrow) return 3;

    // Приоритет 4: Работал вчера ИЛИ будет завтра
    if (hadYesterday || hasTomorrow) return 4;

    // Приоритет 5 (ЛУЧШИЙ): Был выходной вчера и будет выходной завтра
    return 5;
  }

  /// Получить статус вчерашнего/завтрашнего дня для сотрудника
  String _getYesterdayStatus(Employee emp) {
    // Проверяем вчерашний день
    final yesterday = widget.date.subtract(const Duration(days: 1));
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

    // Проверяем завтрашний день
    final tomorrow = widget.date.add(const Duration(days: 1));
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

    // Формируем сообщение
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
        const SnackBar(
          content: Text('Ошибка: не выбран тип смены или магазин'),
          backgroundColor: Colors.red,
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
    if (_selectedEmployee == null || _selectedShiftType == null || _selectedShop == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Заполните все поля'),
          backgroundColor: Colors.red,
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
      Logger.error('Попытка удаления несуществующей смены (existingEntry == null)', null);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Ошибка: Смена не найдена'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }

    Logger.debug('existingEntry: ID="${widget.existingEntry!.id}", employee="${widget.existingEntry!.employeeName}", date=${widget.date}');

    if (widget.existingEntry!.id.isEmpty) {
      Logger.error('ID смены пустой (empty string)', null);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Ошибка: ID смены не найден (пустая строка)'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }

    Logger.debug('ID смены валиден: "${widget.existingEntry!.id}", показываем диалог подтверждения');

    // Запрашиваем подтверждение
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Подтверждение'),
        content: Text(
          'Удалить смену сотрудника ${widget.existingEntry!.employeeName}?\n'
          'Дата: ${widget.date.day}.${widget.date.month}.${widget.date.year}\n'
          'Смена: ${widget.existingEntry!.shiftType.label}\n'
          'ID: ${widget.existingEntry!.id}',
        ),
        actions: [
          TextButton(
            onPressed: () {
              Logger.debug('Удаление отменено пользователем');
              Navigator.of(context).pop(false);
            },
            child: const Text('Отмена'),
          ),
          ElevatedButton(
            onPressed: () {
              Logger.debug('Удаление подтверждено пользователем');
              Navigator.of(context).pop(true);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('Удалить'),
          ),
        ],
      ),
    );

    Logger.debug('Результат диалога подтверждения: $confirmed');

    if (confirmed == true) {
      Logger.debug('Удаление смены подтверждено: ID="${widget.existingEntry!.id}"');
      if (mounted) {
        Logger.debug('Контекст смонтирован, закрываем диалог с action=delete');
        Navigator.of(context).pop({
          'action': 'delete',
          'entry': widget.existingEntry,
        });
      } else {
        Logger.error('Контекст НЕ смонтирован, не можем закрыть диалог!', null);
      }
    } else {
      Logger.debug('Удаление не подтверждено (confirmed != true)');
    }
  }
}
