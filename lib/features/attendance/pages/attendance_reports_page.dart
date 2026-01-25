import 'package:flutter/material.dart';
import '../models/shop_attendance_summary.dart';
import '../services/attendance_report_service.dart';
import '../../../core/services/report_notification_service.dart';
import 'attendance_month_page.dart';

/// Страница отчётов по приходам с группировкой по магазинам
class AttendanceReportsPage extends StatefulWidget {
  const AttendanceReportsPage({super.key});

  @override
  State<AttendanceReportsPage> createState() => _AttendanceReportsPageState();
}

class _AttendanceReportsPageState extends State<AttendanceReportsPage> {
  List<ShopAttendanceSummary> _shopsSummary = [];
  bool _isLoading = true;
  String? _error;
  final Set<String> _expandedShops = {};

  @override
  void initState() {
    super.initState();
    _loadData();
    // Отмечаем все уведомления этого типа как просмотренные
    ReportNotificationService.markAllAsViewed(reportType: ReportType.attendance);
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final summary = await AttendanceReportService.getShopsSummary();
      if (mounted) {
        setState(() {
          _shopsSummary = summary;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Отчеты по приходам'),
        backgroundColor: const Color(0xFF004D40),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadData,
            tooltip: 'Обновить',
          ),
        ],
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF004D40), Color(0xFF00695C)],
          ),
        ),
        child: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.white),
      );
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, color: Colors.white, size: 48),
            const SizedBox(height: 16),
            const Text(
              'Ошибка загрузки',
              style: TextStyle(color: Colors.white, fontSize: 18),
            ),
            const SizedBox(height: 8),
            Text(
              _error!,
              style: const TextStyle(color: Colors.white70, fontSize: 14),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _loadData,
              icon: const Icon(Icons.refresh),
              label: const Text('Повторить'),
            ),
          ],
        ),
      );
    }

    if (_shopsSummary.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.store, color: Colors.white54, size: 64),
            SizedBox(height: 16),
            Text(
              'Нет данных о магазинах',
              style: TextStyle(color: Colors.white, fontSize: 18),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadData,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _shopsSummary.length,
        itemBuilder: (context, index) {
          return _buildShopCard(_shopsSummary[index]);
        },
      ),
    );
  }

  Widget _buildShopCard(ShopAttendanceSummary summary) {
    final isExpanded = _expandedShops.contains(summary.shopAddress);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Column(
        children: [
          // Уровень 1: Заголовок магазина
          ListTile(
            leading: CircleAvatar(
              backgroundColor: summary.isTodayComplete
                  ? Colors.green
                  : summary.todayAttendanceCount > 0
                      ? Colors.orange
                      : Colors.red.shade300,
              child: const Icon(Icons.store, color: Colors.white),
            ),
            title: Text(
              summary.shopAddress,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: summary.isTodayComplete
                          ? Colors.green.withOpacity(0.1)
                          : summary.todayAttendanceCount > 0
                              ? Colors.orange.withOpacity(0.1)
                              : Colors.red.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: summary.isTodayComplete
                            ? Colors.green
                            : summary.todayAttendanceCount > 0
                                ? Colors.orange
                                : Colors.red.shade300,
                      ),
                    ),
                    child: Text(
                      'Сегодня: ${summary.todayAttendanceCount} ${_getEnding(summary.todayAttendanceCount)}',
                      style: TextStyle(
                        color: summary.isTodayComplete
                            ? Colors.green
                            : summary.todayAttendanceCount > 0
                                ? Colors.orange
                                : Colors.red,
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Процент приходов вовремя
                  if (summary.totalRecords > 0)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: _getOnTimeColor(summary.onTimeRate).withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: _getOnTimeColor(summary.onTimeRate),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.timer_outlined,
                            size: 12,
                            color: _getOnTimeColor(summary.onTimeRate),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '${summary.onTimeRate.toStringAsFixed(0)}%',
                            style: TextStyle(
                              color: _getOnTimeColor(summary.onTimeRate),
                              fontWeight: FontWeight.w600,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            trailing: Icon(
              isExpanded ? Icons.expand_less : Icons.expand_more,
              color: const Color(0xFF004D40),
            ),
            onTap: () {
              setState(() {
                if (isExpanded) {
                  _expandedShops.remove(summary.shopAddress);
                } else {
                  _expandedShops.add(summary.shopAddress);
                }
              });
            },
          ),

          // Уровень 2: Месяцы (показываются при раскрытии)
          if (isExpanded) ...[
            const Divider(height: 1),
            _buildMonthTile(
              'Текущий месяц',
              summary.currentMonth,
              summary.shopAddress,
            ),
            const Divider(height: 1, indent: 56),
            _buildMonthTile(
              'Прошлый месяц',
              summary.previousMonth,
              summary.shopAddress,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildMonthTile(
    String label,
    MonthAttendanceSummary month,
    String shopAddress,
  ) {
    final statusColor = _getStatusColor(month.status);
    final percentage = (month.completionRate * 100).toStringAsFixed(0);

    return ListTile(
      contentPadding: const EdgeInsets.only(left: 56, right: 16),
      leading: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: statusColor.withOpacity(0.1),
          shape: BoxShape.circle,
          border: Border.all(color: statusColor, width: 2),
        ),
        child: Center(
          child: Text(
            '$percentage%',
            style: TextStyle(
              color: statusColor,
              fontWeight: FontWeight.bold,
              fontSize: 10,
            ),
          ),
        ),
      ),
      title: Text(
        '$label: ${month.actualCount}/${month.plannedCount}',
        style: const TextStyle(fontWeight: FontWeight.w500),
      ),
      subtitle: Text(
        '${month.displayName} ${month.year}',
        style: const TextStyle(fontSize: 12, color: Colors.grey),
      ),
      trailing: const Icon(Icons.chevron_right),
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => AttendanceMonthPage(
              shopAddress: shopAddress,
              monthSummary: month,
            ),
          ),
        );
      },
    );
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'good':
        return Colors.green;
      case 'warning':
        return Colors.orange;
      default:
        return Colors.red;
    }
  }

  /// Цвет для процента приходов вовремя
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
