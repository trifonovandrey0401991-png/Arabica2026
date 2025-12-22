import 'package:flutter/material.dart';
import 'employees_page.dart';
import 'shop_model.dart';
import 'shop_service.dart';
import 'employee_service.dart';

class EmployeePreferencesDialog extends StatefulWidget {
  final Employee employee;

  const EmployeePreferencesDialog({
    super.key,
    required this.employee,
  });

  @override
  State<EmployeePreferencesDialog> createState() => _EmployeePreferencesDialogState();
}

class _EmployeePreferencesDialogState extends State<EmployeePreferencesDialog> {
  late Set<String> _selectedDays;
  late Set<String> _selectedShops;
  late Map<String, int> _shiftPreferences;
  List<Shop> _shops = [];
  bool _isLoading = true;
  bool _isSaving = false;

  // Названия дней недели
  static const Map<String, String> _dayNames = {
    'monday': 'Понедельник',
    'tuesday': 'Вторник',
    'wednesday': 'Среда',
    'thursday': 'Четверг',
    'friday': 'Пятница',
    'saturday': 'Суббота',
    'sunday': 'Воскресенье',
  };

  static const List<String> _weekDays = [
    'monday',
    'tuesday',
    'wednesday',
    'thursday',
    'friday',
    'saturday',
    'sunday',
  ];

  // Названия смен
  static const Map<String, String> _shiftNames = {
    'morning': 'Утро',
    'day': 'День',
    'night': 'Ночь',
  };

  // Описания градаций
  static const Map<int, String> _gradeDescriptions = {
    1: 'Всегда хочет работать',
    2: 'Не хочет, но может',
    3: 'Не будет работать',
  };

  @override
  void initState() {
    super.initState();
    _selectedDays = Set<String>.from(widget.employee.preferredWorkDays);
    _selectedShops = Set<String>.from(widget.employee.preferredShops);
    _shiftPreferences = Map<String, int>.from(widget.employee.shiftPreferences);
    // Инициализируем значения по умолчанию, если их нет
    if (!_shiftPreferences.containsKey('morning')) _shiftPreferences['morning'] = 2;
    if (!_shiftPreferences.containsKey('day')) _shiftPreferences['day'] = 2;
    if (!_shiftPreferences.containsKey('night')) _shiftPreferences['night'] = 2;
    _loadShops();
  }

