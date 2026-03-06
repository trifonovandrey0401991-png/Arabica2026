import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:path_provider/path_provider.dart';

import '../../../core/theme/app_colors.dart';

/// Stroke model for drawing on photo
class DrawStroke {
  final List<Offset> points;
  final Color color;
  final double width;

  DrawStroke({required this.points, required this.color, required this.width});
}

/// Full-screen photo editor with multi-photo preview, drawing and cropping.
/// Accepts List<File>, returns List<File>? (null = cancelled).
class PhotoEditorPage extends StatefulWidget {
  final List<File> photos;

  const PhotoEditorPage({super.key, required this.photos});

  @override
  State<PhotoEditorPage> createState() => _PhotoEditorPageState();
}

class _PhotoEditorPageState extends State<PhotoEditorPage> {
  late List<File> _photos;
  late PageController _pageController;
  int _currentIndex = 0;

  // Drawing state
  bool _isDrawMode = false;
  final Map<int, List<DrawStroke>> _strokesPerPhoto = {};
  List<Offset>? _currentStroke;
  Color _selectedColor = Colors.red;
  double _strokeWidth = 6.0;

  // For flattening drawing to image
  final GlobalKey _repaintKey = GlobalKey();

  bool _isSending = false;

  static const List<Color> _colors = [
    Colors.white,
    Colors.black,
    Color(0xFFEF4444), // red
    Color(0xFF3B82F6), // blue
    Color(0xFF4CAF50), // green
    Color(0xFFF59E0B), // yellow
    Color(0xFF4ECDC4), // turquoise
    Color(0xFFD4AF37), // gold
  ];

  static const List<double> _thicknesses = [3.0, 6.0, 12.0];

