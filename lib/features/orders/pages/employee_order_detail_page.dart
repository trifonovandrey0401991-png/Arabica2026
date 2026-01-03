import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/order_service.dart';

class EmployeeOrderDetailPage extends StatefulWidget {
  final Map<String, dynamic> orderData;

  const EmployeeOrderDetailPage({
    super.key,
    required this.orderData,
  });

  @override
  State<EmployeeOrderDetailPage> createState() => _EmployeeOrderDetailPageState();
}

class _EmployeeOrderDetailPageState extends State<EmployeeOrderDetailPage> {
  bool _isProcessing = false;

  String _formatPrice(dynamic price) {
    if (price == null) return '0';
    if (price is num) {
      return price.toStringAsFixed(0);
    }
    return price.toString();
  }

  Future<void> _acceptOrder() async {
    setState(() {
      _isProcessing = true;
    });

    try {
      final prefs = await SharedPreferences.getInstance();
      final employeeName = prefs.getString('employee_name') ?? prefs.getString('user_name') ?? 'Сотрудник';

      final success = await OrderService.updateOrderStatus(
        orderId: widget.orderData['id'],
        status: 'accepted',
        acceptedBy: employeeName,
      );

      if (success && mounted) {
        final orderNumber = widget.orderData['orderNumber'];
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              orderNumber != null
                  ? 'Заказ #$orderNumber принят'
                  : 'Заказ принят',
            ),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context, true);
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Ошибка при принятии заказа'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isProcessing = false;
        });
      }
    }
  }

  Future<void> _rejectOrder() async {
    final reasonController = TextEditingController();

    final reason = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Причина отказа'),
        content: TextField(
          controller: reasonController,
          decoration: const InputDecoration(
            hintText: 'Укажите причину отказа',
            border: OutlineInputBorder(),
          ),
          maxLines: 3,
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Отмена'),
          ),
          ElevatedButton(
            onPressed: () {
              if (reasonController.text.trim().isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Укажите причину отказа'),
                    backgroundColor: Colors.orange,
                  ),
                );
                return;
              }
              Navigator.pop(context, reasonController.text.trim());
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('Отказать'),
          ),
        ],
      ),
    );

    if (reason == null || reason.isEmpty) return;

    setState(() {
      _isProcessing = true;
    });

    try {
      final prefs = await SharedPreferences.getInstance();
      final employeeName = prefs.getString('employee_name') ?? prefs.getString('user_name') ?? 'Сотрудник';

      final success = await OrderService.updateOrderStatus(
        orderId: widget.orderData['id'],
        status: 'rejected',
        rejectedBy: employeeName,
        rejectionReason: reason,
      );

      if (success && mounted) {
        final orderNumber = widget.orderData['orderNumber'];
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              orderNumber != null
                  ? 'Заказ #$orderNumber отклонен'
                  : 'Заказ отклонен',
            ),
            backgroundColor: Colors.orange,
          ),
        );
        Navigator.pop(context, true);
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Ошибка при отклонении заказа'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isProcessing = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final orderNumber = widget.orderData['orderNumber'];
    final shopAddress = widget.orderData['shopAddress'] ?? 'Неизвестный магазин';
    final clientName = widget.orderData['clientName'] ?? 'Клиент';
    final clientPhone = widget.orderData['clientPhone'] ?? '';
    final items = widget.orderData['items'] as List<dynamic>? ?? [];
    final totalPrice = widget.orderData['totalPrice'];
    final comment = widget.orderData['comment'];

    return Scaffold(
      appBar: AppBar(
        title: Text(
          orderNumber != null
              ? 'Заказ #$orderNumber'
              : 'Заказ #${widget.orderData['id'].toString().substring(0, 6)}',
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Информация о заказе',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 12),
                          _buildInfoRow(Icons.store, 'Магазин', shopAddress),
                          const SizedBox(height: 8),
                          _buildInfoRow(Icons.person, 'Клиент', clientName),
                          if (clientPhone.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            _buildInfoRow(Icons.phone, 'Телефон', clientPhone),
                          ],
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Состав заказа',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (items.isEmpty)
                    const Card(
                      child: Padding(
                        padding: EdgeInsets.all(16),
                        child: Text('Нет товаров'),
                      ),
                    )
                  else
                    ...items.map((item) {
                      final name = item['name'] ?? 'Товар';
                      final price = _formatPrice(item['price']);
                      final quantity = item['quantity'] ?? 1;
                      final total = _formatPrice(item['total']);

                      return Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      name,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w500,
                                        fontSize: 16,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      '$price ₽ × $quantity',
                                      style: const TextStyle(
                                        color: Colors.grey,
                                        fontSize: 14,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Text(
                                '$total ₽',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                  if (comment != null && comment.toString().isNotEmpty) ...[
                    const SizedBox(height: 16),
                    const Text(
                      'Комментарий',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text(
                          comment.toString(),
                          style: const TextStyle(fontSize: 14),
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  Card(
                    color: Colors.green.shade50,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Итого:',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            '${_formatPrice(totalPrice)} ₽',
                            style: const TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                              color: Colors.green,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 4,
                  offset: const Offset(0, -2),
                ),
              ],
            ),
            child: Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: _isProcessing ? null : _rejectOrder,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: _isProcessing
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                            ),
                          )
                        : const Text(
                            'Отказать',
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                          ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _isProcessing ? null : _acceptOrder,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: _isProcessing
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                            ),
                          )
                        : const Text(
                            'Принять',
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                          ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, size: 20, color: Colors.grey),
        const SizedBox(width: 8),
        Text(
          '$label: ',
          style: const TextStyle(
            fontWeight: FontWeight.w500,
            fontSize: 14,
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(fontSize: 14),
          ),
        ),
      ],
    );
  }
}
