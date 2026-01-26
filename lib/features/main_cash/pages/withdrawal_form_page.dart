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
        elevation: 0,
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              const Color(0xFF004D40).withOpacity(0.05),
              Colors.white,
            ],
          ),
        ),
        child: _isLoadingSuppliers
            ? const Center(child: CircularProgressIndicator())
            : SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Карточка с информацией
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.08),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Column(
                        children: [
                          _buildInfoRow(
                            Icons.store,
                            'Магазин',
                            widget.shopAddress,
                            const Color(0xFF004D40),
                          ),
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 12),
                            child: Divider(height: 1),
                          ),
                          _buildInfoRow(
                            Icons.person,
                            'Сотрудник',
                            widget.employeeName,
                            const Color(0xFF004D40),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Выбор типа (современный дизайн)
                    Text(
                      'Выберите тип',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: Colors.grey[800],
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: _buildTypeCard('ООО', 'ooo', Colors.blue),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _buildTypeCard('ИП', 'ip', Colors.orange),
                        ),
                      ],
                    ),
                    const SizedBox(height: 28),

                    // Заголовок расходов
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Расходы',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: Colors.grey[800],
                          ),
                        ),
                        if (_expenses.isNotEmpty)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFF004D40),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              '${_expenses.length}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    // Список расходов или placeholder
                    if (_expenses.isEmpty)
                      Container(
                        padding: const EdgeInsets.all(40),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: Colors.grey[300]!,
                            width: 2,
                            style: BorderStyle.solid,
                          ),
                        ),
                        child: Column(
                          children: [
                            Icon(
                              Icons.inbox_outlined,
                              size: 64,
                              color: Colors.grey[400],
                            ),
                            const SizedBox(height: 12),
                            Text(
                              'Нет расходов',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: Colors.grey[600],
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Нажмите кнопку ниже чтобы добавить',
                              style: TextStyle(
                                fontSize: 13,
                                color: Colors.grey[500],
                              ),
                            ),
                          ],
                        ),
                      )
                    else
                      ..._expenses.asMap().entries.map((entry) {
                        final index = entry.key;
                        final expense = entry.value;
                        return _buildExpenseCard(index, expense);
                      }).toList(),

                    const SizedBox(height: 20),

                    // Кнопки добавления (улучшенный дизайн)
                    Row(
                      children: [
                        Expanded(
                          child: _buildActionButton(
                            icon: Icons.add_circle_outline,
                            label: 'Добавить расход',
                            color: const Color(0xFF004D40),
                            onPressed: _addSupplierExpense,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _buildActionButton(
                            icon: Icons.edit_note,
                            label: 'Другой расход',
                            color: Colors.orange[700]!,
                            onPressed: _addOtherExpense,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 28),

                    // Общая сумма (улучшенный дизайн)
                    if (_expenses.isNotEmpty) ...[
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              const Color(0xFF004D40),
                              const Color(0xFF00695C),
                            ],
                          ),
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFF004D40).withOpacity(0.3),
                              blurRadius: 12,
                              offset: const Offset(0, 6),
                            ),
                          ],
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Итоговая сумма',
                                  style: TextStyle(
                                    color: Colors.white70,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '${_calculateTotal().toStringAsFixed(0)} руб',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 32,
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: -0.5,
                                  ),
                                ),
                              ],
                            ),
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.2),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Icon(
                                Icons.account_balance_wallet,
                                color: Colors.white,
                                size: 32,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 28),
                    ],

                    // Кнопка сохранения (финальная)
                    Container(
                      height: 56,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.green.withOpacity(0.3),
                            blurRadius: 12,
                            offset: const Offset(0, 6),
                          ),
                        ],
                      ),
                      child: ElevatedButton(
                        onPressed: _isSaving ? null : _showConfirmationDialog,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green[600],
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                          elevation: 0,
                        ),
                        child: _isSaving
                            ? const SizedBox(
                                height: 24,
                                width: 24,
                                child: CircularProgressIndicator(
                                  strokeWidth: 3,
                                  color: Colors.white,
                                ),
                              )
                            : Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: const [
                                  Icon(Icons.check_circle_outline, size: 24),
                                  SizedBox(width: 8),
                                  Text(
                                    'Сохранить выемку',
                                    style: TextStyle(
                                      fontSize: 17,
                                      fontWeight: FontWeight.bold,
                                      letterSpacing: 0.3,
                                    ),
                                  ),
                                ],
                              ),
                      ),
                    ),
                    const SizedBox(height: 20),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value, Color color) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: color, size: 20),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[600],
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: Colors.black87,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTypeCard(String label, String value, Color color) {
    final isSelected = _selectedType == value;
    return InkWell(
      onTap: () => _onTypeChanged(value),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: isSelected ? color : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? color : Colors.grey[300]!,
            width: isSelected ? 2 : 1,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: color.withOpacity(0.3),
                    blurRadius: 8,
                    offset: const Offset(0, 4),
                  ),
                ]
              : [],
        ),
        child: Column(
          children: [
            Icon(
              isSelected ? Icons.check_circle : Icons.circle_outlined,
              color: isSelected ? Colors.white : Colors.grey[400],
              size: 28,
            ),
            const SizedBox(height: 8),
            Text(
              label,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: isSelected ? Colors.white : Colors.grey[700],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onPressed,
  }) {
    return Container(
      height: 50,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.2),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 12),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 20),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                label,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildExpenseCard(int index, ExpenseFormData expense) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Заголовок с кнопкой удаления
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF004D40).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    'Расход ${index + 1}',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF004D40),
                    ),
                  ),
                ),
                const Spacer(),
                Material(
                  color: Colors.red[50],
                  borderRadius: BorderRadius.circular(8),
                  child: InkWell(
                    onTap: () => _removeExpense(index),
                    borderRadius: BorderRadius.circular(8),
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: Icon(
                        Icons.delete_outline,
                        color: Colors.red[700],
                        size: 20,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Поставщик (dropdown или бейдж "Другой расход")
            if (expense.isOtherExpense)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Colors.orange[100]!,
                      Colors.orange[50]!,
                    ],
                  ),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: Colors.orange[300]!,
                    width: 1.5,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.edit_note,
                      color: Colors.orange[800],
                      size: 22,
                    ),
                    const SizedBox(width: 10),
                    Text(
                      'Другой расход',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: Colors.orange[900],
                      ),
                    ),
                  ],
                ),
              )
            else
              Container(
                decoration: BoxDecoration(
                  color: Colors.grey[50],
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey[300]!),
                ),
                child: DropdownButtonFormField<String>(
                  value: expense.supplierId,
                  decoration: InputDecoration(
                    labelText: 'Выберите поставщика',
                    prefixIcon: Icon(
                      Icons.business,
                      color: const Color(0xFF004D40),
                    ),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 14,
                    ),
                  ),
                  dropdownColor: Colors.white,
                  items: _filteredSuppliers.map((supplier) {
                    return DropdownMenuItem(
                      value: supplier.id,
                      child: Text(
                        supplier.name,
                        style: const TextStyle(fontSize: 14),
                      ),
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
              ),
            const SizedBox(height: 14),

            // Сумма
            Container(
              decoration: BoxDecoration(
                color: Colors.grey[50],
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey[300]!),
              ),
              child: TextFormField(
                controller: expense.amountController,
                decoration: InputDecoration(
                  labelText: 'Сумма (руб)',
                  prefixIcon: Icon(
                    Icons.account_balance_wallet,
                    color: Colors.green[700],
                  ),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                ),
                keyboardType: TextInputType.number,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}')),
                ],
              ),
            ),
            const SizedBox(height: 14),

            // Комментарий
            Container(
              decoration: BoxDecoration(
                color: Colors.grey[50],
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey[300]!),
              ),
              child: TextFormField(
                controller: expense.commentController,
                decoration: InputDecoration(
                  labelText: expense.isOtherExpense
                      ? 'Комментарий (обязательно)'
                      : 'Комментарий (опционально)',
                  prefixIcon: Icon(
                    Icons.comment_outlined,
                    color: Colors.blue[700],
                  ),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                ),
                maxLines: 2,
                style: const TextStyle(fontSize: 14),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
