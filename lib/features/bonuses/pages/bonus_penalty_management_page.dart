import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../employees/pages/employees_page.dart';
import '../../employees/services/employee_service.dart';
import '../services/bonus_penalty_service.dart';

class BonusPenaltyManagementPage extends StatefulWidget {
  const BonusPenaltyManagementPage({super.key});

  @override
  State<BonusPenaltyManagementPage> createState() => _BonusPenaltyManagementPageState();
}

class _BonusPenaltyManagementPageState extends State<BonusPenaltyManagementPage> {
  String? _selectedType; // 'bonus' или 'penalty'
  List<Employee> _employees = [];
  bool _isLoading = true;
  String _searchQuery = '';
  String _adminName = '';

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final prefs = await SharedPreferences.getInstance();
    _adminName = prefs.getString('employeeName') ?? prefs.getString('name') ?? 'Администратор';

    final employees = await EmployeeService.getEmployees();
    setState(() {
      _employees = employees;
      _isLoading = false;
    });
  }

  List<Employee> get _filteredEmployees {
    if (_searchQuery.isEmpty) return _employees;
    final query = _searchQuery.toLowerCase();
    return _employees.where((e) =>
      e.name.toLowerCase().contains(query)
    ).toList();
  }

  void _showTypeSelectionDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Выберите действие'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildTypeOption(
              icon: Icons.add_circle_outline,
              title: 'Премия',
              subtitle: 'Начислить сотруднику',
              color: Colors.green,
              type: 'bonus',
            ),
            const SizedBox(height: 12),
            _buildTypeOption(
              icon: Icons.remove_circle_outline,
              title: 'Штраф',
              subtitle: 'Списать у сотрудника',
              color: Colors.red,
              type: 'penalty',
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Отмена'),
          ),
        ],
      ),
    );
  }

  Widget _buildTypeOption({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required String type,
  }) {
    return InkWell(
      onTap: () {
        Navigator.pop(context);
        setState(() => _selectedType = type);
      },
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          border: Border.all(color: color.withOpacity(0.3)),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(icon, color: color, size: 32),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: color,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey[600],
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: color),
          ],
        ),
      ),
    );
  }

  void _selectEmployee(Employee employee) {
    _showAmountDialog(employee);
  }

  void _showAmountDialog(Employee employee) {
    final amountController = TextEditingController();
    final commentController = TextEditingController();
    final formKey = GlobalKey<FormState>();

    final isBonus = _selectedType == 'bonus';
    final typeTitle = isBonus ? 'Премия' : 'Штраф';
    final typeColor = isBonus ? Colors.green : Colors.red;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('$typeTitle для ${employee.name}'),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: amountController,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: 'Сумма',
                  prefixIcon: Icon(
                    isBonus ? Icons.add : Icons.remove,
                    color: typeColor,
                  ),
                  suffixText: 'руб',
                  border: const OutlineInputBorder(),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Введите сумму';
                  }
                  final amount = double.tryParse(value);
                  if (amount == null || amount <= 0) {
                    return 'Введите корректную сумму';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: commentController,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Комментарий',
                  prefixIcon: Icon(Icons.comment),
                  border: OutlineInputBorder(),
                  hintText: 'Причина премии/штрафа',
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Введите комментарий';
                  }
                  return null;
                },
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Отмена'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: typeColor,
              foregroundColor: Colors.white,
            ),
            onPressed: () async {
              if (formKey.currentState!.validate()) {
                Navigator.pop(context);
                await _createRecord(
                  employee,
                  double.parse(amountController.text),
                  commentController.text.trim(),
                );
              }
            },
            child: const Text('Отправить'),
          ),
        ],
      ),
    );
  }

  Future<void> _createRecord(Employee employee, double amount, String comment) async {
    setState(() => _isLoading = true);

    // Используем телефон как ID для совместимости с "Моя эффективность"
    final employeeId = employee.phone?.isNotEmpty == true ? employee.phone! : employee.id;

    final result = await BonusPenaltyService.create(
      employeeId: employeeId,
      employeeName: employee.name,
      type: _selectedType!,
      amount: amount,
      comment: comment,
      adminName: _adminName,
    );

    if (!mounted) return;
    setState(() => _isLoading = false);

    if (result != null) {
      final typeText = _selectedType == 'bonus' ? 'Премия' : 'Штраф';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$typeText ${amount.toStringAsFixed(0)} руб для ${employee.name} создан'),
          backgroundColor: _selectedType == 'bonus' ? Colors.green : Colors.red,
        ),
      );
      setState(() => _selectedType = null);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Ошибка при создании записи'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_selectedType == null
            ? 'Премия/Штрафы'
            : (_selectedType == 'bonus' ? 'Премия' : 'Штраф')),
        backgroundColor: _selectedType == 'bonus'
            ? Colors.green
            : (_selectedType == 'penalty' ? Colors.red : null),
        foregroundColor: _selectedType != null ? Colors.white : null,
        actions: [
          if (_selectedType != null)
            IconButton(
              icon: const Icon(Icons.close),
              onPressed: () => setState(() => _selectedType = null),
              tooltip: 'Сбросить выбор',
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _selectedType == null
              ? _buildTypeSelection()
              : _buildEmployeeList(),
    );
  }

  Widget _buildTypeSelection() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.monetization_on_outlined,
              size: 80,
              color: Colors.grey,
            ),
            const SizedBox(height: 24),
            const Text(
              'Выберите действие',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Начислите премию или назначьте штраф сотруднику',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey[600],
              ),
            ),
            const SizedBox(height: 48),
            _buildLargeTypeButton(
              icon: Icons.add_circle,
              title: 'Премия',
              subtitle: 'Начислить сотруднику',
              color: Colors.green,
              type: 'bonus',
            ),
            const SizedBox(height: 16),
            _buildLargeTypeButton(
              icon: Icons.remove_circle,
              title: 'Штраф',
              subtitle: 'Списать у сотрудника',
              color: Colors.red,
              type: 'penalty',
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLargeTypeButton({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required String type,
  }) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: color.withOpacity(0.1),
          foregroundColor: color,
          padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 24),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: color.withOpacity(0.5)),
          ),
        ),
        onPressed: () => setState(() => _selectedType = type),
        child: Row(
          children: [
            Icon(icon, size: 40),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 14,
                      color: color.withOpacity(0.8),
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, size: 28),
          ],
        ),
      ),
    );
  }

  Widget _buildEmployeeList() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: TextField(
            onChanged: (value) => setState(() => _searchQuery = value),
            decoration: InputDecoration(
              hintText: 'Поиск сотрудника...',
              prefixIcon: const Icon(Icons.search),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              filled: true,
              fillColor: Colors.grey[100],
            ),
          ),
        ),
        Expanded(
          child: _filteredEmployees.isEmpty
              ? Center(
                  child: Text(
                    _searchQuery.isEmpty
                        ? 'Нет сотрудников'
                        : 'Ничего не найдено',
                    style: TextStyle(
                      fontSize: 16,
                      color: Colors.grey[600],
                    ),
                  ),
                )
              : ListView.builder(
                  itemCount: _filteredEmployees.length,
                  itemBuilder: (context, index) {
                    final employee = _filteredEmployees[index];
                    return _buildEmployeeCard(employee);
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildEmployeeCard(Employee employee) {
    final isBonus = _selectedType == 'bonus';
    final typeColor = isBonus ? Colors.green : Colors.red;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: typeColor.withOpacity(0.1),
          child: Text(
            employee.name.isNotEmpty ? employee.name[0].toUpperCase() : '?',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: typeColor,
            ),
          ),
        ),
        title: Text(
          employee.name,
          style: const TextStyle(fontWeight: FontWeight.w500),
        ),
        subtitle: employee.phone != null && employee.phone!.isNotEmpty
            ? Text(employee.phone!)
            : null,
        trailing: Icon(
          isBonus ? Icons.add_circle_outline : Icons.remove_circle_outline,
          color: typeColor,
        ),
        onTap: () => _selectEmployee(employee),
      ),
    );
  }
}
