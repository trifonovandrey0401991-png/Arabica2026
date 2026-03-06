import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';
import 'package:chewie/chewie.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/constants/api_constants.dart';

/// Fullscreen video player for messenger video messages.
/// Uses Chewie (video_player wrapper) with controls, autoplay, and error handling.
class VideoPlayerPage extends StatefulWidget {
  final String videoUrl;
  final String? senderName;

  const VideoPlayerPage({
    super.key,
    required this.videoUrl,
    this.senderName,
  });

  @override
  State<VideoPlayerPage> createState() => _VideoPlayerPageState();
}

class _VideoPlayerPageState extends State<VideoPlayerPage> {
  VideoPlayerController? _videoController;
  ChewieController? _chewieController;
  bool _isLoading = true;
  String? _error;

  String get _resolvedUrl {
    final url = widget.videoUrl;
    if (url.startsWith('http')) return url;
    return '${ApiConstants.serverUrl}$url';
  }

  @override
  void initState() {
    super.initState();
    _initPlayer();
  }

  Future<void> _initPlayer() async {
    try {
      _videoController = VideoPlayerController.networkUrl(
        Uri.parse(_resolvedUrl),
      );

      await _videoController!.initialize();

      _chewieController = ChewieController(
        videoPlayerController: _videoController!,
        autoPlay: true,
        looping: false,
        showControls: true,
        allowFullScreen: false,
        materialProgressColors: ChewieProgressColors(
          playedColor: AppColors.emerald,
          handleColor: AppColors.turquoise,
          bufferedColor: Colors.white24,
          backgroundColor: Colors.white10,
        ),
        errorBuilder: (context, errorMessage) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.error_outline, color: Colors.red.shade300, size: 48),
                const SizedBox(height: 16),
                Text(
                  'Не удалось загрузить видео',
                  style: TextStyle(color: Colors.white.withOpacity(0.7)),
                ),
              ],
            ),
          );
        },
      );

      if (mounted) {
        setState(() => _isLoading = false);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _error = 'Ошибка загрузки видео';
        });
      }
    }
  }

  @override
  void dispose() {
    _chewieController?.dispose();
    _videoController?.dispose();
    super.dispose();
  }

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
        title: widget.senderName != null
            ? Text(
                widget.senderName!,
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
              )
            : null,
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Center(
        child: _isLoading
            ? const CircularProgressIndicator(
                strokeWidth: 2.5,
                color: AppColors.turquoise,
              )
            : _error != null
                ? Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.error_outline, color: Colors.red.shade300, size: 48),
                      const SizedBox(height: 16),
                      Text(
                        _error!,
                        style: TextStyle(color: Colors.white.withOpacity(0.7)),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  )
                : _chewieController != null
                    ? Chewie(controller: _chewieController!)
                    : Text(
                        'Не удалось загрузить видео',
                        style: TextStyle(color: Colors.white.withOpacity(0.7)),
                      ),
      ),
    );
  }
}
