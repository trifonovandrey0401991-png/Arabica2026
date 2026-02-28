import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/constants/api_constants.dart';
import '../models/conversation_model.dart';
import '../models/message_model.dart';
import '../services/messenger_service.dart';
import '../services/messenger_ws_service.dart';
import '../services/voice_recorder_service.dart';
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
  bool _isLoading = false;
  bool _isFirstLoad = true;
  bool _isLoadingMore = false;
  bool _hasMoreMessages = true;
  String? _typingPhone;
  String? _replyToId;
  String? _replyToText;

  // Голосовая запись
  bool _isRecording = false;
  int _recordingSeconds = 0;
  Timer? _recordingTimer;

  // Воспроизведение голосовых
  String? _playingMessageId;
  final AudioPlayer _audioPlayer = AudioPlayer();

  // Emoji picker
  bool _showEmojiPicker = false;
  final TextEditingController _textController = TextEditingController();

  StreamSubscription? _newMessageSub;
  StreamSubscription? _typingSub;
  StreamSubscription? _onlineStatusSub;
  StreamSubscription? _messageDeletedSub;
  StreamSubscription? _reactionAddedSub;
  StreamSubscription? _reactionRemovedSub;
  StreamSubscription? _readReceiptSub;

  bool _isOtherOnline = false;

  Timer? _typingTimer;

  @override
  void initState() {
    super.initState();
    MessengerWsService.setActiveConversation(widget.conversation.id);
    _loadMessages();
    _setupWebSocket();
    _markAsRead();

    _scrollController.addListener(() {
      if (_scrollController.position.pixels <= 50 && !_isLoadingMore && _hasMoreMessages) {
        _loadMoreMessages();
      }
    });

    // Слушаем когда плеер заканчивает воспроизведение
    _audioPlayer.onPlayerComplete.listen((_) {
      if (mounted) {
        setState(() => _playingMessageId = null);
      }
    });
  }

  @override
  void dispose() {
    MessengerWsService.setActiveConversation(null);
    _newMessageSub?.cancel();
    _typingSub?.cancel();
    _onlineStatusSub?.cancel();
    _messageDeletedSub?.cancel();
    _reactionAddedSub?.cancel();
    _reactionRemovedSub?.cancel();
    _readReceiptSub?.cancel();
    _typingTimer?.cancel();
    _recordingTimer?.cancel();
    _scrollController.dispose();
    _audioPlayer.dispose();
    _textController.dispose();
    super.dispose();
  }

  void _setupWebSocket() {
    final ws = MessengerWsService.instance;

    // Ensure WS is connected even if chat opened directly (bypassing list page)
    if (!ws.isConnected) {
      ws.connect(widget.userPhone);
    }

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

    // Online status for private chats
    if (widget.conversation.type == ConversationType.private_) {
      final otherPhone = widget.conversation.otherPhone(widget.userPhone);
      if (otherPhone != null) {
        if (mounted) setState(() => _isOtherOnline = ws.isPhoneOnline(otherPhone));
        _onlineStatusSub = ws.onOnlineStatus.listen((event) {
          if (event.phone == otherPhone && mounted) {
            setState(() => _isOtherOnline = event.isOnline);
          }
        });
      }
    }

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
    if (!silent && _isFirstLoad && mounted) {
      setState(() => _isLoading = true);
    }

    try {
      final messages = await MessengerService.getMessages(widget.conversation.id, limit: 50);
      if (mounted) {
        setState(() {
          _messages.clear();
          _messages.addAll(messages);
          _isLoading = false;
          _isFirstLoad = false;
          _hasMoreMessages = messages.length >= 50;
        });
        if (!silent) {
          WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _isFirstLoad = false;
        });
      }
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

  // ========= Голосовая запись =========

  Future<void> _startVoiceRecording() async {
    final recorder = VoiceRecorderService.instance;
    final started = await recorder.startRecording();

    if (!started) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Нет доступа к микрофону')),
        );
      }
      return;
    }

    if (mounted) {
      setState(() {
        _isRecording = true;
        _recordingSeconds = 0;
      });
    }

    // Таймер для отображения длительности
    _recordingTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        setState(() => _recordingSeconds++);
      }
    });
  }

  Future<void> _stopAndSendVoice() async {
    _recordingTimer?.cancel();
    _recordingTimer = null;

    final recorder = VoiceRecorderService.instance;
    final result = await recorder.stopRecording();

    if (mounted) {
      setState(() {
        _isRecording = false;
        _recordingSeconds = 0;
      });
    }

    if (result == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Запись слишком короткая')),
        );
      }
      return;
    }

    // Загружаем файл на сервер
    final url = await MessengerService.uploadMedia(result.file);
    if (url == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Ошибка загрузки голосового')),
        );
      }
      return;
    }

    // Отправляем сообщение
    final msg = await MessengerService.sendMessage(
      conversationId: widget.conversation.id,
      senderPhone: widget.userPhone,
      senderName: widget.userName,
      type: MessageType.voice,
      mediaUrl: url,
      voiceDuration: result.durationSeconds,
    );

    if (msg != null && mounted) {
      setState(() => _messages.add(msg));
      _scrollToBottom();
    }

    // Удаляем временный файл
    try {
      await result.file.delete();
    } catch (_) {}
  }

  Future<void> _cancelVoiceRecording() async {
    _recordingTimer?.cancel();
    _recordingTimer = null;

    final recorder = VoiceRecorderService.instance;
    await recorder.cancelRecording();

    if (mounted) {
      setState(() {
        _isRecording = false;
        _recordingSeconds = 0;
      });
    }
  }

  // ========= Воспроизведение голосовых =========

  Future<void> _handlePlayVoice(MessengerMessage message) async {
    if (_playingMessageId == message.id) {
      // Остановить текущее воспроизведение
      await _audioPlayer.stop();
      if (mounted) setState(() => _playingMessageId = null);
      return;
    }

    if (message.mediaUrl == null) return;

    // Остановить предыдущее, запустить новое
    await _audioPlayer.stop();
    if (mounted) setState(() => _playingMessageId = message.id);

    try {
      await _audioPlayer.play(UrlSource(message.mediaUrl!));
    } catch (e) {
      if (mounted) {
        setState(() => _playingMessageId = null);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка воспроизведения: $e')),
        );
      }
    }
  }

  // ========= Вложения =========

  void _toggleEmojiPicker() {
    if (mounted) {
      setState(() => _showEmojiPicker = !_showEmojiPicker);
      if (_showEmojiPicker) {
        FocusScope.of(context).unfocus();
      }
    }
  }

  void _handleAttachment() async {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF0A2A2A),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(top: 12, bottom: 8),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.2),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.photo_camera, color: AppColors.turquoise),
              title: Text('Камера', style: TextStyle(color: Colors.white.withOpacity(0.9))),
              onTap: () {
                Navigator.pop(ctx);
                _pickAndSendImage(ImageSource.camera);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library, color: AppColors.turquoise),
              title: Text('Галерея', style: TextStyle(color: Colors.white.withOpacity(0.9))),
              onTap: () {
                Navigator.pop(ctx);
                _pickAndSendImage(ImageSource.gallery);
              },
            ),
            ListTile(
              leading: const Icon(Icons.videocam, color: AppColors.turquoise),
              title: Text('Видео', style: TextStyle(color: Colors.white.withOpacity(0.9))),
              onTap: () {
                Navigator.pop(ctx);
                _pickAndSendVideo();
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<void> _pickAndSendImage(ImageSource source) async {
    try {
      final picked = await ImagePicker().pickImage(source: source, imageQuality: 75, maxWidth: 1280);
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
      final picked = await ImagePicker().pickVideo(source: ImageSource.gallery, maxDuration: const Duration(minutes: 5));
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

  // ========= Действия с сообщениями =========

  void _handleLongPress(MessengerMessage message) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF0A2A2A),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(top: 12, bottom: 8),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.2),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            ListTile(
              leading: Icon(Icons.reply, color: Colors.white.withOpacity(0.7)),
              title: Text('Ответить', style: TextStyle(color: Colors.white.withOpacity(0.9))),
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
            ListTile(
              leading: Icon(Icons.emoji_emotions_outlined, color: Colors.white.withOpacity(0.7)),
              title: Text('Реакция', style: TextStyle(color: Colors.white.withOpacity(0.9))),
              onTap: () {
                Navigator.pop(ctx);
                _showReactionPicker(message);
              },
            ),
            if (message.senderPhone == widget.userPhone)
              ListTile(
                leading: const Icon(Icons.delete_outline, color: AppColors.error),
                title: const Text('Удалить', style: TextStyle(color: AppColors.error)),
                onTap: () {
                  Navigator.pop(ctx);
                  _deleteMessage(message);
                },
              ),
            const SizedBox(height: 8),
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
        backgroundColor: const Color(0xFF0A2A2A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
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
        backgroundColor: const Color(0xFF0A2A2A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Удалить сообщение?', style: TextStyle(color: Colors.white.withOpacity(0.9))),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Отмена', style: TextStyle(color: Colors.white.withOpacity(0.5))),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Удалить', style: TextStyle(color: AppColors.error)),
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
      backgroundColor: AppColors.night,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: Colors.white,
        titleSpacing: 0,
        title: GestureDetector(
          onTap: isGroup ? () => _openGroupInfo() : null,
          child: Row(
            children: [
              _buildAppBarAvatar(title, isGroup),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(fontSize: 16, color: Colors.white.withOpacity(0.95)),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (_typingPhone != null)
                      Text(
                        'печатает...',
                        style: TextStyle(
                          fontSize: 12,
                          fontStyle: FontStyle.italic,
                          color: AppColors.turquoise.withOpacity(0.8),
                        ),
                      )
                    else if (isGroup)
                      Text(
                        '${widget.conversation.participants.length} участников',
                        style: TextStyle(fontSize: 12, color: Colors.white.withOpacity(0.4)),
                      )
                    else if (_isOtherOnline)
                      Text(
                        'онлайн',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppColors.turquoise.withOpacity(0.8),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          if (isGroup)
            IconButton(
              icon: Icon(Icons.group, color: Colors.white.withOpacity(0.6)),
              onPressed: _openGroupInfo,
            ),
        ],
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                AppColors.emerald.withOpacity(0.3),
                Colors.transparent,
              ],
            ),
          ),
        ),
      ),
      body: Column(
        children: [
          // Messages
          Expanded(
            child: _isLoading && _messages.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(color: AppColors.turquoise, strokeWidth: 2),
                        ),
                        const SizedBox(height: 8),
                        Text('Загрузка...', style: TextStyle(color: Colors.white.withOpacity(0.3), fontSize: 13)),
                      ],
                    ),
                  )
                : _messages.isEmpty
                    ? Center(
                        child: Text(
                          'Нет сообщений\nНапишите первое!',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.white.withOpacity(0.3), fontSize: 16),
                        ),
                      )
                    : ListView.builder(
                        controller: _scrollController,
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        itemCount: _messages.length + (_isLoadingMore ? 1 : 0),
                        itemBuilder: (context, index) {
                          if (_isLoadingMore && index == 0) {
                            return const Padding(
                              padding: EdgeInsets.all(8),
                              child: Center(
                                child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.turquoise),
                              ),
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
                                  color: Colors.white.withOpacity(0.08),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  message.formattedDate,
                                  style: TextStyle(fontSize: 12, color: Colors.white.withOpacity(0.5)),
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
                                onPlayVoice: message.type == MessageType.voice
                                    ? () => _handlePlayVoice(message)
                                    : null,
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
            onEmojiTap: _toggleEmojiPicker,
            onTyping: _handleTyping,
            onVoiceStart: _startVoiceRecording,
            onVoiceSend: _stopAndSendVoice,
            onVoiceCancel: _cancelVoiceRecording,
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
            recordingSeconds: _recordingSeconds,
            textController: _textController,
          ),

          // Emoji picker
          if (_showEmojiPicker)
            SizedBox(
              height: 280,
              child: EmojiPicker(
                textEditingController: _textController,
                onEmojiSelected: (category, emoji) {
                  // Emoji уже вставлен в _textController через textEditingController
                },
                config: Config(
                  columns: 8,
                  emojiSizeMax: 28,
                  bgColor: AppColors.night,
                  iconColorSelected: AppColors.turquoise,
                  indicatorColor: AppColors.turquoise,
                  iconColor: Colors.white.withOpacity(0.3),
                  backspaceColor: Colors.white.withOpacity(0.5),
                  skinToneDialogBgColor: const Color(0xFF0A2A2A),
                  skinToneIndicatorColor: AppColors.turquoise,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildAppBarAvatar(String displayName, bool isGroup) {
    final letter = displayName.isNotEmpty ? displayName[0].toUpperCase() : '?';
    final hasAvatar = isGroup && widget.conversation.avatarUrl != null && widget.conversation.avatarUrl!.isNotEmpty;

    return Container(
      width: 38,
      height: 38,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: !hasAvatar
            ? LinearGradient(
                colors: isGroup
                    ? [AppColors.turquoise, AppColors.emerald]
                    : [AppColors.emeraldLight, AppColors.emerald],
              )
            : null,
        border: Border.all(color: Colors.white.withOpacity(0.15)),
      ),
      clipBehavior: Clip.antiAlias,
      child: hasAvatar
          ? CachedNetworkImage(
              imageUrl: widget.conversation.avatarUrl!.startsWith('http')
                  ? widget.conversation.avatarUrl!
                  : '${ApiConstants.serverUrl}${widget.conversation.avatarUrl}',
              fit: BoxFit.cover,
              width: 38,
              height: 38,
              errorWidget: (_, __, ___) => Center(
                child: Text(letter, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
              ),
            )
          : Center(
              child: Text(letter, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
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
