import 'package:flutter/material.dart';
import '../../features/menu/pages/menu_groups_page.dart';
import '../../features/orders/pages/cart_page.dart';
import '../../features/orders/pages/orders_page.dart';
import '../../features/shops/pages/shops_on_map_page.dart';
import '../../features/shops/models/shop_model.dart';
import '../../features/loyalty/pages/loyalty_page.dart';
import '../../features/reviews/pages/review_type_selection_page.dart';
import '../../features/product_questions/pages/product_search_shop_selection_page.dart';
import '../../features/recipes/models/recipe_model.dart';
import '../../core/services/firebase_service.dart';
import '../../shared/dialogs/notification_required_dialog.dart';
import '../../core/utils/logger.dart';
import 'my_dialogs_page.dart';
import '../services/my_dialogs_counter_service.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

/// Страница клиентских функций для сотрудников
class ClientFunctionsPage extends StatefulWidget {
  const ClientFunctionsPage({super.key});

  @override
  State<ClientFunctionsPage> createState() => _ClientFunctionsPageState();
}

class _ClientFunctionsPageState extends State<ClientFunctionsPage> {
  static final Color _emerald = Color(0xFF1A4D4D);
  static final Color _emeraldDark = Color(0xFF0D2E2E);
  static final Color _night = Color(0xFF051515);

  int _myDialogsUnreadCount = 0;

  @override
  void initState() {
    super.initState();
    _loadMyDialogsCount();
  }

