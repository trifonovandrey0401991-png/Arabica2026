import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../../shared/widgets/app_cached_image.dart';
import '../../../core/constants/api_constants.dart';

/// Карусель фото товара (PageView с индикатором)
class PhotoCarousel extends StatefulWidget {
  final List<String> photos;
  final double height;
  final BorderRadius? borderRadius;

  const PhotoCarousel({
    super.key,
    required this.photos,
    this.height = 200,
    this.borderRadius,
  });

  @override
  State<PhotoCarousel> createState() => _PhotoCarouselState();
}

class _PhotoCarouselState extends State<PhotoCarousel> {
  int _currentPage = 0;

  String _resolveUrl(String url) {
    if (url.startsWith('http')) return url;
    return '${ApiConstants.serverUrl}$url';
  }

  @override
  Widget build(BuildContext context) {
    if (widget.photos.isEmpty) {
      return Container(
        height: widget.height,
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.05),
          borderRadius: widget.borderRadius ?? BorderRadius.circular(12.r),
        ),
        child: Center(
          child: Icon(Icons.image_not_supported_rounded, color: Colors.white.withOpacity(0.2), size: 48),
        ),
      );
    }

    return SizedBox(
      height: widget.height,
      child: Stack(
        children: [
          ClipRRect(
            borderRadius: widget.borderRadius ?? BorderRadius.circular(12.r),
            child: PageView.builder(
              itemCount: widget.photos.length,
              onPageChanged: (i) { if (mounted) setState(() => _currentPage = i); },
              itemBuilder: (ctx, i) => AppCachedImage(
                imageUrl: _resolveUrl(widget.photos[i]),
                width: double.infinity,
                height: widget.height,
                fit: BoxFit.cover,
              ),
            ),
          ),
          // Dots indicator
          if (widget.photos.length > 1)
            Positioned(
              bottom: 8,
              left: 0,
              right: 0,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(widget.photos.length, (i) => Container(
                  margin: EdgeInsets.symmetric(horizontal: 3),
                  width: _currentPage == i ? 10 : 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: _currentPage == i ? Colors.white : Colors.white.withOpacity(0.4),
                    borderRadius: BorderRadius.circular(3),
                  ),
                )),
              ),
            ),
        ],
      ),
    );
  }
}
