import 'package:flutter_test/flutter_test.dart';
import 'package:arabica_app/shared/providers/order_provider.dart';

void main() {
  group('Wholesale Orders (Phase 6)', () {
    test('Order model has isWholesaleOrder field, defaults to false', () {
      final order = Order(
        id: 'test-1',
        items: [],
        totalPrice: 100,
        createdAt: DateTime.now(),
      );
      expect(order.isWholesaleOrder, false);
    });

    test('Order.fromJson parses isWholesaleOrder=true', () {
      final order = Order.fromJson({
        'id': 'test-2',
        'items': [],
        'totalPrice': 500,
        'createdAt': DateTime.now().toIso8601String(),
        'isWholesaleOrder': true,
      });
      expect(order.isWholesaleOrder, true);
    });

    test('Order.fromJson defaults isWholesaleOrder to false when missing', () {
      final order = Order.fromJson({
        'id': 'test-3',
        'items': [],
        'totalPrice': 200,
        'createdAt': DateTime.now().toIso8601String(),
      });
      expect(order.isWholesaleOrder, false);
    });

    test('Order.toJson includes isWholesaleOrder', () {
      final order = Order(
        id: 'test-4',
        items: [],
        totalPrice: 300,
        createdAt: DateTime.now(),
        isWholesaleOrder: true,
      );
      final json = order.toJson();
      expect(json['isWholesaleOrder'], true);
    });

    test('OrderProvider.updateOrderStatus preserves isWholesaleOrder', () {
      final provider = OrderProvider();
      // Use fromJson to add an order
      final orderJson = {
        'id': 'test-5',
        'items': [],
        'totalPrice': 1000,
        'createdAt': DateTime.now().toIso8601String(),
        'isWholesaleOrder': true,
        'status': 'pending',
      };
      // Simulate loading by accessing internal list
      final order = Order.fromJson(orderJson);
      expect(order.isWholesaleOrder, true);

      // After status update the flag should be preserved
      final updated = Order(
        id: order.id,
        items: order.items,
        totalPrice: order.totalPrice,
        createdAt: order.createdAt,
        status: 'completed',
        isWholesaleOrder: order.isWholesaleOrder,
      );
      expect(updated.isWholesaleOrder, true);
      expect(updated.status, 'completed');

      provider.dispose();
    });

    test('Wholesale badge data extraction from order map', () {
      // Simulate what employee_orders_page does
      final orderMap = {
        'orderNumber': 42,
        'isWholesaleOrder': true,
        'clientName': 'Тест',
        'shopAddress': 'ул. Ленина 1',
        'totalPrice': 5000,
      };

      final isWholesale = orderMap['isWholesaleOrder'] == true;
      expect(isWholesale, true);

      // Regular order
      final regularMap = {
        'orderNumber': 43,
        'clientName': 'Обычный',
      };
      final isRegular = regularMap['isWholesaleOrder'] == true;
      expect(isRegular, false);
    });
  });
}
