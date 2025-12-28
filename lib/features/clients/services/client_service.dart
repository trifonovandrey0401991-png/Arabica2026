import 'package:http/http.dart' as http;
import 'dart:convert';
import '../models/client_model.dart';
import '../models/client_message_model.dart';
import 'core/utils/logger.dart';

class ClientService {
  static const String serverUrl = 'https://arabica26.ru';
  static const String baseUrl = '$serverUrl/api/clients';

  /// Получить список всех клиентов
  static Future<List<Client>> getClients() async {
    try {
      Logger.debug('📥 Загрузка списка клиентов с сервера...');
      Logger.debug('📥 URL: $baseUrl');
      
      final response = await http.get(
        Uri.parse(baseUrl),
      ).timeout(const Duration(seconds: 15));

      Logger.debug('📥 Response status: ${response.statusCode}');
      Logger.debug('📥 Response body length: ${response.body.length}');

      if (response.statusCode == 200) {
        final result = jsonDecode(response.body);
        Logger.debug('📥 Response keys: ${result.keys.join(", ")}');
        Logger.debug('📥 success: ${result['success']}');
        
        if (result['success'] == true) {
          final clientsJson = result['clients'];
          Logger.debug('📥 clients type: ${clientsJson.runtimeType}');
          
          if (clientsJson is List) {
            Logger.debug('📥 clients count: ${clientsJson.length}');
            final clients = clientsJson
                .map((json) {
                  try {
                    return Client.fromJson(json as Map<String, dynamic>);
                  } catch (e) {
                    Logger.error('❌ Ошибка парсинга клиента: $e, json: $json');
                    return null;
                  }
                })
                .whereType<Client>()
                .toList();
            Logger.debug('✅ Загружено клиентов: ${clients.length}');
            
            // Логируем первых несколько клиентов для отладки
            if (clients.isNotEmpty) {
              Logger.debug('📥 Первый клиент: ${clients[0].name} (${clients[0].phone})');
            }
            
            return clients;
          } else {
            Logger.error('❌ clients не является списком: ${clientsJson.runtimeType}');
            Logger.error('❌ clients value: $clientsJson');
            return [];
          }
        } else {
          Logger.error('❌ Ошибка загрузки клиентов: ${result['error']}');
          return [];
        }
      } else {
        Logger.error('❌ Ошибка API: statusCode=${response.statusCode}');
        Logger.error('❌ Response body: ${response.body.substring(0, 500)}');
        return [];
      }
    } catch (e, stackTrace) {
      Logger.error('❌ Ошибка загрузки клиентов: $e');
      Logger.error('❌ Stack trace: $stackTrace');
      return [];
    }
  }

  /// Получить переписку с клиентом
  static Future<List<ClientMessage>> getClientMessages(String clientPhone) async {
    try {
      Logger.debug('📥 Загрузка сообщений для клиента: $clientPhone');
      
      final response = await http.get(
        Uri.parse('$baseUrl/$clientPhone/messages'),
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final result = jsonDecode(response.body);
        if (result['success'] == true) {
          final messagesJson = result['messages'] as List<dynamic>;
          final messages = messagesJson
              .map((json) => ClientMessage.fromJson(json as Map<String, dynamic>))
              .toList();
          Logger.debug('✅ Загружено сообщений: ${messages.length}');
          return messages;
        } else {
          Logger.error('❌ Ошибка загрузки сообщений: ${result['error']}');
          return [];
        }
      } else {
        Logger.error('❌ Ошибка API: statusCode=${response.statusCode}');
        return [];
      }
    } catch (e) {
      Logger.error('❌ Ошибка загрузки сообщений: $e');
      return [];
    }
  }

  /// Отправить сообщение клиенту
  static Future<ClientMessage?> sendMessage({
    required String clientPhone,
    required String text,
    String? imageUrl,
    String? senderPhone,
  }) async {
    try {
      Logger.debug('📤 Отправка сообщения клиенту: $clientPhone');
      
      final requestBody = <String, dynamic>{
        'text': text,
        if (imageUrl != null) 'imageUrl': imageUrl,
        if (senderPhone != null) 'senderPhone': senderPhone,
      };
      
      final response = await http.post(
        Uri.parse('$baseUrl/$clientPhone/messages'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(requestBody),
      ).timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        final result = jsonDecode(response.body);
        if (result['success'] == true) {
          Logger.debug('✅ Сообщение отправлено');
          // Проверяем наличие поля message в ответе
          if (result['message'] != null && result['message'] is Map) {
            return ClientMessage.fromJson(result['message'] as Map<String, dynamic>);
          } else {
            // Если message не пришел, создаем сообщение из данных запроса
            return ClientMessage(
              id: 'temp_${DateTime.now().millisecondsSinceEpoch}',
              clientPhone: clientPhone,
              senderPhone: senderPhone ?? 'system',
              text: text,
              imageUrl: imageUrl,
              timestamp: DateTime.now().toIso8601String(),
              isRead: false,
            );
          }
        } else {
          Logger.error('❌ Ошибка отправки сообщения: ${result['error']}');
        }
      } else {
        Logger.error('❌ Ошибка API: statusCode=${response.statusCode}');
      }
      return null;
    } catch (e) {
      Logger.error('❌ Ошибка отправки сообщения: $e');
      return null;
    }
  }

  /// Отправить сообщение всем клиентам
  static Future<Map<String, dynamic>?> sendBroadcastMessage({
    required String text,
    String? imageUrl,
    String? senderPhone,
  }) async {
    try {
      Logger.debug('📤 Отправка сообщения всем клиентам');
      
      final requestBody = <String, dynamic>{
        'text': text,
        if (imageUrl != null) 'imageUrl': imageUrl,
        if (senderPhone != null) 'senderPhone': senderPhone,
      };
      
      final response = await http.post(
        Uri.parse('$baseUrl/messages/broadcast'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(requestBody),
      ).timeout(const Duration(seconds: 60));

      if (response.statusCode == 200) {
        final result = jsonDecode(response.body);
        if (result['success'] == true) {
          Logger.debug('✅ Сообщение отправлено ${result['sentCount']} клиентам');
          return {
            'sentCount': result['sentCount'] ?? 0,
            'totalClients': result['totalClients'] ?? 0,
          };
        } else {
          Logger.error('❌ Ошибка отправки сообщения: ${result['error']}');
        }
      } else {
        Logger.error('❌ Ошибка API: statusCode=${response.statusCode}');
      }
      return null;
    } catch (e) {
      Logger.error('❌ Ошибка отправки сообщения всем клиентам: $e');
      return null;
    }
  }

  /// Отметить сообщение как прочитанное
  static Future<bool> markMessageAsRead(String messageId) async {
    try {
      Logger.debug('📤 Отметка сообщения как прочитанного: $messageId');
      
      // TODO: Реализовать endpoint для отметки сообщения как прочитанного
      // Пока возвращаем true
      return true;
    } catch (e) {
      Logger.error('❌ Ошибка отметки сообщения: $e');
      return false;
    }
  }
}


