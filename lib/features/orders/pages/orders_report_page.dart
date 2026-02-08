import 'package:flutter/material.dart';
import '../services/order_service.dart';
import 'employee_order_detail_page.dart';
import '../../../core/services/multitenancy_filter_service.dart';

/// Страница отчётов по заказам клиентов (только для админа)
/// Содержит 4 вкладки: Ожидают, Выполнено, Отказано, Не подтверждено
class OrdersReportPage extends StatefulWidget {
  const OrdersReportPage({super.key});

  @override
  State<OrdersReportPage> createState() => _OrdersReportPageState();
}

class _OrdersReportPageState extends State<OrdersReportPage> with SingleTickerProviderStateMixin {
  static const Color _emerald = Color(0xFF1A4D4D);
  static const Color _emeraldDark = Color(0xFF0D2E2E);
  static const Color _night = Color(0xFF051515);
  static const Color _gold = Color(0xFFD4AF37);

  late TabController _tabController;

  List<Map<String, dynamic>> _pendingOrders = [];
  List<Map<String, dynamic>> _acceptedOrders = [];
  List<Map<String, dynamic>> _rejectedOrders = [];
  List<Map<String, dynamic>> _unconfirmedOrders = [];

  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _tabController.addListener(_onTabChanged);
    _loadOrders();
  }

  void _onTabChanged() {
    if (!_tabController.indexIsChanging) {
      final index = _tabController.index;
      // Вкладка 2 = Отказано, вкладка 3 = Не подтв.
      if (index == 2) {
        // Помечаем rejected как просмотренные
        OrderService.markAsViewed('rejected');
      } else if (index == 3) {
        // Помечаем unconfirmed как просмотренные
        OrderService.markAsViewed('unconfirmed');
      }
    }
  }

  @override
  void dispose() {
    _tabController.removeListener(_onTabChanged);
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadOrders() async {
    setState(() {
      _isLoading = true;
    });

    // Загружаем заказы по статусам и разрешённые адреса параллельно
    final results = await Future.wait([
      OrderService.getAllOrders(status: 'pending'),
      OrderService.getAllOrders(status: 'accepted'),
      OrderService.getAllOrders(status: 'rejected'),
      OrderService.getAllOrders(status: 'unconfirmed'),
      MultitenancyFilterService.getAllowedShopAddresses(),
    ]);

    final pending = results[0] as List<Map<String, dynamic>>;
    final accepted = results[1] as List<Map<String, dynamic>>;
    final rejected = results[2] as List<Map<String, dynamic>>;
    final unconfirmed = results[3] as List<Map<String, dynamic>>;
    final allowedAddresses = results[4] as List<String>?;

    setState(() {
      _pendingOrders = _filterOrdersByShop(pending, allowedAddresses);
      _acceptedOrders = _filterOrdersByShop(accepted, allowedAddresses);
      _rejectedOrders = _filterOrdersByShop(rejected, allowedAddresses);
      _unconfirmedOrders = _filterOrdersByShop(unconfirmed, allowedAddresses);
      _isLoading = false;
    });
  }

  /// Фильтрация заказов по разрешённым магазинам
  List<Map<String, dynamic>> _filterOrdersByShop(
    List<Map<String, dynamic>> orders,
    List<String>? allowedAddresses,
  ) {
    if (allowedAddresses == null) return orders;
    return orders.where((order) => allowedAddresses.contains(order['shopAddress'])).toList();
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

  String _formatDateTime(String? isoDate) {
    if (isoDate == null || isoDate.isEmpty) return '';
    try {
      final date = DateTime.parse(isoDate).toLocal();
      final day = date.day.toString().padLeft(2, '0');
      final month = date.month.toString().padLeft(2, '0');
      final year = date.year;
      final hour = date.hour.toString().padLeft(2, '0');
      final minute = date.minute.toString().padLeft(2, '0');
      return '$day.$month.$year $hour:$minute';
    } catch (e) {
      return '';
    }
  }

  Widget _buildOrderCard(Map<String, dynamic> order, {bool showStatusIcon = false}) {
    final orderNumber = order['orderNumber'];
    final shopAddress = order['shopAddress'] ?? 'Неизвестный магазин';
    final clientName = order['clientName'] ?? 'Клиент';
    final items = order['items'] as List<dynamic>? ?? [];
    final totalPrice = order['totalPrice'];
    final status = order['status'] as String?;
    final acceptedBy = order['acceptedBy'] as String?;
    final rejectedBy = order['rejectedBy'] as String?;
    final expiredAt = order['expiredAt'] as String?;
    final createdAt = order['createdAt'] as String?;

    Color statusColor;
    IconData statusIcon;
    switch (status) {
      case 'accepted':
        statusColor = Colors.green;
        statusIcon = Icons.check_circle;
        break;
      case 'rejected':
        statusColor = Colors.red;
        statusIcon = Icons.cancel;
        break;
      case 'unconfirmed':
        statusColor = Colors.orange;
        statusIcon = Icons.warning_amber;
        break;
      default:
        statusColor = _gold;
        statusIcon = Icons.receipt;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: status == 'pending' ? () async {
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
          } : null,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                // Иконка статуса
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: statusColor.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    statusIcon,
                    color: statusColor,
                    size: 26,
                  ),
                ),
                const SizedBox(width: 12),
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
                              fontSize: 16,
                              color: Colors.white.withOpacity(0.9),
                            ),
                          ),
                          Text(
                            '${_formatPrice(totalPrice)} руб.',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                              color: statusColor,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Icon(Icons.store, size: 14, color: Colors.white.withOpacity(0.3)),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              shopAddress,
                              style: TextStyle(fontSize: 13, color: Colors.white.withOpacity(0.5)),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Icon(Icons.person, size: 14, color: Colors.white.withOpacity(0.3)),
                          const SizedBox(width: 4),
                          Text(
                            clientName,
                            style: TextStyle(fontSize: 13, color: Colors.white.withOpacity(0.5)),
                          ),
                        ],
                      ),
                      // Дата создания
                      if (createdAt != null && createdAt.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            Icon(Icons.access_time, size: 14, color: Colors.white.withOpacity(0.3)),
                            const SizedBox(width: 4),
                            Text(
                              _formatDateTime(createdAt),
                              style: TextStyle(fontSize: 12, color: Colors.white.withOpacity(0.4)),
                            ),
                          ],
                        ),
                      ],
                      // Сотрудник
                      if (acceptedBy != null && acceptedBy.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            const Icon(Icons.person_outline, size: 14, color: Colors.green),
                            const SizedBox(width: 4),
                            Text(
                              'Принял: $acceptedBy',
                              style: const TextStyle(
                                fontSize: 11,
                                color: Colors.green,
                                fontStyle: FontStyle.italic,
                              ),
                            ),
                          ],
                        ),
                      ],
                      if (rejectedBy != null && rejectedBy.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            const Icon(Icons.person_off, size: 14, color: Colors.red),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                'Отказал: $rejectedBy',
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: Colors.red,
                                  fontStyle: FontStyle.italic,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                      // Просрочка
                      if (status == 'unconfirmed' && expiredAt != null) ...[
                        const SizedBox(height: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.orange.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: Colors.orange.withOpacity(0.3)),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.timer_off, size: 14, color: Colors.orange),
                              const SizedBox(width: 4),
                              const Text(
                                'Не подтверждён вовремя',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.orange,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                      const SizedBox(height: 6),
                      Text(
                        _getItemsPreview(items),
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.white.withOpacity(0.4),
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildOrdersList(List<Map<String, dynamic>> orders, String emptyMessage, {bool showStatusIcon = false}) {
    if (_isLoading) {
      return Center(child: CircularProgressIndicator(color: _gold));
    }

    if (orders.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.06),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.receipt_long, size: 40, color: Colors.white.withOpacity(0.3)),
            ),
            const SizedBox(height: 16),
            Text(
              emptyMessage,
              style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 16),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadOrders,
      color: _gold,
      backgroundColor: _emeraldDark,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: orders.length,
        itemBuilder: (context, index) {
          return _buildOrderCard(orders[index], showStatusIcon: showStatusIcon);
        },
      ),
    );
  }

  Widget _buildTabButton({
    required String label,
    required int count,
    required IconData icon,
    required int tabIndex,
    required Color accentColor,
  }) {
    final isSelected = _tabController.index == tabIndex;

    return GestureDetector(
      onTap: () {
        setState(() {
          _tabController.animateTo(tabIndex);
        });
      },
      child: Container(
        decoration: BoxDecoration(
          color: isSelected ? accentColor.withOpacity(0.15) : Colors.white.withOpacity(0.06),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? accentColor.withOpacity(0.5) : Colors.white.withOpacity(0.1),
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                color: isSelected ? accentColor : Colors.white.withOpacity(0.4),
                size: 26,
              ),
              const SizedBox(height: 6),
              Text(
                label,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                  color: isSelected ? accentColor : Colors.white.withOpacity(0.5),
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: isSelected ? accentColor : Colors.white.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '$count',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: isSelected ? Colors.white : Colors.white.withOpacity(0.5),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
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
              // Custom AppBar
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(
                  children: [
                    GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.white.withOpacity(0.1)),
                        ),
                        child: const Icon(Icons.arrow_back, color: Colors.white, size: 20),
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Text(
                        'Отчёты (Заказы клиентов)',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    GestureDetector(
                      onTap: _loadOrders,
                      child: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.white.withOpacity(0.1)),
                        ),
                        child: const Icon(Icons.refresh, color: Colors.white, size: 20),
                      ),
                    ),
                  ],
                ),
              ),

              // Кастомные вкладки в 2 ряда по 2
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  children: [
                    // Первый ряд: Ожидают + Выполнено
                    Row(
                      children: [
                        Expanded(
                          child: _buildTabButton(
                            label: 'Ожидают',
                            count: _pendingOrders.length,
                            icon: Icons.hourglass_empty,
                            tabIndex: 0,
                            accentColor: _gold,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _buildTabButton(
                            label: 'Выполнено',
                            count: _acceptedOrders.length,
                            icon: Icons.check_circle,
                            tabIndex: 1,
                            accentColor: Colors.green,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    // Второй ряд: Отказано + Не подтв.
                    Row(
                      children: [
                        Expanded(
                          child: _buildTabButton(
                            label: 'Отказано',
                            count: _rejectedOrders.length,
                            icon: Icons.cancel,
                            tabIndex: 2,
                            accentColor: Colors.red,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _buildTabButton(
                            label: 'Не подтв.',
                            count: _unconfirmedOrders.length,
                            icon: Icons.warning_amber,
                            tabIndex: 3,
                            accentColor: Colors.orange,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),

              // Контент вкладок
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    _buildOrdersList(_pendingOrders, 'Нет ожидающих заказов'),
                    _buildOrdersList(_acceptedOrders, 'Нет выполненных заказов', showStatusIcon: true),
                    _buildOrdersList(_rejectedOrders, 'Нет отказанных заказов', showStatusIcon: true),
                    _buildOrdersList(_unconfirmedOrders, 'Нет не подтверждённых заказов', showStatusIcon: true),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
