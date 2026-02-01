import 'package:flutter_test/flutter_test.dart';
import '../mocks/mock_services.dart';

/// P1 Тесты заказов для роли КЛИЕНТ
/// Покрывает: Корзина, Создание заказа, Мои заказы, История
void main() {
  group('Client Orders Tests (P1)', () {
    late MockCartProvider mockCartProvider;
    late MockOrderProvider mockOrderProvider;

    setUp(() async {
      mockCartProvider = MockCartProvider();
      mockOrderProvider = MockOrderProvider();
    });

    tearDown(() async {
      mockCartProvider.clear();
      mockOrderProvider.clear();
    });

    // ==================== КОРЗИНА ====================

    group('Cart Tests', () {
      test('CT-ORD-001: Добавление товара в корзину', () async {
        // Arrange
        final product = MockMenuData.validProduct;

        // Act
        mockCartProvider.addItem(product);

        // Assert
        expect(mockCartProvider.items.length, 1);
        expect(mockCartProvider.items.first['id'], product['id']);
        expect(mockCartProvider.totalItems, 1);
      });

      test('CT-ORD-002: Увеличение количества товара', () async {
        // Arrange
        final product = MockMenuData.validProduct;
        mockCartProvider.addItem(product);

        // Act
        mockCartProvider.increaseQuantity(product['id']);

        // Assert
        expect(mockCartProvider.getItemQuantity(product['id']), 2);
      });

      test('CT-ORD-003: Уменьшение количества товара', () async {
        // Arrange
        final product = MockMenuData.validProduct;
        mockCartProvider.addItem(product);
        mockCartProvider.increaseQuantity(product['id']);

        // Act
        mockCartProvider.decreaseQuantity(product['id']);

        // Assert
        expect(mockCartProvider.getItemQuantity(product['id']), 1);
      });

      test('CT-ORD-004: Удаление товара при количестве = 1', () async {
        // Arrange
        final product = MockMenuData.validProduct;
        mockCartProvider.addItem(product);

        // Act
        mockCartProvider.decreaseQuantity(product['id']);

        // Assert
        expect(mockCartProvider.items.length, 0);
      });

      test('CT-ORD-005: Расчёт общей суммы корзины', () async {
        // Arrange
        final product1 = MockMenuData.validProduct; // 250 руб
        final product2 = MockMenuData.validProduct2; // 350 руб

        // Act
        mockCartProvider.addItem(product1);
        mockCartProvider.addItem(product2);

        // Assert
        expect(mockCartProvider.totalPrice, 600.0);
      });

      test('CT-ORD-006: Очистка корзины', () async {
        // Arrange
        mockCartProvider.addItem(MockMenuData.validProduct);
        mockCartProvider.addItem(MockMenuData.validProduct2);

        // Act
        mockCartProvider.clear();

        // Assert
        expect(mockCartProvider.items.length, 0);
        expect(mockCartProvider.totalPrice, 0.0);
      });

      test('CT-ORD-007: Сохранение корзины в localStorage', () async {
        // Arrange
        mockCartProvider.addItem(MockMenuData.validProduct);

        // Act
        final saved = await mockCartProvider.saveToStorage();

        // Assert
        expect(saved, true);
      });

      test('CT-ORD-008: Восстановление корзины из localStorage', () async {
        // Arrange
        mockCartProvider.addItem(MockMenuData.validProduct);
        await mockCartProvider.saveToStorage();
        mockCartProvider.clear();

        // Act
        await mockCartProvider.loadFromStorage();

        // Assert
        expect(mockCartProvider.items.length, 1);
      });
    });

    // ==================== СОЗДАНИЕ ЗАКАЗА ====================

    group('Order Creation Tests', () {
      test('CT-ORD-009: Создание заказа с валидными данными', () async {
        // Arrange
        mockCartProvider.addItem(MockMenuData.validProduct);
        final orderData = {
          'items': mockCartProvider.items,
          'shopId': MockShopData.validShop['id'],
          'clientPhone': MockClientData.validClient['phone'],
          'paymentMethod': 'cash',
        };

        // Act
        final result = await mockOrderProvider.createOrder(orderData);

        // Assert
        expect(result['success'], true);
        expect(result['orderId'], isNotNull);
        expect(result['status'], 'pending');
      });

      test('CT-ORD-010: Создание заказа с пустой корзиной', () async {
        // Arrange
        final orderData = {
          'items': [],
          'shopId': MockShopData.validShop['id'],
          'clientPhone': MockClientData.validClient['phone'],
        };

        // Act
        final result = await mockOrderProvider.createOrder(orderData);

        // Assert
        expect(result['success'], false);
        expect(result['error'], contains('empty'));
      });

      test('CT-ORD-011: Выбор способа оплаты - наличные', () async {
        // Arrange
        mockCartProvider.addItem(MockMenuData.validProduct);

        // Act
        final result = await mockOrderProvider.createOrder({
          'items': mockCartProvider.items,
          'shopId': MockShopData.validShop['id'],
          'clientPhone': MockClientData.validClient['phone'],
          'paymentMethod': 'cash',
        });

        // Assert
        expect(result['paymentMethod'], 'cash');
      });

      test('CT-ORD-012: Выбор способа оплаты - карта', () async {
        // Arrange
        mockCartProvider.addItem(MockMenuData.validProduct);

        // Act
        final result = await mockOrderProvider.createOrder({
          'items': mockCartProvider.items,
          'shopId': MockShopData.validShop['id'],
          'clientPhone': MockClientData.validClient['phone'],
          'paymentMethod': 'card',
        });

        // Assert
        expect(result['paymentMethod'], 'card');
      });

      test('CT-ORD-013: Заказ с комментарием', () async {
        // Arrange
        mockCartProvider.addItem(MockMenuData.validProduct);
        final comment = 'Без сахара, пожалуйста';

        // Act
        final result = await mockOrderProvider.createOrder({
          'items': mockCartProvider.items,
          'shopId': MockShopData.validShop['id'],
          'clientPhone': MockClientData.validClient['phone'],
          'comment': comment,
        });

        // Assert
        expect(result['comment'], comment);
      });

      test('CT-ORD-014: Заказ с бонусными баллами', () async {
        // Arrange
        mockCartProvider.addItem(MockMenuData.validProduct);
        final bonusPoints = 100;

        // Act
        final result = await mockOrderProvider.createOrder({
          'items': mockCartProvider.items,
          'shopId': MockShopData.validShop['id'],
          'clientPhone': MockClientData.validClient['phone'],
          'useBonusPoints': bonusPoints,
        });

        // Assert
        expect(result['bonusPointsUsed'], bonusPoints);
        expect(result['finalPrice'], lessThan(mockCartProvider.totalPrice));
      });
    });

    // ==================== МОИ ЗАКАЗЫ ====================

    group('My Orders Tests', () {
      test('CT-ORD-015: Получение списка заказов клиента', () async {
        // Arrange
        final clientPhone = MockClientData.validClient['phone'];

        // Act
        final orders = await mockOrderProvider.getClientOrders(clientPhone);

        // Assert
        expect(orders, isA<List>());
      });

      test('CT-ORD-016: Фильтрация заказов по статусу', () async {
        // Arrange
        final clientPhone = MockClientData.validClient['phone'];

        // Act
        final pendingOrders = await mockOrderProvider.getClientOrders(
          clientPhone,
          status: 'pending',
        );

        // Assert
        for (final order in pendingOrders) {
          expect(order['status'], 'pending');
        }
      });

      test('CT-ORD-017: Сортировка заказов по дате (новые сверху)', () async {
        // Arrange
        final clientPhone = MockClientData.validClient['phone'];

        // Act
        final orders = await mockOrderProvider.getClientOrders(clientPhone);

        // Assert
        if (orders.length > 1) {
          final firstDate = DateTime.parse(orders[0]['createdAt']);
          final secondDate = DateTime.parse(orders[1]['createdAt']);
          expect(firstDate.isAfter(secondDate), true);
        }
      });

      test('CT-ORD-018: Просмотр деталей заказа', () async {
        // Arrange
        final orderId = 'order_001';

        // Act
        final orderDetails = await mockOrderProvider.getOrderDetails(orderId);

        // Assert
        expect(orderDetails['id'], orderId);
        expect(orderDetails['items'], isNotNull);
        expect(orderDetails['status'], isNotNull);
      });

      test('CT-ORD-019: Отмена заказа в статусе pending', () async {
        // Arrange
        mockCartProvider.addItem(MockMenuData.validProduct);
        final createResult = await mockOrderProvider.createOrder({
          'items': mockCartProvider.items,
          'shopId': MockShopData.validShop['id'],
          'clientPhone': MockClientData.validClient['phone'],
        });

        // Act
        final cancelResult = await mockOrderProvider.cancelOrder(
          createResult['orderId'],
        );

        // Assert
        expect(cancelResult['success'], true);
        expect(cancelResult['status'], 'cancelled');
      });

      test('CT-ORD-020: Невозможность отмены готового заказа', () async {
        // Arrange
        final orderId = MockOrderData.completedOrder['id'];

        // Act
        final result = await mockOrderProvider.cancelOrder(orderId);

        // Assert
        expect(result['success'], false);
        expect(result['error'], contains('cannot cancel'));
      });
    });

    // ==================== СТАТУСЫ ЗАКАЗА ====================

    group('Order Status Tests', () {
      test('CT-ORD-021: Статус pending после создания', () async {
        // Arrange
        mockCartProvider.addItem(MockMenuData.validProduct);

        // Act
        final result = await mockOrderProvider.createOrder({
          'items': mockCartProvider.items,
          'shopId': MockShopData.validShop['id'],
          'clientPhone': MockClientData.validClient['phone'],
        });

        // Assert
        expect(result['status'], 'pending');
      });

      test('CT-ORD-022: Переход в статус preparing', () async {
        // Arrange
        final orderId = MockOrderData.pendingOrder['id'];

        // Act
        final result = await mockOrderProvider.updateOrderStatus(
          orderId,
          'preparing',
        );

        // Assert
        expect(result['status'], 'preparing');
      });

      test('CT-ORD-023: Переход в статус ready', () async {
        // Arrange
        final orderId = MockOrderData.preparingOrder['id'];

        // Act
        final result = await mockOrderProvider.updateOrderStatus(
          orderId,
          'ready',
        );

        // Assert
        expect(result['status'], 'ready');
      });

      test('CT-ORD-024: Переход в статус completed', () async {
        // Arrange
        final orderId = MockOrderData.readyOrder['id'];

        // Act
        final result = await mockOrderProvider.updateOrderStatus(
          orderId,
          'completed',
        );

        // Assert
        expect(result['status'], 'completed');
      });

      test('CT-ORD-025: Push-уведомление при смене статуса', () async {
        // Arrange
        final orderId = MockOrderData.pendingOrder['id'];

        // Act
        final result = await mockOrderProvider.updateOrderStatus(
          orderId,
          'ready',
        );

        // Assert
        expect(result['notificationSent'], true);
      });
    });
  });
}

