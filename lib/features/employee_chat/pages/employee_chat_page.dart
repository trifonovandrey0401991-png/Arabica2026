import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../models/employee_chat_model.dart';
import '../models/employee_chat_message_model.dart';
import '../services/employee_chat_service.dart';
import '../services/chat_websocket_service.dart';
import '../widgets/chat_message_bubble.dart';
import '../widgets/chat_input_field.dart';

/// Страница чата
class EmployeeChatPage extends StatefulWidget {
  final EmployeeChat chat;
  final String userPhone;
  final String userName;
  final bool isAdmin;

  const EmployeeChatPage({
    super.key,
    required this.chat,
    required this.userPhone,
    required this.userName,
    this.isAdmin = false,
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

  // WebSocket
  StreamSubscription? _newMessageSub;
  StreamSubscription? _messageDeletedSub;
  StreamSubscription? _chatClearedSub;
  StreamSubscription? _typingSub;
  StreamSubscription? _reactionAddedSub;
  StreamSubscription? _reactionRemovedSub;

  // Typing indicator
  String? _typingPhone;
  Timer? _typingDebounceTimer;

  // Search mode
  bool _isSearching = false;
  final TextEditingController _searchController = TextEditingController();
  List<EmployeeChatMessage> _searchResults = [];
  bool _isSearchLoading = false;

  @override
  void initState() {
    super.initState();
    _loadMessages();
    _startAutoRefresh();
    _setupWebSocket();
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    _searchController.dispose();
    _refreshTimer?.cancel();
    _typingDebounceTimer?.cancel();
    _newMessageSub?.cancel();
    _messageDeletedSub?.cancel();
    _chatClearedSub?.cancel();
    _typingSub?.cancel();
    _reactionAddedSub?.cancel();
    _reactionRemovedSub?.cancel();
    super.dispose();
  }

  void _startAutoRefresh() {
    // Увеличиваем интервал так как WebSocket доставляет сообщения мгновенно
    // Polling оставляем как fallback на случай проблем с WebSocket
    _refreshTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (mounted) _loadMessages(silent: true);
    });
  }

  void _setupWebSocket() {
    final ws = ChatWebSocketService.instance;

    // Подключаемся если ещё не подключены
    ws.connect(widget.userPhone);

    // Новые сообщения
    _newMessageSub = ws.onNewMessage.listen((event) {
      if (event.chatId == widget.chat.id && mounted) {
        // Проверяем что сообщение ещё не добавлено
        if (!_messages.any((m) => m.id == event.message.id)) {
          setState(() {
            _messages.add(event.message);
          });
          // Скроллим если мы внизу
          if (_scrollController.hasClients &&
              _scrollController.position.pixels >=
                  _scrollController.position.maxScrollExtent - 100) {
            _scrollToBottom();
          }
          // Отмечаем как прочитанное
          EmployeeChatService.markAsRead(widget.chat.id, widget.userPhone);
        }
      }
    });

    // Удаление сообщений
    _messageDeletedSub = ws.onMessageDeleted.listen((event) {
      if (event.chatId == widget.chat.id && mounted) {
        setState(() {
          _messages.removeWhere((m) => m.id == event.messageId);
        });
      }
    });

    // Очистка чата
    _chatClearedSub = ws.onChatCleared.listen((event) {
      if (event.chatId == widget.chat.id && mounted) {
        setState(() {
          _messages.clear();
        });
      }
    });

    // Typing indicator
    _typingSub = ws.onTyping.listen((event) {
      if (event.chatId == widget.chat.id &&
          event.phone != widget.userPhone &&
          mounted) {
        setState(() {
          _typingPhone = event.isTyping ? event.phone : null;
        });
      }
    });

    // Реакция добавлена
    _reactionAddedSub = ws.onReactionAdded.listen((event) {
      if (event.chatId == widget.chat.id && mounted) {
        _updateMessageReaction(event.messageId, event.reaction, event.phone, true);
      }
    });

    // Реакция удалена
    _reactionRemovedSub = ws.onReactionRemoved.listen((event) {
      if (event.chatId == widget.chat.id && mounted) {
        _updateMessageReaction(event.messageId, event.reaction, event.phone, false);
      }
    });
  }

