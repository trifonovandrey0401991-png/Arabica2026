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
      return '$preview...';
    }
    return preview;
  }

  Widget _buildOrderCard(Map<String, dynamic> order) {
    final orderNumber = order['orderNumber'];
    final shopAddress = order['shopAddress'] ?? 'Неизвестный магазин';
    final clientName = order['clientName'] ?? 'Клиент';
    final items = order['items'] as List<dynamic>? ?? [];
    final totalPrice = order['totalPrice'];
    final comment = order['comment'] as String?;

    // Получаем фото первого товара
    final firstItemPhotoId = items.isNotEmpty
        ? items[0]['photoId'] as String?
        : null;

    return Card(
      margin: EdgeInsets.only(bottom: 12.h),
      child: InkWell(
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
          padding: EdgeInsets.all(16.w),
          child: Row(
            children: [
              // Фото первого товара или иконка
              CircleAvatar(
                radius: 28,
                backgroundColor: Colors.grey[200],
                backgroundImage: firstItemPhotoId != null && firstItemPhotoId.isNotEmpty
                    ? AssetImage('assets/images/$firstItemPhotoId.jpg')
                    : null,
                child: firstItemPhotoId == null || firstItemPhotoId.isEmpty
                    ? Icon(Icons.receipt, color: Colors.grey, size: 32)
                    : null,
              ),
              SizedBox(width: 12),
              // Информация о заказе
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          orderNumber != null
                              ? 'Заказ $orderNumber'
                              : 'Заказ ${order['id'].toString().substring(0, 6)}',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 18.sp,
                          ),
                        ),
                        Text(
                          '${_formatPrice(totalPrice)} руб.',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 18.sp,
                            color: Colors.green,
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: 8),
                    Row(
                      children: [
                        Icon(Icons.store, size: 16, color: Colors.grey),
                        SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            shopAddress,
                            style: TextStyle(fontSize: 14.sp),
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(Icons.person, size: 16, color: Colors.grey),
                        SizedBox(width: 4),
                        Text(
                          clientName,
                          style: TextStyle(fontSize: 14.sp),
                        ),
                      ],
                    ),
                    // Показываем комментарий с временем получения
                    if (comment != null && comment.isNotEmpty) ...[
                      SizedBox(height: 4),
                      Container(
                        padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 4.h),
                        decoration: BoxDecoration(
                          color: Colors.blue[50],
                          borderRadius: BorderRadius.circular(4.r),
                          border: Border.all(color: Colors.blue[200]!),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.timer, size: 14, color: Colors.blue),
                            SizedBox(width: 4),
                            Flexible(
                              child: Text(
                                comment,
                                style: TextStyle(
                                  fontSize: 12.sp,
                                  color: Colors.blue[800],
                                  fontWeight: FontWeight.w500,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    SizedBox(height: 8),
                    Text(
                      _getItemsPreview(items),
                      style: TextStyle(
                        fontSize: 14.sp,
                        color: Colors.black87,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              // Стрелка для перехода
              Icon(Icons.chevron_right, color: Colors.grey),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Заказы клиентов (${_pendingOrders.length})'),
        backgroundColor: AppColors.primaryGreen,
        actions: [
          IconButton(
            icon: Icon(Icons.refresh),
            onPressed: _loadOrders,
          ),
        ],
      ),
      body: _isLoading
          ? Center(child: CircularProgressIndicator())
          : _pendingOrders.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.inbox, size: 64, color: Colors.grey),
                      SizedBox(height: 16),
                      Text(
                        'Нет ожидающих заказов',
                        style: TextStyle(fontSize: 18.sp, color: Colors.grey),
                      ),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _loadOrders,
                  child: ListView.builder(
                    padding: EdgeInsets.all(16.w),
                    itemCount: _pendingOrders.length,
                    itemBuilder: (context, index) {
                      return _buildOrderCard(_pendingOrders[index]);
                    },
                  ),
                ),
    );
  }
}
