import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/client_dialog_model.dart';
import '../services/client_dialog_service.dart';
import '../../../shared/models/unified_dialog_message_model.dart';

class ClientDialogPage extends StatefulWidget {
  final String shopAddress;

  const ClientDialogPage({
    super.key,
    required this.shopAddress,
  });

  @override
  State<ClientDialogPage> createState() => _ClientDialogPageState();
}

class _ClientDialogPageState extends State<ClientDialogPage> {
  ClientDialog? _dialog;
  bool _isLoading = true;
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _loadDialog();
    _startAutoRefresh();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _startAutoRefresh() {
    Future.delayed(const Duration(seconds: 5), () {
      if (mounted) {
        _loadDialog();
        _startAutoRefresh();
      }
    });
  }

  Future<void> _loadDialog() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final clientPhone = prefs.getString('user_phone') ?? '';
      
      if (clientPhone.isEmpty) {
        setState(() {
          _isLoading = false;
        });
        return;
      }

      final dialog = await ClientDialogService.getShopDialog(clientPhone, widget.shopAddress);
      
      if (mounted) {
        setState(() {
          _dialog = dialog;
          _isLoading = false;
        });
        
        // Прокручиваем вниз после загрузки
        if (_scrollController.hasClients) {
          _scrollController.animateTo(
            0,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка загрузки диалога: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  String _formatTimestamp(String timestamp) {
    try {
      final date = DateTime.parse(timestamp);
      final now = DateTime.now();
      final difference = now.difference(date);

      if (difference.inDays == 0) {
        return '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
      } else if (difference.inDays == 1) {
        return 'Вчера ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
      } else {
        return '${date.day}.${date.month}.${date.year} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
      }
    } catch (e) {
      return timestamp;
    }
  }

  Widget _buildMessage(UnifiedDialogMessage message) {
    final isFromClient = message.senderType == 'client';
    
    // Заказы отображаются как карточки
    if (message.type == 'order') {
      return _buildOrderCard(message);
    }
    
    // Остальные сообщения отображаются как обычные сообщения
    return Align(
      alignment: isFromClient ? Alignment.centerLeft : Alignment.centerRight,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isFromClient ? Colors.grey[300] : const Color(0xFF004D40),
          borderRadius: BorderRadius.circular(12),
        ),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.7,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Заголовок для отзывов
            if (message.type == 'review') ...[
              Row(
                children: [
                  Icon(
                    message.data['reviewType'] == 'positive' ? Icons.thumb_up : Icons.thumb_down,
                    size: 16,
                    color: message.data['reviewType'] == 'positive' ? Colors.green : Colors.red,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    message.data['reviewType'] == 'positive' ? 'Положительный отзыв' : 'Отрицательный отзыв',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: isFromClient ? Colors.black54 : Colors.white70,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
            ],
            
            // Заголовок для ответов сотрудников
            if (!isFromClient) ...[
              Text(
                'Ответ от магазина ${message.shopAddress}',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: Colors.white70,
                ),
              ),
              const SizedBox(height: 4),
            ],
            
            // Текст сообщения
            Text(
              message.getDisplayText(),
              style: TextStyle(
                color: isFromClient ? Colors.black87 : Colors.white,
              ),
            ),
            
            // Изображение, если есть
            if (message.getImageUrl() != null) ...[
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.network(
                  message.getImageUrl()!,
                  width: double.infinity,
                  fit: BoxFit.cover,
                ),
              ),
            ],
            
            // Время
            const SizedBox(height: 4),
            Text(
              _formatTimestamp(message.timestamp),
              style: TextStyle(
                fontSize: 10,
                color: isFromClient ? Colors.black54 : Colors.white70,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOrderCard(UnifiedDialogMessage message) {
    final orderData = message.data;
    final status = orderData['status'] ?? 'pending';
    final orderId = orderData['orderId'] ?? message.id;
    final totalPrice = orderData['totalPrice'] ?? 0.0;
    final items = orderData['items'] ?? [];
    
    Color statusColor;
    String statusText;
    IconData statusIcon;
    
    switch (status) {
      case 'pending':
        statusColor = Colors.orange;
        statusText = 'Ожидает';
        statusIcon = Icons.access_time;
        break;
      case 'preparing':
        statusColor = Colors.blue;
        statusText = 'Готовится';
        statusIcon = Icons.restaurant;
        break;
      case 'ready':
        statusColor = Colors.green;
        statusText = 'Готов';
        statusIcon = Icons.check_circle;
        break;
      case 'completed':
        statusColor = Colors.grey;
        statusText = 'Завершен';
        statusIcon = Icons.done_all;
        break;
      case 'rejected':
        statusColor = Colors.red;
        statusText = 'Отклонен';
        statusIcon = Icons.cancel;
        break;
      default:
        statusColor = Colors.grey;
        statusText = status;
        statusIcon = Icons.info;
    }
    
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      child: Card(
        elevation: 2,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(statusIcon, color: statusColor, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Заказ #${orderId.toString().substring(orderId.toString().length - 6)}',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: statusColor.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      statusText,
                      style: TextStyle(
                        color: statusColor,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              if (items.isNotEmpty) ...[
                const SizedBox(height: 8),
                const Divider(),
                ...items.map<Widget>((item) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          '${item['name'] ?? ''} x${item['quantity'] ?? 1}',
                        ),
                      ),
                      Text(
                        '${item['total'] ?? 0} ₽',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                )),
              ],
              const Divider(),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Итого:',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  Text(
                    '$totalPrice ₽',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                ],
              ),
              if (orderData['comment'] != null && orderData['comment'].toString().isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  'Комментарий: ${orderData['comment']}',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[600],
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
              if (orderData['acceptedBy'] != null) ...[
                const SizedBox(height: 4),
                Text(
                  'Принят: ${orderData['acceptedBy']}',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.green[700],
                  ),
                ),
              ],
              if (orderData['rejectedBy'] != null) ...[
                const SizedBox(height: 4),
                Text(
                  'Отклонен: ${orderData['rejectedBy']}',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.red[700],
                  ),
                ),
                if (orderData['rejectionReason'] != null)
                  Text(
                    'Причина: ${orderData['rejectionReason']}',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.red[600],
                      fontStyle: FontStyle.italic,
                    ),
                  ),
              ],
              const SizedBox(height: 4),
              Text(
                _formatTimestamp(message.timestamp),
                style: TextStyle(
                  fontSize: 10,
                  color: Colors.grey[600],
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
        title: Text(_dialog?.shopAddress ?? widget.shopAddress),
        backgroundColor: const Color(0xFF004D40),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadDialog,
            tooltip: 'Обновить',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _dialog == null || _dialog!.messages.isEmpty
              ? const Center(
                  child: Text(
                    'Нет сообщений',
                    style: TextStyle(color: Colors.grey),
                  ),
                )
              : ListView.builder(
                  controller: _scrollController,
                  reverse: true,
                  padding: const EdgeInsets.all(16),
                  itemCount: _dialog!.messages.length,
                  itemBuilder: (context, index) {
                    final message = _dialog!.messages[_dialog!.messages.length - 1 - index];
                    return _buildMessage(message);
                  },
                ),
    );
  }
}



