import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../employees/pages/employees_page.dart';
import '../../employees/services/employee_service.dart';
import '../services/bonus_penalty_service.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../../core/theme/app_colors.dart';

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

  // Gradient colors
  static final _bonusGradient = [AppColors.emeraldGreen, AppColors.emeraldGreenLight];
  static final _penaltyGradient = [AppColors.error, AppColors.errorLight];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final prefs = await SharedPreferences.getInstance();
    _adminName = prefs.getString('employeeName') ?? prefs.getString('name') ?? 'Администратор';

    final employees = await EmployeeService.getEmployees();
    if (!mounted) return;
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

  void _selectEmployee(Employee employee) {
    _showAmountDialog(employee);
  }

  void _showAmountDialog(Employee employee) {
    final amountController = TextEditingController();
    final commentController = TextEditingController();
    final formKey = GlobalKey<FormState>();

    final isBonus = _selectedType == 'bonus';
    final typeTitle = isBonus ? 'Премия' : 'Штраф';
    final gradientColors = isBonus ? _bonusGradient : _penaltyGradient;
    final accentColor = isBonus ? Colors.green : Colors.red;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28.r)),
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Handle bar
              Container(
                margin: EdgeInsets.only(top: 12.h),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2.r),
                ),
              ),
              // Header
              Container(
                width: double.infinity,
                margin: EdgeInsets.all(16.w),
                padding: EdgeInsets.all(20.w),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: gradientColors,
                  ),
                  borderRadius: BorderRadius.circular(20.r),
                  boxShadow: [
                    BoxShadow(
                      color: gradientColors[0].withOpacity(0.4),
                      blurRadius: 15,
                      offset: Offset(0, 8),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(16.r),
                      ),
                      child: Icon(
                        isBonus ? Icons.card_giftcard : Icons.money_off,
                        color: Colors.white,
                        size: 28,
                      ),
                    ),
                    SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            typeTitle,
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 20.sp,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            employee.name,
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.9),
                              fontSize: 15.sp,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              // Form
              Padding(
                padding: EdgeInsets.fromLTRB(16.w, 0.h, 16.w, 24.h),
                child: Form(
                  key: formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Amount field
                      Container(
                        decoration: BoxDecoration(
                          color: Colors.grey[50],
                          borderRadius: BorderRadius.circular(16.r),
                          border: Border.all(color: accentColor.withOpacity(0.3)),
                        ),
                        child: TextFormField(
                          controller: amountController,
                          keyboardType: TextInputType.number,
                          style: TextStyle(
                            fontSize: 24.sp,
                            fontWeight: FontWeight.bold,
                            color: accentColor,
                          ),
                          decoration: InputDecoration(
                            labelText: 'Сумма',
                            labelStyle: TextStyle(color: Colors.grey[600]),
                            prefixIcon: Container(
                              margin: EdgeInsets.all(12.w),
                              width: 44,
                              height: 44,
                              decoration: BoxDecoration(
                                color: accentColor.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(12.r),
                              ),
                              child: Icon(
                                isBonus ? Icons.add : Icons.remove,
                                color: accentColor,
                              ),
                            ),
                            suffixText: 'руб',
                            suffixStyle: TextStyle(
                              fontSize: 18.sp,
                              fontWeight: FontWeight.w500,
                              color: Colors.grey[600],
                            ),
                            border: InputBorder.none,
                            contentPadding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 20.h),
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
                      ),
                      SizedBox(height: 16),
                      // Comment field
                      Container(
                        decoration: BoxDecoration(
                          color: Colors.grey[50],
                          borderRadius: BorderRadius.circular(16.r),
                          border: Border.all(color: Colors.grey[300]!),
                        ),
                        child: TextFormField(
                          controller: commentController,
                          maxLines: 3,
                          decoration: InputDecoration(
                            labelText: 'Комментарий',
                            labelStyle: TextStyle(color: Colors.grey[600]),
                            hintText: 'Причина ${isBonus ? "премии" : "штрафа"}...',
                            hintStyle: TextStyle(color: Colors.grey[400]),
                            prefixIcon: Container(
                              margin: EdgeInsets.only(left: 12.w, top: 12.h, bottom: 12.h),
                              alignment: Alignment.topCenter,
                              width: 44,
                              height: 44,
                              decoration: BoxDecoration(
                                color: Colors.grey[200],
                                borderRadius: BorderRadius.circular(12.r),
                              ),
                              child: Icon(
                                Icons.comment_outlined,
                                color: Colors.grey[600],
                              ),
                            ),
                            border: InputBorder.none,
                            contentPadding: EdgeInsets.all(16.w),
                          ),
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) {
                              return 'Введите комментарий';
                            }
                            return null;
                          },
                        ),
                      ),
                      SizedBox(height: 24),
                      // Buttons
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () => Navigator.pop(context),
                              style: OutlinedButton.styleFrom(
                                padding: EdgeInsets.symmetric(vertical: 16.h),
                                side: BorderSide(color: Colors.grey[400]!),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14.r),
                                ),
                              ),
                              child: Text(
                                'Отмена',
                                style: TextStyle(
                                  fontSize: 16.sp,
                                  color: Colors.grey[700],
                                ),
                              ),
                            ),
                          ),
                          SizedBox(width: 12),
                          Expanded(
                            flex: 2,
                            child: Container(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: gradientColors,
                                ),
                                borderRadius: BorderRadius.circular(14.r),
                                boxShadow: [
                                  BoxShadow(
                                    color: gradientColors[0].withOpacity(0.4),
                                    blurRadius: 12,
                                    offset: Offset(0, 6),
                                  ),
                                ],
                              ),
                              child: ElevatedButton(
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
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.transparent,
                                  shadowColor: Colors.transparent,
                                  padding: EdgeInsets.symmetric(vertical: 16.h),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14.r),
                                  ),
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      isBonus ? Icons.check_circle : Icons.send,
                                      color: Colors.white,
                                    ),
                                    SizedBox(width: 8),
                                    Text(
                                      isBonus ? 'Начислить' : 'Списать',
                                      style: TextStyle(
                                        fontSize: 16.sp,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ).then((_) {
      amountController.dispose();
      commentController.dispose();
    });
  }

  Future<void> _createRecord(Employee employee, double amount, String comment) async {
    if (mounted) setState(() => _isLoading = true);

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
      final isBonus = _selectedType == 'bonus';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(
                isBonus ? Icons.check_circle : Icons.info,
                color: Colors.white,
              ),
              SizedBox(width: 12),
              Expanded(
                child: Text('$typeText ${amount.toStringAsFixed(0)} руб для ${employee.name}'),
              ),
            ],
          ),
          backgroundColor: isBonus ? Colors.green[600] : Colors.red[600],
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.r)),
        ),
      );
      if (mounted) setState(() => _selectedType = null);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(Icons.error, color: Colors.white),
              SizedBox(width: 12),
              Text('Ошибка при создании записи'),
            ],
          ),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.r)),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.night,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: Text(_selectedType == null
            ? 'Премия/Штрафы'
            : (_selectedType == 'bonus' ? 'Премия' : 'Штраф')),
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          if (_selectedType != null)
            Container(
              margin: EdgeInsets.only(right: 8.w),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.08),
                borderRadius: BorderRadius.circular(12.r),
                border: Border.all(color: Colors.white.withOpacity(0.1)),
              ),
              child: IconButton(
                icon: Icon(Icons.close, color: AppColors.gold),
                onPressed: () => setState(() => _selectedType = null),
                tooltip: 'Сбросить выбор',
              ),
            ),
        ],
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [AppColors.emerald, AppColors.emeraldDark, AppColors.night],
            stops: [0.0, 0.3, 1.0],
          ),
        ),
        child: _isLoading
            ? Center(child: CircularProgressIndicator(color: AppColors.gold))
            : _selectedType == null
                ? _buildTypeSelection()
                : _buildEmployeeList(),
      ),
    );
  }

  Widget _buildTypeSelection() {
    return SafeArea(
      child: Column(
        children: [
          // Header
          Padding(
            padding: EdgeInsets.fromLTRB(24.w, 60.h, 24.w, 0.h),
            child: Column(
              children: [
                Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(20.r),
                    border: Border.all(color: AppColors.gold.withOpacity(0.3)),
                  ),
                  child: Icon(
                    Icons.account_balance_wallet_outlined,
                    color: AppColors.gold,
                    size: 36,
                  ),
                ),
                SizedBox(height: 16),
                Text(
                  'Управление премиями',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.9),
                    fontSize: 22.sp,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                SizedBox(height: 8),
                Text(
                  'Начислите премию или назначьте штраф',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.5),
                    fontSize: 14.sp,
                  ),
                ),
              ],
            ),
          ),
          // Selection buttons
          Expanded(
            child: Padding(
              padding: EdgeInsets.all(24.w),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _buildLargeTypeButton(
                    icon: Icons.card_giftcard,
                    title: 'Премия',
                    subtitle: 'Начислить сотруднику денежное вознаграждение',
                    gradientColors: _bonusGradient,
                    type: 'bonus',
                  ),
                  SizedBox(height: 16),
                  _buildLargeTypeButton(
                    icon: Icons.money_off,
                    title: 'Штраф',
                    subtitle: 'Списать у сотрудника за нарушение',
                    gradientColors: _penaltyGradient,
                    type: 'penalty',
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLargeTypeButton({
    required IconData icon,
    required String title,
    required String subtitle,
    required List<Color> gradientColors,
    required String type,
  }) {
    return GestureDetector(
      onTap: () => setState(() => _selectedType = type),
      child: Container(
        width: double.infinity,
        padding: EdgeInsets.all(20.w),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.06),
          borderRadius: BorderRadius.circular(20.r),
          border: Border.all(color: gradientColors[0].withOpacity(0.3)),
        ),
        child: Row(
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: gradientColors,
                ),
                borderRadius: BorderRadius.circular(16.r),
                boxShadow: [
                  BoxShadow(
                    color: gradientColors[0].withOpacity(0.3),
                    blurRadius: 10,
                    offset: Offset(0, 4),
                  ),
                ],
              ),
              child: Icon(icon, color: Colors.white, size: 28),
            ),
            SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 20.sp,
                      fontWeight: FontWeight.bold,
                      color: gradientColors[1],
                    ),
                  ),
                  SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 13.sp,
                      color: Colors.white.withOpacity(0.5),
                    ),
                  ),
                ],
              ),
            ),
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: gradientColors[0].withOpacity(0.15),
                borderRadius: BorderRadius.circular(12.r),
              ),
              child: Icon(
                Icons.arrow_forward_ios,
                color: gradientColors[1],
                size: 18,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmployeeList() {
    final isBonus = _selectedType == 'bonus';
    final gradientColors = isBonus ? _bonusGradient : _penaltyGradient;

    return SafeArea(
      bottom: false,
      child: Column(
        children: [
          // Header
          Padding(
            padding: EdgeInsets.fromLTRB(20.w, 60.h, 20.w, 0.h),
            child: Container(
              padding: EdgeInsets.all(14.w),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.08),
                borderRadius: BorderRadius.circular(16.r),
                border: Border.all(color: gradientColors[0].withOpacity(0.3)),
              ),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(colors: gradientColors),
                      borderRadius: BorderRadius.circular(12.r),
                    ),
                    child: Icon(
                      isBonus ? Icons.card_giftcard : Icons.money_off,
                      color: Colors.white,
                      size: 22,
                    ),
                  ),
                  SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Выберите сотрудника',
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.9),
                            fontSize: 15.sp,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          isBonus ? 'для начисления премии' : 'для назначения штрафа',
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.5),
                            fontSize: 12.sp,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          // Search field
          Padding(
            padding: EdgeInsets.fromLTRB(16.w, 14.h, 16.w, 8.h),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.08),
                borderRadius: BorderRadius.circular(14.r),
                border: Border.all(color: Colors.white.withOpacity(0.1)),
              ),
              child: TextField(
                onChanged: (value) => setState(() => _searchQuery = value),
                style: TextStyle(color: Colors.white),
                cursorColor: AppColors.gold,
                decoration: InputDecoration(
                  hintText: 'Поиск сотрудника...',
                  hintStyle: TextStyle(color: Colors.white.withOpacity(0.3)),
                  prefixIcon: Icon(Icons.search, color: AppColors.gold),
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 14.h),
                ),
              ),
            ),
          ),
          // Employee list
          Expanded(
            child: _filteredEmployees.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.person_search,
                          size: 56,
                          color: Colors.white.withOpacity(0.2),
                        ),
                        SizedBox(height: 16),
                        Text(
                          _searchQuery.isEmpty
                              ? 'Нет сотрудников'
                              : 'Ничего не найдено',
                          style: TextStyle(
                            fontSize: 16.sp,
                            color: Colors.white.withOpacity(0.5),
                          ),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 4.h),
                    itemCount: _filteredEmployees.length,
                    itemBuilder: (context, index) {
                      final employee = _filteredEmployees[index];
                      return _buildEmployeeCard(employee);
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmployeeCard(Employee employee) {
    final isBonus = _selectedType == 'bonus';
    final gradientColors = isBonus ? _bonusGradient : _penaltyGradient;

    return GestureDetector(
      onTap: () => _selectEmployee(employee),
      child: Container(
        margin: EdgeInsets.only(bottom: 6.h),
        padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 10.h),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.06),
          borderRadius: BorderRadius.circular(14.r),
          border: Border.all(color: Colors.white.withOpacity(0.1)),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [AppColors.emeraldDark, AppColors.emerald],
                ),
                borderRadius: BorderRadius.circular(12.r),
              ),
              child: Center(
                child: Text(
                  employee.name.isNotEmpty ? employee.name[0].toUpperCase() : '?',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 18.sp,
                  ),
                ),
              ),
            ),
            SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    employee.name,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 15.sp,
                      color: Colors.white.withOpacity(0.9),
                    ),
                  ),
                  if (employee.phone != null && employee.phone!.isNotEmpty)
                    Text(
                      employee.phone!,
                      style: TextStyle(
                        fontSize: 12.sp,
                        color: Colors.white.withOpacity(0.4),
                      ),
                    ),
                ],
              ),
            ),
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: gradientColors[0].withOpacity(0.15),
                borderRadius: BorderRadius.circular(10.r),
              ),
              child: Icon(
                isBonus ? Icons.add_circle_outline : Icons.remove_circle_outline,
                color: gradientColors[1],
                size: 20,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
