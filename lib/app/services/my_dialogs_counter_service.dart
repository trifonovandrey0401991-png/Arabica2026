import 'package:shared_preferences/shared_preferences.dart';
import '../../features/clients/services/network_message_service.dart';
import '../../features/clients/services/management_message_service.dart';
import '../../features/reviews/services/review_service.dart';
import '../../features/product_questions/services/product_question_service.dart';
import '../../core/utils/logger.dart';

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

      int total = 0;

      // Сетевые сообщения
      try {
        final networkData = await NetworkMessageService.getNetworkMessages(phone);
        total += networkData.unreadCount;
      } catch (e) {
        Logger.error('Ошибка загрузки сетевых сообщений для счётчика', e);
      }

      // Сообщения руководству
      try {
        final managementData = await ManagementMessageService.getManagementMessages(phone);
        total += managementData.unreadCount;
      } catch (e) {
        Logger.error('Ошибка загрузки сообщений руководству для счётчика', e);
      }

      // Отзывы
      try {
        final reviews = await ReviewService.getClientReviews(phone);
        for (final review in reviews) {
          total += review.getUnreadCountForClient();
        }
      } catch (e) {
        Logger.error('Ошибка загрузки отзывов для счётчика', e);
      }

      // Поиск товара (общий)
      try {
        final productQuestionData = await ProductQuestionService.getClientDialog(phone);
        if (productQuestionData != null) {
          total += productQuestionData.unreadCount;
        }
      } catch (e) {
        Logger.error('Ошибка загрузки вопросов для счётчика', e);
      }

      // Персональные диалоги "Поиск Товара"
      try {
        final personalDialogs = await ProductQuestionService.getClientPersonalDialogs(phone);
        for (final dialog in personalDialogs) {
          if (dialog.hasUnreadFromEmployee) {
            total += 1;
          }
        }
      } catch (e) {
        Logger.error('Ошибка загрузки персональных диалогов для счётчика', e);
      }

      Logger.debug('Общий счётчик "Мои диалоги": $total');
      return total;
    } catch (e) {
      Logger.error('Ошибка получения общего счётчика диалогов', e);
      return 0;
    }
  }
}
