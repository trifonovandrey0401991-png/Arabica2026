import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../core/theme/app_colors.dart';
import '../services/messenger_service.dart';

/// GIF picker panel — search field + trending grid.
class GifPicker extends StatefulWidget {
  final Function(String gifUrl) onGifSelected;

  const GifPicker({super.key, required this.onGifSelected});

  @override
  State<GifPicker> createState() => _GifPickerState();
}

class _GifPickerState extends State<GifPicker> {
  final _searchController = TextEditingController();
  List<Map<String, dynamic>> _gifs = [];
  bool _isLoading = true;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _loadTrending();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _loadTrending() async {
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
        setState(() => _isLoading = true);
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

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 320,
      color: AppColors.night,
      child: Column(
        children: [
          // Search field
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: Colors.white.withOpacity(0.08))),
            ),
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

          // GIF grid
          Expanded(
            child: _isLoading
                ? Center(
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppColors.turquoise.withOpacity(0.5),
                    ),
                  )
                : _gifs.isEmpty
                    ? Center(
                        child: Text(
                          'Ничего не найдено',
                          style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 14),
                        ),
                      )
                    : GridView.builder(
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

                          return GestureDetector(
                            onTap: () {
                              final url = gif['url'] as String? ?? '';
                              if (url.isNotEmpty) {
                                widget.onGifSelected(url);
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
                      ),
          ),

          // Powered by Tenor
          Container(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(
              'Powered by Tenor',
              style: TextStyle(fontSize: 10, color: Colors.white.withOpacity(0.2)),
            ),
          ),
        ],
      ),
    );
  }
}
