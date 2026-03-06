import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;
import '../../../core/theme/app_colors.dart';
import '../../../core/constants/api_constants.dart';
import '../services/messenger_service.dart';
import 'image_viewer_page.dart';
import 'video_player_page.dart';
import 'conversation_picker_page.dart';

/// Full-screen media gallery — grid of photos and videos from a conversation.
/// Newest items first. Long-press for actions. Multi-select mode.
class MediaGalleryPage extends StatefulWidget {
  final String conversationId;
  final String title;
  final String userPhone;

  const MediaGalleryPage({
    super.key,
    required this.conversationId,
    required this.title,
    required this.userPhone,
  });

  @override
  State<MediaGalleryPage> createState() => _MediaGalleryPageState();
}

class _MediaGalleryPageState extends State<MediaGalleryPage> {
  final List<Map<String, dynamic>> _media = [];
  bool _isLoading = true;
  bool _isLoadingMore = false;
  bool _hasMore = true;
  final ScrollController _scrollController = ScrollController();

  // Selection mode
  bool _selectionMode = false;
  final Set<String> _selectedIds = {};

  @override
  void initState() {
    super.initState();
    _loadMedia();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels > _scrollController.position.maxScrollExtent - 300) {
      _loadMoreMedia();
    }
  }

  Future<void> _loadMedia() async {
    final media = await MessengerService.getConversationMedia(
      widget.conversationId,
      limit: 60,
    );
    if (!mounted) return;
    setState(() {
      _media.addAll(media);
      _isLoading = false;
      _hasMore = media.length >= 60;
    });
  }

  Future<void> _loadMoreMedia() async {
    if (_isLoadingMore || !_hasMore) return;
    setState(() => _isLoadingMore = true);
    final media = await MessengerService.getConversationMedia(
      widget.conversationId,
      limit: 60,
      offset: _media.length,
    );
    if (!mounted) return;
    setState(() {
      _media.addAll(media);
      _isLoadingMore = false;
      _hasMore = media.length >= 60;
    });
  }

  String _fullUrl(String mediaUrl) {
    return mediaUrl.startsWith('http')
        ? mediaUrl
        : '${ApiConstants.serverUrl}$mediaUrl';
  }

  void _openMedia(Map<String, dynamic> item) {
    final type = item['type'] as String? ?? '';
    final mediaUrl = item['media_url'] as String? ?? '';
    final senderName = item['sender_name'] as String?;
    final fullUrl = _fullUrl(mediaUrl);

    if (type == 'image') {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ImageViewerPage(imageUrl: fullUrl, senderName: senderName),
        ),
      );
    } else if (type == 'video' || type == 'video_note') {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => VideoPlayerPage(videoUrl: fullUrl),
        ),
      );
    }
  }

  // ==================== LONG PRESS MENU ====================

  void _showItemMenu(Map<String, dynamic> item) {
    final messageId = item['id'] as String? ?? '';

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
            ListTile(
              leading: Icon(Icons.chat_bubble_outline, color: Colors.white.withOpacity(0.7)),
              title: Text('Показать в чате', style: TextStyle(color: Colors.white.withOpacity(0.9))),
              onTap: () {
                Navigator.pop(ctx);
                _showInChat(messageId);
              },
            ),
            ListTile(
              leading: Icon(Icons.forward_outlined, color: Colors.white.withOpacity(0.7)),
              title: Text('Переслать', style: TextStyle(color: Colors.white.withOpacity(0.9))),
              onTap: () {
                Navigator.pop(ctx);
                _forwardItems([messageId]);
              },
            ),
            ListTile(
              leading: Icon(Icons.delete_outline, color: Colors.white.withOpacity(0.7)),
              title: Text('Удалить у меня', style: TextStyle(color: Colors.white.withOpacity(0.9))),
              onTap: () {
                Navigator.pop(ctx);
                _hideItems([messageId]);
              },
            ),
            ListTile(
              leading: Icon(Icons.check_circle_outline, color: Colors.white.withOpacity(0.7)),
              title: Text('Выбрать', style: TextStyle(color: Colors.white.withOpacity(0.9))),
              onTap: () {
                Navigator.pop(ctx);
                _enterSelectionMode(messageId);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  // ==================== ACTIONS ====================

  void _showInChat(String messageId) {
    Navigator.pop(context, {'action': 'showInChat', 'messageId': messageId});
  }

  Future<void> _forwardItems(List<String> messageIds) async {
    final targetIds = await Navigator.push<List<String>>(
      context,
      MaterialPageRoute(
        builder: (_) => ConversationPickerPage(userPhone: widget.userPhone),
      ),
    );
    if (targetIds == null || targetIds.isEmpty) return;

    int successCount = 0;
    for (final msgId in messageIds) {
      final ok = await MessengerService.forwardMessage(msgId, targetIds);
      if (ok) successCount++;
    }

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Переслано: $successCount из ${messageIds.length}'),
        backgroundColor: AppColors.emerald,
      ),
    );
    _exitSelectionMode();
  }

  Future<void> _hideItems(List<String> messageIds) async {
    final ok = await MessengerService.hideMessages(messageIds);
    if (!mounted) return;

    if (ok) {
      setState(() {
        _media.removeWhere((m) => messageIds.contains(m['id']));
        _selectedIds.removeAll(messageIds);
        if (_selectedIds.isEmpty) _selectionMode = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Удалено: ${messageIds.length}'),
          backgroundColor: AppColors.emerald,
        ),
      );
    }
  }

  Future<void> _shareItems(List<String> messageIds) async {
    final items = _media.where((m) => messageIds.contains(m['id'])).toList();
    if (items.isEmpty) return;

    // Show loading
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Подготовка файлов...'), backgroundColor: AppColors.emerald, duration: Duration(seconds: 1)),
    );

    final List<XFile> files = [];
    final dir = await getTemporaryDirectory();

    for (final item in items) {
      final mediaUrl = item['media_url'] as String? ?? '';
      final type = item['type'] as String? ?? '';
      final fullUrl = _fullUrl(mediaUrl);

      try {
        final response = await http.get(Uri.parse(fullUrl));
        if (response.statusCode == 200) {
          final ext = type == 'video' || type == 'video_note' ? '.mp4' : '.jpg';
          final file = File('${dir.path}/share_${DateTime.now().millisecondsSinceEpoch}_${files.length}$ext');
          await file.writeAsBytes(response.bodyBytes);
          files.add(XFile(file.path));
        }
      } catch (_) { /* skip failed downloads */ }
    }

    if (files.isNotEmpty) {
      await SharePlus.instance.share(ShareParams(files: files));
    }

    _exitSelectionMode();
  }

  // ==================== SELECTION MODE ====================

  void _enterSelectionMode(String firstId) {
    setState(() {
      _selectionMode = true;
      _selectedIds.add(firstId);
    });
  }

  void _exitSelectionMode() {
    setState(() {
      _selectionMode = false;
      _selectedIds.clear();
    });
  }

  void _toggleSelection(String id) {
    setState(() {
      if (_selectedIds.contains(id)) {
        _selectedIds.remove(id);
        if (_selectedIds.isEmpty) _selectionMode = false;
      } else {
        _selectedIds.add(id);
      }
    });
  }

  // ==================== BUILD ====================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.night,
      appBar: _selectionMode ? _buildSelectionAppBar() : _buildNormalAppBar(),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.turquoise, strokeWidth: 2.5),
            )
          : _media.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.photo_library_outlined,
                          size: 64, color: Colors.white.withOpacity(0.2)),
                      const SizedBox(height: 12),
                      Text(
                        'Нет медиа файлов',
                        style: TextStyle(color: Colors.white.withOpacity(0.4)),
                      ),
                    ],
                  ),
                )
              : Column(
                  children: [
                    Expanded(
                      child: GridView.builder(
                        controller: _scrollController,
                        padding: const EdgeInsets.all(2),
                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 3,
                          crossAxisSpacing: 2,
                          mainAxisSpacing: 2,
                        ),
                        itemCount: _media.length + (_isLoadingMore ? 1 : 0),
                        itemBuilder: (context, index) {
                          if (index >= _media.length) {
                            return const Center(
                              child: CircularProgressIndicator(
                                  color: AppColors.turquoise, strokeWidth: 2),
                            );
                          }
                          return _buildMediaTile(_media[index]);
                        },
                      ),
                    ),
                    if (_selectionMode) _buildSelectionBottomBar(),
                  ],
                ),
    );
  }

  AppBar _buildNormalAppBar() {
    return AppBar(
      backgroundColor: Colors.transparent,
      elevation: 0,
      foregroundColor: Colors.white,
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.title, style: const TextStyle(fontSize: 16)),
          if (!_isLoading)
            Text(
              '${_media.length} файлов',
              style: TextStyle(fontSize: 12, color: Colors.white.withOpacity(0.4)),
            ),
        ],
      ),
    );
  }

  AppBar _buildSelectionAppBar() {
    return AppBar(
      backgroundColor: AppColors.emerald,
      elevation: 0,
      foregroundColor: Colors.white,
      leading: IconButton(
        icon: const Icon(Icons.close),
        onPressed: _exitSelectionMode,
      ),
      title: Text('Выбрано: ${_selectedIds.length}', style: const TextStyle(fontSize: 16)),
    );
  }

  Widget _buildSelectionBottomBar() {
    return Container(
      color: AppColors.emeraldDark,
      padding: EdgeInsets.only(
        left: 8, right: 8, top: 8,
        bottom: MediaQuery.of(context).padding.bottom + 8,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _bottomBarButton(Icons.delete_outline, 'Удалить', () {
            _hideItems(_selectedIds.toList());
          }),
          _bottomBarButton(Icons.forward_outlined, 'Переслать', () {
            _forwardItems(_selectedIds.toList());
          }),
          _bottomBarButton(Icons.share_outlined, 'Поделиться', () {
            _shareItems(_selectedIds.toList());
          }),
        ],
      ),
    );
  }

  Widget _bottomBarButton(IconData icon, String label, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: AppColors.turquoise, size: 24),
            const SizedBox(height: 4),
            Text(label, style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 12)),
          ],
        ),
      ),
    );
  }

  Widget _buildMediaTile(Map<String, dynamic> item) {
    final type = item['type'] as String? ?? '';
    final mediaUrl = item['media_url'] as String? ?? '';
    final messageId = item['id'] as String? ?? '';
    final isImage = type == 'image';
    final isVideo = type == 'video' || type == 'video_note';
    final fullUrl = _fullUrl(mediaUrl);
    final isSelected = _selectedIds.contains(messageId);

    return GestureDetector(
      onTap: () {
        if (_selectionMode) {
          _toggleSelection(messageId);
        } else {
          _openMedia(item);
        }
      },
      onLongPress: () {
        if (_selectionMode) {
          _toggleSelection(messageId);
        } else {
          _showItemMenu(item);
        }
      },
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (isImage)
            CachedNetworkImage(
              imageUrl: fullUrl,
              fit: BoxFit.cover,
              placeholder: (_, __) => Container(
                color: AppColors.emerald.withOpacity(0.15),
                child: const Center(
                    child: Icon(Icons.image, color: AppColors.turquoise, size: 24)),
              ),
              errorWidget: (_, __, ___) => Container(
                color: AppColors.emerald.withOpacity(0.15),
                child: const Center(
                    child: Icon(Icons.broken_image, color: AppColors.turquoise, size: 24)),
              ),
            )
          else if (isVideo)
            Container(
              color: AppColors.emerald.withOpacity(0.15),
              child: const Center(
                  child: Icon(Icons.videocam, color: AppColors.turquoise, size: 32)),
            )
          else
            Container(
              color: AppColors.emerald.withOpacity(0.15),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.insert_drive_file,
                        color: AppColors.turquoise, size: 28),
                    const SizedBox(height: 4),
                    Text(
                      item['file_name'] as String? ?? 'Файл',
                      style: TextStyle(
                          fontSize: 10, color: Colors.white.withOpacity(0.5)),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ),
          // Video play icon overlay
          if (isVideo)
            Center(
              child: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.5),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.play_arrow, color: Colors.white, size: 22),
              ),
            ),
          // Selection overlay
          if (_selectionMode)
            Positioned.fill(
              child: Container(
                color: isSelected ? AppColors.turquoise.withOpacity(0.3) : Colors.transparent,
              ),
            ),
          if (_selectionMode)
            Positioned(
              top: 4,
              right: 4,
              child: Container(
                width: 24, height: 24,
                decoration: BoxDecoration(
                  color: isSelected ? AppColors.turquoise : Colors.black.withOpacity(0.4),
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white.withOpacity(0.6), width: 1.5),
                ),
                child: isSelected
                    ? const Icon(Icons.check, color: Colors.white, size: 16)
                    : null,
              ),
            ),
        ],
      ),
    );
  }
}
