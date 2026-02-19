import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/theme/app_colors.dart';
import '../../suppliers/models/supplier_model.dart';
import '../../suppliers/services/supplier_service.dart';
import '../models/withdrawal_model.dart';
import '../models/withdrawal_expense_model.dart';
import '../widgets/withdrawal_confirmation_dialog.dart';
import '../services/withdrawal_service.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

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
  final List<ExpenseFormData> _expenses = [];
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
    if (mounted) setState(() {
      _filteredSuppliers = _allSuppliers
          .where((s) => s.legalType == targetType)
          .toList();
    });
  }

  void _onTypeChanged(String? value) {
    if (value != null) {
      if (mounted) setState(() {
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
    if (mounted) setState(() {
      _expenses.add(ExpenseFormData(
        amountController: TextEditingController(),
        commentController: TextEditingController(),
        isOtherExpense: false,
      ));
    });
  }

  void _addOtherExpense() {
    if (mounted) setState(() {
      _expenses.add(ExpenseFormData(
        supplierName: 'Другой расход',
        amountController: TextEditingController(),
        commentController: TextEditingController(),
        isOtherExpense: true,
      ));
    });
  }

  void _removeExpense(int index) {
    if (mounted) setState(() {
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
    if (mounted) setState(() => _isSaving = true);

    try {
      await WithdrawalService.createWithdrawal(withdrawal);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Выемка успешно создана'),
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
      backgroundColor: AppColors.night,
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [AppColors.emerald, AppColors.emeraldDark, AppColors.night],
            stops: [0.0, 0.3, 1.0],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              // Custom AppBar
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 12.h),
                child: Row(
                  children: [
                    GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(12.r),
                          border: Border.all(
                            color: Colors.white.withOpacity(0.1),
                          ),
                        ),
                        child: Icon(
                          Icons.arrow_back,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    SizedBox(width: 16),
                    Text(
                      'Форма выемки',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 20.sp,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
              // Content
              Expanded(
                child: _isLoadingSuppliers
                    ? Center(
                        child: CircularProgressIndicator(color: AppColors.gold))
                    : SingleChildScrollView(
                        padding: EdgeInsets.all(20.w),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            // Карточка с информацией
                            Container(
                              padding: EdgeInsets.all(20.w),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.06),
                                borderRadius: BorderRadius.circular(14.r),
                                border: Border.all(
                                  color: Colors.white.withOpacity(0.1),
                                ),
                              ),
                              child: Column(
                                children: [
                                  _buildInfoRow(
                                    Icons.store,
                                    'Магазин',
                                    widget.shopAddress,
                                  ),
                                  Padding(
                                    padding:
                                        EdgeInsets.symmetric(vertical: 12.h),
                                    child: Divider(
                                      height: 1,
                                      color: Colors.white.withOpacity(0.1),
                                    ),
                                  ),
                                  _buildInfoRow(
                                    Icons.person,
                                    'Сотрудник',
                                    widget.employeeName,
                                  ),
                                ],
                              ),
                            ),
                            SizedBox(height: 24),

                            // Выбор типа (современный дизайн)
                            Text(
                              'Выберите тип',
                              style: TextStyle(
                                fontSize: 18.sp,
                                fontWeight: FontWeight.w700,
                                color: Colors.white.withOpacity(0.9),
                              ),
                            ),
                            SizedBox(height: 12),
                            Row(
                              children: [
                                Expanded(
                                  child: _buildTypeCard(
                                      'ООО', 'ooo', Colors.blue),
                                ),
                                SizedBox(width: 12),
                                Expanded(
                                  child: _buildTypeCard(
                                      'ИП', 'ip', Colors.orange),
                                ),
                              ],
                            ),
                            SizedBox(height: 28),

                            // Заголовок расходов
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  'Расходы',
                                  style: TextStyle(
                                    fontSize: 18.sp,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.white.withOpacity(0.9),
                                  ),
                                ),
                                if (_expenses.isNotEmpty)
                                  Container(
                                    padding: EdgeInsets.symmetric(
                                      horizontal: 12.w,
                                      vertical: 4.h,
                                    ),
                                    decoration: BoxDecoration(
                                      color: AppColors.emerald.withOpacity(0.3),
                                      borderRadius: BorderRadius.circular(12.r),
                                    ),
                                    child: Text(
                                      '${_expenses.length}',
                                      style: TextStyle(
                                        color: AppColors.gold,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 14.sp,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                            SizedBox(height: 12),

                            // Список расходов или placeholder
                            if (_expenses.isEmpty)
                              Container(
                                padding: EdgeInsets.all(40.w),
                                decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(0.06),
                                  borderRadius: BorderRadius.circular(14.r),
                                  border: Border.all(
                                    color: Colors.white.withOpacity(0.1),
                                    width: 2,
                                    style: BorderStyle.solid,
                                  ),
                                ),
                                child: Column(
                                  children: [
                                    Icon(
                                      Icons.inbox_outlined,
                                      size: 64,
                                      color: Colors.white.withOpacity(0.3),
                                    ),
                                    SizedBox(height: 12),
                                    Text(
                                      'Нет расходов',
                                      style: TextStyle(
                                        fontSize: 16.sp,
                                        fontWeight: FontWeight.w600,
                                        color: Colors.white.withOpacity(0.5),
                                      ),
                                    ),
                                    SizedBox(height: 4),
                                    Text(
                                      'Нажмите кнопку ниже чтобы добавить',
                                      style: TextStyle(
                                        fontSize: 13.sp,
                                        color: Colors.white.withOpacity(0.3),
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
                              }),

                            SizedBox(height: 20),

                            // Кнопки добавления
                            Row(
                              children: [
                                Expanded(
                                  child: _buildActionButton(
                                    icon: Icons.add_circle_outline,
                                    label: 'Добавить расход',
                                    color: AppColors.emerald,
                                    onPressed: _addSupplierExpense,
                                  ),
                                ),
                                SizedBox(width: 12),
                                Expanded(
                                  child: _buildActionButton(
                                    icon: Icons.edit_note,
                                    label: 'Другой расход',
                                    color: Colors.orange[700]!.withOpacity(0.8),
                                    onPressed: _addOtherExpense,
                                  ),
                                ),
                              ],
                            ),
                            SizedBox(height: 28),

                            // Общая сумма
                            if (_expenses.isNotEmpty) ...[
                              Container(
                                padding: EdgeInsets.all(20.w),
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    colors: [AppColors.emeraldDark, AppColors.emerald],
                                  ),
                                  borderRadius: BorderRadius.circular(16.r),
                                ),
                                child: Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'Итоговая сумма',
                                          style: TextStyle(
                                            color:
                                                Colors.white.withOpacity(0.5),
                                            fontSize: 14.sp,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                        SizedBox(height: 4),
                                        Text(
                                          '${_calculateTotal().toStringAsFixed(0)} руб',
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontSize: 32.sp,
                                            fontWeight: FontWeight.bold,
                                            letterSpacing: -0.5,
                                          ),
                                        ),
                                      ],
                                    ),
                                    Container(
                                      padding: EdgeInsets.all(12.w),
                                      decoration: BoxDecoration(
                                        color: Colors.white.withOpacity(0.2),
                                        borderRadius:
                                            BorderRadius.circular(12.r),
                                      ),
                                      child: Icon(
                                        Icons.account_balance_wallet,
                                        color: Colors.white,
                                        size: 32,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              SizedBox(height: 28),
                            ],

                            // Кнопка сохранения
                            SizedBox(
                              height: 56,
                              child: ElevatedButton(
                                onPressed:
                                    _isSaving ? null : _showConfirmationDialog,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.green[600],
                                  foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(16.r),
                                  ),
                                  elevation: 0,
                                ),
                                child: _isSaving
                                    ? SizedBox(
                                        height: 24,
                                        width: 24,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 3,
                                          color: Colors.white,
                                        ),
                                      )
                                    : Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          Icon(Icons.check_circle_outline,
                                              size: 24),
                                          SizedBox(width: 8),
                                          Text(
                                            'Сохранить выемку',
                                            style: TextStyle(
                                              fontSize: 17.sp,
                                              fontWeight: FontWeight.bold,
                                              letterSpacing: 0.3,
                                            ),
                                          ),
                                        ],
                                      ),
                              ),
                            ),
                            SizedBox(height: 20),
                          ],
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value) {
    return Row(
      children: [
        Container(
          padding: EdgeInsets.all(10.w),
          decoration: BoxDecoration(
            color: AppColors.emerald.withOpacity(0.3),
            borderRadius: BorderRadius.circular(10.r),
          ),
          child: Icon(icon, color: AppColors.gold, size: 20),
        ),
        SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 12.sp,
                  color: Colors.white.withOpacity(0.5),
                  fontWeight: FontWeight.w500,
                ),
              ),
              SizedBox(height: 2),
              Text(
                value,
                style: TextStyle(
                  fontSize: 15.sp,
                  fontWeight: FontWeight.w600,
                  color: Colors.white.withOpacity(0.9),
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
    return GestureDetector(
      onTap: () => _onTypeChanged(value),
      child: Container(
        padding: EdgeInsets.symmetric(vertical: 16.h),
        decoration: BoxDecoration(
          color: isSelected ? color : Colors.white.withOpacity(0.06),
          borderRadius: BorderRadius.circular(14.r),
          border: Border.all(
            color: isSelected ? color : Colors.white.withOpacity(0.1),
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Column(
          children: [
            Icon(
              isSelected ? Icons.check_circle : Icons.circle_outlined,
              color: isSelected ? Colors.white : Colors.white.withOpacity(0.3),
              size: 28,
            ),
            SizedBox(height: 8),
            Text(
              label,
              style: TextStyle(
                fontSize: 16.sp,
                fontWeight: FontWeight.bold,
                color:
                    isSelected ? Colors.white : Colors.white.withOpacity(0.5),
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
    return SizedBox(
      height: 50,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12.r),
          ),
          elevation: 0,
          padding: EdgeInsets.symmetric(horizontal: 12.w),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 20),
            SizedBox(width: 6),
            Flexible(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 13.sp,
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
      margin: EdgeInsets.only(bottom: 16.h),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.06),
        borderRadius: BorderRadius.circular(14.r),
        border: Border.all(
          color: Colors.white.withOpacity(0.1),
        ),
      ),
      child: Padding(
        padding: EdgeInsets.all(16.w),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Заголовок с кнопкой удаления
            Row(
              children: [
                Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: 10.w,
                    vertical: 4.h,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.emerald.withOpacity(0.3),
                    borderRadius: BorderRadius.circular(8.r),
                  ),
                  child: Text(
                    'Расход ${index + 1}',
                    style: TextStyle(
                      fontSize: 13.sp,
                      fontWeight: FontWeight.bold,
                      color: AppColors.gold,
                    ),
                  ),
                ),
                Spacer(),
                Material(
                  color: Colors.red.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(8.r),
                  child: InkWell(
                    onTap: () => _removeExpense(index),
                    borderRadius: BorderRadius.circular(8.r),
                    child: Padding(
                      padding: EdgeInsets.all(8.w),
                      child: Icon(
                        Icons.delete_outline,
                        color: Colors.red[400],
                        size: 20,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            SizedBox(height: 16),

            // Поставщик (dropdown или бейдж "Другой расход")
            if (expense.isOtherExpense)
              Container(
                width: double.infinity,
                padding: EdgeInsets.all(14.w),
                decoration: BoxDecoration(
                  color: Colors.orange.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(12.r),
                  border: Border.all(
                    color: Colors.orange.withOpacity(0.3),
                    width: 1.5,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.edit_note,
                      color: Colors.orange[300],
                      size: 22,
                    ),
                    SizedBox(width: 10),
                    Text(
                      'Другой расход',
                      style: TextStyle(
                        fontSize: 15.sp,
                        fontWeight: FontWeight.w600,
                        color: Colors.orange[300],
                      ),
                    ),
                  ],
                ),
              )
            else
              Container(
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(12.r),
                  border: Border.all(
                    color: Colors.white.withOpacity(0.1),
                  ),
                ),
                child: DropdownButtonFormField<String>(
                  value: expense.supplierId,
                  decoration: InputDecoration(
                    labelText: 'Выберите поставщика',
                    labelStyle: TextStyle(
                      color: Colors.white.withOpacity(0.5),
                    ),
                    prefixIcon: Icon(
                      Icons.business,
                      color: AppColors.gold,
                    ),
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 16.w,
                      vertical: 14.h,
                    ),
                  ),
                  dropdownColor: AppColors.emeraldDark,
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.9),
                    fontSize: 14.sp,
                  ),
                  items: _filteredSuppliers.map((supplier) {
                    return DropdownMenuItem(
                      value: supplier.id,
                      child: Text(
                        supplier.name,
                        style: TextStyle(
                          fontSize: 14.sp,
                          color: Colors.white.withOpacity(0.9),
                        ),
                      ),
                    );
                  }).toList(),
                  onChanged: (value) {
                    if (mounted) setState(() {
                      expense.supplierId = value;
                      expense.supplierName = _filteredSuppliers
                          .firstWhere((s) => s.id == value)
                          .name;
                    });
                  },
                ),
              ),
            SizedBox(height: 14),

            // Сумма
            Container(
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.08),
                borderRadius: BorderRadius.circular(12.r),
                border: Border.all(
                  color: Colors.white.withOpacity(0.1),
                ),
              ),
              child: TextFormField(
                controller: expense.amountController,
                decoration: InputDecoration(
                  labelText: 'Сумма (руб)',
                  labelStyle: TextStyle(
                    color: Colors.white.withOpacity(0.5),
                  ),
                  prefixIcon: Icon(
                    Icons.account_balance_wallet,
                    color: Colors.green[400],
                  ),
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 16.w,
                    vertical: 14.h,
                  ),
                ),
                keyboardType: TextInputType.number,
                style: TextStyle(
                  fontSize: 16.sp,
                  fontWeight: FontWeight.w600,
                  color: Colors.white.withOpacity(0.9),
                ),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(
                      RegExp(r'^\d+\.?\d{0,2}')),
                ],
              ),
            ),
            SizedBox(height: 14),

            // Комментарий
            Container(
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.08),
                borderRadius: BorderRadius.circular(12.r),
                border: Border.all(
                  color: Colors.white.withOpacity(0.1),
                ),
              ),
              child: TextFormField(
                controller: expense.commentController,
                decoration: InputDecoration(
                  labelText: expense.isOtherExpense
                      ? 'Комментарий (обязательно)'
                      : 'Комментарий (опционально)',
                  labelStyle: TextStyle(
                    color: Colors.white.withOpacity(0.5),
                  ),
                  prefixIcon: Icon(
                    Icons.comment_outlined,
                    color: Colors.blue[400],
                  ),
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 16.w,
                    vertical: 14.h,
                  ),
                ),
                maxLines: 2,
                style: TextStyle(
                  fontSize: 14.sp,
                  color: Colors.white.withOpacity(0.9),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
