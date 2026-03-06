import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:image_picker/image_picker.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/constants/api_constants.dart';
import '../services/messenger_service.dart';

/// Sticker picker panel — shows packs as tabs, stickers in a grid.
/// First tab is always "Favorites" (star icon).
class StickerPicker extends StatefulWidget {
  final Function(String stickerUrl) onStickerSelected;

  const StickerPicker({super.key, required this.onStickerSelected});

  @override
  State<StickerPicker> createState() => _StickerPickerState();
}

class _StickerPickerState extends State<StickerPicker> {
  List<Map<String, dynamic>> _packs = [];
  // index 0 = favorites, index 1+ = server packs
  int _selectedTabIndex = 0;
  bool _isLoading = true;

  // Cache: packId → list of sticker URLs
  final Map<String, List<String>> _stickerCache = {};

  // Favorites
  List<String> _favorites = [];
  bool _isUploading = false;

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  Future<void> _loadAll() async {
    final results = await Future.wait([
      MessengerService.getStickerPacks(),
      MessengerService.getFavoriteStickers(),
    ]);
    if (mounted) {
      final packs = results[0] as List<Map<String, dynamic>>;
      final favs = results[1] as List<String>;
      setState(() {
        _packs = packs;
        _favorites = favs;
        _isLoading = false;
      });
      // Pre-load first server pack stickers
      if (packs.isNotEmpty) {
        _loadPackStickers(0);
      }
    }
  }

  Future<void> _loadPackStickers(int packIndex) async {
    if (packIndex >= _packs.length) return;
    final pack = _packs[packIndex];
    final packId = pack['id'] as String;

    if (_stickerCache.containsKey(packId)) return;

    if (pack['sticker_urls'] is List) {
      final urls = (pack['sticker_urls'] as List).cast<String>();
      _stickerCache[packId] = urls;
      if (mounted) setState(() {});
      return;
    }

    final detail = await MessengerService.getStickerPack(packId);
    if (detail != null && detail['sticker_urls'] is List && mounted) {
      final urls = (detail['sticker_urls'] as List).cast<String>();
      _stickerCache[packId] = urls;
      setState(() {});
    }
  }

  String _resolveUrl(String url) {
    if (url.startsWith('http')) return url;
    return '${ApiConstants.serverUrl}$url';
  }

  /// Add sticker to favorites (called from chat long-press)
  Future<bool> addToFavorites(String stickerUrl) async {
    final success = await MessengerService.addFavoriteSticker(stickerUrl);
    if (success && mounted) {
      setState(() {
        if (!_favorites.contains(stickerUrl)) {
          _favorites.insert(0, stickerUrl);
        }
      });
    }
    return success;
  }

  Future<void> _removeFromFavorites(String stickerUrl) async {
    final success = await MessengerService.removeFavoriteSticker(stickerUrl);
    if (success && mounted) {
      setState(() => _favorites.remove(stickerUrl));
    }
  }

