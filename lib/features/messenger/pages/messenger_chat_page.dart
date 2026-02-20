import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../../../core/theme/app_colors.dart';
import '../models/conversation_model.dart';
import '../models/message_model.dart';
import '../services/messenger_service.dart';
import '../services/messenger_ws_service.dart';
import '../widgets/message_bubble.dart';
import '../widgets/message_input_bar.dart';
import 'group_info_page.dart';

class MessengerChatPage extends StatefulWidget {
  final Conversation conversation;
  final String userPhone;
  final String userName;

  const MessengerChatPage({
    super.key,
    required this.conversation,
    required this.userPhone,
    required this.userName,
  });

  @override
  State<MessengerChatPage> createState() => _MessengerChatPageState();
}

class _MessengerChatPageState extends State<MessengerChatPage> {
  final List<MessengerMessage> _messages = [];
  final ScrollController _scrollController = ScrollController();
  bool _isLoading = true;
  bool _isLoadingMore = false;
  bool _hasMoreMessages = true;
  String? _typingPhone;
  String? _replyToId;
  String? _replyToText;
  final bool _isRecording = false;

  // Для воспроизведения голосовых
  String? _playingMessageId;

  StreamSubscription? _newMessageSub;
  StreamSubscription? _typingSub;
  StreamSubscription? _messageDeletedSub;
  StreamSubscription? _reactionAddedSub;
  StreamSubscription? _reactionRemovedSub;
  StreamSubscription? _readReceiptSub;

  Timer? _typingTimer;

  @override
  void initState() {
    super.initState();
    _loadMessages();
    _setupWebSocket();
    _markAsRead();

    // Пагинация — подгрузка при скролле вверх
    _scrollController.addListener(() {
      if (_scrollController.position.pixels <= 50 && !_isLoadingMore && _hasMoreMessages) {
        _loadMoreMessages();
      }
    });
  }

