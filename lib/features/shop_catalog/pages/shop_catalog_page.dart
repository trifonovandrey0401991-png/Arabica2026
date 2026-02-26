import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/services/base_http_service.dart';
import '../../../core/constants/api_constants.dart';
import '../../../core/utils/logger.dart';
import '../../../shared/providers/cart_provider.dart';
import '../../auth/services/auth_service.dart';
import '../../orders/pages/cart_page.dart';
import '../models/shop_product.dart';
import '../models/shop_product_group.dart';
import '../services/shop_catalog_service.dart';

/// Каталог товаров магазина для клиента.
/// Показывает группы → карточки с фото, поиск, цены.
class ShopCatalogPage extends StatefulWidget {
  /// null = auto-detect from server
  final bool? isWholesale;

  const ShopCatalogPage({super.key, this.isWholesale});

  @override
  State<ShopCatalogPage> createState() => _ShopCatalogPageState();
}

class _ShopCatalogPageState extends State<ShopCatalogPage> {
  static const _goldColor = Color(0xFFD4AF37);

  bool _loading = true;
  String? _error;
  List<ShopProductGroup> _groups = [];
  List<ShopProduct> _products = [];
  List<ShopProduct> _filtered = [];
  int _loyaltyPoints = 0;
  bool _isWholesale = false;
  String? _selectedGroupId; // null = all groups
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData({bool forceRefresh = false}) async {
    try {
      // Auto-detect wholesale from server if not explicitly set
      bool isWholesale = widget.isWholesale ?? false;
      if (widget.isWholesale == null) {
        isWholesale = await _detectWholesale();
      }
      _isWholesale = isWholesale;

      // 1) Try cache first (unless force refresh)
      if (!forceRefresh) {
        final cached = await ShopCatalogService.readCache();
        if (cached != null) {
          final filtered = _applyWholesaleFilter(cached.groups, cached.products, isWholesale);
          if (mounted) {
            setState(() {
              _groups = filtered.groups;
              _products = filtered.products;
              _filtered = filtered.products;
              _loading = false;
            });
          }
          _loadLoyaltyBalance();
          // Refresh from server in background (silently)
          _refreshFromServer(isWholesale);
          return;
        }
      }

      // 2) No cache or force refresh — load from server
      await _refreshFromServer(isWholesale, showLoading: true);
      _loadLoyaltyBalance();
    } catch (e) {
      Logger.error('ShopCatalog load error', e);
      if (mounted) setState(() { _error = e.toString(); _loading = false; });
    }
  }

  /// Fetch fresh data from server, update cache and UI
  Future<void> _refreshFromServer(bool isWholesale, {bool showLoading = false}) async {
    try {
      final results = await Future.wait([
        ShopCatalogService.getGroups(),
        ShopCatalogService.getProducts(active: true),
      ]);

      final allGroups = results[0] as List<ShopProductGroup>;
      final allProducts = results[1] as List<ShopProduct>;

      // Save raw data to cache (before filtering)
      ShopCatalogService.writeCache(allProducts, allGroups);

      final filtered = _applyWholesaleFilter(allGroups, allProducts, isWholesale);
      if (mounted) {
        setState(() {
          _groups = filtered.groups;
          _products = filtered.products;
          _loading = false;
          _applyFilters();
        });
      }
    } catch (e) {
      Logger.error('ShopCatalog server refresh error', e);
      // If we already have cached data shown, silently ignore the error
      if (_products.isEmpty && mounted) {
        setState(() { _error = e.toString(); _loading = false; });
      }
    }
  }

  /// Filter groups and products by wholesale visibility
  ({List<ShopProductGroup> groups, List<ShopProduct> products}) _applyWholesaleFilter(
    List<ShopProductGroup> groups, List<ShopProduct> products, bool isWholesale,
  ) {
    var filteredGroups = groups.toList();
    var filteredProducts = products.toList();

    if (!isWholesale) {
      final wholesaleGroupIds = filteredGroups
          .where((g) => g.visibility == 'wholesale_only')
          .map((g) => g.id)
          .toSet();
      filteredGroups = filteredGroups.where((g) => g.visibility != 'wholesale_only').toList();
      filteredProducts = filteredProducts.where((p) =>
          !p.isWholesale &&
          (p.groupId == null || !wholesaleGroupIds.contains(p.groupId))).toList();
    }
    filteredGroups = filteredGroups.where((g) => g.isActive).toList();

    return (groups: filteredGroups, products: filteredProducts);
  }

