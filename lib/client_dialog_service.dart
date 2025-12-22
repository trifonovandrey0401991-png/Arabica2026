import 'package:http/http.dart' as http;
import 'dart:convert';
import 'client_dialog_model.dart';
import 'utils/logger.dart';

class ClientDialogService {
  static const String serverUrl = 'https://arabica26.ru';
  static const String baseUrl = '$serverUrl/api/client-dialogs';

  /// Получить все диалоги клиента
  static Future<List<ClientDialog>> getClientDialogs(String clientPhone) async {
    try {
      Logger.debug('📥 Загрузка диалогов клиента: $clientPhone');
      
      final response = await http.get(
        Uri.parse('$baseUrl/$clientPhone'),
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final result = jsonDecode(response.body);
        if (result['success'] == true) {
          final dialogsJson = result['dialogs'] as List<dynamic>;
          final dialogs = dialogsJson
              .map((json) => ClientDialog.fromJson(json as Map<String, dynamic>))
              .toList();
          Logger.debug('✅ Загружено диалогов: ${dialogs.length}');
          return dialogs;
        } else {
          Logger.error('❌ Ошибка загрузки диалогов: ${result['error']}');
        }
      } else {
        Logger.error('❌ Ошибка API: statusCode=${response.statusCode}');
      }
      return [];
    } catch (e) {
      Logger.error('❌ Ошибка загрузки диалогов: $e');
      return [];
    }
  }

  /// Получить диалог по магазину
  static Future<ClientDialog?> getShopDialog(String clientPhone, String shopAddress) async {
    try {
      Logger.debug('📥 Загрузка диалога: $clientPhone, магазин: $shopAddress');
      
      final encodedShopAddress = Uri.encodeComponent(shopAddress);
      final response = await http.get(
        Uri.parse('$baseUrl/$clientPhone/shop/$encodedShopAddress'),
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final result = jsonDecode(response.body);
        if (result['success'] == true) {
          final dialog = ClientDialog.fromJson(result['dialog'] as Map<String, dynamic>);
          Logger.debug('✅ Диалог загружен: ${dialog.messages.length} сообщений');
          return dialog;
        } else {
          Logger.error('❌ Ошибка загрузки диалога: ${result['error']}');
        }
      } else {
        Logger.error('❌ Ошибка API: statusCode=${response.statusCode}');
      }
      return null;
    } catch (e) {
      Logger.error('❌ Ошибка загрузки диалога: $e');
      return null;
    }
  }
}