  @override
  void initState() {
    super.initState();
    _photos = List<File>.from(widget.photos);
    _pageController = PageController();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  List<DrawStroke> get _currentStrokes =>
      _strokesPerPhoto[_currentIndex] ?? [];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            // Top bar
            _buildTopBar(),

            // Photo viewer
            Expanded(child: _buildPhotoViewer()),

            // Drawing toolbar (only in draw mode)
            if (_isDrawMode) _buildDrawToolbar(),

            // Bottom: thumbnails + send button
            _buildBottomBar(),
          ],
        ),
      ),
    );
  }

  // ===== TOP BAR =====

  Widget _buildTopBar() {
    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      color: const Color(0xFF0A2A2A),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.close, color: Colors.white),
            onPressed: () => Navigator.pop(context),
          ),
          const Spacer(),
          if (_photos.length > 1)
            Text(
              '${_currentIndex + 1}/${_photos.length}',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
            ),
          const Spacer(),
          // Crop button
          IconButton(
            icon: const Icon(Icons.crop, color: Colors.white),
            tooltip: 'Обрезать',
            onPressed: _isDrawMode ? null : _onCropTap,
          ),
          // Draw toggle
          IconButton(
            icon: Icon(
              Icons.edit,
              color: _isDrawMode ? AppColors.turquoise : Colors.white,
            ),
            tooltip: 'Рисовать',
            onPressed: _onDrawToggle,
          ),
        ],
      ),
    );
  }

  // ===== PHOTO VIEWER =====

  Widget _buildPhotoViewer() {
    if (_isDrawMode) {
      // In draw mode — single photo with drawing overlay, no PageView swipe
      return _buildDrawablePhoto(_currentIndex);
    }

    return PageView.builder(
      controller: _pageController,
      itemCount: _photos.length,
      onPageChanged: (index) {
        if (mounted) setState(() => _currentIndex = index);
      },
      itemBuilder: (context, index) {
        return Center(
          child: Image.file(
            _photos[index],
            fit: BoxFit.contain,
          ),
        );
      },
    );
  }

  Widget _buildDrawablePhoto(int index) {
    final strokes = _strokesPerPhoto[index] ?? [];

    return RepaintBoundary(
      key: _repaintKey,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Photo
          Center(
            child: Image.file(
              _photos[index],
              fit: BoxFit.contain,
            ),
          ),
          // Drawing layer
          Positioned.fill(
            child: GestureDetector(
              onPanStart: _onPanStart,
              onPanUpdate: _onPanUpdate,
              onPanEnd: _onPanEnd,
              child: CustomPaint(
                painter: _DrawingPainter(
                  strokes: strokes,
                  currentStroke: _currentStroke,
                  currentColor: _selectedColor,
                  currentWidth: _strokeWidth,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ===== DRAWING TOOLBAR =====

  Widget _buildDrawToolbar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      color: const Color(0xFF0A2A2A),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Color picker row
          Row(
            children: [
              // Undo button
              IconButton(
                icon: const Icon(Icons.undo, color: Colors.white, size: 22),
                onPressed: _currentStrokes.isEmpty ? null : _undoStroke,
              ),
              const SizedBox(width: 4),
              // Colors
              Expanded(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: _colors.map((c) => _buildColorDot(c)).toList(),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          // Thickness selector
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: _thicknesses.map((t) => _buildThicknessOption(t)).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildColorDot(Color color) {
    final isSelected = _selectedColor == color;
    return GestureDetector(
      onTap: () => setState(() => _selectedColor = color),
      child: Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(
            color: isSelected ? AppColors.turquoise : Colors.white.withOpacity(0.3),
            width: isSelected ? 2.5 : 1,
          ),
        ),
      ),
    );
  }

  Widget _buildThicknessOption(double thickness) {
    final isSelected = _strokeWidth == thickness;
    return GestureDetector(
      onTap: () => setState(() => _strokeWidth = thickness),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16),
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            color: isSelected ? AppColors.turquoise : Colors.transparent,
            width: 2,
          ),
        ),
        child: Center(
          child: Container(
            width: thickness + 4,
            height: thickness + 4,
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
            ),
          ),
        ),
      ),
    );
  }

  // ===== BOTTOM BAR: THUMBNAILS + SEND =====

  Widget _buildBottomBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      color: const Color(0xFF0A2A2A),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Thumbnails (only if multiple photos)
          if (_photos.length > 1)
            SizedBox(
              height: 60,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: _photos.length,
                itemBuilder: (context, index) => _buildThumbnail(index),
              ),
            ),
          if (_photos.length > 1) const SizedBox(height: 10),
          // Send button
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton.icon(
              onPressed: _isSending ? null : _onSend,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.turquoise,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                disabledBackgroundColor: AppColors.turquoise.withOpacity(0.5),
              ),
              icon: _isSending
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.send, size: 20),
              label: Text(
                _isSending
                    ? 'Отправка...'
                    : _photos.length > 1
                        ? 'Отправить (${_photos.length})'
                        : 'Отправить',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildThumbnail(int index) {
    final isSelected = index == _currentIndex;
    return GestureDetector(
      onTap: () {
        if (!_isDrawMode) {
          _pageController.animateToPage(
            index,
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeInOut,
          );
        }
        setState(() => _currentIndex = index);
      },
      child: Container(
        width: 56,
        height: 56,
        margin: const EdgeInsets.symmetric(horizontal: 4),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected ? AppColors.turquoise : Colors.transparent,
            width: 2,
          ),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: Image.file(
            _photos[index],
            fit: BoxFit.cover,
          ),
        ),
      ),
    );
  }

  // ===== ACTIONS =====

  Future<void> _onCropTap() async {
    // Flatten drawing first if there are strokes
    await _flattenCurrentDrawingIfNeeded();

    // Verify file exists before opening cropper
    final sourceFile = _photos[_currentIndex];
    if (!await sourceFile.exists()) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Файл фото не найден')),
        );
      }
      return;
    }

    try {
      final cropped = await ImageCropper().cropImage(
        sourcePath: sourceFile.path,
        compressQuality: 80,
        maxWidth: 1280,
        maxHeight: 1280,
        uiSettings: [
          AndroidUiSettings(
            toolbarTitle: 'Обрезать',
            toolbarColor: AppColors.emeraldDark,
            toolbarWidgetColor: Colors.white,
            backgroundColor: Colors.black,
            activeControlsWidgetColor: AppColors.turquoise,
            cropGridColor: Colors.white.withOpacity(0.3),
            cropFrameColor: AppColors.turquoise,
          ),
        ],
      );
      if (cropped != null && mounted) {
        setState(() {
          _photos[_currentIndex] = File(cropped.path);
          _strokesPerPhoto.remove(_currentIndex); // clear strokes — photo changed
        });
      }
    } catch (e) {
      debugPrint('Crop error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Не удалось обрезать фото. Попробуйте ещё раз.')),
        );
      }
    }
  }

  void _onDrawToggle() async {
    if (_isDrawMode) {
      // Exiting draw mode — flatten if there are strokes
      await _flattenCurrentDrawingIfNeeded();
    }
    if (mounted) {
      setState(() => _isDrawMode = !_isDrawMode);
    }
  }

  Future<void> _flattenCurrentDrawingIfNeeded() async {
    final strokes = _strokesPerPhoto[_currentIndex];
    if (strokes == null || strokes.isEmpty) return;

    try {
      final boundary = _repaintKey.currentContext
          ?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) return;

      final image = await boundary.toImage(pixelRatio: 2.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) return;

      final bytes = byteData.buffer.asUint8List();
      final dir = await getTemporaryDirectory();
      final file = File(
        '${dir.path}/edited_${DateTime.now().millisecondsSinceEpoch}.png',
      );
      await file.writeAsBytes(bytes);

      if (mounted) {
        setState(() {
          _photos[_currentIndex] = file;
          _strokesPerPhoto.remove(_currentIndex);
        });
      }
    } catch (e) {
      debugPrint('Error flattening drawing: $e');
    }
  }

  void _undoStroke() {
    final strokes = _strokesPerPhoto[_currentIndex];
    if (strokes != null && strokes.isNotEmpty) {
      setState(() => strokes.removeLast());
    }
  }

  // Drawing gesture handlers
  void _onPanStart(DragStartDetails details) {
    setState(() {
      _currentStroke = [details.localPosition];
    });
  }

  void _onPanUpdate(DragUpdateDetails details) {
    if (_currentStroke == null) return;
    setState(() {
      _currentStroke!.add(details.localPosition);
    });
  }

  void _onPanEnd(DragEndDetails details) {
    if (_currentStroke == null || _currentStroke!.isEmpty) return;
    final stroke = DrawStroke(
      points: List<Offset>.from(_currentStroke!),
      color: _selectedColor,
      width: _strokeWidth,
    );
    setState(() {
      _strokesPerPhoto.putIfAbsent(_currentIndex, () => []);
      _strokesPerPhoto[_currentIndex]!.add(stroke);
      _currentStroke = null;
    });
  }

  Future<void> _onSend() async {
    if (_isSending) return;
    setState(() => _isSending = true);

    // Flatten current drawing if in draw mode
    if (_isDrawMode) {
      await _flattenCurrentDrawingIfNeeded();
      if (mounted) setState(() => _isDrawMode = false);
    }

    if (mounted) {
      Navigator.pop(context, _photos);
    }
  }
}

