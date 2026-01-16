import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../suppliers/models/supplier_model.dart';
import '../../suppliers/services/supplier_service.dart';
import '../models/withdrawal_model.dart';
import '../models/withdrawal_expense_model.dart';
import '../widgets/withdrawal_confirmation_dialog.dart';
import '../services/withdrawal_service.dart';

/// Данные формы для одного расхода
class ExpenseFormData {
  String? supplierId;
  String? supplierName;
  TextEditingController amountController;
  TextEditingController commentController;
  bool isOtherExpense;

  ExpenseFormData({
    this.supplierId,
    this.supplierName,
    required this.amountController,
    required this.commentController,
    this.isOtherExpense = false,
  });

  double get amount {
    final text = amountController.text.trim();
    return double.tryParse(text) ?? 0;
  }

  String get comment => commentController.text.trim();

  WithdrawalExpense toExpense() {
    return WithdrawalExpense(
      supplierId: supplierId,
      supplierName: supplierName,
      amount: amount,
      comment: comment,
    );
  }

  void dispose() {
    amountController.dispose();
    commentController.dispose();
  }
}

/// Страница формы выемки
class WithdrawalFormPage extends StatefulWidget {
  final String shopAddress;
  final String employeeName;
  final String employeeId;
  final String currentUserName;

  const WithdrawalFormPage({
    super.key,
    required this.shopAddress,
    required this.employeeName,
    required this.employeeId,
    required this.currentUserName,
  });

  @override
  State<WithdrawalFormPage> createState() => _WithdrawalFormPageState();
}

