import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:image_picker/image_picker.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/constants/api_constants.dart';
import '../services/messenger_service.dart';

/// GIF picker panel — favorites tab + search/trending.
/// Tab 0 = Favorites (star icon), Tab 1 = Trending (flame), Tab 2 = Search.
class GifPicker extends StatefulWidget {
  final Function(String gifUrl) onGifSelected;

  const GifPicker({super.key, required this.onGifSelected});

  @override
  State<GifPicker> createState() => GifPickerState();
}

class GifPickerState extends State<GifPicker> {
  final _searchController = TextEditingController();
  List<Map<String, dynamic>> _gifs = [];
  List<String> _favorites = [];
  bool _isLoading = true;
  bool _isUploading = false;
  int _selectedTab = 0; // 0=favorites, 1=trending, 2=search
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _loadInitial();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _loadInitial() async {
    final results = await Future.wait([
      MessengerService.getFavoriteGifs(),
      MessengerService.getTrendingGifs(),
    ]);
    if (mounted) {
      setState(() {
        _favorites = results[0] as List<String>;
        _gifs = results[1] as List<Map<String, dynamic>>;
        _isLoading = false;
      });
    }
  }

  Future<void> _loadTrending() async {
    setState(() => _isLoading = true);
    final gifs = await MessengerService.getTrendingGifs();
    if (mounted) {
      setState(() {
        _gifs = gifs;
        _isLoading = false;
      });
    }
  }