// ===== DRAWING PAINTER =====

class _DrawingPainter extends CustomPainter {
  final List<DrawStroke> strokes;
  final List<Offset>? currentStroke;
  final Color currentColor;
  final double currentWidth;

  _DrawingPainter({
    required this.strokes,
    this.currentStroke,
    required this.currentColor,
    required this.currentWidth,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Draw completed strokes
    for (final stroke in strokes) {
      _drawStroke(canvas, stroke.points, stroke.color, stroke.width);
    }

    // Draw current stroke in progress
    if (currentStroke != null && currentStroke!.isNotEmpty) {
      _drawStroke(canvas, currentStroke!, currentColor, currentWidth);
    }
  }

  void _drawStroke(Canvas canvas, List<Offset> points, Color color, double width) {
    if (points.length < 2) return;

    final paint = Paint()
      ..color = color
      ..strokeWidth = width
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;

    final path = Path()..moveTo(points[0].dx, points[0].dy);
    for (int i = 1; i < points.length; i++) {
      path.lineTo(points[i].dx, points[i].dy);
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _DrawingPainter oldDelegate) =>
      strokes != oldDelegate.strokes ||
      currentStroke != oldDelegate.currentStroke ||
      currentColor != oldDelegate.currentColor ||
      currentWidth != oldDelegate.currentWidth;
}
