import 'package:flutter/widgets.dart';
import 'cart_provider.dart';

/// Модель заказа
class Order {
  final String id;
  final List<CartItem> items;
  final double totalPrice;
  final DateTime createdAt;
  final String? comment;
  final String status; // 'pending', 'preparing', 'ready', 'completed', 'rejected'
  final String? acceptedBy; // Имя сотрудника, который принял заказ
  final String? rejectedBy; // Имя сотрудника, который отказал от заказа
  final String? rejectionReason; // Причина отказа

  Order({
    required this.id,
    required this.items,
    required this.totalPrice,
    required this.createdAt,
    this.comment,
    this.status = 'pending',
    this.acceptedBy,
    this.rejectedBy,
    this.rejectionReason,
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
    };
  }

  factory Order.fromJson(Map<String, dynamic> json) {
    // Для упрощения, создаем заказ из JSON
    // В реальном приложении нужно будет восстановить MenuItem из данных
    return Order(
      id: json['id'] as String,
      items: [], // Упрощенная версия
      totalPrice: (json['totalPrice'] as num).toDouble(),
      createdAt: DateTime.parse(json['createdAt'] as String),
      comment: json['comment'] as String?,
      status: json['status'] as String? ?? 'pending',
      acceptedBy: json['acceptedBy'] as String?,
      rejectedBy: json['rejectedBy'] as String?,
      rejectionReason: json['rejectionReason'] as String?,
    );
  }
}

/// Провайдер для управления заказами
class OrderProvider with ChangeNotifier {
  final List<Order> _orders = [];

  List<Order> get orders => List.unmodifiable(_orders.reversed); // Новые заказы сверху

  int get orderCount => _orders.length;

  /// Создать новый заказ из корзины
  void createOrder(List<CartItem> items, double totalPrice, {String? comment}) {
    final order = Order(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      items: items.map((item) => CartItem(
        menuItem: item.menuItem,
        quantity: item.quantity,
      )).toList(),
      totalPrice: totalPrice,
      createdAt: DateTime.now(),
      comment: comment,
      status: 'pending',
    );

    _orders.add(order);
    notifyListeners();
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
        totalPrice: order.totalPrice,
        createdAt: order.createdAt,
        comment: order.comment,
        status: newStatus,
        acceptedBy: order.acceptedBy,
        rejectedBy: order.rejectedBy,
        rejectionReason: order.rejectionReason,
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
        totalPrice: order.totalPrice,
        createdAt: order.createdAt,
        comment: order.comment,
        status: 'completed',
        acceptedBy: employeeName,
        rejectedBy: null,
        rejectionReason: null,
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
        totalPrice: order.totalPrice,
        createdAt: order.createdAt,
        comment: order.comment,
        status: 'rejected',
        acceptedBy: null,
        rejectedBy: employeeName,
        rejectionReason: reason,
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

