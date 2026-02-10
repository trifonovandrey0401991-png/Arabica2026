import 'package:shared_preferences/shared_preferences.dart';
import '../../features/clients/services/network_message_service.dart';
import '../../features/clients/services/management_message_service.dart';
import '../../features/reviews/services/review_service.dart';
import '../../features/product_questions/services/product_question_service.dart';
import '../../core/utils/logger.dart';
import '../../features/employee_chat/services/client_group_chat_service.dart';

/// Сервис для получения общего количества непрочитанных сообщений в "Мои диалоги"
class MyDialogsCounterService {
  /// Получить общее количество непрочитанных сообщений для клиента
  static Future<int> getTotalUnreadCount() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final phone = prefs.getString('user_phone') ?? '';

      if (phone.isEmpty) {
        return 0;
      }

      // Запускаем все 6 запросов ПАРАЛЛЕЛЬНО (было последовательно)
      final results = await Future.wait<int>([
        // Сетевые сообщения
        NetworkMessageService.getNetworkMessages(phone)
            .then((data) => data.unreadCount)
            .catchError((e) {
          Logger.error('Ошибка загрузки сетевых сообщений для счётчика', e);
          return 0;
        }),
        // Сообщения руководству
        ManagementMessageService.getManagementMessages(phone)
            .then((data) => data.unreadCount)
            .catchError((e) {
          Logger.error('Ошибка загрузки сообщений руководству для счётчика', e);
          return 0;
        }),
        // Отзывы
        ReviewService.getClientReviews(phone).then((reviews) {
          int count = 0;
          for (final review in reviews) {
            count += review.getUnreadCountForClient();
          }
          return count;
        }).catchError((e) {
          Logger.error('Ошибка загрузки отзывов для счётчика', e);
          return 0;
        }),
        // Поиск товара (общий)
        ProductQuestionService.getClientDialog(phone)
            .then((data) => data?.unreadCount ?? 0)
            .catchError((e) {
          Logger.error('Ошибка загрузки вопросов для счётчика', e);
          return 0;
        }),
        // Персональные диалоги "Поиск Товара"
        ProductQuestionService.getClientPersonalDialogs(phone).then((dialogs) {
          int count = 0;
          for (final dialog in dialogs) {
            if (dialog.hasUnreadFromEmployee) count += 1;
          }
          return count;
        }).catchError((e) {
          Logger.error('Ошибка загрузки персональных диалогов для счётчика', e);
          return 0;
        }),
        // Групповые чаты
        ClientGroupChatService.getUnreadCount(phone).catchError((e) {
          Logger.error('Ошибка загрузки групповых чатов для счётчика', e);
          return 0;
        }),
      ]);

      final total = results.fold<int>(0, (sum, count) => sum + count);
      Logger.debug('Общий счётчик "Мои диалоги": $total');
      return total;
    } catch (e) {
      Logger.error('Ошибка получения общего счётчика диалогов', e);
      return 0;
    }
  }
}
