import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../../core/services/media_upload_service.dart';
import 'app_cached_image.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

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
              leading: Icon(Icons.photo_camera, color: Color(0xFF004D40)),
              title: Text('Сделать фото'),
              onTap: () => Navigator.pop(context, {'source': ImageSource.camera, 'type': 'image'}),
            ),
            ListTile(
              leading: Icon(Icons.photo_library, color: Color(0xFF004D40)),
              title: Text('Выбрать фото из галереи'),
              onTap: () => Navigator.pop(context, {'source': ImageSource.gallery, 'type': 'image'}),
            ),
            ListTile(
              leading: Icon(Icons.videocam, color: Color(0xFF004D40)),
              title: Text('Записать видео'),
              onTap: () => Navigator.pop(context, {'source': ImageSource.camera, 'type': 'video'}),
            ),
            ListTile(
              leading: Icon(Icons.video_library, color: Color(0xFF004D40)),
              title: Text('Выбрать видео из галереи'),
              onTap: () => Navigator.pop(context, {'source': ImageSource.gallery, 'type': 'video'}),
            ),
            SizedBox(height: 8),
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
        maxDuration: Duration(minutes: 2),
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
              CircularProgressIndicator(),
              SizedBox(width: 16),
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
          ? SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Icon(Icons.attach_file, color: Color(0xFF004D40)),
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
    if (url == null) return SizedBox.shrink();

    final isVideo = MediaUploadService.isVideo(url) || videoUrl != null;

    return GestureDetector(
      onTap: () => _showFullScreen(context, url, isVideo),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8.r),
        child: Stack(
          alignment: Alignment.center,
          children: [
            if (isVideo)
              Container(
                width: maxWidth,
                height: 150,
                color: Colors.black87,
                child: Center(
                  child: Icon(Icons.play_circle_outline, color: Colors.white, size: 48),
                ),
              )
            else
              AppCachedImage(
                imageUrl: url,
                width: maxWidth,
                fit: BoxFit.cover,
                errorWidget: (context, error, stackTrace) => Container(
                  width: maxWidth,
                  height: 100,
                  color: Colors.grey[300],
                  child: Icon(Icons.broken_image, color: Colors.grey),
                ),
              ),
            if (isVideo)
              Positioned(
                bottom: 8.h,
                right: 8.w,
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
            iconTheme: IconThemeData(color: Colors.white),
          ),
          body: Center(
            child: isVideo
                ? Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.videocam, color: Colors.white, size: 64),
                      SizedBox(height: 16),
                      Text(
                        'Воспроизведение видео',
                        style: TextStyle(color: Colors.white),
                      ),
                      SizedBox(height: 8),
                      Text(
                        url,
                        style: TextStyle(color: Colors.grey, fontSize: 12.sp),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  )
                : InteractiveViewer(
                    child: AppCachedImage(
                      imageUrl: url,
                      fit: BoxFit.contain,
                      errorWidget: (context, error, stackTrace) =>
                          Icon(Icons.broken_image, color: Colors.white, size: 64),
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}