  Future<bool> _detectWholesale() async {
    try {
      final authService = AuthService();
      final session = await authService.getCurrentSession();
      if (session == null) return false;
      final phone = session.phone.replaceAll(RegExp(r'[^0-9]'), '');
      if (phone.isEmpty) return false;

      final prefs = await SharedPreferences.getInstance();
      final cacheKey = 'wholesale_status_$phone';

      final result = await BaseHttpService.getRaw(
        endpoint: '/api/loyalty/balance/$phone',
        timeout: ApiConstants.defaultTimeout,
      );
      if (result != null && result['success'] == true) {
        final value = result['isWholesale'] == true;
        await prefs.setBool(cacheKey, value);
        return value;
      }
      // Network failed — use last known value
      return prefs.getBool(cacheKey) ?? false;
    } catch (e) {
      Logger.error('Detect wholesale error', e);
    }
    return false;
  }

  Future<void> _loadLoyaltyBalance() async {
    try {
      final authService = AuthService();
      final session = await authService.getCurrentSession();
      if (session == null) return;
      final phone = session.phone.replaceAll(RegExp(r'[^0-9]'), '');
      if (phone.isEmpty) return;

      final result = await BaseHttpService.getRaw(
        endpoint: '/api/loyalty/balance/$phone',
        timeout: ApiConstants.defaultTimeout,
      );
      if (result != null && result['success'] == true) {
        final pts = (result['loyaltyPoints'] as num?)?.toInt() ?? 0;
        if (mounted) setState(() => _loyaltyPoints = pts);
      }
    } catch (e) {
      Logger.error('Load loyalty balance error', e);
    }
  }

  void _applyFilters() {
    setState(() {
      var result = _products.toList();

      // Filter by selected group
      if (_selectedGroupId != null) {
        result = result.where((p) => p.groupId == _selectedGroupId).toList();
      }

      // Filter by search query
      if (_searchQuery.isNotEmpty) {
        final q = _searchQuery.toLowerCase();
        result = result.where((p) {
          if (p.name.toLowerCase().contains(q)) return true;
          if (p.description.toLowerCase().contains(q)) return true;
          return false;
        }).toList();
      }

      _filtered = result;
    });
  }

  List<ShopProduct> _productsForGroup(String groupId) {
    return _filtered.where((p) => p.groupId == groupId).toList();
  }

