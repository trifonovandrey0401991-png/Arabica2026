import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../models/employee_chat_model.dart';
import '../models/employee_chat_message_model.dart';
import '../services/employee_chat_service.dart';
import '../widgets/chat_message_bubble.dart';
import '../widgets/chat_input_field.dart';

/// Страница чата
class EmployeeChatPage extends StatefulWidget {
  final EmployeeChat chat;
  final String userPhone;
  final String userName;

  const EmployeeChatPage({
    super.key,
    required this.chat,
    required this.userPhone,
    required this.userName,
  });

  @override
  State<EmployeeChatPage> createState() => _EmployeeChatPageState();
}

class _EmployeeChatPageState extends State<EmployeeChatPage> {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final ImagePicker _imagePicker = ImagePicker();

  List<EmployeeChatMessage> _messages = [];
  bool _isLoading = true;
  bool _isSending = false;
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _loadMessages();
    _startAutoRefresh();
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    _refreshTimer?.cancel();
    super.dispose();
  }

  void _startAutoRefresh() {
    _refreshTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (mounted) _loadMessages(silent: true);
    });
  }

  Future<void> _loadMessages({bool silent = false}) async {
    if (!silent) {
      setState(() => _isLoading = true);
    }

    try {
      final messages = await EmployeeChatService.getMessages(
        widget.chat.id,
        phone: widget.userPhone,
      );

      if (mounted) {
        final wasEmpty = _messages.isEmpty;
        final hadNewMessages = messages.length > _messages.length;

        // Проверяем, находится ли пользователь внизу списка
        final isAtBottom = _scrollController.hasClients &&
            _scrollController.position.pixels >=
            _scrollController.position.maxScrollExtent - 100;

        setState(() {
          _messages = messages;
          _isLoading = false;
        });

        // Отмечаем как прочитанное
        if (messages.isNotEmpty) {
          EmployeeChatService.markAsRead(widget.chat.id, widget.userPhone);
        }

        // Скроллим к последнему сообщению если:
        // - первая загрузка (wasEmpty)
        // - пользователь уже был внизу и пришли новые сообщения
        // - не silent режим и есть новые сообщения
        if (wasEmpty || (hadNewMessages && (isAtBottom || !silent))) {
          _scrollToBottom();
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        if (!silent) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Ошибка загрузки: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      Future.delayed(const Duration(milliseconds: 100), () {
        if (_scrollController.hasClients) {
          _scrollController.animateTo(
            _scrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
        }
      });
    }
  }

  Future<void> _sendMessage({String? imageUrl}) async {
    final text = _messageController.text.trim();

    if (text.isEmpty && imageUrl == null) return;

    setState(() => _isSending = true);
    _messageController.clear();

    try {
      final message = await EmployeeChatService.sendMessage(
        chatId: widget.chat.id,
        senderPhone: widget.userPhone,
        senderName: widget.userName,
        text: text,
        imageUrl: imageUrl,
      );

      if (message != null && mounted) {
        setState(() {
          _messages.add(message);
          _isSending = false;
        });
        _scrollToBottom();
      } else {
        if (mounted) {
          setState(() => _isSending = false);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Ошибка отправки сообщения'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSending = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _pickAndSendImage() async {
    try {
      final XFile? image = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 85,
      );

      if (image == null) return;

      setState(() => _isSending = true);

      // Показываем индикатор загрузки
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Row(
              children: [
                SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                ),
                SizedBox(width: 16),
                Text('Загрузка фото...'),
              ],
            ),
            duration: Duration(seconds: 30),
          ),
        );
      }

      final photoUrl = await EmployeeChatService.uploadMessagePhoto(File(image.path));

      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
      }

      if (photoUrl != null) {
        await _sendMessage(imageUrl: photoUrl);
      } else {
        if (mounted) {
          setState(() => _isSending = false);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Ошибка загрузки фото'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        setState(() => _isSending = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _takePhoto() async {
    try {
      final XFile? image = await _imagePicker.pickImage(
        source: ImageSource.camera,
        imageQuality: 85,
      );

      if (image == null) return;

      setState(() => _isSending = true);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Row(
              children: [
                SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                ),
                SizedBox(width: 16),
                Text('Загрузка фото...'),
              ],
            ),
            duration: Duration(seconds: 30),
          ),
        );
      }

      final photoUrl = await EmployeeChatService.uploadMessagePhoto(File(image.path));

      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
      }

      if (photoUrl != null) {
        await _sendMessage(imageUrl: photoUrl);
      } else {
        if (mounted) {
          setState(() => _isSending = false);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Ошибка загрузки фото'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        setState(() => _isSending = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _showImageSourceDialog() {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt),
              title: const Text('Камера'),
              onTap: () {
                Navigator.pop(context);
                _takePhoto();
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('Галерея'),
              onTap: () {
                Navigator.pop(context);
                _pickAndSendImage();
              },
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
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.chat.displayName,
              style: const TextStyle(fontSize: 16),
            ),
            if (widget.chat.type == EmployeeChatType.shop)
              Text(
                widget.chat.shopAddress ?? '',
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.normal),
              ),
          ],
        ),
        backgroundColor: const Color(0xFF004D40),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadMessages,
            tooltip: 'Обновить',
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _messages.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.chat_bubble_outline,
                              size: 64,
                              color: Colors.grey[400],
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'Нет сообщений',
                              style: TextStyle(
                                fontSize: 18,
                                color: Colors.grey[600],
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Начните общение!',
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.grey[500],
                              ),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        controller: _scrollController,
                        padding: const EdgeInsets.all(8),
                        itemCount: _messages.length,
                        itemBuilder: (context, index) {
                          final message = _messages[index];
                          final isMe = message.senderPhone == widget.userPhone;

                          // Показывать дату если это первое сообщение или дата изменилась
                          bool showDate = false;
                          if (index == 0) {
                            showDate = true;
                          } else {
                            final prevMessage = _messages[index - 1];
                            final prevDate = DateTime(
                              prevMessage.timestamp.year,
                              prevMessage.timestamp.month,
                              prevMessage.timestamp.day,
                            );
                            final currDate = DateTime(
                              message.timestamp.year,
                              message.timestamp.month,
                              message.timestamp.day,
                            );
                            showDate = prevDate != currDate;
                          }

                          return Column(
                            children: [
                              if (showDate) _buildDateSeparator(message.timestamp),
                              ChatMessageBubble(
                                message: message,
                                isMe: isMe,
                                showSenderName: widget.chat.type != EmployeeChatType.private && !isMe,
                              ),
                            ],
                          );
                        },
                      ),
          ),
          ChatInputField(
            controller: _messageController,
            isSending: _isSending,
            onSend: () => _sendMessage(),
            onAttach: _showImageSourceDialog,
          ),
        ],
      ),
    );
  }

  Widget _buildDateSeparator(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final messageDate = DateTime(date.year, date.month, date.day);

    String dateText;
    if (messageDate == today) {
      dateText = 'Сегодня';
    } else if (messageDate == today.subtract(const Duration(days: 1))) {
      dateText = 'Вчера';
    } else {
      dateText = '${date.day}.${date.month.toString().padLeft(2, '0')}.${date.year}';
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Row(
        children: [
          Expanded(child: Divider(color: Colors.grey[300])),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              dateText,
              style: TextStyle(
                color: Colors.grey[600],
                fontSize: 12,
              ),
            ),
          ),
          Expanded(child: Divider(color: Colors.grey[300])),
        ],
      ),
    );
  }
}
