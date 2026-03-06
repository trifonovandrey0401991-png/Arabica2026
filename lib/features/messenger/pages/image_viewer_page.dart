import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../core/theme/app_colors.dart';

/// Fullscreen image viewer with pinch-to-zoom and swipe-to-dismiss.
class ImageViewerPage extends StatelessWidget {
  final String imageUrl;
  final String? senderName;

  const ImageViewerPage({
    super.key,
    required this.imageUrl,
    this.senderName,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.black.withOpacity(0.5),
        elevation: 0,
        foregroundColor: Colors.white,
        systemOverlayStyle: SystemUiOverlayStyle.light,
        title: senderName != null
            ? Text(senderName!,
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500))
            : null,
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Center(
        child: InteractiveViewer(
          minScale: 0.5,
          maxScale: 4.0,
          child: CachedNetworkImage(
            imageUrl: imageUrl,
            fit: BoxFit.contain,
            width: double.infinity,
            height: double.infinity,
            placeholder: (_, __) => const Center(
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                color: AppColors.turquoise,
              ),
            ),
            errorWidget: (_, __, ___) => Icon(
              Icons.broken_image,
              size: 64,
              color: Colors.white.withOpacity(0.3),
            ),
          ),
        ),
      ),
    );
  }
}
