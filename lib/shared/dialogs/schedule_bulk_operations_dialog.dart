import 'package:flutter/material.dart';
import '../../features/work_schedule/models/work_schedule_model.dart';
import '../../features/work_schedule/services/work_schedule_service.dart';
import '../../features/employees/pages/employees_page.dart';
import '../../features/shops/models/shop_model.dart';

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
      setState(() {
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
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            const Text(
              'Массовые операции',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            TabBar(
              controller: _tabController,
              tabs: const [
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
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Закрыть'),
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
            const Text('Копировать график недели', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            ListTile(
              title: const Text('Неделя источник:'),
              subtitle: Text(sourceWeekStart != null
                  ? '${sourceWeekStart!.day}.${sourceWeekStart!.month}.${sourceWeekStart!.year}'
                  : 'Не выбрана'),
              trailing: const Icon(Icons.calendar_today),
              onTap: () async {
                final date = await showDatePicker(
                  context: context,
                  initialDate: widget.selectedMonth,
                  firstDate: DateTime(2020),
                  lastDate: DateTime(2030),
                );
                if (date != null) {
                  setState(() {
                    sourceWeekStart = _getWeekStart(date);
                  });
                }
              },
            ),
            ListTile(
              title: const Text('Неделя назначения:'),
              subtitle: Text(targetWeekStart != null
                  ? '${targetWeekStart!.day}.${targetWeekStart!.month}.${targetWeekStart!.year}'
                  : 'Не выбрана'),
              trailing: const Icon(Icons.calendar_today),
              onTap: () async {
                final date = await showDatePicker(
                  context: context,
                  initialDate: widget.selectedMonth,
                  firstDate: DateTime(2020),
                  lastDate: DateTime(2030),
                );
                if (date != null) {
                  setState(() {
                    targetWeekStart = _getWeekStart(date);
                  });
                }
              },
            ),
            const SizedBox(height: 16),
            const Text('Выберите сотрудников:', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
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
                      setState(() {
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
                          const SnackBar(content: Text('Неделя скопирована')),
                        );
                        widget.onOperationComplete();
                        Navigator.of(context).pop();
                      }
                    }
                  : null,
              child: const Text('Копировать'),
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
          return const Center(child: CircularProgressIndicator());
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
                const Text('Шаблоны', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                ElevatedButton.icon(
                  onPressed: () => _createTemplate(context),
                  icon: const Icon(Icons.add),
                  label: const Text('Создать'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Expanded(
              child: templates.isEmpty
                  ? const Center(child: Text('Нет сохраненных шаблонов'))
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
                                icon: const Icon(Icons.play_arrow),
                                onPressed: () => _applyTemplate(template),
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete),
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
        const Text('Автозаполнение выходных', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        const SizedBox(height: 16),
        const Text('Эта функция автоматически отметит выходные для сотрудников, у которых нет смен в определенные дни.'),
        const SizedBox(height: 24),
        ElevatedButton(
          onPressed: () async {
            // Реализация автозаполнения выходных
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Функция в разработке')),
            );
          },
          child: const Text('Автозаполнить выходные'),
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
        title: const Text('Создать шаблон'),
        content: TextField(
          controller: nameController,
          decoration: const InputDecoration(labelText: 'Название шаблона'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Отмена'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(nameController.text),
            child: const Text('Создать'),
          ),
        ],
      ),
    );

    if (result != null && result.isNotEmpty) {
      // Создаем шаблон из текущей недели
      final weekStart = _getWeekStart(widget.selectedMonth);
      final weekEntries = widget.schedule.entries.where((entry) {
        final entryDate = DateTime(entry.date.year, entry.date.month, entry.date.day);
        final weekEnd = weekStart.add(const Duration(days: 6));
        return entryDate.isAfter(weekStart.subtract(const Duration(days: 1))) &&
               entryDate.isBefore(weekEnd.add(const Duration(days: 1)));
      }).toList();

      final template = ScheduleTemplate(
        id: '',
        name: result,
        entries: weekEntries,
      );

      final success = await WorkScheduleService.saveTemplate(template);
      if (success && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Шаблон сохранен')),
        );
        setState(() {});
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
          const SnackBar(content: Text('Шаблон применен')),
        );
        widget.onOperationComplete();
        Navigator.of(context).pop();
      }
    }
  }

  Future<void> _deleteTemplate(ScheduleTemplate template) async {
    // TODO: Реализовать удаление шаблона
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Удаление шаблонов в разработке')),
    );
  }
}