  List<ShopProduct> _ungroupedProducts() {
    final groupIds = _groups.map((g) => g.id).toSet();
    return _filtered.where((p) => p.groupId == null || !groupIds.contains(p.groupId)).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.night,
      appBar: AppBar(
        backgroundColor: AppColors.emeraldDark,
        title: Text('Магазин', style: TextStyle(color: Colors.white)),
        iconTheme: IconThemeData(color: Colors.white),
      ),
      body: _loading
          ? Center(child: CircularProgressIndicator(color: _goldColor))
          : _error != null
              ? _buildError()
              : _buildCatalog(),
    );
  }

  Widget _buildError() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.error_outline, color: Colors.red.shade300, size: 48),
          SizedBox(height: 16),
          Text(_error ?? '', style: TextStyle(color: Colors.white), textAlign: TextAlign.center),
          SizedBox(height: 16),
          ElevatedButton(
            onPressed: () { setState(() { _error = null; _loading = true; }); _loadData(forceRefresh: true); },
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.emerald),
            child: Text('Обновить', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Widget _buildCatalog() {
    final cart = CartProvider.of(context);
    return Column(
      children: [
        _buildSearchBar(),
        Expanded(
          child: _filtered.isEmpty
              ? Center(child: Text(
                  _products.isEmpty ? 'Товаров пока нет' : 'Ничего не найдено',
                  style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 15.sp),
                ))
              : RefreshIndicator(
                  onRefresh: () => _loadData(forceRefresh: true),
                  color: _goldColor,
                  child: ListView(
                    padding: EdgeInsets.only(bottom: 16.h),
                    children: [
                      for (final group in _groups)
                        if (_productsForGroup(group.id).isNotEmpty)
                          _buildGroupSection(group, _productsForGroup(group.id)),
                      if (_ungroupedProducts().isNotEmpty)
                        _buildGroupSection(null, _ungroupedProducts()),
                    ],
                  ),
                ),
        ),
        _buildBottomCartBar(cart),
      ],
    );
  }

  Widget _buildSearchBar() {
    // Current group name for the filter button
    final groupName = _selectedGroupId == null
        ? 'Все'
        : _groups.where((g) => g.id == _selectedGroupId).firstOrNull?.name ?? 'Все';

    return Padding(
      padding: EdgeInsets.fromLTRB(12.w, 8.h, 12.w, 4.h),
      child: Row(
        children: [
          // Search field
          Expanded(
            flex: 2,
            child: TextField(
              style: TextStyle(color: Colors.white, fontSize: 13.sp),
              decoration: InputDecoration(
                hintText: 'Поиск...',
                hintStyle: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 13.sp),
                prefixIcon: Icon(Icons.search_rounded, color: Colors.white.withOpacity(0.4), size: 20),
                filled: true,
                fillColor: Colors.white.withOpacity(0.08),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12.r), borderSide: BorderSide.none),
                contentPadding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 10.h),
                isDense: true,
              ),
              onChanged: (q) {
                _searchQuery = q;
                _applyFilters();
              },
            ),
          ),
          SizedBox(width: 8.w),
          // Group filter button
          Expanded(
            flex: 1,
            child: GestureDetector(
              onTapDown: (details) => _showGroupMenu(details.globalPosition),
              child: Container(
                height: 42,
                padding: EdgeInsets.symmetric(horizontal: 8.w),
                decoration: BoxDecoration(
                  color: _selectedGroupId != null
                      ? AppColors.emerald.withOpacity(0.3)
                      : Colors.white.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(12.r),
                  border: _selectedGroupId != null
                      ? Border.all(color: AppColors.emerald.withOpacity(0.5))
                      : null,
                ),
                child: Row(
                  children: [
                    Icon(Icons.filter_list_rounded, color: Colors.white.withOpacity(0.6), size: 16),
                    SizedBox(width: 4.w),
                    Expanded(
                      child: Text(
                        groupName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: Colors.white.withOpacity(0.8), fontSize: 11.sp),
                      ),
                    ),
                    Icon(Icons.arrow_drop_down_rounded, color: Colors.white.withOpacity(0.4), size: 18),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showGroupMenu(Offset position) {
    // Use '__all__' as sentinel for "show all groups"
    const allValue = '__all__';
    final items = <PopupMenuEntry<String>>[];

    // "All" option
    items.add(PopupMenuItem<String>(
      value: allValue,
      child: Text('Все', style: TextStyle(
        color: Colors.white,
        fontWeight: _selectedGroupId == null ? FontWeight.bold : FontWeight.normal,
      )),
    ));

    // Each group
    for (final group in _groups) {
      final count = _products.where((p) => p.groupId == group.id).length;
      items.add(PopupMenuItem<String>(
        value: group.id,
        child: Row(
          children: [
            Expanded(child: Text(group.name, style: TextStyle(
              color: Colors.white,
              fontWeight: _selectedGroupId == group.id ? FontWeight.bold : FontWeight.normal,
            ))),
            Text('$count', style: TextStyle(color: Colors.white54, fontSize: 12)),
          ],
        ),
      ));
    }

    showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(position.dx, position.dy, position.dx + 1, position.dy + 1),
      items: items,
      color: AppColors.emeraldDark,
    ).then((value) {
      if (value == null) return; // dismissed without selection
      final newGroupId = value == allValue ? null : value;
      if (newGroupId != _selectedGroupId) {
        _selectedGroupId = newGroupId;
        _applyFilters();
      }
    });
  }

  Widget _buildGroupSection(ShopProductGroup? group, List<ShopProduct> items) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(16.w, 12.h, 16.w, 6.h),
          child: Row(
            children: [
              Icon(Icons.storefront_rounded, color: _goldColor.withOpacity(0.6), size: 16),
              SizedBox(width: 6),
              Text(
                group?.name ?? 'Другое',
                style: TextStyle(color: Colors.white.withOpacity(0.8), fontSize: 14.sp, fontWeight: FontWeight.w600),
              ),
              if (group != null && group.isWholesaleOnly) ...[
                SizedBox(width: 6),
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                  decoration: BoxDecoration(color: Colors.orange.withOpacity(0.3), borderRadius: BorderRadius.circular(6)),
                  child: Text('Опт', style: TextStyle(color: Colors.orange, fontSize: 9.sp)),
                ),
              ],
              SizedBox(width: 6),
              Container(
                padding: EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(color: AppColors.emerald.withOpacity(0.3), borderRadius: BorderRadius.circular(8)),
                child: Text('${items.length}', style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 10.sp)),
              ),
            ],
          ),
        ),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: 10.w),
          child: GridView.builder(
            shrinkWrap: true,
            physics: NeverScrollableScrollPhysics(),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              crossAxisSpacing: 8,
              mainAxisSpacing: 8,
              childAspectRatio: 0.55,
            ),
            itemCount: items.length,
            itemBuilder: (context, i) => _buildProductTile(items[i]),
          ),
        ),
      ],
    );
  }

  /// Product tile: photo card + quantity controls below
  Widget _buildProductTile(ShopProduct product) {
    final cart = CartProvider.of(context);
    final qty = cart.getShopProductQuantity(product.id);

    // Primary price for badge
    final String priceText;
    if (_isWholesale && product.priceWholesale != null) {
      priceText = '${product.priceWholesale!.toStringAsFixed(0)} руб.';
    } else if (product.priceRetail != null) {
      priceText = '${product.priceRetail!.toStringAsFixed(0)} руб.';
    } else if (product.pricePoints != null) {
      priceText = '${product.pricePoints} балл.';
    } else {
      priceText = '';
    }

    return Column(
      children: [
        // Photo card (like drinks menu)
        Expanded(
          child: GestureDetector(
            onTap: () => _showProductDetail(product),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14.r),
                border: Border.all(color: _goldColor, width: 1.5),
                boxShadow: [
                  BoxShadow(color: _goldColor.withOpacity(0.15), blurRadius: 8, offset: Offset(0, 3)),
                  BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 8, offset: Offset(0, 4)),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(14.r),
                child: Stack(
                  children: [
                    Positioned.fill(child: _buildProductImage(product)),
                    // Bottom gradient
                    Positioned(
                      bottom: 0, left: 0, right: 0,
                      child: Container(
                        height: 50,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter, end: Alignment.bottomCenter,
                            colors: [Colors.transparent, Colors.black.withOpacity(0.8)],
                          ),
                        ),
                      ),
                    ),
                    // Price badge top-right
                    if (priceText.isNotEmpty)
                      Positioned(
                        top: 4.h, right: 4.w,
                        child: Container(
                          padding: EdgeInsets.symmetric(horizontal: 5.w, vertical: 2.h),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(colors: [AppColors.primaryGreen, Color(0xFF00695C)]),
                            borderRadius: BorderRadius.circular(8.r),
                            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 4, offset: Offset(0, 2))],
                          ),
                          child: Text(priceText, style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 9.sp)),
                        ),
                      ),
                    // Points badge below price
                    if (product.pricePoints != null && product.priceRetail != null)
                      Positioned(
                        top: 24.h, right: 4.w,
                        child: Container(
                          padding: EdgeInsets.symmetric(horizontal: 4.w, vertical: 2.h),
                          decoration: BoxDecoration(
                            color: _goldColor.withOpacity(0.9),
                            borderRadius: BorderRadius.circular(6.r),
                          ),
                          child: Text('${product.pricePoints} б.', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 8.sp)),
                        ),
                      ),
                    // Name at bottom
                    Positioned(
                      bottom: 6.h, left: 6.w, right: 6.w,
                      child: Text(
                        product.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: Colors.white, fontSize: 10.sp, fontWeight: FontWeight.w600, shadows: [Shadow(color: Colors.black54, blurRadius: 4)]),
                      ),
                    ),
                    // Cart quantity badge top-left
                    if (qty > 0)
                      Positioned(
                        top: 4.h, left: 4.w,
                        child: Container(
                          padding: EdgeInsets.all(4.w),
                          decoration: BoxDecoration(
                            color: AppColors.emerald,
                            borderRadius: BorderRadius.circular(8.r),
                            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 4, offset: Offset(0, 2))],
                          ),
                          child: Text('$qty', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 10.sp)),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
        SizedBox(height: 4),
        // Quantity controls: [-] [qty] [+]
        _buildQuantityControls(product, qty),
      ],
    );
  }

  Widget _buildQuantityControls(ShopProduct product, int qty) {
    final cart = CartProvider.of(context);
    return Container(
      height: 30,
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.08),
        borderRadius: BorderRadius.circular(8.r),
        border: Border.all(color: Colors.white.withOpacity(0.15)),
      ),
      child: Row(
        children: [
          // Minus button
          Expanded(
            child: GestureDetector(
              onTap: qty > 0 ? () {
                cart.decreaseShopProduct(product.id);
                if (mounted) setState(() {});
              } : null,
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.horizontal(left: Radius.circular(8.r)),
                  color: qty > 0 ? Colors.red.withOpacity(0.2) : Colors.transparent,
                ),
                child: Center(
                  child: Icon(Icons.remove_rounded, color: qty > 0 ? Colors.red.shade300 : Colors.white.withOpacity(0.2), size: 16),
                ),
              ),
            ),
          ),
          // Quantity display (tappable for manual input)
          GestureDetector(
            onTap: () => _showQuantityInput(product, qty),
            child: Container(
              width: 32,
              decoration: BoxDecoration(
                border: Border.symmetric(vertical: BorderSide(color: Colors.white.withOpacity(0.15))),
              ),
              child: Center(
                child: Text(
                  '$qty',
                  style: TextStyle(
                    color: qty > 0 ? Colors.white : Colors.white.withOpacity(0.3),
                    fontWeight: FontWeight.bold,
                    fontSize: 11.sp,
                  ),
                ),
              ),
            ),
          ),
          // Plus button
          Expanded(
            child: GestureDetector(
              onTap: () {
                cart.addShopProduct(product);
                if (mounted) setState(() {});
              },
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.horizontal(right: Radius.circular(8.r)),
                  color: AppColors.emerald.withOpacity(0.3),
                ),
                child: Center(
                  child: Icon(Icons.add_rounded, color: AppColors.emerald, size: 16),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showQuantityInput(ShopProduct product, int currentQty) {
    final controller = TextEditingController(text: currentQty > 0 ? '$currentQty' : '');
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.night,
        title: Text('Количество', style: TextStyle(color: Colors.white, fontSize: 16.sp)),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          autofocus: true,
          style: TextStyle(color: Colors.white, fontSize: 18.sp),
          decoration: InputDecoration(
            hintText: '0',
            hintStyle: TextStyle(color: Colors.white.withOpacity(0.3)),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12.r)),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12.r),
              borderSide: BorderSide(color: Colors.white.withOpacity(0.2)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12.r),
              borderSide: BorderSide(color: AppColors.emerald),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Отмена', style: TextStyle(color: Colors.white.withOpacity(0.5))),
          ),
          ElevatedButton(
            onPressed: () {
              final val = int.tryParse(controller.text) ?? 0;
              final cart = CartProvider.of(context);
              cart.setShopProductQuantity(product, val);
              if (mounted) setState(() {});
              Navigator.pop(ctx);
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.emerald),
            child: Text('ОК', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomCartBar(CartProvider cart) {
    final totalItems = cart.itemCount;
    final totalMoney = cart.totalPrice;
    final hasItems = totalItems > 0;

    return Container(
      padding: EdgeInsets.fromLTRB(16.w, 12.h, 16.w, 16.h),
      decoration: BoxDecoration(
        color: AppColors.emeraldDark,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20.r)),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 12, offset: Offset(0, -4))],
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          width: double.infinity,
          height: 50,
          child: ElevatedButton(
            onPressed: hasItems ? () => _showCartSummary(cart) : null,
            style: ElevatedButton.styleFrom(
              backgroundColor: hasItems ? AppColors.emerald : Colors.white.withOpacity(0.1),
              foregroundColor: Colors.white,
              disabledBackgroundColor: Colors.white.withOpacity(0.05),
              disabledForegroundColor: Colors.white.withOpacity(0.3),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14.r)),
              elevation: hasItems ? 4 : 0,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.shopping_cart_rounded, size: 22),
                SizedBox(width: 10),
                Text(
                  hasItems
                      ? 'Корзина ($totalItems)  •  ${totalMoney.toStringAsFixed(0)} руб.'
                      : 'Корзина пуста',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showCartSummary(CartProvider cart) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => _CartSummarySheet(
        cart: cart,
        loyaltyPoints: _loyaltyPoints,
        onGoToCart: () {
          Navigator.pop(ctx);
          Navigator.push(context, MaterialPageRoute(builder: (_) => const CartPage()));
        },
        onBack: () => Navigator.pop(ctx),
      ),
    );
  }

  Widget _buildProductImage(ShopProduct product) {
    final url = product.firstPhotoUrl;
    if (url == null) {
      return Container(
        color: AppColors.emeraldDark,
        child: Center(child: Icon(Icons.shopping_bag_rounded, color: Colors.white.withOpacity(0.3), size: 48)),
      );
    }
    return CachedNetworkImage(
      imageUrl: url,
      fit: BoxFit.cover,
      placeholder: (_, __) => Container(
        color: AppColors.emeraldDark,
        child: Center(child: CircularProgressIndicator(color: _goldColor, strokeWidth: 2)),
      ),
      errorWidget: (_, __, ___) => Container(
        color: AppColors.emeraldDark,
        child: Center(child: Icon(Icons.broken_image_rounded, color: Colors.white.withOpacity(0.3), size: 48)),
      ),
    );
  }

  void _showProductDetail(ShopProduct product) {
    showDialog(
      context: context,
      builder: (_) => _ProductDetailDialog(
        product: product,
        isWholesale: _isWholesale,
        onAddToCart: () {
          final cart = CartProvider.of(context);
          cart.addShopProduct(product);
          if (mounted) setState(() {});
        },
      ),
    );
  }
}

