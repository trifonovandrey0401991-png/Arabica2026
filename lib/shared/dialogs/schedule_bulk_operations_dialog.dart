import 'package:flutter/material.dart';
import '../../features/work_schedule/models/work_schedule_model.dart';
import '../../features/work_schedule/services/work_schedule_service.dart';
import '../../features/employees/pages/employees_page.dart';
import '../../features/shops/models/shop_model.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

class ScheduleBulkOperationsDialog extends StatefulWidget {
  final WorkSchedule schedule;
  final List<Employee> employees;
  final List<Shop> shops;
  final DateTime selectedMonth;
  final VoidCallback onOperationComplete;

  const ScheduleBulkOperationsDialog({
    super.key,
    required this.schedule,
    required this.employees,
    required this.shops,
    required this.selectedMonth,
    required this.onOperationComplete,
  });

  @override
  State<ScheduleBulkOperationsDialog> createState() => _ScheduleBulkOperationsDialogState();
}

class _ScheduleBulkOperationsDialogState extends State<ScheduleBulkOperationsDialog>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  int _selectedTab = 0;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(() {
      if (mounted) setState(() {
        _selectedTab = _tabController.index;
      });
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: Container(
        width: MediaQuery.of(context).size.width * 0.9,
        height: MediaQuery.of(context).size.height * 0.7,
        padding: EdgeInsets.all(16.w),
        child: Column(
          children: [
            Text(
              'Массовые операции',
              style: TextStyle(fontSize: 20.sp, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 16),
            TabBar(
              controller: _tabController,
              tabs: [
                Tab(text: 'Копировать неделю'),
                Tab(text: 'Шаблоны'),
                Tab(text: 'Автозаполнение'),
              ],
            ),
            Expanded(
              child: IndexedStack(
                index: _selectedTab,
                children: [
                  _buildCopyWeekTab(),
                  _buildTemplatesTab(),
                  _buildAutoFillTab(),
                ],
              ),
            ),
            SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text('Закрыть'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCopyWeekTab() {
    DateTime? sourceWeekStart;
    DateTime? targetWeekStart;
    final selectedEmployees = <String>{};

    return StatefulBuilder(
      builder: (context, setState) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Копировать график недели', style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.bold)),
            SizedBox(height: 16),
            ListTile(
              title: Text('Неделя источник:'),
              subtitle: Text(sourceWeekStart != null
                  ? '${sourceWeekStart!.day}.${sourceWeekStart!.month}.${sourceWeekStart!.year}'
                  : 'Не выбрана'),
              trailing: Icon(Icons.calendar_today),
              onTap: () async {
                final date = await showDatePicker(
                  context: context,
                  initialDate: widget.selectedMonth,
                  firstDate: DateTime(2020),
                  lastDate: DateTime(2030),
                );
                if (date != null) {
                  if (mounted) setState(() {
                    sourceWeekStart = _getWeekStart(date);
                  });
                }
              },
            ),
            ListTile(
              title: Text('Неделя назначения:'),
              subtitle: Text(targetWeekStart != null
                  ? '${targetWeekStart!.day}.${targetWeekStart!.month}.${targetWeekStart!.year}'
                  : 'Не выбрана'),
              trailing: Icon(Icons.calendar_today),
              onTap: () async {
                final date = await showDatePicker(
                  context: context,
                  initialDate: widget.selectedMonth,
                  firstDate: DateTime(2020),
                  lastDate: DateTime(2030),
                );
                if (date != null) {
                  if (mounted) setState(() {
                    targetWeekStart = _getWeekStart(date);
                  });
                }
              },
            ),
            SizedBox(height: 16),
            Text('Выберите сотрудников:', style: TextStyle(fontWeight: FontWeight.w600)),
            SizedBox(height: 8),
            Expanded(
              child: ListView.builder(
                itemCount: widget.employees.length,
                itemBuilder: (context, index) {
                  final employee = widget.employees[index];
                  final isSelected = selectedEmployees.contains(employee.id);
                  return CheckboxListTile(
                    title: Text(employee.name),
                    value: isSelected,
                    onChanged: (value) {
                      if (mounted) setState(() {
                        if (value == true) {
                          selectedEmployees.add(employee.id);
                        } else {
                          selectedEmployees.remove(employee.id);
                        }
                      });
                    },
                  );
                },
              ),
            ),
            ElevatedButton(
              onPressed: sourceWeekStart != null && targetWeekStart != null && selectedEmployees.isNotEmpty
                  ? () async {
                      final success = await WorkScheduleService.copyWeek(
                        sourceWeekStart: sourceWeekStart!,
                        targetWeekStart: targetWeekStart!,
                        employeeIds: selectedEmployees.toList(),
                      );
                      if (success && context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Неделя скопирована')),
                        );
                        widget.onOperationComplete();
                        Navigator.of(context).pop();
                      }
                    }
                  : null,
              child: Text('Копировать'),
            ),
          ],
        );
      },
    );
  }

  Widget _buildTemplatesTab() {
    return FutureBuilder<List<ScheduleTemplate>>(
      future: WorkScheduleService.getTemplates(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError) {
          return Center(child: Text('Ошибка: ${snapshot.error}'));
        }

        final templates = snapshot.data ?? [];

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Шаблоны', style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.bold)),
                ElevatedButton.icon(
                  onPressed: () => _createTemplate(context),
                  icon: Icon(Icons.add),
                  label: Text('Создать'),
                ),
              ],
            ),
            SizedBox(height: 16),
            Expanded(
              child: templates.isEmpty
                  ? Center(child: Text('Нет сохраненных шаблонов'))
                  : ListView.builder(
                      itemCount: templates.length,
                      itemBuilder: (context, index) {
                        final template = templates[index];
                        return ListTile(
                          title: Text(template.name),
                          subtitle: Text('${template.entries.length} смен'),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: Icon(Icons.play_arrow),
                                onPressed: () => _applyTemplate(template),
                              ),
                              IconButton(
                                icon: Icon(Icons.delete),
                                onPressed: () => _deleteTemplate(template),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildAutoFillTab() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Автозаполнение выходных', style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.bold)),
        SizedBox(height: 16),
        Text('Эта функция автоматически отметит выходные для сотрудников, у которых нет смен в определенные дни.'),
        SizedBox(height: 24),
        ElevatedButton(
          onPressed: () async {
            // Реализация автозаполнения выходных
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Функция в разработке')),
            );
          },
          child: Text('Автозаполнить выходные'),
        ),
      ],
    );
  }

  DateTime _getWeekStart(DateTime date) {
    final weekday = date.weekday;
    return date.subtract(Duration(days: weekday - 1));
  }

  Future<void> _createTemplate(BuildContext context) async {
    final nameController = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Создать шаблон'),
        content: TextField(
          controller: nameController,
          decoration: InputDecoration(labelText: 'Название шаблона'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text('Отмена'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(nameController.text),
            child: Text('Создать'),
          ),
        ],
      ),
    ).whenComplete(() => nameController.dispose());

    if (result != null && result.isNotEmpty) {
      // Создаем шаблон из текущей недели
      final weekStart = _getWeekStart(widget.selectedMonth);
      final weekEntries = widget.schedule.entries.where((entry) {
        final entryDate = DateTime(entry.date.year, entry.date.month, entry.date.day);
        final weekEnd = weekStart.add(Duration(days: 6));
        return entryDate.isAfter(weekStart.subtract(Duration(days: 1))) &&
               entryDate.isBefore(weekEnd.add(Duration(days: 1)));
      }).toList();

      final template = ScheduleTemplate(
        id: '',
        name: result,
        entries: weekEntries,
      );

      final success = await WorkScheduleService.saveTemplate(template);
      if (success && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Шаблон сохранен')),
        );
        if (mounted) setState(() {});
      }
    }
  }

  Future<void> _applyTemplate(ScheduleTemplate template) async {
    final date = await showDatePicker(
      context: context,
      initialDate: widget.selectedMonth,
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
    );

    if (date != null) {
      final weekStart = _getWeekStart(date);
      final success = await WorkScheduleService.applyTemplate(template, weekStart);
      if (!mounted) return;
      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Шаблон применен')),
        );
        widget.onOperationComplete();
        Navigator.of(context).pop();
      }
    }
  }

  Future<void> _deleteTemplate(ScheduleTemplate template) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Удалить шаблон?'),
        content: Text('Шаблон "${template.name}" будет удалён.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text('Отмена'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: Text('Удалить'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      final success = await WorkScheduleService.deleteTemplate(template.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(success ? 'Шаблон удалён' : 'Ошибка удаления шаблона'),
            backgroundColor: success ? Colors.green : Colors.red,
          ),
        );
        if (success) {
          if (mounted) setState(() {}); // Перезагрузит FutureBuilder
        }
      }
    }
  }
}

