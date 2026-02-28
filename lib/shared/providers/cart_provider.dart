import 'package:flutter/widgets.dart';
import '../../features/menu/pages/menu_page.dart';
import '../../features/shop_catalog/models/shop_product.dart';

/// Тип элемента корзины
enum CartItemType { drink, shopProduct }

/// Способ оплаты
enum PaymentMethod { money, points }

/// Элемент корзины
class CartItem {
  final CartItemType type;
  final MenuItem? menuItem;        // For drinks
  final ShopProduct? shopProduct;  // For shop products
  final PaymentMethod paymentMethod;
  int quantity;

  CartItem({
    this.type = CartItemType.drink,
    this.menuItem,
    this.shopProduct,
    this.paymentMethod = PaymentMethod.money,
    this.quantity = 1,
  });

  /// Name for display
  String get name => type == CartItemType.drink
      ? (menuItem?.name ?? '')
      : (shopProduct?.name ?? '');

  /// Unit price in rubles (retail)
  double get unitPrice {
    if (type == CartItemType.drink) {
      return double.tryParse(menuItem?.price ?? '') ?? 0.0;
    }
    return shopProduct?.priceRetail ?? 0.0;
  }

  /// Unit price in points (for points payment)
  int get unitPointsPrice {
    if (type == CartItemType.drink) return 0;
    return shopProduct?.pricePoints ?? 0;
  }

  /// Total price in rubles
  double get totalPrice {
    if (paymentMethod == PaymentMethod.points) return 0.0;
    return unitPrice * quantity;
  }

  /// Total price in points
  int get totalPointsPrice {
    if (paymentMethod != PaymentMethod.points) return 0;
    return unitPointsPrice * quantity;
  }

}

/// Провайдер для управления корзиной
class CartProvider with ChangeNotifier {
  final List<CartItem> _items = [];
  String? _selectedShopAddress;

  /// Получить адрес выбранного магазина
  String? get selectedShopAddress => _selectedShopAddress;

  /// Установить адрес магазина
  void setShopAddress(String? address) {
    if (_selectedShopAddress != address) {
      _selectedShopAddress = address;
      notifyListeners();
    }
  }

  List<CartItem> get items => List.unmodifiable(_items);

  int get itemCount => _items.fold(0, (sum, item) => sum + item.quantity);

  /// Total in rubles (only money-payment items)
  double get totalPrice {
    return _items.fold(0.0, (sum, item) => sum + item.totalPrice);
  }

  /// Total in points (only points-payment items)
  int get totalPointsPrice {
    return _items.fold(0, (sum, item) => sum + item.totalPointsPrice);
  }

  bool get isEmpty => _items.isEmpty;

  /// Has any shop products?
  bool get hasShopProducts => _items.any((i) => i.type == CartItemType.shopProduct);

  /// Has any drinks?
  bool get hasDrinks => _items.any((i) => i.type == CartItemType.drink);

  /// Добавить напиток в корзину (backward compat)
  void addItem(MenuItem menuItem) {
    final existing = _items.indexWhere(
      (item) =>
          item.type == CartItemType.drink &&
          item.menuItem?.name == menuItem.name &&
          item.menuItem?.price == menuItem.price &&
          item.menuItem?.category == menuItem.category,
    );

    if (existing >= 0) {
      _items[existing].quantity++;
    } else {
      _items.add(CartItem(type: CartItemType.drink, menuItem: menuItem));
    }
    notifyListeners();
  }

  /// Добавить товар магазина в корзину
  void addShopProduct(ShopProduct product, {PaymentMethod paymentMethod = PaymentMethod.money}) {
    final existing = _items.indexWhere(
      (item) =>
          item.type == CartItemType.shopProduct &&
          item.shopProduct?.id == product.id &&
          item.paymentMethod == paymentMethod,
    );

    if (existing >= 0) {
      _items[existing].quantity++;
    } else {
      _items.add(CartItem(
        type: CartItemType.shopProduct,
        shopProduct: product,
        paymentMethod: paymentMethod,
      ));
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

  /// Get quantity of a shop product in cart (by product id, money payment)
  int getShopProductQuantity(String productId, {PaymentMethod paymentMethod = PaymentMethod.money}) {
    final idx = _items.indexWhere(
      (item) =>
          item.type == CartItemType.shopProduct &&
          item.shopProduct?.id == productId &&
          item.paymentMethod == paymentMethod,
    );
    return idx >= 0 ? _items[idx].quantity : 0;
  }

  /// Set exact quantity for a shop product
  void setShopProductQuantity(ShopProduct product, int quantity, {PaymentMethod paymentMethod = PaymentMethod.money}) {
    final idx = _items.indexWhere(
      (item) =>
          item.type == CartItemType.shopProduct &&
          item.shopProduct?.id == product.id &&
          item.paymentMethod == paymentMethod,
    );

    if (quantity <= 0) {
      if (idx >= 0) _items.removeAt(idx);
    } else if (idx >= 0) {
      _items[idx].quantity = quantity;
    } else {
      _items.add(CartItem(
        type: CartItemType.shopProduct,
        shopProduct: product,
        paymentMethod: paymentMethod,
        quantity: quantity,
      ));
    }
    notifyListeners();
  }

  /// Decrease shop product quantity by 1
  void decreaseShopProduct(String productId, {PaymentMethod paymentMethod = PaymentMethod.money}) {
    final idx = _items.indexWhere(
      (item) =>
          item.type == CartItemType.shopProduct &&
          item.shopProduct?.id == productId &&
          item.paymentMethod == paymentMethod,
    );
    if (idx < 0) return;
    if (_items[idx].quantity > 1) {
      _items[idx].quantity--;
    } else {
      _items.removeAt(idx);
    }
    notifyListeners();
  }

  /// Очистить корзину
  void clear() {
    _items.clear();
    _selectedShopAddress = null;
    notifyListeners();
  }

  /// Получить провайдер из контекста (регистрирует зависимость для перестройки)
  static CartProvider of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<_CartProviderScope>();
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
    // Same instance, but content changed — always notify dependents
    return true;
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
  void initState() {
    super.initState();
    // Rebuild InheritedWidget when cart notifies (e.g. item added/removed)
    _cart.addListener(_onCartChanged);
  }

  void _onCartChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _cart.removeListener(_onCartChanged);
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
