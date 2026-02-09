import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';

/// Обёртка над CachedNetworkImage с API, похожим на Image.network.
/// Кэширует загруженные изображения — при повторном показе берёт из кэша.
///
/// Использование:
/// ```dart
/// AppCachedImage(
///   imageUrl: 'https://example.com/photo.jpg',
///   fit: BoxFit.cover,
///   width: 200,
///   height: 200,
/// )
/// ```
class AppCachedImage extends StatelessWidget {
  final String imageUrl;
  final BoxFit? fit;
  final double? width;
  final double? height;
  final Widget Function(BuildContext, String, dynamic)? errorWidget;
  final Widget Function(BuildContext, String)? placeholder;

  const AppCachedImage({
    super.key,
    required this.imageUrl,
    this.fit,
    this.width,
    this.height,
    this.errorWidget,
    this.placeholder,
  });

  @override
  Widget build(BuildContext context) {
    return CachedNetworkImage(
      imageUrl: imageUrl,
      fit: fit,
      width: width,
      height: height,
      placeholder: placeholder ??
          (context, url) => const Center(
                child: SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
      errorWidget: errorWidget ??
          (context, url, error) => const Icon(
                Icons.broken_image,
                color: Colors.grey,
              ),
    );
  }
}
