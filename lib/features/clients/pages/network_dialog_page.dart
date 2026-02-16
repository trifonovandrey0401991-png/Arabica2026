import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/network_message_model.dart';
import '../services/network_message_service.dart';
import '../../../shared/widgets/media_message_widget.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

/// Страница диалога "Сообщение от Всей Сети"
class NetworkDialogPage extends StatefulWidget {
  const NetworkDialogPage({super.key});

  @override
  State<NetworkDialogPage> createState() => _NetworkDialogPageState();
}

class _NetworkDialogPageState extends State<NetworkDialogPage> {
  List<NetworkMessage> _messages = [];
  bool _isLoading = true;
  bool _isSending = false;
  String? _userPhone;
  String? _userName;
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _loadMessages();
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadMessages() async {
    setState(() => _isLoading = true);

    try {
      final prefs = await SharedPreferences.getInstance();
      _userPhone = prefs.getString('user_phone') ?? prefs.getString('userPhone') ?? '';
      _userName = prefs.getString('user_name') ?? prefs.getString('userName');

      if (_userPhone!.isEmpty) {
        setState(() => _isLoading = false);
        return;
      }

      final data = await NetworkMessageService.getNetworkMessages(_userPhone!);

      // Отмечаем сообщения как прочитанные
      if (data.hasUnread) {
        NetworkMessageService.markAsReadByClient(_userPhone!);
      }

      setState(() {
        _messages = data.messages;
        _isLoading = false;
      });

      // Прокручиваем к последнему сообщению
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollController.hasClients && _messages.isNotEmpty) {
          _scrollController.animateTo(
            _scrollController.position.maxScrollExtent,
            duration: Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
        }
      });
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка загрузки: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _sendMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty || _userPhone == null || _userPhone!.isEmpty) return;

    setState(() => _isSending = true);

    final message = await NetworkMessageService.sendReply(
      clientPhone: _userPhone!,
      text: text,
      clientName: _userName,
    );

    setState(() => _isSending = false);

    if (message != null) {
      setState(() {
        _messages.add(message);
        _messageController.clear();
      });

      // Прокручиваем к новому сообщению
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollController.hasClients) {
          _scrollController.animateTo(
            _scrollController.position.maxScrollExtent,
            duration: Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
        }
      });
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка отправки'), backgroundColor: Colors.red),
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
        return '${date.day}.${date.month}.${date.year}';
      }
    } catch (e) {
      return timestamp;
    }
  }

  Widget _buildMessage(NetworkMessage message) {
    final isFromAdmin = message.isFromAdmin;

    return Align(
      alignment: isFromAdmin ? Alignment.centerLeft : Alignment.centerRight,
      child: Container(
        margin: EdgeInsets.only(
          left: isFromAdmin ? 8 : 48,
          right: isFromAdmin ? 48 : 8,
          bottom: 8.h,
        ),
        padding: EdgeInsets.all(12.w),
        decoration: BoxDecoration(
          color: isFromAdmin ? Colors.grey[200] : Color(0xFF004D40),
          borderRadius: BorderRadius.circular(16.r),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (isFromAdmin)
              Padding(
                padding: EdgeInsets.only(bottom: 4.h),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.language, size: 14, color: Colors.grey[600]),
                    SizedBox(width: 4),
                    Text(
                      'Сообщение от Всей Сети',
                      style: TextStyle(
                        fontSize: 12.sp,
                        color: Colors.grey[600],
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            if (message.text.isNotEmpty)
              Text(
                message.text,
                style: TextStyle(
                  color: isFromAdmin ? Colors.black87 : Colors.white,
                ),
              ),
            if (message.imageUrl != null) ...[
              SizedBox(height: 8),
              MediaMessageWidget(mediaUrl: message.imageUrl, maxHeight: 200),
            ],
            SizedBox(height: 4),
            Text(
              _formatTimestamp(message.timestamp),
              style: TextStyle(
                fontSize: 10.sp,
                color: isFromAdmin ? Colors.grey : Colors.white70,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Icon(Icons.language, size: 24),
            SizedBox(width: 8),
            Text('Сообщение от Всей Сети'),
          ],
        ),
        backgroundColor: Color(0xFF004D40),
        actions: [
          IconButton(
            icon: Icon(Icons.refresh),
            onPressed: _loadMessages,
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: _isLoading
                ? Center(child: CircularProgressIndicator())
                : _messages.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.chat_bubble_outline, size: 64, color: Colors.grey[400]),
                            SizedBox(height: 16),
                            Text(
                              'Нет сообщений',
                              style: TextStyle(color: Colors.grey[600], fontSize: 18.sp),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        controller: _scrollController,
                        padding: EdgeInsets.symmetric(vertical: 16.h),
                        itemCount: _messages.length,
                        itemBuilder: (context, index) => _buildMessage(_messages[index]),
                      ),
          ),
          Container(
            padding: EdgeInsets.all(8.w),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 4,
                  offset: Offset(0, -2),
                ),
              ],
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _messageController,
                    decoration: InputDecoration(
                      hintText: 'Написать ответ...',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24.r),
                        borderSide: BorderSide.none,
                      ),
                      filled: true,
                      fillColor: Colors.grey[100],
                      contentPadding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 8.h),
                    ),
                    maxLines: 3,
                    minLines: 1,
                  ),
                ),
                SizedBox(width: 8),
                IconButton(
                  onPressed: _isSending ? null : _sendMessage,
                  icon: _isSending
                      ? SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Icon(Icons.send, color: Color(0xFF004D40)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