  Future<void> _pickAndUploadSticker() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery);
    if (picked == null || !mounted) return;

    setState(() => _isUploading = true);
    final stickerUrl = await MessengerService.uploadCustomSticker(File(picked.path));
    if (!mounted) return;

    setState(() => _isUploading = false);

    if (stickerUrl != null) {
      setState(() {
        if (!_favorites.contains(stickerUrl)) {
          _favorites.insert(0, stickerUrl);
        }
      });
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Не удалось загрузить стикер'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Container(
        height: 280,
        color: AppColors.night,
        child: const Center(
          child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.turquoise),
        ),
      );
    }

    // Total tabs = 1 (favorites) + packs.length
    final totalTabs = 1 + _packs.length;

    // Current stickers to show
    List<String> currentStickers;
    bool isFavoritesTab = _selectedTabIndex == 0;
    if (isFavoritesTab) {
      currentStickers = _favorites;
    } else {
      final packIndex = _selectedTabIndex - 1;
      final packId = _packs[packIndex]['id'] as String;
      currentStickers = _stickerCache[packId] ?? [];
    }

    return Container(
      height: 280,
      color: AppColors.night,
      child: Column(
        children: [
          // Tab bar
          Container(
            height: 48,
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: Colors.white.withOpacity(0.08))),
            ),
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: totalTabs,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              itemBuilder: (context, index) {
                final isSelected = index == _selectedTabIndex;

                // Favorites tab (index 0)
                if (index == 0) {
                  return GestureDetector(
                    onTap: () => setState(() => _selectedTabIndex = 0),
                    child: Container(
                      width: 44,
                      height: 44,
                      margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(10),
                        color: isSelected
                            ? AppColors.turquoise.withOpacity(0.2)
                            : Colors.white.withOpacity(0.05),
                        border: isSelected
                            ? Border.all(color: AppColors.turquoise, width: 1.5)
                            : null,
                      ),
                      child: Icon(
                        Icons.star_rounded,
                        size: 24,
                        color: isSelected ? AppColors.gold : Colors.white.withOpacity(0.4),
                      ),
                    ),
                  );
                }

                // Pack tabs (index 1+)
                final packIndex = index - 1;
                final pack = _packs[packIndex];
                final thumbUrl = pack['thumbnail_url'] as String?;

                return GestureDetector(
                  onTap: () {
                    setState(() => _selectedTabIndex = index);
                    _loadPackStickers(packIndex);
                  },
                  child: Container(
                    width: 44,
                    height: 44,
                    margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      color: isSelected
                          ? AppColors.turquoise.withOpacity(0.2)
                          : Colors.white.withOpacity(0.05),
                      border: isSelected
                          ? Border.all(color: AppColors.turquoise, width: 1.5)
                          : null,
                    ),
                    child: thumbUrl != null
                        ? ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: CachedNetworkImage(
                              imageUrl: _resolveUrl(thumbUrl),
                              fit: BoxFit.cover,
                              width: 40,
                              height: 40,
                              placeholder: (_, __) => Icon(
                                Icons.emoji_emotions,
                                size: 20,
                                color: Colors.white.withOpacity(0.3),
                              ),
                              errorWidget: (_, __, ___) => Icon(
                                Icons.emoji_emotions,
                                size: 20,
                                color: Colors.white.withOpacity(0.3),
                              ),
                            ),
                          )
                        : Center(
                            child: Text(
                              pack['name']?.toString().substring(0, 1) ?? '?',
                              style: TextStyle(
                                fontSize: 18,
                                color: isSelected ? AppColors.turquoise : Colors.white.withOpacity(0.5),
                              ),
                            ),
                          ),
                  ),
                );
              },
            ),
          ),

          // Stickers grid
          Expanded(
            child: _buildStickerGrid(currentStickers, isFavoritesTab),
          ),
        ],
      ),
    );
  }

  Widget _buildStickerGrid(List<String> stickers, bool isFavoritesTab) {
    // Loading state for pack stickers (not favorites)
    if (!isFavoritesTab && stickers.isEmpty) {
      return Center(
        child: CircularProgressIndicator(
          strokeWidth: 2,
          color: AppColors.turquoise.withOpacity(0.5),
        ),
      );
    }

    // Favorites tab: first cell is always "+" button
    if (isFavoritesTab) {
      final totalItems = 1 + stickers.length; // +1 for "+" button
      return GridView.builder(
        padding: const EdgeInsets.all(8),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 4,
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
        ),
        itemCount: totalItems,
        itemBuilder: (context, index) {
          // First cell — "+" add button
          if (index == 0) {
            return GestureDetector(
              onTap: _isUploading ? null : _pickAndUploadSticker,
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.06),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: AppColors.turquoise.withOpacity(0.3),
                    width: 1.5,
                  ),
                ),
                child: _isUploading
                    ? const Center(
                        child: SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.turquoise),
                        ),
                      )
                    : Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.add_photo_alternate_outlined, size: 28, color: AppColors.turquoise.withOpacity(0.7)),
                          const SizedBox(height: 2),
                          Text(
                            'Свой',
                            style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 10),
                          ),
                        ],
                      ),
              ),
            );
          }

          // Regular sticker cells (shifted by 1)
          final stickerIndex = index - 1;
          final stickerUrl = _resolveUrl(stickers[stickerIndex]);
          return GestureDetector(
            onTap: () => widget.onStickerSelected(stickerUrl),
            onLongPress: () => _showRemoveDialog(stickers[stickerIndex]),
            child: CachedNetworkImage(
              imageUrl: stickerUrl,
              fit: BoxFit.contain,
              placeholder: (_, __) => Container(
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.04),
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              errorWidget: (_, __, ___) => Icon(
                Icons.broken_image,
                size: 32,
                color: Colors.white.withOpacity(0.2),
              ),
            ),
          );
        },
      );
    }

    // Non-favorites tab — regular grid
    return GridView.builder(
      padding: const EdgeInsets.all(8),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 4,
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
      ),
      itemCount: stickers.length,
      itemBuilder: (context, index) {
        final stickerUrl = _resolveUrl(stickers[index]);
        return GestureDetector(
          onTap: () => widget.onStickerSelected(stickerUrl),
          child: CachedNetworkImage(
            imageUrl: stickerUrl,
            fit: BoxFit.contain,
            placeholder: (_, __) => Container(
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.04),
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            errorWidget: (_, __, ___) => Icon(
              Icons.broken_image,
              size: 32,
              color: Colors.white.withOpacity(0.2),
            ),
          ),
        );
      },
    );
  }

  void _showRemoveDialog(String stickerUrl) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.emeraldDark,
        title: const Text('Убрать из избранного?', style: TextStyle(color: Colors.white, fontSize: 16)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Отмена', style: TextStyle(color: Colors.white54)),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _removeFromFavorites(stickerUrl);
            },
            child: const Text('Убрать', style: TextStyle(color: AppColors.gold)),
          ),
        ],
      ),
    );
  }
}
