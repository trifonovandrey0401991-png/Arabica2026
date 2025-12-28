import 'package:flutter/material.dart';
import 'models/attendance_model.dart';
import 'services/attendance_service.dart';

class AttendanceReportsPage extends StatefulWidget {
  const AttendanceReportsPage({super.key});

  @override
  State<AttendanceReportsPage> createState() => _AttendanceReportsPageState();
}

class _AttendanceReportsPageState extends State<AttendanceReportsPage> {
  List<AttendanceRecord> _records = [];
  bool _isLoading = true;
  String? _selectedEmployee;
  String? _selectedShop;
  DateTime? _selectedDate;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final records = await AttendanceService.getAttendanceRecords(
        employeeName: _selectedEmployee,
        shopAddress: _selectedShop,
        date: _selectedDate,
      );
      setState(() {
        _records = records;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка загрузки: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Отчеты по приходам'),
        backgroundColor: const Color(0xFF004D40),
      ),
      body: Column(
        children: [
          // Фильтры
          Container(
            padding: const EdgeInsets.all(16),
            color: Colors.grey[100],
            child: Column(
              children: [
                // Фильтр по дате
                InkWell(
                  onTap: () async {
                    final date = await showDatePicker(
                      context: context,
                      initialDate: DateTime.now(),
                      firstDate: DateTime(2020),
                      lastDate: DateTime.now(),
                    );
                    if (date != null) {
                      setState(() {
                        _selectedDate = date;
                      });
                      _loadData();
                    }
                  },
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.calendar_today),
                        const SizedBox(width: 8),
                        Text(
                          _selectedDate != null
                              ? '${_selectedDate!.day}.${_selectedDate!.month}.${_selectedDate!.year}'
                              : 'Выберите дату',
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                ElevatedButton(
                  onPressed: () {
                    setState(() {
                      _selectedDate = null;
                      _selectedEmployee = null;
                      _selectedShop = null;
                    });
                    _loadData();
                  },
                  child: const Text('Сбросить фильтры'),
                ),
              ],
            ),
          ),
          // Список записей
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _records.isEmpty
                    ? const Center(child: Text('Нет записей'))
                    : ListView.builder(
                        itemCount: _records.length,
                        itemBuilder: (context, index) {
                          final record = _records[index];
                          return Card(
                            margin: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 8,
                            ),
                            child: ListTile(
                              leading: _buildStatusIcon(record),
                              title: Text(record.employeeName),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(record.shopAddress),
                                  Text(
                                    '${record.timestamp.day}.${record.timestamp.month}.${record.timestamp.year} '
                                    '${record.timestamp.hour.toString().padLeft(2, '0')}:${record.timestamp.minute.toString().padLeft(2, '0')}',
                                  ),
                                  if (record.shiftType != null)
                                    Text(
                                      _getShiftTypeName(record.shiftType!),
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.blue[700],
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  if (record.isOnTime == true)
                                    const Row(
                                      children: [
                                        Icon(Icons.check_circle, size: 16, color: Colors.green),
                                        SizedBox(width: 4),
                                        Text(
                                          'Вовремя',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: Colors.green,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      ],
                                    ),
                                  if (record.isOnTime == false && record.lateMinutes != null)
                                    Row(
                                      children: [
                                        const Icon(Icons.warning, size: 16, color: Colors.orange),
                                        const SizedBox(width: 4),
                                        Text(
                                          'Опоздал на ${record.lateMinutes} мин',
                                          style: const TextStyle(
                                            fontSize: 12,
                                            color: Colors.orange,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      ],
                                    ),
                                  if (record.isOnTime == null)
                                    const Row(
                                      children: [
                                        Icon(Icons.info, size: 16, color: Colors.grey),
                                        SizedBox(width: 4),
                                        Text(
                                          'Вне смены',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: Colors.grey,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      ],
                                    ),
                                  if (record.distance != null)
                                    Text(
                                      'Расстояние: ${record.distance!.toStringAsFixed(0)} м',
                                      style: const TextStyle(fontSize: 12),
                                    ),
                                ],
                              ),
                              trailing: IconButton(
                                icon: const Icon(Icons.location_on),
                                onPressed: () {
                                  // Показать координаты
                                  showDialog(
                                    context: context,
                                    builder: (context) => AlertDialog(
                                      title: const Text('Координаты'),
                                      content: Text(
                                        'Широта: ${record.latitude}\n'
                                        'Долгота: ${record.longitude}',
                                      ),
                                      actions: [
                                        TextButton(
                                          onPressed: () => Navigator.pop(context),
                                          child: const Text('OK'),
                                        ),
                                      ],
                                    ),
                                  );
                                },
                              ),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusIcon(AttendanceRecord record) {
    if (record.isOnTime == true) {
      return const Icon(Icons.check_circle, color: Colors.green, size: 32);
    } else if (record.isOnTime == false) {
      return const Icon(Icons.warning, color: Colors.orange, size: 32);
    } else {
      return const Icon(Icons.info, color: Colors.grey, size: 32);
    }
  }

  String _getShiftTypeName(String shiftType) {
    switch (shiftType) {
      case 'morning':
        return 'Утренняя смена';
      case 'day':
        return 'Дневная смена';
      case 'night':
        return 'Ночная смена';
      default:
        return shiftType;
    }
  }
}