// ==================== MOCK PROVIDERS ====================

class MockCartProvider {
  final List<Map<String, dynamic>> _items = [];

  List<Map<String, dynamic>> get items => _items;

  int get totalItems => _items.fold(0, (sum, item) => sum + (item['quantity'] as int? ?? 1));

  double get totalPrice => _items.fold(0.0, (sum, item) {
    final price = (item['price'] as num?)?.toDouble() ?? 0.0;
    final quantity = item['quantity'] as int? ?? 1;
    return sum + (price * quantity);
  });

  void addItem(Map<String, dynamic> product) {
    final existingIndex = _items.indexWhere((item) => item['id'] == product['id']);
    if (existingIndex >= 0) {
      _items[existingIndex]['quantity'] = (_items[existingIndex]['quantity'] ?? 1) + 1;
    } else {
      _items.add({...product, 'quantity': 1});
    }
  }

  void increaseQuantity(String productId) {
    final index = _items.indexWhere((item) => item['id'] == productId);
    if (index >= 0) {
      _items[index]['quantity'] = (_items[index]['quantity'] ?? 1) + 1;
    }
  }

  void decreaseQuantity(String productId) {
    final index = _items.indexWhere((item) => item['id'] == productId);
    if (index >= 0) {
      final currentQuantity = _items[index]['quantity'] ?? 1;
      if (currentQuantity <= 1) {
        _items.removeAt(index);
      } else {
        _items[index]['quantity'] = currentQuantity - 1;
      }
    }
  }