  void _updateMessageReaction(String messageId, String reaction, String phone, bool add) {
    final index = _messages.indexWhere((m) => m.id == messageId);
    if (index == -1) return;

    final msg = _messages[index];
    final newReactions = Map<String, List<String>>.from(
      msg.reactions.map((k, v) => MapEntry(k, List<String>.from(v))),
    );

    if (add) {
      if (!newReactions.containsKey(reaction)) {
        newReactions[reaction] = [];
      }
      if (!newReactions[reaction]!.contains(phone)) {
        newReactions[reaction]!.add(phone);
      }
    } else {
      if (newReactions.containsKey(reaction)) {
        newReactions[reaction]!.remove(phone);
        if (newReactions[reaction]!.isEmpty) {
          newReactions.remove(reaction);
        }
      }
    }

    setState(() {
      _messages[index] = msg.copyWith(reactions: newReactions);
    });
  }

  void _onTextChanged(String text) {
    // Отправляем typing event с debounce
    _typingDebounceTimer?.cancel();
    if (text.isNotEmpty) {
      ChatWebSocketService.instance.sendTypingStart(widget.chat.id);
      // Автоматически остановить через 3 секунды если пользователь перестал печатать
      _typingDebounceTimer = Timer(const Duration(seconds: 3), () {
        ChatWebSocketService.instance.sendTypingStop(widget.chat.id);
      });
    } else {
      ChatWebSocketService.instance.sendTypingStop(widget.chat.id);
    }
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

  void _showClearMessagesDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Очистить сообщения'),
        content: const Text('Выберите период для удаления:'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Отмена'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _confirmClearMessages('previous_month', 'за предыдущий месяц');
            },
            child: const Text('За предыдущий месяц'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _confirmClearMessages('all', 'все');
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Все сообщения'),
          ),
        ],
      ),
    );
  }

  void _confirmClearMessages(String mode, String periodText) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Вы уверены?'),
        content: Text(
          'Будут удалены $periodText сообщения.\nЭто действие нельзя отменить.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Отмена'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              await _clearMessages(mode);
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Удалить'),
          ),
        ],
      ),
    );
  }

  // ===== РЕАКЦИИ И ПЕРЕСЫЛКА =====

  Future<void> _handleReaction(EmployeeChatMessage message, String reaction) async {
    final hasReaction = message.hasReactionFrom(widget.userPhone, reaction);

    if (hasReaction) {
      // Удаляем реакцию
      await EmployeeChatService.removeReaction(
        chatId: widget.chat.id,
        messageId: message.id,
        phone: widget.userPhone,
        reaction: reaction,
      );
    } else {
      // Добавляем реакцию
      await EmployeeChatService.addReaction(
        chatId: widget.chat.id,
        messageId: message.id,
        phone: widget.userPhone,
        reaction: reaction,
      );
    }
  }

  void _showForwardDialog(EmployeeChatMessage message) {
    // TODO: Показать диалог выбора чата для пересылки
    // Пока показываем простой snackbar
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Функция пересылки будет доступна в следующем обновлении'),
        backgroundColor: Color(0xFF004D40),
      ),
    );
  }

  // ===== ПОИСК =====

  Future<void> _searchMessages(String query) async {
    if (query.length < 2) {
      setState(() {
        _searchResults = [];
        _isSearchLoading = false;
      });
      return;
    }

    setState(() => _isSearchLoading = true);

    try {
      final results = await EmployeeChatService.searchMessages(
        widget.chat.id,
        query,
      );
      if (mounted) {
        setState(() {
          _searchResults = results;
          _isSearchLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSearchLoading = false);
      }
    }
  }

  void _scrollToMessage(String messageId) {
    final index = _messages.indexWhere((m) => m.id == messageId);
    if (index == -1) return;

    // Закрываем поиск
    setState(() {
      _isSearching = false;
      _searchController.clear();
      _searchResults = [];
    });

    // Скроллим к сообщению
    if (_scrollController.hasClients) {
      // Примерная высота элемента
      final estimatedOffset = index * 80.0;
      _scrollController.animateTo(
        estimatedOffset.clamp(0, _scrollController.position.maxScrollExtent),
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  Future<void> _clearMessages(String mode) async {
    final deletedCount = await EmployeeChatService.clearChatMessages(
      widget.chat.id,
      mode,
      requesterPhone: widget.userPhone,
    );

    if (mounted) {
      if (deletedCount > 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Удалено $deletedCount сообщений'),
            backgroundColor: Colors.green,
          ),
        );
        _loadMessages();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Нет сообщений для удаления'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: _isSearching ? _buildSearchAppBar() : _buildNormalAppBar(),
      body: Column(
        children: [
          // Результаты поиска
          if (_isSearching && _searchResults.isNotEmpty)
            Container(
              color: Colors.grey[100],
              constraints: const BoxConstraints(maxHeight: 200),
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: _searchResults.length,
                itemBuilder: (context, index) {
                  final msg = _searchResults[index];
                  return ListTile(
                    dense: true,
                    leading: Icon(
                      Icons.message,
                      color: Colors.grey[600],
                      size: 20,
                    ),
                    title: Text(
                      msg.text,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      '${msg.senderName} • ${msg.formattedTime}',
                      style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                    ),
                    onTap: () => _scrollToMessage(msg.id),
                  );
                },
              ),
            ),
          if (_isSearching && _isSearchLoading)
            const LinearProgressIndicator(),
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
                                userPhone: widget.userPhone,
                                onReactionTap: (reaction) => _handleReaction(message, reaction),
                                onForwardTap: () => _showForwardDialog(message),
                              ),
                            ],
                          );
                        },
                      ),
          ),
          // Typing indicator
          if (_typingPhone != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              alignment: Alignment.centerLeft,
              child: Text(
                'печатает...',
                style: TextStyle(
                  fontSize: 12,
                  fontStyle: FontStyle.italic,
                  color: Colors.grey[600],
                ),
              ),
            ),
          ChatInputField(
            controller: _messageController,
            isSending: _isSending,
            onSend: () {
              // Останавливаем typing при отправке
              ChatWebSocketService.instance.sendTypingStop(widget.chat.id);
              _sendMessage();
            },
            onAttach: _showImageSourceDialog,
            onChanged: _onTextChanged,
          ),
        ],
      ),
    );
  }

  AppBar _buildNormalAppBar() {
    return AppBar(
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
          icon: const Icon(Icons.search),
          onPressed: () => setState(() => _isSearching = true),
          tooltip: 'Поиск',
        ),
        if (widget.isAdmin)
          IconButton(
            icon: const Icon(Icons.delete_sweep),
            onPressed: _showClearMessagesDialog,
            tooltip: 'Очистить сообщения',
          ),
        IconButton(
          icon: const Icon(Icons.refresh),
          onPressed: _loadMessages,
          tooltip: 'Обновить',
        ),
      ],
    );
  }

  AppBar _buildSearchAppBar() {
    return AppBar(
      backgroundColor: const Color(0xFF004D40),
      leading: IconButton(
        icon: const Icon(Icons.arrow_back),
        onPressed: () {
          setState(() {
            _isSearching = false;
            _searchController.clear();
            _searchResults = [];
          });
        },
      ),
      title: TextField(
        controller: _searchController,
        autofocus: true,
        style: const TextStyle(color: Colors.white),
        decoration: const InputDecoration(
          hintText: 'Поиск сообщений...',
          hintStyle: TextStyle(color: Colors.white60),
          border: InputBorder.none,
        ),
        onChanged: _searchMessages,
      ),
      actions: [
        if (_searchController.text.isNotEmpty)
          IconButton(
            icon: const Icon(Icons.close),
            onPressed: () {
              _searchController.clear();
              setState(() => _searchResults = []);
            },
          ),
      ],
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
