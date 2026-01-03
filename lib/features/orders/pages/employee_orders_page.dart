import 'package:flutter/material.dart';
import '../services/order_service.dart';
import 'employee_order_detail_page.dart';

class EmployeeOrdersPage extends StatefulWidget {
  const EmployeeOrdersPage({super.key});

  @override
  State<EmployeeOrdersPage> createState() => _EmployeeOrdersPageState();
}

class _EmployeeOrdersPageState extends State<EmployeeOrdersPage> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  List<Map<String, dynamic>> _pendingOrders = [];
  List<Map<String, dynamic>> _acceptedOrders = [];
  List<Map<String, dynamic>> _rejectedOrders = [];

  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadOrders();
  }

  @override
  void dispose() {
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

    setState(() {
      _pendingOrders = pending;
      _acceptedOrders = accepted;
      _rejectedOrders = rejected;
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

  Widget _buildOrderCard(Map<String, dynamic> order, {bool showStatusIcon = false}) {
    final orderNumber = order['orderNumber'];
    final shopAddress = order['shopAddress'] ?? 'Неизвестный магазин';
    final clientName = order['clientName'] ?? 'Клиент';
    final items = order['items'] as List<dynamic>? ?? [];
    final totalPrice = order['totalPrice'];
    final status = order['status'] as String?;
    final acceptedBy = order['acceptedBy'] as String?;
    final rejectedBy = order['rejectedBy'] as String?;

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
                                : Icons.receipt,
                        color: status == 'accepted'
                            ? Colors.green
                            : status == 'rejected'
                                ? Colors.red
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
                          '${_formatPrice(totalPrice)} ₽',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 18,
                            color: status == 'accepted'
                                ? Colors.green
                                : status == 'rejected'
                                    ? Colors.red
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Заказы клиентов'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadOrders,
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: [
            Tab(
              icon: const Icon(Icons.hourglass_empty),
              text: 'Ожидают (${_pendingOrders.length})',
            ),
            Tab(
              icon: const Icon(Icons.check_circle),
              text: 'Выполненные (${_acceptedOrders.length})',
            ),
            Tab(
              icon: const Icon(Icons.cancel),
              text: 'Отказано (${_rejectedOrders.length})',
            ),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildOrdersList(_pendingOrders, 'Нет ожидающих заказов'),
          _buildOrdersList(_acceptedOrders, 'Нет выполненных заказов', showStatusIcon: true),
          _buildOrdersList(_rejectedOrders, 'Нет отказанных заказов', showStatusIcon: true),
        ],
      ),
    );
  }
}
