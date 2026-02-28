import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/theme/app_colors.dart';
import '../../../shared/providers/cart_provider.dart';
import '../../../shared/providers/order_provider.dart';
import '../../shops/models/shop_model.dart';
import 'orders_page.dart';
import '../../../shared/widgets/app_cached_image.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

/// Страница корзины (Dark Emerald тема)
class CartPage extends StatefulWidget {
  const CartPage({super.key});

  @override
  State<CartPage> createState() => _CartPageState();
}

class _CartPageState extends State<CartPage> {
  List<Shop> _shops = [];
  String? _lastShopAddress;
  bool _isCreatingOrder = false;

  @override
  void initState() {
    super.initState();
    _loadShops();
    _loadLastShop();
  }

  Future<void> _loadShops() async {
    final shops = await Shop.loadShopsFromServer();
    if (mounted) setState(() => _shops = shops);
  }

  Future<void> _loadLastShop() async {
    final prefs = await SharedPreferences.getInstance();
    final lastShop = prefs.getString('last_shop_order_address');
    if (mounted) setState(() => _lastShopAddress = lastShop);
  }

  Future<void> _saveLastShop(String address) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('last_shop_order_address', address);
    if (mounted) setState(() => _lastShopAddress = address);
  }

  Widget _buildNoPhotoPlaceholder({bool isShopProduct = false}) {
    return Container(
      width: 60,
      height: 60,
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12.r),
      ),
      child: Icon(
        isShopProduct ? Icons.storefront_rounded : Icons.local_cafe_rounded,
        size: 28,
        color: AppColors.gold,
      ),
    );
  }

  Widget _buildCartItemImage(CartItem cartItem) {
    if (cartItem.type == CartItemType.shopProduct) {
      final photoUrl = cartItem.shopProduct?.firstPhotoUrl;
      if (photoUrl != null) {
        return AppCachedImage(
          imageUrl: photoUrl,
          width: 60,
          height: 60,
          fit: BoxFit.cover,
          errorWidget: (_, __, ___) => _buildNoPhotoPlaceholder(isShopProduct: true),
        );
      }
      return _buildNoPhotoPlaceholder(isShopProduct: true);
    }
    // Drink
    final item = cartItem.menuItem;
    if (item != null && item.hasNetworkPhoto) {
      return AppCachedImage(
        imageUrl: item.imageUrl!,
        width: 60,
        height: 60,
        fit: BoxFit.cover,
        errorWidget: (_, __, ___) => _buildNoPhotoPlaceholder(),
      );
    } else if (item != null && item.photoId.isNotEmpty) {
      final imagePath = 'assets/images/${item.photoId}.jpg';
      return Image.asset(
        imagePath,
        width: 60,
        height: 60,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _buildNoPhotoPlaceholder(),
      );
    } else {
      return _buildNoPhotoPlaceholder();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.night,
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [AppColors.emerald, AppColors.emeraldDark, AppColors.night],
            stops: [0.0, 0.3, 1.0],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              // Custom AppBar
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 12.h),
                child: Row(
                  children: [
                    GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(12.r),
                          border: Border.all(color: Colors.white.withOpacity(0.1)),
                        ),
                        child: Icon(Icons.arrow_back, color: Colors.white, size: 20),
                      ),
                    ),
                    SizedBox(width: 12),
                    Icon(Icons.shopping_cart_rounded, color: AppColors.gold, size: 24),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Корзина',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 20.sp,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    ListenableBuilder(
                      listenable: CartProvider.of(context),
                      builder: (context, _) {
                        final count = CartProvider.of(context).items.length;
                        if (count == 0) return SizedBox.shrink();
                        return Container(
                          padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 4.h),
                          decoration: BoxDecoration(
                            color: AppColors.gold.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(10.r),
                            border: Border.all(color: AppColors.gold.withOpacity(0.4)),
                          ),
                          child: Text(
                            '$count',
                            style: TextStyle(
                              color: AppColors.gold,
                              fontWeight: FontWeight.bold,
                              fontSize: 14.sp,
                            ),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),

              // Содержимое
              Expanded(
                child: ListenableBuilder(
                  listenable: CartProvider.of(context),
                  builder: (context, _) {
                    final cart = CartProvider.of(context);

                    if (cart.isEmpty) {
                      return _buildEmptyState(context);
                    }

                    return Column(
                      children: [
                        Expanded(
                          child: ListView.builder(
                            padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 4.h),
                            itemCount: cart.items.length,
                            itemBuilder: (context, index) {
                              final cartItem = cart.items[index];
                              return _buildCartItemCard(context, cart, cartItem);
                            },
                          ),
                        ),
                        _buildBottomPanel(context, cart),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: EdgeInsets.all(32.w),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.06),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.shopping_cart_outlined,
              size: 72,
              color: Colors.white.withOpacity(0.3),
            ),
          ),
          SizedBox(height: 28),
          Text(
            'Корзина пуста',
            style: TextStyle(
              fontSize: 22.sp,
              color: Colors.white,
              fontWeight: FontWeight.w600,
            ),
          ),
          SizedBox(height: 10),
          Text(
            'Добавьте напитки из меню или товары из магазина',
            style: TextStyle(
              fontSize: 15.sp,
              color: Colors.white.withOpacity(0.5),
            ),
          ),
          SizedBox(height: 28),
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Container(
              padding: EdgeInsets.symmetric(horizontal: 24.w, vertical: 12.h),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.1),
                borderRadius: BorderRadius.circular(14.r),
                border: Border.all(color: Colors.white.withOpacity(0.15)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.arrow_back_rounded, color: AppColors.gold, size: 18),
                  SizedBox(width: 8),
                  Text(
                    'В меню',
                    style: TextStyle(
                      color: AppColors.gold,
                      fontSize: 15.sp,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
          SizedBox(height: 16),
          GestureDetector(
            onTap: () {
              Navigator.push(context, MaterialPageRoute(builder: (_) => OrdersPage()));
            },
            child: Container(
              padding: EdgeInsets.symmetric(horizontal: 24.w, vertical: 12.h),
              decoration: BoxDecoration(
                color: AppColors.gold.withOpacity(0.1),
                borderRadius: BorderRadius.circular(14.r),
                border: Border.all(color: AppColors.gold.withOpacity(0.25)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.receipt_long_rounded, color: AppColors.gold, size: 18),
                  SizedBox(width: 8),
                  Text(
                    'Просмотр заказов',
                    style: TextStyle(
                      color: AppColors.gold,
                      fontSize: 15.sp,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCartItemCard(BuildContext context, CartProvider cart, CartItem cartItem) {
    return Container(
      margin: EdgeInsets.only(bottom: 10.h),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.06),
        borderRadius: BorderRadius.circular(14.r),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
      ),
      child: Padding(
        padding: EdgeInsets.all(12.w),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12.r),
              child: _buildCartItemImage(cartItem),
            ),
            SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    cartItem.name,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 15.sp,
                      color: Colors.white.withOpacity(0.9),
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  SizedBox(height: 6),
                  if (cartItem.paymentMethod == PaymentMethod.points)
                    Text(
                      '${cartItem.unitPointsPrice} б. × ${cartItem.quantity} = ${cartItem.totalPointsPrice} баллов',
                      style: TextStyle(
                        color: Color(0xFFD4AF37),
                        fontSize: 13.sp,
                        fontWeight: FontWeight.w600,
                      ),
                      overflow: TextOverflow.ellipsis,
                    )
                  else
                    Text(
                      '${cartItem.unitPrice.toStringAsFixed(0)} × ${cartItem.quantity} = ${cartItem.totalPrice.toStringAsFixed(0)} руб.',
                      style: TextStyle(
                        color: AppColors.gold,
                        fontSize: 13.sp,
                        fontWeight: FontWeight.w600,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
            SizedBox(width: 8),
            Container(
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.06),
                borderRadius: BorderRadius.circular(12.r),
                border: Border.all(color: Colors.white.withOpacity(0.1)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildQtyButton(
                    icon: Icons.remove_rounded,
                    onTap: () => cart.decreaseQuantity(cartItem),
                  ),
                  SizedBox(
                    width: 28,
                    child: Text(
                      '${cartItem.quantity}',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 16.sp,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  _buildQtyButton(
                    icon: Icons.add_rounded,
                    onTap: () => cart.increaseQuantity(cartItem),
                  ),
                ],
              ),
            ),
            SizedBox(width: 6),
            GestureDetector(
              onTap: () => cart.removeItem(cartItem),
              child: Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(10.r),
                  border: Border.all(color: Colors.red.withOpacity(0.3)),
                ),
                child: Icon(Icons.delete_outline_rounded, color: Colors.red, size: 18),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQtyButton({required IconData icon, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10.r),
        ),
        child: Icon(icon, color: AppColors.gold, size: 20),
      ),
    );
  }

  Widget _buildBottomPanel(BuildContext context, CartProvider cart) {
    return Container(
      padding: EdgeInsets.fromLTRB(20.w, 16.h, 20.w, 16.h),
      decoration: BoxDecoration(
        color: AppColors.emeraldDark.withOpacity(0.9),
        border: Border(
          top: BorderSide(color: Colors.white.withOpacity(0.1)),
        ),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Итого:',
                style: TextStyle(
                  fontSize: 18.sp,
                  fontWeight: FontWeight.w600,
                  color: Colors.white.withOpacity(0.7),
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (cart.totalPrice > 0)
                    Container(
                      padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 8.h),
                      decoration: BoxDecoration(
                        color: AppColors.gold.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(12.r),
                        border: Border.all(color: AppColors.gold.withOpacity(0.3)),
                      ),
                      child: Text(
                        '${cart.totalPrice.toStringAsFixed(0)} руб.',
                        style: TextStyle(
                          fontSize: 22.sp,
                          fontWeight: FontWeight.bold,
                          color: AppColors.gold,
                        ),
                      ),
                    ),
                  if (cart.totalPointsPrice > 0) ...[
                    SizedBox(height: 6),
                    Container(
                      padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 6.h),
                      decoration: BoxDecoration(
                        color: Color(0xFFD4AF37).withOpacity(0.1),
                        borderRadius: BorderRadius.circular(10.r),
                        border: Border.all(color: Color(0xFFD4AF37).withOpacity(0.3)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.star_rounded, color: Color(0xFFD4AF37), size: 16),
                          SizedBox(width: 4),
                          Text(
                            '+ ${cart.totalPointsPrice} баллов',
                            style: TextStyle(
                              fontSize: 14.sp,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFFD4AF37),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
          SizedBox(height: 10),
          // Кнопка "Просмотр заказов"
          GestureDetector(
            onTap: () {
              Navigator.push(context, MaterialPageRoute(builder: (_) => OrdersPage()));
            },
            child: Container(
              width: double.infinity,
              padding: EdgeInsets.symmetric(vertical: 12.h),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.06),
                borderRadius: BorderRadius.circular(12.r),
                border: Border.all(color: Colors.white.withOpacity(0.12)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.receipt_long_rounded, size: 18, color: AppColors.gold),
                  SizedBox(width: 8),
                  Text(
                    'Просмотр заказов',
                    style: TextStyle(
                      fontSize: 14.sp,
                      fontWeight: FontWeight.w600,
                      color: AppColors.gold,
                    ),
                  ),
                ],
              ),
            ),
          ),
          SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: () {
                    if (cart.hasShopProducts) {
                      _showShopSelectionDialog(context, cart, null);
                    } else {
                      _showPickupTimeDialog(context, cart, null);
                    }
                  },
                  child: Container(
                    padding: EdgeInsets.symmetric(vertical: 14.h),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [AppColors.gold.withOpacity(0.9), AppColors.gold],
                      ),
                      borderRadius: BorderRadius.circular(14.r),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.gold.withOpacity(0.3),
                          blurRadius: 8,
                          offset: Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Center(
                      child: Text(
                        'Заказать',
                        style: TextStyle(
                          fontSize: 17.sp,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF1A1A1A),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              SizedBox(width: 12),
              Expanded(
                child: GestureDetector(
                  onTap: () => _showCommentDialogWithOrder(context, cart),
                  child: Container(
                    padding: EdgeInsets.symmetric(vertical: 14.h),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(14.r),
                      border: Border.all(color: Colors.white.withOpacity(0.15)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.message_outlined, size: 18, color: AppColors.gold),
                        SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            'Комментарий',
                            style: TextStyle(
                              fontSize: 14.sp,
                              fontWeight: FontWeight.w600,
                              color: Colors.white.withOpacity(0.8),
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _showPickupTimeDialog(BuildContext context, CartProvider cart, String? comment) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20.r),
        ),
        backgroundColor: AppColors.emeraldDark,
        title: Column(
          children: [
            Container(
              padding: EdgeInsets.all(14.w),
              decoration: BoxDecoration(
                color: AppColors.gold.withOpacity(0.15),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.access_time_rounded,
                size: 32,
                color: AppColors.gold,
              ),
            ),
            SizedBox(height: 12),
            Text(
              'Когда заберёте?',
              style: TextStyle(
                fontSize: 22.sp,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(child: _buildTimeOption(context, dialogContext, cart, comment, 5)),
                SizedBox(width: 12),
                Expanded(child: _buildTimeOption(context, dialogContext, cart, comment, 10)),
              ],
            ),
            SizedBox(height: 12),
            Row(
              children: [
                Expanded(child: _buildTimeOption(context, dialogContext, cart, comment, 15)),
                SizedBox(width: 12),
                Expanded(child: _buildTimeOption(context, dialogContext, cart, comment, 30)),
              ],
            ),
            SizedBox(height: 16),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(
                'Отмена',
                style: TextStyle(
                  fontSize: 16.sp,
                  color: Colors.white.withOpacity(0.5),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTimeOption(
    BuildContext context,
    BuildContext dialogContext,
    CartProvider cart,
    String? comment,
    int minutes,
  ) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () async {
          Navigator.of(dialogContext).pop();
          await _createOrderWithPickupTime(context, cart, comment, minutes);
        },
        borderRadius: BorderRadius.circular(16.r),
        child: Container(
          padding: EdgeInsets.symmetric(vertical: 20.h, horizontal: 16.w),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.06),
            borderRadius: BorderRadius.circular(16.r),
            border: Border.all(color: AppColors.gold.withOpacity(0.3)),
          ),
          child: Column(
            children: [
              Text(
                '$minutes',
                style: TextStyle(
                  fontSize: 28.sp,
                  fontWeight: FontWeight.bold,
                  color: AppColors.gold,
                ),
              ),
              Text(
                'мин',
                style: TextStyle(
                  fontSize: 14.sp,
                  color: Colors.white.withOpacity(0.5),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _createOrderWithPickupTime(
    BuildContext context,
    CartProvider cart,
    String? comment,
    int pickupMinutes,
  ) async {
    if (_isCreatingOrder) return; // Prevent double-tap
    setState(() => _isCreatingOrder = true);
    try {
      final orderProvider = OrderProvider.of(context);

      final pickupComment = 'Заберу через $pickupMinutes мин';
      final fullComment = comment != null && comment.isNotEmpty
          ? '$comment\n$pickupComment'
          : pickupComment;

      await orderProvider.createOrder(
        cart.items,
        cart.totalPrice,
        comment: fullComment,
        shopAddress: cart.selectedShopAddress,
      );

      if (!context.mounted) return;

      cart.clear();

      Navigator.of(context).pop();
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) => OrdersPage(),
        ),
      );

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(Icons.check_circle_rounded, color: Colors.white, size: 20),
              SizedBox(width: 10),
              Text('Заказ успешно создан!'),
            ],
          ),
          backgroundColor: AppColors.emerald,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.r)),
          margin: EdgeInsets.all(16.w),
          duration: Duration(seconds: 2),
        ),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Ошибка создания заказа: $e'),
          backgroundColor: Colors.red,
          duration: Duration(seconds: 3),
        ),
      );
    } finally {
      if (mounted) setState(() => _isCreatingOrder = false);
    }
  }

  void _showCommentDialogWithOrder(BuildContext context, CartProvider cart) {
    final TextEditingController controller = TextEditingController();

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20.r),
        ),
        backgroundColor: AppColors.emeraldDark,
        title: Row(
          children: [
            Container(
              padding: EdgeInsets.all(8.w),
              decoration: BoxDecoration(
                color: AppColors.gold.withOpacity(0.15),
                borderRadius: BorderRadius.circular(10.r),
              ),
              child: Icon(
                Icons.edit_note_rounded,
                size: 24,
                color: AppColors.gold,
              ),
            ),
            SizedBox(width: 12),
            Text(
              'Комментарий',
              style: TextStyle(
                fontSize: 20.sp,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: controller,
                  maxLines: 3,
                  style: TextStyle(color: Colors.white.withOpacity(0.9)),
                  cursorColor: AppColors.gold,
                  decoration: InputDecoration(
                    hintText: 'Напишите пожелания к заказу...',
                    hintStyle: TextStyle(color: Colors.white.withOpacity(0.3)),
                    filled: true,
                    fillColor: Colors.white.withOpacity(0.06),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12.r),
                      borderSide: BorderSide(color: Colors.white.withOpacity(0.1)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12.r),
                      borderSide: BorderSide(color: Colors.white.withOpacity(0.1)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12.r),
                      borderSide: BorderSide(color: AppColors.gold, width: 2),
                    ),
                    contentPadding: EdgeInsets.all(14.w),
                  ),
                ),
                SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: GestureDetector(
                        onTap: () {
                          Navigator.of(dialogContext).pop();
                          final comment = controller.text.trim().isEmpty
                              ? null
                              : controller.text.trim();
                          if (cart.hasShopProducts) {
                            _showShopSelectionDialog(context, cart, comment);
                          } else {
                            _showPickupTimeDialog(context, cart, comment);
                          }
                        },
                        child: Container(
                          height: 46,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [AppColors.gold.withOpacity(0.9), AppColors.gold],
                            ),
                            borderRadius: BorderRadius.circular(12.r),
                          ),
                          child: Center(
                            child: Text(
                              'Заказать',
                              style: TextStyle(
                                fontSize: 15.sp,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF1A1A1A),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    SizedBox(width: 10),
                    Expanded(
                      child: GestureDetector(
                        onTap: () => Navigator.of(dialogContext).pop(),
                        child: Container(
                          height: 46,
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.08),
                            borderRadius: BorderRadius.circular(12.r),
                            border: Border.all(color: Colors.white.withOpacity(0.15)),
                          ),
                          child: Center(
                            child: Text(
                              'Назад',
                              style: TextStyle(
                                fontSize: 15.sp,
                                fontWeight: FontWeight.bold,
                                color: Colors.white.withOpacity(0.7),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    ).then((_) => controller.dispose());
  }

  void _showCommentDialog(
    BuildContext context,
    String? initialComment,
    Function(String?) onSave,
  ) {
    final TextEditingController controller =
        TextEditingController(text: initialComment ?? '');

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(15.r),
        ),
        title: Text('Комментарий к заказу'),
        content: TextField(
          controller: controller,
          maxLines: 5,
          decoration: InputDecoration(
            hintText: 'Введите комментарий к заказу...',
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10.r),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text('Отмена'),
          ),
          ElevatedButton(
            onPressed: () {
              onSave(controller.text.trim().isEmpty ? null : controller.text.trim());
              Navigator.of(dialogContext).pop();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primaryGreen,
            ),
            child: Text('Готово'),
          ),
        ],
      ),
    ).then((_) => controller.dispose());
  }

  void _showShopSelectionDialog(BuildContext context, CartProvider cart, String? comment) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetCtx) => Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.75,
        ),
        decoration: BoxDecoration(
          color: AppColors.emeraldDark,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24.r)),
          border: Border.all(color: Colors.white.withOpacity(0.1)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle bar
            Center(
              child: Container(
                margin: EdgeInsets.only(top: 12),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            // Title
            Padding(
              padding: EdgeInsets.fromLTRB(20.w, 16.h, 20.w, 12.h),
              child: Row(
                children: [
                  Container(
                    padding: EdgeInsets.all(8.w),
                    decoration: BoxDecoration(
                      color: AppColors.gold.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(10.r),
                    ),
                    child: Icon(Icons.store_rounded, color: AppColors.gold, size: 22),
                  ),
                  SizedBox(width: 12),
                  Text(
                    'Выберите магазин',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 20.sp,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
            Divider(color: Colors.white.withOpacity(0.1), height: 1),
            // Shops list or loading indicator
            if (_shops.isEmpty)
              Padding(
                padding: EdgeInsets.all(32),
                child: Column(
                  children: [
                    CircularProgressIndicator(color: AppColors.gold),
                    SizedBox(height: 12),
                    Text(
                      'Загружаем список магазинов...',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.5),
                        fontSize: 14.sp,
                      ),
                    ),
                  ],
                ),
              )
            else
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 12.h),
                  itemCount: _shops.length,
                  itemBuilder: (_, index) {
                    final shop = _shops[index];
                    final isSelected = shop.address == _lastShopAddress;
                    return GestureDetector(
                      onTap: () async {
                        Navigator.of(sheetCtx).pop();
                        cart.setShopAddress(shop.address);
                        await _saveLastShop(shop.address);
                        if (context.mounted) {
                          await _createOrderForShop(context, cart, comment, shop.address);
                        }
                      },
                      child: Container(
                        margin: EdgeInsets.only(bottom: 8.h),
                        padding: EdgeInsets.all(14.w),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? AppColors.gold.withOpacity(0.12)
                              : Colors.white.withOpacity(0.05),
                          borderRadius: BorderRadius.circular(14.r),
                          border: Border.all(
                            color: isSelected
                                ? AppColors.gold.withOpacity(0.5)
                                : Colors.white.withOpacity(0.1),
                            width: isSelected ? 1.5 : 1,
                          ),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? AppColors.gold.withOpacity(0.15)
                                    : Colors.white.withOpacity(0.06),
                                borderRadius: BorderRadius.circular(10.r),
                              ),
                              child: Icon(
                                Icons.store_rounded,
                                color: isSelected ? AppColors.gold : Colors.white.withOpacity(0.5),
                                size: 20,
                              ),
                            ),
                            SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    shop.name,
                                    style: TextStyle(
                                      color: Colors.white.withOpacity(0.9),
                                      fontSize: 15.sp,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  if (shop.address.isNotEmpty) ...[
                                    SizedBox(height: 2),
                                    Text(
                                      shop.address,
                                      style: TextStyle(
                                        color: Colors.white.withOpacity(0.4),
                                        fontSize: 12.sp,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            if (isSelected)
                              Icon(Icons.check_circle_rounded, color: AppColors.gold, size: 22),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  Future<void> _createOrderForShop(
    BuildContext context,
    CartProvider cart,
    String? comment,
    String shopAddress,
  ) async {
    if (_isCreatingOrder) return; // Prevent double-tap
    setState(() => _isCreatingOrder = true);
    try {
      final orderProvider = OrderProvider.of(context);
      await orderProvider.createOrder(
        cart.items,
        cart.totalPrice,
        comment: comment,
        shopAddress: shopAddress,
      );
      if (!context.mounted) return;
      cart.clear();
      Navigator.of(context).pop();
      Navigator.of(context).push(
        MaterialPageRoute(builder: (context) => OrdersPage()),
      );
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(Icons.check_circle_rounded, color: Colors.white, size: 20),
              SizedBox(width: 10),
              Text('Заказ успешно создан!'),
            ],
          ),
          backgroundColor: AppColors.emerald,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.r)),
          margin: EdgeInsets.all(16.w),
          duration: Duration(seconds: 2),
        ),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Ошибка создания заказа: $e'),
          backgroundColor: Colors.red,
          duration: Duration(seconds: 3),
        ),
      );
    } finally {
      if (mounted) setState(() => _isCreatingOrder = false);
    }
  }
}
