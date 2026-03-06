import 'dart:async';
import 'dart:io' show Platform;
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/constants/api_constants.dart';

/// Circular video note widget for messenger chat.
///
/// Shows a thumbnail (first frame) with play button in the chat list.
/// On tap: opens expanded view in center of screen with circular progress ring.
class VideoNotePlayer extends StatefulWidget {
  final String mediaUrl;
  final int? durationSeconds;
  final bool isFile;

  const VideoNotePlayer({
    super.key,
    required this.mediaUrl,
    this.durationSeconds,
    this.isFile = false,
  });

  @override
  State<VideoNotePlayer> createState() => _VideoNotePlayerState();
}

class _VideoNotePlayerState extends State<VideoNotePlayer> {
  VideoPlayerController? _controller;
  bool _initialized = false;
  bool _hasError = false;

  String get _resolvedUrl {
    if (widget.isFile) return widget.mediaUrl;
    final url = widget.mediaUrl;
    if (url.startsWith('http')) return url;
    return '${ApiConstants.serverUrl}$url';
  }

  @override
  void initState() {
    super.initState();
    _initPlayer();
  }

  Future<void> _initPlayer() async {
    final url = _resolvedUrl;
    if (url.isEmpty) return;
    try {
      _controller = VideoPlayerController.networkUrl(Uri.parse(url));
      await _controller!.initialize();
      if (!mounted) return;
      _controller!.setVolume(0);
      _controller!.setLooping(true);
      _controller!.play();
      setState(() => _initialized = true);
    } catch (e) {
      debugPrint('VideoNotePlayer init error: $e');
      if (mounted) setState(() => _hasError = true);
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  void _openExpandedPlayer() {
    // Pause inline playback while expanded view is open
    _controller?.pause();
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Close',
      barrierColor: Colors.transparent,
      transitionDuration: const Duration(milliseconds: 250),
      transitionBuilder: (context, animation, _, child) {
        return ScaleTransition(
          scale:
              CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
          child: child,
        );
      },
      pageBuilder: (context, _, __) => _ExpandedVideoNote(
        mediaUrl: _resolvedUrl,
        isFile: widget.isFile,
        thumbnail: null,
        durationSeconds: widget.durationSeconds,
      ),
    ).then((_) {
      // Resume inline playback after expanded view is closed
      if (mounted && _initialized) {
        _controller?.setVolume(0);
        _controller?.play();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    const double size = 180;

    return GestureDetector(
      onTap: _openExpandedPlayer,
      child: SizedBox(
        width: size,
        height: size,
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Video or placeholder circle
            Container(
              width: size,
              height: size,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: Color(0xFF0A2020),
              ),
              child: _initialized && _controller != null
                  ? ClipOval(
                      child: SizedBox(
                        width: size,
                        height: size,
                        child: FittedBox(
                          fit: BoxFit.cover,
                          clipBehavior: Clip.hardEdge,
                          child: SizedBox(
                            width: _controller!.value.size.width,
                            height: _controller!.value.size.height,
                            child: VideoPlayer(_controller!),
                          ),
                        ),
                      ),
                    )
                  : Center(
                      child: _hasError
                          ? Icon(Icons.videocam,
                              color: Colors.white.withOpacity(0.4), size: 40)
                          : const SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: AppColors.turquoise,
                              ),
                            ),
                    ),
            ),

            // Duration badge
            Positioned(
              bottom: 8,
              right: 6,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.55),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  _formatDuration(widget.durationSeconds ?? 0),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDuration(int secs) {
    final m = secs ~/ 60;
    final s = secs % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }
}

// ---------------------------------------------------------------------------
// Expanded video note overlay — plays in center of screen with progress ring
// ---------------------------------------------------------------------------

class _ExpandedVideoNote extends StatefulWidget {
  final String mediaUrl;
  final bool isFile;
  final Uint8List? thumbnail;
  final int? durationSeconds;

  const _ExpandedVideoNote({
    required this.mediaUrl,
    required this.isFile,
    this.thumbnail,
    this.durationSeconds,
  });

  @override
  State<_ExpandedVideoNote> createState() => _ExpandedVideoNoteState();
}

class _ExpandedVideoNoteState extends State<_ExpandedVideoNote> {
  bool _isReady = false;
  bool _isPlaying = false;
  bool _isCompleted = false;
  double _progress = 0.0;

  MethodChannel? _channel;
  Timer? _progressTimer;

  void _onPlatformViewCreated(int id) {
    _channel = MethodChannel('native_video_player_$id');
    _channel!.setMethodCallHandler(_handleNativeCall);
  }

  Future<dynamic> _handleNativeCall(MethodCall call) async {
    if (!mounted) return;
    switch (call.method) {
      case 'onReady':
        setState(() => _isReady = true);
        // Auto-play with sound when ready
        _channel?.invokeMethod('play');
        setState(() => _isPlaying = true);
        _startProgressPolling();
        break;
      case 'onCompleted':
        _stopProgressPolling();
        _channel?.invokeMethod('seekTo', {'position': 0});
        if (mounted) {
          setState(() {
            _isPlaying = false;
            _isCompleted = true;
            _progress = 0.0;
          });
        }
        break;
      case 'onError':
        debugPrint('Expanded player error: ${call.arguments}');
        break;
      case 'onThumbnailReady':
      case 'onSizeChanged':
        break;
    }
  }

  void _startProgressPolling() {
    _progressTimer?.cancel();
    _progressTimer = Timer.periodic(const Duration(milliseconds: 80), (_) async {
      if (!_isPlaying || _channel == null) return;
      try {
        final result =
            await _channel!.invokeMapMethod<String, dynamic>('getPosition');
        if (result != null && mounted) {
          final pos = (result['position'] as int?) ?? 0;
          final dur = (result['duration'] as int?) ?? 1;
          if (dur > 0) {
            setState(() => _progress = (pos / dur).clamp(0.0, 1.0));
          }
        }
      } catch (_) {}
    });
  }

  void _stopProgressPolling() {
    _progressTimer?.cancel();
    _progressTimer = null;
  }

  void _onTapVideo() {
    if (!_isReady) return;

    if (_isCompleted) {
      // Replay
      setState(() {
        _isCompleted = false;
        _isPlaying = true;
        _progress = 0.0;
      });
      _channel?.invokeMethod('seekTo', {'position': 0});
      _channel?.invokeMethod('play');
      _startProgressPolling();
    } else if (_isPlaying) {
      // Pause
      _channel?.invokeMethod('pause');
      _stopProgressPolling();
      setState(() => _isPlaying = false);
    } else {
      // Resume
      _channel?.invokeMethod('play');
      setState(() => _isPlaying = true);
      _startProgressPolling();
    }
  }

  @override
  void dispose() {
    _stopProgressPolling();
    _channel?.setMethodCallHandler(null);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final expandedSize = screenWidth * 0.75;
    const ringWidth = 3.0;
    final videoSize = expandedSize - ringWidth * 2;

    return Material(
      type: MaterialType.transparency,
      child: Center(
        child: GestureDetector(
          onTap: _onTapVideo,
          child: Container(
            width: expandedSize,
            height: expandedSize,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.4),
                  blurRadius: 24,
                  spreadRadius: 4,
                ),
              ],
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                // Progress ring
                CustomPaint(
                  painter: _CircleProgressPainter(
                    progress: _progress,
                    strokeWidth: ringWidth,
                    backgroundColor: Colors.white.withOpacity(0.15),
                    progressColor: const Color(0xFF1A4D4D),
                  ),
                  size: Size(expandedSize, expandedSize),
                ),

                // Video + thumbnail layer
                ClipOval(
                  child: SizedBox(
                    width: videoSize,
                    height: videoSize,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        // Native video view (always present once created)
                        _buildPlatformView(videoSize),
                        // Thumbnail overlay (shown when loading or completed)
                        if (_isCompleted || !_isReady)
                          _buildThumbnail(videoSize),
                      ],
                    ),
                  ),
                ),

                // Play / replay button
                if (_isReady && !_isPlaying)
                  Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.black.withOpacity(0.5),
                    ),
                    child: Icon(
                      _isCompleted
                          ? Icons.replay_rounded
                          : Icons.play_arrow_rounded,
                      color: Colors.white,
                      size: 36,
                    ),
                  ),

                // Loading spinner
                if (!_isReady)
                  const SizedBox(
                    width: 40,
                    height: 40,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppColors.turquoise,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildThumbnail(double size) {
    if (widget.thumbnail != null) {
      return Image.memory(
        widget.thumbnail!,
        fit: BoxFit.cover,
        width: size,
        height: size,
      );
    }
    return Container(
      width: size,
      height: size,
      color: const Color(0xFF0A2020),
    );
  }

  Widget _buildPlatformView(double size) {
    final creationParams = <String, dynamic>{
      'url': widget.mediaUrl,
      'isFile': widget.isFile,
    };

    if (!kIsWeb && Platform.isAndroid) {
      return SizedBox(
        width: size,
        height: size,
        child: PlatformViewLink(
          viewType: 'native_video_player',
          surfaceFactory: (context, controller) {
            return AndroidViewSurface(
              controller: controller as AndroidViewController,
              gestureRecognizers: const <Factory<
                  OneSequenceGestureRecognizer>>{},
              hitTestBehavior: PlatformViewHitTestBehavior.opaque,
            );
          },
          onCreatePlatformView: (params) {
            final controller =
                PlatformViewsService.initExpensiveAndroidView(
              id: params.id,
              viewType: 'native_video_player',
              layoutDirection: TextDirection.ltr,
              creationParams: creationParams,
              creationParamsCodec: const StandardMessageCodec(),
            );
            controller
              ..addOnPlatformViewCreatedListener(
                  params.onPlatformViewCreated)
              ..addOnPlatformViewCreatedListener(_onPlatformViewCreated)
              ..create();
            return controller;
          },
        ),
      );
    } else if (!kIsWeb && Platform.isIOS) {
      return SizedBox(
        width: size,
        height: size,
        child: UiKitView(
          viewType: 'native_video_player',
          creationParams: creationParams,
          creationParamsCodec: const StandardMessageCodec(),
          onPlatformViewCreated: _onPlatformViewCreated,
        ),
      );
    }

    return Container(color: Colors.black);
  }
}

// ---------------------------------------------------------------------------
// Circular progress ring painter
// ---------------------------------------------------------------------------

class _CircleProgressPainter extends CustomPainter {
  final double progress;
  final double strokeWidth;
  final Color backgroundColor;
  final Color progressColor;

  _CircleProgressPainter({
    required this.progress,
    required this.strokeWidth,
    required this.backgroundColor,
    required this.progressColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width - strokeWidth) / 2;

    // Background circle
    final bgPaint = Paint()
      ..color = backgroundColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;
    canvas.drawCircle(center, radius, bgPaint);

    // Progress arc
    if (progress > 0) {
      final progressPaint = Paint()
        ..color = progressColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round;

      final sweepAngle = 2 * pi * progress;
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        -pi / 2, // start from top
        sweepAngle,
        false,
        progressPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _CircleProgressPainter old) {
    return old.progress != progress;
  }
}
