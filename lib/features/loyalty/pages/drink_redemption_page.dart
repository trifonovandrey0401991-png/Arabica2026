import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../../core/theme/app_colors.dart';

import '../../../core/utils/logger.dart';
import '../services/loyalty_service.dart';
import '../../recipes/models/recipe_model.dart';
import '../../recipes/services/recipe_service.dart';
import '../../../shared/widgets/app_cached_image.dart';

/// Экран выбора напитка за баллы лояльности.
/// Клиент видит каталог напитков → выбирает → получает QR-код →
/// сотрудник сканирует → подтверждает → баллы списываются.
class DrinkRedemptionPage extends StatefulWidget {
  const DrinkRedemptionPage({super.key});

  @override
  State<DrinkRedemptionPage> createState() => _DrinkRedemptionPageState();
}

class _DrinkRedemptionPageState extends State<DrinkRedemptionPage> {
  static const _primaryColor = AppColors.emerald;
  static const _goldColor = Color(0xFFD4AF37);

  bool _loading = true;
  String? _error;
  List<Recipe> _drinks = [];
  List<Recipe> _filtered = [];

  int _balance = 0;
  String? _clientPhone;
  String _searchQuery = '';
  String? _selectedCategory; // null = all categories

  // QR state
  String? _qrToken;
  String? _selectedDrinkName;
  int? _selectedPointsPrice;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _clientPhone = prefs.getString('user_phone');
      if (_clientPhone == null) {
        if (mounted) setState(() { _error = 'Не удалось получить данные клиента'; _loading = false; });
        return;
      }

      // Load balance and recipes in parallel
      final balanceFuture = LoyaltyService.fetchWalletBalance(_clientPhone!);
      final recipesFuture = RecipeService.getRecipes();

      final results = await Future.wait([balanceFuture, recipesFuture]);

      final balanceData = results[0] as Map<String, dynamic>;
      final allRecipes = results[1] as List<Recipe>;

      // Filter only recipes that have pointsPrice set
      final drinksWithPoints = allRecipes.where((r) => r.pointsPrice != null && r.pointsPrice! > 0).toList();

