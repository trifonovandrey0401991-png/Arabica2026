import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:visibility_detector/visibility_detector.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/constants/api_constants.dart';
import '../../../core/utils/logger.dart';

/// Telegram-style inline video player for messenger chat.
/// Auto-loads and plays muted+looping when visible. Tap opens fullscreen.
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
  bool _isLoading = false;
  bool _visible = false;

  String get _resolvedUrl {
    final url = widget.videoUrl;
    if (url.startsWith('http')) return url;
    return '${ApiConstants.serverUrl}$url';
  }

  String? get _resolvedThumbUrl {
    final url = widget.thumbnailUrl;
    if (url == null) return null;
    if (url.startsWith('http')) return url;
    return '${ApiConstants.serverUrl}$url';
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _initAndPlay() async {
    if (_isLoading) return;
    if (_initialized && _controller != null) {
      _controller!.play();
      return;
    }
    setState(() => _isLoading = true);
    try {
      _controller = VideoPlayerController.networkUrl(Uri.parse(_resolvedUrl));
      await _controller!.initialize();
      if (!mounted) return;
      _controller!.setVolume(0);
      _controller!.setLooping(true);
      _controller!.play();
      setState(() {
        _initialized = true;
        _isLoading = false;
      });
    } catch (e) {
      Logger.error('InlineChatVideoPlayer error: $e');
      if (mounted) {
        setState(() {
          _hasError = true;
          _isLoading = false;
        });
      }
    }
  }

  void _onVisibilityChanged(VisibilityInfo info) {
    final nowVisible = info.visibleFraction > 0.3;
    if (nowVisible == _visible) return;
    _visible = nowVisible;

    if (nowVisible) {
      // Became visible — auto-load and play
      if (!_initialized && !_isLoading && !_hasError) {
        _initAndPlay();
      } else if (_initialized && _controller != null) {
        _controller!.play();
      }
    } else {
      // Scrolled away — pause to save resources
      _controller?.pause();
    }
  }

  void _toggleMute() {
    if (_controller == null || !_initialized) return;
    setState(() {
      _isMuted = !_isMuted;
      _controller!.setVolume(_isMuted ? 0 : 1);
    });
  }

  void _retry() {
    _controller?.dispose();
    _controller = null;
    _initialized = false;
    setState(() => _hasError = false);
    _initAndPlay();
  }

  @override
  Widget build(BuildContext context) {
    final maxWidth = (MediaQuery.of(context).size.width * 0.7).clamp(200.0, 300.0);

    return VisibilityDetector(
      key: Key('video_${widget.videoUrl}'),
      onVisibilityChanged: _onVisibilityChanged,
      child: GestureDetector(
        onTap: () {
          if (_hasError) {
            _retry();
          } else if (_initialized) {
            widget.onTap?.call();
          }
        },
        child: ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxWidth),
            child: _initialized && _controller != null
                ? _buildVideoView(maxWidth)
                : _buildPlaceholder(maxWidth),
          ),
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
    final height = maxWidth * 0.75;

    return SizedBox(
      width: maxWidth,
      height: height,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Thumbnail or dark background
          if (_resolvedThumbUrl != null && !_hasError)
            CachedNetworkImage(
              imageUrl: _resolvedThumbUrl!,
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
          // Loading indicator or error retry
          if (_isLoading)
            const SizedBox(
              width: 28,
              height: 28,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: AppColors.turquoise,
              ),
            )
          else if (_hasError)
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.black.withOpacity(0.5),
              ),
              child: const Icon(Icons.refresh_rounded, size: 34, color: Colors.white),
            ),
          // No icon when idle — video will auto-load on visibility
        ],
      ),
    );
  }
}
