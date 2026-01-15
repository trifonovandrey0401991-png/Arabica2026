import 'package:flutter/material.dart';
import '../services/order_service.dart';
import 'employee_order_detail_page.dart';

/// Страница заказов клиентов для сотрудников
/// Показывает только ожидающие заказы (pending)
class EmployeeOrdersPage extends StatefulWidget {
  const EmployeeOrdersPage({super.key});

  @override
  State<EmployeeOrdersPage> createState() => _EmployeeOrdersPageState();
}

class _EmployeeOrdersPageState extends State<EmployeeOrdersPage> {
  List<Map<String, dynamic>> _pendingOrders = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadOrders();
  }

  Future<void> _loadOrders() async {
    setState(() {
      _isLoading = true;
    });

    final pending = await OrderService.getAllOrders(status: 'pending');

    setState(() {
      _pendingOrders = pending;
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
      margin: const EdgeInsets.only(bottom: 12),
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
          padding: const EdgeInsets.all(16),
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
                    ? const Icon(Icons.receipt, color: Colors.grey, size: 32)
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
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 18,
                            color: Colors.green,
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
                    // Показываем комментарий с временем получения
                    if (comment != null && comment.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.blue[50],
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: Colors.blue[200]!),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.timer, size: 14, color: Colors.blue),
                            const SizedBox(width: 4),
                            Flexible(
                              child: Text(
                                comment,
                                style: TextStyle(
                                  fontSize: 12,
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
              // Стрелка для перехода
              const Icon(Icons.chevron_right, color: Colors.grey),
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
        backgroundColor: const Color(0xFF004D40),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadOrders,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _pendingOrders.isEmpty
              ? const Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.inbox, size: 64, color: Colors.grey),
                      SizedBox(height: 16),
                      Text(
                        'Нет ожидающих заказов',
                        style: TextStyle(fontSize: 18, color: Colors.grey),
                      ),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _loadOrders,
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _pendingOrders.length,
                    itemBuilder: (context, index) {
                      return _buildOrderCard(_pendingOrders[index]);
                    },
                  ),
                ),
    );
  }
}
