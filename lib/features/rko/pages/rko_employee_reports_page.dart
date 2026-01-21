import 'package:flutter/material.dart';
import '../../employees/pages/employees_page.dart';
import '../services/rko_reports_service.dart';
import 'rko_pdf_viewer_page.dart';
import '../../../core/utils/logger.dart';

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

  Future<void> _loadEmployees() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final employees = await EmployeesPage.loadEmployeesForNotifications();
      setState(() {
        _employees = employees;
        _isLoading = false;
      });
    } catch (e) {
      Logger.error('Ошибка загрузки сотрудников', e);
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Отчет по сотруднику'),
        backgroundColor: const Color(0xFF004D40),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadEmployees,
            tooltip: 'Обновить',
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              decoration: InputDecoration(
                hintText: 'Поиск сотрудника...',
                prefixIcon: const Icon(Icons.search),
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
              onChanged: (value) {
                setState(() {
                  _searchQuery = value.trim().toLowerCase();
                });
              },
            ),
          ),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _employees.isEmpty
                    ? const Center(child: Text('Сотрудники не найдены'))
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        itemCount: _employees.length,
                        itemBuilder: (context, index) {
                          final employee = _employees[index];
                          
                          // Фильтрация по поисковому запросу
                          if (_searchQuery.isNotEmpty) {
                            final name = employee.name.toLowerCase();
                            if (!name.contains(_searchQuery)) {
                              return const SizedBox.shrink();
                            }
                          }

                          return Card(
                            margin: const EdgeInsets.symmetric(vertical: 4),
                            child: ListTile(
                              leading: const Icon(
                                Icons.person,
                                color: Color(0xFF004D40),
                              ),
                              title: Text(
                                employee.name,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              subtitle: Text(employee.position ?? ''),
                              trailing: const Icon(Icons.chevron_right),
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
  static const _primaryColor = Color(0xFF004D40);

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
    setState(() {
      _isLoading = true;
    });

    try {
      final data = await RKOReportsService.getEmployeeRKOs(widget.employeeName);
      if (data != null) {
        setState(() {
          _latest = data['latest'] ?? [];
          _months = data['months'] ?? [];
          _isLoading = false;
        });
      } else {
        setState(() {
          _isLoading = false;
        });
      }
    } catch (e) {
      Logger.error('Ошибка загрузки РКО', e);
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
        title: const Text('История РКО'),
        backgroundColor: _primaryColor,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadRKOs,
            tooltip: 'Обновить',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // Шапка с информацией о сотруднике
                Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: _primaryColor,
                    borderRadius: const BorderRadius.only(
                      bottomLeft: Radius.circular(24),
                      bottomRight: Radius.circular(24),
                    ),
                  ),
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
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
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: const Icon(
                              Icons.person_rounded,
                              color: Colors.white,
                              size: 30,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  widget.employeeName,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Всего документов: ${_latest.length}',
                                  style: TextStyle(
                                    color: Colors.white.withOpacity(0.8),
                                    fontSize: 14,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      // Общая сумма
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 44,
                              height: 44,
                              decoration: BoxDecoration(
                                color: Colors.green.withOpacity(0.3),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Icon(
                                Icons.payments_rounded,
                                color: Colors.white,
                                size: 24,
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Общая сумма выплат',
                                    style: TextStyle(
                                      color: Colors.white.withOpacity(0.8),
                                      fontSize: 13,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    '${_totalAmount.toStringAsFixed(0)} руб.',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 22,
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
                    padding: const EdgeInsets.all(16),
                    children: [
                      // Последние РКО
                      if (_latest.isNotEmpty) ...[
                        Row(
                          children: [
                            Icon(Icons.history, color: _primaryColor, size: 20),
                            const SizedBox(width: 8),
                            const Text(
                              'Последние выплаты',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF2D2D2D),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        ..._latest.map((rko) => _buildRKOCard(rko)),
                      ],

                      // Папка "За все время"
                      if (_months.isNotEmpty) ...[
                        const SizedBox(height: 20),
                        _buildAllTimeFolder(),

                        if (_showAllTime) ...[
                          const SizedBox(height: 8),
                          ..._months.map((monthData) => _buildMonthFolder(monthData)),
                        ],
                      ],

                      if (_latest.isEmpty && _months.isEmpty)
                        Center(
                          child: Padding(
                            padding: const EdgeInsets.all(32.0),
                            child: Column(
                              children: [
                                Icon(
                                  Icons.receipt_long_outlined,
                                  size: 64,
                                  color: Colors.grey[400],
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  'РКО не найдены',
                                  style: TextStyle(
                                    fontSize: 16,
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
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 10,
            offset: const Offset(0, 4),
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
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                // Иконка документа
                Container(
                  width: 50,
                  height: 50,
                  decoration: BoxDecoration(
                    color: isPdf ? Colors.red.withOpacity(0.1) : Colors.blue.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    isPdf ? Icons.picture_as_pdf_rounded : Icons.description_rounded,
                    color: isPdf ? Colors.red : Colors.blue,
                    size: 26,
                  ),
                ),
                const SizedBox(width: 14),
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
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF2D2D2D),
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (rkoType.isNotEmpty) ...[
                            const SizedBox(width: 8),
                            Flexible(
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: rkoType.contains('месяц')
                                      ? Colors.blue.withOpacity(0.1)
                                      : Colors.orange.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  rkoType,
                                  style: TextStyle(
                                    fontSize: 11,
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
                        const SizedBox(height: 4),
                        Text(
                          shopAddress,
                          style: TextStyle(
                            fontSize: 13,
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
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.green.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '$amount руб.',
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: Colors.green,
                      ),
                    ),
                  ),
                const SizedBox(width: 8),
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
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.blue.shade100),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            setState(() {
              _showAllTime = !_showAllTime;
            });
          },
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: Colors.blue.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.folder_rounded,
                    color: Colors.blue,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 14),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'За все время',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF2D2D2D),
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'Архив документов по месяцам',
                        style: TextStyle(
                          fontSize: 13,
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
      margin: const EdgeInsets.only(top: 8, left: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          leading: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: Colors.orange.withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.folder_outlined,
              color: Colors.orange,
              size: 22,
            ),
          ),
          title: Text(
            _formatMonth(monthKey),
            style: const TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 15,
            ),
          ),
          subtitle: Text(
            '${items.length} документов',
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey[600],
            ),
          ),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
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
      const monthNames = [
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

