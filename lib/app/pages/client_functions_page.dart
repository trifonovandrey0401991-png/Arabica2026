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

/// Страница клиентских функций для сотрудников
class ClientFunctionsPage extends StatefulWidget {
  const ClientFunctionsPage({super.key});

  @override
  State<ClientFunctionsPage> createState() => _ClientFunctionsPageState();
}

class _ClientFunctionsPageState extends State<ClientFunctionsPage> {
  static const Color _emerald = Color(0xFF1A4D4D);
  static const Color _emeraldDark = Color(0xFF0D2E2E);
  static const Color _night = Color(0xFF051515);

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
        decoration: const BoxDecoration(
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
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
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
                        Navigator.push(context, MaterialPageRoute(builder: (_) => const CartPage()));
                      },
                    ),
                    _buildRow(
                      icon: Icons.receipt_long_outlined,
                      title: 'Заказы',
                      onTap: () {
                        Navigator.push(context, MaterialPageRoute(builder: (_) => const OrdersPage()));
                      },
                    ),
                    _buildRow(
                      icon: Icons.place_outlined,
                      title: 'Кофейни',
                      onTap: () {
                        Navigator.push(context, MaterialPageRoute(builder: (_) => const ShopsOnMapPage()));
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
                            await Future.delayed(const Duration(milliseconds: 500));
                            final ok = await FirebaseService.areNotificationsEnabled();
                            if (ok && context.mounted) {
                              Navigator.push(context, MaterialPageRoute(builder: (_) => const LoyaltyPage()));
                            }
                          }
                          return;
                        }
                        Navigator.push(context, MaterialPageRoute(builder: (_) => const LoyaltyPage()));
                      },
                    ),
                    _buildRow(
                      icon: Icons.star_outline_rounded,
                      title: 'Отзывы',
                      onTap: () {
                        Navigator.push(context, MaterialPageRoute(builder: (_) => const ReviewTypeSelectionPage()));
                      },
                    ),
                    _buildRow(
                      icon: Icons.chat_bubble_outline_rounded,
                      title: 'Диалоги',
                      badge: _myDialogsUnreadCount,
                      onTap: () async {
                        await Navigator.push(context, MaterialPageRoute(builder: (_) => const MyDialogsPage()));
                        _loadMyDialogsCount();
                      },
                    ),
                    _buildRow(
                      icon: Icons.search_outlined,
                      title: 'Поиск товара',
                      onTap: () {
                        Navigator.push(context, MaterialPageRoute(builder: (_) => const ProductSearchShopSelectionPage()));
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
      padding: const EdgeInsets.fromLTRB(8, 8, 24, 16),
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
          const Expanded(
            child: Text(
              'Функции клиента',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w400,
                letterSpacing: 1,
              ),
            ),
          ),
          const SizedBox(width: 48),
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
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          splashColor: Colors.white.withOpacity(0.1),
          highlightColor: Colors.white.withOpacity(0.05),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white.withOpacity(0.15)),
            ),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    color: Colors.white.withOpacity(0.1),
                  ),
                  child: Icon(
                    icon,
                    color: Colors.white.withOpacity(0.85),
                    size: 22,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.9),
                      fontSize: 15,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                ),
                if (badge != null && badge > 0)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      badge > 99 ? '99+' : '$badge',
                      style: TextStyle(
                        color: _emerald,
                        fontSize: 13,
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
      final shops = await Shop.loadShopsFromGoogleSheets();
      if (!context.mounted) return null;

      return showDialog<Shop>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: _emeraldDark,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: BorderSide(color: Colors.white.withOpacity(0.15)),
          ),
          title: const Text(
            'Выберите кофейню',
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w400,
            ),
          ),
          content: SizedBox(
            width: double.maxFinite,
            height: MediaQuery.of(context).size.height * 0.45,
            child: ListView.separated(
              itemCount: shops.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (_, i) {
                final shop = shops[i];
                return Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () => Navigator.pop(ctx, shop),
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.white.withOpacity(0.1)),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.place_outlined, color: Colors.white.withOpacity(0.6), size: 22),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Text(
                              shop.address,
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.85),
                                fontSize: 14,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
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