// ================ CART SUMMARY BOTTOM SHEET ================

class _CartSummarySheet extends StatelessWidget {
  final CartProvider cart;
  final int loyaltyPoints;
  final VoidCallback onGoToCart;
  final VoidCallback onBack;

  static const _goldColor = Color(0xFFD4AF37);

  const _CartSummarySheet({
    required this.cart,
    required this.loyaltyPoints,
    required this.onGoToCart,
    required this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    final items = cart.items;
    final totalMoney = cart.totalPrice;
    final totalPoints = cart.totalPointsPrice;

    // Calculate total points needed if ALL items were paid with points
    int totalPointsNeeded = 0;
    for (final item in items) {
      if (item.type == CartItemType.shopProduct && item.shopProduct?.pricePoints != null) {
        totalPointsNeeded += item.shopProduct!.pricePoints! * item.quantity;
      }
    }
    final hasEnoughPoints = loyaltyPoints >= totalPointsNeeded && totalPointsNeeded > 0;

    return Container(
      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.7),
      decoration: BoxDecoration(
        color: AppColors.night,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24.r)),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle
          Center(
            child: Container(
              margin: EdgeInsets.only(top: 12),
              width: 40, height: 4,
              decoration: BoxDecoration(color: Colors.white.withOpacity(0.3), borderRadius: BorderRadius.circular(2)),
            ),
          ),
          // Title
          Padding(
            padding: EdgeInsets.fromLTRB(20.w, 16.h, 20.w, 8.h),
            child: Row(
              children: [
                Icon(Icons.shopping_cart_rounded, color: Colors.white, size: 22),
                SizedBox(width: 10),
                Text('Ваш заказ', style: TextStyle(color: Colors.white, fontSize: 18.sp, fontWeight: FontWeight.bold)),
                Spacer(),
                Text('${cart.itemCount} шт.', style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 14.sp)),
              ],
            ),
          ),
          Divider(color: Colors.white.withOpacity(0.1), height: 1),
          // Items list
          Flexible(
            child: ListView.builder(
              shrinkWrap: true,
              padding: EdgeInsets.symmetric(horizontal: 20.w, vertical: 8.h),
              itemCount: items.length,
              itemBuilder: (_, i) {
                final item = items[i];
                return Padding(
                  padding: EdgeInsets.symmetric(vertical: 6.h),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(item.name, style: TextStyle(color: Colors.white, fontSize: 14.sp, fontWeight: FontWeight.w500)),
                            if (item.paymentMethod == PaymentMethod.points)
                              Text('за баллы', style: TextStyle(color: _goldColor, fontSize: 11.sp)),
                          ],
                        ),
                      ),
                      Text('x${item.quantity}', style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 13.sp)),
                      SizedBox(width: 12),
                      Text(
                        item.paymentMethod == PaymentMethod.points
                            ? '${item.totalPointsPrice} балл.'
                            : '${item.totalPrice.toStringAsFixed(0)} руб.',
                        style: TextStyle(color: Colors.white, fontSize: 14.sp, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
          Divider(color: Colors.white.withOpacity(0.1), height: 1),
          // Totals
          Padding(
            padding: EdgeInsets.fromLTRB(20.w, 12.h, 20.w, 4.h),
            child: Column(
              children: [
                if (totalMoney > 0)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Итого:', style: TextStyle(color: Colors.white, fontSize: 16.sp, fontWeight: FontWeight.bold)),
                      Text('${totalMoney.toStringAsFixed(0)} руб.', style: TextStyle(color: AppColors.emerald, fontSize: 18.sp, fontWeight: FontWeight.bold)),
                    ],
                  ),
                if (totalPoints > 0)
                  Padding(
                    padding: EdgeInsets.only(top: 4),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('За баллы:', style: TextStyle(color: _goldColor, fontSize: 14.sp)),
                        Text('$totalPoints балл.', style: TextStyle(color: _goldColor, fontSize: 16.sp, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
                // Loyalty balance info
                Padding(
                  padding: EdgeInsets.only(top: 6),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Ваш баланс:', style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 12.sp)),
                      Text('$loyaltyPoints балл.', style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 12.sp)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          // Buttons
          Padding(
            padding: EdgeInsets.fromLTRB(20.w, 12.h, 20.w, 20.h),
            child: Column(
              children: [
                // "Оплатить за баллы" button
                if (totalPointsNeeded > 0)
                  Padding(
                    padding: EdgeInsets.only(bottom: 8),
                    child: SizedBox(
                      width: double.infinity,
                      height: 46,
                      child: ElevatedButton.icon(
                        onPressed: hasEnoughPoints ? () {
                          // Switch all shop products to points payment
                          for (final item in cart.items) {
                            if (item.type == CartItemType.shopProduct && item.shopProduct?.pricePoints != null) {
                              // Re-add with points payment
                              cart.setShopProductQuantity(item.shopProduct!, 0);
                              cart.setShopProductQuantity(item.shopProduct!, item.quantity, paymentMethod: PaymentMethod.points);
                            }
                          }
                          onGoToCart();
                        } : null,
                        icon: Icon(Icons.star_rounded, size: 20),
                        label: Text(
                          hasEnoughPoints
                              ? 'Оплатить за баллы ($totalPointsNeeded балл.)'
                              : 'Недостаточно баллов (нужно $totalPointsNeeded)',
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: hasEnoughPoints ? _goldColor : Colors.grey.shade800,
                          foregroundColor: Colors.white,
                          disabledBackgroundColor: Colors.grey.shade800,
                          disabledForegroundColor: Colors.white.withOpacity(0.4),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.r)),
                        ),
                      ),
                    ),
                  ),
                // Two buttons row: Вернуться + Перейти в корзину
                Row(
                  children: [
                    Expanded(
                      child: SizedBox(
                        height: 46,
                        child: OutlinedButton(
                          onPressed: onBack,
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white,
                            side: BorderSide(color: Colors.white.withOpacity(0.3)),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.r)),
                          ),
                          child: Text('Вернуться', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                        ),
                      ),
                    ),
                    SizedBox(width: 12),
                    Expanded(
                      child: SizedBox(
                        height: 46,
                        child: ElevatedButton(
                          onPressed: onGoToCart,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.emerald,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.r)),
                          ),
                          child: Text('В корзину', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ================ PRODUCT DETAIL DIALOG ================

class _ProductDetailDialog extends StatefulWidget {
  final ShopProduct product;
  final bool isWholesale;
  final VoidCallback onAddToCart;

  const _ProductDetailDialog({
    required this.product,
    required this.isWholesale,
    required this.onAddToCart,
  });

  @override
  State<_ProductDetailDialog> createState() => _ProductDetailDialogState();
}

class _ProductDetailDialogState extends State<_ProductDetailDialog> {
  static const _goldColor = Color(0xFFD4AF37);
  int _currentPhoto = 0;
  late final PageController _pageController;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final product = widget.product;
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: EdgeInsets.symmetric(horizontal: 20.w, vertical: 40.h),
      child: Container(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.75),
        decoration: BoxDecoration(
          color: AppColors.night,
          borderRadius: BorderRadius.circular(20.r),
          border: Border.all(color: Colors.white.withOpacity(0.1)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Photo area
            ClipRRect(
              borderRadius: BorderRadius.vertical(top: Radius.circular(20.r)),
              child: SizedBox(
                height: 250.h,
                child: product.photos.isEmpty
                    ? Container(
                        color: AppColors.emeraldDark,
                        child: Center(child: Icon(Icons.shopping_bag_rounded, color: Colors.white.withOpacity(0.3), size: 64)),
                      )
                    : Stack(
                        children: [
                          PageView.builder(
                            controller: _pageController,
                            itemCount: product.photos.length,
                            onPageChanged: (i) { if (mounted) setState(() => _currentPhoto = i); },
                            itemBuilder: (_, i) {
                              final url = product.getPhotoUrl(i);
                              if (url == null) return SizedBox();
                              return CachedNetworkImage(imageUrl: url, fit: BoxFit.cover, width: double.infinity);
                            },
                          ),
                          if (product.photos.length > 1)
                            Positioned(
                              bottom: 10, left: 0, right: 0,
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: List.generate(product.photos.length, (i) => Container(
                                  width: 8, height: 8,
                                  margin: EdgeInsets.symmetric(horizontal: 3),
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: _currentPhoto == i ? Colors.white : Colors.white.withOpacity(0.4),
                                  ),
                                )),
                              ),
                            ),
                        ],
                      ),
              ),
            ),
            // Info
            Padding(
              padding: EdgeInsets.all(16.w),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(product.name, style: TextStyle(color: Colors.white, fontSize: 18.sp, fontWeight: FontWeight.bold)),
                  if (product.description.isNotEmpty) ...[
                    SizedBox(height: 8),
                    Text(product.description, style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 14.sp)),
                  ],
                  SizedBox(height: 16),
                  if (product.priceRetail != null)
                    _priceRow('Розница', '${product.priceRetail!.toStringAsFixed(0)} руб.', AppColors.primaryGreen),
                  if (widget.isWholesale && product.priceWholesale != null)
                    _priceRow('Опт', '${product.priceWholesale!.toStringAsFixed(0)} руб.', Colors.orange),
                  if (product.pricePoints != null)
                    _priceRow('Баллы', '${product.pricePoints}', _goldColor),
                  SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    height: 46,
                    child: ElevatedButton.icon(
                      onPressed: () { widget.onAddToCart(); Navigator.pop(context); },
                      icon: Icon(Icons.add_shopping_cart_rounded, size: 20),
                      label: Text('Добавить в корзину', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.emerald,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.r)),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _priceRow(String label, String value, Color color) {
    return Padding(
      padding: EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Text('$label: ', style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 14.sp)),
          Text(value, style: TextStyle(color: color, fontSize: 16.sp, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}
