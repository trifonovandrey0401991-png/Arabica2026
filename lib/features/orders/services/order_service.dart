import 'package:http/http.dart' as http;
import 'dart:convert';
import '../../../shared/providers/order_provider.dart';
import '../../../shared/providers/cart_provider.dart';
import '../../../core/constants/api_constants.dart';
import '../../../core/utils/logger.dart';

class OrderService {
  static const String baseEndpoint = '/api/orders';

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
        'photoId': item.menuItem.photoId,
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
        Uri.parse('${ApiConstants.serverUrl}$baseEndpoint'),
        headers: ApiConstants.jsonHeaders,
        body: jsonEncode(requestBody),
      ).timeout(ApiConstants.longTimeout);

      if (response.statusCode == 200) {
        final result = jsonDecode(response.body);
        if (result['success'] == true) {
          Logger.debug('✅ Заказ создан: ${result['order']['id']}');
          // Возвращаем упрощенный Order (без полного восстановления CartItem)
          final orderData = result['order'];
          final itemsList = orderData['items'] as List<dynamic>?;
          final itemsData = itemsList?.map((item) => item as Map<String, dynamic>).toList();

          return Order(
            id: orderData['id'],
            items: [], // Упрощенная версия
            itemsData: itemsData,
            totalPrice: (orderData['totalPrice'] as num).toDouble(),
            createdAt: DateTime.parse(orderData['createdAt']),
            comment: orderData['comment'] as String?,
            status: orderData['status'] ?? 'pending',
            acceptedBy: orderData['acceptedBy'] as String?,
            rejectedBy: orderData['rejectedBy'] as String?,
            rejectionReason: orderData['rejectionReason'] as String?,
            orderNumber: orderData['orderNumber'] as int?,
            clientPhone: orderData['clientPhone'] as String?,
            clientName: orderData['clientName'] as String?,
            shopAddress: orderData['shopAddress'] as String?,
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

      final uri = Uri.parse('${ApiConstants.serverUrl}$baseEndpoint')
          .replace(queryParameters: {'clientPhone': clientPhone});

      final response = await http.get(uri).timeout(ApiConstants.defaultTimeout);

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

  /// Получить все заказы (для сотрудников)
  static Future<List<Map<String, dynamic>>> getAllOrders({String? status}) async {
    try {
      Logger.debug('📥 Загрузка всех заказов${status != null ? ' со статусом: $status' : ''}');

      final queryParams = <String, String>{};
      if (status != null) {
        queryParams['status'] = status;
      }

      final uri = Uri.parse('${ApiConstants.serverUrl}$baseEndpoint')
          .replace(queryParameters: queryParams.isNotEmpty ? queryParams : null);

      final response = await http.get(uri).timeout(ApiConstants.defaultTimeout);

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
        Uri.parse('${ApiConstants.serverUrl}$baseEndpoint/$orderId'),
        headers: ApiConstants.jsonHeaders,
        body: jsonEncode(requestBody),
      ).timeout(ApiConstants.defaultTimeout);

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

