import 'package:flutter/material.dart';
import '../services/kpi_service.dart';
import '../models/kpi_models.dart';
import 'kpi_employee_day_detail_page.dart';
import '../../../core/utils/logger.dart';

/// Детальная страница сотрудника со списком магазинов и дат работы
class KPIEmployeeDetailPage extends StatefulWidget {
  final String employeeName;
  final int? year;
  final int? month;

  const KPIEmployeeDetailPage({
    super.key,
    required this.employeeName,
    this.year,
    this.month,
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

      // Фильтровать по месяцу, если указан
      List<KPIEmployeeShopDayData> filteredData = data;
      if (widget.year != null && widget.month != null) {
        filteredData = data.where((day) {
          return day.date.year == widget.year && day.date.month == widget.month;
        }).toList();
      }

      if (mounted) {
        setState(() {
          _shopDaysData = filteredData;
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
  int get _totalEnvelopes => _shopDaysData.where((day) => day.hasEnvelope).length;
  int get _totalShiftHandovers => _shopDaysData.where((day) => day.hasShiftHandover).length;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.year != null && widget.month != null
              ? '${widget.employeeName} - ${widget.month}.${widget.year}'
              : widget.employeeName,
        ),
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
                      child: Column(
                        children: [
                          Row(
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
                            ],
                          ),
                          const SizedBox(height: 12),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceAround,
                            children: [
                              _buildStatCard(
                                'РКО',
                                _totalRKOs.toString(),
                                Icons.receipt_long,
                              ),
                              _buildStatCard(
                                'Конвертов',
                                _totalEnvelopes.toString(),
                                Icons.mail,
                              ),
                              _buildStatCard(
                                'Сдач смены',
                                _totalShiftHandovers.toString(),
                                Icons.swap_horiz,
                              ),
                            ],
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
                              trailing: SingleChildScrollView(
                                scrollDirection: Axis.horizontal,
                                child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  // Приход - часы
                                  _buildIndicator(
                                    Icons.access_time,
                                    shopDay.attendanceTime != null,
                                  ),
                                  const SizedBox(width: 8),
                                  // Пересменка - рукопожатие
                                  _buildIndicator(
                                    Icons.handshake,
                                    shopDay.hasShift,
                                  ),
                                  const SizedBox(width: 8),
                                  // Пересчет - калькулятор
                                  _buildIndicator(
                                    Icons.calculate,
                                    shopDay.hasRecount,
                                  ),
                                  const SizedBox(width: 8),
                                  // РКО - документ
                                  _buildIndicator(
                                    Icons.description,
                                    shopDay.hasRKO,
                                  ),
                                  const SizedBox(width: 8),
                                  // Конверт - письмо
                                  _buildIndicator(
                                    Icons.mail,
                                    shopDay.hasEnvelope,
                                  ),
                                  const SizedBox(width: 8),
                                  // Сдача смены - деньги
                                  _buildIndicator(
                                    Icons.payments,
                                    shopDay.hasShiftHandover,
                                  ),
                                ],
                              ),
                                ),
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

  Widget _buildIndicator(IconData topIcon, bool isCompleted) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          topIcon,
          size: 14,
          color: Colors.grey[600],
        ),
        const SizedBox(height: 2),
        Icon(
          isCompleted ? Icons.check_circle : Icons.cancel,
          size: 18,
          color: isCompleted ? Colors.green : Colors.red,
        ),
      ],
    );
  }

}

