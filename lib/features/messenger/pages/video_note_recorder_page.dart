import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import '../../../core/theme/app_colors.dart';

/// Full-screen page for recording circular video notes (max 30 sec).
/// Returns the recorded [File] on confirm, or null on cancel.
class VideoNoteRecorderPage extends StatefulWidget {
  const VideoNoteRecorderPage({super.key});

  @override
  State<VideoNoteRecorderPage> createState() => _VideoNoteRecorderPageState();
}

enum _RecorderMode { idle, recording, preview }

class _VideoNoteRecorderPageState extends State<VideoNoteRecorderPage>
    with TickerProviderStateMixin {
  static const int _maxSeconds = 30;

  List<CameraDescription> _cameras = [];
  CameraController? _cameraCtrl;
  int _cameraIndex = 1; // 1 = front camera (selfie), 0 = back
  bool _cameraReady = false;
  bool _switchingCamera = false;

  _RecorderMode _mode = _RecorderMode.idle;
  int _seconds = 0;
  Timer? _timer;
  late AnimationController _progressAnim;

  // Preview — native video player
  File? _recordedFile;
  bool _previewReady = false;
  bool _previewViewCreated = false;
  MethodChannel? _previewChannel;

  @override
  void initState() {
    super.initState();
    _progressAnim = AnimationController(
      vsync: this,
      duration: const Duration(seconds: _maxSeconds),
    );
    _initCameras();
  }

  Future<void> _initCameras() async {
    try {
      _cameras = await availableCameras();
      if (_cameras.isEmpty) return;
      _cameraIndex = _cameras.length > 1 ? 1 : 0;
      await _setupCamera(_cameraIndex);
    } catch (e) {
      // Camera unavailable
    }
  }

  Future<void> _setupCamera(int index) async {
    final old = _cameraCtrl;
    _cameraCtrl = null;
    if (mounted) setState(() => _cameraReady = false);

    try {
      await old?.dispose();
    } catch (e) {
      debugPrint('video_note_recorder: Failed to dispose old camera: $e');
    }

    if (index >= _cameras.length) return;

    final ctrl = CameraController(
      _cameras[index],
      ResolutionPreset.high,
      enableAudio: true,
      imageFormatGroup: ImageFormatGroup.jpeg,
    );
    _cameraCtrl = ctrl;

    try {
      await ctrl.initialize();
      if (mounted) setState(() => _cameraReady = true);
    } catch (e) {
      // ignore
    }
  }

  Future<void> _flipCamera() async {
    if (_cameras.length < 2 ||
        _mode == _RecorderMode.recording ||
        _switchingCamera) return;
    setState(() => _switchingCamera = true);
    final newIndex = _cameraIndex == 0 ? 1 : 0;
    _cameraIndex = newIndex;
    await _setupCamera(newIndex);
    if (mounted) setState(() => _switchingCamera = false);
  }

  Future<void> _startRecording() async {
    final ctrl = _cameraCtrl;
    if (ctrl == null ||
        !ctrl.value.isInitialized ||
        _mode != _RecorderMode.idle) return;

    try {
      await ctrl.startVideoRecording();
    } catch (e) {
      return;
    }

    _progressAnim.forward(from: 0);
    if (!mounted) return;
    setState(() {
      _mode = _RecorderMode.recording;
      _seconds = 0;
    });

    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _seconds++);
      if (_seconds >= _maxSeconds) _stopRecording();
    });
  }

  Future<void> _stopRecording() async {
    _timer?.cancel();
    _timer = null;
    _progressAnim.stop();

    final ctrl = _cameraCtrl;
    if (ctrl == null || !ctrl.value.isRecordingVideo) return;

    try {
      final xfile = await ctrl.stopVideoRecording();
      final file = File(xfile.path);

      final dir = await getTemporaryDirectory();
      final ts = DateTime.now().millisecondsSinceEpoch;
      final rawDest = File('${dir.path}/video_note_raw_$ts.mp4');
      final dest = File('${dir.path}/video_note_$ts.mp4');
      await file.copy(rawDest.path);

      // Remux to fix broken timestamps and front-camera mirroring on Samsung
      final isFront = _cameraIndex == 1 && _cameras.length > 1;
      final remuxed = await _remuxVideo(rawDest.path, dest.path, frontCamera: isFront);
      final finalFile = remuxed ? dest : rawDest;

      // Clean up raw file if remux succeeded
      if (remuxed) {
        try { await rawDest.delete(); } catch (e) {
          debugPrint('video_note_recorder: Failed to delete raw file: $e');
        }
      }

      // Release camera BEFORE playing preview — frees the video decoder
      // so ExoPlayer can use it (critical on older devices with limited codecs)
      try {
        await _cameraCtrl?.dispose();
      } catch (e) {
        debugPrint('video_note_recorder: Failed to dispose camera: $e');
      }
      _cameraCtrl = null;
      _cameraReady = false;

      if (!mounted) return;
      setState(() {
        _recordedFile = finalFile;
        _mode = _RecorderMode.preview;
        _previewReady = false;
        _previewViewCreated = true;
      });
    } catch (e) {
      if (mounted) setState(() => _mode = _RecorderMode.idle);
    }
  }

  /// Remux video to fix broken timestamps from Samsung camera.
  /// Uses Android's MediaExtractor + MediaMuxer to produce clean MP4.
  static const _videoUtils = MethodChannel('video_utils');
  Future<bool> _remuxVideo(String input, String output, {bool frontCamera = false}) async {
    try {
      final result = await _videoUtils.invokeMethod('remux', {
        'input': input,
        'output': output,
        'frontCamera': frontCamera,
      });
      return result == true;
    } catch (e) {
      debugPrint('Remux failed: $e');
      return false;
    }
  }

  void _onPreviewPlatformViewCreated(int id) {
    _previewChannel = MethodChannel('native_video_player_$id');
    _previewChannel!.setMethodCallHandler(_handlePreviewCall);
  }

  Future<dynamic> _handlePreviewCall(MethodCall call) async {
    if (!mounted) return;
    switch (call.method) {
      case 'onReady':
        setState(() => _previewReady = true);
        // Auto-play preview
        _previewChannel?.invokeMethod('play');
        break;
      case 'onCompleted':
        break;
      case 'onError':
        debugPrint('Preview error: ${call.arguments}');
        break;
    }
  }

  void _cancelPreview() async {
    _previewChannel?.setMethodCallHandler(null);
    _previewChannel = null;
    _previewReady = false;
    _previewViewCreated = false;
    _recordedFile = null;
    _progressAnim.reset();
    if (mounted) setState(() => _mode = _RecorderMode.idle);
    await _setupCamera(_cameraIndex);
  }

  void _confirmSend() {
    _previewChannel?.invokeMethod('pause');
    _previewChannel?.setMethodCallHandler(null);
    _previewChannel = null;
    final file = _recordedFile;
    Navigator.of(context).pop({'file': file, 'duration': _seconds});
  }

  @override
  void dispose() {
    _timer?.cancel();
    _progressAnim.dispose();
    try { _cameraCtrl?.dispose(); } catch (_) {}
    _cameraCtrl = null;
    _previewChannel?.setMethodCallHandler(null);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: _mode == _RecorderMode.preview
            ? _buildPreviewUI()
            : _buildRecorderUI(),
      ),
    );
  }

  // ─── Recorder UI ───────────────────────────────────────────────────────────

  Widget _buildRecorderUI() {
    return Stack(
      children: [
        Container(color: Colors.black),
        Column(
          children: [
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () => Navigator.of(context).pop(null),
                    child: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white.withOpacity(0.1),
                      ),
                      child: const Icon(Icons.close,
                          color: Colors.white, size: 22),
                    ),
                  ),
                  const Spacer(),
                  if (_mode == _RecorderMode.recording)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.red.withOpacity(0.85),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Text(
                        '${_maxSeconds - _seconds}с',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  const Spacer(),
                  GestureDetector(
                    onTap: _flipCamera,
                    child: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white.withOpacity(0.1),
                      ),
                      child: _switchingCamera
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white),
                            )
                          : const Icon(Icons.flip_camera_ios,
                              color: Colors.white, size: 22),
                    ),
                  ),
                ],
              ),
            ),
            const Spacer(),
            Center(child: _buildCircularCamera()),
            const Spacer(),
            Center(child: _buildRecordButton()),
            const SizedBox(height: 48),
          ],
        ),
      ],
    );
  }

  Widget _buildCircularCamera() {
    const double size = 280;

    return AnimatedBuilder(
      animation: _progressAnim,
      builder: (_, child) {
        return SizedBox(
          width: size + 12,
          height: size + 12,
          child: Stack(
            alignment: Alignment.center,
            children: [
              if (_mode == _RecorderMode.recording)
                CustomPaint(
                  size: const Size(size + 12, size + 12),
                  painter:
                      _RingProgressPainter(progress: _progressAnim.value),
                ),
              if (_mode == _RecorderMode.idle)
                Container(
                  width: size + 4,
                  height: size + 4,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                        color: Colors.white.withOpacity(0.25), width: 2),
                  ),
                ),
              SizedBox(
                width: size,
                height: size,
                child: _cameraReady && _cameraCtrl != null
                    ? ClipOval(
                        child: _buildCameraPreview(size),
                      )
                    : Container(
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: Color(0xFF111111),
                        ),
                        child: const Center(
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppColors.turquoise,
                          ),
                        ),
                      ),
              ),
              child!,
            ],
          ),
        );
      },
      child: const SizedBox.shrink(),
    );
  }

  Widget _buildCameraPreview(double size) {
    final ctrl = _cameraCtrl!;

    // Use FittedBox with cover to fill the circle without distortion.
    // The camera aspect ratio (e.g. 9:16) will be cropped to 1:1 square.
    return SizedBox(
      width: size,
      height: size,
      child: FittedBox(
        fit: BoxFit.cover,
        clipBehavior: Clip.hardEdge,
        child: SizedBox(
          width: ctrl.value.previewSize?.height ?? size,
          height: ctrl.value.previewSize?.width ?? size,
          child: CameraPreview(ctrl),
        ),
      ),
    );
  }

  Widget _buildRecordButton() {
    final isRecording = _mode == _RecorderMode.recording;
    return GestureDetector(
      onTap: isRecording ? _stopRecording : _startRecording,
      child: Container(
        width: 72,
        height: 72,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white.withOpacity(0.12),
          border: Border.all(color: Colors.white, width: 3),
        ),
        child: Center(
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: isRecording ? 28 : 52,
            height: isRecording ? 28 : 52,
            decoration: BoxDecoration(
              color: Colors.red,
              borderRadius: BorderRadius.circular(isRecording ? 6 : 26),
            ),
          ),
        ),
      ),
    );
  }

  // ─── Preview UI ────────────────────────────────────────────────────────────

  Widget _buildPreviewUI() {
    const double size = 280;
    return Column(
      children: [
        const SizedBox(height: 16),
        Text(
          'Предпросмотр',
          style: TextStyle(
            color: Colors.white.withOpacity(0.7),
            fontSize: 16,
          ),
        ),
        const Spacer(),

        // Circular video preview using native platform view
        Center(
          child: ClipOval(
            child: SizedBox(
              width: size,
              height: size,
              child: _previewViewCreated && _recordedFile != null
                  ? Stack(
                      children: [
                        SizedBox(
                          width: size,
                          height: size,
                          child: _buildPreviewPlatformView(),
                        ),
                        // Loading indicator while preparing
                        if (!_previewReady)
                          const Center(
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: AppColors.turquoise,
                            ),
                          ),
                      ],
                    )
                  : Container(
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.black,
                      ),
                      child: const Center(
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppColors.turquoise,
                        ),
                      ),
                    ),
            ),
          ),
        ),

        const Spacer(),

        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 40),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              GestureDetector(
                onTap: _cancelPreview,
                child: Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withOpacity(0.1),
                  ),
                  child:
                      const Icon(Icons.close, color: Colors.white, size: 28),
                ),
              ),
              GestureDetector(
                onTap: _confirmSend,
                child: Container(
                  width: 64,
                  height: 64,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      colors: [AppColors.turquoise, AppColors.emerald],
                    ),
                  ),
                  child: const Icon(Icons.send_rounded,
                      color: Colors.white, size: 28),
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 48),
      ],
    );
  }

  Widget _buildPreviewPlatformView() {
    final creationParams = <String, dynamic>{
      'url': _recordedFile!.path,
      'isFile': true,
      'loop': true,
    };

    if (!kIsWeb && Platform.isAndroid) {
      return PlatformViewLink(
        viewType: 'native_video_player',
        surfaceFactory: (context, controller) {
          return AndroidViewSurface(
            controller: controller as AndroidViewController,
            gestureRecognizers: const <Factory<OneSequenceGestureRecognizer>>{},
            hitTestBehavior: PlatformViewHitTestBehavior.opaque,
          );
        },
        onCreatePlatformView: (params) {
          final controller = PlatformViewsService.initExpensiveAndroidView(
            id: params.id,
            viewType: 'native_video_player',
            layoutDirection: TextDirection.ltr,
            creationParams: creationParams,
            creationParamsCodec: const StandardMessageCodec(),
          );
          controller
            ..addOnPlatformViewCreatedListener(params.onPlatformViewCreated)
            ..addOnPlatformViewCreatedListener(_onPreviewPlatformViewCreated)
            ..create();
          return controller;
        },
      );
    } else if (!kIsWeb && Platform.isIOS) {
      return UiKitView(
        viewType: 'native_video_player',
        creationParams: creationParams,
        creationParamsCodec: const StandardMessageCodec(),
        onPlatformViewCreated: _onPreviewPlatformViewCreated,
      );
    }

    return Container(color: Colors.black);
  }
}

// ─── Ring Progress Painter ────────────────────────────────────────────────────

class _RingProgressPainter extends CustomPainter {
  final double progress;

  _RingProgressPainter({required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 4;

    final trackPaint = Paint()
      ..color = Colors.white.withOpacity(0.15)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;

    canvas.drawCircle(center, radius, trackPaint);

    final progressPaint = Paint()
      ..color = Colors.red
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2,
      2 * math.pi * progress,
      false,
      progressPaint,
    );
  }

  @override
  bool shouldRepaint(_RingProgressPainter old) => old.progress != progress;
}

/// Paints background color everywhere EXCEPT inside a centered circle.
class _CircleMaskPainter extends CustomPainter {
  final Color color;
  _CircleMaskPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) / 2;

    final path = Path()
      ..addRect(Rect.fromLTWH(0, 0, size.width, size.height))
      ..addOval(Rect.fromCircle(center: center, radius: radius))
      ..fillType = PathFillType.evenOdd;

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_CircleMaskPainter old) => old.color != color;
}
