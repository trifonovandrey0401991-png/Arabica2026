import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/client_dialog_model.dart';
import '../services/client_dialog_service.dart';
import '../../../shared/models/unified_dialog_message_model.dart';
import '../../../shared/widgets/app_cached_image.dart';
import '../../../core/theme/app_colors.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

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
    Future.delayed(Duration(seconds: 5), () {
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
        if (mounted) setState(() {
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
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_scrollController.hasClients) {
            _scrollController.animateTo(
              _scrollController.position.maxScrollExtent,
              duration: Duration(milliseconds: 300),
              curve: Curves.easeOut,
            );
          }
        });
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
      final date = DateTime.parse(timestamp).toLocal();
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
        margin: EdgeInsets.only(bottom: 8.h),
        padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 8.h),
        decoration: BoxDecoration(
          color: isFromClient ? Colors.grey[300] : AppColors.primaryGreen,
          borderRadius: BorderRadius.circular(12.r),
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
                  SizedBox(width: 4),
                  Text(
                    message.data['reviewType'] == 'positive' ? 'Положительный отзыв' : 'Отрицательный отзыв',
                    style: TextStyle(
                      fontSize: 10.sp,
                      fontWeight: FontWeight.bold,
                      color: isFromClient ? Colors.black54 : Colors.white70,
                    ),
                  ),
                ],
              ),
              SizedBox(height: 4),
            ],
            
            // Заголовок для ответов сотрудников
            if (!isFromClient) ...[
              Text(
                'Ответ от магазина ${message.shopAddress}',
                style: TextStyle(
                  fontSize: 10.sp,
                  fontWeight: FontWeight.bold,
                  color: Colors.white70,
                ),
              ),
              SizedBox(height: 4),
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
              SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(8.r),
                child: AppCachedImage(
                  imageUrl: message.getImageUrl()!,
                  width: double.infinity,
                  fit: BoxFit.cover,
                ),
              ),
            ],
            
            // Время
            SizedBox(height: 4),
            Text(
              _formatTimestamp(message.timestamp),
              style: TextStyle(
                fontSize: 10.sp,
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
      margin: EdgeInsets.only(bottom: 12.h),
      child: Card(
        elevation: 2,
        child: Padding(
          padding: EdgeInsets.all(12.w),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(statusIcon, color: statusColor, size: 20),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      message.data['orderNumber'] != null
                          ? 'Заказ ${message.data['orderNumber']}'
                          : 'Заказ ${orderId.toString().substring(orderId.toString().length - 6)}',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16.sp,
                      ),
                    ),
                  ),
                  Container(
                    padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 4.h),
                    decoration: BoxDecoration(
                      color: statusColor.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(12.r),
                    ),
                    child: Text(
                      statusText,
                      style: TextStyle(
                        color: statusColor,
                        fontSize: 12.sp,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              if (items.isNotEmpty) ...[
                SizedBox(height: 8),
                Divider(),
                ...items.map<Widget>((item) => Padding(
                  padding: EdgeInsets.symmetric(vertical: 4.h),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          '${item['name'] ?? ''} x${item['quantity'] ?? 1}',
                        ),
                      ),
                      Text(
                        '${item['total'] ?? 0} руб',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                )),
              ],
              Divider(),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Итого:',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  Text(
                    '$totalPrice руб',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16.sp,
                    ),
                  ),
                ],
              ),
              if (orderData['comment'] != null && orderData['comment'].toString().isNotEmpty) ...[
                SizedBox(height: 8),
                Text(
                  'Комментарий: ${orderData['comment']}',
                  style: TextStyle(
                    fontSize: 12.sp,
                    color: Colors.grey[600],
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
              if (orderData['acceptedBy'] != null) ...[
                SizedBox(height: 4),
                Text(
                  'Принят: ${orderData['acceptedBy']}',
                  style: TextStyle(
                    fontSize: 12.sp,
                    color: Colors.green[700],
                  ),
                ),
              ],
              if (orderData['rejectedBy'] != null) ...[
                SizedBox(height: 4),
                Text(
                  'Отклонен: ${orderData['rejectedBy']}',
                  style: TextStyle(
                    fontSize: 12.sp,
                    color: Colors.red[700],
                  ),
                ),
                if (orderData['rejectionReason'] != null)
                  Text(
                    'Причина: ${orderData['rejectionReason']}',
                    style: TextStyle(
                      fontSize: 12.sp,
                      color: Colors.red[600],
                      fontStyle: FontStyle.italic,
                    ),
                  ),
              ],
              SizedBox(height: 4),
              Text(
                _formatTimestamp(message.timestamp),
                style: TextStyle(
                  fontSize: 10.sp,
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
        backgroundColor: AppColors.primaryGreen,
        actions: [
          IconButton(
            icon: Icon(Icons.refresh),
            onPressed: _loadDialog,
            tooltip: 'Обновить',
          ),
        ],
      ),
      body: _isLoading
          ? Center(child: CircularProgressIndicator())
          : _dialog == null || _dialog!.messages.isEmpty
              ? Center(
                  child: Text(
                    'Нет сообщений',
                    style: TextStyle(color: Colors.grey),
                  ),
                )
              : ListView.builder(
                  controller: _scrollController,
                  padding: EdgeInsets.all(16.w),
                  itemCount: _dialog!.messages.length,
                  itemBuilder: (context, index) {
                    final message = _dialog!.messages[index];
                    return _buildMessage(message);
                  },
                ),
    );
  }
}



