import 'package:flutter/widgets.dart';
import 'menu_page.dart';

/// Элемент корзины
class CartItem {
  final MenuItem menuItem;
  int quantity;

  CartItem({
    required this.menuItem,
    this.quantity = 1,
  });

  double get totalPrice {
    final price = double.tryParse(menuItem.price) ?? 0.0;
    return price * quantity;
  }
}

/// Провайдер для управления корзиной
class CartProvider with ChangeNotifier {
  final List<CartItem> _items = [];

  List<CartItem> get items => List.unmodifiable(_items);

  int get itemCount => _items.fold(0, (sum, item) => sum + item.quantity);

  double get totalPrice {
    return _items.fold(0.0, (sum, item) => sum + item.totalPrice);
  }

  bool get isEmpty => _items.isEmpty;

  /// Добавить товар в корзину
  void addItem(MenuItem menuItem) {
    // Проверяем, есть ли уже такой товар в корзине
    final existingIndex = _items.indexWhere(
      (item) =>
          item.menuItem.name == menuItem.name &&
          item.menuItem.price == menuItem.price &&
          item.menuItem.category == menuItem.category,
    );

    if (existingIndex >= 0) {
      // Если товар уже есть, увеличиваем количество
      _items[existingIndex].quantity++;
    } else {
      // Если товара нет, добавляем новый
      _items.add(CartItem(menuItem: menuItem));
    }
    notifyListeners();
  }

  /// Удалить товар из корзины
  void removeItem(CartItem cartItem) {
    _items.remove(cartItem);
    notifyListeners();
  }

  /// Уменьшить количество товара
  void decreaseQuantity(CartItem cartItem) {
    if (cartItem.quantity > 1) {
      cartItem.quantity--;
      notifyListeners();
    } else {
      removeItem(cartItem);
    }
  }

  /// Увеличить количество товара
  void increaseQuantity(CartItem cartItem) {
    cartItem.quantity++;
    notifyListeners();
  }

  /// Очистить корзину
  void clear() {
    _items.clear();
    notifyListeners();
  }

  /// Получить провайдер из контекста
  static CartProvider of(BuildContext context) {
    final scope = context.findAncestorWidgetOfExactType<_CartProviderScope>();
    if (scope == null) {
      throw Exception('CartProvider not found in widget tree');
    }
    return scope.cart;
  }
}

/// Обертка для провайдера корзины
class _CartProviderScope extends InheritedWidget {
  final CartProvider cart;

  const _CartProviderScope({
    required this.cart,
    required super.child,
  });

  @override
  bool updateShouldNotify(_CartProviderScope oldWidget) {
    return cart != oldWidget.cart;
  }
}

/// Обертка для предоставления CartProvider
class CartProviderScope extends StatefulWidget {
  final Widget child;

  const CartProviderScope({super.key, required this.child});

  @override
  State<CartProviderScope> createState() => _CartProviderScopeState();
}

class _CartProviderScopeState extends State<CartProviderScope> {
  final CartProvider _cart = CartProvider();

  @override
  void dispose() {
    _cart.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _CartProviderScope(
      cart: _cart,
      child: widget.child,
    );
  }
}

