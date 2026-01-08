import '../models/shop_cash_balance_model.dart';
import '../../envelope/services/envelope_report_service.dart';
import '../../../core/utils/logger.dart';

class TurnoverService {
  /// Получить оборот за месяц по дням
  static Future<List<DayTurnover>> getMonthTurnover(
    String shopAddress,
    int year,
    int month,
  ) async {
    try {
      Logger.debug('Загрузка оборота за $month/$year для $shopAddress');

      // Определяем диапазон дат
      final firstDay = DateTime(year, month, 1);
      final lastDay = DateTime(year, month + 1, 0); // Последний день месяца

      // Загружаем отчеты за период
      final reports = await EnvelopeReportService.getReports(
        shopAddress: shopAddress,
        fromDate: firstDay,
        toDate: lastDay.add(const Duration(days: 1)), // Включаем последний день
      );

      Logger.debug('Загружено отчетов за период: ${reports.length}');

      // Группируем по дням
      final turnoverByDay = <String, DayTurnover>{};

      for (final report in reports) {
        final dateKey = '${report.createdAt.year}-'
            '${report.createdAt.month.toString().padLeft(2, '0')}-'
            '${report.createdAt.day.toString().padLeft(2, '0')}';

        final date = DateTime(
          report.createdAt.year,
          report.createdAt.month,
          report.createdAt.day,
        );

        if (turnoverByDay.containsKey(dateKey)) {
          final existing = turnoverByDay[dateKey]!;
          turnoverByDay[dateKey] = DayTurnover(
            date: date,
            oooRevenue: existing.oooRevenue + report.oooRevenue,
            ipRevenue: existing.ipRevenue + report.ipRevenue,
          );
        } else {
          turnoverByDay[dateKey] = DayTurnover(
            date: date,
            oooRevenue: report.oooRevenue,
            ipRevenue: report.ipRevenue,
          );
        }
      }

      // Преобразуем в список и сортируем по дате
      final result = turnoverByDay.values.toList();
      result.sort((a, b) => a.date.compareTo(b.date));

      Logger.debug('Сформировано дней с оборотом: ${result.length}');
      return result;
    } catch (e) {
      Logger.error('Ошибка загрузки оборота', e);
      return [];
    }
  }

  /// Получить оборот за конкретный день
  static Future<DayTurnover?> getDayTurnover(
    String shopAddress,
    DateTime date,
  ) async {
    try {
      final startOfDay = DateTime(date.year, date.month, date.day);
      final endOfDay = startOfDay.add(const Duration(days: 1));

      final reports = await EnvelopeReportService.getReports(
        shopAddress: shopAddress,
        fromDate: startOfDay,
        toDate: endOfDay,
      );

      if (reports.isEmpty) {
        return DayTurnover(
          date: startOfDay,
          oooRevenue: 0,
          ipRevenue: 0,
        );
      }

      double oooRevenue = 0;
      double ipRevenue = 0;

      for (final report in reports) {
        oooRevenue += report.oooRevenue;
        ipRevenue += report.ipRevenue;
      }

      return DayTurnover(
        date: startOfDay,
        oooRevenue: oooRevenue,
        ipRevenue: ipRevenue,
      );
    } catch (e) {
      Logger.error('Ошибка загрузки оборота за день', e);
      return null;
    }
  }

  /// Получить сравнение с прошлой неделей и прошлым месяцем
  static Future<TurnoverComparison?> getDayComparison(
    String shopAddress,
    DateTime date,
  ) async {
    try {
      Logger.debug('Загрузка сравнения для ${date.day}.${date.month}.${date.year}');

      // Текущий день
      final current = await getDayTurnover(shopAddress, date);
      if (current == null) return null;

      // Неделя назад (тот же день недели)
      final weekAgoDate = date.subtract(const Duration(days: 7));
      final weekAgo = await getDayTurnover(shopAddress, weekAgoDate);

      // Месяц назад (та же дата)
      final monthAgoDate = DateTime(date.year, date.month - 1, date.day);
      final monthAgo = await getDayTurnover(shopAddress, monthAgoDate);

      return TurnoverComparison(
        current: current,
        weekAgo: weekAgo,
        monthAgo: monthAgo,
      );
    } catch (e) {
      Logger.error('Ошибка загрузки сравнения', e);
      return null;
    }
  }

  /// Получить общий оборот за месяц
  static Future<Map<String, double>> getMonthTotal(
    String shopAddress,
    int year,
    int month,
  ) async {
    try {
      final turnover = await getMonthTurnover(shopAddress, year, month);

      double oooTotal = 0;
      double ipTotal = 0;

      for (final day in turnover) {
        oooTotal += day.oooRevenue;
        ipTotal += day.ipRevenue;
      }

      return {
        'ooo': oooTotal,
        'ip': ipTotal,
        'total': oooTotal + ipTotal,
      };
    } catch (e) {
      Logger.error('Ошибка расчета общего оборота', e);
      return {'ooo': 0, 'ip': 0, 'total': 0};
    }
  }
}
