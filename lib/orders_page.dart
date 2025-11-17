import 'package:flutter/material.dart';
import 'order_provider.dart';

/// Страница "Мои заказы"
class OrdersPage extends StatelessWidget {
  const OrdersPage({super.key});

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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Мои заказы'),
        backgroundColor: const Color(0xFF004D40),
      ),
      body: ListenableBuilder(
        listenable: OrderProvider.of(context),
        builder: (context, _) {
          final orderProvider = OrderProvider.of(context);

          if (orderProvider.orders.isEmpty) {
            return const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.receipt_long_outlined,
                    size: 80,
                    color: Colors.grey,
                  ),
                  SizedBox(height: 16),
                  Text(
                    'У вас пока нет заказов',
                    style: TextStyle(
                      fontSize: 20,
                      color: Colors.grey,
                    ),
                  ),
                ],
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(8),
            itemCount: orderProvider.orders.length,
            itemBuilder: (context, index) {
              final order = orderProvider.orders[index];
              final dateTime = order.createdAt;

              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: ExpansionTile(
                  leading: CircleAvatar(
                    backgroundColor: order.status == 'completed'
                        ? Colors.green
                        : order.status == 'rejected'
                            ? Colors.red
                            : _getStatusColor(order.status),
                    child: order.status == 'completed'
                        ? const Icon(
                            Icons.check,
                            color: Colors.white,
                          )
                        : order.status == 'rejected'
                            ? const Icon(
                                Icons.close,
                                color: Colors.white,
                              )
                            : const Icon(
                                Icons.receipt,
                                color: Colors.white,
                              ),
                  ),
                  title: Text(
                    'Заказ #${order.id.substring(order.id.length - 6)}',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${dateTime.day}.${dateTime.month}.${dateTime.year} ${dateTime.hour}:${dateTime.minute.toString().padLeft(2, '0')}',
                        style: const TextStyle(fontSize: 12),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: order.status == 'completed'
                                  ? Colors.green.withOpacity(0.2)
                                  : order.status == 'rejected'
                                      ? Colors.red.withOpacity(0.2)
                                      : _getStatusColor(order.status).withOpacity(0.2),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (order.status == 'completed')
                                  const Icon(
                                    Icons.check_circle,
                                    color: Colors.green,
                                    size: 14,
                                  ),
                                if (order.status == 'rejected')
                                  const Icon(
                                    Icons.cancel,
                                    color: Colors.red,
                                    size: 14,
                                  ),
                                if (order.status == 'completed' || order.status == 'rejected')
                                  const SizedBox(width: 4),
                                Text(
                                  _getStatusText(order.status),
                                  style: TextStyle(
                                    color: order.status == 'completed'
                                        ? Colors.green
                                        : order.status == 'rejected'
                                            ? Colors.red
                                            : _getStatusColor(order.status),
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      // Показываем сотрудника, если заказ принят
                      if (order.acceptedBy != null &&
                          order.acceptedBy!.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            const Icon(
                              Icons.person,
                              size: 14,
                              color: Colors.grey,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              'Принял: ${order.acceptedBy}',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey[700],
                                fontStyle: FontStyle.italic,
                              ),
                            ),
                          ],
                        ),
                      ],
                      // Показываем информацию об отказе
                      if (order.rejectedBy != null &&
                          order.rejectedBy!.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            const Icon(
                              Icons.person_off,
                              size: 14,
                              color: Colors.red,
                            ),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                'Отказал: ${order.rejectedBy}',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.red[700],
                                  fontStyle: FontStyle.italic,
                                ),
                              ),
                            ),
                          ],
                        ),
                        if (order.rejectionReason != null &&
                            order.rejectionReason!.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.red[50],
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.red[200]!),
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Icon(
                                  Icons.info_outline,
                                  size: 16,
                                  color: Colors.red,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    'Причина: ${order.rejectionReason}',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.red[900],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ],
                  ),
                  trailing: Text(
                    '${order.totalPrice.toStringAsFixed(0)} ₽',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF004D40),
                    ),
                  ),
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Список товаров
                          const Text(
                            'Товары:',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                          const SizedBox(height: 8),
                          ...order.items.map((item) => Padding(
                                padding: const EdgeInsets.symmetric(vertical: 4),
                                child: Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Expanded(
                                      child: Text(
                                        '${item.menuItem.name} × ${item.quantity}',
                                        style: const TextStyle(fontSize: 14),
                                      ),
                                    ),
                                    Text(
                                      '${item.totalPrice.toStringAsFixed(0)} ₽',
                                      style: const TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                              )),
                          // Комментарий
                          if (order.comment != null &&
                              order.comment!.isNotEmpty) ...[
                            const SizedBox(height: 16),
                            const Divider(),
                            const SizedBox(height: 8),
                            const Text(
                              'Комментарий:',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.grey[100],
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                order.comment!,
                                style: const TextStyle(fontSize: 14),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}

