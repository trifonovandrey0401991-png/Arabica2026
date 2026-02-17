import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../services/kpi_service.dart';
import '../models/kpi_models.dart';
import '../../../core/utils/logger.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

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
        backgroundColor: AppColors.primaryGreen,
        actions: [
          IconButton(
            icon: Icon(Icons.refresh),
            onPressed: () {
              KPIService.clearCache();
              _loadShopDaysData();
            },
          ),
        ],
      ),
      body: _isLoading
          ? Center(child: CircularProgressIndicator())
          : _shopDaysData.isEmpty
              ? Center(child: Text('Нет данных'))
              : Column(
                  children: [
                    // Статистика
                    Container(
                      padding: EdgeInsets.all(16.0.w),
                      color: AppColors.primaryGreen.withOpacity(0.1),
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
                          SizedBox(height: 12),
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
                            margin: EdgeInsets.symmetric(
                              horizontal: 16.0.w,
                              vertical: 8.0.h,
                            ),
                            child: ListTile(
                              title: Text(
                                shopDay.displayTitle,
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              subtitle: shopDay.formattedAttendanceTime != null
                                  ? Text('Приход: ${shopDay.formattedAttendanceTime}')
                                  : Text('Приход: не отмечен'),
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
                                  SizedBox(width: 8),
                                  // Пересменка - рукопожатие
                                  _buildIndicator(
                                    Icons.handshake,
                                    shopDay.hasShift,
                                  ),
                                  SizedBox(width: 8),
                                  // Пересчет - калькулятор
                                  _buildIndicator(
                                    Icons.calculate,
                                    shopDay.hasRecount,
                                  ),
                                  SizedBox(width: 8),
                                  // РКО - документ
                                  _buildIndicator(
                                    Icons.description,
                                    shopDay.hasRKO,
                                  ),
                                  SizedBox(width: 8),
                                  // Конверт - письмо
                                  _buildIndicator(
                                    Icons.mail,
                                    shopDay.hasEnvelope,
                                  ),
                                  SizedBox(width: 8),
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
        Icon(icon, color: AppColors.primaryGreen),
        SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            fontSize: 20.sp,
            fontWeight: FontWeight.bold,
            color: AppColors.primaryGreen,
          ),
        ),
        Text(
          label,
          style: TextStyle(fontSize: 12.sp),
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
        SizedBox(height: 2),
        Icon(
          isCompleted ? Icons.check_circle : Icons.cancel,
          size: 18,
          color: isCompleted ? Colors.green : Colors.red,
        ),
      ],
    );
  }

}

