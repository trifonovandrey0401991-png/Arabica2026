import 'dart:async';
import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../models/contact_model.dart';
import '../models/conversation_model.dart';
import '../services/messenger_service.dart';
import '../services/messenger_ws_service.dart';
import '../widgets/chat_list_tile.dart';
import 'messenger_chat_page.dart';
import 'contact_search_page.dart';
import 'channel_list_page.dart';
import 'manage_folders_page.dart';
import 'messenger_shell_page.dart';
import '../models/chat_folder_model.dart';

class MessengerListPage extends StatefulWidget {
  final String userPhone;
  final String userName;
  final List<MessengerContact> matchedContacts;
  final bool contactsGranted;
  final bool isClient;
  final Map<String, String> phoneBookNames;

  const MessengerListPage({
    super.key,
    required this.userPhone,
    required this.userName,
    required this.matchedContacts,
    required this.contactsGranted,
    this.isClient = false,
    this.phoneBookNames = const {},
  });

  @override
  State<MessengerListPage> createState() => _MessengerListPageState();
}

class _MessengerListPageState extends State<MessengerListPage> {
  List<Conversation> _conversations = [];
  Conversation? _savedConversation;
  bool _isLoading = true;
  String? _error;
  late String _userName;

  // Folder tabs
  int _activeTabIndex = 0; // 0=Все, 1+=custom folders
  List<ChatFolder> _customFolders = [];
  static const _builtInTabs = ['Все'];

  StreamSubscription? _newMessageSub;
  StreamSubscription? _readReceiptSub;
  Timer? _refreshTimer;
  Timer? _debounceTimer;