  @override
  void dispose() {
    _newMessageSub?.cancel();
    _typingSub?.cancel();
    _messageDeletedSub?.cancel();
    _reactionAddedSub?.cancel();
    _reactionRemovedSub?.cancel();
    _readReceiptSub?.cancel();
    _typingTimer?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  void _setupWebSocket() {
    final ws = MessengerWsService.instance;

    _newMessageSub = ws.onNewMessage.listen((event) {
      if (event.conversationId == widget.conversation.id && mounted) {
        setState(() {
          _messages.add(event.message);
        });
        _scrollToBottom();
        _markAsRead();
      }
    });

    _typingSub = ws.onTyping.listen((event) {
      if (event.conversationId == widget.conversation.id && event.phone != widget.userPhone) {
        if (mounted) {
          setState(() {
            _typingPhone = event.isTyping ? event.phone : null;
          });
        }
      }
    });

    _messageDeletedSub = ws.onMessageDeleted.listen((event) {
      if (event.conversationId == widget.conversation.id && mounted) {
        setState(() {
          final idx = _messages.indexWhere((m) => m.id == event.messageId);
          if (idx != -1) {
            _messages[idx] = MessengerMessage(
              id: _messages[idx].id,
              conversationId: _messages[idx].conversationId,
              senderPhone: _messages[idx].senderPhone,
              senderName: _messages[idx].senderName,
              type: _messages[idx].type,
              isDeleted: true,
              createdAt: _messages[idx].createdAt,
            );
          }
        });
      }
    });

    _reactionAddedSub = ws.onReactionAdded.listen((event) {
      if (event.conversationId == widget.conversation.id && mounted) {
        _loadMessages(silent: true);
      }
    });

    _reactionRemovedSub = ws.onReactionRemoved.listen((event) {
      if (event.conversationId == widget.conversation.id && mounted) {
        _loadMessages(silent: true);
      }
    });
  }

  Future<void> _loadMessages({bool silent = false}) async {
    if (!silent && mounted) setState(() => _isLoading = true);

    try {
      final messages = await MessengerService.getMessages(widget.conversation.id, limit: 50);
      if (mounted) {
        setState(() {
          _messages.clear();
          _messages.addAll(messages);
          _isLoading = false;
          _hasMoreMessages = messages.length >= 50;
        });
        if (!silent) {
          WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
        }
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _loadMoreMessages() async {
    if (_messages.isEmpty || _isLoadingMore) return;

    setState(() => _isLoadingMore = true);

    try {
      final oldest = _messages.first.createdAt.toIso8601String();
      final olderMessages = await MessengerService.getMessages(
        widget.conversation.id,
        limit: 50,
        before: oldest,
      );

      if (mounted) {
        setState(() {
          _messages.insertAll(0, olderMessages);
          _isLoadingMore = false;
          _hasMoreMessages = olderMessages.length >= 50;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoadingMore = false);
    }
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  Future<void> _markAsRead() async {
    await MessengerService.markAsRead(widget.conversation.id, widget.userPhone);
  }

  void _handleSendText(String text) async {
    final msg = await MessengerService.sendMessage(
      conversationId: widget.conversation.id,
      senderPhone: widget.userPhone,
      senderName: widget.userName,
      type: MessageType.text,
      content: text,
      replyToId: _replyToId,
    );

    if (msg != null && mounted) {
      setState(() {
        _messages.add(msg);
        _replyToId = null;
        _replyToText = null;
      });
      _scrollToBottom();
    }
  }

  void _handleTyping(String text) {
    final ws = MessengerWsService.instance;
    ws.sendTypingStart(widget.conversation.id);
    _typingTimer?.cancel();
    _typingTimer = Timer(const Duration(seconds: 3), () {
      ws.sendTypingStop(widget.conversation.id);
    });
  }

  void _handleAttachment() async {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera, color: AppColors.emerald),
              title: const Text('Камера'),
              onTap: () {
                Navigator.pop(ctx);
                _pickAndSendImage(ImageSource.camera);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library, color: AppColors.emerald),
              title: const Text('Галерея'),
              onTap: () {
                Navigator.pop(ctx);
                _pickAndSendImage(ImageSource.gallery);
              },
            ),
            ListTile(
              leading: const Icon(Icons.videocam, color: AppColors.emerald),
              title: const Text('Видео'),
              onTap: () {
                Navigator.pop(ctx);
                _pickAndSendVideo();
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickAndSendImage(ImageSource source) async {
    try {
      final picker = ImagePicker();
      final picked = await picker.pickImage(source: source, imageQuality: 75, maxWidth: 1280);
      if (picked == null) return;

      final file = File(picked.path);
      final url = await MessengerService.uploadMedia(file);
      if (url == null) return;

      final msg = await MessengerService.sendMessage(
        conversationId: widget.conversation.id,
        senderPhone: widget.userPhone,
        senderName: widget.userName,
        type: MessageType.image,
        mediaUrl: url,
      );

      if (msg != null && mounted) {
        setState(() => _messages.add(msg));
        _scrollToBottom();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка загрузки: $e')),
        );
      }
    }
  }

  Future<void> _pickAndSendVideo() async {
    try {
      final picker = ImagePicker();
      final picked = await picker.pickVideo(source: ImageSource.gallery, maxDuration: const Duration(minutes: 5));
      if (picked == null) return;

      final file = File(picked.path);
      final url = await MessengerService.uploadMedia(file);
      if (url == null) return;

      final msg = await MessengerService.sendMessage(
        conversationId: widget.conversation.id,
        senderPhone: widget.userPhone,
        senderName: widget.userName,
        type: MessageType.video,
        mediaUrl: url,
      );

      if (msg != null && mounted) {
        setState(() => _messages.add(msg));
        _scrollToBottom();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка загрузки: $e')),
        );
      }
    }
  }

  void _handleLongPress(MessengerMessage message) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.reply),
              title: const Text('Ответить'),
              onTap: () {
                Navigator.pop(ctx);
                if (mounted) {
                  setState(() {
                    _replyToId = message.id;
                    _replyToText = message.preview;
                  });
                }
              },
            ),
            // Reactions
            ListTile(
              leading: const Icon(Icons.emoji_emotions_outlined),
              title: const Text('Реакция'),
              onTap: () {
                Navigator.pop(ctx);
                _showReactionPicker(message);
              },
            ),
            // Delete (only own messages)
            if (message.senderPhone == widget.userPhone)
              ListTile(
                leading: const Icon(Icons.delete_outline, color: Colors.red),
                title: const Text('Удалить', style: TextStyle(color: Colors.red)),
                onTap: () {
                  Navigator.pop(ctx);
                  _deleteMessage(message);
                },
              ),
          ],
        ),
      ),
    );
  }

  void _showReactionPicker(MessengerMessage message) {
    final reactions = ['👍', '❤️', '😂', '😮', '😢', '🔥'];
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        content: Wrap(
          spacing: 12,
          children: reactions.map((emoji) => GestureDetector(
            onTap: () {
              Navigator.pop(ctx);
              MessengerService.addReaction(
                widget.conversation.id,
                message.id,
                phone: widget.userPhone,
                reaction: emoji,
              );
            },
            child: Text(emoji, style: const TextStyle(fontSize: 32)),
          )).toList(),
        ),
      ),
    );
  }

  Future<void> _deleteMessage(MessengerMessage message) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Удалить сообщение?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отмена')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Удалить', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await MessengerService.deleteMessage(widget.conversation.id, message.id, widget.userPhone);
      _loadMessages(silent: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isGroup = widget.conversation.type == ConversationType.group;
    final title = widget.conversation.displayName(widget.userPhone);

    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        backgroundColor: AppColors.emerald,
        foregroundColor: Colors.white,
        title: GestureDetector(
          onTap: isGroup ? () => _openGroupInfo() : null,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontSize: 16)),
              if (_typingPhone != null)
                const Text('печатает...', style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic))
              else if (isGroup)
                Text(
                  '${widget.conversation.participants.length} участников',
                  style: const TextStyle(fontSize: 12, color: Colors.white70),
                ),
            ],
          ),
        ),
        actions: [
          if (isGroup)
            IconButton(
              icon: const Icon(Icons.group),
              onPressed: _openGroupInfo,
            ),
        ],
      ),
      body: Column(
        children: [
          // Messages
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator(color: AppColors.emerald))
                : _messages.isEmpty
                    ? Center(
                        child: Text('Нет сообщений', style: TextStyle(color: Colors.grey[400], fontSize: 16)),
                      )
                    : ListView.builder(
                        controller: _scrollController,
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        itemCount: _messages.length + (_isLoadingMore ? 1 : 0),
                        itemBuilder: (context, index) {
                          if (_isLoadingMore && index == 0) {
                            return const Padding(
                              padding: EdgeInsets.all(8),
                              child: Center(child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.emerald)),
                            );
                          }

                          final msgIndex = _isLoadingMore ? index - 1 : index;
                          final message = _messages[msgIndex];
                          final isMine = message.senderPhone == widget.userPhone;

                          // Date separator
                          Widget? dateSeparator;
                          if (msgIndex == 0 || _messages[msgIndex].formattedDate != _messages[msgIndex - 1].formattedDate) {
                            dateSeparator = Center(
                              child: Container(
                                margin: const EdgeInsets.symmetric(vertical: 8),
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                                decoration: BoxDecoration(
                                  color: Colors.black12,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  message.formattedDate,
                                  style: const TextStyle(fontSize: 12, color: Colors.black54),
                                ),
                              ),
                            );
                          }

                          return Column(
                            children: [
                              if (dateSeparator != null) dateSeparator,
                              MessageBubble(
                                message: message,
                                isMine: isMine,
                                showSenderName: isGroup && !isMine,
                                onLongPress: () => _handleLongPress(message),
                                isPlayingVoice: _playingMessageId == message.id,
                              ),
                            ],
                          );
                        },
                      ),
          ),

          // Input bar
          MessageInputBar(
            onSendText: _handleSendText,
            onAttachmentTap: _handleAttachment,
            onTyping: _handleTyping,
            replyToText: _replyToText,
            onCancelReply: () {
              if (mounted) {
                setState(() {
                  _replyToId = null;
                  _replyToText = null;
                });
              }
            },
            isRecording: _isRecording,
          ),
        ],
      ),
    );
  }

  void _openGroupInfo() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => GroupInfoPage(
          conversation: widget.conversation,
          userPhone: widget.userPhone,
          userName: widget.userName,
        ),
      ),
    );
  }
}