  Future<void> _loadShops() async {
    try {
      final shops = await ShopService.getShops();
      setState(() {
        _shops = shops;
        _isLoading = false;
      });
    } catch (e) {
      print('❌ Ошибка загрузки магазинов: $e');
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _savePreferences() async {
    setState(() {
      _isSaving = true;
    });

    try {
      // Очищаем список магазинов от адресов, оставляем только ID
      final shopIds = _shops
          .where((shop) => _selectedShops.contains(shop.id) || _selectedShops.contains(shop.address))
          .map((shop) => shop.id)
          .toList();

      final updatedEmployee = widget.employee.copyWith(
        preferredWorkDays: _selectedDays.toList(),
        preferredShops: shopIds,
        shiftPreferences: _shiftPreferences,
      );

      final result = await EmployeeService.updateEmployee(
        id: updatedEmployee.id,
        name: updatedEmployee.name,
        phone: updatedEmployee.phone,
        isAdmin: updatedEmployee.isAdmin,
        employeeName: updatedEmployee.employeeName,
        preferredWorkDays: updatedEmployee.preferredWorkDays,
        preferredShops: updatedEmployee.preferredShops,
        shiftPreferences: updatedEmployee.shiftPreferences,
      );

      if (result != null && mounted) {
        Navigator.of(context).pop(true); // Возвращаем true для обновления данных
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Ошибка сохранения предпочтений'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      print('❌ Ошибка сохранения предпочтений: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка: $e'),
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

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: Container(
        width: MediaQuery.of(context).size.width * 0.9,
        constraints: const BoxConstraints(maxWidth: 500, maxHeight: 700),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Заголовок
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF004D40),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(8),
                  topRight: Radius.circular(8),
                ),
              ),
              child: Row(
                children: [
                  const Icon(Icons.settings, color: Colors.white),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Предпочтения сотрудника',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            // Содержимое
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Информация о сотруднике
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Row(
                          children: [
                            CircleAvatar(
                              backgroundColor: const Color(0xFF004D40),
                              child: Text(
                                widget.employee.name.isNotEmpty
                                    ? widget.employee.name[0].toUpperCase()
                                    : '?',
                                style: const TextStyle(color: Colors.white),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    widget.employee.name,
                                    style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  if (widget.employee.phone != null)
                                    Text(
                                      widget.employee.phone!,
                                      style: TextStyle(
                                        fontSize: 14,
                                        color: Colors.grey[600],
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    // Желаемые дни работы
                    const Text(
                      'Желаемые дни работы:',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    ..._weekDays.map((day) {
                      final isSelected = _selectedDays.contains(day);
                      return CheckboxListTile(
                        title: Text(_dayNames[day] ?? day),
                        value: isSelected,
                        onChanged: (value) {
                          setState(() {
                            if (value == true) {
                              _selectedDays.add(day);
                            } else {
                              _selectedDays.remove(day);
                            }
                          });
                        },
                        contentPadding: EdgeInsets.zero,
                      );
                    }),
                    const SizedBox(height: 24),
                    // Желаемые магазины
                    const Text(
                      'Желаемые магазины:',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (_isLoading)
                      const Center(child: CircularProgressIndicator())
                    else if (_shops.isEmpty)
                      const Padding(
                        padding: EdgeInsets.all(16.0),
                        child: Text(
                          'Магазины не найдены',
                          style: TextStyle(color: Colors.grey),
                        ),
                      )
                    else
                      ..._shops.map((shop) {
                        // Проверяем по ID или адресу (для обратной совместимости)
                        final isSelected = _selectedShops.contains(shop.id) ||
                            _selectedShops.contains(shop.address);
                        return CheckboxListTile(
                          title: Text(shop.name),
                          subtitle: Text(
                            shop.address,
                            style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                          ),
                          value: isSelected,
                          onChanged: (value) {
                            setState(() {
                              if (value == true) {
                                // Удаляем старые значения (адрес) и добавляем ID
                                _selectedShops.remove(shop.address);
                                if (!_selectedShops.contains(shop.id)) {
                                  _selectedShops.add(shop.id);
                                }
                              } else {
                                // Удаляем и ID и адрес
                                _selectedShops.remove(shop.id);
                                _selectedShops.remove(shop.address);
                              }
                            });
                          },
                          contentPadding: EdgeInsets.zero,
                        );
                      }),
                    const SizedBox(height: 24),
                    // Предпочтения смен
                    const Text(
                      'Предпочтения смен:',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    ...['morning', 'day', 'night'].map((shiftKey) {
                      final shiftName = _shiftNames[shiftKey] ?? shiftKey;
                      final currentGrade = _shiftPreferences[shiftKey] ?? 2;
                      return Card(
                        margin: const EdgeInsets.only(bottom: 12),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                shiftName,
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 8),
                              ...([1, 2, 3] as List<int>).map((grade) {
                                final isSelected = currentGrade == grade;
                                return RadioListTile<int>(
                                  title: Text(
                                    _gradeDescriptions[grade] ?? 'Градация $grade',
                                    style: TextStyle(
                                      color: isSelected ? const Color(0xFF004D40) : Colors.black87,
                                      fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                                    ),
                                  ),
                                  value: grade,
                                  groupValue: currentGrade,
                                  onChanged: (value) {
                                    setState(() {
                                      _shiftPreferences[shiftKey] = value!;
                                    });
                                  },
                                  contentPadding: EdgeInsets.zero,
                                  dense: true,
                                );
                              }),
                            ],
                          ),
                        ),
                      );
                    }),
                  ],
                ),
              ),
            ),
            // Кнопки
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                border: Border(
                  top: BorderSide(color: Colors.grey[300]!),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: _isSaving ? null : () => Navigator.of(context).pop(),
                    child: const Text('Отмена'),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: _isSaving ? null : _savePreferences,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF004D40),
                    ),
                    child: _isSaving
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                            ),
                          )
                        : const Text('Сохранить'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

