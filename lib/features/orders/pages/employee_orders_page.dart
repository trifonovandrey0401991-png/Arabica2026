import 'dart:async';
import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../services/order_service.dart';
import 'employee_order_detail_page.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

/// Страница заказов клиентов для сотрудников
/// Показывает только ожидающие заказы (pending)
/// Автоматически обновляется каждые 15 секунд
class EmployeeOrdersPage extends StatefulWidget {
  const EmployeeOrdersPage({super.key});

  @override
  State<EmployeeOrdersPage> createState() => _EmployeeOrdersPageState();
}

class _EmployeeOrdersPageState extends State<EmployeeOrdersPage> {
  List<Map<String, dynamic>> _pendingOrders = [];
  bool _isLoading = true;
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _loadOrders();
    // Авто-обновление каждые 15 секунд
    _refreshTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      _refreshOrders();
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  /// Первичная загрузка — с индикатором загрузки
  Future<void> _loadOrders() async {
    if (mounted) setState(() => _isLoading = true);

    final pending = await OrderService.getAllOrders(status: 'pending');

    if (mounted) {
      setState(() {
        _pendingOrders = pending;
        _isLoading = false;
      });
    }
  }

  /// Фоновое обновление — без индикатора загрузки (тихое)
  Future<void> _refreshOrders() async {
    final pending = await OrderService.getAllOrders(status: 'pending');
    if (mounted) {
      setState(() {
        _pendingOrders = pending;
      });
    }
  }

  String _formatPrice(dynamic price) {
    if (price == null) return '0';
    if (price is num) {
      return price.toStringAsFixed(0);
    }
    return price.toString();
  }

  String _getItemsPreview(List<dynamic> items) {
    if (items.isEmpty) return 'Нет товаров';

    final firstThree = items.take(3).map((item) {
      final name = item['name'] ?? '';
      final quantity = item['quantity'] ?? 1;
      return '$name x$quantity';
    }).toList();

    final preview = firstThree.join(', ');
    if (items.length > 3) {
      return '$preview ...ещё ${items.length - 3}';
    }
    return preview;
  }

  String _formatTime(dynamic createdAt) {
    if (createdAt == null) return '';
    try {
      DateTime dt;
      if (createdAt is String) {
        dt = DateTime.parse(createdAt);
      } else if (createdAt is num) {
        dt = DateTime.fromMillisecondsSinceEpoch(createdAt.toInt());
      } else {
        return '';
      }
      final now = DateTime.now();
      final diff = now.difference(dt);
      if (diff.inMinutes < 1) return 'только что';
      if (diff.inMinutes < 60) return '${diff.inMinutes} мин назад';
      if (diff.inHours < 24) return '${diff.inHours} ч назад';
      return '${dt.day}.${dt.month.toString().padLeft(2, '0')} ${dt.hour}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return '';
    }
  }