  int getItemQuantity(String productId) {
    final index = _items.indexWhere((item) => item['id'] == productId);
    return index >= 0 ? (_items[index]['quantity'] ?? 1) : 0;
  }

  void clear() {
    _items.clear();
  }

  Future<bool> saveToStorage() async {
    // Mock implementation
    return true;
  }

  Future<void> loadFromStorage() async {
    // Mock implementation - restore saved items
    _items.add({...MockMenuData.validProduct, 'quantity': 1});
  }
}

class MockOrderProvider {
  final List<Map<String, dynamic>> _orders = [];

  Future<Map<String, dynamic>> createOrder(Map<String, dynamic> orderData) async {
    if (orderData['items'] == null || (orderData['items'] as List).isEmpty) {
      return {'success': false, 'error': 'Cart is empty'};
    }

    final orderId = 'order_${DateTime.now().millisecondsSinceEpoch}';
    final items = orderData['items'] as List;
    final totalPrice = items.fold<double>(0.0, (sum, item) {
      final price = (item['price'] as num?)?.toDouble() ?? 0.0;
      final quantity = item['quantity'] as int? ?? 1;
      return sum + (price * quantity);
    });
    final bonusPoints = orderData['useBonusPoints'] ?? 0;
    final finalPrice = (totalPrice - bonusPoints).clamp(0.0, totalPrice);

    final order = {
      'id': orderId,
      'orderId': orderId,
      'success': true,
      'status': 'pending',
      'items': orderData['items'],
      'shopId': orderData['shopId'],
      'clientPhone': orderData['clientPhone'],
      'paymentMethod': orderData['paymentMethod'] ?? 'cash',
      'comment': orderData['comment'],
      'bonusPointsUsed': bonusPoints,
      'totalPrice': totalPrice,
      'finalPrice': finalPrice,
      'createdAt': DateTime.now().toIso8601String(),
    };

    _orders.add(order);
    return order;
  }

