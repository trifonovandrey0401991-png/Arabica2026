import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/constants/api_constants.dart';

/// Inline video player for messenger chat (Telegram-style).
/// Auto-plays muted + looping. Tap opens fullscreen player.
class InlineChatVideoPlayer extends StatefulWidget {
  final String videoUrl;
  final String? thumbnailUrl;
  final VoidCallback? onTap;

  const InlineChatVideoPlayer({
    super.key,
    required this.videoUrl,
    this.thumbnailUrl,
    this.onTap,
  });

  @override
  State<InlineChatVideoPlayer> createState() => _InlineChatVideoPlayerState();
}

class _InlineChatVideoPlayerState extends State<InlineChatVideoPlayer> {
  VideoPlayerController? _controller;
  bool _initialized = false;
  bool _hasError = false;
  bool _isMuted = true;

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
      _controller = VideoPlayerController.networkUrl(Uri.parse(_resolvedUrl));
      await _controller!.initialize();
      if (!mounted) return;
      _controller!.setVolume(0);
      _controller!.setLooping(true);
      _controller!.play();
      setState(() => _initialized = true);
    } catch (e) {
      debugPrint('InlineChatVideoPlayer error: $e');
      if (mounted) setState(() => _hasError = true);
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  void _toggleMute() {
    if (_controller == null || !_initialized) return;
    setState(() {
      _isMuted = !_isMuted;
      _controller!.setVolume(_isMuted ? 0 : 1);
    });
  }

  @override
  Widget build(BuildContext context) {
    // Max width like Telegram — roughly 70% of screen, capped at 300
    final maxWidth = (MediaQuery.of(context).size.width * 0.7).clamp(200.0, 300.0);

    return GestureDetector(
      onTap: widget.onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: _initialized && _controller != null
              ? _buildVideoView(maxWidth)
              : _buildPlaceholder(maxWidth),
        ),
      ),
    );
  }

  Widget _buildVideoView(double maxWidth) {
    final aspect = _controller!.value.aspectRatio;
    final height = (maxWidth / aspect).clamp(100.0, 400.0);

    return SizedBox(
      width: maxWidth,
      height: height,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Video
          FittedBox(
            fit: BoxFit.cover,
            clipBehavior: Clip.hardEdge,
            child: SizedBox(
              width: _controller!.value.size.width,
              height: _controller!.value.size.height,
              child: VideoPlayer(_controller!),
            ),
          ),
          // Mute/unmute button (top-right)
          Positioned(
            top: 6,
            right: 6,
            child: GestureDetector(
              onTap: _toggleMute,
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.5),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  _isMuted ? Icons.volume_off : Icons.volume_up,
                  color: Colors.white,
                  size: 16,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPlaceholder(double maxWidth) {
    final height = maxWidth * 0.75; // 4:3 default ratio

    return SizedBox(
      width: maxWidth,
      height: height,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Thumbnail or dark background
          if (widget.thumbnailUrl != null && !_hasError)
            CachedNetworkImage(
              imageUrl: widget.thumbnailUrl!,
              fit: BoxFit.cover,
              width: maxWidth,
              height: height,
              placeholder: (_, __) => Container(color: Colors.black.withOpacity(0.3)),
              errorWidget: (_, __, ___) => Container(
                color: Colors.black.withOpacity(0.3),
                child: Icon(Icons.videocam, size: 32, color: Colors.white.withOpacity(0.2)),
              ),
            )
          else
            Container(
              color: Colors.black.withOpacity(0.3),
              child: Icon(Icons.videocam, size: 32, color: Colors.white.withOpacity(0.2)),
            ),
          // Loading or play icon
          if (!_hasError)
            const SizedBox(
              width: 28,
              height: 28,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: AppColors.turquoise,
              ),
            )
          else
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.black.withOpacity(0.5),
              ),
              child: const Icon(Icons.play_arrow_rounded, size: 34, color: Colors.white),
            ),
        ],
      ),
    );
  }
}
