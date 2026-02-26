import 'package:flutter_test/flutter_test.dart';
import 'package:arabica_app/shared/providers/cart_provider.dart';
import 'package:arabica_app/features/shop_catalog/models/shop_product.dart';
import 'package:arabica_app/features/menu/pages/menu_page.dart';

void main() {
  late CartProvider cart;

  setUp(() {
    cart = CartProvider();
  });

  ShopProduct _makeProduct({
    String id = 'p1',
    String name = 'Кружка',
    double? priceRetail = 500,
    double? priceWholesale = 350,
    int? pricePoints = 100,
  }) {
    return ShopProduct(
      id: id,
      name: name,
      priceRetail: priceRetail,
      priceWholesale: priceWholesale,
      pricePoints: pricePoints,
    );
  }

  MenuItem _makeDrink({String name = 'Латте', String price = '250'}) {
    return MenuItem(id: '1', name: name, price: price, category: 'Кофе', shop: 'Shop1', photoId: '');
  }

  group('CartItem types', () {
    test('drink CartItem has correct type', () {
      cart.addItem(_makeDrink());
      expect(cart.items.first.type, CartItemType.drink);
    });

    test('shop product CartItem has correct type', () {
      cart.addShopProduct(_makeProduct());
      expect(cart.items.first.type, CartItemType.shopProduct);
    });

    test('name getter works for both types', () {
      cart.addItem(_makeDrink(name: 'Капучино'));
      cart.addShopProduct(_makeProduct(name: 'Стакан'));
      expect(cart.items[0].name, 'Капучино');
      expect(cart.items[1].name, 'Стакан');
    });
  });

  group('Mixed cart', () {
    test('cart holds both drinks and shop products', () {
      cart.addItem(_makeDrink());
      cart.addShopProduct(_makeProduct());
      expect(cart.itemCount, 2);
      expect(cart.hasDrinks, true);
      expect(cart.hasShopProducts, true);
    });

    test('total price includes both types (money payment)', () {
      cart.addItem(_makeDrink(price: '200')); // 200
      cart.addShopProduct(_makeProduct(priceRetail: 500)); // 500
      expect(cart.totalPrice, 700);
    });

    test('clear removes everything', () {
      cart.addItem(_makeDrink());
      cart.addShopProduct(_makeProduct());
      cart.clear();
      expect(cart.isEmpty, true);
      expect(cart.hasDrinks, false);
      expect(cart.hasShopProducts, false);
    });
  });

  group('Points payment', () {
    test('points payment does not affect totalPrice', () {
      cart.addShopProduct(_makeProduct(priceRetail: 500, pricePoints: 100), paymentMethod: PaymentMethod.points);
      expect(cart.totalPrice, 0);
      expect(cart.totalPointsPrice, 100);
    });

    test('mixed money and points', () {
      cart.addShopProduct(_makeProduct(id: 'p1', priceRetail: 500, pricePoints: 100), paymentMethod: PaymentMethod.money);
      cart.addShopProduct(_makeProduct(id: 'p2', priceRetail: 300, pricePoints: 50), paymentMethod: PaymentMethod.points);
      expect(cart.totalPrice, 500);
      expect(cart.totalPointsPrice, 50);
    });

    test('same product with different payment methods = separate items', () {
      final product = _makeProduct();
      cart.addShopProduct(product, paymentMethod: PaymentMethod.money);
      cart.addShopProduct(product, paymentMethod: PaymentMethod.points);
      expect(cart.items.length, 2);
    });

    test('same product same payment = merged', () {
      final product = _makeProduct();
      cart.addShopProduct(product, paymentMethod: PaymentMethod.money);
      cart.addShopProduct(product, paymentMethod: PaymentMethod.money);
      expect(cart.items.length, 1);
      expect(cart.items.first.quantity, 2);
      expect(cart.totalPrice, 1000);
    });
  });

  group('Quantity management', () {
    test('increase quantity for shop product', () {
      cart.addShopProduct(_makeProduct(priceRetail: 100));
      cart.increaseQuantity(cart.items.first);
      expect(cart.items.first.quantity, 2);
      expect(cart.totalPrice, 200);
    });

    test('decrease quantity for shop product', () {
      cart.addShopProduct(_makeProduct());
      cart.increaseQuantity(cart.items.first);
      cart.decreaseQuantity(cart.items.first);
      expect(cart.items.first.quantity, 1);
    });

    test('decrease to zero removes item', () {
      cart.addShopProduct(_makeProduct());
      cart.decreaseQuantity(cart.items.first);
      expect(cart.isEmpty, true);
    });

    test('remove specific item', () {
      cart.addItem(_makeDrink());
      cart.addShopProduct(_makeProduct());
      cart.removeItem(cart.items.last);
      expect(cart.items.length, 1);
      expect(cart.items.first.type, CartItemType.drink);
    });
  });

  group('Points price calculation', () {
    test('unitPointsPrice for shop product', () {
      cart.addShopProduct(_makeProduct(pricePoints: 50), paymentMethod: PaymentMethod.points);
      expect(cart.items.first.unitPointsPrice, 50);
      expect(cart.items.first.totalPointsPrice, 50);
    });

    test('totalPointsPrice with quantity', () {
      cart.addShopProduct(_makeProduct(pricePoints: 30), paymentMethod: PaymentMethod.points);
      cart.increaseQuantity(cart.items.first);
      cart.increaseQuantity(cart.items.first);
      expect(cart.items.first.quantity, 3);
      expect(cart.items.first.totalPointsPrice, 90);
      expect(cart.totalPointsPrice, 90);
    });

    test('drink has zero unitPointsPrice', () {
      cart.addItem(_makeDrink());
      expect(cart.items.first.unitPointsPrice, 0);
    });
  });
}