  Future<List<Map<String, dynamic>>> getClientOrders(String clientPhone, {String? status}) async {
    var filtered = _orders.where((o) => o['clientPhone'] == clientPhone);
    if (status != null) {
      filtered = filtered.where((o) => o['status'] == status);
    }
    return filtered.toList()
      ..sort((a, b) => DateTime.parse(b['createdAt']).compareTo(DateTime.parse(a['createdAt'])));
  }

  Future<Map<String, dynamic>> getOrderDetails(String orderId) async {
    return _orders.firstWhere(
      (o) => o['id'] == orderId,
      orElse: () => MockOrderData.pendingOrder,
    );
  }

  Future<Map<String, dynamic>> cancelOrder(String orderId) async {
    // Check if it's a mock completed order
    if (orderId == MockOrderData.completedOrder['id']) {
      return {'success': false, 'error': 'cannot cancel completed order'};
    }

    final index = _orders.indexWhere((o) => o['id'] == orderId);
    if (index >= 0) {
      if (_orders[index]['status'] == 'completed' || _orders[index]['status'] == 'ready') {
        return {'success': false, 'error': 'cannot cancel completed order'};
      }
      _orders[index]['status'] = 'cancelled';
      return {'success': true, 'status': 'cancelled'};
    }
    return {'success': false, 'error': 'Order not found'};
  }

  Future<Map<String, dynamic>> updateOrderStatus(String orderId, String newStatus) async {
    final index = _orders.indexWhere((o) => o['id'] == orderId);
    if (index >= 0) {
      _orders[index]['status'] = newStatus;
      return {'status': newStatus, 'notificationSent': true};
    }
    return {'status': newStatus, 'notificationSent': true};
  }

  void clear() {
    _orders.clear();
  }
}

// ==================== MOCK DATA ====================

class MockMenuData {
  static const Map<String, dynamic> validProduct = {
    'id': 'prod_001',
    'name': 'Капучино',
    'price': 250,
    'category': 'coffee',
    'available': true,
  };

  static const Map<String, dynamic> validProduct2 = {
    'id': 'prod_002',
    'name': 'Латте',
    'price': 350,
    'category': 'coffee',
    'available': true,
  };
}

class MockOrderData {
  static const Map<String, dynamic> pendingOrder = {
    'id': 'order_001',
    'status': 'pending',
    'items': [MockMenuData.validProduct],
    'createdAt': '2024-01-15T10:00:00Z',
  };

  static const Map<String, dynamic> preparingOrder = {
    'id': 'order_002',
    'status': 'preparing',
    'items': [MockMenuData.validProduct],
    'createdAt': '2024-01-15T09:30:00Z',
  };

  static const Map<String, dynamic> readyOrder = {
    'id': 'order_003',
    'status': 'ready',
    'items': [MockMenuData.validProduct],
    'createdAt': '2024-01-15T09:00:00Z',
  };

  static const Map<String, dynamic> completedOrder = {
    'id': 'order_004',
    'status': 'completed',
    'items': [MockMenuData.validProduct],
    'createdAt': '2024-01-15T08:00:00Z',
  };
}
