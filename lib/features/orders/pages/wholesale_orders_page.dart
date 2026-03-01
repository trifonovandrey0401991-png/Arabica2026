import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/theme/app_colors.dart';
import '../services/order_service.dart';
import '../../messenger/services/messenger_service.dart';
import '../../messenger/pages/messenger_chat_page.dart';
import 'employee_order_detail_page.dart';

/// Страница опт-заказов для авторизованных сотрудников
/// Вкладка 1: Активные (pending) — можно принять и написать клиенту
/// Вкладка 2: Подтверждённые (accepted)
class WholesaleOrdersPage extends StatefulWidget {
  final String employeePhone;

  const WholesaleOrdersPage({super.key, required this.employeePhone});

  @override
  State<WholesaleOrdersPage> createState() => _WholesaleOrdersPageState();
}

class _WholesaleOrdersPageState extends State<WholesaleOrdersPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  List<Map<String, dynamic>> _activeOrders = [];
  List<Map<String, dynamic>> _confirmedOrders = [];
  bool _isLoading = true;
  bool _isAcceptingOrder = false;
  String? _employeeName;
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadEmployeeName();
    _loadOrders();
    _refreshTimer = Timer.periodic(const Duration(seconds: 15), (_) => _refreshOrders());
  }

  @override
  void dispose() {
    _tabController.dispose();
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadEmployeeName() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) setState(() => _employeeName = prefs.getString('user_name'));
  }

  Future<void> _loadOrders() async {
    if (mounted) setState(() => _isLoading = true);
    await _fetchOrders();
    if (mounted) setState(() => _isLoading = false);
  }

  Future<void> _refreshOrders() async {
    await _fetchOrders();
    if (mounted) setState(() {});
  }

  Future<void> _fetchOrders() async {
    final pending = await OrderService.getAllOrders(status: 'pending');
    final accepted = await OrderService.getAllOrders(status: 'accepted');
    if (mounted) {
      _activeOrders = pending.where((o) => o['isWholesaleOrder'] == true).toList();
      _confirmedOrders = accepted.where((o) => o['isWholesaleOrder'] == true).toList();
    }
  }

  Future<void> _acceptOrder(Map<String, dynamic> order) async {
    if (_isAcceptingOrder) return; // Prevent double-tap
    setState(() => _isAcceptingOrder = true);
    try {
      final orderId = order['id'] as String?;
      if (orderId == null) return;

      final ok = await OrderService.updateOrderStatus(
        orderId: orderId,
        status: 'accepted',
        acceptedBy: widget.employeePhone,
      );

      if (ok && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Заказ #${order['orderNumber']} принят'),
            backgroundColor: Colors.green.shade700,
            behavior: SnackBarBehavior.floating,
          ),
        );
        _loadOrders();
      }
    } finally {
      if (mounted) setState(() => _isAcceptingOrder = false);
    }
  }

  Future<void> _openMessenger(Map<String, dynamic> order) async {
    final clientPhone = order['clientPhone'] as String?;
    final clientName = order['clientName'] as String? ?? 'Клиент';
    if (clientPhone == null || clientPhone.isEmpty) return;

    try {
      final conversation = await MessengerService.getOrCreatePrivateChat(
        phone1: widget.employeePhone,
        phone2: clientPhone,
        name1: _employeeName,
        name2: clientName,
      );

      if (conversation != null && mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => MessengerChatPage(
              conversation: conversation,
              userPhone: widget.employeePhone,
              userName: _employeeName ?? widget.employeePhone,
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Не удалось открыть чат'),
            backgroundColor: Colors.red.shade700,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.night,
      appBar: AppBar(
        backgroundColor: AppColors.emerald,
        elevation: 0,
        leading: IconButton(
          onPressed: () => Navigator.pop(context),
          icon: Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 20),
        ),
        title: Text(
          'Опт-заказы',
          style: TextStyle(
            color: Colors.white,
            fontSize: 18.sp,
            fontWeight: FontWeight.w600,
          ),
        ),
        actions: [
          IconButton(
            onPressed: _loadOrders,
            icon: Icon(Icons.refresh_rounded, color: Colors.white.withOpacity(0.8)),
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: AppColors.gold,
          indicatorWeight: 2.5,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white.withOpacity(0.5),
          labelStyle: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.w600),
          unselectedLabelStyle: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.w400),
          tabs: [
            Tab(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Flexible(child: Text('Активные', overflow: TextOverflow.ellipsis)),
                  if (_activeOrders.isNotEmpty) ...[
                    SizedBox(width: 6.w),
                    Container(
                      padding: EdgeInsets.symmetric(horizontal: 6.w, vertical: 1.h),
                      decoration: BoxDecoration(
                        color: Colors.orange.withOpacity(0.3),
                        borderRadius: BorderRadius.circular(8.r),
                      ),
                      child: Text(
                        '${_activeOrders.length}',
                        style: TextStyle(fontSize: 11.sp, color: Colors.orange),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            Tab(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Flexible(child: Text('Подтверждённые', overflow: TextOverflow.ellipsis)),
                  if (_confirmedOrders.isNotEmpty) ...[
                    SizedBox(width: 6.w),
                    Container(
                      padding: EdgeInsets.symmetric(horizontal: 6.w, vertical: 1.h),
                      decoration: BoxDecoration(
                        color: Colors.green.withOpacity(0.3),
                        borderRadius: BorderRadius.circular(8.r),
                      ),
                      child: Text(
                        '${_confirmedOrders.length}',
                        style: TextStyle(fontSize: 11.sp, color: Colors.green),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [AppColors.emeraldDark, AppColors.night],
          ),
        ),
        child: _isLoading
            ? Center(child: CircularProgressIndicator(color: AppColors.gold))
            : TabBarView(
                controller: _tabController,
                children: [
                  _buildActiveTab(),
                  _buildConfirmedTab(),
                ],
              ),
      ),
    );
  }

  Widget _buildActiveTab() {
    if (_activeOrders.isEmpty) {
      return _buildEmptyState('Нет активных опт-заказов', Icons.inventory_2_outlined);
    }
    return RefreshIndicator(
      onRefresh: _loadOrders,
      color: AppColors.gold,
      child: ListView.builder(
        padding: EdgeInsets.all(12.w),
        itemCount: _activeOrders.length,
        itemBuilder: (_, i) => _buildActiveCard(_activeOrders[i]),
      ),
    );
  }

  Widget _buildConfirmedTab() {
    if (_confirmedOrders.isEmpty) {
      return _buildEmptyState('Нет подтверждённых заказов', Icons.check_circle_outline_rounded);
    }
    return RefreshIndicator(
      onRefresh: _loadOrders,
      color: AppColors.gold,
      child: ListView.builder(
        padding: EdgeInsets.all(12.w),
        itemCount: _confirmedOrders.length,
        itemBuilder: (_, i) => _buildOrderCard(_confirmedOrders[i], showActions: false),
      ),
    );
  }

  Widget _buildActiveCard(Map<String, dynamic> order) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildOrderCard(order, showActions: true),
        // Кнопки действий под карточкой
        Padding(
          padding: EdgeInsets.only(bottom: 16.h, left: 2.w, right: 2.w),
          child: Row(
            children: [
              Expanded(
                flex: 3,
                child: SizedBox(
                  height: 40.h,
                  child: ElevatedButton.icon(
                    onPressed: () => _acceptOrder(order),
                    icon: Icon(Icons.check_rounded, size: 18),
                    label: Text('Принять', style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.w600)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green.shade700,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10.r)),
                    ),
                  ),
                ),
              ),
              SizedBox(width: 8.w),
              SizedBox(
                height: 40.h,
                child: ElevatedButton.icon(
                  onPressed: () => _openMessenger(order),
                  icon: Icon(Icons.chat_bubble_outline_rounded, size: 16),
                  label: Text('Написать', style: TextStyle(fontSize: 13.sp)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue.shade700,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10.r)),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildOrderCard(Map<String, dynamic> order, {required bool showActions}) {
    final orderNumber = order['orderNumber'];
    final shopAddress = order['shopAddress'] ?? 'Неизвестный магазин';
    final clientName = order['clientName'] ?? 'Клиент';
    final items = order['items'] as List<dynamic>? ?? [];
    final totalPrice = order['totalPrice'];
    final comment = order['comment'] as String?;
    final createdAt = order['createdAt'];
    final timeAgo = _formatTime(createdAt);

    return GestureDetector(
      onTap: () async {
        final result = await Navigator.push<bool>(
          context,
          MaterialPageRoute(
            builder: (_) => EmployeeOrderDetailPage(orderData: order),
          ),
        );
        if (result == true && mounted) _loadOrders();
      },
      child: Container(
        margin: EdgeInsets.only(bottom: showActions ? 6.h : 12.h),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.06),
          borderRadius: BorderRadius.circular(14.r),
          border: Border.all(color: Colors.orange.withOpacity(0.2)),
        ),
      child: Padding(
        padding: EdgeInsets.all(14.w),
        child: Row(
          children: [
            // Иконка
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: Colors.orange.withOpacity(0.12),
                borderRadius: BorderRadius.circular(12.r),
              ),
              child: Icon(Icons.inventory_2_outlined, color: Colors.orange, size: 24),
            ),
            SizedBox(width: 12.w),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Номер + бейдж ОПТ + цена
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            orderNumber != null ? 'Заказ #$orderNumber' : 'Заказ',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16.sp,
                              color: Colors.white.withOpacity(0.9),
                            ),
                          ),
                          SizedBox(width: 8.w),
                          Container(
                            padding: EdgeInsets.symmetric(horizontal: 6.w, vertical: 2.h),
                            decoration: BoxDecoration(
                              color: Colors.orange.withOpacity(0.15),
                              borderRadius: BorderRadius.circular(6.r),
                              border: Border.all(color: Colors.orange.withOpacity(0.4)),
                            ),
                            child: Text(
                              'ОПТ',
                              style: TextStyle(
                                color: Colors.orange,
                                fontSize: 10.sp,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
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
                          style: TextStyle(fontSize: 13.sp, color: Colors.white.withOpacity(0.55)),
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
                        style: TextStyle(fontSize: 13.sp, color: Colors.white.withOpacity(0.55)),
                      ),
                      if (timeAgo.isNotEmpty) ...[
                        Spacer(),
                        Icon(Icons.access_time_rounded, size: 12, color: Colors.white.withOpacity(0.3)),
                        SizedBox(width: 4.w),
                        Text(
                          timeAgo,
                          style: TextStyle(fontSize: 11.sp, color: Colors.white.withOpacity(0.35)),
                        ),
                      ],
                    ],
                  ),
                  // Комментарий
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
                          style: TextStyle(fontSize: 12.sp, color: Colors.white.withOpacity(0.45)),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
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

  Widget _buildEmptyState(String message, IconData icon) {
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
            child: Icon(icon, size: 40, color: Colors.white.withOpacity(0.3)),
          ),
          SizedBox(height: 20.h),
          Text(
            message,
            style: TextStyle(
              fontSize: 16.sp,
              color: Colors.white.withOpacity(0.5),
              fontWeight: FontWeight.w400,
            ),
          ),
        ],
      ),
    );
  }

  String _getItemsPreview(List<dynamic> items) {
    if (items.isEmpty) return 'Нет товаров';
    final names = items.take(2).map((item) {
      final name = item['name'] ?? item['drinkName'] ?? '';
      final qty = item['quantity'] ?? 1;
      return '$name × $qty';
    }).join(', ');
    return items.length > 2 ? '$names и ещё ${items.length - 2}...' : names;
  }

  String _formatPrice(dynamic price) {
    if (price == null) return '0';
    final p = (price is num) ? price.toDouble() : double.tryParse(price.toString()) ?? 0;
    return p == p.truncateToDouble() ? p.toInt().toString() : p.toStringAsFixed(2);
  }

  String _formatTime(dynamic createdAt) {
    try {
      if (createdAt == null) return '';
      final dt = createdAt is int
          ? DateTime.fromMillisecondsSinceEpoch(createdAt)
          : DateTime.parse(createdAt.toString()).toLocal();
      final diff = DateTime.now().difference(dt);
      if (diff.inMinutes < 1) return 'только что';
      if (diff.inMinutes < 60) return '${diff.inMinutes} мин назад';
      if (diff.inHours < 24) return '${diff.inHours} ч назад';
      return '${diff.inDays} дн назад';
    } catch (_) {
      return '';
    }
  }
}
