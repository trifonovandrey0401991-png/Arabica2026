import '../../core/services/report_notification_service.dart';
import '../../core/services/base_http_service.dart';
import '../../core/constants/api_constants.dart';
import '../../core/utils/logger.dart';
import '../../core/services/multitenancy_filter_service.dart';
import '../../features/main_cash/services/withdrawal_service.dart';
import '../../features/envelope/services/envelope_report_service.dart';
import '../../features/work_schedule/services/shift_transfer_service.dart';
import '../../features/reviews/services/review_service.dart';
import '../../features/product_questions/services/product_question_service.dart';
import '../../features/tasks/services/task_service.dart';
import '../../features/job_application/services/job_application_service.dart';
import '../../features/referrals/services/referral_service.dart';
import '../../features/orders/services/order_service.dart';
import '../../features/coffee_machine/services/coffee_machine_report_service.dart';

/// Сервис для получения общего количества непросмотренных отчётов
/// (для иерархического бейджа "Отчёты" в главном меню админа)
class ReportsCounterService {
  /// Получить общее количество непросмотренных/требующих внимания отчётов.
  /// Все 12 категорий загружаются параллельно для максимальной скорости.
  static Future<int> getTotalUnreadCount() async {
    try {
      // Запускаем все 12 категорий параллельно — каждая возвращает свой счётчик
      final results = await Future.wait<int>([
        // 1. Базовые отчёты (RKO, пересменки, сдача смены, пересчёты, приходы, тесты)
        _safeCount(() async {
          final reportCounts = await ReportNotificationService.getUnviewedCounts();
          return reportCounts.total;
        }, 'базовых счётчиков отчётов'),

        // 2. Выемки (неподтверждённые, с фильтрацией по магазинам)
        _safeCount(() async {
          final allWithdrawals = await WithdrawalService.getWithdrawals();
          final withdrawals = await MultitenancyFilterService.filterByShopAddress(
            allWithdrawals,
            (w) => w.shopAddress,
          );
          return withdrawals.where((w) => !w.confirmed).length;
        }, 'счётчика выемок'),

        // 3. Конверты (неподтверждённые, с фильтрацией по магазинам)
        _safeCount(() async {
          final envelopes = await EnvelopeReportService.getReportsForCurrentUser();
          return envelopes.where((r) => r.status != 'confirmed').length;
        }, 'счётчика конвертов'),

        // 4. Заявки на смены (непрочитанные)
        _safeCount(() async {
          final requests = await ShiftTransferService.getAdminRequests();
          return requests.where((r) => !r.isReadByAdmin).length;
        }, 'счётчика заявок на смены'),

        // 5. Отзывы (непрочитанные, с фильтрацией по магазинам)
        _safeCount(() async {
          final allReviews = await ReviewService.getAllReviews();
          final reviews = await MultitenancyFilterService.filterByShopAddress(
            allReviews,
            (review) => review.shopAddress,
          );
          return reviews.where((r) => r.hasUnreadFromClient).length;
        }, 'счётчика отзывов'),

        // 6. Сообщения руководству (непрочитанные)
        _safeCount(() async {
          final result = await BaseHttpService.getRaw(
            endpoint: '/api/management-dialogs',
            timeout: ApiConstants.longTimeout,
          );
          if (result != null && result['success'] == true) {
            return (result['totalUnread'] ?? 0) as int;
          }
          return 0;
        }, 'счётчика сообщений руководству'),

        // 7. Поиск товаров (непросмотренные админом, с фильтрацией по магазинам)
        _safeCount(() async {
          final allCounts = await ProductQuestionService.getUnviewedByAdminCounts();
          final allowedAddresses = await MultitenancyFilterService.getAllowedShopAddresses();
          if (allowedAddresses == null) {
            return allCounts.values.fold<int>(0, (sum, count) => sum + count);
          } else {
            int count = 0;
            for (final entry in allCounts.entries) {
              if (allowedAddresses.contains(entry.key)) {
                count += entry.value;
              }
            }
            return count;
          }
        }, 'счётчика вопросов о товарах'),

        // 8. Задачи (просроченные непросмотренные)
        _safeCount(() => TaskService.getUnviewedExpiredCount(), 'счётчика задач'),

        // 9. Заявки на работу (непросмотренные)
        _safeCount(() => JobApplicationService.getUnviewedCount(), 'счётчика заявок на работу'),

        // 10. Приглашения (непросмотренные)
        _safeCount(() => ReferralService.getUnviewedCount(), 'счётчика приглашений'),

        // 11. Заказы клиентов (непросмотренные)
        _safeCount(() async {
          final counts = await OrderService.getUnviewedCounts();
          return counts['total'] ?? 0;
        }, 'счётчика заказов'),

        // 12. Счётчик кофемашин (неподтверждённые)
        _safeCount(
          () => CoffeeMachineReportService.getUnconfirmedCountForCurrentUser(),
          'счётчика кофемашин',
        ),
      ]);

      final total = results.fold(0, (sum, count) => sum + count);
      Logger.debug('Общий счётчик "Отчёты": $total');
      return total;
    } catch (e) {
      Logger.error('Ошибка получения общего счётчика отчётов', e);
      return 0;
    }
  }

  /// Безопасно выполняет функцию подсчёта — при ошибке возвращает 0
  static Future<int> _safeCount(Future<int> Function() fn, String label) async {
    try {
      return await fn();
    } catch (e) {
      Logger.error('Ошибка загрузки $label', e);
      return 0;
    }
  }
}
