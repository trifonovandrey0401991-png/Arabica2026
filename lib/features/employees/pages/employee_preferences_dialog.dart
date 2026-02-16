import 'package:flutter/material.dart';
import 'employees_page.dart';
import '../../shops/models/shop_model.dart';
import '../../shops/services/shop_service.dart';
import '../services/employee_service.dart';
import '../../../core/utils/logger.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

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
  static Map<String, String> _dayNames = {
    'monday': 'Понедельник',
    'tuesday': 'Вторник',
    'wednesday': 'Среда',
    'thursday': 'Четверг',
    'friday': 'Пятница',
    'saturday': 'Суббота',
    'sunday': 'Воскресенье',
  };

  static List<String> _weekDays = [
    'monday',
    'tuesday',
    'wednesday',
    'thursday',
    'friday',
    'saturday',
    'sunday',
  ];

  // Названия смен
  static Map<String, String> _shiftNames = {
    'morning': 'Утро',
    'day': 'День',
    'night': 'Ночь',
  };

  // Описания градаций
  static Map<int, String> _gradeDescriptions = {
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
      Logger.error('Ошибка загрузки магазинов', e);
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
            SnackBar(
              content: Text('Ошибка сохранения предпочтений'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      Logger.error('Ошибка сохранения предпочтений', e);
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
        constraints: BoxConstraints(maxWidth: 500, maxHeight: 700),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Заголовок
            Container(
              padding: EdgeInsets.all(16.w),
              decoration: BoxDecoration(
                color: Color(0xFF004D40),
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(8.r),
                  topRight: Radius.circular(8.r),
                ),
              ),
              child: Row(
                children: [
                  Icon(Icons.settings, color: Colors.white),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Предпочтения сотрудника',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18.sp,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.close, color: Colors.white),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            // Содержимое
            Flexible(
              child: SingleChildScrollView(
                padding: EdgeInsets.all(16.w),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Информация о сотруднике
                    Card(
                      child: Padding(
                        padding: EdgeInsets.all(12.w),
                        child: Row(
                          children: [
                            CircleAvatar(
                              backgroundColor: Color(0xFF004D40),
                              child: Text(
                                widget.employee.name.isNotEmpty
                                    ? widget.employee.name[0].toUpperCase()
                                    : '?',
                                style: TextStyle(color: Colors.white),
                              ),
                            ),
                            SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    widget.employee.name,
                                    style: TextStyle(
                                      fontSize: 16.sp,
                                      fontWeight: FontWeight.bold,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  if (widget.employee.phone != null)
                                    Text(
                                      widget.employee.phone!,
                                      style: TextStyle(
                                        fontSize: 14.sp,
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
                    SizedBox(height: 24),
                    // Желаемые дни работы
                    Text(
                      'Желаемые дни работы:',
                      style: TextStyle(
                        fontSize: 16.sp,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    SizedBox(height: 12),
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
                    SizedBox(height: 24),
                    // Желаемые магазины
                    Text(
                      'Желаемые магазины:',
                      style: TextStyle(
                        fontSize: 16.sp,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    SizedBox(height: 12),
                    if (_isLoading)
                      Center(child: CircularProgressIndicator())
                    else if (_shops.isEmpty)
                      Padding(
                        padding: EdgeInsets.all(16.0.w),
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
                          title: Text(
                            shop.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                            shop.address,
                            style: TextStyle(fontSize: 12.sp, color: Colors.grey[600]),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
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
                    SizedBox(height: 24),
                    // Предпочтения смен
                    Text(
                      'Предпочтения смен:',
                      style: TextStyle(
                        fontSize: 16.sp,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    SizedBox(height: 12),
                    ...['morning', 'day', 'night'].map((shiftKey) {
                      final shiftName = _shiftNames[shiftKey] ?? shiftKey;
                      final currentGrade = _shiftPreferences[shiftKey] ?? 2;
                      return Card(
                        margin: EdgeInsets.only(bottom: 12.h),
                        child: Padding(
                          padding: EdgeInsets.all(12.w),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                shiftName,
                                style: TextStyle(
                                  fontSize: 16.sp,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              SizedBox(height: 8),
                              ...([1, 2, 3] as List<int>).map((grade) {
                                final isSelected = currentGrade == grade;
                                return RadioListTile<int>(
                                  title: Text(
                                    _gradeDescriptions[grade] ?? 'Градация $grade',
                                    style: TextStyle(
                                      color: isSelected ? Color(0xFF004D40) : Colors.black87,
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
              padding: EdgeInsets.all(16.w),
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
                    child: Text('Отмена'),
                  ),
                  SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: _isSaving ? null : _savePreferences,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Color(0xFF004D40),
                    ),
                    child: _isSaving
                        ? SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                            ),
                          )
                        : Text('Сохранить'),
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

