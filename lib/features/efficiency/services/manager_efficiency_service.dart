import '../../../core/services/base_http_service.dart';
import '../../../core/utils/logger.dart';
import '../models/manager_efficiency_model.dart';

/// Сервис для загрузки эффективности управляющего (admin)
///
/// Эффективность состоит из двух компонентов:
/// - Эффективность магазинов (50%) - агрегация баллов сотрудников
/// - Эффективность отчётов (50%) - баллы за проверку отчётов + задачи
class ManagerEfficiencyService {
  static const String _baseEndpoint = '/api/manager-efficiency';

  /// Загрузить эффективность управляющего за указанный месяц
  ///
  /// [phone] - телефон управляющего
  /// [month] - месяц в формате YYYY-MM (например, "2026-02")
  static Future<ManagerEfficiencyData?> getManagerEfficiency({
    required String phone,
    required String month,
  }) async {
    Logger.debug('Fetching manager efficiency for $phone, month: $month');

    try {
      final result = await BaseHttpService.get<ManagerEfficiencyData>(
        endpoint: '$_baseEndpoint?phone=$phone&month=$month',
        fromJson: (json) => ManagerEfficiencyData.fromJson(json),
        itemKey: 'data',
      );

      return result;
    } catch (e) {
      Logger.error('Error fetching manager efficiency: $e');
      return null;
    }
  }

  /// Загрузить эффективность управляющего за текущий и прошлый месяц
  /// для сравнения
  static Future<ManagerEfficiencyData?> getManagerEfficiencyWithComparison({
    required String phone,
    required String currentMonth,
  }) async {
    Logger.debug('Fetching manager efficiency with comparison for $phone');

    try {
      // Вычисляем прошлый месяц
      final parts = currentMonth.split('-');
      final year = int.parse(parts[0]);
      final month = int.parse(parts[1]);

      DateTime previousDate;
      if (month == 1) {
        previousDate = DateTime(year - 1, 12, 1);
      } else {
        previousDate = DateTime(year, month - 1, 1);
      }

      final previousMonth =
          '${previousDate.year}-${previousDate.month.toString().padLeft(2, '0')}';

      // Загружаем оба месяца параллельно
      final results = await Future.wait([
        getManagerEfficiency(phone: phone, month: currentMonth),
        getManagerEfficiency(phone: phone, month: previousMonth),
      ]);

      final current = results[0];
      final previous = results[1];

      if (current == null) {
        return ManagerEfficiencyData.empty();
      }

      // Если нет данных за прошлый месяц, возвращаем текущие без сравнения
      if (previous == null) {
        return current;
      }

      // Добавляем сравнение к текущим данным
      final comparison = PreviousMonthComparison(
        totalChange: current.totalPercentage - previous.totalPercentage,
        shopEfficiencyChange:
            current.shopEfficiencyPercentage - previous.shopEfficiencyPercentage,
        reviewEfficiencyChange:
            current.reviewEfficiencyPercentage - previous.reviewEfficiencyPercentage,
      );

      // Добавляем изменения по магазинам
      final shopBreakdownWithChanges = current.shopBreakdown.map((shop) {
        final previousShop = previous.shopBreakdown.firstWhere(
          (s) => s.shopId == shop.shopId,
          orElse: () => ShopEfficiencyItem(
            shopId: shop.shopId,
            shopName: shop.shopName,
            totalPoints: 0,
            percentage: 0,
          ),
        );

        return ShopEfficiencyItem(
          shopId: shop.shopId,
          shopName: shop.shopName,
          totalPoints: shop.totalPoints,
          percentage: shop.percentage,
          previousMonthChange: shop.totalPoints - previousShop.totalPoints,
        );
      }).toList();

      // Добавляем изменения по категориям
      final categoryBreakdownWithChanges = CategoryBreakdown(
        shiftPoints: current.categoryBreakdown.shiftPoints,
        recountPoints: current.categoryBreakdown.recountPoints,
        shiftHandoverPoints: current.categoryBreakdown.shiftHandoverPoints,
        tasksPoints: current.categoryBreakdown.tasksPoints,
        shiftChange: current.categoryBreakdown.shiftPoints -
            previous.categoryBreakdown.shiftPoints,
        recountChange: current.categoryBreakdown.recountPoints -
            previous.categoryBreakdown.recountPoints,
        shiftHandoverChange: current.categoryBreakdown.shiftHandoverPoints -
            previous.categoryBreakdown.shiftHandoverPoints,
        tasksChange: current.categoryBreakdown.tasksPoints -
            previous.categoryBreakdown.tasksPoints,
      );

      return ManagerEfficiencyData(
        totalPercentage: current.totalPercentage,
        shopEfficiencyPercentage: current.shopEfficiencyPercentage,
        reviewEfficiencyPercentage: current.reviewEfficiencyPercentage,
        shopBreakdown: shopBreakdownWithChanges,
        categoryBreakdown: categoryBreakdownWithChanges,
        comparison: comparison,
      );
    } catch (e) {
      Logger.error('Error fetching manager efficiency with comparison: $e');
      return null;
    }
  }

  /// Получить текущий месяц в формате YYYY-MM
  static String getCurrentMonth() {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}';
  }
}
