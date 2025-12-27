import 'package:flutter/material.dart';
import 'work_schedule_model.dart';
import 'employees_page.dart';
import 'shop_model.dart';
import 'shop_settings_model.dart';

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
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _selectedStartDay = widget.startDay;
    _selectedEndDay = widget.endDay;
  }

  int get _maxDay {
    final lastDay = DateTime(widget.selectedMonth.year, widget.selectedMonth.month + 1, 0);
    return lastDay.day;
  }

  Future<void> _performAutoFill() async {
    if (_selectedStartDay > _selectedEndDay) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Начальный день не может быть больше конечного'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    // Возвращаем результат диалога
    if (mounted) {
      Navigator.of(context).pop({
        'startDay': _selectedStartDay,
        'endDay': _selectedEndDay,
        'replaceExisting': _replaceExisting,
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Автозаполнение графика'),
      content: SizedBox(
        width: MediaQuery.of(context).size.width * 0.8,
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Выберите период:',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        const Text('С: '),
                        Expanded(
                          child: DropdownButtonFormField<int>(
                            value: _selectedStartDay,
                            decoration: const InputDecoration(
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
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        const Text('По: '),
                        Expanded(
                          child: DropdownButtonFormField<int>(
                            value: _selectedEndDay,
                            decoration: const InputDecoration(
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
                    const SizedBox(height: 24),
                    const Text(
                      'Режим заполнения:',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    RadioListTile<bool>(
                      title: const Text('Заменить все существующие смены'),
                      subtitle: const Text('Удалить все смены в периоде и заполнить заново'),
                      value: true,
                      groupValue: _replaceExisting,
                      onChanged: (value) {
                        setState(() {
                          _replaceExisting = value ?? false;
                        });
                      },
                    ),
                    RadioListTile<bool>(
                      title: const Text('Заполнить только пустые дни'),
                      subtitle: const Text('Оставить существующие смены без изменений'),
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
          child: const Text('Отмена'),
        ),
        ElevatedButton(
          onPressed: _isLoading ? null : _performAutoFill,
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF004D40),
            foregroundColor: Colors.white,
          ),
          child: const Text('Заполнить'),
        ),
      ],
    );
  }
}







