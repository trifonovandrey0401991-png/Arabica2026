import 'package:flutter/material.dart';
import '../../employees/pages/employees_page.dart';
import '../services/rko_reports_service.dart';
import 'rko_pdf_viewer_page.dart';
import '../../../core/services/multitenancy_filter_service.dart';
import '../../../core/utils/logger.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/cache_manager.dart';

/// Страница отчетов по сотрудникам
class RKOEmployeeReportsPage extends StatefulWidget {
  const RKOEmployeeReportsPage({super.key});

  @override
  State<RKOEmployeeReportsPage> createState() => _RKOEmployeeReportsPageState();
}

class _RKOEmployeeReportsPageState extends State<RKOEmployeeReportsPage> {
  List<Employee> _employees = [];
  bool _isLoading = true;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _loadEmployees();
  }

  static const _cacheKey = 'rko_employee_reports';

  Future<void> _loadEmployees() async {
    // Step 1: Show cached data instantly
    final cached = CacheManager.get<List<Employee>>(_cacheKey);
    if (cached != null && mounted) {
      setState(() {
        _employees = cached;
        _isLoading = false;
      });
    }

    if (_employees.isEmpty && mounted) setState(() => _isLoading = true);

    try {
      final allEmployees = await EmployeesPage.loadEmployeesForNotifications();
      final employees = await MultitenancyFilterService.filterByEmployeePhone<Employee>(
        allEmployees,
        (emp) => emp.phone ?? '',
      );
      if (!mounted) return;
      setState(() {
        _employees = employees;
        _isLoading = false;
      });
      // Step 3: Save to cache
      CacheManager.set(_cacheKey, employees);
    } catch (e) {
      Logger.error('Ошибка загрузки сотрудников', e);
      if (!mounted) return;
      if (_employees.isEmpty) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Отчет по сотруднику'),
        backgroundColor: AppColors.primaryGreen,
        actions: [
          IconButton(
            icon: Icon(Icons.refresh),
            onPressed: _loadEmployees,
            tooltip: 'Обновить',
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: EdgeInsets.all(12.w),
            child: TextField(
              decoration: InputDecoration(
                hintText: 'Поиск сотрудника...',
                prefixIcon: Icon(Icons.search),
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12.r),
                  borderSide: BorderSide.none,
                ),
              ),
              onChanged: (value) {
                if (mounted) setState(() {
                  _searchQuery = value.trim().toLowerCase();
                });
              },
            ),
          ),
          Expanded(
            child: _isLoading
                ? Center(child: CircularProgressIndicator())
                : _employees.isEmpty
                    ? Center(child: Text('Сотрудники не найдены'))
                    : ListView.builder(
                        padding: EdgeInsets.symmetric(horizontal: 8.w),
                        itemCount: _employees.length,
                        itemBuilder: (context, index) {
                          final employee = _employees[index];
                          
                          // Фильтрация по поисковому запросу
                          if (_searchQuery.isNotEmpty) {
                            final name = employee.name.toLowerCase();
                            if (!name.contains(_searchQuery)) {
                              return SizedBox.shrink();
                            }
                          }

                          return Card(
                            margin: EdgeInsets.symmetric(vertical: 4.h),
                            child: ListTile(
                              leading: Icon(
                                Icons.person,
                                color: AppColors.primaryGreen,
                              ),
                              title: Text(
                                employee.name,
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              subtitle: Text(employee.position ?? ''),
                              trailing: Icon(Icons.chevron_right),
                              onTap: () {
                                // Нормализуем имя сотрудника (приводим к нижнему регистру для совместимости)
                                final normalizedName = employee.name.toLowerCase().trim().replaceAll(RegExp(r'\s+'), ' ');
                                Logger.debug('Поиск РКО для сотрудника: "$normalizedName" (оригинальное имя: "${employee.name}")');
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => RKOEmployeeDetailPage(
                                      employeeName: normalizedName,
                                    ),
                                  ),
                                );
                              },
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}

/// Страница детального просмотра РКО сотрудника
class RKOEmployeeDetailPage extends StatefulWidget {
  final String employeeName;

  const RKOEmployeeDetailPage({
    super.key,
    required this.employeeName,
  });

  @override
  State<RKOEmployeeDetailPage> createState() => _RKOEmployeeDetailPageState();
}

class _RKOEmployeeDetailPageState extends State<RKOEmployeeDetailPage> {
  List<dynamic> _latest = [];
  List<dynamic> _months = [];
  bool _isLoading = true;
  bool _showAllTime = false;

  @override
  void initState() {
    super.initState();
    _loadRKOs();
  }

  Future<void> _loadRKOs() async {
    if (mounted) setState(() {
      _isLoading = true;
    });

    try {
      final data = await RKOReportsService.getEmployeeRKOs(widget.employeeName);
      if (!mounted) return;
      if (data != null) {
        setState(() {
          _latest = data['latest'] ?? [];
          _months = data['months'] ?? [];
          _isLoading = false;
        });
      } else {
        if (mounted) setState(() {
          _isLoading = false;
        });
      }
    } catch (e) {
      Logger.error('Ошибка загрузки РКО', e);
      if (!mounted) return;
      setState(() {
        _isLoading = false;
      });
    }
  }

  // Вычисляем общую сумму
  double get _totalAmount {
    double total = 0;
    for (var rko in _latest) {
      final amount = double.tryParse(rko['amount']?.toString() ?? '0') ?? 0;
      total += amount;
    }
    return total;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: Text('История РКО'),
        backgroundColor: AppColors.primaryGreen,
        elevation: 0,
        actions: [
          IconButton(
            icon: Icon(Icons.refresh),
            onPressed: _loadRKOs,
            tooltip: 'Обновить',
          ),
        ],
      ),
      body: _isLoading
          ? Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // Шапка с информацией о сотруднике
                Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: AppColors.primaryGreen,
                    borderRadius: BorderRadius.only(
                      bottomLeft: Radius.circular(24.r),
                      bottomRight: Radius.circular(24.r),
                    ),
                  ),
                  padding: EdgeInsets.fromLTRB(20.w, 0.h, 20.w, 24.h),
                  child: Column(
                    children: [
                      // Аватар и имя
                      Row(
                        children: [
                          Container(
                            width: 56,
                            height: 56,
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(16.r),
                            ),
                            child: Icon(
                              Icons.person_rounded,
                              color: Colors.white,
                              size: 30,
                            ),
                          ),
                          SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  widget.employeeName,
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 18.sp,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                SizedBox(height: 4),
                                Text(
                                  'Всего документов: ${_latest.length}',
                                  style: TextStyle(
                                    color: Colors.white.withOpacity(0.8),
                                    fontSize: 14.sp,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: 16),
                      // Общая сумма
                      Container(
                        width: double.infinity,
                        padding: EdgeInsets.all(16.w),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(16.r),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 44,
                              height: 44,
                              decoration: BoxDecoration(
                                color: Colors.green.withOpacity(0.3),
                                borderRadius: BorderRadius.circular(12.r),
                              ),
                              child: Icon(
                                Icons.payments_rounded,
                                color: Colors.white,
                                size: 24,
                              ),
                            ),
                            SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Общая сумма выплат',
                                    style: TextStyle(
                                      color: Colors.white.withOpacity(0.8),
                                      fontSize: 13.sp,
                                    ),
                                  ),
                                  SizedBox(height: 2),
                                  Text(
                                    '${_totalAmount.toStringAsFixed(0)} руб.',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 22.sp,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                // Список РКО
                Expanded(
                  child: ListView(
                    padding: EdgeInsets.all(16.w),
                    children: [
                      // Последние РКО
                      if (_latest.isNotEmpty) ...[
                        Row(
                          children: [
                            Icon(Icons.history, color: AppColors.primaryGreen, size: 20),
                            SizedBox(width: 8),
                            Text(
                              'Последние выплаты',
                              style: TextStyle(
                                fontSize: 16.sp,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF2D2D2D),
                              ),
                            ),
                          ],
                        ),
                        SizedBox(height: 12),
                        ..._latest.map((rko) => _buildRKOCard(rko)),
                      ],

                      // Папка "За все время"
                      if (_months.isNotEmpty) ...[
                        SizedBox(height: 20),
                        _buildAllTimeFolder(),

                        if (_showAllTime) ...[
                          SizedBox(height: 8),
                          ..._months.map((monthData) => _buildMonthFolder(monthData)),
                        ],
                      ],

                      if (_latest.isEmpty && _months.isEmpty)
                        Center(
                          child: Padding(
                            padding: EdgeInsets.all(32.0.w),
                            child: Column(
                              children: [
                                Icon(
                                  Icons.receipt_long_outlined,
                                  size: 64,
                                  color: Colors.grey[400],
                                ),
                                SizedBox(height: 16),
                                Text(
                                  'РКО не найдены',
                                  style: TextStyle(
                                    fontSize: 16.sp,
                                    color: Colors.grey[600],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildRKOCard(dynamic rko) {
    final fileName = rko['fileName'] ?? '';
    final date = rko['date'] ?? '';
    final amount = rko['amount']?.toString() ?? '';
    final rkoType = rko['rkoType'] ?? '';
    final shopAddress = rko['shopAddress'] ?? '';

    final isPdf = !fileName.toLowerCase().endsWith('.docx');
    final displayDate = date.length >= 10 ? date.substring(0, 10) : date;

    return Container(
      margin: EdgeInsets.only(bottom: 12.h),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16.r),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 10,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => RKOPDFViewerPage(fileName: fileName),
              ),
            );
          },
          borderRadius: BorderRadius.circular(16.r),
          child: Padding(
            padding: EdgeInsets.all(16.w),
            child: Row(
              children: [
                // Иконка документа
                Container(
                  width: 50,
                  height: 50,
                  decoration: BoxDecoration(
                    color: isPdf ? Colors.red.withOpacity(0.1) : Colors.blue.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12.r),
                  ),
                  child: Icon(
                    isPdf ? Icons.picture_as_pdf_rounded : Icons.description_rounded,
                    color: isPdf ? Colors.red : Colors.blue,
                    size: 26,
                  ),
                ),
                SizedBox(width: 14),
                // Информация
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              displayDate,
                              style: TextStyle(
                                fontSize: 15.sp,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF2D2D2D),
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (rkoType.isNotEmpty) ...[
                            SizedBox(width: 8),
                            Flexible(
                              child: Container(
                                padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 2.h),
                                decoration: BoxDecoration(
                                  color: rkoType.contains('месяц')
                                      ? Colors.blue.withOpacity(0.1)
                                      : Colors.orange.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(6.r),
                                ),
                                child: Text(
                                  rkoType,
                                  style: TextStyle(
                                    fontSize: 11.sp,
                                    fontWeight: FontWeight.w500,
                                    color: rkoType.contains('месяц') ? Colors.blue : Colors.orange,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      if (shopAddress.isNotEmpty) ...[
                        SizedBox(height: 4),
                        Text(
                          shopAddress,
                          style: TextStyle(
                            fontSize: 13.sp,
                            color: Colors.grey[600],
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ],
                  ),
                ),
                // Сумма
                if (amount.isNotEmpty)
                  Container(
                    padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 8.h),
                    decoration: BoxDecoration(
                      color: Colors.green.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(10.r),
                    ),
                    child: Text(
                      '$amount руб.',
                      style: TextStyle(
                        fontSize: 15.sp,
                        fontWeight: FontWeight.bold,
                        color: Colors.green,
                      ),
                    ),
                  ),
                SizedBox(width: 8),
                Icon(
                  Icons.chevron_right_rounded,
                  color: Colors.grey[400],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAllTimeFolder() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.blue.shade50,
        borderRadius: BorderRadius.circular(16.r),
        border: Border.all(color: Colors.blue.shade100),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            if (mounted) setState(() {
              _showAllTime = !_showAllTime;
            });
          },
          borderRadius: BorderRadius.circular(16.r),
          child: Padding(
            padding: EdgeInsets.all(16.w),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: Colors.blue.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(12.r),
                  ),
                  child: Icon(
                    Icons.folder_rounded,
                    color: Colors.blue,
                    size: 24,
                  ),
                ),
                SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'За все время',
                        style: TextStyle(
                          fontSize: 16.sp,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF2D2D2D),
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'Архив документов по месяцам',
                        style: TextStyle(
                          fontSize: 13.sp,
                          color: Colors.blue,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  _showAllTime ? Icons.expand_less_rounded : Icons.expand_more_rounded,
                  color: Colors.blue,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMonthFolder(dynamic monthData) {
    final monthKey = monthData['monthKey'] ?? '';
    final items = monthData['items'] ?? [];

    return Container(
      margin: EdgeInsets.only(top: 8.h, left: 16.w),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14.r),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 4.h),
          leading: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: Colors.orange.withOpacity(0.1),
              borderRadius: BorderRadius.circular(10.r),
            ),
            child: Icon(
              Icons.folder_outlined,
              color: Colors.orange,
              size: 22,
            ),
          ),
          title: Text(
            _formatMonth(monthKey),
            style: TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 15.sp,
            ),
          ),
          subtitle: Text(
            '${items.length} документов',
            style: TextStyle(
              fontSize: 12.sp,
              color: Colors.grey[600],
            ),
          ),
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(8.w, 0.h, 8.w, 8.h),
              child: Column(
                children: items.map<Widget>((rko) => _buildRKOCard(rko)).toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatMonth(String monthKey) {
    // monthKey в формате YYYY-MM
    final parts = monthKey.split('-');
    if (parts.length == 2) {
      final year = parts[0];
      final month = int.tryParse(parts[1]) ?? 0;
      final monthNames = [
        'Январь', 'Февраль', 'Март', 'Апрель', 'Май', 'Июнь',
        'Июль', 'Август', 'Сентябрь', 'Октябрь', 'Ноябрь', 'Декабрь'
      ];
      if (month >= 1 && month <= 12) {
        return '${monthNames[month - 1]} $year';
      }
    }
    return monthKey;
  }
}
