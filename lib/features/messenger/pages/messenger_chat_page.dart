import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart' show compute;
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/logger.dart';
import '../../../core/constants/api_constants.dart';
import '../../../core/services/photo_upload_service.dart' show compressImageIsolate;
import '../models/conversation_model.dart';
import '../models/message_model.dart';
import '../models/participant_model.dart';
import '../services/messenger_service.dart';
import '../services/messenger_ws_service.dart';
import '../services/voice_recorder_service.dart';
import '../services/call_service.dart';
import '../services/offline_message_queue.dart';
import '../widgets/message_bubble.dart';
import '../widgets/album_bubble.dart';
import '../widgets/message_input_bar.dart';
import '../widgets/message_context_menu.dart';
import '../widgets/pinned_message_bar.dart';
import '../widgets/combined_media_picker.dart';
import '../widgets/template_picker.dart';
import 'call_page.dart';
import 'group_info_page.dart';
import 'messenger_shell_page.dart';
import 'photo_editor_page.dart';
import 'video_note_recorder_page.dart';
import 'create_poll_page.dart';
import 'conversation_picker_page.dart';
import '../widgets/contact_profile_sheet.dart';
import 'media_gallery_page.dart';
import 'image_viewer_page.dart';
import 'video_player_page.dart';
import '../models/poll_model.dart';
import '../widgets/poll_bubble.dart';

class MessengerChatPage extends StatefulWidget {
  final Conversation conversation;
  final String userPhone;
  final String userName;
  final bool isClient;
  final Map<String, String> phoneBookNames;

  const MessengerChatPage({
    super.key,
    required this.conversation,
    required this.userPhone,
    required this.userName,
    this.isClient = false,
    this.phoneBookNames = const {},
  });

  @override
  State<MessengerChatPage> createState() => _MessengerChatPageState();
}

class _MessengerChatPageState extends State<MessengerChatPage> with WidgetsBindingObserver {
  // In-memory cache shared across all chat instances (lives while app is open)
  static final Map<String, List<MessengerMessage>> _messagesCache = {};
  static const int _messagesCacheLimit = 20; // max conversations cached

  // Draft text per conversation (persists while app is open)
  static final Map<String, String> _drafts = {};

  final List<MessengerMessage> _messages = [];
  // O(1) lookup for reply-to messages (rebuilt when messages change)
  Map<String, MessengerMessage> _messagesById = {};
  final ScrollController _scrollController = ScrollController();
  bool _isLoading = false;
  bool _isFirstLoad = true;
  bool _isLoadingMore = false;
  bool _hasMoreMessages = true;
  String? _loadError; // error message shown to user with retry button
  String? _typingPhone;
  String? _replyToId;
  String? _replyToText;

  // Edit mode
  String? _editingMessageId;

  // Pinned messages (multiple pins support)
  List<MessengerMessage> _pinnedMessages = [];
  int _currentPinnedIndex = 0;
  bool _isBlocked = false; // true if WE blocked the other user

  /// Is current user admin of the channel (can post)?
  bool get _isChannelAdmin {
    if (widget.conversation.type != ConversationType.channel) return false;
    final me = widget.conversation.participants
        .where((p) => p.phone == widget.userPhone)
        .toList();
    return me.isNotEmpty && (me.first.role == 'admin' || me.first.role == 'creator');
  }

  // Голосовая запись
  bool _isRecording = false;
  int _recordingSeconds = 0;
  Timer? _recordingTimer;

  // Воспроизведение голосовых
  String? _playingMessageId;
  bool _voicePaused = false;
  final AudioPlayer _audioPlayer = AudioPlayer();
  double _voiceProgress = 0.0; // 0.0 – 1.0
  int _voicePositionSec = 0;
  int _voiceDurationMs = 0;
  StreamSubscription? _positionSub;
  StreamSubscription? _durationSub;

  // Emoji / Sticker / GIF picker
  bool _showMediaPicker = false;
  final TextEditingController _textController = TextEditingController();

  StreamSubscription? _newMessageSub;
  StreamSubscription? _typingSub;
  StreamSubscription? _onlineStatusSub;
  StreamSubscription? _messageDeletedSub;
  StreamSubscription? _reactionAddedSub;
  StreamSubscription? _reactionRemovedSub;
  StreamSubscription? _readReceiptSub;
  StreamSubscription? _messageEditedSub;
  StreamSubscription? _messageDeliveredSub;
  StreamSubscription? _connectionStatusSub;
  StreamSubscription? _audioCompleteSub;
  StreamSubscription? _queueSentSub;
  StreamSubscription? _queueFailedSub;

  bool _isOtherOnline = false;

  // Search mode
  bool _isSearchMode = false;
  final TextEditingController _searchController = TextEditingController();
  List<MessengerMessage> _searchResults = [];
  int _currentSearchIndex = -1;
  bool _isSearching = false;
  String? _highlightMessageId;

  // Keys for scroll-to-message (GlobalKey per message ID)
  final Map<String, GlobalKey> _messageKeys = {};

  // Mute
  bool _isMuted = false;

  // Read receipts: phone → last_read_at for each OTHER participant
  final Map<String, DateTime> _participantLastRead = {};

  Timer? _typingTimer;
  Timer? _markAsReadTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    MessengerWsService.setActiveConversation(widget.conversation.id);
    // Init read status from participants (populated when conversation list includes last_read_at)
    for (final p in widget.conversation.participants) {
      if (p.phone != widget.userPhone && p.lastReadAt != null) {
        _participantLastRead[p.phone] = p.lastReadAt!;
      }
    }
    // Load from cache immediately (no loading spinner if cached)
    final cached = _messagesCache[widget.conversation.id];
    if (cached != null && cached.isNotEmpty) {
      _messages.addAll(cached);
      _rebuildIndex();
      _isFirstLoad = false;
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
    }
    // Restore draft if any
    final draft = _drafts[widget.conversation.id];
    if (draft != null && draft.isNotEmpty) {
      _textController.text = draft;
      _textController.selection = TextSelection.collapsed(offset: draft.length);
    }

    _loadMessages();
    _setupWebSocket();
    _markAsRead();
    _refreshParticipantReadTimes();
    _checkBlockStatus();
    _checkMuteStatus();
    _setupOfflineQueue();

    _scrollController.addListener(() {
      if (_scrollController.hasClients &&
          _scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 50 &&
          !_isLoadingMore && _hasMoreMessages) {
        _loadMoreMessages();
      }
    });