  @override
  void initState() {
    super.initState();
    _userName = widget.userName;
    _loadConversations();
    _loadSavedConversation();
    _loadFolders();
    _setupWebSocket();
    _refreshTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      _loadConversations(silent: true);
    });
  }

  @override
  void dispose() {
    _newMessageSub?.cancel();
    _readReceiptSub?.cancel();
    _refreshTimer?.cancel();
    _debounceTimer?.cancel();
    super.dispose();
  }

  /// Debounce WS-triggered reloads: wait 500ms before fetching,
  /// so multiple rapid events (messages, receipts) result in a single request.
  void _debouncedReload() {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 500), () {
      _loadConversations(silent: true);
    });
  }

  void _setupWebSocket() {
    final ws = MessengerWsService.instance;
    ws.connect(widget.userPhone);

    _newMessageSub = ws.onNewMessage.listen((event) {
      _debouncedReload();
    });

    _readReceiptSub = ws.onReadReceipt.listen((event) {
      _debouncedReload();
    });
  }

  Future<void> _loadConversations({bool silent = false}) async {
    if (!silent && mounted) {
      setState(() {
        _isLoading = true;
        _error = null;
      });
    }

    try {
      final conversations = await MessengerService.getConversations(widget.userPhone);
      if (mounted) {
        setState(() {
          // Only replace list if server returned non-empty result
          // This prevents dialogs from disappearing on temporary server hiccups
          if (conversations.isNotEmpty || _conversations.isEmpty) {
            _conversations = conversations;
          }
          _isLoading = false;
        });
      }
    } catch (e) {
      // On error — keep existing list, just stop loading spinner
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _loadSavedConversation() async {
    try {
      final saved = await MessengerService.getSavedMessages(widget.userPhone);
      if (mounted && saved != null) {
        setState(() => _savedConversation = saved);
      }
    } catch (_) {
      // Silently ignore — "Избранное" is optional
    }
  }

  Future<void> _loadFolders() async {
    try {
      final raw = await MessengerService.getFolders(widget.userPhone);
      if (mounted) {
        setState(() {
          _customFolders = raw.map((j) => ChatFolder.fromJson(j)).toList();
        });
      }
    } catch (_) {}
  }

  List<Conversation> _filteredConversations() {
    final base = _conversations
        .where((c) => !c.isSavedMessages(widget.userPhone))
        .toList();

    // Sort by last message time (newest first) — like Telegram
    base.sort((a, b) {
      final aTime = a.lastMessage?.createdAt ?? a.createdAt;
      final bTime = b.lastMessage?.createdAt ?? b.createdAt;
      return bTime.compareTo(aTime);
    });

    if (_activeTabIndex == 0) return base; // "Все"

    // Custom folder
    final folderIdx = _activeTabIndex - _builtInTabs.length;
    if (folderIdx >= 0 && folderIdx < _customFolders.length) {
      final folder = _customFolders[folderIdx];
      final ids = folder.conversationIds.toSet();
      return base.where((c) => ids.contains(c.id)).toList();
    }

    return base;
  }

  void _openSaved() {
    if (_savedConversation == null) return;
    _openChat(_savedConversation!);
  }

  void _openChat(Conversation conversation) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MessengerChatPage(
          conversation: conversation,
          userPhone: widget.userPhone,
          userName: _userName,
          isClient: widget.isClient,
          phoneBookNames: widget.phoneBookNames,
        ),
      ),
    ).then((_) => _loadConversations(silent: true));
  }

  void _openContactSearch() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ContactSearchPage(
          userPhone: widget.userPhone,
          userName: _userName,
          matchedContacts: widget.contactsGranted ? widget.matchedContacts : null,
        ),
      ),
    ).then((_) => _loadConversations(silent: true));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.night,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: Colors.white,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          tooltip: 'Назад в приложение',
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Мессенджер',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: Colors.white.withOpacity(0.95),
          ),
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.campaign_outlined, color: Colors.white.withOpacity(0.6)),
            tooltip: 'Каналы',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ChannelListPage(
                    userPhone: widget.userPhone,
                    userName: widget.userName,
                    isClient: widget.isClient,
                    phoneBookNames: widget.phoneBookNames,
                  ),
                ),
              ).then((_) => _loadConversations(silent: true));
            },
          ),
          IconButton(
            icon: Icon(Icons.refresh, color: Colors.white.withOpacity(0.6)),
            onPressed: () => _loadConversations(),
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
          _buildFolderTabs(),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  Widget _buildSavedTile() {
    final saved = _savedConversation!;
    final lastMsg = saved.lastMessage;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: _openSaved,
        splashColor: Colors.white.withOpacity(0.05),
        highlightColor: Colors.white.withOpacity(0.03),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(color: Colors.white.withOpacity(0.06)),
            ),
          ),
          child: Row(
            children: [
              // Bookmark avatar
              Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [AppColors.turquoise, AppColors.emerald],
                  ),
                  border: Border.all(color: Colors.white.withOpacity(0.15), width: 1.5),
                ),
                child: const Center(
                  child: Icon(Icons.bookmark, color: Colors.white, size: 24),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Избранное',
                            style: TextStyle(
                              fontWeight: FontWeight.w500,
                              fontSize: 15,
                              color: Colors.white.withOpacity(0.8),
                            ),
                          ),
                        ),
                        if (lastMsg != null)
                          Text(
                            lastMsg.formattedTime,
                            style: TextStyle(fontSize: 12, color: Colors.white.withOpacity(0.35)),
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      lastMsg?.preview ?? 'Ваши заметки',
                      style: TextStyle(fontSize: 13, color: Colors.white.withOpacity(0.35)),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  int _unreadCountForTab(int tabIndex) {
    final nonSaved = _conversations.where((c) => !c.isSavedMessages(widget.userPhone));
    if (tabIndex == 0) {
      // "Все" — total unread across all conversations
      return nonSaved.fold<int>(0, (sum, c) => sum + c.unreadCount);
    }
    // Custom folder
    final folderIdx = tabIndex - _builtInTabs.length;
    if (folderIdx >= 0 && folderIdx < _customFolders.length) {
      final ids = _customFolders[folderIdx].conversationIds.toSet();
      return nonSaved.where((c) => ids.contains(c.id)).fold<int>(0, (sum, c) => sum + c.unreadCount);
    }
    return 0;
  }

  Widget _buildFolderTabs() {
    final allTabs = [..._builtInTabs, ..._customFolders.map((f) => f.name)];
    return Container(
      decoration: BoxDecoration(
        color: AppColors.night.withOpacity(0.95),
        border: Border(bottom: BorderSide(color: Colors.white.withOpacity(0.06))),
      ),
      child: Row(
        children: [
          ...List.generate(allTabs.length, (index) {
            final isActive = index == _activeTabIndex;
            final unread = _unreadCountForTab(index);
            return Expanded(
              child: GestureDetector(
                onTap: () {
                  if (mounted) setState(() => _activeTabIndex = index);
                },
                behavior: HitTestBehavior.opaque,
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  decoration: BoxDecoration(
                    border: Border(
                      bottom: BorderSide(
                        color: isActive ? AppColors.turquoise : Colors.transparent,
                        width: 2,
                      ),
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child: Text(
                          allTabs[index],
                          textAlign: TextAlign.center,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
                            color: isActive ? AppColors.turquoise : Colors.white.withOpacity(0.4),
                          ),
                        ),
                      ),
                      if (unread > 0) ...[
                        const SizedBox(width: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                          decoration: BoxDecoration(
                            color: AppColors.turquoise,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            unread > 99 ? '99+' : unread.toString(),
                            style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            );
          }),
          // Edit folders button — same size as tabs
          Expanded(
            child: GestureDetector(
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ManageFoldersPage(
                      userPhone: widget.userPhone,
                      conversations: _conversations,
                    ),
                  ),
                ).then((_) => _loadFolders());
              },
              behavior: HitTestBehavior.opaque,
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Icon(Icons.edit_outlined, size: 18, color: Colors.white.withOpacity(0.4)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.turquoise, strokeWidth: 2.5),
      );
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 48, color: Colors.white.withOpacity(0.3)),
            const SizedBox(height: 16),
            Text(_error!, style: TextStyle(color: Colors.white.withOpacity(0.5))),
            const SizedBox(height: 16),
            Container(
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [AppColors.turquoise, AppColors.emerald],
                ),
                borderRadius: BorderRadius.circular(12),
              ),
              child: ElevatedButton(
                onPressed: _loadConversations,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.transparent,
                  shadowColor: Colors.transparent,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: const Text('Повторить', style: TextStyle(color: Colors.white)),
              ),
            ),
          ],
        ),
      );
    }

    if (_conversations.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.chat_bubble_outline, size: 64, color: Colors.white.withOpacity(0.15)),
            const SizedBox(height: 16),
            Text(
              'Нет диалогов',
              style: TextStyle(fontSize: 18, color: Colors.white.withOpacity(0.5)),
            ),
            const SizedBox(height: 8),
            Text(
              'Перейдите в Контакты, чтобы начать чат',
              style: TextStyle(fontSize: 14, color: Colors.white.withOpacity(0.3)),
            ),
          ],
        ),
      );
    }

    final filteredConversations = _filteredConversations();

    final hasSaved = _savedConversation != null && _activeTabIndex == 0;
    final totalItems = filteredConversations.length + (hasSaved ? 1 : 0);
    final isInFolder = _activeTabIndex > 0 && (_activeTabIndex - _builtInTabs.length) < _customFolders.length;

    return Stack(
      children: [
        RefreshIndicator(
          color: AppColors.turquoise,
          backgroundColor: AppColors.night,
          onRefresh: () => _loadConversations(),
          child: ListView.builder(
            itemCount: totalItems,
            itemBuilder: (context, index) {
              // "Избранное" card — always first
              if (hasSaved && index == 0) {
                return _buildSavedTile();
              }
              final convIndex = hasSaved ? index - 1 : index;
              final conv = filteredConversations[convIndex];
              return ChatListTile(
                conversation: conv,
                myPhone: widget.userPhone,
                onTap: () => _openChat(conv),
                onLongPress: isInFolder ? () => _showRemoveFromFolder(conv) : null,
                isClient: widget.isClient,
                phoneBookNames: widget.phoneBookNames,
              );
            },
          ),
        ),
        // FAB "+" — only visible inside a custom folder
        if (isInFolder)
          Positioned(
            bottom: 16,
            right: 16,
            child: Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const LinearGradient(
                  colors: [AppColors.turquoise, AppColors.emerald],
                ),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.turquoise.withOpacity(0.4),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Material(
                color: Colors.transparent,
                shape: const CircleBorder(),
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: _showFolderChatSelector,
                  child: const Center(
                    child: Icon(Icons.add, color: Colors.white, size: 28),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  void _showRemoveFromFolder(Conversation conv) {
    final folderIdx = _activeTabIndex - _builtInTabs.length;
    if (folderIdx < 0 || folderIdx >= _customFolders.length) return;
    final folder = _customFolders[folderIdx];

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
              width: 40, height: 4,
              margin: const EdgeInsets.only(top: 12, bottom: 8),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.2),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            ListTile(
              leading: Icon(Icons.folder_off, color: Colors.red.shade300),
              title: Text(
                'Убрать из «${folder.name}»',
                style: TextStyle(color: Colors.white.withOpacity(0.9)),
              ),
              onTap: () async {
                Navigator.pop(ctx);
                await MessengerService.removeConversationFromFolder(folder.id, conv.id);
                _loadFolders();
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  void _showFolderChatSelector() {
    final folderIdx = _activeTabIndex - _builtInTabs.length;
    if (folderIdx < 0 || folderIdx >= _customFolders.length) return;
    final folder = _customFolders[folderIdx];
    final allConvs = _conversations
        .where((c) => !c.isSavedMessages(widget.userPhone))
        .toList();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF0A2A2A),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.85,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        builder: (_, scrollController) => _FolderChatSelectorSheet(
          folder: folder,
          conversations: allConvs,
          myPhone: widget.userPhone,
          isClient: widget.isClient,
          phoneBookNames: widget.phoneBookNames,
          scrollController: scrollController,
          onDone: () {
            Navigator.pop(ctx);
            _loadFolders();
          },
        ),
      ),
    );
  }
}

/// Full-screen bottom sheet for selecting chats to add/remove from a folder.
class _FolderChatSelectorSheet extends StatefulWidget {
  final ChatFolder folder;
  final List<Conversation> conversations;
  final String myPhone;
  final bool isClient;
  final Map<String, String> phoneBookNames;
  final ScrollController scrollController;
  final VoidCallback onDone;

  const _FolderChatSelectorSheet({
    required this.folder,
    required this.conversations,
    required this.myPhone,
    required this.isClient,
    required this.phoneBookNames,
    required this.scrollController,
    required this.onDone,
  });

  @override
  State<_FolderChatSelectorSheet> createState() => _FolderChatSelectorSheetState();
}

class _FolderChatSelectorSheetState extends State<_FolderChatSelectorSheet> {
  late Set<String> _selected;
  late Set<String> _originalIds;
  final _searchController = TextEditingController();
  String _searchQuery = '';
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _originalIds = widget.folder.conversationIds.toSet();
    _selected = Set.from(_originalIds);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<Conversation> get _filtered {
    if (_searchQuery.isEmpty) return widget.conversations;
    final q = _searchQuery.toLowerCase();
    return widget.conversations.where((c) {
      final name = _resolveName(c).toLowerCase();
      return name.contains(q);
    }).toList();
  }

  String _resolveName(Conversation c) {
    if (c.type == ConversationType.group || c.type == ConversationType.channel) {
      return c.displayName(widget.myPhone);
    }
    // Private chat — resolve via phone book
    final other = c.participants.where((p) => p.phone != widget.myPhone).toList();
    if (other.isEmpty) return c.displayName(widget.myPhone);
    return MessengerShellPage.resolveDisplayName(
      other.first.phone,
      other.first.name,
      widget.phoneBookNames,
    );
  }

  Future<void> _save() async {
    if (_isSaving) return;
    setState(() => _isSaving = true);

    final toAdd = _selected.difference(_originalIds);
    final toRemove = _originalIds.difference(_selected);

    for (final id in toAdd) {
      await MessengerService.addConversationToFolder(widget.folder.id, id);
    }
    for (final id in toRemove) {
      await MessengerService.removeConversationFromFolder(widget.folder.id, id);
    }

    widget.onDone();
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filtered;

    return Column(
      children: [
        // Drag handle
        Container(
          width: 40, height: 4,
          margin: const EdgeInsets.only(top: 12, bottom: 12),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.2),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        // Header
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'Чаты в «${widget.folder.name}»',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.white.withOpacity(0.9),
                  ),
                ),
              ),
              _isSaving
                  ? const SizedBox(
                      width: 24, height: 24,
                      child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.turquoise),
                    )
                  : TextButton(
                      onPressed: _save,
                      child: const Text('Готово', style: TextStyle(color: AppColors.turquoise, fontWeight: FontWeight.w600)),
                    ),
            ],
          ),
        ),
        // Search
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: TextField(
            controller: _searchController,
            style: const TextStyle(color: Colors.white, fontSize: 14),
            decoration: InputDecoration(
              hintText: 'Поиск...',
              hintStyle: TextStyle(color: Colors.white.withOpacity(0.3)),
              prefixIcon: Icon(Icons.search, color: Colors.white.withOpacity(0.3), size: 20),
              filled: true,
              fillColor: Colors.white.withOpacity(0.06),
              contentPadding: const EdgeInsets.symmetric(vertical: 10),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
            ),
            onChanged: (val) {
              if (mounted) setState(() => _searchQuery = val.trim());
            },
          ),
        ),
        // Conversation list
        Expanded(
          child: ListView.builder(
            controller: widget.scrollController,
            itemCount: filtered.length,
            itemBuilder: (context, index) {
              final conv = filtered[index];
              final isChecked = _selected.contains(conv.id);
              final name = _resolveName(conv);
              final isGroup = conv.type == ConversationType.group;
              final letter = name.isNotEmpty ? name[0].toUpperCase() : '?';

              return InkWell(
                onTap: () {
                  setState(() {
                    if (isChecked) {
                      _selected.remove(conv.id);
                    } else {
                      _selected.add(conv.id);
                    }
                  });
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Row(
                    children: [
                      // Avatar
                      Container(
                        width: 40, height: 40,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: LinearGradient(
                            colors: isGroup
                                ? [AppColors.turquoise, AppColors.emerald]
                                : [AppColors.emeraldLight, AppColors.emerald],
                          ),
                        ),
                        child: Center(
                          child: isGroup
                              ? const Icon(Icons.group, color: Colors.white, size: 18)
                              : Text(letter, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600)),
                        ),
                      ),
                      const SizedBox(width: 12),
                      // Name
                      Expanded(
                        child: Text(
                          name,
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.85),
                            fontSize: 14,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      // Checkbox
                      Checkbox(
                        value: isChecked,
                        onChanged: (val) {
                          setState(() {
                            if (val == true) {
                              _selected.add(conv.id);
                            } else {
                              _selected.remove(conv.id);
                            }
                          });
                        },
                        activeColor: AppColors.turquoise,
                        checkColor: Colors.white,
                        side: BorderSide(color: Colors.white.withOpacity(0.3)),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