  void _onSearchChanged(String query) {
    _debounce?.cancel();
    if (query.trim().isEmpty) {
      _debounce = Timer(const Duration(milliseconds: 300), () {
        if (!mounted) return;
        _loadTrending();
      });
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 500), () async {
      if (!mounted) return;
      setState(() => _isLoading = true);
      final gifs = await MessengerService.searchGifs(query.trim());
      if (mounted) {
        setState(() {
          _gifs = gifs;
          _isLoading = false;
        });
      }
    });
  }

  /// Add GIF to favorites (called from chat long-press)
  Future<bool> addToFavorites(String gifUrl) async {
    final success = await MessengerService.addFavoriteGif(gifUrl);
    if (success && mounted) {
      setState(() {
        if (!_favorites.contains(gifUrl)) {
          _favorites.insert(0, gifUrl);
        }
      });
    }
    return success;
  }

  Future<void> _removeFromFavorites(String gifUrl) async {
    final success = await MessengerService.removeFavoriteGif(gifUrl);
    if (success && mounted) {
      setState(() => _favorites.remove(gifUrl));
    }
  }

  Future<void> _pickAndUploadGif() async {
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
          content: Text('Не удалось загрузить GIF'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  String _resolveUrl(String url) {
    if (url.startsWith('http')) return url;
    return '${ApiConstants.serverUrl}$url';
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading && _selectedTab == 0 && _favorites.isEmpty && _gifs.isEmpty) {
      return Container(
        height: 320,
        color: AppColors.night,
        child: const Center(
          child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.turquoise),
        ),
      );
    }

    return Container(
      height: 320,
      color: AppColors.night,
      child: Column(
        children: [
          // Tab bar
          Container(
            height: 48,
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: Colors.white.withOpacity(0.08))),
            ),
            child: Row(
              children: [
                const SizedBox(width: 8),
                _buildTab(0, Icons.star_rounded, null),
                _buildTab(1, Icons.local_fire_department_rounded, null),
                _buildTab(2, Icons.search_rounded, null),
                const Spacer(),
                // Powered by GIPHY
                Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: Text(
                    'GIPHY',
                    style: TextStyle(fontSize: 10, color: Colors.white.withOpacity(0.2)),
                  ),
                ),
              ],
            ),
          ),

          // Search field (only for search tab)
          if (_selectedTab == 2)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: TextField(
                controller: _searchController,
                onChanged: _onSearchChanged,
                style: TextStyle(color: Colors.white.withOpacity(0.9), fontSize: 14),
                decoration: InputDecoration(
                  hintText: 'Поиск GIF...',
                  hintStyle: TextStyle(color: Colors.white.withOpacity(0.3)),
                  prefixIcon: Icon(Icons.search, size: 20, color: Colors.white.withOpacity(0.4)),
                  filled: true,
                  fillColor: Colors.white.withOpacity(0.06),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(20),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  isDense: true,
                ),
              ),
            ),

          // Content
          Expanded(child: _buildContent()),
        ],
      ),
    );
  }

  Widget _buildTab(int index, IconData icon, String? label) {
    final isSelected = _selectedTab == index;
    return GestureDetector(
      onTap: () {
        setState(() => _selectedTab = index);
        if (index == 1 && _gifs.isEmpty) _loadTrending();
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
        child: Icon(
          icon,
          size: 24,
          color: isSelected
              ? (index == 0 ? AppColors.gold : AppColors.turquoise)
              : Colors.white.withOpacity(0.4),
        ),
      ),
    );
  }

  Widget _buildContent() {
    if (_selectedTab == 0) return _buildFavoritesGrid();
    // Tabs 1 and 2 show the same _gifs list (trending or search results)
    return _buildGifsGrid();
  }

  Widget _buildFavoritesGrid() {
    final totalItems = 1 + _favorites.length; // +1 for "+" button
    return GridView.builder(
      padding: const EdgeInsets.all(8),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: 4,
        crossAxisSpacing: 4,
      ),
      itemCount: totalItems,
      itemBuilder: (context, index) {
        // First cell — "+" upload button
        if (index == 0) {
          return GestureDetector(
            onTap: _isUploading ? null : _pickAndUploadGif,
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

        // Regular favorite GIF cells
        final gifIndex = index - 1;
        final gifUrl = _resolveUrl(_favorites[gifIndex]);
        return GestureDetector(
          onTap: () => widget.onGifSelected(gifUrl),
          onLongPress: () => _showRemoveDialog(_favorites[gifIndex]),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: CachedNetworkImage(
              imageUrl: gifUrl,
              fit: BoxFit.cover,
              placeholder: (_, __) => Container(
                color: Colors.white.withOpacity(0.04),
              ),
              errorWidget: (_, __, ___) => Container(
                color: Colors.white.withOpacity(0.04),
                child: Icon(Icons.gif, size: 32, color: Colors.white.withOpacity(0.2)),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildGifsGrid() {
    if (_isLoading) {
      return Center(
        child: CircularProgressIndicator(
          strokeWidth: 2,
          color: AppColors.turquoise.withOpacity(0.5),
        ),
      );
    }

    if (_gifs.isEmpty) {
      return Center(
        child: Text(
          'Ничего не найдено',
          style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 14),
        ),
      );
    }

    return GridView.builder(
      padding: const EdgeInsets.all(8),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: 4,
        crossAxisSpacing: 4,
      ),
      itemCount: _gifs.length,
      itemBuilder: (context, index) {
        final gif = _gifs[index];
        final previewUrl = gif['preview'] as String? ?? gif['url'] as String? ?? '';
        final fullUrl = gif['url'] as String? ?? '';

        return GestureDetector(
          onTap: () {
            if (fullUrl.isNotEmpty) {
              widget.onGifSelected(fullUrl);
            }
          },
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: previewUrl.isNotEmpty
                ? CachedNetworkImage(
                    imageUrl: previewUrl,
                    fit: BoxFit.cover,
                    placeholder: (_, __) => Container(
                      color: Colors.white.withOpacity(0.04),
                    ),
                    errorWidget: (_, __, ___) => Container(
                      color: Colors.white.withOpacity(0.04),
                      child: Icon(Icons.gif, size: 32, color: Colors.white.withOpacity(0.2)),
                    ),
                  )
                : Container(
                    color: Colors.white.withOpacity(0.04),
                    child: Icon(Icons.gif, size: 32, color: Colors.white.withOpacity(0.2)),
                  ),
          ),
        );
      },
    );
  }

  void _showRemoveDialog(String gifUrl) {
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
              _removeFromFavorites(gifUrl);
            },
            child: const Text('Убрать', style: TextStyle(color: AppColors.gold)),
          ),
        ],
      ),
    );
  }
}
