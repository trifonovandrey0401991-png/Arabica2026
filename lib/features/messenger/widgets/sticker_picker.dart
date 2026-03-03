import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/constants/api_constants.dart';
import '../services/messenger_service.dart';

/// Sticker picker panel — shows packs as tabs, stickers in a grid.
class StickerPicker extends StatefulWidget {
  final Function(String stickerUrl) onStickerSelected;

  const StickerPicker({super.key, required this.onStickerSelected});

  @override
  State<StickerPicker> createState() => _StickerPickerState();
}

class _StickerPickerState extends State<StickerPicker> {
  List<Map<String, dynamic>> _packs = [];
  int _selectedPackIndex = 0;
  bool _isLoading = true;

  // Cache: packId → list of sticker URLs
  final Map<String, List<String>> _stickerCache = {};

  @override
  void initState() {
    super.initState();
    _loadPacks();
  }

  Future<void> _loadPacks() async {
    final packs = await MessengerService.getStickerPacks();
    if (mounted) {
      setState(() {
        _packs = packs;
        _isLoading = false;
      });
      if (packs.isNotEmpty) {
        _loadStickers(0);
      }
    }
  }

  Future<void> _loadStickers(int index) async {
    if (index >= _packs.length) return;
    final pack = _packs[index];
    final packId = pack['id'] as String;

    // Already cached?
    if (_stickerCache.containsKey(packId)) return;

    // Check if URLs are embedded in pack data
    if (pack['sticker_urls'] is List) {
      final urls = (pack['sticker_urls'] as List).cast<String>();
      _stickerCache[packId] = urls;
      if (mounted) setState(() {});
      return;
    }

    // Otherwise load from server
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

    if (_packs.isEmpty) {
      return Container(
        height: 280,
        color: AppColors.night,
        child: Center(
          child: Text(
            'Нет стикеров',
            style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 14),
          ),
        ),
      );
    }

    final currentPackId = _packs[_selectedPackIndex]['id'] as String;
    final stickers = _stickerCache[currentPackId] ?? [];

    return Container(
      height: 280,
      color: AppColors.night,
      child: Column(
        children: [
          // Pack tabs
          Container(
            height: 48,
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: Colors.white.withOpacity(0.08))),
            ),
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: _packs.length,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              itemBuilder: (context, index) {
                final pack = _packs[index];
                final isSelected = index == _selectedPackIndex;
                final thumbUrl = pack['thumbnail_url'] as String?;

                return GestureDetector(
                  onTap: () {
                    setState(() => _selectedPackIndex = index);
                    _loadStickers(index);
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
            child: stickers.isEmpty
                ? Center(
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppColors.turquoise.withOpacity(0.5),
                    ),
                  )
                : GridView.builder(
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
                  ),
          ),
        ],
      ),
    );
  }
}