    // Слушаем прогресс и завершение воспроизведения
    _durationSub = _audioPlayer.onDurationChanged.listen((dur) {
      _voiceDurationMs = dur.inMilliseconds;
    });
    _positionSub = _audioPlayer.onPositionChanged.listen((pos) {
      if (!mounted || _playingMessageId == null) return;
      if (_voiceDurationMs > 0) {
        setState(() {
          _voiceProgress = (pos.inMilliseconds / _voiceDurationMs).clamp(0.0, 1.0);
          _voicePositionSec = pos.inSeconds;
        });
      }
    });
    _audioCompleteSub = _audioPlayer.onPlayerComplete.listen((_) {
      if (mounted) {
        setState(() {
          _playingMessageId = null;
          _voicePaused = false;
          _voiceProgress = 0.0;
          _voicePositionSec = 0;
        });
      }
    });
  }

  @override
  void dispose() {
    // Save draft text before disposing
    final text = _textController.text.trim();
    if (text.isNotEmpty) {
      _drafts[widget.conversation.id] = text;
    } else {
      _drafts.remove(widget.conversation.id);
    }

    WidgetsBinding.instance.removeObserver(this);
    MessengerWsService.setActiveConversation(null);
    _searchController.dispose();
    _newMessageSub?.cancel();
    _typingSub?.cancel();
    _onlineStatusSub?.cancel();
    _messageDeletedSub?.cancel();
    _reactionAddedSub?.cancel();
    _reactionRemovedSub?.cancel();
    _readReceiptSub?.cancel();
    _messageEditedSub?.cancel();
    _messageDeliveredSub?.cancel();
    _connectionStatusSub?.cancel();
    _audioCompleteSub?.cancel();
    _queueSentSub?.cancel();
    _queueFailedSub?.cancel();
    _positionSub?.cancel();
    _durationSub?.cancel();
    _typingTimer?.cancel();
    _recordingTimer?.cancel();
    _markAsReadTimer?.cancel();
    _scrollController.dispose();
    _audioPlayer.dispose();
    _textController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      MessengerWsService.instance.reconnectIfNeeded();
      // Load messages that may have been missed while app was in background
      _loadMessages(silent: true);
      _markAsRead();
    }
  }

  void _setupOfflineQueue() {
    final queue = OfflineMessageQueue.instance;
    queue.init();
    _queueSentSub = queue.onSent.listen((event) {
      if (!mounted) return;
      final idx = _messages.indexWhere((m) => m.id == event.tempId);
      if (idx != -1) {
        setState(() {
          _messages[idx] = event.message;
          _messagesById.remove(event.tempId);
          _messagesById[event.message.id] = event.message;
        });
        _messagesCache[widget.conversation.id] = List.of(_messages);
      }
    });
    _queueFailedSub = queue.onFailed.listen((tempId) {
      if (!mounted) return;
      final idx = _messages.indexWhere((m) => m.id == tempId);
      if (idx != -1) {
        setState(() {
          _messages[idx] = _messages[idx].copyWith(isFailed: true, isPending: false);
          _messagesById[tempId] = _messages[idx];
        });
      }
    });
  }

  void _setupWebSocket() {
    final ws = MessengerWsService.instance;

    // Ensure WS is connected even if chat opened directly (bypassing list page)
    if (!ws.isConnected) {
      ws.connect(widget.userPhone);
    }

    _newMessageSub = ws.onNewMessage.listen((event) {
      if (event.conversationId == widget.conversation.id && mounted) {
        // Deduplicate: O(1) lookup via index map
        if (_messagesById.containsKey(event.message.id)) return;

        // Dedup WS vs pending: if this is my own message, replace pending instead of adding
        if (event.message.senderPhone == widget.userPhone) {
          final pendingIdx = _messages.lastIndexWhere((m) => m.isPending && m.senderPhone == widget.userPhone);
          if (pendingIdx != -1) {
            setState(() {
              final pendingId = _messages[pendingIdx].id;
              _messages[pendingIdx] = event.message;
              _messagesById.remove(pendingId);
              _messagesById[event.message.id] = event.message;
            });
            _messagesCache[widget.conversation.id] = List.of(_messages);
            return;
          }
        }

        setState(() {
          _messages.add(event.message);
          _messagesById[event.message.id] = event.message;
        });
        // Update cache with new message
        _messagesCache[widget.conversation.id] = List.of(_messages);
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
        // Remove pinned message if it was deleted
        _pinnedMessages.removeWhere((m) => m.id == event.messageId);
        if (_currentPinnedIndex >= _pinnedMessages.length) {
          _currentPinnedIndex = _pinnedMessages.isEmpty ? 0 : _pinnedMessages.length - 1;
        }
        _updateMessage(event.messageId, (msg) => MessengerMessage(
          id: msg.id,
          conversationId: msg.conversationId,
          senderPhone: msg.senderPhone,
          senderName: msg.senderName,
          type: msg.type,
          isDeleted: true,
          createdAt: msg.createdAt,
        ));
      }
    });

    _reactionAddedSub = ws.onReactionAdded.listen((event) {
      if (event.conversationId == widget.conversation.id && mounted) {
        _updateMessage(event.messageId, (msg) {
          final reactions = Map<String, List<String>>.from(
            msg.reactions.map((k, v) => MapEntry(k, List<String>.from(v))),
          );
          if (!reactions.containsKey(event.reaction)) reactions[event.reaction] = [];
          if (!reactions[event.reaction]!.contains(event.phone)) {
            reactions[event.reaction]!.add(event.phone);
          }
          return msg.copyWith(reactions: reactions);
        });
      }
    });

    _reactionRemovedSub = ws.onReactionRemoved.listen((event) {
      if (event.conversationId == widget.conversation.id && mounted) {
        _updateMessage(event.messageId, (msg) {
          final reactions = Map<String, List<String>>.from(
            msg.reactions.map((k, v) => MapEntry(k, List<String>.from(v))),
          );
          if (reactions.containsKey(event.reaction)) {
            reactions[event.reaction]!.remove(event.phone);
            if (reactions[event.reaction]!.isEmpty) reactions.remove(event.reaction);
          }
          return msg.copyWith(reactions: reactions);
        });
      }
    });

    // Track when other participants read messages
    _readReceiptSub = ws.onReadReceipt.listen((event) {
      if (event.conversationId == widget.conversation.id &&
          event.phone != widget.userPhone &&
          mounted) {
        final ts = DateTime.tryParse(event.readAt)?.toLocal();
        if (ts != null) {
          setState(() => _participantLastRead[event.phone] = ts);
        }
      }
    });

    _messageEditedSub = ws.onMessageEdited.listen((event) {
      if (event.conversationId == widget.conversation.id && mounted) {
        _updateMessage(event.messageId, (msg) => msg.copyWith(
          content: event.newContent,
          editedAt: DateTime.tryParse(event.editedAt)?.toLocal(),
        ));
      }
    });

    _messageDeliveredSub = ws.onMessageDelivered.listen((event) {
      if (event.conversationId == widget.conversation.id && mounted) {
        _updateMessage(event.messageId, (msg) => msg.copyWith(
          deliveredTo: event.deliveredTo,
        ));
      }
    });

    // When WS reconnects after disconnection — load missed messages
    _connectionStatusSub = ws.onConnectionStatus.listen((isConnected) {
      if (isConnected && mounted) {
        _loadMessages(silent: true);
        _markAsRead();
      }
    });
  }

  Future<void> _loadMessages({bool silent = false}) async {
    if (!silent && _isFirstLoad && mounted) {
      setState(() => _isLoading = true);
    }

    try {
      // Параллельная загрузка сообщений и закреплённых (вместо последовательной)
      final results = await Future.wait([
        MessengerService.getMessages(widget.conversation.id, limit: 50),
        MessengerService.getPinnedMessages(widget.conversation.id),
      ]);
      final messages = results[0] as List<MessengerMessage>;
      final pinned = results[1] as List<MessengerMessage>;
      if (mounted) {
        setState(() {
          _loadError = null;
          if (silent && _messages.isNotEmpty) {
            // Merge: keep existing WS messages that server hasn't returned yet
            final serverIds = <String>{for (final m in messages) m.id};
            // Messages from WS that arrived after the server snapshot
            final wsOnly = _messages.where((m) => !serverIds.contains(m.id)).toList();
            _messages.clear();
            _messageKeys.clear();
            _messages.addAll(messages);
            // Append WS-only messages (newer than server batch) at the end
            if (messages.isNotEmpty) {
              for (final m in wsOnly) {
                if (m.createdAt.isAfter(messages.last.createdAt)) {
                  _messages.add(m);
                }
              }
            } else {
              _messages.addAll(wsOnly);
            }
          } else {
            _messages.clear();
            _messageKeys.clear();
            _messages.addAll(messages);
          }
          _isLoading = false;
          _isFirstLoad = false;
          _hasMoreMessages = messages.length >= 50;
          _pinnedMessages = pinned;
          _currentPinnedIndex = 0;
        });
        // Update cache — limit to avoid unbounded memory growth
        if (_messagesCache.length >= _messagesCacheLimit && !_messagesCache.containsKey(widget.conversation.id)) {
          _messagesCache.remove(_messagesCache.keys.first);
        }
        _messagesCache[widget.conversation.id] = List.of(_messages);
        _rebuildIndex();
        _batchLoadPolls(_messages);
        if (!silent) {
          _scrollToBottom();
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _isFirstLoad = false;
          // Only show error if we have no cached messages to display
          if (_messages.isEmpty) {
            _loadError = 'Не удалось загрузить сообщения';
          }
        });
      }
    }
  }

  Future<void> _loadMoreMessages() async {
    if (_messages.isEmpty || _isLoadingMore) return;

    if (!mounted) return;
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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          0.0,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _markAsRead() {
    _markAsReadTimer?.cancel();
    _markAsReadTimer = Timer(const Duration(milliseconds: 300), () {
      MessengerService.markAsRead(widget.conversation.id, widget.userPhone);
    });
  }

  /// Rebuild id→message index for O(1) reply lookups
  void _rebuildIndex() {
    _messagesById = {for (final m in _messages) m.id: m};
  }

  /// Update a single message in-place by ID (avoids O(n) indexWhere)
  void _updateMessage(String messageId, MessengerMessage Function(MessengerMessage old) transform) {
    final old = _messagesById[messageId];
    if (old == null) return;
    final idx = _messages.indexOf(old);
    if (idx == -1) return;
    final updated = transform(old);
    _messages[idx] = updated;
    _messagesById[messageId] = updated;
    if (mounted) setState(() {});
  }

  /// Fetch fresh conversation data to get accurate last_read_at for all participants.
  /// The conversations LIST endpoint may not include last_read_at, but the single
  /// conversation GET endpoint always does.
  Future<void> _refreshParticipantReadTimes() async {
    try {
      final conv = await MessengerService.getConversation(widget.conversation.id);
      if (conv == null || !mounted) return;
      bool changed = false;
      for (final p in conv.participants) {
        if (p.phone != widget.userPhone && p.lastReadAt != null) {
          final existing = _participantLastRead[p.phone];
          if (existing == null || p.lastReadAt!.isAfter(existing)) {
            _participantLastRead[p.phone] = p.lastReadAt!;
            changed = true;
          }
        }
      }
      if (changed && mounted) setState(() {});
    } catch (e) {
      Logger.error('messenger_chat: Failed to refresh read times', e);
    }
  }

  /// Number of OTHER participants whose last_read_at >= message.createdAt
  int _readersCount(MessengerMessage message) {
    return _participantLastRead.values
        .where((readAt) => !readAt.isBefore(message.createdAt))
        .length;
  }

  /// Total number of other participants (not counting sender)
  int get _otherParticipantCount {
    return widget.conversation.participants
        .where((p) => p.phone != widget.userPhone)
        .length
        .clamp(1, 999);
  }

  /// Participants (name + readAt) who have read up to a given message
  List<Map<String, dynamic>> _readersOf(MessengerMessage message) {
    return widget.conversation.participants
        .where((p) =>
            p.phone != widget.userPhone &&
            _participantLastRead[p.phone] != null &&
            !_participantLastRead[p.phone]!.isBefore(message.createdAt))
        .map((p) => {
              'name': p.name ?? p.phone,
              'readAt': _participantLastRead[p.phone]!,
            })
        .toList();
  }

  void _handleSendText(String text) async {
    // If editing — submit edit instead of sending new message
    if (_editingMessageId != null) {
      _submitEdit();
      return;
    }

    final savedReplyToId = _replyToId;

    // Optimistic: show message immediately with temporary ID
    final tempId = 'pending_${DateTime.now().millisecondsSinceEpoch}';
    final optimistic = MessengerMessage(
      id: tempId,
      conversationId: widget.conversation.id,
      senderPhone: widget.userPhone,
      senderName: widget.userName,
      type: MessageType.text,
      content: text,
      replyToId: savedReplyToId,
      createdAt: DateTime.now(),
      isPending: true,
    );

    setState(() {
      _messages.add(optimistic);
      _messagesById[tempId] = optimistic;
      _replyToId = null;
      _replyToText = null;
    });
    _scrollToBottom();

    final msg = await MessengerService.sendMessage(
      conversationId: widget.conversation.id,
      senderPhone: widget.userPhone,
      senderName: widget.userName,
      type: MessageType.text,
      content: text,
      replyToId: savedReplyToId,
    );

    if (!mounted) return;

    if (msg != null) {
      // Replace optimistic message with real one from server
      final idx = _messages.indexWhere((m) => m.id == tempId);
      if (idx != -1) {
        setState(() {
          _messages[idx] = msg;
          _messagesById.remove(tempId);
          _messagesById[msg.id] = msg;
        });
      }
      _messagesCache[widget.conversation.id] = List.of(_messages);
    } else {
      // Failed — add to offline queue for auto-retry
      OfflineMessageQueue.instance.enqueue(QueuedMessage(
        conversationId: widget.conversation.id,
        senderPhone: widget.userPhone,
        senderName: widget.userName,
        type: MessageType.text,
        content: text,
        replyToId: savedReplyToId,
        tempId: tempId,
      ));
      final idx = _messages.indexWhere((m) => m.id == tempId);
      if (idx != -1) {
        setState(() {
          _messages[idx] = optimistic.copyWith(isFailed: true, isPending: false);
          _messagesById[tempId] = _messages[idx];
        });
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Нет связи — сообщение отправится автоматически'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  /// Retry sending a failed message
  Future<void> _retryMessage(MessengerMessage failedMsg) async {
    // Mark as pending again
    final idx = _messages.indexWhere((m) => m.id == failedMsg.id);
    if (idx == -1) return;

    final pendingMsg = failedMsg.copyWith(isPending: true, isFailed: false);
    setState(() {
      _messages[idx] = pendingMsg;
      _messagesById[failedMsg.id] = pendingMsg;
    });

    final msg = await MessengerService.sendMessage(
      conversationId: widget.conversation.id,
      senderPhone: widget.userPhone,
      senderName: widget.userName,
      type: failedMsg.type,
      content: failedMsg.content,
      replyToId: failedMsg.replyToId,
      mediaUrl: failedMsg.mediaUrl,
    );

    if (!mounted) return;

    final retryIdx = _messages.indexWhere((m) => m.id == failedMsg.id);
    if (retryIdx == -1) return;

    if (msg != null) {
      setState(() {
        _messages[retryIdx] = msg;
        _messagesById.remove(failedMsg.id);
        _messagesById[msg.id] = msg;
      });
      _messagesCache[widget.conversation.id] = List.of(_messages);
    } else {
      setState(() {
        _messages[retryIdx] = failedMsg.copyWith(isFailed: true, isPending: false);
        _messagesById[failedMsg.id] = _messages[retryIdx];
      });
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

    // Wait for audio buffer to fully flush to disk before uploading
    await Future.delayed(const Duration(milliseconds: 300));

    // Upload with retry (3 attempts, 1 sec between)
    String? url;
    for (int attempt = 1; attempt <= 3; attempt++) {
      url = await MessengerService.uploadMedia(result.file);
      if (url != null) break;
      if (attempt < 3) await Future.delayed(const Duration(seconds: 1));
    }

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
      setState(() {
        _messages.add(msg);
        _messagesById[msg.id] = msg;
      });
      _messagesCache[widget.conversation.id] = List.of(_messages);
      _scrollToBottom();
    }

    // Удаляем временный файл
    try {
      await result.file.delete();
    } catch (e) {
      Logger.info('messenger_chat: Failed to delete temp voice file: $e');
    }
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

  // ========= Видео-кружки =========

  Future<void> _handleVideoNote() async {
    final result = await Navigator.of(context).push<Map<String, dynamic>?>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => const VideoNoteRecorderPage(),
      ),
    );

    if (result == null || !mounted) return;
    final File? file = result['file'] as File?;
    if (file == null) return;
    final int durationSecs = (result['duration'] as int?) ?? 0;

    // Upload
    String? url;
    for (int attempt = 1; attempt <= 3; attempt++) {
      url = await MessengerService.uploadMedia(file);
      if (url != null) break;
      if (attempt < 3) await Future.delayed(const Duration(seconds: 1));
    }

    if (url == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Ошибка загрузки видео-кружка')),
        );
      }
      return;
    }

    final msg = await MessengerService.sendMessage(
      conversationId: widget.conversation.id,
      senderPhone: widget.userPhone,
      senderName: widget.userName,
      type: MessageType.videoNote,
      mediaUrl: url,
      voiceDuration: durationSecs,
    );

    if (msg != null && mounted) {
      setState(() {
        _messages.add(msg);
        _messagesById[msg.id] = msg;
      });
      _messagesCache[widget.conversation.id] = List.of(_messages);
      _scrollToBottom();
    }

    // Clean up temp file
    try {
      await file.delete();
    } catch (e) {
      Logger.info('messenger_chat: Failed to delete temp video file: $e');
    }
  }

  // ========= Воспроизведение голосовых =========

  Future<void> _handlePlayVoice(MessengerMessage message) async {
    if (_playingMessageId == message.id) {
      if (_voicePaused) {
        // Продолжить с того же места
        await _audioPlayer.resume();
        if (mounted) setState(() => _voicePaused = false);
      } else {
        // Поставить на паузу (не сбрасывать прогресс)
        await _audioPlayer.pause();
        if (mounted) setState(() => _voicePaused = true);
      }
      return;
    }

    if (message.mediaUrl == null) return;

    // Остановить предыдущее, запустить новое
    await _audioPlayer.stop();
    if (mounted) setState(() {
      _playingMessageId = message.id;
      _voicePaused = false;
      _voiceProgress = 0.0;
      _voicePositionSec = 0;
      _voiceDurationMs = 0;
    });

    try {
      final voiceUrl = message.mediaUrl!.startsWith('http') ? message.mediaUrl! : '${ApiConstants.serverUrl}${message.mediaUrl!}';
      await _audioPlayer.play(UrlSource(voiceUrl));
    } catch (e) {
      if (mounted) {
        setState(() {
          _playingMessageId = null;
          _voicePaused = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка воспроизведения: $e')),
        );
      }
    }
  }

  Future<void> _handleSeekVoice(double progress) async {
    if (_playingMessageId == null || _voiceDurationMs <= 0) return;
    final posMs = (progress.clamp(0.0, 1.0) * _voiceDurationMs).round();
    await _audioPlayer.seek(Duration(milliseconds: posMs));
    if (mounted) {
      setState(() {
        _voiceProgress = progress.clamp(0.0, 1.0);
        _voicePositionSec = posMs ~/ 1000;
      });
    }
  }

  // ========= Вложения =========

  void _showTemplatePicker() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => TemplatePicker(
        onSelect: (text) {
          _textController.text = text;
          _textController.selection = TextSelection.collapsed(offset: text.length);
        },
      ),
    );
  }

  void _toggleMediaPicker() {
    if (mounted) {
      setState(() {
        _showMediaPicker = !_showMediaPicker;
      });
      if (_showMediaPicker) {
        FocusScope.of(context).unfocus();
      }
    }
  }

  Future<void> _sendSticker(String stickerUrl) async {
    if (mounted) {
      setState(() => _showMediaPicker = false);
    }
    final msg = await MessengerService.sendMessage(
      conversationId: widget.conversation.id,
      senderPhone: widget.userPhone,
      senderName: widget.userName,
      type: MessageType.sticker,
      mediaUrl: stickerUrl,
    );
    if (msg != null && mounted) {
      setState(() {
        _messages.add(msg);
        _messagesById[msg.id] = msg;
        _messagesCache[widget.conversation.id] = List.from(_messages);
      });
      _scrollToBottom();
    }
  }

  Future<void> _sendGif(String gifUrl) async {
    if (mounted) {
      setState(() => _showMediaPicker = false);
    }
    final msg = await MessengerService.sendMessage(
      conversationId: widget.conversation.id,
      senderPhone: widget.userPhone,
      senderName: widget.userName,
      type: MessageType.gif,
      mediaUrl: gifUrl,
    );
    if (msg != null && mounted) {
      setState(() {
        _messages.add(msg);
        _messagesById[msg.id] = msg;
        _messagesCache[widget.conversation.id] = List.from(_messages);
      });
      _scrollToBottom();
    }
  }

  void _handleAttachment() async {
    // Close media picker if open
    if (_showMediaPicker && mounted) {
      setState(() => _showMediaPicker = false);
    }

    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surfaceDark,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(top: 12, bottom: 20),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              // Row 1: Галерея | Контакт
              Row(
                children: [
                  _buildAttachmentCell(ctx, Icons.photo_library, 'Галерея', () => _pickFromGallery()),
                  const SizedBox(width: 12),
                  _buildAttachmentCell(ctx, Icons.person, 'Контакт', () => _pickAndShareContact()),
                ],
              ),
              const SizedBox(height: 12),
              // Row 2: Камера | Видео
              Row(
                children: [
                  _buildAttachmentCell(ctx, Icons.photo_camera, 'Камера', () => _pickAndSendImage(ImageSource.camera)),
                  const SizedBox(width: 12),
                  _buildAttachmentCell(ctx, Icons.videocam, 'Видео', () => _pickAndSendVideoFromCamera()),
                ],
              ),
              const SizedBox(height: 12),
              // Row 3: Документ | Опрос
              Row(
                children: [
                  _buildAttachmentCell(ctx, Icons.insert_drive_file, 'Документ', () => _pickAndSendFile()),
                  const SizedBox(width: 12),
                  _buildAttachmentCell(ctx, Icons.poll, 'Опрос', () => _createPoll()),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAttachmentCell(BuildContext ctx, IconData icon, String label, VoidCallback onTap) {
    return Expanded(
      child: GestureDetector(
        onTap: () {
          Navigator.pop(ctx);
          onTap();
        },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 16),
          decoration: BoxDecoration(
            border: Border.all(color: AppColors.gold.withOpacity(0.5), width: 1),
            borderRadius: BorderRadius.circular(14),
            color: AppColors.gold.withOpacity(0.06),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: AppColors.gold, size: 28),
              const SizedBox(height: 8),
              Text(
                label,
                style: TextStyle(
                  color: Colors.white.withOpacity(0.85),
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Opens gallery for picking photos and/or videos.
  Future<void> _pickFromGallery() async {
    try {
      final picker = ImagePicker();
      final picked = await picker.pickMultipleMedia();
      if (picked.isEmpty || !mounted) return;

      final images = <File>[];
      final videos = <File>[];

      for (final xf in picked.take(10)) {
        final path = xf.path.toLowerCase();
        if (path.endsWith('.mp4') || path.endsWith('.mov') || path.endsWith('.avi') || path.endsWith('.mkv') || path.endsWith('.webm')) {
          videos.add(File(xf.path));
        } else {
          images.add(File(xf.path));
        }
      }

      // Generate album group ID if multiple media selected
      final totalCount = images.length + videos.length;
      final groupId = totalCount > 1
          ? 'album_${DateTime.now().millisecondsSinceEpoch}_$totalCount'
          : null;

      // Send photos through editor
      if (images.isNotEmpty) {
        final editedFiles = await Navigator.push<List<File>>(
          context,
          MaterialPageRoute(
            builder: (_) => PhotoEditorPage(photos: images),
          ),
        );
        if (editedFiles != null && editedFiles.isNotEmpty && mounted) {
          await _uploadAndSendPhotos(editedFiles, mediaGroupId: groupId);
        }
      }

      // Send videos directly
      for (final video in videos) {
        final url = await MessengerService.uploadMedia(video);
        if (url == null || !mounted) continue;
        final msg = await MessengerService.sendMessage(
          conversationId: widget.conversation.id,
          senderPhone: widget.userPhone,
          senderName: widget.userName,
          type: MessageType.video,
          mediaUrl: url,
          mediaGroupId: groupId,
        );
        if (msg != null && mounted) {
          setState(() {
            _messages.add(msg);
            _rebuildIndex();
          });
          _messagesCache[widget.conversation.id] = List.of(_messages);
          _scrollToBottom();
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка загрузки: $e')),
        );
      }
    }
  }

  Future<void> _pickAndShareContact() async {
    try {
      // Проверяем доступ к контактам через FlutterContacts (корректно на iOS 18+)
      final contactsGranted = await FlutterContacts.requestPermission();
      if (!contactsGranted) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Для отправки контакта необходим доступ к телефонной книге')),
          );
        }
        return;
      }

      // Open native contact picker
      final picked = await FlutterContacts.openExternalPick();
      if (picked == null || !mounted) return;

      // Reload with full properties (phone numbers)
      final fullContact = await FlutterContacts.getContact(picked.id, withProperties: true);
      if (fullContact == null || !mounted) return;

      final phones = fullContact.phones;
      if (phones.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('У этого контакта нет номера телефона')),
          );
        }
        return;
      }

      // If multiple phones — let user pick one
      String selectedPhone = phones.first.number;
      if (phones.length > 1 && mounted) {
        final result = await showModalBottomSheet<String>(
          context: context,
          backgroundColor: AppColors.surfaceDark,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          builder: (ctx) => _buildPhonePickerSheet(fullContact.displayName, phones),
        );
        if (result == null || !mounted) return;
        selectedPhone = result;
      }

      // Show confirmation dialog with contact card preview
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => _buildContactConfirmDialog(fullContact.displayName, selectedPhone),
      );
      if (confirmed != true || !mounted) return;

      // Normalize phone and send
      final normalized = selectedPhone.replaceAll(RegExp(r'\D'), '');
      final contactJson = jsonEncode({'name': fullContact.displayName, 'phone': normalized});
      final msg = await MessengerService.sendMessage(
        conversationId: widget.conversation.id,
        senderPhone: widget.userPhone,
        senderName: widget.userName,
        type: MessageType.contact,
        content: contactJson,
      );
      if (msg != null && mounted) {
        setState(() {
          _messages.add(msg);
          _messagesById[msg.id] = msg;
          _messagesCache[widget.conversation.id] = List.from(_messages);
        });
        _scrollToBottom();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Не удалось выбрать контакт')),
        );
      }
    }
  }

  /// Bottom sheet for picking one phone number when contact has multiple
  Widget _buildPhonePickerSheet(String name, List<Phone> phones) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            child: Text(
              'Выберите номер для $name',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Colors.white.withOpacity(0.9),
              ),
            ),
          ),
          const SizedBox(height: 8),
          ...phones.map((p) => ListTile(
            leading: Icon(Icons.phone, color: AppColors.turquoise.withOpacity(0.7)),
            title: Text(p.number, style: TextStyle(color: Colors.white.withOpacity(0.9))),
            subtitle: p.label.name.isNotEmpty
                ? Text(p.label.name, style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 12))
                : null,
            onTap: () => Navigator.pop(context, p.number),
          )),
        ],
      ),
    );
  }

  /// Confirmation dialog showing contact card before sending
  Widget _buildContactConfirmDialog(String name, String phone) {
    final letter = name.isNotEmpty ? name[0].toUpperCase() : '?';
    return AlertDialog(
      backgroundColor: AppColors.surfaceDark,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Отправить контакт?',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w600,
              color: Colors.white.withOpacity(0.9),
            ),
          ),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.05),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white.withOpacity(0.08)),
            ),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      colors: [AppColors.emeraldLight, AppColors.emerald],
                    ),
                  ),
                  child: Center(
                    child: Text(letter,
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 20)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(name,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: Colors.white.withOpacity(0.9),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(phone,
                        style: TextStyle(fontSize: 14, color: Colors.white.withOpacity(0.5)),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      actionsAlignment: MainAxisAlignment.center,
      actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      actions: [
        Row(
          children: [
            Expanded(
              child: TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text('Отмена', style: TextStyle(color: Colors.white.withOpacity(0.4))),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [AppColors.turquoise, AppColors.emerald],
                  ),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: TextButton(
                  onPressed: () => Navigator.pop(context, true),
                  style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 12)),
                  child: const Text('Отправить',
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _openPrivateChatWith(String phone, String name) async {
    try {
      final conv = await MessengerService.getOrCreatePrivateChat(
        phone1: widget.userPhone,
        phone2: phone,
      );
      if (conv != null && mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => MessengerChatPage(
              conversation: conv,
              userPhone: widget.userPhone,
              userName: widget.userName,
              isClient: widget.isClient,
              phoneBookNames: widget.phoneBookNames,
            ),
          ),
        );
      }
    } catch (e) {
      Logger.error('messenger_chat: Failed to open private chat', e);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Не удалось открыть чат')),
        );
      }
    }
  }

  void _showContactActions(String phone, String name) {
    final letter = name.isNotEmpty ? name[0].toUpperCase() : '?';
    // Format phone for display
    final displayPhone = phone.length == 11
        ? '+${phone[0]} (${phone.substring(1, 4)}) ${phone.substring(4, 7)}-${phone.substring(7, 9)}-${phone.substring(9)}'
        : phone;
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surfaceDark,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Contact card preview
            Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      colors: [AppColors.emeraldLight, AppColors.emerald],
                    ),
                  ),
                  child: Center(
                    child: Text(letter,
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 20)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(name,
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.white.withOpacity(0.9)),
                      ),
                      const SizedBox(height: 2),
                      Text(displayPhone,
                        style: TextStyle(fontSize: 14, color: Colors.white.withOpacity(0.5)),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            // Action: Написать
            ListTile(
              leading: Container(
                width: 40, height: 40,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.turquoise.withOpacity(0.15),
                ),
                child: const Icon(Icons.chat_bubble_outline, color: AppColors.turquoise, size: 20),
              ),
              title: Text('Написать', style: TextStyle(color: Colors.white.withOpacity(0.9))),
              onTap: () {
                Navigator.pop(ctx);
                _openPrivateChatWith(phone, name);
              },
            ),
            // Action: Сохранить в контакты
            ListTile(
              leading: Container(
                width: 40, height: 40,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.emerald.withOpacity(0.15),
                ),
                child: const Icon(Icons.person_add_outlined, color: AppColors.emerald, size: 20),
              ),
              title: Text('Сохранить в контакты', style: TextStyle(color: Colors.white.withOpacity(0.9))),
              onTap: () {
                Navigator.pop(ctx);
                _saveToPhoneBook(phone, name);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _saveToPhoneBook(String phone, String name) async {
    try {
      // Format phone with + prefix for phone book
      final formattedPhone = phone.startsWith('+') ? phone : '+$phone';
      final newContact = Contact(
        name: Name(first: name),
        phones: [Phone(formattedPhone)],
      );
      await FlutterContacts.openExternalInsert(newContact);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Не удалось открыть контакты')),
        );
      }
    }
  }

  void _openImageViewer(String imageUrl, String? senderName) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ImageViewerPage(
          imageUrl: imageUrl,
          senderName: senderName,
        ),
      ),
    );
  }

  void _openVideoPlayer(String videoUrl, String? senderName) {
    // Collect all video URLs for swipe navigation
    final videoMessages = _messages
        .where((m) => m.type == MessageType.video && m.mediaUrl != null)
        .toList();
    final videoUrls = videoMessages.map((m) => m.mediaUrl!).toList();
    final index = videoUrls.indexOf(videoUrl);

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => VideoPlayerPage(
          videoUrl: videoUrl,
          senderName: senderName,
          videoUrls: videoUrls.length > 1 ? videoUrls : null,
          initialIndex: index >= 0 ? index : 0,
        ),
      ),
    );
  }

  Future<void> _openFile(String fileUrl, String fileName) async {
    final resolvedUrl = fileUrl.startsWith('http')
        ? fileUrl
        : '${ApiConstants.serverUrl}$fileUrl';
    final uri = Uri.parse(resolvedUrl);
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Не удалось открыть файл')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка: $e')),
        );
      }
    }
  }

  Future<void> _pickAndSendImage(ImageSource source) async {
    try {
      final picked = await ImagePicker().pickImage(source: source, imageQuality: 75, maxWidth: 1280);
      if (picked == null || !mounted) return;

      final editedFiles = await Navigator.push<List<File>>(
        context,
        MaterialPageRoute(
          builder: (_) => PhotoEditorPage(photos: [File(picked.path)]),
        ),
      );

      if (editedFiles == null || editedFiles.isEmpty || !mounted) return;

      await _uploadAndSendPhotos(editedFiles);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка загрузки: $e')),
        );
      }
    }
  }

  Future<void> _uploadAndSendPhotos(List<File> files, {String? mediaGroupId}) async {
    for (var file in files) {
      // Compress photo if larger than 500KB (resize 1280px + JPEG 75%)
      try {
        final bytes = await file.readAsBytes();
        if (bytes.length > 512 * 1024) {
          final compressed = await compute(compressImageIsolate, bytes.toList());
          if (compressed.length < bytes.length) {
            final tmpPath = '${file.path}_compressed.jpg';
            final tmpFile = File(tmpPath);
            await tmpFile.writeAsBytes(compressed);
            file = tmpFile;
          }
        }
      } catch (_) {
        // Compression failed — upload original
      }
      final url = await MessengerService.uploadMedia(file);
      if (url == null) continue;

      final msg = await MessengerService.sendMessage(
        conversationId: widget.conversation.id,
        senderPhone: widget.userPhone,
        senderName: widget.userName,
        type: MessageType.image,
        mediaUrl: url,
        mediaGroupId: files.length > 1 ? mediaGroupId : null,
      );

      if (msg != null && mounted) {
        setState(() {
          _messages.add(msg);
          _rebuildIndex();
        });
        _messagesCache[widget.conversation.id] = List.of(_messages);
        _scrollToBottom();
      }
    }
  }

  Future<void> _pickAndSendVideoFromCamera() async {
    try {
      final picked = await ImagePicker().pickVideo(source: ImageSource.camera, maxDuration: const Duration(minutes: 5));
      if (picked == null || !mounted) return;

      final file = File(picked.path);
      final url = await MessengerService.uploadMedia(file);
      if (url == null || !mounted) return;

      final msg = await MessengerService.sendMessage(
        conversationId: widget.conversation.id,
        senderPhone: widget.userPhone,
        senderName: widget.userName,
        type: MessageType.video,
        mediaUrl: url,
      );

      if (msg != null && mounted) {
        setState(() {
          _messages.add(msg);
          _messagesById[msg.id] = msg;
          _messagesCache[widget.conversation.id] = List.from(_messages);
        });
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

  Future<void> _pickAndSendFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf', 'doc', 'docx', 'xls', 'xlsx', 'zip', 'txt', 'csv'],
      );
      if (result == null || result.files.isEmpty) return;

      final platformFile = result.files.first;
      if (platformFile.path == null) return;

      final file = File(platformFile.path!);
      final url = await MessengerService.uploadMedia(file);
      if (url == null) return;

      final msg = await MessengerService.sendMessage(
        conversationId: widget.conversation.id,
        senderPhone: widget.userPhone,
        senderName: widget.userName,
        type: MessageType.file,
        mediaUrl: url,
        fileName: platformFile.name,
        fileSize: platformFile.size,
      );

      if (msg != null && mounted) {
        setState(() {
          _messages.add(msg);
          _messagesById[msg.id] = msg;
        });
        _messagesCache[widget.conversation.id] = List.of(_messages);
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

  // ========= Polls =========

  final Map<String, PollModel> _pollCache = {};
  static const int _pollCacheLimit = 100;

  Widget _buildPollWidget(MessengerMessage message) {
    final poll = _pollCache[message.id];
    if (poll == null) {
      // Load poll data asynchronously
      _getPoll(message.id).then((_) {
        if (mounted) setState(() {});
      });
      return Text(
        '📊 ${message.content ?? 'Загрузка...'}',
        style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 14),
      );
    }

    return PollBubble(
      poll: poll,
      userPhone: widget.userPhone,
      isMine: message.senderPhone == widget.userPhone,
      onVote: (optionIndex) => _votePoll(message.id, poll.id, optionIndex),
    );
  }

  Future<void> _createPoll() async {
    final result = await Navigator.push<Map<String, dynamic>>(
      context,
      MaterialPageRoute(builder: (_) => const CreatePollPage()),
    );
    if (result == null) return;

    final response = await MessengerService.createPoll(
      conversationId: widget.conversation.id,
      question: result['question'] as String,
      options: (result['options'] as List).cast<String>(),
      multipleChoice: result['multipleChoice'] == true,
      anonymous: result['anonymous'] == true,
    );

    if (response != null && response['message'] != null && mounted) {
      final msg = MessengerMessage.fromJson(response['message'] as Map<String, dynamic>);
      if (response['poll'] != null) {
        _pollCache[msg.id] = PollModel.fromJson(response['poll'] as Map<String, dynamic>);
      }
      setState(() {
        _messages.add(msg);
        _messagesById[msg.id] = msg;
      });
      _messagesCache[widget.conversation.id] = List.of(_messages);
      _scrollToBottom();
    }
  }

  /// Batch-load polls for all poll messages in one request
  Future<void> _batchLoadPolls(List<MessengerMessage> messages) async {
    final pollMsgIds = messages
        .where((m) => m.type == MessageType.poll && !_pollCache.containsKey(m.id))
        .map((m) => m.id)
        .toList();
    if (pollMsgIds.isEmpty) return;

    final pollsMap = await MessengerService.getPollsBatch(
      widget.conversation.id,
      pollMsgIds,
    );
    if (pollsMap.isNotEmpty && mounted) {
      setState(() {
        for (final entry in pollsMap.entries) {
          if (_pollCache.length >= _pollCacheLimit) {
            _pollCache.remove(_pollCache.keys.first);
          }
          _pollCache[entry.key] = PollModel.fromJson(entry.value);
        }
      });
    }
  }

  Future<PollModel?> _getPoll(String messageId) async {
    if (_pollCache.containsKey(messageId)) return _pollCache[messageId];
    final data = await MessengerService.getPoll(widget.conversation.id, messageId);
    if (data != null) {
      final poll = PollModel.fromJson(data);
      if (_pollCache.length >= _pollCacheLimit) {
        _pollCache.remove(_pollCache.keys.first);
      }
      _pollCache[messageId] = poll;
      return poll;
    }
    return null;
  }

  Future<void> _votePoll(String messageId, String pollId, int optionIndex) async {
    final result = await MessengerService.votePoll(widget.conversation.id, pollId, optionIndex);
    if (result != null && result['votes'] != null && mounted) {
      // Update cached poll
      final existing = _pollCache[messageId];
      if (existing != null) {
        final votes = <String, List<String>>{};
        final rawVotes = result['votes'] as Map;
        for (final entry in rawVotes.entries) {
          final key = entry.key.toString();
          if (entry.value is List) {
            votes[key] = (entry.value as List).map((e) => e.toString()).toList();
          }
        }
        _pollCache[messageId] = PollModel(
          id: existing.id,
          conversationId: existing.conversationId,
          messageId: existing.messageId,
          question: existing.question,
          options: existing.options,
          votes: votes,
          multipleChoice: existing.multipleChoice,
          anonymous: existing.anonymous,
          closed: existing.closed,
        );
        setState(() {});
      }
    }
  }

  // ========= Действия с сообщениями =========

  void _setReplyTo(MessengerMessage message) {
    if (mounted) {
      setState(() {
        _replyToId = message.id;
        _replyToText = message.preview;
      });
    }
  }

  void _handleLongPress(MessengerMessage message) {
    MessageContextMenu.show(
      context,
      message: message,
      userPhone: widget.userPhone,
      conversationId: widget.conversation.id,
      onReply: () => _setReplyTo(message),
      onEdit: (msg) => _startEditing(msg),
      onForward: (msg) => _forwardMessage(msg),
      onPin: (msg) => _togglePin(msg),
      onSaveToFavorites: (msg) => _saveToFavorites(msg),
      onSaveStickerToFavorites: (msg) => _saveStickerToFavorites(msg),
      onSaveGifToFavorites: (msg) => _saveGifToFavorites(msg),
      readers: _readersOf(message),
      onDeleteForMe: (msg) async {
        await MessengerService.deleteMessageForMe(widget.conversation.id, msg.id);
        if (mounted) {
          setState(() => _messages.removeWhere((m) => m.id == msg.id));
        }
      },
      onDeleteConfirmed: (msg) => () async {
        await MessengerService.deleteMessageForAll(widget.conversation.id, msg.id);
        _loadMessages(silent: true);
      },
    );
  }

  void _startEditing(MessengerMessage message) {
    if (mounted) {
      setState(() {
        _editingMessageId = message.id;
        _replyToId = null;
        _replyToText = null;
      });
      _textController.text = message.content ?? '';
      _textController.selection = TextSelection.fromPosition(
        TextPosition(offset: _textController.text.length),
      );
    }
  }

  void _cancelEditing() {
    if (mounted) {
      setState(() {
        _editingMessageId = null;
      });
      _textController.clear();
    }
  }

  Future<void> _submitEdit() async {
    final newContent = _textController.text.trim();
    if (newContent.isEmpty || _editingMessageId == null) return;

    final msgId = _editingMessageId!;
    _cancelEditing();

    final success = await MessengerService.editMessage(
      widget.conversation.id,
      msgId,
      content: newContent,
    );

    if (success && mounted) {
      // Local update will come via WS event, but update immediately for responsiveness
      final idx = _messages.indexWhere((m) => m.id == msgId);
      if (idx != -1) {
        setState(() {
          _messages[idx] = _messages[idx].copyWith(
            content: newContent,
            editedAt: DateTime.now(),
          );
        });
      }
    }
  }

  Future<void> _togglePin(MessengerMessage message) async {
    if (message.isPinned) {
      final success = await MessengerService.unpinMessage(widget.conversation.id, message.id);
      if (success && mounted) {
        setState(() {
          final idx = _messages.indexWhere((m) => m.id == message.id);
          if (idx != -1) _messages[idx] = _messages[idx].copyWith(isPinned: false);
          _pinnedMessages.removeWhere((m) => m.id == message.id);
          if (_currentPinnedIndex >= _pinnedMessages.length) {
            _currentPinnedIndex = _pinnedMessages.isEmpty ? 0 : _pinnedMessages.length - 1;
          }
        });
      }
    } else {
      final success = await MessengerService.pinMessage(widget.conversation.id, message.id, widget.userPhone);
      if (success && mounted) {
        setState(() {
          final idx = _messages.indexWhere((m) => m.id == message.id);
          if (idx != -1) _messages[idx] = _messages[idx].copyWith(isPinned: true);
          _pinnedMessages.insert(0, message);
          _currentPinnedIndex = 0;
        });
      }
    }
  }

  void _scrollToPinnedMessage() {
    if (_pinnedMessages.isEmpty) return;
    final pinned = _pinnedMessages[_currentPinnedIndex];
    final idx = _messages.indexWhere((m) => m.id == pinned.id);
    if (idx != -1) {
      // Each message is roughly 60-80px. Scroll to approximate position.
      _scrollController.animateTo(
        idx * 70.0,
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeOut,
      );
    }
  }

  void _showReadersList(MessengerMessage message) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.night,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return FutureBuilder<List<Map<String, dynamic>>>(
          future: MessengerService.getMessageReaders(widget.conversation.id, message.id),
          builder: (ctx, snapshot) {
            final readers = snapshot.data ?? [];
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 8),
                Container(width: 40, height: 4, decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2), borderRadius: BorderRadius.circular(2))),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    'Прочитали (${readers.length})',
                    style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                ),
                if (snapshot.connectionState == ConnectionState.waiting)
                  const Padding(
                    padding: EdgeInsets.all(24),
                    child: CircularProgressIndicator(color: AppColors.turquoise, strokeWidth: 2),
                  )
                else if (readers.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text('Никто ещё не прочитал',
                        style: TextStyle(color: Colors.white.withOpacity(0.5))),
                  )
                else
                  ConstrainedBox(
                    constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.4),
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: readers.length,
                      itemBuilder: (_, i) {
                        final r = readers[i];
                        final name = r['name'] ?? r['phone'] ?? '';
                        final avatar = r['avatar_url'] as String?;
                        return ListTile(
                          dense: true,
                          leading: CircleAvatar(
                            radius: 18,
                            backgroundColor: AppColors.emerald,
                            backgroundImage: avatar != null ? NetworkImage(avatar) : null,
                            child: avatar == null
                                ? Text(name.isNotEmpty ? name[0].toUpperCase() : '?',
                                    style: const TextStyle(color: Colors.white, fontSize: 14))
                                : null,
                          ),
                          title: Text(name, style: const TextStyle(color: Colors.white, fontSize: 14)),
                        );
                      },
                    ),
                  ),
                const SizedBox(height: 16),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _forwardMessage(MessengerMessage message) async {
    final targetIds = await Navigator.push<List<String>>(
      context,
      MaterialPageRoute(
        builder: (_) => ConversationPickerPage(userPhone: widget.userPhone),
      ),
    );
    if (targetIds == null || targetIds.isEmpty) return;

    final success = await MessengerService.forwardMessage(message.id, targetIds);
    if (success && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Переслано в ${targetIds.length} ${targetIds.length == 1 ? 'чат' : 'чатов'}'),
          backgroundColor: AppColors.emerald,
        ),
      );
    }
  }

  Future<void> _saveToFavorites(MessengerMessage message) async {
    // Get or create "Избранное" conversation, then forward the message there
    final saved = await MessengerService.getSavedMessages(widget.userPhone);
    if (saved == null) return;

    final success = await MessengerService.forwardMessage(message.id, [saved.id]);
    if (success && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Сохранено в Избранное'),
          backgroundColor: AppColors.emerald,
        ),
      );
    }
  }

  Future<void> _saveStickerToFavorites(MessengerMessage message) async {
    if (message.mediaUrl == null) return;
    final success = await MessengerService.addFavoriteSticker(message.mediaUrl!);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(success ? 'Стикер сохранён в избранное' : 'Не удалось сохранить стикер'),
          backgroundColor: success ? AppColors.emerald : AppColors.error,
        ),
      );
    }
  }

  Future<void> _saveGifToFavorites(MessengerMessage message) async {
    if (message.mediaUrl == null) return;
    final success = await MessengerService.addFavoriteGif(message.mediaUrl!);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(success ? 'GIF сохранён в избранное' : 'Не удалось сохранить GIF'),
          backgroundColor: success ? AppColors.emerald : AppColors.error,
        ),
      );
    }
  }

  Future<void> _checkBlockStatus() async {
    final otherPhone = widget.conversation.otherPhone(widget.userPhone);
    if (otherPhone == null) return; // group or saved — no blocking
    final blocks = await MessengerService.getBlockedUsers(widget.userPhone);
    final blocked = blocks.any((b) => b['blocked_phone'] == otherPhone);
    if (mounted && blocked != _isBlocked) {
      setState(() => _isBlocked = blocked);
    }
  }

  Future<void> _toggleBlock() async {
    final otherPhone = widget.conversation.otherPhone(widget.userPhone);
    if (otherPhone == null) return;

    if (_isBlocked) {
      await MessengerService.unblockUser(phone: widget.userPhone, blockedPhone: otherPhone);
    } else {
      await MessengerService.blockUser(phone: widget.userPhone, blockedPhone: otherPhone);
    }
    if (mounted) {
      setState(() => _isBlocked = !_isBlocked);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_isBlocked ? 'Пользователь заблокирован' : 'Пользователь разблокирован'),
          backgroundColor: AppColors.emerald,
        ),
      );
    }
  }

  void _showContactProfile() {
    showContactProfileSheet(
      context: context,
      conversation: widget.conversation,
      myPhone: widget.userPhone,
      myName: widget.userName,
      phoneBookNames: widget.phoneBookNames,
      isBlocked: _isBlocked,
      isMuted: _isMuted,
      onCall: _startCall,
      onSearch: _enterSearchMode,
      onToggleMute: _showMuteDialog,
      onToggleBlock: _toggleBlock,
      onDeleteChat: _deleteConversation,
      onOpenMediaGallery: _openMediaGallery,
    );
  }

  // ==================== SEARCH ====================

  void _enterSearchMode() {
    setState(() {
      _isSearchMode = true;
      _searchResults = [];
      _currentSearchIndex = -1;
      _highlightMessageId = null;
    });
  }

  void _exitSearchMode() {
    setState(() {
      _isSearchMode = false;
      _searchController.clear();
      _searchResults = [];
      _currentSearchIndex = -1;
      _highlightMessageId = null;
    });
  }

  Future<void> _performSearch(String query) async {
    if (query.trim().isEmpty) {
      setState(() {
        _searchResults = [];
        _currentSearchIndex = -1;
        _highlightMessageId = null;
      });
      return;
    }
    setState(() => _isSearching = true);
    final results = await MessengerService.searchMessages(
      widget.conversation.id,
      query.trim(),
      limit: 100,
    );
    if (!mounted) return;
    setState(() {
      _searchResults = results;
      _isSearching = false;
      _currentSearchIndex = results.isNotEmpty ? 0 : -1;
    });
    if (results.isNotEmpty) {
      _scrollToSearchResult(0);
    }
  }

  void _scrollToSearchResult(int index) {
    if (index < 0 || index >= _searchResults.length) return;
    final msgId = _searchResults[index].id;
    setState(() {
      _currentSearchIndex = index;
      _highlightMessageId = msgId;
    });

    final msgIndex = _messages.indexWhere((m) => m.id == msgId);
    if (msgIndex >= 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final key = _messageKeys[msgId];
        if (key?.currentContext != null) {
          Scrollable.ensureVisible(
            key!.currentContext!,
            alignment: 0.5,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
        } else {
          final reversedIndex = _messages.length - 1 - msgIndex;
          final estimatedOffset = reversedIndex * 72.0;
          if (_scrollController.hasClients) {
            _scrollController.jumpTo(
              estimatedOffset.clamp(0.0, _scrollController.position.maxScrollExtent),
            );
          }
          Future.delayed(const Duration(milliseconds: 300), () {
            if (!mounted) return;
            final retryKey = _messageKeys[msgId];
            if (retryKey?.currentContext != null) {
              Scrollable.ensureVisible(
                retryKey!.currentContext!,
                alignment: 0.5,
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeOut,
              );
            }
          });
        }
      });
    }
    // Clear highlight after 2 seconds
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted && _highlightMessageId == msgId) {
        setState(() => _highlightMessageId = null);
      }
    });
  }

  // ==================== MUTE ====================

  Future<void> _checkMuteStatus() async {
    try {
      final status = await MessengerService.getMuteStatus(widget.conversation.id);
      if (mounted) {
        setState(() => _isMuted = status['is_muted'] == true);
      }
    } catch (e) {
      Logger.error('messenger_chat: Failed to load mute status', e);
    }
  }

  void _showMuteDialog() {
    if (_isMuted) {
      // Unmute immediately
      _unmute();
      return;
    }
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surfaceDark,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              margin: const EdgeInsets.only(top: 12, bottom: 16),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.2),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Text(
              'Без звука',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white.withOpacity(0.95)),
            ),
            const SizedBox(height: 16),
            _muteOption(ctx, 'На 1 час', '1h'),
            _muteOption(ctx, 'На 8 часов', '8h'),
            _muteOption(ctx, 'На 2 дня', '2d'),
            _muteOption(ctx, 'Навсегда', 'forever'),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Widget _muteOption(BuildContext ctx, String label, String duration) {
    return InkWell(
      onTap: () {
        Navigator.pop(ctx);
        _mute(duration);
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        child: Row(
          children: [
            Icon(Icons.notifications_off_outlined, color: AppColors.turquoise, size: 22),
            const SizedBox(width: 16),
            Text(label, style: TextStyle(fontSize: 15, color: Colors.white.withOpacity(0.9))),
          ],
        ),
      ),
    );
  }

  Future<void> _mute(String duration) async {
    final success = await MessengerService.muteConversation(widget.conversation.id, duration);
    if (mounted && success) {
      setState(() => _isMuted = true);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Уведомления отключены'), backgroundColor: AppColors.emerald),
      );
    }
  }

  Future<void> _unmute() async {
    final success = await MessengerService.unmuteConversation(widget.conversation.id);
    if (mounted && success) {
      setState(() => _isMuted = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Уведомления включены'), backgroundColor: AppColors.emerald),
      );
    }
  }

  // ==================== AUTO-DELETE (DISAPPEARING MESSAGES) ====================

  static String _autoDeleteLabel(int seconds) {
    if (seconds <= 0) return 'Выкл';
    if (seconds == 86400) return '1 день';
    if (seconds == 604800) return '1 неделя';
    if (seconds == 2592000) return '1 месяц';
    return '${seconds}с';
  }

  void _showAutoDeleteDialog() {
    final current = widget.conversation.autoDeleteSeconds;
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.emeraldDark,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 36, height: 4,
              margin: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.2),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Row(
                children: [
                  const Icon(Icons.timer_outlined, color: AppColors.turquoise, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    'Исчезающие сообщения',
                    style: TextStyle(color: Colors.white.withOpacity(0.9), fontWeight: FontWeight.w600, fontSize: 16),
                  ),
                ],
              ),
            ),
            const Divider(color: Colors.white12, height: 1),
            _autoDeleteOption(ctx, 'Выключено', 0, current),
            _autoDeleteOption(ctx, '1 день', 86400, current),
            _autoDeleteOption(ctx, '1 неделя', 604800, current),
            _autoDeleteOption(ctx, '1 месяц', 2592000, current),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _autoDeleteOption(BuildContext ctx, String label, int seconds, int current) {
    final isActive = current == seconds;
    return ListTile(
      leading: Icon(
        isActive ? Icons.radio_button_checked : Icons.radio_button_unchecked,
        color: isActive ? AppColors.turquoise : Colors.white.withOpacity(0.4),
      ),
      title: Text(label, style: TextStyle(color: Colors.white.withOpacity(0.9))),
      onTap: () async {
        Navigator.pop(ctx);
        if (seconds == current) return;
        final ok = await MessengerService.setAutoDelete(widget.conversation.id, seconds);
        if (ok && mounted) {
          _loadMessages(silent: true);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(seconds > 0
                  ? 'Исчезающие сообщения: ${_autoDeleteLabel(seconds)}'
                  : 'Исчезающие сообщения выключены'),
              backgroundColor: AppColors.emerald,
            ),
          );
        }
      },
    );
  }

  // ==================== MEDIA GALLERY ====================

  Future<void> _openMediaGallery() async {
    final rawTitle = widget.conversation.displayName(widget.userPhone);
    final otherPhone = widget.conversation.otherPhone(widget.userPhone);
    final title = (otherPhone != null)
        ? MessengerShellPage.resolveDisplayName(otherPhone, rawTitle, widget.phoneBookNames)
        : rawTitle;
    final result = await Navigator.push<Map<String, dynamic>>(
      context,
      MaterialPageRoute(
        builder: (_) => MediaGalleryPage(
          conversationId: widget.conversation.id,
          title: 'Медиа — $title',
          userPhone: widget.userPhone,
        ),
      ),
    );

    // Handle "show in chat" result from gallery
    if (result != null && result['action'] == 'showInChat' && mounted) {
      final messageId = result['messageId'] as String?;
      if (messageId != null) {
        _scrollToMessage(messageId);
      }
    }
  }

  void _scrollToMessage(String messageId) {
    final index = _messages.indexWhere((m) => m.id == messageId);
    if (index == -1) return;

    setState(() => _highlightMessageId = messageId);

    // Try ensureVisible if the widget is already built
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final key = _messageKeys[messageId];
      if (key?.currentContext != null) {
        Scrollable.ensureVisible(
          key!.currentContext!,
          alignment: 0.5, // center on screen
          duration: const Duration(milliseconds: 400),
          curve: Curves.easeOut,
        );
      } else {
        // Message widget not built yet — jump to approximate area, then retry
        final reversedIndex = _messages.length - 1 - index;
        final approxOffset = reversedIndex * 80.0;
        if (_scrollController.hasClients) {
          _scrollController.jumpTo(
            approxOffset.clamp(0.0, _scrollController.position.maxScrollExtent),
          );
        }
        Future.delayed(const Duration(milliseconds: 300), () {
          if (!mounted) return;
          final retryKey = _messageKeys[messageId];
          if (retryKey?.currentContext != null) {
            Scrollable.ensureVisible(
              retryKey!.currentContext!,
              alignment: 0.5,
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOut,
            );
          }
        });
      }
    });

    // Clear highlight after animation
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _highlightMessageId = null);
    });
  }

  // ==================== ALBUM GROUPING ====================

  /// Returns all messages in the same album group, or null if not part of an album.
  /// Only returns for the FIRST message of the group (oldest in _messages).
  List<MessengerMessage>? _getAlbumGroup(int msgIndex) {
    final msg = _messages[msgIndex];
    if (msg.mediaGroupId == null) return null;

    // Only render album at the first message of the group
    if (msgIndex > 0 && _messages[msgIndex - 1].mediaGroupId == msg.mediaGroupId) {
      return null; // Not the first in group
    }

    final group = <MessengerMessage>[msg];
    for (int i = msgIndex + 1; i < _messages.length; i++) {
      if (_messages[i].mediaGroupId == msg.mediaGroupId) {
        group.add(_messages[i]);
      } else {
        break; // Album messages are consecutive
      }
    }
    return group.length > 1 ? group : null;
  }

  /// Check if this message should be hidden (part of album but not first).
  bool _isHiddenAlbumMember(int msgIndex) {
    final msg = _messages[msgIndex];
    if (msg.mediaGroupId == null) return false;
    return msgIndex > 0 && _messages[msgIndex - 1].mediaGroupId == msg.mediaGroupId;
  }

  Future<void> _deleteConversation() async {
    final success = await MessengerService.deleteConversation(
      widget.conversation.id,
      widget.userPhone,
    );
    if (mounted) {
      if (success) {
        Navigator.pop(context, 'deleted');
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Не удалось удалить чат'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  PreferredSizeWidget _buildSearchAppBar() {
    return AppBar(
      backgroundColor: AppColors.surfaceDark,
      elevation: 1,
      foregroundColor: Colors.white,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back),
        onPressed: _exitSearchMode,
      ),
      title: TextField(
        controller: _searchController,
        autofocus: true,
        style: TextStyle(color: Colors.white.withOpacity(0.9), fontSize: 16),
        decoration: InputDecoration(
          hintText: 'Поиск по сообщениям...',
          hintStyle: TextStyle(color: Colors.white.withOpacity(0.35)),
          border: InputBorder.none,
        ),
        onSubmitted: _performSearch,
        onChanged: (value) {
          if (value.isEmpty) {
            setState(() {
              _searchResults = [];
              _currentSearchIndex = -1;
              _highlightMessageId = null;
            });
          }
        },
      ),
      actions: [
        if (_isSearching)
          const Padding(
            padding: EdgeInsets.all(12),
            child: SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(color: AppColors.turquoise, strokeWidth: 2),
            ),
          )
        else if (_searchResults.isNotEmpty) ...[
          Text(
            '${_currentSearchIndex + 1}/${_searchResults.length}',
            style: TextStyle(fontSize: 13, color: Colors.white.withOpacity(0.5)),
          ),
          IconButton(
            icon: const Icon(Icons.keyboard_arrow_up, size: 24),
            onPressed: _currentSearchIndex > 0
                ? () => _scrollToSearchResult(_currentSearchIndex - 1)
                : null,
          ),
          IconButton(
            icon: const Icon(Icons.keyboard_arrow_down, size: 24),
            onPressed: _currentSearchIndex < _searchResults.length - 1
                ? () => _scrollToSearchResult(_currentSearchIndex + 1)
                : null,
          ),
        ] else
          IconButton(
            icon: const Icon(Icons.search),
            onPressed: () => _performSearch(_searchController.text),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final isGroup = widget.conversation.type == ConversationType.group;
    final isChannel = widget.conversation.type == ConversationType.channel;
    final isGroupOrChannel = isGroup || isChannel;
    final isSaved = widget.conversation.isSavedMessages(widget.userPhone);
    final rawTitle = widget.conversation.displayName(widget.userPhone);
    final otherPhone = widget.conversation.otherPhone(widget.userPhone);
    final title = (otherPhone != null)
        ? MessengerShellPage.resolveDisplayName(otherPhone, rawTitle, widget.phoneBookNames)
        : rawTitle;

    return Scaffold(
      backgroundColor: AppColors.night,
      appBar: _isSearchMode ? _buildSearchAppBar() : AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: Colors.white,
        titleSpacing: 0,
        title: GestureDetector(
          onTap: isGroupOrChannel ? () => _openGroupInfo() : (!isSaved ? () => _showContactProfile() : null),
          child: Row(
            children: [
              _buildAppBarAvatar(title, isGroup),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            title,
                            style: TextStyle(fontSize: 16, color: Colors.white.withOpacity(0.95)),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (widget.conversation.autoDeleteSeconds > 0)
                          Padding(
                            padding: const EdgeInsets.only(left: 4),
                            child: Icon(Icons.timer_outlined, size: 14, color: AppColors.turquoise.withOpacity(0.7)),
                          ),
                      ],
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
          // Voice call button (private chats only)
          if (!isGroup)
            IconButton(
              icon: Icon(Icons.call, color: Colors.white.withOpacity(0.7)),
              tooltip: 'Позвонить',
              onPressed: _startCall,
            ),
          if (isGroupOrChannel)
            IconButton(
              icon: Icon(isChannel ? Icons.campaign : Icons.group, color: Colors.white.withOpacity(0.6)),
              onPressed: _openGroupInfo,
            ),
          if (!isSaved)
            PopupMenuButton<String>(
              icon: Icon(Icons.more_vert, color: Colors.white.withOpacity(0.6)),
              color: AppColors.surfaceDark,
              onSelected: (value) {
                if (value == 'block') _toggleBlock();
                if (value == 'autoDelete') _showAutoDeleteDialog();
              },
              itemBuilder: (_) => [
                PopupMenuItem(
                  value: 'autoDelete',
                  child: Row(
                    children: [
                      Icon(
                        Icons.timer_outlined,
                        color: widget.conversation.autoDeleteSeconds > 0
                            ? AppColors.turquoise
                            : Colors.white70,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        widget.conversation.autoDeleteSeconds > 0
                            ? 'Исчезающие: ${_autoDeleteLabel(widget.conversation.autoDeleteSeconds)}'
                            : 'Исчезающие сообщения',
                        style: const TextStyle(color: Colors.white70),
                      ),
                    ],
                  ),
                ),
                if (!isGroup)
                  PopupMenuItem(
                    value: 'block',
                    child: Row(
                      children: [
                        Icon(
                          _isBlocked ? Icons.lock_open : Icons.block,
                          color: _isBlocked ? Colors.white70 : AppColors.error,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _isBlocked ? 'Разблокировать' : 'Заблокировать',
                          style: TextStyle(color: _isBlocked ? Colors.white70 : AppColors.error),
                        ),
                      ],
                    ),
                  ),
              ],
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
          // Pinned message bar
          if (_pinnedMessages.isNotEmpty)
            PinnedMessageBar(
              messages: _pinnedMessages,
              currentIndex: _currentPinnedIndex,
              onTap: _scrollToPinnedMessage,
              onUnpin: () => _togglePin(_pinnedMessages[_currentPinnedIndex]),
              onNext: _pinnedMessages.length > 1 ? () {
                setState(() {
                  _currentPinnedIndex = (_currentPinnedIndex + 1) % _pinnedMessages.length;
                });
                _scrollToPinnedMessage();
              } : null,
            ),
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
                : _loadError != null && _messages.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.cloud_off, size: 48, color: Colors.white.withOpacity(0.3)),
                            const SizedBox(height: 12),
                            Text(
                              _loadError!,
                              textAlign: TextAlign.center,
                              style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 15),
                            ),
                            const SizedBox(height: 16),
                            TextButton.icon(
                              onPressed: () {
                                setState(() { _loadError = null; _isLoading = true; });
                                _loadMessages();
                              },
                              icon: const Icon(Icons.refresh, color: AppColors.turquoise),
                              label: const Text('Повторить', style: TextStyle(color: AppColors.turquoise)),
                            ),
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
                        reverse: true,
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        itemCount: _messages.length + (_isLoadingMore ? 1 : 0),
                        itemBuilder: (context, index) {
                          // Loading indicator at the top (last index in reverse mode)
                          if (_isLoadingMore && index == _messages.length) {
                            return const Padding(
                              padding: EdgeInsets.all(8),
                              child: Center(
                                child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.turquoise),
                              ),
                            );
                          }

                          // Reverse: index 0 = newest (bottom), higher index = older (top)
                          final msgIndex = _messages.length - 1 - index;
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

                          // Assign GlobalKey for scroll-to-message
                          _messageKeys.putIfAbsent(message.id, () => GlobalKey());
                          final messageKey = _messageKeys[message.id]!;

                          // Skip hidden album members (not the first in group)
                          if (_isHiddenAlbumMember(msgIndex)) {
                            return const SizedBox.shrink();
                          }

                          // Album group — render as single AlbumBubble
                          final albumGroup = _getAlbumGroup(msgIndex);
                          if (albumGroup != null) {
                            final isAlbumHighlighted = albumGroup.any((m) => _highlightMessageId == m.id);
                            return Column(
                              key: messageKey,
                              children: [
                                if (dateSeparator != null) dateSeparator,
                                AnimatedContainer(
                                  duration: const Duration(milliseconds: 500),
                                  color: isAlbumHighlighted
                                      ? AppColors.turquoise.withOpacity(0.15)
                                      : Colors.transparent,
                                  child: AlbumBubble(
                                    messages: albumGroup,
                                    isMine: isMine,
                                    showSenderName: isGroup && !isMine,
                                    displaySenderName: (!isMine && isGroup)
                                        ? MessengerShellPage.resolveDisplayName(
                                            message.senderPhone, message.senderName,
                                            widget.phoneBookNames, isGroupContext: true)
                                        : null,
                                    onLongPress: () => _handleLongPress(message),
                                    onImageTap: (url) {
                                      Navigator.push(context, MaterialPageRoute(
                                        builder: (_) => ImageViewerPage(
                                          imageUrl: url,
                                          senderName: message.senderName ?? message.senderPhone,
                                        ),
                                      ));
                                    },
                                    onVideoTap: (url) {
                                      Navigator.push(context, MaterialPageRoute(
                                        builder: (_) => VideoPlayerPage(videoUrl: url),
                                      ));
                                    },
                                  ),
                                ),
                              ],
                            );
                          }

                          // Call message — special compact bubble
                          if (message.type == MessageType.call) {
                            return Column(
                              key: messageKey,
                              children: [
                                if (dateSeparator != null) dateSeparator,
                                _buildCallBubble(message, isMine),
                              ],
                            );
                          }

                          final isHighlighted = _highlightMessageId == message.id;
                          return Column(
                            key: messageKey,
                            children: [
                              if (dateSeparator != null) dateSeparator,
                              AnimatedContainer(
                                duration: const Duration(milliseconds: 500),
                                color: isHighlighted
                                    ? AppColors.turquoise.withOpacity(0.15)
                                    : Colors.transparent,
                                child: SwipeableMessage(
                                isMine: isMine,
                                onSwipeToReply: message.isDeleted ? null : () => _setReplyTo(message),
                                child: MessageBubble(
                                  message: message,
                                  isMine: isMine,
                                  replyToMessage: message.replyToId != null
                                      ? _messagesById[message.replyToId]
                                      : null,
                                  showSenderName: isGroup && !isMine,
                                  displaySenderName: (!isMine && isGroup)
                                      ? MessengerShellPage.resolveDisplayName(
                                          message.senderPhone, message.senderName,
                                          widget.phoneBookNames, isGroupContext: true)
                                      : null,
                                  onLongPress: () => _handleLongPress(message),
                                  onPlayVoice: message.type == MessageType.voice
                                      ? () => _handlePlayVoice(message)
                                      : null,
                                  isPlayingVoice: _playingMessageId == message.id && !_voicePaused,
                                  isVoicePaused: _playingMessageId == message.id && _voicePaused,
                                  voiceProgress: _playingMessageId == message.id ? _voiceProgress : 0.0,
                                  voicePositionSec: _playingMessageId == message.id ? _voicePositionSec : 0,
                                  onSeekVoice: _playingMessageId == message.id
                                      ? _handleSeekVoice
                                      : null,
                                  readersCount: isMine ? _readersCount(message) : 0,
                                  totalOtherCount: _otherParticipantCount,
                                  pollWidget: message.type == MessageType.poll
                                      ? _buildPollWidget(message)
                                      : null,
                                  onContactTap: message.type == MessageType.contact
                                      ? (phone, name) => _showContactActions(phone, name)
                                      : null,
                                  onImageTap: message.type == MessageType.image
                                      ? (url) => _openImageViewer(url, message.senderName ?? message.senderPhone)
                                      : null,
                                  onVideoTap: message.type == MessageType.video
                                      ? (url) => _openVideoPlayer(url, message.senderName ?? message.senderPhone)
                                      : null,
                                  onFileTap: message.type == MessageType.file
                                      ? (url, name) => _openFile(url, name)
                                      : null,
                                  onRetry: message.isFailed
                                      ? () => _retryMessage(message)
                                      : null,
                                  onReadersListTap: (isMine && isGroup && !message.isPending && !message.isFailed)
                                      ? () => _showReadersList(message)
                                      : null,
                                ),
                              ),
                              ),
                            ],
                          );
                        },
                      ),
          ),

          // Input bar (hidden for channel subscribers)
          if (_isChannelAdmin || widget.conversation.type != ConversationType.channel)
          MessageInputBar(
            onSendText: _handleSendText,
            onAttachmentTap: _handleAttachment,
            onMediaPickerTap: _toggleMediaPicker,
            onTyping: _handleTyping,
            onVoiceStart: _startVoiceRecording,
            onVoiceSend: _stopAndSendVoice,
            onVoiceCancel: _cancelVoiceRecording,
            onVideoNote: _handleVideoNote,
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
            isEditing: _editingMessageId != null,
            onCancelEdit: _cancelEditing,
            onTemplateTap: widget.isClient ? null : () => _showTemplatePicker(),
          ),

          // Combined media picker (Emoji + Stickers + GIF)
          if (_showMediaPicker)
            CombinedMediaPicker(
              textController: _textController,
              onStickerSelected: _sendSticker,
              onGifSelected: _sendGif,
            ),
        ],
      ),
    );
  }

  Widget _buildAppBarAvatar(String displayName, bool isGroup) {
    final letter = displayName.isNotEmpty ? displayName[0].toUpperCase() : '?';

    // Groups: group avatar. Private: other participant's profile avatar.
    String? avatarUrl;
    if (isGroup) {
      avatarUrl = widget.conversation.avatarUrl;
    } else {
      final other = widget.conversation.participants
          .where((p) => p.phone != widget.userPhone)
          .toList();
      if (other.isNotEmpty) avatarUrl = other.first.avatarUrl;
    }
    final hasAvatar = avatarUrl != null && avatarUrl.isNotEmpty;

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
              imageUrl: avatarUrl.startsWith('http')
                  ? avatarUrl
                  : '${ApiConstants.serverUrl}$avatarUrl',
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

  // ─── Call message bubble ───

  Widget _buildCallBubble(MessengerMessage message, bool isMine) {
    final isMissed = message.content?.contains('Пропущенный') == true;
    final isRejected = message.content?.contains('отклонён') == true;
    final color = isMissed ? Colors.red : AppColors.turquoise;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Align(
        alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.07),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: color.withOpacity(0.3)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                isMissed || isRejected ? Icons.call_missed : Icons.call,
                color: color,
                size: 18,
              ),
              const SizedBox(width: 8),
              Text(
                message.content ?? 'Звонок',
                style: TextStyle(color: Colors.white.withOpacity(0.85), fontSize: 14),
              ),
              const SizedBox(width: 8),
              Text(
                message.formattedTime,
                style: TextStyle(color: Colors.white.withOpacity(0.35), fontSize: 11),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ─── Voice call ───

  void _startCall() {
    // Find the remote participant (not me)
    // Normalize phones to digits-only for comparison (avoids +7 vs 7 mismatch)
    final myPhoneNorm = widget.userPhone.replaceAll(RegExp(r'[^\d]'), '');
    final participants = widget.conversation.participants;
    final remote = participants.cast<Participant?>().firstWhere(
      (p) => p!.phone.replaceAll(RegExp(r'[^\d]'), '') != myPhoneNorm,
      orElse: () => null,
    );

    // Self-call protection: if no remote participant found, abort
    if (remote == null) return;
    final remotePhoneNorm = remote.phone.replaceAll(RegExp(r'[^\d]'), '');
    if (remotePhoneNorm == myPhoneNorm || remotePhoneNorm.isEmpty) return;

    final callService = CallService.instance;

    // Navigate to call page first, then start the call
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CallPage(
          callInfo: CallInfo(
            callId: 'pending_${DateTime.now().millisecondsSinceEpoch}',
            remotePhone: remote.phone,
            remoteName: MessengerShellPage.resolveDisplayName(
              remote.phone,
              remote.name,
              widget.phoneBookNames,
            ),
            isOutgoing: true,
            startedAt: DateTime.now(),
          ),
        ),
      ),
    );

    // Initiate WebRTC call after navigation
    callService.startCall(
      targetPhone: remote.phone,
      targetName: MessengerShellPage.resolveDisplayName(
        remote.phone,
        remote.name,
        widget.phoneBookNames,
      ),
      conversationId: widget.conversation.id,
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
