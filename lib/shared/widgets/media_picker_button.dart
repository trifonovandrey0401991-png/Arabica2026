import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../../core/services/media_upload_service.dart';

/// Кнопка для выбора и загрузки медиа (фото/видео)
class MediaPickerButton extends StatelessWidget {
  final Function(String mediaUrl, bool isVideo) onMediaSelected;
  final bool isLoading;

  const MediaPickerButton({
    super.key,
    required this.onMediaSelected,
    this.isLoading = false,
  });

  Future<void> _showMediaPicker(BuildContext context) async {
    final result = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera, color: Color(0xFF004D40)),
              title: const Text('Сделать фото'),
              onTap: () => Navigator.pop(context, {'source': ImageSource.camera, 'type': 'image'}),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library, color: Color(0xFF004D40)),
              title: const Text('Выбрать фото из галереи'),
              onTap: () => Navigator.pop(context, {'source': ImageSource.gallery, 'type': 'image'}),
            ),
            ListTile(
              leading: const Icon(Icons.videocam, color: Color(0xFF004D40)),
              title: const Text('Записать видео'),
              onTap: () => Navigator.pop(context, {'source': ImageSource.camera, 'type': 'video'}),
            ),
            ListTile(
              leading: const Icon(Icons.video_library, color: Color(0xFF004D40)),
              title: const Text('Выбрать видео из галереи'),
              onTap: () => Navigator.pop(context, {'source': ImageSource.gallery, 'type': 'video'}),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );

    if (result == null) return;

    final picker = ImagePicker();
    XFile? file;
    bool isVideo = result['type'] == 'video';

    if (isVideo) {
      file = await picker.pickVideo(
        source: result['source'] as ImageSource,
        maxDuration: const Duration(minutes: 2),
      );
    } else {
      file = await picker.pickImage(
        source: result['source'] as ImageSource,
        imageQuality: 80,
        maxWidth: 1920,
        maxHeight: 1920,
      );
    }

    if (file == null) return;

    // Показываем индикатор загрузки
    if (context.mounted) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          content: Row(
            children: [
              const CircularProgressIndicator(),
              const SizedBox(width: 16),
              Expanded(
                child: Text(isVideo ? 'Загрузка видео...' : 'Загрузка фото...'),
              ),
            ],
          ),
        ),
      );
    }

    // Загружаем на сервер
    final mediaUrl = await MediaUploadService.uploadMedia(
      file.path,
      type: isVideo ? MediaType.video : MediaType.image,
    );

    // Закрываем диалог загрузки
    if (context.mounted) {
      Navigator.of(context).pop();
    }

    if (mediaUrl != null) {
      onMediaSelected(mediaUrl, isVideo);
    } else {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка загрузки ${isVideo ? "видео" : "фото"}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: isLoading ? null : () => _showMediaPicker(context),
      icon: isLoading
          ? const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.attach_file, color: Color(0xFF004D40)),
      tooltip: 'Прикрепить фото/видео',
    );
  }
}

/// Виджет для отображения медиа в сообщении
class MediaMessageWidget extends StatelessWidget {
  final String? imageUrl;
  final String? videoUrl;
  final double maxWidth;

  const MediaMessageWidget({
    super.key,
    this.imageUrl,
    this.videoUrl,
    this.maxWidth = 250,
  });

  @override
  Widget build(BuildContext context) {
    final url = videoUrl ?? imageUrl;
    if (url == null) return const SizedBox.shrink();

    final isVideo = MediaUploadService.isVideo(url) || videoUrl != null;

    return GestureDetector(
      onTap: () => _showFullScreen(context, url, isVideo),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Stack(
          alignment: Alignment.center,
          children: [
            if (isVideo)
              Container(
                width: maxWidth,
                height: 150,
                color: Colors.black87,
                child: const Center(
                  child: Icon(Icons.play_circle_outline, color: Colors.white, size: 48),
                ),
              )
            else
              Image.network(
                url,
                width: maxWidth,
                fit: BoxFit.cover,
                loadingBuilder: (context, child, loadingProgress) {
                  if (loadingProgress == null) return child;
                  return Container(
                    width: maxWidth,
                    height: 150,
                    color: Colors.grey[300],
                    child: const Center(child: CircularProgressIndicator()),
                  );
                },
                errorBuilder: (context, error, stackTrace) => Container(
                  width: maxWidth,
                  height: 100,
                  color: Colors.grey[300],
                  child: const Icon(Icons.broken_image, color: Colors.grey),
                ),
              ),
            if (isVideo)
              const Positioned(
                bottom: 8,
                right: 8,
                child: Icon(Icons.videocam, color: Colors.white, size: 20),
              ),
          ],
        ),
      ),
    );
  }

  void _showFullScreen(BuildContext context, String url, bool isVideo) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(
            backgroundColor: Colors.black,
            iconTheme: const IconThemeData(color: Colors.white),
          ),
          body: Center(
            child: isVideo
                ? Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.videocam, color: Colors.white, size: 64),
                      const SizedBox(height: 16),
                      const Text(
                        'Воспроизведение видео',
                        style: TextStyle(color: Colors.white),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        url,
                        style: const TextStyle(color: Colors.grey, fontSize: 12),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  )
                : InteractiveViewer(
                    child: Image.network(
                      url,
                      fit: BoxFit.contain,
                      errorBuilder: (context, error, stackTrace) =>
                          const Icon(Icons.broken_image, color: Colors.white, size: 64),
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}
