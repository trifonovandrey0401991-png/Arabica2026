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
  /// Получить общее количество непросмотренных/требующих внимания отчётов
  static Future<int> getTotalUnreadCount() async {
    try {
      int total = 0;

      // 1. Базовые отчёты (RKO, пересменки, сдача смены, пересчёты, приходы, тесты)
      try {
        final reportCounts = await ReportNotificationService.getUnviewedCounts();
        total += reportCounts.total;
      } catch (e) {
        Logger.error('Ошибка загрузки базовых счётчиков отчётов', e);
      }

      // 2. Выемки (неподтверждённые, с фильтрацией по магазинам)
      try {
        final allWithdrawals = await WithdrawalService.getWithdrawals();
        final withdrawals = await MultitenancyFilterService.filterByShopAddress(
          allWithdrawals,
          (w) => w.shopAddress,
        );
        total += withdrawals.where((w) => !w.confirmed).length;
      } catch (e) {
        Logger.error('Ошибка загрузки счётчика выемок', e);
      }

      // 3. Конверты (неподтверждённые, с фильтрацией по магазинам)
      try {
        final envelopes = await EnvelopeReportService.getReportsForCurrentUser();
        total += envelopes.where((r) => r.status != 'confirmed').length;
      } catch (e) {
        Logger.error('Ошибка загрузки счётчика конвертов', e);
      }

      // 4. Заявки на смены (непрочитанные)
      try {
        final requests = await ShiftTransferService.getAdminRequests();
        total += requests.where((r) => !r.isReadByAdmin).length;
      } catch (e) {
        Logger.error('Ошибка загрузки счётчика заявок на смены', e);
      }

      // 5. Отзывы (непрочитанные, с фильтрацией по магазинам)
      try {
        final allReviews = await ReviewService.getAllReviews();
        final reviews = await MultitenancyFilterService.filterByShopAddress(
          allReviews,
          (review) => review.shopAddress,
        );
        total += reviews.where((r) => r.hasUnreadFromClient).length;
      } catch (e) {
        Logger.error('Ошибка загрузки счётчика отзывов', e);
      }

      // 6. Сообщения руководству (непрочитанные)
      try {
        final result = await BaseHttpService.getRaw(
          endpoint: '/api/management-dialogs',
          timeout: ApiConstants.longTimeout,
        );
        if (result != null && result['success'] == true) {
          total += (result['totalUnread'] ?? 0) as int;
        }
      } catch (e) {
        Logger.error('Ошибка загрузки счётчика сообщений руководству', e);
      }

      // 7. Поиск товаров (непросмотренные админом, с фильтрацией по магазинам)
      try {
        final allCounts = await ProductQuestionService.getUnviewedByAdminCounts();
        final allowedAddresses = await MultitenancyFilterService.getAllowedShopAddresses();
        if (allowedAddresses == null) {
          // Developer видит всё
          total += allCounts.values.fold(0, (sum, count) => sum + count);
        } else {
          // Управляющий видит только свои магазины
          for (final entry in allCounts.entries) {
            if (allowedAddresses.contains(entry.key)) {
              total += entry.value;
            }
          }
        }
      } catch (e) {
        Logger.error('Ошибка загрузки счётчика вопросов о товарах', e);
      }

      // 8. Задачи (просроченные непросмотренные)
      try {
        final count = await TaskService.getUnviewedExpiredCount();
        total += count;
      } catch (e) {
        Logger.error('Ошибка загрузки счётчика задач', e);
      }

      // 9. Заявки на работу (непросмотренные)
      try {
        final count = await JobApplicationService.getUnviewedCount();
        total += count;
      } catch (e) {
        Logger.error('Ошибка загрузки счётчика заявок на работу', e);
      }

      // 10. Приглашения (непросмотренные)
      try {
        final count = await ReferralService.getUnviewedCount();
        total += count;
      } catch (e) {
        Logger.error('Ошибка загрузки счётчика приглашений', e);
      }

      // 11. Заказы клиентов (непросмотренные)
      try {
        final counts = await OrderService.getUnviewedCounts();
        total += counts['total'] ?? 0;
      } catch (e) {
        Logger.error('Ошибка загрузки счётчика заказов', e);
      }

      // 12. Счётчик кофемашин (неподтверждённые)
      try {
        final count = await CoffeeMachineReportService.getUnconfirmedCountForCurrentUser();
        total += count;
      } catch (e) {
        Logger.error('Ошибка загрузки счётчика кофемашин', e);
      }

      Logger.debug('Общий счётчик "Отчёты": $total');
      return total;
    } catch (e) {
      Logger.error('Ошибка получения общего счётчика отчётов', e);
      return 0;
    }
  }
}
