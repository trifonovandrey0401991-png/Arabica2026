import 'package:flutter/material.dart';
import '../services/order_service.dart';
import 'employee_order_detail_page.dart';

/// Страница отчётов по заказам клиентов (только для админа)
/// Содержит 4 вкладки: Ожидают, Выполнено, Отказано, Не подтверждено
class OrdersReportPage extends StatefulWidget {
  const OrdersReportPage({super.key});

  @override
  State<OrdersReportPage> createState() => _OrdersReportPageState();
}

class _OrdersReportPageState extends State<OrdersReportPage> with SingleTickerProviderStateMixin {
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

    // Загружаем заказы по статусам
    final pending = await OrderService.getAllOrders(status: 'pending');
    final accepted = await OrderService.getAllOrders(status: 'accepted');
    final rejected = await OrderService.getAllOrders(status: 'rejected');
    final unconfirmed = await OrderService.getAllOrders(status: 'unconfirmed');

    setState(() {
      _pendingOrders = pending;
      _acceptedOrders = accepted;
      _rejectedOrders = rejected;
      _unconfirmedOrders = unconfirmed;
      _isLoading = false;
    });
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
    final updatedAt = order['updatedAt'] as String?;

    // Получаем фото первого товара
    final firstItemPhotoId = items.isNotEmpty
        ? items[0]['photoId'] as String?
        : null;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
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
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              // Фото первого товара или иконка статуса
              CircleAvatar(
                radius: 28,
                backgroundColor: status == 'accepted'
                    ? Colors.green[100]
                    : status == 'rejected'
                        ? Colors.red[100]
                        : status == 'unconfirmed'
                            ? Colors.orange[100]
                            : Colors.grey[200],
                backgroundImage: !showStatusIcon && firstItemPhotoId != null && firstItemPhotoId.isNotEmpty
                    ? AssetImage('assets/images/$firstItemPhotoId.jpg')
                    : null,
                child: showStatusIcon || firstItemPhotoId == null || firstItemPhotoId.isEmpty
                    ? Icon(
                        status == 'accepted'
                            ? Icons.check_circle
                            : status == 'rejected'
                                ? Icons.cancel
                                : status == 'unconfirmed'
                                    ? Icons.warning_amber
                                    : Icons.receipt,
                        color: status == 'accepted'
                            ? Colors.green
                            : status == 'rejected'
                                ? Colors.red
                                : status == 'unconfirmed'
                                    ? Colors.orange
                                    : Colors.grey,
                        size: 32,
                      )
                    : null,
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
                              ? 'Заказ #$orderNumber'
                              : 'Заказ #${order['id'].toString().substring(0, 6)}',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 18,
                          ),
                        ),
                        Text(
                          '${_formatPrice(totalPrice)} руб.',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 18,
                            color: status == 'accepted'
                                ? Colors.green
                                : status == 'rejected'
                                    ? Colors.red
                                    : status == 'unconfirmed'
                                        ? Colors.orange
                                        : Colors.green,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        const Icon(Icons.store, size: 16, color: Colors.grey),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            shopAddress,
                            style: const TextStyle(fontSize: 14),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        const Icon(Icons.person, size: 16, color: Colors.grey),
                        const SizedBox(width: 4),
                        Text(
                          clientName,
                          style: const TextStyle(fontSize: 14),
                        ),
                      ],
                    ),
                    // Дата и время создания заказа
                    if (createdAt != null && createdAt.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          const Icon(Icons.access_time, size: 16, color: Colors.grey),
                          const SizedBox(width: 4),
                          Text(
                            _formatDateTime(createdAt),
                            style: const TextStyle(fontSize: 13, color: Colors.grey),
                          ),
                        ],
                      ),
                    ],
                    // Показываем сотрудника для выполненных/отказанных
                    if (acceptedBy != null && acceptedBy.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          const Icon(Icons.person_outline, size: 16, color: Colors.green),
                          const SizedBox(width: 4),
                          Text(
                            'Принял: $acceptedBy',
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.green,
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                        ],
                      ),
                    ],
                    if (rejectedBy != null && rejectedBy.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          const Icon(Icons.person_off, size: 16, color: Colors.red),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              'Отказал: $rejectedBy',
                              style: const TextStyle(
                                fontSize: 12,
                                color: Colors.red,
                                fontStyle: FontStyle.italic,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                    // Показываем информацию о просрочке для unconfirmed
                    if (status == 'unconfirmed' && expiredAt != null) ...[
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.orange[50],
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: Colors.orange[200]!),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.timer_off, size: 14, color: Colors.orange),
                            const SizedBox(width: 4),
                            Text(
                              'Не подтверждён вовремя',
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.orange[800],
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 8),
                    Text(
                      _getItemsPreview(items),
                      style: const TextStyle(
                        fontSize: 14,
                        color: Colors.black87,
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
    );
  }

  Widget _buildOrdersList(List<Map<String, dynamic>> orders, String emptyMessage, {bool showStatusIcon = false}) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (orders.isEmpty) {
      return Center(
        child: Text(
          emptyMessage,
          style: const TextStyle(fontSize: 16, color: Colors.grey),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadOrders,
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
    required List<Color> gradientColors,
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
          gradient: isSelected
              ? LinearGradient(
                  colors: gradientColors,
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                )
              : null,
          color: isSelected ? null : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? gradientColors[0] : Colors.grey.shade300,
            width: isSelected ? 2.5 : 1.5,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: gradientColors[0].withOpacity(0.3),
                    blurRadius: 8,
                    offset: const Offset(0, 4),
                  ),
                ]
              : [
                  BoxShadow(
                    color: Colors.grey.withOpacity(0.1),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ],
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                color: isSelected ? Colors.white : gradientColors[0],
                size: 28,
              ),
              const SizedBox(height: 6),
              Text(
                label,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                  color: isSelected ? Colors.white : Colors.grey.shade700,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: isSelected ? Colors.white.withOpacity(0.9) : gradientColors[0].withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '$count',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: isSelected ? gradientColors[0] : gradientColors[0],
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
      appBar: AppBar(
        title: const Text('Отчёты (Заказы клиентов)'),
        backgroundColor: const Color(0xFF004D40),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadOrders,
          ),
        ],
      ),
      body: Column(
        children: [
          // Кастомные вкладки в 2 ряда по 2
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.grey.shade50,
              boxShadow: [
                BoxShadow(
                  color: Colors.grey.withOpacity(0.2),
                  blurRadius: 6,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
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
                        gradientColors: [const Color(0xFF00897B), const Color(0xFF00695C)],
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _buildTabButton(
                        label: 'Выполнено',
                        count: _acceptedOrders.length,
                        icon: Icons.check_circle,
                        tabIndex: 1,
                        gradientColors: [const Color(0xFF43A047), const Color(0xFF2E7D32)],
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
                        gradientColors: [const Color(0xFFE53935), const Color(0xFFC62828)],
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _buildTabButton(
                        label: 'Не подтв.',
                        count: _unconfirmedOrders.length,
                        icon: Icons.warning_amber,
                        tabIndex: 3,
                        gradientColors: [const Color(0xFFFB8C00), const Color(0xFFEF6C00)],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
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
    );
  }
}
