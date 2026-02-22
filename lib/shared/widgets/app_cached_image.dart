import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../core/constants/api_constants.dart';

/// Обёртка над CachedNetworkImage с API, похожим на Image.network.
/// Кэширует загруженные изображения — при повторном показе берёт из кэша.
/// Автоматически добавляет Authorization header если есть sessionToken.
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
  final Map<String, String>? httpHeaders;

  const AppCachedImage({
    super.key,
    required this.imageUrl,
    this.fit,
    this.width,
    this.height,
    this.errorWidget,
    this.placeholder,
    this.httpHeaders,
  });

  @override
  Widget build(BuildContext context) {
    // memCacheWidth ограничивает размер декодированного изображения в памяти
    // Без этого Flutter декодирует 1080x2424 (10 МБ RAM) для показа в 220x220
    final int? memCacheWidth = (width != null && width!.isFinite)
        ? (width! * MediaQuery.of(context).devicePixelRatio).toInt()
        : null;

    // Авто-добавление Authorization header для запросов к нашему серверу
    final headers = httpHeaders ?? <String, String>{};
    if (!headers.containsKey('Authorization') &&
        ApiConstants.sessionToken != null &&
        ApiConstants.sessionToken!.isNotEmpty) {
      headers['Authorization'] = 'Bearer ${ApiConstants.sessionToken}';
    }

    return CachedNetworkImage(
      imageUrl: imageUrl,
      fit: fit,
      width: width,
      height: height,
      memCacheWidth: memCacheWidth,
      httpHeaders: headers.isNotEmpty ? headers : null,
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
