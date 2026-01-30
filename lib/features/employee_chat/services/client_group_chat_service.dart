import '../models/employee_chat_model.dart';
import 'employee_chat_service.dart';
import '../../../core/utils/logger.dart';

/// Сервис для получения групповых чатов клиента
/// Используется для показа групповых чатов в "Мои диалоги" для клиентов
class ClientGroupChatService {
  /// Получить только групповые чаты для клиента
  /// Фильтрует все чаты и возвращает только type == group
  static Future<List<EmployeeChat>> getClientGroupChats(String phone) async {
    try {
      Logger.debug('📥 Загрузка групповых чатов для клиента $phone...');
      final allChats = await EmployeeChatService.getChats(phone, isAdmin: false);
      // Фильтруем: только группы (не general, не shop, не private)
      final groups = allChats.where((chat) => chat.type == EmployeeChatType.group).toList();
      Logger.debug('✅ Найдено ${groups.length} групповых чатов для клиента');
      return groups;
    } catch (e) {
      Logger.error('Ошибка загрузки групповых чатов клиента', e);
      return [];
    }
  }

  /// Получить количество непрочитанных сообщений в группах
  static Future<int> getUnreadCount(String phone) async {
    try {
      final groups = await getClientGroupChats(phone);
      final unread = groups.fold(0, (sum, chat) => sum + chat.unreadCount);
      Logger.debug('📬 Непрочитанных в группах: $unread');
      return unread;
    } catch (e) {
      Logger.error('Ошибка подсчёта непрочитанных в группах', e);
      return 0;
    }
  }
}
