import '../../../shared/providers/order_provider.dart';
import '../../../shared/providers/cart_provider.dart';
import '../../../core/services/base_http_service.dart';
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
        'imageUrl': item.menuItem.imageUrl,
      }).toList();

      final requestBody = {
        'clientPhone': clientPhone,
        'clientName': clientName,
        'shopAddress': shopAddress,
        'items': itemsJson,
        'totalPrice': totalPrice,
        if (comment != null && comment.isNotEmpty) 'comment': comment,
      };

      final result = await BaseHttpService.postRaw(
        endpoint: baseEndpoint,
        body: requestBody,
        timeout: ApiConstants.longTimeout,
      );

      if (result != null && result['order'] != null) {
        Logger.debug('✅ Заказ создан: ${result['order']['id']}');
        final orderData = result['order'];
        final itemsList = orderData['items'] as List<dynamic>?;
        final itemsData = itemsList?.map((item) => item as Map<String, dynamic>).toList();

        return Order(
          id: orderData['id'],
          items: [],
          itemsData: itemsData,
          totalPrice: (orderData['totalPrice'] as num).toDouble(),
          createdAt: DateTime.parse(orderData['createdAt']).toLocal(),
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
      }
      return null;
    } catch (e) {
      Logger.error('❌ Ошибка создания заказа: $e');
      return null;
    }
  }

  /// Получить заказы клиента
  static Future<List<Map<String, dynamic>>> getClientOrders(String clientPhone) async {
    Logger.debug('📥 Загрузка заказов клиента: ${Logger.maskPhone(clientPhone)}');

    final result = await BaseHttpService.getRaw(
      endpoint: baseEndpoint,
      queryParams: {'clientPhone': clientPhone},
    );

    if (result != null && result['orders'] != null) {
      final ordersJson = result['orders'] as List<dynamic>;
      Logger.debug('✅ Загружено заказов: ${ordersJson.length}');
      return ordersJson.map((o) => o as Map<String, dynamic>).toList();
    }
    return [];
  }

  /// Получить все заказы (для сотрудников)
  static Future<List<Map<String, dynamic>>> getAllOrders({String? status}) async {
    Logger.debug('📥 Загрузка всех заказов${status != null ? ' со статусом: $status' : ''}');

    final queryParams = <String, String>{};
    if (status != null) {
      queryParams['status'] = status;
    }

    final result = await BaseHttpService.getRaw(
      endpoint: baseEndpoint,
      queryParams: queryParams.isNotEmpty ? queryParams : null,
    );

    if (result != null && result['orders'] != null) {
      final ordersJson = result['orders'] as List<dynamic>;
      Logger.debug('✅ Загружено заказов: ${ordersJson.length}');
      return ordersJson.map((o) => o as Map<String, dynamic>).toList();
    }
    return [];
  }

  /// Обновить статус заказа
  static Future<bool> updateOrderStatus({
    required String orderId,
    String? status,
    String? acceptedBy,
    String? rejectedBy,
    String? rejectionReason,
  }) async {
    Logger.debug('📤 Обновление статуса заказа: $orderId');

    final requestBody = <String, dynamic>{};
    if (status != null) requestBody['status'] = status;
    if (acceptedBy != null) requestBody['acceptedBy'] = acceptedBy;
    if (rejectedBy != null) requestBody['rejectedBy'] = rejectedBy;
    if (rejectionReason != null) requestBody['rejectionReason'] = rejectionReason;

    return await BaseHttpService.simplePatch(
      endpoint: '$baseEndpoint/$orderId',
      body: requestBody,
    );
  }

  /// Получить количество непросмотренных заказов (rejected + unconfirmed)
  static Future<Map<String, int>> getUnviewedCounts() async {
    try {
      final result = await BaseHttpService.getRaw(
        endpoint: '$baseEndpoint/unviewed-count',
      );
      if (result != null) {
        return {
          'rejected': result['rejected'] as int? ?? 0,
          'unconfirmed': result['unconfirmed'] as int? ?? 0,
          'total': result['total'] as int? ?? 0,
        };
      }
      return {'rejected': 0, 'unconfirmed': 0, 'total': 0};
    } catch (e) {
      Logger.error('Ошибка получения непросмотренных заказов', e);
      return {'rejected': 0, 'unconfirmed': 0, 'total': 0};
    }
  }

  /// Отметить заказы как просмотренные
  static Future<void> markAsViewed(String type) async {
    try {
      await BaseHttpService.simplePost(
        endpoint: '$baseEndpoint/mark-viewed/$type',
        body: {},
      );
    } catch (e) {
      Logger.error('Ошибка отметки заказов как просмотренных', e);
    }
  }
}

