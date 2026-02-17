import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/shop_icon.dart';
import '../../features/shops/models/shop_model.dart';

/// Scaffold для страниц выбора магазина.
///
/// Обрабатывает: Dark Emerald градиент, кастомный AppBar,
/// состояния загрузки/ошибки/пустого списка, список магазинов с карточками.
///
/// Пример:
/// ```dart
/// ShopSelectionScaffold(
///   title: 'Выберите магазин',
///   loadShops: () => ShopService.getShopsForCurrentUser(),
///   onShopTap: (context, shop) {
///     Navigator.push(context, MaterialPageRoute(
///       builder: (_) => NextPage(shopAddress: shop.address),
///     ));
///   },
/// )
/// ```
class ShopSelectionScaffold extends StatefulWidget {
  final String title;

  /// Загрузка списка магазинов.
  final Future<List<Shop>> Function() loadShops;

  /// Вызывается при нажатии на магазин.
  final void Function(BuildContext context, Shop shop) onShopTap;

  /// Виджет-заголовок над списком (баннер, информация и т.д.).
  final Widget? headerWidget;

  /// Фильтр магазинов (например, скрыть уже сданные).
  final bool Function(Shop)? shopFilter;

  /// Кастомный builder карточки магазина.
  final Widget Function(BuildContext context, Shop shop, int index)?
      shopCardBuilder;

  /// Текст для пустого списка.
  final String emptyMessage;

  /// Текст когда все магазины отфильтрованы.
  final String? emptyFilteredMessage;

  /// Дополнительная загрузка при инициализации (настройки, статус и т.д.).
  final Future<void> Function()? onExtraLoad;

  const ShopSelectionScaffold({
    super.key,
    required this.title,
    required this.loadShops,
    required this.onShopTap,
    this.headerWidget,
    this.shopFilter,
    this.shopCardBuilder,
    this.emptyMessage = 'Магазины не найдены',
    this.emptyFilteredMessage,
    this.onExtraLoad,
  });

  @override
  State<ShopSelectionScaffold> createState() => _ShopSelectionScaffoldState();
}

class _ShopSelectionScaffoldState extends State<ShopSelectionScaffold> {
  bool _isLoading = true;
  List<Shop> _shops = [];
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      if (widget.onExtraLoad != null) {
        await widget.onExtraLoad!();
      }
      final shops = await widget.loadShops();
      if (mounted) {
        setState(() {
          _shops = shops;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [AppColors.emerald, AppColors.emeraldDark, AppColors.night],
          stops: [0.0, 0.3, 1.0],
        ),
      ),
      child: SafeArea(
        child: Scaffold(
          backgroundColor: Colors.transparent,
          body: Column(
            children: [
              _buildAppBar(context),
              if (widget.headerWidget != null) widget.headerWidget!,
              Expanded(child: _buildBody()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAppBar(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 8.h),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Container(
              padding: EdgeInsets.all(10.w),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.15),
                borderRadius: BorderRadius.circular(12.r),
              ),
              child: Icon(
                Icons.arrow_back_ios_new,
                color: Colors.white,
                size: 20.sp,
              ),
            ),
          ),
          SizedBox(width: 16.w),
          Text(
            widget.title,
            style: TextStyle(
              color: Colors.white,
              fontSize: 20.sp,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return Center(
        child: CircularProgressIndicator(color: AppColors.gold),
      );
    }

    if (_error != null) {
      return _buildErrorState();
    }

    final filtered =
        widget.shopFilter != null ? _shops.where(widget.shopFilter!).toList() : _shops;

    if (_shops.isEmpty) {
      return _buildEmptyState(widget.emptyMessage);
    }

    if (filtered.isEmpty && widget.emptyFilteredMessage != null) {
      return _buildEmptyState(widget.emptyFilteredMessage!);
    }

    if (filtered.isEmpty) {
      return _buildEmptyState(widget.emptyMessage);
    }

    return ListView.builder(
      padding: EdgeInsets.all(16.w),
      itemCount: filtered.length,
      itemBuilder: (context, index) {
        final shop = filtered[index];
        if (widget.shopCardBuilder != null) {
          return widget.shopCardBuilder!(context, shop, index);
        }
        return _buildDefaultShopCard(shop, index);
      },
    );
  }

  Widget _buildDefaultShopCard(Shop shop, int index) {
    return Padding(
      padding: EdgeInsets.only(bottom: 12.h),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => widget.onShopTap(context, shop),
          borderRadius: BorderRadius.circular(16.r),
          child: Container(
            padding: EdgeInsets.all(16.w),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.08),
              borderRadius: BorderRadius.circular(16.r),
              border: Border.all(
                color: AppColors.gold.withOpacity(0.2),
                width: 1,
              ),
            ),
            child: Row(
              children: [
                ShopIcon(size: 44),
                SizedBox(width: 14.w),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        shop.address,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 15.sp,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (shop.name.isNotEmpty) ...[
                        SizedBox(height: 4.h),
                        Text(
                          shop.name,
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.6),
                            fontSize: 12.sp,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_right,
                  color: AppColors.gold.withOpacity(0.6),
                  size: 24.sp,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Padding(
        padding: EdgeInsets.all(32.w),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, color: Colors.red[300], size: 48.sp),
            SizedBox(height: 16.h),
            Text(
              'Ошибка загрузки',
              style: TextStyle(
                color: Colors.white,
                fontSize: 16.sp,
                fontWeight: FontWeight.w600,
              ),
            ),
            SizedBox(height: 8.h),
            Text(
              _error ?? '',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white.withOpacity(0.6),
                fontSize: 13.sp,
              ),
            ),
            SizedBox(height: 24.h),
            OutlinedButton(
              onPressed: () => Navigator.pop(context),
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: AppColors.gold),
                foregroundColor: AppColors.gold,
              ),
              child: Text('Назад'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(String message) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.store_outlined,
            color: Colors.white.withOpacity(0.3),
            size: 48.sp,
          ),
          SizedBox(height: 16.h),
          Text(
            message,
            style: TextStyle(
              color: Colors.white.withOpacity(0.5),
              fontSize: 15.sp,
            ),
          ),
        ],
      ),
    );
  }
}
