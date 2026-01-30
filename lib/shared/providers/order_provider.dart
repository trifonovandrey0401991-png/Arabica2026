import 'package:flutter/widgets.dart';
import 'cart_provider.dart';
import '../../features/orders/services/order_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/utils/logger.dart';

/// Модель заказа
class Order {
  final String id;
  final List<CartItem> items;
  final List<Map<String, dynamic>>? itemsData; // Сырые данные товаров с photoId
  final double totalPrice;
  final DateTime createdAt;
  final String? comment;
  final String status; // 'pending', 'preparing', 'ready', 'completed', 'rejected'
  final String? acceptedBy; // Имя сотрудника, который принял заказ
  final String? rejectedBy; // Имя сотрудника, который отказал от заказа
  final String? rejectionReason; // Причина отказа
  final int? orderNumber; // Глобальный номер заказа
  final String? clientPhone; // Телефон клиента
  final String? clientName; // Имя клиента
  final String? shopAddress; // Адрес магазина

  Order({
    required this.id,
    required this.items,
    this.itemsData,
    required this.totalPrice,
    required this.createdAt,
    this.comment,
    this.status = 'pending',
    this.acceptedBy,
    this.rejectedBy,
    this.rejectionReason,
    this.orderNumber,
    this.clientPhone,
    this.clientName,
    this.shopAddress,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'items': items.map((item) => {
        'name': item.menuItem.name,
        'price': item.menuItem.price,
        'quantity': item.quantity,
        'total': item.totalPrice,
      }).toList(),
      'totalPrice': totalPrice,
      'createdAt': createdAt.toIso8601String(),
      'comment': comment,
      'status': status,
      'acceptedBy': acceptedBy,
      'rejectedBy': rejectedBy,
      'rejectionReason': rejectionReason,
      'orderNumber': orderNumber,
      'clientPhone': clientPhone,
      'clientName': clientName,
      'shopAddress': shopAddress,
    };
  }

  factory Order.fromJson(Map<String, dynamic> json) {
    // Для упрощения, создаем заказ из JSON
    // В реальном приложении нужно будет восстановить MenuItem из данных
    final itemsList = json['items'] as List<dynamic>?;
    final itemsData = itemsList?.map((item) => item as Map<String, dynamic>).toList();

    return Order(
      id: json['id'] as String,
      items: [], // Упрощенная версия
      itemsData: itemsData,
      totalPrice: (json['totalPrice'] as num).toDouble(),
      createdAt: DateTime.parse(json['createdAt'] as String).toLocal(),
      comment: json['comment'] as String?,
      status: json['status'] as String? ?? 'pending',
      acceptedBy: json['acceptedBy'] as String?,
      rejectedBy: json['rejectedBy'] as String?,
      rejectionReason: json['rejectionReason'] as String?,
      orderNumber: json['orderNumber'] as int?,
      clientPhone: json['clientPhone'] as String?,
      clientName: json['clientName'] as String?,
      shopAddress: json['shopAddress'] as String?,
    );
  }
}

/// Провайдер для управления заказами
class OrderProvider with ChangeNotifier {
  final List<Order> _orders = [];

  List<Order> get orders => List.unmodifiable(_orders); // Новые заказы сверху (сервер уже сортирует по orderNumber DESC)

  int get orderCount => _orders.length;

  /// Загрузить заказы клиента с сервера
  Future<void> loadClientOrders(String clientPhone) async {
    if (clientPhone.isEmpty) return;

    try {
      final ordersData = await OrderService.getClientOrders(clientPhone);
      _orders.clear();
      for (var orderData in ordersData) {
        final order = Order.fromJson(orderData);
        _orders.add(order);
      }
      notifyListeners();
    } catch (e) {
      Logger.error('Ошибка загрузки заказов', e);
    }
  }

  /// Создать новый заказ из корзины
  Future<void> createOrder(List<CartItem> items, double totalPrice, {String? comment, String? shopAddress}) async {
    if (items.isEmpty) return;

    // Используем переданный shopAddress, иначе пытаемся взять из первого товара
    final effectiveShopAddress = shopAddress ?? items.first.menuItem.shop;
    
    // Получаем данные клиента
    final prefs = await SharedPreferences.getInstance();
    final clientPhone = prefs.getString('user_phone') ?? '';
    final clientName = prefs.getString('user_name') ?? 'Клиент';
    
    if (clientPhone.isEmpty) {
      throw Exception('Не удалось определить телефон клиента');
    }
    
    // Создаем заказ на сервере
    final serverOrder = await OrderService.createOrder(
      clientPhone: clientPhone,
      clientName: clientName,
      shopAddress: effectiveShopAddress,
      items: items,
      totalPrice: totalPrice,
      comment: comment,
    );
    
    if (serverOrder != null) {
      // Добавляем заказ в локальный список
      _orders.add(serverOrder);
      notifyListeners();
    } else {
      throw Exception('Не удалось создать заказ на сервере');
    }
  }

