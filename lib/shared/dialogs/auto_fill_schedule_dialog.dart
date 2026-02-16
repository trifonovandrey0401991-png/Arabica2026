import 'package:flutter/material.dart';
import '../../features/work_schedule/models/work_schedule_model.dart';
import '../../features/employees/pages/employees_page.dart';
import '../../features/shops/models/shop_model.dart';
import '../../features/shops/models/shop_settings_model.dart';
import '../../core/utils/logger.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

/// Диалог выбора параметров автозаполнения графика
class AutoFillScheduleDialog extends StatefulWidget {
  final DateTime selectedMonth;
  final int startDay;
  final int endDay;
  final WorkSchedule? schedule;
  final List<Employee> employees;
  final List<Shop> shops;
  final Map<String, ShopSettings> shopSettingsCache;

  const AutoFillScheduleDialog({
    super.key,
    required this.selectedMonth,
    required this.startDay,
    required this.endDay,
    required this.schedule,
    required this.employees,
    required this.shops,
    required this.shopSettingsCache,
  });

  @override
  State<AutoFillScheduleDialog> createState() => _AutoFillScheduleDialogState();
}

class _AutoFillScheduleDialogState extends State<AutoFillScheduleDialog> {
  late int _selectedStartDay;
  late int _selectedEndDay;
  bool _replaceExisting = false;
  final bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    // Ограничиваем значения максимальным днём месяца
    final maxDay = DateTime(widget.selectedMonth.year, widget.selectedMonth.month + 1, 0).day;
    _selectedStartDay = widget.startDay.clamp(1, maxDay);
    _selectedEndDay = widget.endDay.clamp(_selectedStartDay, maxDay);
  }

  int get _maxDay {
    final lastDay = DateTime(widget.selectedMonth.year, widget.selectedMonth.month + 1, 0);
    return lastDay.day;
  }

  Future<void> _performAutoFill() async {
    Logger.debug('📋 Диалог автозаполнения: нажата кнопка Заполнить');
    Logger.debug('   Период: с $_selectedStartDay по $_selectedEndDay');
    Logger.debug('   Режим: ${_replaceExisting ? "Заменить" : "Только пустые"}');

    if (_selectedStartDay > _selectedEndDay) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Начальный день не может быть больше конечного'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    Logger.debug('✅ Диалог автозаполнения: возвращаем результат');
    Logger.debug('   mounted: $mounted');

    // Возвращаем результат диалога
    if (mounted) {
      final result = {
        'startDay': _selectedStartDay,
        'endDay': _selectedEndDay,
        'replaceExisting': _replaceExisting,
      };
      Logger.debug('   Результат: $result');
      Navigator.of(context).pop(result);
      Logger.debug('   Navigator.pop вызван');
    } else {
      Logger.warning('   ⚠️ Диалог не mounted!');
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Автозаполнение графика'),
      content: SizedBox(
        width: MediaQuery.of(context).size.width * 0.8,
        child: _isLoading
            ? Center(child: CircularProgressIndicator())
            : SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Выберите период:',
                      style: TextStyle(
                        fontSize: 16.sp,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    SizedBox(height: 16),
                    Row(
                      children: [
                        Text('С: '),
                        Expanded(
                          child: DropdownButtonFormField<int>(
                            value: _selectedStartDay,
                            decoration: InputDecoration(
                              border: OutlineInputBorder(),
                            ),
                            items: List.generate(_maxDay, (i) => i + 1).map((day) {
                              return DropdownMenuItem<int>(
                                value: day,
                                child: Text('$day'),
                              );
                            }).toList(),
                            onChanged: (value) {
                              if (value != null) {
                                setState(() {
                                  _selectedStartDay = value;
                                  if (_selectedEndDay < _selectedStartDay) {
                                    _selectedEndDay = _selectedStartDay;
                                  }
                                });
                              }
                            },
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: 16),
                    Row(
                      children: [
                        Text('По: '),
                        Expanded(
                          child: DropdownButtonFormField<int>(
                            value: _selectedEndDay,
                            decoration: InputDecoration(
                              border: OutlineInputBorder(),
                            ),
                            items: List.generate(
                              _maxDay - _selectedStartDay + 1,
                              (i) => _selectedStartDay + i,
                            ).map((day) {
                              return DropdownMenuItem<int>(
                                value: day,
                                child: Text('$day'),
                              );
                            }).toList(),
                            onChanged: (value) {
                              if (value != null) {
                                setState(() {
                                  _selectedEndDay = value;
                                });
                              }
                            },
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: 24),
                    Text(
                      'Режим заполнения:',
                      style: TextStyle(
                        fontSize: 16.sp,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    SizedBox(height: 12),
                    RadioListTile<bool>(
                      title: Text('Заменить все существующие смены'),
                      subtitle: Text('Удалить все смены в периоде и заполнить заново'),
                      value: true,
                      groupValue: _replaceExisting,
                      onChanged: (value) {
                        setState(() {
                          _replaceExisting = value ?? false;
                        });
                      },
                    ),
                    RadioListTile<bool>(
                      title: Text('Заполнить только пустые дни'),
                      subtitle: Text('Оставить существующие смены без изменений'),
                      value: false,
                      groupValue: _replaceExisting,
                      onChanged: (value) {
                        setState(() {
                          _replaceExisting = value ?? false;
                        });
                      },
                    ),
                  ],
                ),
              ),
      ),
      actions: [
        TextButton(
          onPressed: _isLoading ? null : () => Navigator.of(context).pop(),
          child: Text('Отмена'),
        ),
        ElevatedButton(
          onPressed: _isLoading ? null : _performAutoFill,
          style: ElevatedButton.styleFrom(
            backgroundColor: Color(0xFF004D40),
            foregroundColor: Colors.white,
          ),
          child: Text('Заполнить'),
        ),
      ],
    );
  }
}

