import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import '../models/employee_chat_model.dart';
import '../models/employee_chat_message_model.dart';
import '../services/employee_chat_service.dart';
import '../services/chat_websocket_service.dart';
import '../widgets/chat_message_bubble.dart';
import '../widgets/chat_input_field.dart';
import 'group_info_page.dart';

/// Страница чата — dark emerald стиль
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

class _EmployeeChatPageState extends State<EmployeeChatPage>
    with TickerProviderStateMixin {
  // Dark emerald palette
  static const Color _emerald = Color(0xFF1A4D4D);
  static const Color _emeraldDark = Color(0xFF0D2E2E);
  static const Color _night = Color(0xFF051515);

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
  late AnimationController _typingAnimationController;

  // Search mode
  bool _isSearching = false;
  final TextEditingController _searchController = TextEditingController();
  List<EmployeeChatMessage> _searchResults = [];
  bool _isSearchLoading = false;

  @override
  void initState() {
    super.initState();
    _typingAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
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
    _typingAnimationController.dispose();
    _newMessageSub?.cancel();
    _messageDeletedSub?.cancel();
    _chatClearedSub?.cancel();
    _typingSub?.cancel();
    _reactionAddedSub?.cancel();
    _reactionRemovedSub?.cancel();
    super.dispose();
  }

  void _startAutoRefresh() {
    _refreshTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (mounted) _loadMessages(silent: true);
    });
  }

  void _setupWebSocket() {
    final ws = ChatWebSocketService.instance;
    ws.connect(widget.userPhone);

    _newMessageSub = ws.onNewMessage.listen((event) {
      if (event.chatId == widget.chat.id && mounted) {
        if (!_messages.any((m) => m.id == event.message.id)) {
          setState(() {
            _messages.add(event.message);
          });
          if (_scrollController.hasClients &&
              _scrollController.position.pixels >=
                  _scrollController.position.maxScrollExtent - 100) {
            _scrollToBottom();
          }
          EmployeeChatService.markAsRead(widget.chat.id, widget.userPhone);
        }
      }
    });

    _messageDeletedSub = ws.onMessageDeleted.listen((event) {
      if (event.chatId == widget.chat.id && mounted) {
        setState(() {
          _messages.removeWhere((m) => m.id == event.messageId);
        });
      }
    });

    _chatClearedSub = ws.onChatCleared.listen((event) {
      if (event.chatId == widget.chat.id && mounted) {
        setState(() {
          _messages.clear();
        });
      }
    });

    _typingSub = ws.onTyping.listen((event) {
      if (event.chatId == widget.chat.id &&
          event.phone != widget.userPhone &&
          mounted) {
        setState(() {
          _typingPhone = event.isTyping ? event.phone : null;
        });
      }
    });

    _reactionAddedSub = ws.onReactionAdded.listen((event) {
      if (event.chatId == widget.chat.id && mounted) {
        _updateMessageReaction(event.messageId, event.reaction, event.phone, true);
      }
    });

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
    _typingDebounceTimer?.cancel();
    if (text.isNotEmpty) {
      ChatWebSocketService.instance.sendTypingStart(widget.chat.id);
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
        final isAtBottom = _scrollController.hasClients &&
            _scrollController.position.pixels >=
                _scrollController.position.maxScrollExtent - 100;

        setState(() {
          _messages = messages;
          _isLoading = false;
        });

        if (messages.isNotEmpty) {
          EmployeeChatService.markAsRead(widget.chat.id, widget.userPhone);
        }

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
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
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
            curve: Curves.easeOutCubic,
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
    HapticFeedback.lightImpact();

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
            SnackBar(
              content: const Text('Ошибка отправки сообщения'),
              backgroundColor: Colors.red,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
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
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
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
      await _uploadAndSendImage(File(image.path));
    } catch (e) {
      _showImageError(e);
    }
  }

  Future<void> _takePhoto() async {
    try {
      final XFile? image = await _imagePicker.pickImage(
        source: ImageSource.camera,
        imageQuality: 85,
      );
      if (image == null) return;
      await _uploadAndSendImage(File(image.path));
    } catch (e) {
      _showImageError(e);
    }
  }

  Future<void> _uploadAndSendImage(File imageFile) async {
    setState(() => _isSending = true);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                  backgroundColor: Colors.white.withOpacity(0.3),
                ),
              ),
              const SizedBox(width: 16),
              const Text('Загрузка фото...'),
            ],
          ),
          duration: const Duration(seconds: 30),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          backgroundColor: _emerald,
        ),
      );
    }

    final photoUrl = await EmployeeChatService.uploadMessagePhoto(imageFile);

    if (mounted) {
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
    }

    if (photoUrl != null) {
      await _sendMessage(imageUrl: photoUrl);
    } else {
      if (mounted) {
        setState(() => _isSending = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Ошибка загрузки фото'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
      }
    }
  }

  void _showImageError(dynamic e) {
    if (mounted) {
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      setState(() => _isSending = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Ошибка: $e'),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
    }
  }

  void _showImageSourceDialog() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: BoxDecoration(
          color: _night.withOpacity(0.98),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          border: Border(
            top: BorderSide(color: Colors.white.withOpacity(0.1)),
          ),
        ),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  'Отправить фото',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: Colors.white.withOpacity(0.9),
                  ),
                ),
              ),
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: _emerald.withOpacity(0.3),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(Icons.camera_alt, color: Colors.white.withOpacity(0.8)),
                ),
                title: Text(
                  'Камера',
                  style: TextStyle(color: Colors.white.withOpacity(0.9)),
                ),
                subtitle: Text(
                  'Сделать фото',
                  style: TextStyle(color: Colors.white.withOpacity(0.4)),
                ),
                onTap: () {
                  Navigator.pop(context);
                  _takePhoto();
                },
              ),
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.purple.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(Icons.photo_library, color: Colors.purple[300]),
                ),
                title: Text(
                  'Галерея',
                  style: TextStyle(color: Colors.white.withOpacity(0.9)),
                ),
                subtitle: Text(
                  'Выбрать из галереи',
                  style: TextStyle(color: Colors.white.withOpacity(0.4)),
                ),
                onTap: () {
                  Navigator.pop(context);
                  _pickAndSendImage();
                },
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  void _showClearMessagesDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: _night.withOpacity(0.98),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.delete_sweep, color: Colors.red),
            ),
            const SizedBox(width: 12),
            Text(
              'Очистить чат',
              style: TextStyle(color: Colors.white.withOpacity(0.9)),
            ),
          ],
        ),
        content: Text(
          'Выберите период для удаления сообщений:',
          style: TextStyle(color: Colors.white.withOpacity(0.7)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              'Отмена',
              style: TextStyle(color: Colors.white.withOpacity(0.5)),
            ),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _confirmClearMessages('previous_month', 'за предыдущий месяц');
            },
            child: Text(
              'За прошлый месяц',
              style: TextStyle(color: Colors.white.withOpacity(0.8)),
            ),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _confirmClearMessages('all', 'все');
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: const Text('Все'),
          ),
        ],
      ),
    );
  }

  void _confirmClearMessages(String mode, String periodText) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: _night.withOpacity(0.98),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'Подтверждение',
          style: TextStyle(color: Colors.white.withOpacity(0.9)),
        ),
        content: Text(
          'Будут удалены $periodText сообщения.\nЭто действие нельзя отменить.',
          style: TextStyle(color: Colors.white.withOpacity(0.7)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              'Отмена',
              style: TextStyle(color: Colors.white.withOpacity(0.5)),
            ),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              await _clearMessages(mode);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: const Text('Удалить'),
          ),
        ],
      ),
    );
  }

  Future<void> _handleReaction(EmployeeChatMessage message, String reaction) async {
    HapticFeedback.selectionClick();
    final hasReaction = message.hasReactionFrom(widget.userPhone, reaction);

    if (hasReaction) {
      await EmployeeChatService.removeReaction(
        chatId: widget.chat.id,
        messageId: message.id,
        phone: widget.userPhone,
        reaction: reaction,
      );
    } else {
      await EmployeeChatService.addReaction(
        chatId: widget.chat.id,
        messageId: message.id,
        phone: widget.userPhone,
        reaction: reaction,
      );
    }
  }

  void _showForwardDialog(EmployeeChatMessage message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Функция пересылки будет доступна в следующем обновлении'),
        backgroundColor: _emerald,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

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

    setState(() {
      _isSearching = false;
      _searchController.clear();
      _searchResults = [];
    });

    if (_scrollController.hasClients) {
      final estimatedOffset = index * 80.0;
      _scrollController.animateTo(
        estimatedOffset.clamp(0, _scrollController.position.maxScrollExtent),
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
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
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
        _loadMessages();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Нет сообщений для удаления'),
            backgroundColor: Colors.orange,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _night,
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [_emerald, _emeraldDark, _night],
            stops: [0.0, 0.15, 0.4],
          ),
        ),
        child: SafeArea(
          bottom: false,
          child: Column(
            children: [
              // AppBar
              _isSearching ? _buildSearchHeader() : _buildAppBar(),
              // Результаты поиска
              if (_isSearching && _searchResults.isNotEmpty)
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.06),
                    border: Border(
                      bottom: BorderSide(color: Colors.white.withOpacity(0.08)),
                    ),
                  ),
                  constraints: const BoxConstraints(maxHeight: 200),
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: _searchResults.length,
                    itemBuilder: (context, index) {
                      final msg = _searchResults[index];
                      return ListTile(
                        dense: true,
                        leading: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: _emerald.withOpacity(0.3),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Icon(
                            Icons.message,
                            color: Colors.white.withOpacity(0.7),
                            size: 18,
                          ),
                        ),
                        title: Text(
                          msg.text,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: Colors.white.withOpacity(0.9)),
                        ),
                        subtitle: Text(
                          '${msg.senderName} • ${msg.formattedTime}',
                          style: TextStyle(fontSize: 11, color: Colors.white.withOpacity(0.4)),
                        ),
                        onTap: () => _scrollToMessage(msg.id),
                      );
                    },
                  ),
                ),
              if (_isSearching && _isSearchLoading)
                LinearProgressIndicator(
                  backgroundColor: Colors.white.withOpacity(0.05),
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white.withOpacity(0.4)),
                ),
              Expanded(
                child: _isLoading
                    ? const Center(
                        child: CircularProgressIndicator(color: Colors.white),
                      )
                    : _messages.isEmpty
                        ? _buildEmptyState()
                        : ListView.builder(
                            controller: _scrollController,
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            itemCount: _messages.length,
                            itemBuilder: (context, index) {
                              final message = _messages[index];
                              final isMe = message.senderPhone == widget.userPhone;

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
                                    showSenderName:
                                        widget.chat.type != EmployeeChatType.private && !isMe,
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
              if (_typingPhone != null) _buildTypingIndicator(),
              ChatInputField(
                controller: _messageController,
                isSending: _isSending,
                onSend: () {
                  ChatWebSocketService.instance.sendTypingStop(widget.chat.id);
                  _sendMessage();
                },
                onAttach: _showImageSourceDialog,
                onChanged: _onTextChanged,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAppBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 8, 4, 8),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.pop(context),
            icon: Icon(
              Icons.arrow_back_ios_new_rounded,
              color: Colors.white.withOpacity(0.8),
              size: 22,
            ),
          ),
          Expanded(
            child: GestureDetector(
              onTap: widget.chat.type == EmployeeChatType.group ? _openGroupInfo : null,
              child: Row(
                children: [
                  // Аватар для групп
                  if (widget.chat.type == EmployeeChatType.group) ...[
                    Hero(
                      tag: 'group_avatar_${widget.chat.id}',
                      child: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: widget.chat.imageUrl == null
                              ? Colors.purple.withOpacity(0.3)
                              : null,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white.withOpacity(0.15)),
                          image: widget.chat.imageUrl != null
                              ? DecorationImage(
                                  image: NetworkImage(widget.chat.imageUrl!),
                                  fit: BoxFit.cover,
                                )
                              : null,
                        ),
                        child: widget.chat.imageUrl == null
                            ? const Icon(Icons.group, size: 22, color: Colors.white)
                            : null,
                      ),
                    ),
                    const SizedBox(width: 12),
                  ],
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.chat.displayName,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 17,
                            fontWeight: FontWeight.w500,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (widget.chat.type == EmployeeChatType.shop)
                          Text(
                            widget.chat.shopAddress ?? '',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.white.withOpacity(0.5),
                            ),
                          ),
                        if (widget.chat.type == EmployeeChatType.group)
                          Text(
                            '${widget.chat.participantsCount} участников',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.white.withOpacity(0.5),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          IconButton(
            icon: Icon(Icons.search_rounded, color: Colors.white.withOpacity(0.7), size: 22),
            onPressed: () => setState(() => _isSearching = true),
          ),
          if (widget.chat.type == EmployeeChatType.group)
            IconButton(
              icon: Icon(Icons.info_outline_rounded, color: Colors.white.withOpacity(0.7), size: 22),
              onPressed: _openGroupInfo,
            ),
          if (widget.isAdmin)
            IconButton(
              icon: Icon(Icons.delete_sweep_rounded, color: Colors.white.withOpacity(0.7), size: 22),
              onPressed: _showClearMessagesDialog,
            ),
          PopupMenuButton<String>(
            icon: Icon(Icons.more_vert_rounded, color: Colors.white.withOpacity(0.7), size: 22),
            color: _night.withOpacity(0.98),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            onSelected: (value) {
              if (value == 'refresh') _loadMessages();
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'refresh',
                child: Row(
                  children: [
                    Icon(Icons.refresh, color: Colors.white.withOpacity(0.7)),
                    const SizedBox(width: 12),
                    Text('Обновить', style: TextStyle(color: Colors.white.withOpacity(0.9))),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSearchHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 8, 4, 8),
      child: Row(
        children: [
          IconButton(
            icon: Icon(Icons.arrow_back_rounded, color: Colors.white.withOpacity(0.8)),
            onPressed: () {
              setState(() {
                _isSearching = false;
                _searchController.clear();
                _searchResults = [];
              });
            },
          ),
          Expanded(
            child: Container(
              height: 42,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white.withOpacity(0.12)),
              ),
              child: TextField(
                controller: _searchController,
                autofocus: true,
                style: TextStyle(color: Colors.white.withOpacity(0.9), fontSize: 15),
                cursorColor: Colors.white,
                decoration: InputDecoration(
                  hintText: 'Поиск сообщений...',
                  hintStyle: TextStyle(color: Colors.white.withOpacity(0.3)),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                ),
                onChanged: _searchMessages,
              ),
            ),
          ),
          if (_searchController.text.isNotEmpty)
            IconButton(
              icon: Icon(Icons.close_rounded, color: Colors.white.withOpacity(0.7)),
              onPressed: () {
                _searchController.clear();
                setState(() => _searchResults = []);
              },
            ),
        ],
      ),
    );
  }

  void _openGroupInfo() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => GroupInfoPage(
          chat: widget.chat,
          currentUserPhone: widget.userPhone,
        ),
      ),
    );

    if (result == 'left' || result == 'deleted') {
      if (mounted) {
        Navigator.pop(context);
      }
    }
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.06),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: Colors.white.withOpacity(0.1)),
            ),
            child: Icon(
              Icons.chat_bubble_outline,
              size: 32,
              color: Colors.white.withOpacity(0.4),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'Нет сообщений',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w500,
              color: Colors.white.withOpacity(0.8),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Начните общение прямо сейчас!',
            style: TextStyle(
              fontSize: 13,
              color: Colors.white.withOpacity(0.4),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTypingIndicator() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      child: Row(
        children: [
          AnimatedBuilder(
            animation: _typingAnimationController,
            builder: (context, child) {
              return Row(
                children: List.generate(3, (index) {
                  final delay = index * 0.2;
                  final value = ((_typingAnimationController.value + delay) % 1.0);
                  final scale = 0.5 + (0.5 * (1 - (value - 0.5).abs() * 2));
                  return Container(
                    margin: const EdgeInsets.symmetric(horizontal: 2),
                    child: Transform.scale(
                      scale: scale,
                      child: Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.5),
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                  );
                }),
              );
            },
          ),
          const SizedBox(width: 8),
          Text(
            'печатает...',
            style: TextStyle(
              fontSize: 12,
              fontStyle: FontStyle.italic,
              color: Colors.white.withOpacity(0.4),
            ),
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
      padding: const EdgeInsets.symmetric(vertical: 20),
      child: Row(
        children: [
          Expanded(
            child: Container(
              height: 1,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Colors.transparent,
                    Colors.white.withOpacity(0.15),
                  ],
                ),
              ),
            ),
          ),
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.08),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white.withOpacity(0.1)),
            ),
            child: Text(
              dateText,
              style: TextStyle(
                color: Colors.white.withOpacity(0.5),
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Expanded(
            child: Container(
              height: 1,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Colors.white.withOpacity(0.15),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
