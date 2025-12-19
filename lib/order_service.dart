import 'package:http/http.dart' as http;
import 'dart:convert';
import 'order_provider.dart';
import 'utils/logger.dart';

class OrderService {
  static const String serverUrl = 'https://arabica26.ru';
  static const String baseUrl = '$serverUrl/api/orders';

  /// Создать заказ на сервере
  static Future<Order?> createOrder({
    required String clientPhone,
    required String clientName,
    required String shopAddress,
    required List<CartItem> items,
    required double totalPrice,
    String? comment,
  }) async {
    try {
      Logger.debug('📤 Создание заказа: $clientName, магазин: $shopAddress');
      
      final itemsJson = items.map((item) => {
        'name': item.menuItem.name,
        'price': item.menuItem.price,
        'quantity': item.quantity,
        'total': item.totalPrice,
      }).toList();
      
      final requestBody = {
        'clientPhone': clientPhone,
        'clientName': clientName,
        'shopAddress': shopAddress,
        'items': itemsJson,
        'totalPrice': totalPrice,
        if (comment != null && comment.isNotEmpty) 'comment': comment,
      };
      
      final response = await http.post(
        Uri.parse(baseUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(requestBody),
      ).timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        final result = jsonDecode(response.body);
        if (result['success'] == true) {
          Logger.debug('✅ Заказ создан: ${result['order']['id']}');
          // Возвращаем упрощенный Order (без полного восстановления CartItem)
          final orderData = result['order'];
          return Order(
            id: orderData['id'],
            items: [], // Упрощенная версия
            totalPrice: (orderData['totalPrice'] as num).toDouble(),
            createdAt: DateTime.parse(orderData['createdAt']),
            comment: orderData['comment'] as String?,
            status: orderData['status'] ?? 'pending',
            acceptedBy: orderData['acceptedBy'] as String?,
            rejectedBy: orderData['rejectedBy'] as String?,
            rejectionReason: orderData['rejectionReason'] as String?,
          );
        } else {
          Logger.error('❌ Ошибка создания заказа: ${result['error']}');
        }
      } else {
        Logger.error('❌ Ошибка API: statusCode=${response.statusCode}');
      }
      return null;
    } catch (e) {
      Logger.error('❌ Ошибка создания заказа: $e');
      return null;
    }
  }

  /// Получить заказы клиента
  static Future<List<Map<String, dynamic>>> getClientOrders(String clientPhone) async {
    try {
      Logger.debug('📥 Загрузка заказов клиента: $clientPhone');
      
      final response = await http.get(
        Uri.parse('$baseUrl?clientPhone=$clientPhone'),
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final result = jsonDecode(response.body);
        if (result['success'] == true) {
          final ordersJson = result['orders'] as List<dynamic>;
          Logger.debug('✅ Загружено заказов: ${ordersJson.length}');
          return ordersJson.map((o) => o as Map<String, dynamic>).toList();
        } else {
          Logger.error('❌ Ошибка загрузки заказов: ${result['error']}');
        }
      } else {
        Logger.error('❌ Ошибка API: statusCode=${response.statusCode}');
      }
      return [];
    } catch (e) {
      Logger.error('❌ Ошибка загрузки заказов: $e');
      return [];
    }
  }

  /// Обновить статус заказа
  static Future<bool> updateOrderStatus({
    required String orderId,
    String? status,
    String? acceptedBy,
    String? rejectedBy,
    String? rejectionReason,
  }) async {
    try {
      Logger.debug('📤 Обновление статуса заказа: $orderId');
      
      final requestBody = <String, dynamic>{};
      if (status != null) requestBody['status'] = status;
      if (acceptedBy != null) requestBody['acceptedBy'] = acceptedBy;
      if (rejectedBy != null) requestBody['rejectedBy'] = rejectedBy;
      if (rejectionReason != null) requestBody['rejectionReason'] = rejectionReason;
      
      final response = await http.patch(
        Uri.parse('$baseUrl/$orderId'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(requestBody),
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final result = jsonDecode(response.body);
        if (result['success'] == true) {
          Logger.debug('✅ Статус заказа обновлен');
          return true;
        } else {
          Logger.error('❌ Ошибка обновления заказа: ${result['error']}');
        }
      } else {
        Logger.error('❌ Ошибка API: statusCode=${response.statusCode}');
      }
      return false;
    } catch (e) {
      Logger.error('❌ Ошибка обновления статуса заказа: $e');
      return false;
    }
  }
}

