import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/theme/app_colors.dart';
import '../../../shared/providers/order_provider.dart';
import '../../../core/utils/logger.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

/// Страница "Мои заказы" (Dark Emerald тема)
class OrdersPage extends StatefulWidget {
  const OrdersPage({super.key});

  @override
  State<OrdersPage> createState() => _OrdersPageState();
}

class _OrdersPageState extends State<OrdersPage> with SingleTickerProviderStateMixin {
  bool _isLoading = true;
  late AnimationController _animationController;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: 800),
    );
    _loadOrders();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  Future<void> _loadOrders() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final prefs = await SharedPreferences.getInstance();
      final clientPhone = prefs.getString('user_phone') ?? '';

      if (clientPhone.isNotEmpty && mounted) {
        final orderProvider = OrderProvider.of(context);
        await orderProvider.loadClientOrders(clientPhone);
      }
    } catch (e) {
      Logger.error('Ошибка загрузки заказов', e);
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        _animationController.forward();
      }
    }
  }

  String _getStatusText(String status) {
    switch (status) {
      case 'pending':
        return 'Ожидает';
      case 'preparing':
        return 'Готовится';
      case 'ready':
        return 'Готов';
      case 'completed':
        return 'Выполнено';
      case 'rejected':
        return 'Не принят';
      default:
        return status;
    }
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'pending':
        return Colors.orange;
      case 'preparing':
        return Colors.blue;
      case 'ready':
        return Colors.green;
      case 'completed':
        return Colors.grey;
      case 'rejected':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  IconData _getStatusIcon(String status) {
    switch (status) {
      case 'pending':
        return Icons.access_time_rounded;
      case 'preparing':
        return Icons.restaurant_rounded;
      case 'ready':
        return Icons.check_circle_rounded;
      case 'completed':
        return Icons.done_all_rounded;
      case 'rejected':
        return Icons.cancel_rounded;
      default:
        return Icons.receipt_rounded;
    }
  }

  String _formatPrice(dynamic value) {
    if (value == null) return '0';
    if (value is num) return value.toStringAsFixed(0);
    if (value is String) {
      final parsed = double.tryParse(value);
      return parsed?.toStringAsFixed(0) ?? '0';
    }
    return '0';
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
                    Icon(Icons.receipt_long_rounded, color: AppColors.gold, size: 24),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Мои заказы',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 20.sp,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    GestureDetector(
                      onTap: () {
                        _animationController.reset();
                        _loadOrders();
                      },
                      child: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(12.r),
                          border: Border.all(color: Colors.white.withOpacity(0.1)),
                        ),
                        child: Icon(Icons.refresh_rounded, color: Colors.white, size: 20),
                      ),
                    ),
                  ],
                ),
              ),

              // Содержимое
              Expanded(
                child: _isLoading
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                              padding: EdgeInsets.all(20.w),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.06),
                                shape: BoxShape.circle,
                              ),
                              child: CircularProgressIndicator(
                                color: AppColors.gold,
                                strokeWidth: 3,
                              ),
                            ),
                            SizedBox(height: 24),
                            Text(
                              'Загрузка заказов...',
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.5),
                                fontSize: 16.sp,
                              ),
                            ),
                          ],
                        ),
                      )
                    : ListenableBuilder(
                        listenable: OrderProvider.of(context),
                        builder: (context, _) {
                          final orderProvider = OrderProvider.of(context);

                          if (orderProvider.orders.isEmpty) {
                            return _buildEmptyState();
                          }

                          return RefreshIndicator(
                            onRefresh: _loadOrders,
                            color: AppColors.gold,
                            backgroundColor: AppColors.emeraldDark,
                            child: ListView.builder(
                              padding: EdgeInsets.fromLTRB(16.w, 8.h, 16.w, 16.h),
                              itemCount: orderProvider.orders.length,
                              itemBuilder: (context, index) {
                                final order = orderProvider.orders[index];
                                return AnimatedBuilder(
                                  animation: _animationController,
                                  builder: (context, child) {
                                    final delay = (index * 0.1).clamp(0.0, 0.8);
                                    final animationValue = Curves.easeOutCubic.transform(
                                      (_animationController.value - delay).clamp(0.0, 1.0),
                                    );
                                    return Transform.translate(
                                      offset: Offset(0, 30 * (1 - animationValue)),
                                      child: Opacity(
                                        opacity: animationValue,
                                        child: _buildOrderCard(context, order, orderProvider),
                                      ),
                                    );
                                  },
                                );
                              },
                            ),
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

  Widget _buildEmptyState() {
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
              Icons.receipt_long_outlined,
              size: 72,
              color: Colors.white.withOpacity(0.3),
            ),
          ),
          SizedBox(height: 28),
          Text(
            'У вас пока нет заказов',
            style: TextStyle(
              fontSize: 22.sp,
              color: Colors.white,
              fontWeight: FontWeight.w600,
            ),
          ),
          SizedBox(height: 10),
          Text(
            'Ваши заказы появятся здесь',
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
                    'Вернуться в меню',
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

  Widget _buildOrderCard(BuildContext context, Order order, OrderProvider orderProvider) {
    final dateTime = order.createdAt;
    final statusColor = _getStatusColor(order.status);
    final statusIcon = _getStatusIcon(order.status);

    final firstItemPhotoId = order.itemsData?.isNotEmpty == true
        ? order.itemsData![0]['photoId'] as String?
        : null;

    return Container(
      margin: EdgeInsets.only(bottom: 12.h),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.06),
        borderRadius: BorderRadius.circular(16.r),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 8.h),
          childrenPadding: EdgeInsets.zero,
          iconColor: Colors.white.withOpacity(0.4),
          collapsedIconColor: Colors.white.withOpacity(0.4),
          leading: _buildOrderAvatar(order, firstItemPhotoId, statusColor, statusIcon),
          title: _buildOrderTitle(order),
          subtitle: _buildOrderSubtitle(order, dateTime, statusColor),
          trailing: _buildOrderPrice(order),
          children: [
            _buildOrderDetails(context, order, orderProvider),
          ],
        ),
      ),
    );
  }

  bool _isUnconfirmedOrder(Order order) {
    if (order.status != 'pending') return false;
    if (order.acceptedBy != null && order.acceptedBy!.isNotEmpty) return false;
    if (order.rejectedBy != null && order.rejectedBy!.isNotEmpty) return false;

    final hoursSinceCreated = DateTime.now().difference(order.createdAt).inHours;
    return hoursSinceCreated >= 24;
  }

  Widget _buildOrderAvatar(Order order, String? firstItemPhotoId, Color statusColor, IconData statusIcon) {
    Color avatarColor = statusColor;
    IconData avatarIcon = statusIcon;

    if (order.acceptedBy != null && order.acceptedBy!.isNotEmpty) {
      avatarColor = Colors.green;
      avatarIcon = Icons.check_circle_rounded;
    } else if (order.rejectedBy != null && order.rejectedBy!.isNotEmpty) {
      avatarColor = Colors.red;
      avatarIcon = Icons.cancel_rounded;
    } else if (_isUnconfirmedOrder(order)) {
      avatarColor = Colors.red;
      avatarIcon = Icons.cancel_rounded;
    }

    return Container(
      width: 52,
      height: 52,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14.r),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14.r),
        child: firstItemPhotoId != null && firstItemPhotoId.isNotEmpty
            ? Image.asset(
                'assets/images/$firstItemPhotoId.jpg',
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) {
                  return _buildStatusIcon(avatarColor, avatarIcon);
                },
              )
            : _buildStatusIcon(avatarColor, avatarIcon),
      ),
    );
  }

  Widget _buildStatusIcon(Color statusColor, IconData statusIcon) {
    return Container(
      decoration: BoxDecoration(
        color: statusColor.withOpacity(0.2),
      ),
      child: Center(
        child: Icon(
          statusIcon,
          color: statusColor,
          size: 26,
        ),
      ),
    );
  }

  Widget _buildOrderTitle(Order order) {
    return Text(
      order.orderNumber != null
          ? 'Заказ ${order.orderNumber}'
          : 'Заказ ${order.id.substring(order.id.length - 6)}',
      style: TextStyle(
        fontWeight: FontWeight.bold,
        fontSize: 16.sp,
        color: Colors.white.withOpacity(0.9),
      ),
    );
  }

  Widget _buildOrderSubtitle(Order order, DateTime dateTime, Color statusColor) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(height: 6),
        Row(
          children: [
            Icon(
              Icons.calendar_today_rounded,
              size: 13,
              color: Colors.white.withOpacity(0.4),
            ),
            SizedBox(width: 4),
            Text(
              '${dateTime.day.toString().padLeft(2, '0')}.${dateTime.month.toString().padLeft(2, '0')}.${dateTime.year} в ${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}',
              style: TextStyle(
                fontSize: 12.sp,
                color: Colors.white.withOpacity(0.4),
              ),
            ),
          ],
        ),
        SizedBox(height: 6),
        // Статус бейдж
        Container(
          padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 3.h),
          decoration: BoxDecoration(
            color: statusColor.withOpacity(0.15),
            borderRadius: BorderRadius.circular(8.r),
            border: Border.all(color: statusColor.withOpacity(0.3)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(_getStatusIcon(order.status), size: 12, color: statusColor),
              SizedBox(width: 4),
              Text(
                _getStatusText(order.status),
                style: TextStyle(
                  fontSize: 11.sp,
                  color: statusColor,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
        // Информация об отказе
        if (order.rejectedBy != null && order.rejectedBy!.isNotEmpty) ...[
          SizedBox(height: 8),
          Container(
            padding: EdgeInsets.all(8.w),
            decoration: BoxDecoration(
              color: Colors.red.withOpacity(0.1),
              borderRadius: BorderRadius.circular(10.r),
              border: Border.all(color: Colors.red.withOpacity(0.3)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.person_off_rounded,
                      size: 14,
                      color: Colors.red,
                    ),
                    SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        'Отказал: ${order.rejectedBy}',
                        style: TextStyle(
                          fontSize: 12.sp,
                          color: Colors.red,
                          fontWeight: FontWeight.w500,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                if (order.rejectionReason != null && order.rejectionReason!.isNotEmpty) ...[
                  SizedBox(height: 4),
                  Text(
                    'Причина: ${order.rejectionReason}',
                    style: TextStyle(
                      fontSize: 12.sp,
                      color: Colors.red[300],
                    ),
                    maxLines: 10,
                    overflow: TextOverflow.fade,
                  ),
                ],
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildOrderPrice(Order order) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 6.h),
      decoration: BoxDecoration(
        color: AppColors.gold.withOpacity(0.15),
        borderRadius: BorderRadius.circular(10.r),
        border: Border.all(color: AppColors.gold.withOpacity(0.3)),
      ),
      child: Text(
        '${order.totalPrice.toStringAsFixed(0)} р.',
        style: TextStyle(
          fontSize: 15.sp,
          fontWeight: FontWeight.bold,
          color: AppColors.gold,
        ),
      ),
    );
  }

  Widget _buildOrderDetails(BuildContext context, Order order, OrderProvider orderProvider) {
    return Container(
      margin: EdgeInsets.fromLTRB(16.w, 0.h, 16.w, 16.h),
      padding: EdgeInsets.all(14.w),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.04),
        borderRadius: BorderRadius.circular(14.r),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Заголовок списка товаров
          Row(
            children: [
              Container(
                padding: EdgeInsets.all(6.w),
                decoration: BoxDecoration(
                  color: AppColors.gold.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(8.r),
                ),
                child: Icon(
                  Icons.shopping_basket_rounded,
                  color: AppColors.gold,
                  size: 18,
                ),
              ),
              SizedBox(width: 10),
              Text(
                'Товары в заказе',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 15.sp,
                  color: Colors.white.withOpacity(0.9),
                ),
              ),
            ],
          ),
          SizedBox(height: 12),
          // Список товаров
          ...(order.itemsData ?? []).map((item) => Container(
                margin: EdgeInsets.only(bottom: 8.h),
                padding: EdgeInsets.all(10.w),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.04),
                  borderRadius: BorderRadius.circular(10.r),
                  border: Border.all(color: Colors.white.withOpacity(0.06)),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: AppColors.emerald,
                        borderRadius: BorderRadius.circular(8.r),
                      ),
                      child: Center(
                        child: Text(
                          '×${item['quantity'] ?? 1}',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                            fontSize: 12.sp,
                          ),
                        ),
                      ),
                    ),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        item['name'] ?? 'Товар',
                        style: TextStyle(
                          fontSize: 14.sp,
                          fontWeight: FontWeight.w500,
                          color: Colors.white.withOpacity(0.8),
                        ),
                      ),
                    ),
                    Text(
                      '${_formatPrice(item['total'] ?? item['price'] ?? 0)} руб.',
                      style: TextStyle(
                        fontSize: 14.sp,
                        fontWeight: FontWeight.bold,
                        color: AppColors.gold,
                      ),
                    ),
                  ],
                ),
              )),
          SizedBox(height: 12),
          Divider(height: 1, color: Colors.white.withOpacity(0.1)),
          SizedBox(height: 12),
          // Комментарий
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    padding: EdgeInsets.all(6.w),
                    decoration: BoxDecoration(
                      color: Colors.amber.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(8.r),
                    ),
                    child: Icon(
                      Icons.comment_rounded,
                      color: Colors.amber[600],
                      size: 18,
                    ),
                  ),
                  SizedBox(width: 10),
                  Text(
                    'Комментарий',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14.sp,
                      color: Colors.white.withOpacity(0.9),
                    ),
                  ),
                ],
              ),
              GestureDetector(
                onTap: () {
                  _showCommentDialog(context, order, orderProvider);
                },
                child: Container(
                  padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 6.h),
                  decoration: BoxDecoration(
                    color: order.comment != null && order.comment!.isNotEmpty
                        ? Colors.amber.withOpacity(0.15)
                        : AppColors.gold.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(10.r),
                    border: Border.all(
                      color: order.comment != null && order.comment!.isNotEmpty
                          ? Colors.amber.withOpacity(0.3)
                          : AppColors.gold.withOpacity(0.3),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        order.comment != null && order.comment!.isNotEmpty
                            ? Icons.edit_rounded
                            : Icons.add_rounded,
                        size: 14,
                        color: order.comment != null && order.comment!.isNotEmpty
                            ? Colors.amber
                            : AppColors.gold,
                      ),
                      SizedBox(width: 4),
                      Text(
                        order.comment != null && order.comment!.isNotEmpty
                            ? 'Изменить'
                            : 'Добавить',
                        style: TextStyle(
                          color: order.comment != null && order.comment!.isNotEmpty
                              ? Colors.amber
                              : AppColors.gold,
                          fontSize: 12.sp,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: 10),
          // Блок комментария
          Container(
            width: double.infinity,
            padding: EdgeInsets.all(12.w),
            decoration: BoxDecoration(
              color: order.comment != null && order.comment!.isNotEmpty
                  ? Colors.amber.withOpacity(0.08)
                  : Colors.white.withOpacity(0.03),
              borderRadius: BorderRadius.circular(10.r),
              border: Border.all(
                color: order.comment != null && order.comment!.isNotEmpty
                    ? Colors.amber.withOpacity(0.2)
                    : Colors.white.withOpacity(0.06),
              ),
            ),
            child: Text(
              order.comment != null && order.comment!.isNotEmpty
                  ? order.comment!
                  : 'Комментарий не добавлен',
              style: TextStyle(
                fontSize: 13.sp,
                color: order.comment != null && order.comment!.isNotEmpty
                    ? Colors.white.withOpacity(0.7)
                    : Colors.white.withOpacity(0.3),
                fontStyle: order.comment != null && order.comment!.isNotEmpty
                    ? FontStyle.normal
                    : FontStyle.italic,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showCommentDialog(
    BuildContext context,
    Order order,
    OrderProvider orderProvider,
  ) {
    final TextEditingController controller =
        TextEditingController(text: order.comment ?? '');

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
              padding: EdgeInsets.all(10.w),
              decoration: BoxDecoration(
                color: AppColors.gold.withOpacity(0.15),
                borderRadius: BorderRadius.circular(12.r),
              ),
              child: Icon(
                Icons.comment_rounded,
                color: AppColors.gold,
                size: 24,
              ),
            ),
            SizedBox(width: 12),
            Text(
              'Комментарий',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 20.sp,
                color: Colors.white,
              ),
            ),
          ],
        ),
        content: TextField(
          controller: controller,
          maxLines: 5,
          style: TextStyle(color: Colors.white.withOpacity(0.9)),
          cursorColor: AppColors.gold,
          decoration: InputDecoration(
            hintText: 'Введите комментарий к заказу...',
            hintStyle: TextStyle(color: Colors.white.withOpacity(0.3)),
            filled: true,
            fillColor: Colors.white.withOpacity(0.06),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14.r),
              borderSide: BorderSide(color: Colors.white.withOpacity(0.1)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14.r),
              borderSide: BorderSide(color: Colors.white.withOpacity(0.1)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14.r),
              borderSide: BorderSide(color: AppColors.gold, width: 2),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            style: TextButton.styleFrom(
              padding: EdgeInsets.symmetric(horizontal: 20.w, vertical: 12.h),
            ),
            child: Text(
              'Отмена',
              style: TextStyle(
                color: Colors.white.withOpacity(0.5),
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          GestureDetector(
            onTap: () {
              final comment = controller.text.trim();
              orderProvider.updateOrderComment(
                order.id,
                comment.isEmpty ? null : comment,
              );
              Navigator.of(dialogContext).pop();
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Row(
                    children: [
                      Icon(
                        comment.isEmpty ? Icons.delete_rounded : Icons.check_circle_rounded,
                        color: Colors.white,
                        size: 20,
                      ),
                      SizedBox(width: 12),
                      Text(
                        comment.isEmpty
                            ? 'Комментарий удален'
                            : 'Комментарий сохранен',
                      ),
                    ],
                  ),
                  backgroundColor: AppColors.emerald,
                  behavior: SnackBarBehavior.floating,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12.r),
                  ),
                  margin: EdgeInsets.all(16.w),
                  duration: Duration(seconds: 2),
                ),
              );
            },
            child: Container(
              padding: EdgeInsets.symmetric(horizontal: 20.w, vertical: 10.h),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [AppColors.gold.withOpacity(0.9), AppColors.gold],
                ),
                borderRadius: BorderRadius.circular(12.r),
              ),
              child: Text(
                'Сохранить',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF1A1A1A),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