  Widget _buildHeader() {
    return Padding(
      padding: EdgeInsets.fromLTRB(8.w, 8.h, 8.w, 16.h),
      child: Row(
        children: [
          // Кнопка назад
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withOpacity(0.1),
                border: Border.all(color: Colors.white.withOpacity(0.2)),
              ),
              child: Icon(
                Icons.arrow_back_ios_new_rounded,
                color: Colors.white.withOpacity(0.8),
                size: 18,
              ),
            ),
          ),
          SizedBox(width: 12.w),
          // Заголовок
          Expanded(
            child: Text(
              'Заказы клиентов (${_pendingOrders.length})',
              style: TextStyle(
                color: Colors.white,
                fontSize: 20.sp,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.5,
              ),
            ),
          ),
          // Кнопка обновления
          GestureDetector(
            onTap: _loadOrders,
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withOpacity(0.1),
                border: Border.all(color: Colors.white.withOpacity(0.2)),
              ),
              child: Icon(
                Icons.refresh_rounded,
                color: Colors.white.withOpacity(0.8),
                size: 20,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOrderCard(Map<String, dynamic> order) {
    final orderNumber = order['orderNumber'];
    final shopAddress = order['shopAddress'] ?? 'Неизвестный магазин';
    final clientName = order['clientName'] ?? 'Клиент';
    final items = order['items'] as List<dynamic>? ?? [];
    final totalPrice = order['totalPrice'];
    final comment = order['comment'] as String?;
    final createdAt = order['createdAt'];
    final timeAgo = _formatTime(createdAt);
    final isWholesale = order['isWholesaleOrder'] == true;

    return Container(
      margin: EdgeInsets.only(bottom: 12.h),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.06),
        borderRadius: BorderRadius.circular(14.r),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(14.r),
          onTap: () async {
            final result = await Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => EmployeeOrderDetailPage(
                  orderData: order,
                ),
              ),
            );

            if (result == true) {
              _loadOrders();
            }
          },
          child: Padding(
            padding: EdgeInsets.all(14.w),
            child: Row(
              children: [
                // Иконка заказа
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: AppColors.gold.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(12.r),
                  ),
                  child: Icon(
                    Icons.receipt_long_rounded,
                    color: AppColors.gold,
                    size: 26,
                  ),
                ),
                SizedBox(width: 12.w),
                // Информация о заказе
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Номер заказа + бейдж Опт + цена
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                orderNumber != null
                                    ? 'Заказ #$orderNumber'
                                    : 'Заказ',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16.sp,
                                  color: Colors.white.withOpacity(0.9),
                                ),
                              ),
                              if (isWholesale) ...[
                                SizedBox(width: 8.w),
                                Container(
                                  padding: EdgeInsets.symmetric(horizontal: 6.w, vertical: 2.h),
                                  decoration: BoxDecoration(
                                    color: Colors.orange.withOpacity(0.15),
                                    borderRadius: BorderRadius.circular(6.r),
                                    border: Border.all(color: Colors.orange.withOpacity(0.3)),
                                  ),
                                  child: Text(
                                    'Опт',
                                    style: TextStyle(
                                      color: Colors.orange,
                                      fontSize: 11.sp,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                          Text(
                            '${_formatPrice(totalPrice)} руб',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16.sp,
                              color: AppColors.gold,
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: 8.h),
                      // Магазин
                      Row(
                        children: [
                          Icon(Icons.store_rounded, size: 14, color: Colors.white.withOpacity(0.35)),
                          SizedBox(width: 6.w),
                          Expanded(
                            child: Text(
                              shopAddress,
                              style: TextStyle(
                                fontSize: 13.sp,
                                color: Colors.white.withOpacity(0.55),
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: 4.h),
                      // Клиент + время
                      Row(
                        children: [
                          Icon(Icons.person_rounded, size: 14, color: Colors.white.withOpacity(0.35)),
                          SizedBox(width: 6.w),
                          Text(
                            clientName,
                            style: TextStyle(
                              fontSize: 13.sp,
                              color: Colors.white.withOpacity(0.55),
                            ),
                          ),
                          if (timeAgo.isNotEmpty) ...[
                            Spacer(),
                            Icon(Icons.access_time_rounded, size: 12, color: Colors.white.withOpacity(0.3)),
                            SizedBox(width: 4.w),
                            Text(
                              timeAgo,
                              style: TextStyle(
                                fontSize: 11.sp,
                                color: Colors.white.withOpacity(0.35),
                              ),
                            ),
                          ],
                        ],
                      ),
                      // Комментарий (время получения)
                      if (comment != null && comment.isNotEmpty) ...[
                        SizedBox(height: 8.h),
                        Container(
                          padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 4.h),
                          decoration: BoxDecoration(
                            color: AppColors.gold.withOpacity(0.12),
                            borderRadius: BorderRadius.circular(6.r),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.timer_rounded, size: 14, color: AppColors.gold),
                              SizedBox(width: 4.w),
                              Flexible(
                                child: Text(
                                  comment,
                                  style: TextStyle(
                                    fontSize: 12.sp,
                                    color: AppColors.gold,
                                    fontWeight: FontWeight.w500,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                      // Товары
                      SizedBox(height: 8.h),
                      Row(
                        children: [
                          Icon(Icons.shopping_bag_rounded, size: 14, color: Colors.white.withOpacity(0.3)),
                          SizedBox(width: 6.w),
                          Expanded(
                            child: Text(
                              _getItemsPreview(items),
                              style: TextStyle(
                                fontSize: 12.sp,
                                color: Colors.white.withOpacity(0.45),
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                SizedBox(width: 8.w),
                // Стрелка
                Icon(
                  Icons.chevron_right_rounded,
                  color: Colors.white.withOpacity(0.25),
                  size: 22,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.06),
              borderRadius: BorderRadius.circular(20.r),
            ),
            child: Icon(
              Icons.inbox_rounded,
              size: 40,
              color: Colors.white.withOpacity(0.3),
            ),
          ),
          SizedBox(height: 20.h),
          Text(
            'Нет ожидающих заказов',
            style: TextStyle(
              fontSize: 18.sp,
              color: Colors.white.withOpacity(0.5),
              fontWeight: FontWeight.w400,
            ),
          ),
          SizedBox(height: 8.h),
          Text(
            'Новые заказы появятся автоматически',
            style: TextStyle(
              fontSize: 14.sp,
              color: Colors.white.withOpacity(0.3),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [AppColors.emerald, AppColors.emeraldDark, AppColors.night],
            stops: const [0.0, 0.3, 1.0],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              _buildHeader(),
              Expanded(
                child: _isLoading
                    ? Center(
                        child: CircularProgressIndicator(color: AppColors.gold),
                      )
                    : _pendingOrders.isEmpty
                        ? _buildEmptyState()
                        : RefreshIndicator(
                            color: AppColors.gold,
                            backgroundColor: AppColors.emeraldDark,
                            onRefresh: _loadOrders,
                            child: ListView.builder(
                              padding: EdgeInsets.symmetric(horizontal: 16.w),
                              itemCount: _pendingOrders.length,
                              itemBuilder: (context, index) {
                                return _buildOrderCard(_pendingOrders[index]);
                              },
                            ),
                          ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
