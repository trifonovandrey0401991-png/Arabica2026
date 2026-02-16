import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/attendance_model.dart';
import '../services/attendance_report_service.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

/// Страница детальной информации по посещаемости сотрудника
class AttendanceEmployeeDetailPage extends StatefulWidget {
  final String employeeName;

  const AttendanceEmployeeDetailPage({
    super.key,
    required this.employeeName,
  });

  @override
  State<AttendanceEmployeeDetailPage> createState() => _AttendanceEmployeeDetailPageState();
}

class _AttendanceEmployeeDetailPageState extends State<AttendanceEmployeeDetailPage> {
  List<AttendanceRecord> _records = [];
  bool _isLoading = true;
  String _selectedPeriod = 'month'; // week, month, all

  static final _gradientColors = [Color(0xFF004D40), Color(0xFF00695C)];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);

    try {
      final now = DateTime.now();
      DateTime? startDate;

      switch (_selectedPeriod) {
        case 'week':
          startDate = now.subtract(Duration(days: 7));
          break;
        case 'month':
          startDate = DateTime(now.year, now.month, 1);
          break;
        default:
          startDate = null;
      }

      final records = await AttendanceReportService.getEmployeeRecords(
        widget.employeeName,
        startDate: startDate,
      );

      setState(() {
        _records = records;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Статистика
    final onTimeCount = _records.where((r) => r.isOnTime == true).length;
    final lateCount = _records.where((r) => r.isOnTime == false).length;
    final onTimeRate = _records.isNotEmpty ? (onTimeCount / _records.length * 100) : 0.0;

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: _gradientColors,
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              // Заголовок
              _buildHeader(),
              // Статистика
              _buildStatsCard(onTimeCount, lateCount, onTimeRate),
              // Фильтр периода
              _buildPeriodFilter(),
              // Список отметок
              Expanded(
                child: _isLoading
                    ? Center(child: CircularProgressIndicator(color: Colors.white))
                    : _buildRecordsList(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: EdgeInsets.fromLTRB(16.w, 8.h, 16.w, 12.h),
      child: Row(
        children: [
          Container(
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.15),
              borderRadius: BorderRadius.circular(12.r),
            ),
            child: IconButton(
              icon: Icon(Icons.arrow_back, color: Colors.white),
              onPressed: () => Navigator.pop(context),
            ),
          ),
          SizedBox(width: 12),
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
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  'Отметок: ${_records.length}',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.7),
                    fontSize: 13.sp,
                  ),
                ),
              ],
            ),
          ),
          Container(
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.15),
              borderRadius: BorderRadius.circular(12.r),
            ),
            child: IconButton(
              icon: Icon(Icons.refresh, color: Colors.white),
              onPressed: _loadData,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatsCard(int onTimeCount, int lateCount, double onTimeRate) {
    return Container(
      margin: EdgeInsets.symmetric(horizontal: 16.w, vertical: 8.h),
      padding: EdgeInsets.all(16.w),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16.r),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 8,
            offset: Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildStatItem('Вовремя', onTimeCount.toString(), Colors.green),
          _buildStatItem('Опоздания', lateCount.toString(), Colors.red),
          _buildStatItem('Процент', '${onTimeRate.toStringAsFixed(0)}%', _getOnTimeColor(onTimeRate)),
        ],
      ),
    );
  }

  Widget _buildStatItem(String label, String value, Color color) {
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(
            fontSize: 24.sp,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 12.sp,
            color: Colors.grey[600],
          ),
        ),
      ],
    );
  }

  Widget _buildPeriodFilter() {
    return Container(
      margin: EdgeInsets.symmetric(horizontal: 16.w, vertical: 8.h),
      child: Row(
        children: [
          _buildPeriodChip('week', 'Неделя'),
          SizedBox(width: 8),
          _buildPeriodChip('month', 'Месяц'),
          SizedBox(width: 8),
          _buildPeriodChip('all', 'Все'),
        ],
      ),
    );
  }

  Widget _buildPeriodChip(String period, String label) {
    final isSelected = _selectedPeriod == period;
    return Expanded(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            setState(() => _selectedPeriod = period);
            _loadData();
          },
          borderRadius: BorderRadius.circular(10.r),
          child: Container(
            padding: EdgeInsets.symmetric(vertical: 10.h),
            decoration: BoxDecoration(
              color: isSelected ? Colors.white : Colors.white.withOpacity(0.1),
              borderRadius: BorderRadius.circular(10.r),
              border: Border.all(
                color: isSelected ? Colors.white : Colors.white30,
              ),
            ),
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: isSelected ? _gradientColors[0] : Colors.white,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildRecordsList() {
    if (_records.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.access_time, size: 64, color: Colors.white.withOpacity(0.5)),
            SizedBox(height: 16),
            Text(
              'Нет отметок за период',
              style: TextStyle(color: Colors.white, fontSize: 16.sp),
            ),
          ],
        ),
      );
    }

    // Группируем по дате
    final groupedRecords = <String, List<AttendanceRecord>>{};
    for (final record in _records) {
      final dateKey = DateFormat('dd.MM.yyyy').format(record.timestamp);
      groupedRecords.putIfAbsent(dateKey, () => []).add(record);
    }

    final sortedDates = groupedRecords.keys.toList()
      ..sort((a, b) => DateFormat('dd.MM.yyyy').parse(b).compareTo(DateFormat('dd.MM.yyyy').parse(a)));

    return ListView.builder(
      padding: EdgeInsets.all(16.w),
      itemCount: sortedDates.length,
      itemBuilder: (context, index) {
        final date = sortedDates[index];
        final records = groupedRecords[date]!;
        return _buildDayCard(date, records);
      },
    );
  }

  Widget _buildDayCard(String date, List<AttendanceRecord> records) {
    return Container(
      margin: EdgeInsets.only(bottom: 12.h),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16.r),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 8,
            offset: Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Заголовок дня
          Container(
            padding: EdgeInsets.all(12.w),
            decoration: BoxDecoration(
              color: _gradientColors[0].withOpacity(0.1),
              borderRadius: BorderRadius.vertical(top: Radius.circular(16.r)),
            ),
            child: Row(
              children: [
                Icon(Icons.calendar_today, size: 18, color: _gradientColors[0]),
                SizedBox(width: 8),
                Text(
                  date,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: _gradientColors[0],
                  ),
                ),
                Spacer(),
                Text(
                  '${records.length} ${_getEnding(records.length)}',
                  style: TextStyle(
                    color: Colors.grey[600],
                    fontSize: 12.sp,
                  ),
                ),
              ],
            ),
          ),
          // Записи
          ...records.map((record) => _buildRecordTile(record)),
        ],
      ),
    );
  }

  Widget _buildRecordTile(AttendanceRecord record) {
    final time = DateFormat('HH:mm').format(record.timestamp);
    final isOnTime = record.isOnTime == true;
    final isLate = record.isOnTime == false;
    final shiftLabel = _getShiftLabel(record.shiftType);

    return Container(
      padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 10.h),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: Colors.grey.shade200),
        ),
      ),
      child: Row(
        children: [
          // Иконка статуса
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: isOnTime
                  ? Colors.green.withOpacity(0.1)
                  : isLate
                      ? Colors.red.withOpacity(0.1)
                      : Colors.grey.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(
              isOnTime
                  ? Icons.check_circle
                  : isLate
                      ? Icons.warning_amber
                      : Icons.access_time,
              size: 20,
              color: isOnTime ? Colors.green : isLate ? Colors.red : Colors.grey,
            ),
          ),
          SizedBox(width: 12),
          // Информация
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  time,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15.sp,
                  ),
                ),
                if (shiftLabel.isNotEmpty)
                  Text(
                    shiftLabel,
                    style: TextStyle(
                      fontSize: 12.sp,
                      color: Colors.grey[600],
                    ),
                  ),
              ],
            ),
          ),
          // Статус
          if (isLate && record.lateMinutes != null)
            Container(
              padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 4.h),
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8.r),
              ),
              child: Text(
                '+${record.lateMinutes} мин',
                style: TextStyle(
                  color: Colors.red,
                  fontWeight: FontWeight.bold,
                  fontSize: 12.sp,
                ),
              ),
            )
          else if (isOnTime)
            Container(
              padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 4.h),
              decoration: BoxDecoration(
                color: Colors.green.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8.r),
              ),
              child: Text(
                'Вовремя',
                style: TextStyle(
                  color: Colors.green,
                  fontWeight: FontWeight.bold,
                  fontSize: 12.sp,
                ),
              ),
            ),
        ],
      ),
    );
  }

  String _getShiftLabel(String? shiftType) {
    switch (shiftType) {
      case 'morning':
        return 'Утренняя смена';
      case 'day':
        return 'Дневная смена';
      case 'night':
        return 'Ночная смена';
      default:
        return '';
    }
  }

  Color _getOnTimeColor(double rate) {
    if (rate >= 90) return Colors.green;
    if (rate >= 70) return Colors.orange;
    return Colors.red;
  }

  String _getEnding(int count) {
    if (count == 1) return 'отметка';
    if (count >= 2 && count <= 4) return 'отметки';
    return 'отметок';
  }
}
