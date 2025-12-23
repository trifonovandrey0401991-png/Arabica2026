import 'package:flutter/material.dart';
import 'employees_page.dart';
import 'work_schedule_model.dart';
import 'work_schedule_service.dart';
import 'shop_model.dart';
import 'shop_settings_model.dart';
import 'employee_preferences_dialog.dart';
import 'work_schedule_validator.dart';
import 'schedule_validation_dialog.dart';
import 'employee_service.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

/// Страница расписания сотрудника для проставления смен
class EmployeeSchedulePage extends StatefulWidget {
  final Employee employee;
  final DateTime selectedMonth;
  final int startDay;
  final int endDay;
  final List<Shop> shops;
  final WorkSchedule? schedule;
  final Map<String, ShopSettings> shopSettingsCache;
  final VoidCallback onScheduleUpdated;

  const EmployeeSchedulePage({
    super.key,
    required this.employee,
    required this.selectedMonth,
    required this.startDay,
    required this.endDay,
    required this.shops,
    this.schedule,
    required this.shopSettingsCache,
    required this.onScheduleUpdated,
  });

  @override
  State<EmployeeSchedulePage> createState() => _EmployeeSchedulePageState();
}

class _EmployeeSchedulePageState extends State<EmployeeSchedulePage> {
  late Employee _employee;
  WorkSchedule? _schedule;
  Map<String, ShopSettings> _shopSettingsCache = {};
  List<ShopAbbreviation> _allAbbreviations = [];
  Map<DateTime, String?> _selectedAbbreviations = {}; // Дата -> выбранная аббревиатура
  bool _isLoading = false;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _employee = widget.employee;
    _schedule = widget.schedule;
    _shopSettingsCache = Map.from(widget.shopSettingsCache);
    _initializeData();
  }

  Future<void> _initializeData() async {
    setState(() {
      _isLoading = true;
    });
    await _refreshSchedule();
    await _loadAbbreviations();
  }

  Future<void> _refreshSchedule() async {
    try {
      final schedule = await WorkScheduleService.getSchedule(widget.selectedMonth);
      setState(() {
        _schedule = schedule;
      });
    } catch (e) {
      print('Ошибка загрузки графика: $e');
    }
  }

  Future<void> _loadAbbreviations() async {
    final List<ShopAbbreviation> abbreviations = [];
    
    for (var shop in widget.shops) {
      final settings = _shopSettingsCache[shop.address];
      if (settings == null) continue;
      
      if (settings.morningAbbreviation != null && settings.morningAbbreviation!.isNotEmpty) {
        abbreviations.add(ShopAbbreviation(
          abbreviation: settings.morningAbbreviation!,
          shopAddress: shop.address,
          shopName: shop.name,
          shiftType: ShiftType.morning,
        ));
      }
      if (settings.dayAbbreviation != null && settings.dayAbbreviation!.isNotEmpty) {
        abbreviations.add(ShopAbbreviation(
          abbreviation: settings.dayAbbreviation!,
          shopAddress: shop.address,
          shopName: shop.name,
          shiftType: ShiftType.day,
        ));
      }
      if (settings.nightAbbreviation != null && settings.nightAbbreviation!.isNotEmpty) {
        abbreviations.add(ShopAbbreviation(
          abbreviation: settings.nightAbbreviation!,
          shopAddress: shop.address,
          shopName: shop.name,
          shiftType: ShiftType.evening,
        ));
      }
    }
    
    setState(() {
      _allAbbreviations = abbreviations;
    });
  }

  void _loadExistingShifts() {
    if (_schedule == null || _allAbbreviations.isEmpty) return;
    
    final days = _getDaysInMonth();
    for (var day in days) {
      if (!_schedule!.hasEntry(_employee.id, day)) continue;
      
      try {
        final entry = _schedule!.getEntry(_employee.id, day);
        if (entry == null) continue;
        
        // Находим аббревиатуру для этой записи
        final abbrev = _allAbbreviations.firstWhere(
          (a) => a.shopAddress == entry.shopAddress && a.shiftType == entry.shiftType,
          orElse: () => ShopAbbreviation(
            abbreviation: '',
            shopAddress: entry.shopAddress,
            shopName: '',
            shiftType: entry.shiftType,
          ),
        );
        if (abbrev.abbreviation.isNotEmpty) {
          _selectedAbbreviations[day] = abbrev.abbreviation;
        }
      } catch (e) {
        // Запись не найдена - это нормально
      }
    }
    
    if (mounted) {
      setState(() {});
    }
  }

  List<DateTime> _getDaysInMonth() {
    final firstDay = DateTime(widget.selectedMonth.year, widget.selectedMonth.month, 1);
    final lastDay = DateTime(widget.selectedMonth.year, widget.selectedMonth.month + 1, 0);
    final maxDay = lastDay.day;
    final actualStartDay = widget.startDay.clamp(1, maxDay);
    final actualEndDay = widget.endDay.clamp(actualStartDay, maxDay);
    
    final days = <DateTime>[];
    for (var i = actualStartDay; i <= actualEndDay; i++) {
      days.add(DateTime(widget.selectedMonth.year, widget.selectedMonth.month, i));
    }
    return days;
  }

  /// Проверяет, является ли магазин предпочтительным для сотрудника
  bool _isShopPreferred(String shopAddress) {
    return _employee.preferredShops.contains(shopAddress) ||
           _employee.preferredShops.any((id) => 
             widget.shops.any((shop) => shop.id == id && shop.address == shopAddress)
           );
  }

  /// Проверяет, занята ли аббревиатура в этот день
  bool _isAbbreviationOccupied(String abbreviation, DateTime day) {
    if (_schedule == null) return false;
    
    final abbrev = _allAbbreviations.firstWhere(
      (a) => a.abbreviation == abbreviation,
      orElse: () => ShopAbbreviation(
        abbreviation: '',
        shopAddress: '',
        shopName: '',
        shiftType: ShiftType.morning,
      ),
    );
    
    if (abbrev.abbreviation.isEmpty) return false;
    
    // Проверяем, есть ли смена с этой аббревиатурой в этот день (любым сотрудником)
    return _schedule!.entries.any((entry) =>
        entry.date.year == day.year &&
        entry.date.month == day.month &&
        entry.date.day == day.day &&
        entry.shopAddress == abbrev.shopAddress &&
        entry.shiftType == abbrev.shiftType);
  }

  /// Обработка выбора аббревиатуры
  void _toggleAbbreviation(DateTime day, String abbreviation) {
    setState(() {
      if (_selectedAbbreviations[day] == abbreviation) {
        // Отмена выбора
        _selectedAbbreviations.remove(day);
      } else {
        // Выбор новой аббревиатуры
        _selectedAbbreviations[day] = abbreviation;
      }
    });
  }

  Future<void> _editPreferences() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => EmployeePreferencesDialog(employee: _employee),
    );
    
    if (result == true) {
      // Обновляем данные сотрудника
      final updatedEmployee = await EmployeeService.getEmployee(_employee.id);
      if (updatedEmployee != null) {
        setState(() {
          _employee = updatedEmployee;
        });
      }
    }
  }

  Future<void> _saveShifts() async {
    if (_selectedAbbreviations.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Не выбрано ни одной смены'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() {
      _isSaving = true;
    });

    try {
      final List<String> allWarnings = [];
      final List<WorkScheduleEntry> entriesToSave = [];
      
      // Сначала проверяем валидацию для всех выбранных смен
      for (var entry in _selectedAbbreviations.entries) {
        final day = entry.key;
        final abbreviation = entry.value;
        
        if (abbreviation == null) continue;
        
        final abbrev = _allAbbreviations.firstWhere(
          (a) => a.abbreviation == abbreviation,
        );
        
        // Проверяем, есть ли уже запись для этого дня
        String? existingId;
        if (_schedule != null && _schedule!.hasEntry(_employee.id, day)) {
          try {
            final existingEntry = _schedule!.getEntry(_employee.id, day);
            if (existingEntry != null) {
              existingId = existingEntry.id;
            }
          } catch (e) {
            // Запись не найдена - создадим новую
          }
        }
        
        final shiftEntry = WorkScheduleEntry(
          id: existingId ?? '', // Используем существующий ID или создаем новый
          employeeId: _employee.id,
          employeeName: _employee.name,
          shopAddress: abbrev.shopAddress,
          date: day,
          shiftType: abbrev.shiftType,
        );
        
        entriesToSave.add(shiftEntry);
        
        // Проверяем валидацию
        if (_schedule != null) {
          final warnings = WorkScheduleValidator.checkShiftConflict(shiftEntry, _schedule!);
          allWarnings.addAll(warnings);
        }
      }
      
      // Показываем предупреждения, если есть
      if (allWarnings.isNotEmpty) {
        final shouldContinue = await showDialog<bool>(
          context: context,
          builder: (context) => ScheduleValidationDialog(warnings: allWarnings),
        );
        
        if (shouldContinue != true) {
          setState(() {
            _isSaving = false;
          });
          return;
        }
      }
      
      // Сохраняем каждую выбранную смену
      for (var shiftEntry in entriesToSave) {
        await WorkScheduleService.saveShift(shiftEntry);
      }
      
      // Удаляем смены, которые были сняты
      if (_schedule != null) {
        final days = _getDaysInMonth();
        for (var day in days) {
          if (!_selectedAbbreviations.containsKey(day)) {
            try {
              final existingEntry = _schedule!.getEntry(_employee.id, day);
              if (existingEntry != null && existingEntry.id.isNotEmpty) {
                await WorkScheduleService.deleteShift(existingEntry.id);
              }
            } catch (e) {
              // Запись не найдена - это нормально
            }
          }
        }
      }
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Смены успешно сохранены'),
            backgroundColor: Colors.green,
          ),
        );
        widget.onScheduleUpdated();
        Navigator.of(context).pop();
      }
    } catch (e) {
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
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  String _getWeekdayName(int weekday) {
    const weekdays = ['Пн', 'Вт', 'Ср', 'Чт', 'Пт', 'Сб', 'Вс'];
    return weekdays[weekday - 1];
  }

  @override
  Widget build(BuildContext context) {
    final days = _getDaysInMonth();
    
    return Scaffold(
      appBar: AppBar(
        title: Text(_employee.name),
        backgroundColor: const Color(0xFF004D40),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: _editPreferences,
            tooltip: 'Редактировать предпочтения',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // Секция предпочтений
                _buildPreferencesSection(),
                // Список дней
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: days.length,
                    itemBuilder: (context, index) {
                      final day = days[index];
                      return _buildDayCard(day);
                    },
                  ),
                ),
              ],
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _isSaving ? null : _saveShifts,
        backgroundColor: const Color(0xFF004D40),
        icon: _isSaving
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              )
            : const Icon(Icons.save),
        label: Text(_isSaving ? 'Сохранение...' : 'Сохранить смены'),
      ),
    );
  }

  Widget _buildPreferencesSection() {
    return Container(
      padding: const EdgeInsets.all(16),
      color: Colors.grey[100],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Предпочтения сотрудника',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              TextButton.icon(
                onPressed: _editPreferences,
                icon: const Icon(Icons.edit, size: 16),
                label: const Text('Редактировать'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (_employee.preferredWorkDays.isNotEmpty)
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: _employee.preferredWorkDays.map((day) {
                const dayNames = {
                  'monday': 'Пн',
                  'tuesday': 'Вт',
                  'wednesday': 'Ср',
                  'thursday': 'Чт',
                  'friday': 'Пт',
                  'saturday': 'Сб',
                  'sunday': 'Вс',
                };
                return Chip(
                  label: Text(dayNames[day] ?? day),
                  backgroundColor: Colors.green[100],
                );
              }).toList(),
            ),
          if (_employee.preferredShops.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: _employee.preferredShops.map((shopId) {
                final shop = widget.shops.firstWhere(
                  (s) => s.id == shopId || s.address == shopId,
                  orElse: () => Shop(
                    id: shopId,
                    name: shopId,
                    address: shopId,
                    icon: Icons.store,
                  ),
                );
                return Chip(
                  label: Text(shop.name),
                  backgroundColor: Colors.blue[100],
                );
              }).toList(),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildDayCard(DateTime day) {
    final selectedAbbrev = _selectedAbbreviations[day];
    
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${day.day} (${_getWeekdayName(day.weekday)})',
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _allAbbreviations.map((abbrev) {
                final isSelected = selectedAbbrev == abbrev.abbreviation;
                final isPreferred = _isShopPreferred(abbrev.shopAddress);
                final isOccupied = _isAbbreviationOccupied(abbrev.abbreviation, day);
                
                return _buildAbbreviationChip(
                  abbrev,
                  isSelected,
                  isPreferred,
                  isOccupied,
                  () => _toggleAbbreviation(day, abbrev.abbreviation),
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAbbreviationChip(
    ShopAbbreviation abbrev,
    bool isSelected,
    bool isPreferred,
    bool isOccupied,
    VoidCallback onTap,
  ) {
    Color? backgroundColor;
    Color borderColor = Colors.grey;
    double borderWidth = 1.0;
    
    if (isSelected) {
      backgroundColor = abbrev.shiftType.color.withOpacity(0.2);
      borderColor = abbrev.shiftType.color;
      borderWidth = 2.0;
    } else if (isOccupied) {
      backgroundColor = Colors.red[50];
      borderColor = Colors.red;
    }
    
    return InkWell(
      onTap: isOccupied ? null : onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: backgroundColor,
          border: Border.all(
            color: borderColor,
            width: borderWidth,
          ),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Индикатор точки
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: isPreferred
                    ? Colors.green
                    : isOccupied
                        ? Colors.red
                        : Colors.transparent,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              abbrev.abbreviation,
              style: TextStyle(
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                color: isSelected ? abbrev.shiftType.color : Colors.black87,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Вспомогательный класс для хранения информации об аббревиатуре
class ShopAbbreviation {
  final String abbreviation;
  final String shopAddress;
  final String shopName;
  final ShiftType shiftType;

  ShopAbbreviation({
    required this.abbreviation,
    required this.shopAddress,
    required this.shopName,
    required this.shiftType,
  });
}

