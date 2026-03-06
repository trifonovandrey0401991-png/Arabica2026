import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';
import 'package:chewie/chewie.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;
import 'dart:io';
import '../../../core/theme/app_colors.dart';
import '../../../core/constants/api_constants.dart';

/// Fullscreen video player for messenger video messages.
/// Uses Chewie (video_player wrapper) with controls, autoplay, and error handling.
class VideoPlayerPage extends StatefulWidget {
  final String videoUrl;
  final String? senderName;
  /// Optional list of video URLs for swipe navigation
  final List<String>? videoUrls;
  /// Starting index in videoUrls
  final int initialIndex;

  const VideoPlayerPage({
    super.key,
    required this.videoUrl,
    this.senderName,
    this.videoUrls,
    this.initialIndex = 0,
  });

  @override
  State<VideoPlayerPage> createState() => _VideoPlayerPageState();
}

class _VideoPlayerPageState extends State<VideoPlayerPage> {
  VideoPlayerController? _videoController;
  ChewieController? _chewieController;
  bool _isLoading = true;
  String? _error;
  late int _currentIndex;
  late List<String> _urls;

  String get _resolvedUrl {
    final url = _urls[_currentIndex];
    if (url.startsWith('http')) return url;
    return '${ApiConstants.serverUrl}$url';
  }

  @override
  void initState() {
    super.initState();
    _urls = widget.videoUrls ?? [widget.videoUrl];
    _currentIndex = widget.initialIndex.clamp(0, _urls.length - 1);
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

  Future<void> _shareVideo() async {
    try {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Загрузка...'), duration: Duration(seconds: 1)),
      );
      final response = await http.get(Uri.parse(_resolvedUrl));
      if (response.statusCode == 200) {
        final dir = await getTemporaryDirectory();
        final file = File('${dir.path}/share_video_${DateTime.now().millisecondsSinceEpoch}.mp4');
        await file.writeAsBytes(response.bodyBytes);
        await SharePlus.instance.share(ShareParams(files: [XFile(file.path)]));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка: $e')),
        );
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
        actions: [
          IconButton(
            icon: const Icon(Icons.share),
            tooltip: 'Поделиться',
            onPressed: _shareVideo,
          ),
        ],
      ),
      body: Stack(
        children: [
          Center(
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
          // Navigation arrows for multiple videos
          if (_urls.length > 1) ...[
            if (_currentIndex > 0)
              Positioned(
                left: 8,
                top: 0,
                bottom: 0,
                child: Center(
                  child: IconButton(
                    icon: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.5),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.chevron_left, color: Colors.white, size: 28),
                    ),
                    onPressed: () => _switchVideo(_currentIndex - 1),
                  ),
                ),
              ),
            if (_currentIndex < _urls.length - 1)
              Positioned(
                right: 8,
                top: 0,
                bottom: 0,
                child: Center(
                  child: IconButton(
                    icon: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.5),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.chevron_right, color: Colors.white, size: 28),
                    ),
                    onPressed: () => _switchVideo(_currentIndex + 1),
                  ),
                ),
              ),
            // Counter
            Positioned(
              bottom: 16,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.5),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${_currentIndex + 1} / ${_urls.length}',
                    style: const TextStyle(color: Colors.white, fontSize: 13),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _switchVideo(int index) async {
    _chewieController?.dispose();
    _videoController?.dispose();
    setState(() {
      _currentIndex = index;
      _isLoading = true;
      _error = null;
      _chewieController = null;
      _videoController = null;
    });
    await _initPlayer();
  }
}