      if (mounted) {
        setState(() {
          _balance = (balanceData['loyaltyPoints'] as num?)?.toInt() ?? 0;
          _drinks = drinksWithPoints;
          _filtered = drinksWithPoints;
          _loading = false;
        });
      }
    } catch (e) {
      Logger.error('DrinkRedemption load error', e);
      if (mounted) setState(() { _error = e.toString(); _loading = false; });
    }
  }

  void _applyFilters() {
    setState(() {
      var result = _drinks.toList();

      // Filter by selected category
      if (_selectedCategory != null) {
        result = result.where((r) => r.category == _selectedCategory).toList();
      }

      // Filter by search query
      if (_searchQuery.isNotEmpty) {
        final q = _searchQuery.toLowerCase();
        result = result.where((r) =>
            r.name.toLowerCase().contains(q)).toList();
      }

      _filtered = result;
    });
  }

  Future<void> _onDrinkTap(Recipe drink) async {
    if (drink.pointsPrice == null) return;

    final pointsPrice = drink.pointsPrice!;

    if (_balance < pointsPrice) {
      final deficit = pointsPrice - _balance;
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Недостаточно баллов. Нужно ещё $deficit'),
          behavior: SnackBarBehavior.floating,
          backgroundColor: Colors.red.shade700,
        ),
      );
      return;
    }

    // Confirmation dialog
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.emeraldDark,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20.r)),
        title: Text('Обменять баллы?', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(drink.name, style: TextStyle(color: _goldColor, fontSize: 18.sp, fontWeight: FontWeight.w600)),
            SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.star_rounded, color: _goldColor, size: 20),
                SizedBox(width: 4),
                Text('$pointsPrice баллов', style: TextStyle(color: Colors.white, fontSize: 16.sp)),
              ],
            ),
            SizedBox(height: 8),
            Text('Баланс после: ${_balance - pointsPrice}',
                style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 13.sp)),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Отмена', style: TextStyle(color: Colors.white.withOpacity(0.6))),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: _goldColor,
              foregroundColor: Colors.black,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.r)),
            ),
            child: Text('Обменять'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    // Create redemption and get QR
    try {
      setState(() => _loading = true);

      final result = await LoyaltyService.redeemDrink(
        clientPhone: _clientPhone!,
        recipeId: drink.id,
        recipeName: drink.name,
        pointsPrice: pointsPrice,
      );

      if (mounted) {
        setState(() {
          _qrToken = result['qrToken'] as String?;
          _selectedDrinkName = drink.name;
          _selectedPointsPrice = pointsPrice;
          _loading = false;
        });
      }
    } catch (e) {
      Logger.error('Redeem drink error', e);
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка: ${e.toString().replaceFirst('Exception: ', '')}'),
            behavior: SnackBarBehavior.floating,
            backgroundColor: Colors.red.shade700,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.primaryGreen,
      appBar: AppBar(
        title: Text('Бесплатный напиток', style: TextStyle(fontWeight: FontWeight.w600)),
        backgroundColor: AppColors.primaryGreen,
        elevation: 0,
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [AppColors.primaryGreen, Color(0xFF00695C), Color(0xFF00796B)],
          ),
        ),
        child: _loading
            ? Center(child: CircularProgressIndicator(color: Colors.white, strokeWidth: 3))
            : _error != null
                ? _buildError()
                : _qrToken != null
                    ? _buildQrScreen()
                    : _buildCatalog(),
      ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: EdgeInsets.all(32.w),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, color: Colors.red.shade300, size: 48),
            SizedBox(height: 16),
            Text(_error ?? 'Ошибка', style: TextStyle(color: Colors.white, fontSize: 16.sp), textAlign: TextAlign.center),
            SizedBox(height: 16),
            ElevatedButton(
              onPressed: () { setState(() { _error = null; _loading = true; }); _loadData(); },
              style: ElevatedButton.styleFrom(backgroundColor: _primaryColor),
              child: Text('Попробовать снова', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCatalog() {
    // Group by category
    final categories = <String, List<Recipe>>{};
    for (final drink in _filtered) {
      categories.putIfAbsent(drink.category, () => []).add(drink);
    }
    final sortedCategories = categories.keys.toList()..sort();

    return Column(
      children: [
        // Balance bar
        _buildBalanceBar(),
        // Search
        _buildSearchBar(),
        // Results
        Expanded(
          child: _filtered.isEmpty
              ? Center(
                  child: Text(
                    _drinks.isEmpty
                        ? 'Нет напитков с ценой в баллах'
                        : 'Ничего не найдено',
                    style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 15.sp),
                  ),
                )
              : ListView.builder(
                  padding: EdgeInsets.only(bottom: 32.h),
                  itemCount: sortedCategories.length,
                  itemBuilder: (ctx, i) {
                    final cat = sortedCategories[i];
                    final items = categories[cat]!;
                    return _buildCategorySection(cat, items);
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildBalanceBar() {
    return Container(
      margin: EdgeInsets.fromLTRB(16.w, 8.h, 16.w, 4.h),
      padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 10.h),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14.r),
        color: Colors.white.withOpacity(0.15),
        border: Border.all(color: Colors.white.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Icon(Icons.account_balance_wallet_rounded, color: _goldColor, size: 20),
          SizedBox(width: 8),
          Text('Баланс:', style: TextStyle(color: Colors.white.withOpacity(0.8), fontSize: 14.sp)),
          Spacer(),
          Text('$_balance', style: TextStyle(color: _goldColor, fontSize: 20.sp, fontWeight: FontWeight.bold)),
          SizedBox(width: 4),
          Text('балл.', style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 12.sp)),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    final categories = _drinks.map((r) => r.category).toSet().toList()..sort();
    final categoryName = _selectedCategory ?? 'Все';

    return Padding(
      padding: EdgeInsets.fromLTRB(16.w, 8.h, 16.w, 8.h),
      child: Row(
        children: [
          // White search field (like menu)
          Expanded(
            flex: 2,
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16.r),
                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.15), blurRadius: 10, offset: Offset(0, 4))],
              ),
              child: TextField(
                decoration: InputDecoration(
                  hintText: 'Поиск напитка...',
                  hintStyle: TextStyle(color: Colors.grey[400]),
                  prefixIcon: Icon(Icons.search_rounded, color: Colors.grey[500]),
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(16.r), borderSide: BorderSide.none),
                  contentPadding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 14.h),
                ),
                onChanged: (q) {
                  _searchQuery = q;
                  _applyFilters();
                },
              ),
            ),
          ),
          SizedBox(width: 8.w),
          // Category filter button
          Expanded(
            flex: 1,
            child: GestureDetector(
              onTapDown: (details) => _showCategoryMenu(details.globalPosition, categories),
              child: Container(
                height: 50,
                padding: EdgeInsets.symmetric(horizontal: 8.w),
                decoration: BoxDecoration(
                  color: _selectedCategory != null
                      ? Colors.white
                      : Colors.white.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(16.r),
                  border: Border.all(color: Colors.white.withOpacity(0.3)),
                  boxShadow: _selectedCategory != null
                      ? [BoxShadow(color: Colors.black.withOpacity(0.15), blurRadius: 10, offset: Offset(0, 4))]
                      : null,
                ),
                child: Row(
                  children: [
                    Icon(Icons.filter_list_rounded,
                        color: _selectedCategory != null ? AppColors.primaryGreen : Colors.white.withOpacity(0.8), size: 18),
                    SizedBox(width: 4.w),
                    Expanded(
                      child: Text(
                        categoryName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: _selectedCategory != null ? AppColors.primaryGreen : Colors.white.withOpacity(0.9),
                          fontSize: 12.sp,
                          fontWeight: _selectedCategory != null ? FontWeight.w600 : FontWeight.normal,
                        ),
                      ),
                    ),
                    Icon(Icons.arrow_drop_down_rounded,
                        color: _selectedCategory != null ? AppColors.primaryGreen : Colors.white.withOpacity(0.6), size: 18),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showCategoryMenu(Offset position, List<String> categories) {
    const allValue = '__all__';
    final items = <PopupMenuEntry<String>>[];

    items.add(PopupMenuItem<String>(
      value: allValue,
      child: Text('Все', style: TextStyle(
        color: Colors.white,
        fontWeight: _selectedCategory == null ? FontWeight.bold : FontWeight.normal,
      )),
    ));

    for (final cat in categories) {
      final count = _drinks.where((r) => r.category == cat).length;
      items.add(PopupMenuItem<String>(
        value: cat,
        child: Row(
          children: [
            Expanded(child: Text(cat, style: TextStyle(
              color: Colors.white,
              fontWeight: _selectedCategory == cat ? FontWeight.bold : FontWeight.normal,
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
      if (value == null) return;
      final newCat = value == allValue ? null : value;
      if (newCat != _selectedCategory) {
        _selectedCategory = newCat;
        _applyFilters();
      }
    });
  }

  Widget _buildCategorySection(String category, List<Recipe> items) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(height: 16),
        // Category header (like menu)
        Padding(
          padding: EdgeInsets.symmetric(horizontal: 16.w),
          child: Container(
            padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 10.h),
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [Colors.white.withOpacity(0.2), Colors.white.withOpacity(0.1)]),
              borderRadius: BorderRadius.circular(14.r),
              border: Border.all(color: Colors.white.withOpacity(0.3)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: EdgeInsets.all(6.w),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(8.r),
                  ),
                  child: Icon(Icons.local_cafe_rounded, color: Colors.white, size: 18),
                ),
                SizedBox(width: 10),
                Text(category, style: TextStyle(fontSize: 18.sp, fontWeight: FontWeight.bold, color: Colors.white)),
                SizedBox(width: 10),
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 4.h),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(12.r),
                  ),
                  child: Text('${items.length}', style: TextStyle(color: Colors.white.withOpacity(0.9), fontWeight: FontWeight.w600, fontSize: 13.sp)),
                ),
              ],
            ),
          ),
        ),
        SizedBox(height: 12),
        // Grid 2 columns (like menu)
        Padding(
          padding: EdgeInsets.symmetric(horizontal: 16.w),
          child: GridView.builder(
            shrinkWrap: true,
            physics: NeverScrollableScrollPhysics(),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              childAspectRatio: 0.85,
            ),
            itemCount: items.length,
            itemBuilder: (ctx, i) => _buildDrinkCard(items[i]),
          ),
        ),
      ],
    );
  }

  Widget _buildDrinkCard(Recipe drink) {
    final pointsPrice = drink.pointsPrice ?? 0;
    final canAfford = _balance >= pointsPrice;

    return GestureDetector(
      onTap: () => _onDrinkTap(drink),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20.r),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.15), blurRadius: 12, offset: Offset(0, 6))],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20.r),
          child: Stack(
            children: [
              // Photo (full card)
              Positioned.fill(
                child: drink.photoUrlOrId != null
                    ? AppCachedImage(
                        imageUrl: drink.photoUrlOrId!,
                        width: double.infinity,
                        height: double.infinity,
                        fit: BoxFit.cover,
                      )
                    : Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topLeft, end: Alignment.bottomRight,
                            colors: [AppColors.primaryGreen.withOpacity(0.15), Color(0xFF00695C).withOpacity(0.1)],
                          ),
                        ),
                        child: Center(child: Icon(Icons.local_cafe_rounded, size: 48, color: AppColors.primaryGreen)),
                      ),
              ),
              // Bottom gradient
              Positioned(
                bottom: 0, left: 0, right: 0,
                child: Container(
                  height: 80,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter, end: Alignment.bottomCenter,
                      colors: [Colors.transparent, Colors.black.withOpacity(0.8)],
                    ),
                  ),
                ),
              ),
              // Points price badge top-right (gold like menu's green price)
              Positioned(
                top: 10.h, right: 10.w,
                child: Container(
                  padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 6.h),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(colors: canAfford
                        ? [_goldColor, Color(0xFFBF9B30)]
                        : [Colors.grey.shade600, Colors.grey.shade700]),
                    borderRadius: BorderRadius.circular(12.r),
                    boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 6, offset: Offset(0, 3))],
                  ),
                  child: Text(
                    '$pointsPrice балл.',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 13.sp,
                    ),
                  ),
                ),
              ),
              // "+" button top-left (like menu)
              if (canAfford)
                Positioned(
                  top: 10.h, left: 10.w,
                  child: Container(
                    padding: EdgeInsets.all(8.w),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.9),
                      borderRadius: BorderRadius.circular(12.r),
                      boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 6, offset: Offset(0, 3))],
                    ),
                    child: Icon(Icons.add_rounded, color: AppColors.primaryGreen, size: 20),
                  ),
                ),
              // Name at bottom
              Positioned(
                bottom: 12.h, left: 12.w, right: 12.w,
                child: Text(
                  drink.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 14.sp,
                    fontWeight: FontWeight.w600,
                    shadows: [Shadow(color: Colors.black54, blurRadius: 4)],
                  ),
                ),
              ),
              // Dimming for unaffordable
              if (!canAfford)
                Positioned.fill(
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(20.r),
                      color: Colors.black.withOpacity(0.4),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildQrScreen() {
    return Center(
      child: SingleChildScrollView(
        padding: EdgeInsets.all(24.w),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.local_cafe_rounded, color: _goldColor, size: 48),
            SizedBox(height: 16),
            Text(
              _selectedDrinkName ?? '',
              style: TextStyle(color: Colors.white, fontSize: 20.sp, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.star_rounded, color: _goldColor, size: 18),
                SizedBox(width: 4),
                Text('${_selectedPointsPrice ?? 0} баллов', style: TextStyle(color: _goldColor, fontSize: 16.sp)),
              ],
            ),
            SizedBox(height: 24),
            // QR Code
            Container(
              padding: EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20.r),
                boxShadow: [BoxShadow(color: _goldColor.withOpacity(0.3), blurRadius: 20, offset: Offset(0, 10))],
              ),
              child: QrImageView(
                data: _qrToken!,
                version: QrVersions.auto,
                size: 200,
                backgroundColor: Colors.white,
                eyeStyle: QrEyeStyle(eyeShape: QrEyeShape.square, color: AppColors.emeraldDark),
                dataModuleStyle: QrDataModuleStyle(dataModuleShape: QrDataModuleShape.square, color: AppColors.emeraldDark),
              ),
            ),
            SizedBox(height: 24),
            Container(
              padding: EdgeInsets.symmetric(horizontal: 20.w, vertical: 12.h),
              decoration: BoxDecoration(
                color: _primaryColor.withOpacity(0.15),
                borderRadius: BorderRadius.circular(12.r),
                border: Border.all(color: _primaryColor.withOpacity(0.3)),
              ),
              child: Text(
                'Покажите QR-код сотруднику кофейни',
                style: TextStyle(color: Colors.white.withOpacity(0.8), fontSize: 14.sp),
                textAlign: TextAlign.center,
              ),
            ),
            SizedBox(height: 32),
            TextButton.icon(
              onPressed: () {
                setState(() {
                  _qrToken = null;
                  _selectedDrinkName = null;
                  _selectedPointsPrice = null;
                });
                _loadData(); // Refresh balance
              },
              icon: Icon(Icons.arrow_back, color: Colors.white.withOpacity(0.6)),
              label: Text('Назад к каталогу', style: TextStyle(color: Colors.white.withOpacity(0.6))),
            ),
          ],
        ),
      ),
    );
  }
}