  Future<void> _loadMyDialogsCount() async {
    try {
      final count = await MyDialogsCounterService.getTotalUnreadCount();
      if (mounted) setState(() => _myDialogsUnreadCount = count);
    } catch (e) {
      Logger.error('Ошибка загрузки счётчика диалогов', e);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _night,
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [_emerald, _emeraldDark, _night],
            stops: [0.0, 0.3, 1.0],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              _buildAppBar(),
              Expanded(
                child: ListView(
                  padding: EdgeInsets.fromLTRB(20.w, 8.h, 20.w, 20.h),
                  children: [
                    _buildRow(
                      icon: Icons.coffee_outlined,
                      title: 'Меню',
                      onTap: () async {
                        final shop = await _showShopDialog(context);
                        if (!mounted || shop == null) return;
                        final cats = await _loadCategories(shop.address);
                        if (!mounted) return;
                        Navigator.push(context, MaterialPageRoute(
                          builder: (_) => MenuGroupsPage(groups: cats, selectedShop: shop.address),
                        ));
                      },
                    ),
                    _buildRow(
                      icon: Icons.shopping_bag_outlined,
                      title: 'Корзина',
                      onTap: () {
                        Navigator.push(context, MaterialPageRoute(builder: (_) => CartPage()));
                      },
                    ),
                    _buildRow(
                      icon: Icons.receipt_long_outlined,
                      title: 'Заказы',
                      onTap: () {
                        Navigator.push(context, MaterialPageRoute(builder: (_) => OrdersPage()));
                      },
                    ),
                    _buildRow(
                      icon: Icons.place_outlined,
                      title: 'Кофейни',
                      onTap: () {
                        Navigator.push(context, MaterialPageRoute(builder: (_) => ShopsOnMapPage()));
                      },
                    ),
                    _buildRow(
                      icon: Icons.card_membership_outlined,
                      title: 'Лояльность',
                      onTap: () async {
                        final enabled = await FirebaseService.areNotificationsEnabled();
                        if (!enabled && context.mounted) {
                          final result = await NotificationRequiredDialog.show(context);
                          if (result == true) {
                            await Future.delayed(Duration(milliseconds: 500));
                            final ok = await FirebaseService.areNotificationsEnabled();
                            if (ok && context.mounted) {
                              Navigator.push(context, MaterialPageRoute(builder: (_) => LoyaltyPage()));
                            }
                          }
                          return;
                        }
                        Navigator.push(context, MaterialPageRoute(builder: (_) => LoyaltyPage()));
                      },
                    ),
                    _buildRow(
                      icon: Icons.star_outline_rounded,
                      title: 'Отзывы',
                      onTap: () {
                        Navigator.push(context, MaterialPageRoute(builder: (_) => ReviewTypeSelectionPage()));
                      },
                    ),
                    _buildRow(
                      icon: Icons.chat_bubble_outline_rounded,
                      title: 'Диалоги',
                      badge: _myDialogsUnreadCount,
                      onTap: () async {
                        await Navigator.push(context, MaterialPageRoute(builder: (_) => MyDialogsPage()));
                        _loadMyDialogsCount();
                      },
                    ),
                    _buildRow(
                      icon: Icons.search_outlined,
                      title: 'Поиск товара',
                      onTap: () {
                        Navigator.push(context, MaterialPageRoute(builder: (_) => ProductSearchShopSelectionPage()));
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAppBar() {
    return Padding(
      padding: EdgeInsets.fromLTRB(8.w, 8.h, 24.w, 16.h),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.pop(context),
            icon: Icon(
              Icons.arrow_back_ios_new_rounded,
              color: Colors.white.withOpacity(0.8),
              size: 22,
            ),
          ),
          Expanded(
            child: Text(
              'Функции клиента',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                fontSize: 20.sp,
                fontWeight: FontWeight.w400,
                letterSpacing: 1,
              ),
            ),
          ),
          SizedBox(width: 48),
        ],
      ),
    );
  }

  Widget _buildRow({
    required IconData icon,
    required String title,
    int? badge,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: EdgeInsets.only(bottom: 12.h),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16.r),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16.r),
          splashColor: Colors.white.withOpacity(0.1),
          highlightColor: Colors.white.withOpacity(0.05),
          child: Container(
            padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 14.h),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16.r),
              border: Border.all(color: Colors.white.withOpacity(0.15)),
            ),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10.r),
                    color: Colors.white.withOpacity(0.1),
                  ),
                  child: Icon(
                    icon,
                    color: Colors.white.withOpacity(0.85),
                    size: 22,
                  ),
                ),
                SizedBox(width: 14),
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.9),
                      fontSize: 15.sp,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                ),
                if (badge != null && badge > 0)
                  Container(
                    padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 4.h),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12.r),
                    ),
                    child: Text(
                      badge > 99 ? '99+' : '$badge',
                      style: TextStyle(
                        color: _emerald,
                        fontSize: 13.sp,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  )
                else
                  Icon(
                    Icons.chevron_right_rounded,
                    color: Colors.white.withOpacity(0.4),
                    size: 24,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<Shop?> _showShopDialog(BuildContext context) async {
    try {
      final shops = await Shop.loadShopsFromServer();
      if (!context.mounted) return null;

      return showModalBottomSheet<Shop>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        backgroundColor: _emeraldDark,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20.r)),
        ),
        builder: (ctx) => DraggableScrollableSheet(
          initialChildSize: 0.9,
          minChildSize: 0.5,
          maxChildSize: 0.95,
          expand: false,
          builder: (context, scrollController) => Column(
            children: [
              // Ручка для перетаскивания
              Container(
                margin: EdgeInsets.only(top: 12.h, bottom: 8.h),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(2.r),
                ),
              ),
              // Заголовок
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 20.w, vertical: 16.h),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Выберите кофейню',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 20.sp,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(ctx),
                      icon: Icon(Icons.close, color: Colors.white.withOpacity(0.6)),
                    ),
                  ],
                ),
              ),
              Divider(color: Colors.white.withOpacity(0.1), height: 1),
              // Список магазинов
              Expanded(
                child: ListView.separated(
                  controller: scrollController,
                  padding: EdgeInsets.all(16.w),
                  itemCount: shops.length,
                  separatorBuilder: (_, __) => SizedBox(height: 8),
                  itemBuilder: (_, i) {
                    final shop = shops[i];
                    return Material(
                      color: Colors.transparent,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(12.r),
                        onTap: () => Navigator.pop(ctx, shop),
                        child: Container(
                          padding: EdgeInsets.all(16.w),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12.r),
                            border: Border.all(color: Colors.white.withOpacity(0.1)),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.place_outlined, color: Colors.white.withOpacity(0.6), size: 22),
                              SizedBox(width: 14),
                              Expanded(
                                child: Text(
                                  shop.address,
                                  style: TextStyle(
                                    color: Colors.white.withOpacity(0.85),
                                    fontSize: 15.sp,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      );
    } catch (e) {
      Logger.error('Ошибка загрузки магазинов', e);
      return null;
    }
  }

  Future<List<String>> _loadCategories(String address) async {
    try {
      final recipes = await Recipe.loadRecipesFromServer();
      return recipes.map((r) => r.category).where((c) => c.isNotEmpty).toSet().toList()..sort();
    } catch (e) {
      Logger.error('Ошибка загрузки категорий', e);
      return [];
    }
  }
}