class _WithdrawalFormPageState extends State<WithdrawalFormPage> {
  String _selectedType = 'ooo'; // 'ooo' или 'ip'
  List<Supplier> _allSuppliers = [];
  List<Supplier> _filteredSuppliers = [];
  List<ExpenseFormData> _expenses = [];
  bool _isLoadingSuppliers = true;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _loadSuppliers();
  }

  @override
  void dispose() {
    for (var expense in _expenses) {
      expense.dispose();
    }
    super.dispose();
  }

  Future<void> _loadSuppliers() async {
    try {
      final suppliers = await SupplierService.getSuppliers();
      if (mounted) {
        setState(() {
          _allSuppliers = suppliers;
          _filterSuppliersByType();
          _isLoadingSuppliers = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoadingSuppliers = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка загрузки поставщиков: $e')),
        );
      }
    }
  }

  void _filterSuppliersByType() {
    final targetType = _selectedType == 'ooo' ? 'ООО' : 'ИП';
    setState(() {
      _filteredSuppliers = _allSuppliers
          .where((s) => s.legalType == targetType)
          .toList();
    });
  }

  void _onTypeChanged(String? value) {
    if (value != null) {
      setState(() {
        _selectedType = value;
        _filterSuppliersByType();
        // Сбросить расходы при смене типа
        for (var expense in _expenses) {
          expense.dispose();
        }
        _expenses.clear();
      });
    }
  }

  void _addSupplierExpense() {
    setState(() {
      _expenses.add(ExpenseFormData(
        amountController: TextEditingController(),
        commentController: TextEditingController(),
        isOtherExpense: false,
      ));
    });
  }

  void _addOtherExpense() {
    setState(() {
      _expenses.add(ExpenseFormData(
        supplierName: 'Другой расход',
        amountController: TextEditingController(),
        commentController: TextEditingController(),
        isOtherExpense: true,
      ));
    });
  }

  void _removeExpense(int index) {
    setState(() {
      _expenses[index].dispose();
      _expenses.removeAt(index);
    });
  }

  double _calculateTotal() {
    return _expenses.fold(0.0, (sum, expense) => sum + expense.amount);
  }

  String? _validateExpenses() {
    if (_expenses.isEmpty) {
      return 'Добавьте хотя бы один расход';
    }

    for (int i = 0; i < _expenses.length; i++) {
      final expense = _expenses[i];

      if (expense.amount <= 0) {
        return 'Расход ${i + 1}: сумма должна быть больше нуля';
      }

      if (expense.isOtherExpense && expense.comment.isEmpty) {
        return 'Расход ${i + 1}: для "Другого расхода" комментарий обязателен';
      }

      if (!expense.isOtherExpense && expense.supplierId == null) {
        return 'Расход ${i + 1}: выберите поставщика';
      }
    }

    return null;
  }

  Future<void> _showConfirmationDialog() async {
    final error = _validateExpenses();
    if (error != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error), backgroundColor: Colors.red),
      );
      return;
    }

    final withdrawal = Withdrawal(
      shopAddress: widget.shopAddress,
      employeeName: widget.employeeName,
      employeeId: widget.employeeId,
      type: _selectedType,
      totalAmount: _calculateTotal(),
      expenses: _expenses.map((e) => e.toExpense()).toList(),
      adminName: widget.currentUserName,
    );

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => WithdrawalConfirmationDialog(withdrawal: withdrawal),
    );

    if (confirmed == true) {
      await _saveWithdrawal(withdrawal);
    }
  }

  Future<void> _saveWithdrawal(Withdrawal withdrawal) async {
    setState(() => _isSaving = true);

    try {
      await WithdrawalService.createWithdrawal(withdrawal);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Выемка успешно создана'),
            backgroundColor: Colors.green,
          ),
        );
        // Вернуться на главную страницу кассы
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка создания выемки: $e'),
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
        title: const Text('Форма выемки'),
        backgroundColor: const Color(0xFF004D40),
      ),
      body: _isLoadingSuppliers
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Readonly поля
                  _buildReadonlyField('Магазин', widget.shopAddress),
                  const SizedBox(height: 12),
                  _buildReadonlyField('Сотрудник', widget.employeeName),
                  const SizedBox(height: 24),

                  // Выбор типа
                  const Text(
                    'Тип',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: RadioListTile<String>(
                          title: const Text('ООО'),
                          value: 'ooo',
                          groupValue: _selectedType,
                          onChanged: _onTypeChanged,
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                      Expanded(
                        child: RadioListTile<String>(
                          title: const Text('ИП'),
                          value: 'ip',
                          groupValue: _selectedType,
                          onChanged: _onTypeChanged,
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),

                  // Список расходов
                  const Text(
                    'Расходы',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),

                  if (_expenses.isEmpty)
                    Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: Colors.grey[200],
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Text(
                        'Нажмите "Добавить расход" чтобы начать',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.grey),
                      ),
                    ),

                  ..._expenses.asMap().entries.map((entry) {
                    final index = entry.key;
                    final expense = entry.value;
                    return _buildExpenseCard(index, expense);
                  }).toList(),

                  const SizedBox(height: 16),

                  // Кнопки добавления
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: _addSupplierExpense,
                          icon: const Icon(Icons.add),
                          label: const Text('Добавить расход'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF004D40),
                            foregroundColor: Colors.white,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: _addOtherExpense,
                          icon: const Icon(Icons.more_horiz),
                          label: const Text('Другой расход'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.orange[700],
                            foregroundColor: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),

                  // Общая сумма
                  if (_expenses.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.blue[50],
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.blue[300]!, width: 2),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Итого:',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            '${_calculateTotal().toStringAsFixed(0)} руб',
                            style: const TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF004D40),
                            ),
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 24),

                  // Кнопка сохранения
                  ElevatedButton(
                    onPressed: _isSaving ? null : _showConfirmationDialog,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green[700],
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                    child: _isSaving
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Text(
                            'Сохранить',
                            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                          ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildReadonlyField(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 14, color: Colors.grey),
        ),
        const SizedBox(height: 4),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.grey[200],
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            value,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
          ),
        ),
      ],
    );
  }

  Widget _buildExpenseCard(int index, ExpenseFormData expense) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Расход ${index + 1}',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.delete, color: Colors.red),
                  onPressed: () => _removeExpense(index),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ),
            const Divider(),
            const SizedBox(height: 8),

            // Поставщик (dropdown или текст "Другой расход")
            if (expense.isOtherExpense)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.orange[50],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.orange, width: 2),
                ),
                child: const Text(
                  'Другой расход',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.orange,
                  ),
                ),
              )
            else
              DropdownButtonFormField<String>(
                value: expense.supplierId,
                decoration: const InputDecoration(
                  labelText: 'Поставщик',
                  border: OutlineInputBorder(),
                ),
                items: _filteredSuppliers.map((supplier) {
                  return DropdownMenuItem(
                    value: supplier.id,
                    child: Text(supplier.name),
                  );
                }).toList(),
                onChanged: (value) {
                  setState(() {
                    expense.supplierId = value;
                    expense.supplierName = _filteredSuppliers
                        .firstWhere((s) => s.id == value)
                        .name;
                  });
                },
              ),
            const SizedBox(height: 12),

            // Сумма
            TextFormField(
              controller: expense.amountController,
              decoration: const InputDecoration(
                labelText: 'Сумма (руб)',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.attach_money),
              ),
              keyboardType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}')),
              ],
            ),
            const SizedBox(height: 12),

            // Комментарий
            TextFormField(
              controller: expense.commentController,
              decoration: InputDecoration(
                labelText: expense.isOtherExpense
                    ? 'Комментарий (обязательно)'
                    : 'Комментарий',
                border: const OutlineInputBorder(),
                prefixIcon: const Icon(Icons.comment),
              ),
              maxLines: 2,
            ),
          ],
        ),
      ),
    );
  }
}
