import 'package:flutter/material.dart';
import '../services/kpi_service.dart';
import '../models/kpi_models.dart';
import 'kpi_employee_day_detail_page.dart';
import 'core/utils/logger.dart';

/// Детальная страница сотрудника со списком магазинов и дат работы
class KPIEmployeeDetailPage extends StatefulWidget {
  final String employeeName;

  const KPIEmployeeDetailPage({
    super.key,
    required this.employeeName,
  });

  @override
  State<KPIEmployeeDetailPage> createState() => _KPIEmployeeDetailPageState();
}

class _KPIEmployeeDetailPageState extends State<KPIEmployeeDetailPage> {
  List<KPIEmployeeShopDayData> _shopDaysData = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadShopDaysData();
  }

  Future<void> _loadShopDaysData() async {
    setState(() => _isLoading = true);

    try {
      final data = await KPIService.getEmployeeShopDaysData(widget.employeeName);
      if (mounted) {
        setState(() {
          _shopDaysData = data;
          _isLoading = false;
        });
      }
    } catch (e) {
      Logger.error('Ошибка загрузки данных сотрудника', e);
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  int get _totalDaysWorked => _shopDaysData.length;
  int get _totalShifts => _shopDaysData.where((day) => day.hasShift).length;
  int get _totalRecounts => _shopDaysData.where((day) => day.hasRecount).length;
  int get _totalRKOs => _shopDaysData.where((day) => day.hasRKO).length;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.employeeName),
        backgroundColor: const Color(0xFF004D40),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              KPIService.clearCache();
              _loadShopDaysData();
            },
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _shopDaysData.isEmpty
              ? const Center(child: Text('Нет данных'))
              : Column(
                  children: [
                    // Статистика
                    Container(
                      padding: const EdgeInsets.all(16.0),
                      color: const Color(0xFF004D40).withOpacity(0.1),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          _buildStatCard(
                            'Дней отработано',
                            _totalDaysWorked.toString(),
                            Icons.calendar_today,
                          ),
                          _buildStatCard(
                            'Пересменок',
                            _totalShifts.toString(),
                            Icons.work_history,
                          ),
                          _buildStatCard(
                            'Пересчетов',
                            _totalRecounts.toString(),
                            Icons.inventory,
                          ),
                          _buildStatCard(
                            'РКО',
                            _totalRKOs.toString(),
                            Icons.receipt_long,
                          ),
                        ],
                      ),
                    ),
                    // Список магазинов с датами
                    Expanded(
                      child: ListView.builder(
                        itemCount: _shopDaysData.length,
                        itemBuilder: (context, index) {
                          final shopDay = _shopDaysData[index];
                          return Card(
                            margin: const EdgeInsets.symmetric(
                              horizontal: 16.0,
                              vertical: 8.0,
                            ),
                            child: ListTile(
                              title: Text(
                                shopDay.displayTitle,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              subtitle: shopDay.formattedAttendanceTime != null
                                  ? Text('Приход: ${shopDay.formattedAttendanceTime}')
                                  : const Text('Приход: не отмечен'),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  // Иконка прихода
                                  Icon(
                                    shopDay.attendanceTime != null
                                        ? Icons.check
                                        : Icons.close,
                                    color: shopDay.attendanceTime != null
                                        ? Colors.green
                                        : Colors.red,
                                    size: 20,
                                  ),
                                  const SizedBox(width: 8),
                                  // Иконка пересменки
                                  Icon(
                                    shopDay.hasShift ? Icons.check : Icons.close,
                                    color: shopDay.hasShift ? Colors.green : Colors.red,
                                    size: 20,
                                  ),
                                  const SizedBox(width: 8),
                                  // Иконка пересчета
                                  Icon(
                                    shopDay.hasRecount ? Icons.check : Icons.close,
                                    color: shopDay.hasRecount ? Colors.green : Colors.red,
                                    size: 20,
                                  ),
                                  const SizedBox(width: 8),
                                  // Иконка РКО
                                  Icon(
                                    shopDay.hasRKO ? Icons.check : Icons.close,
                                    color: shopDay.hasRKO ? Colors.green : Colors.red,
                                    size: 20,
                                  ),
                                ],
                              ),
                              onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => KPIEmployeeDayDetailPage(
                                      shopDayData: shopDay,
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

  Widget _buildStatCard(String label, String value, IconData icon) {
    return Column(
      children: [
        Icon(icon, color: const Color(0xFF004D40)),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: Color(0xFF004D40),
          ),
        ),
        Text(
          label,
          style: const TextStyle(fontSize: 12),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

}

