import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../models/conversation_model.dart';
import '../models/chat_folder_model.dart';
import '../services/messenger_service.dart';

/// Page to create, edit, and delete custom chat folders.
class ManageFoldersPage extends StatefulWidget {
  final String userPhone;
  final List<Conversation> conversations;

  const ManageFoldersPage({
    super.key,
    required this.userPhone,
    required this.conversations,
  });

  @override
  State<ManageFoldersPage> createState() => _ManageFoldersPageState();
}

class _ManageFoldersPageState extends State<ManageFoldersPage> {
  List<ChatFolder> _folders = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadFolders();
  }

  Future<void> _loadFolders() async {
    final raw = await MessengerService.getFolders(widget.userPhone);
    if (mounted) {
      setState(() {
        _folders = raw.map((j) => ChatFolder.fromJson(j)).toList();
        _isLoading = false;
      });
    }
  }

  Future<void> _createFolder() async {
    final nameController = TextEditingController();
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF0A2A2A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Новая папка', style: TextStyle(color: Colors.white.withOpacity(0.9))),
        content: TextField(
          controller: nameController,
          style: const TextStyle(color: Colors.white),
          autofocus: true,
          decoration: InputDecoration(
            hintText: 'Название',
            hintStyle: TextStyle(color: Colors.white.withOpacity(0.3)),
            enabledBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: Colors.white.withOpacity(0.2)),
            ),
            focusedBorder: const UnderlineInputBorder(
              borderSide: BorderSide(color: AppColors.turquoise),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Отмена', style: TextStyle(color: Colors.white.withOpacity(0.5))),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Создать', style: TextStyle(color: AppColors.turquoise)),
          ),
        ],
      ),
    );

    if (result == true && nameController.text.trim().isNotEmpty) {
      await MessengerService.createFolder(
        phone: widget.userPhone,
        name: nameController.text.trim(),
        sortOrder: _folders.length,
      );
      _loadFolders();
    }
    nameController.dispose();
  }

  Future<void> _deleteFolder(ChatFolder folder) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF0A2A2A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Удалить папку?', style: TextStyle(color: Colors.white.withOpacity(0.9))),
        content: Text(
          'Папка «${folder.name}» будет удалена. Чаты останутся на месте.',
          style: TextStyle(color: Colors.white.withOpacity(0.6)),
        ),
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
      await MessengerService.deleteFolder(folder.id);
      _loadFolders();
    }
  }

  Future<void> _editFolderChats(ChatFolder folder) async {
    // Show a dialog to add/remove conversations from this folder
    final allConvs = widget.conversations
        .where((c) => !c.isSavedMessages(widget.userPhone))
        .toList();
    final selectedIds = Set<String>.from(folder.conversationIds);

    final result = await showDialog<Set<String>>(
      context: context,
      builder: (ctx) => _ConversationSelectorDialog(
        conversations: allConvs,
        selectedIds: selectedIds,
        myPhone: widget.userPhone,
        folderName: folder.name,
      ),
    );

    if (result != null) {
      // Sync: add new, remove old
      final oldIds = folder.conversationIds.toSet();
      final toAdd = result.difference(oldIds);
      final toRemove = oldIds.difference(result);

      for (final id in toAdd) {
        await MessengerService.addConversationToFolder(folder.id, id);
      }
      for (final id in toRemove) {
        await MessengerService.removeConversationFromFolder(folder.id, id);
      }
      _loadFolders();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.night,
      appBar: AppBar(
        backgroundColor: AppColors.night,
        title: const Text('Папки', style: TextStyle(color: Colors.white)),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            icon: const Icon(Icons.add, color: AppColors.turquoise),
            tooltip: 'Новая папка',
            onPressed: _createFolder,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: AppColors.turquoise))
          : _folders.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.folder_outlined, size: 64, color: Colors.white.withOpacity(0.15)),
                      const SizedBox(height: 16),
                      Text('Нет папок', style: TextStyle(fontSize: 18, color: Colors.white.withOpacity(0.5))),
                      const SizedBox(height: 8),
                      Text(
                        'Нажмите + чтобы создать',
                        style: TextStyle(fontSize: 14, color: Colors.white.withOpacity(0.3)),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  itemCount: _folders.length,
                  itemBuilder: (context, index) {
                    final folder = _folders[index];
                    return ListTile(
                      leading: Icon(Icons.folder, color: AppColors.turquoise.withOpacity(0.7)),
                      title: Text(
                        folder.name,
                        style: TextStyle(color: Colors.white.withOpacity(0.9)),
                      ),
                      subtitle: Text(
                        '${folder.conversationIds.length} чатов',
                        style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 13),
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: Icon(Icons.edit, size: 20, color: Colors.white.withOpacity(0.4)),
                            onPressed: () => _editFolderChats(folder),
                          ),
                          IconButton(
                            icon: Icon(Icons.delete_outline, size: 20, color: AppColors.error.withOpacity(0.7)),
                            onPressed: () => _deleteFolder(folder),
                          ),
                        ],
                      ),
                    );
                  },
                ),
    );
  }
}

/// Dialog for selecting conversations to include in a folder.
class _ConversationSelectorDialog extends StatefulWidget {
  final List<Conversation> conversations;
  final Set<String> selectedIds;
  final String myPhone;
  final String folderName;

  const _ConversationSelectorDialog({
    required this.conversations,
    required this.selectedIds,
    required this.myPhone,
    required this.folderName,
  });

  @override
  State<_ConversationSelectorDialog> createState() => _ConversationSelectorDialogState();
}

class _ConversationSelectorDialogState extends State<_ConversationSelectorDialog> {
  late Set<String> _selected;

  @override
  void initState() {
    super.initState();
    _selected = Set.from(widget.selectedIds);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF0A2A2A),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Text(
        'Чаты в «${widget.folderName}»',
        style: TextStyle(color: Colors.white.withOpacity(0.9), fontSize: 16),
      ),
      content: SizedBox(
        width: double.maxFinite,
        height: 400,
        child: ListView.builder(
          itemCount: widget.conversations.length,
          itemBuilder: (context, index) {
            final conv = widget.conversations[index];
            final isChecked = _selected.contains(conv.id);
            final name = conv.displayName(widget.myPhone);

            return CheckboxListTile(
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
              title: Text(
                name,
                style: TextStyle(color: Colors.white.withOpacity(0.85), fontSize: 14),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              activeColor: AppColors.turquoise,
              checkColor: Colors.white,
              controlAffinity: ListTileControlAffinity.leading,
              dense: true,
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text('Отмена', style: TextStyle(color: Colors.white.withOpacity(0.5))),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, _selected),
          child: const Text('Сохранить', style: TextStyle(color: AppColors.turquoise)),
        ),
      ],
    );
  }
}