  /// Удалить заказ
  void removeOrder(String orderId) {
    _orders.removeWhere((order) => order.id == orderId);
    notifyListeners();
  }

  /// Обновить статус заказа
  void updateOrderStatus(String orderId, String newStatus) {
    final index = _orders.indexWhere((order) => order.id == orderId);
    if (index >= 0) {
      final order = _orders[index];
      _orders[index] = Order(
        id: order.id,
        items: order.items,
        itemsData: order.itemsData,
        totalPrice: order.totalPrice,
        createdAt: order.createdAt,
        comment: order.comment,
        status: newStatus,
        acceptedBy: order.acceptedBy,
        rejectedBy: order.rejectedBy,
        rejectionReason: order.rejectionReason,
        orderNumber: order.orderNumber,
        clientPhone: order.clientPhone,
        clientName: order.clientName,
        shopAddress: order.shopAddress,
      );
      notifyListeners();
    }
  }

  /// Принять заказ сотрудником
  void acceptOrder(String orderId, String employeeName) {
    final index = _orders.indexWhere((order) => order.id == orderId);
    if (index >= 0) {
      final order = _orders[index];
      _orders[index] = Order(
        id: order.id,
        items: order.items,
        itemsData: order.itemsData,
        totalPrice: order.totalPrice,
        createdAt: order.createdAt,
        comment: order.comment,
        status: 'completed',
        acceptedBy: employeeName,
        rejectedBy: null,
        rejectionReason: null,
        orderNumber: order.orderNumber,
        clientPhone: order.clientPhone,
        clientName: order.clientName,
        shopAddress: order.shopAddress,
      );
      notifyListeners();
    }
  }

  /// Отказаться от заказа
  void rejectOrder(String orderId, String employeeName, String reason) {
    final index = _orders.indexWhere((order) => order.id == orderId);
    if (index >= 0) {
      final order = _orders[index];
      _orders[index] = Order(
        id: order.id,
        items: order.items,
        itemsData: order.itemsData,
        totalPrice: order.totalPrice,
        createdAt: order.createdAt,
        comment: order.comment,
        status: 'rejected',
        acceptedBy: null,
        rejectedBy: employeeName,
        rejectionReason: reason,
        orderNumber: order.orderNumber,
        clientPhone: order.clientPhone,
        clientName: order.clientName,
        shopAddress: order.shopAddress,
      );
      notifyListeners();
    }
  }

  /// Обновить комментарий к заказу
  void updateOrderComment(String orderId, String? comment) {
    final index = _orders.indexWhere((order) => order.id == orderId);
    if (index >= 0) {
      final order = _orders[index];
      _orders[index] = Order(
        id: order.id,
        items: order.items,
        itemsData: order.itemsData,
        totalPrice: order.totalPrice,
        createdAt: order.createdAt,
        comment: comment,
        status: order.status,
        acceptedBy: order.acceptedBy,
        rejectedBy: order.rejectedBy,
        rejectionReason: order.rejectionReason,
        orderNumber: order.orderNumber,
        clientPhone: order.clientPhone,
        clientName: order.clientName,
        shopAddress: order.shopAddress,
      );
      notifyListeners();
    }
  }

  /// Получить провайдер из контекста
  static OrderProvider of(BuildContext context) {
    final scope = context.findAncestorWidgetOfExactType<_OrderProviderScope>();
    if (scope == null) {
      throw Exception('OrderProvider not found in widget tree');
    }
    return scope.orderProvider;
  }
}

/// Обертка для провайдера заказов
class _OrderProviderScope extends InheritedWidget {
  final OrderProvider orderProvider;

  const _OrderProviderScope({
    required this.orderProvider,
    required super.child,
  });

  @override
  bool updateShouldNotify(_OrderProviderScope oldWidget) {
    return orderProvider != oldWidget.orderProvider;
  }
}

/// Обертка для предоставления OrderProvider
class OrderProviderScope extends StatefulWidget {
  final Widget child;

  const OrderProviderScope({super.key, required this.child});

  @override
  State<OrderProviderScope> createState() => _OrderProviderScopeState();
}

class _OrderProviderScopeState extends State<OrderProviderScope> {
  final OrderProvider _orderProvider = OrderProvider();

  @override
  void dispose() {
    _orderProvider.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _OrderProviderScope(
      orderProvider: _orderProvider,
      child: widget.child,
    );
  }
}

