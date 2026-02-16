import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

/// Полноэкранный виджет для выделения области счётчика на фото
/// Сотрудник рисует красный прямоугольник вокруг числа на экране кофемашины
class CounterRegionSelector extends StatefulWidget {
  final File imageFile;
  final Map<String, double>? initialRegion;

  const CounterRegionSelector({
    super.key,
    required this.imageFile,
    this.initialRegion,
  });

  /// Показать полноэкранный выбор области и вернуть {x, y, width, height} (0.0-1.0)
  static Future<Map<String, double>?> show(
    BuildContext context, {
    required File imageFile,
    Map<String, double>? initialRegion,
  }) async {
    return Navigator.of(context).push<Map<String, double>>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => CounterRegionSelector(
          imageFile: imageFile,
          initialRegion: initialRegion,
        ),
      ),
    );
  }

  @override
  State<CounterRegionSelector> createState() => _CounterRegionSelectorState();
}

class _CounterRegionSelectorState extends State<CounterRegionSelector> {
  static final Color _emerald = Color(0xFF1A4D4D);
  static final Color _night = Color(0xFF051515);

  ui.Image? _image;
  Size? _imageSize;

  // Текущий прямоугольник (нормализованные координаты 0.0-1.0)
  Rect? _region;

  // Состояние рисования
  Offset? _startPoint;
  Offset? _currentPoint;
  bool _isDrawing = false;

  @override
  void initState() {
    super.initState();
    if (widget.initialRegion != null) {
      final r = widget.initialRegion!;
      _region = Rect.fromLTWH(
        r['x'] ?? 0,
        r['y'] ?? 0,
        r['width'] ?? 0,
        r['height'] ?? 0,
      );
    }
    _loadImage();
  }

  Future<void> _loadImage() async {
    final bytes = await widget.imageFile.readAsBytes();
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    if (!mounted) return;
    setState(() {
      _image = frame.image;
      _imageSize = Size(
        frame.image.width.toDouble(),
        frame.image.height.toDouble(),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [_emerald, _night],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              _buildHeader(),
              Expanded(child: _buildImageArea()),
              _buildBottomBar(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 4.h),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.pop(context),
            icon: Icon(Icons.close, color: Colors.white),
          ),
          SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Выделите счётчик',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18.sp,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  'Обведите число пальцем',
                  style: TextStyle(color: Colors.white54, fontSize: 13.sp),
                ),
              ],
            ),
          ),
          if (_region != null)
            TextButton(
              onPressed: () => setState(() => _region = null),
              child: Text(
                'Сбросить',
                style: TextStyle(color: Colors.orange, fontSize: 14.sp),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildImageArea() {
    if (_image == null) {
      return Center(
        child: CircularProgressIndicator(color: Colors.white),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final imageAspect = _imageSize!.width / _imageSize!.height;
        final containerAspect = constraints.maxWidth / constraints.maxHeight;

        Size displaySize;
        if (imageAspect > containerAspect) {
          displaySize = Size(
            constraints.maxWidth,
            constraints.maxWidth / imageAspect,
          );
        } else {
          displaySize = Size(
            constraints.maxHeight * imageAspect,
            constraints.maxHeight,
          );
        }

        return GestureDetector(
          onPanStart: (d) => _onPanStart(d, displaySize),
          onPanUpdate: (d) => _onPanUpdate(d, displaySize),
          onPanEnd: (_) => _onPanEnd(),
          child: Center(
            child: SizedBox(
              width: displaySize.width,
              height: displaySize.height,
              child: CustomPaint(
                painter: _RegionPainter(
                  image: _image!,
                  region: _region,
                  currentRect: _isDrawing &&
                          _startPoint != null &&
                          _currentPoint != null
                      ? Rect.fromPoints(_startPoint!, _currentPoint!)
                      : null,
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildBottomBar() {
    return Container(
      padding: EdgeInsets.all(16.w),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.3),
        border: Border(
          top: BorderSide(color: Colors.white.withOpacity(0.1)),
        ),
      ),
      child: SizedBox(
        width: double.infinity,
        child: ElevatedButton.icon(
          onPressed: _region != null ? _confirmRegion : null,
          icon: Icon(Icons.crop_free, color: Colors.white),
          label: Text(
            _region != null
                ? 'Повторить распознавание'
                : 'Выделите область на фото',
            style: TextStyle(
              color: Colors.white,
              fontSize: 16.sp,
              fontWeight: FontWeight.w600,
            ),
          ),
          style: ElevatedButton.styleFrom(
            backgroundColor:
                _region != null ? Color(0xFFD4AF37) : Colors.grey,
            padding: EdgeInsets.symmetric(vertical: 14.h),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12.r),
            ),
          ),
        ),
      ),
    );
  }

  void _onPanStart(DragStartDetails details, Size displaySize) {
    setState(() {
      _isDrawing = true;
      _startPoint = Offset(
        (details.localPosition.dx / displaySize.width).clamp(0.0, 1.0),
        (details.localPosition.dy / displaySize.height).clamp(0.0, 1.0),
      );
      _currentPoint = _startPoint;
    });
  }

  void _onPanUpdate(DragUpdateDetails details, Size displaySize) {
    if (!_isDrawing) return;
    setState(() {
      _currentPoint = Offset(
        (details.localPosition.dx / displaySize.width).clamp(0.0, 1.0),
        (details.localPosition.dy / displaySize.height).clamp(0.0, 1.0),
      );
    });
  }

  void _onPanEnd() {
    if (!_isDrawing || _startPoint == null || _currentPoint == null) {
      setState(() => _isDrawing = false);
      return;
    }

    final rect = Rect.fromPoints(_startPoint!, _currentPoint!);

    // Минимум 3% по ширине и высоте
    if (rect.width > 0.03 && rect.height > 0.03) {
      setState(() => _region = rect);
    }

    setState(() {
      _isDrawing = false;
      _startPoint = null;
      _currentPoint = null;
    });
  }

  void _confirmRegion() {
    if (_region == null) return;
    Navigator.pop(context, {
      'x': _region!.left,
      'y': _region!.top,
      'width': _region!.width,
      'height': _region!.height,
    });
  }
}

/// CustomPainter для фото + красная рамка выбора области
class _RegionPainter extends CustomPainter {
  final ui.Image image;
  final Rect? region;
  final Rect? currentRect;

  _RegionPainter({
    required this.image,
    this.region,
    this.currentRect,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Рисуем фото
    final srcRect = Rect.fromLTWH(
      0, 0,
      image.width.toDouble(),
      image.height.toDouble(),
    );
    final dstRect = Rect.fromLTWH(0, 0, size.width, size.height);
    canvas.drawImageRect(image, srcRect, dstRect, Paint());

    // Рисуем сохранённую область (красная рамка)
    if (region != null) {
      _drawRegion(canvas, size, region!, Colors.red, 3.0);
    }

    // Рисуем текущую (в процессе рисования) область
    if (currentRect != null) {
      _drawRegion(canvas, size, currentRect!, Colors.red.withOpacity(0.7), 2.0);
    }
  }

  void _drawRegion(Canvas canvas, Size size, Rect rect, Color color, double strokeWidth) {
    final displayRect = Rect.fromLTRB(
      rect.left * size.width,
      rect.top * size.height,
      rect.right * size.width,
      rect.bottom * size.height,
    );

    // Полупрозрачная заливка
    final fillPaint = Paint()
      ..color = color.withOpacity(0.15)
      ..style = PaintingStyle.fill;
    canvas.drawRect(displayRect, fillPaint);

    // Красная рамка
    final borderPaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;
    canvas.drawRect(displayRect, borderPaint);

    // Угловые маркеры (для красивости)
    final markerLen = 15.0;
    final markerPaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth + 1;

    // Верхний левый
    canvas.drawLine(displayRect.topLeft, Offset(displayRect.left + markerLen, displayRect.top), markerPaint);
    canvas.drawLine(displayRect.topLeft, Offset(displayRect.left, displayRect.top + markerLen), markerPaint);
    // Верхний правый
    canvas.drawLine(displayRect.topRight, Offset(displayRect.right - markerLen, displayRect.top), markerPaint);
    canvas.drawLine(displayRect.topRight, Offset(displayRect.right, displayRect.top + markerLen), markerPaint);
    // Нижний левый
    canvas.drawLine(displayRect.bottomLeft, Offset(displayRect.left + markerLen, displayRect.bottom), markerPaint);
    canvas.drawLine(displayRect.bottomLeft, Offset(displayRect.left, displayRect.bottom - markerLen), markerPaint);
    // Нижний правый
    canvas.drawLine(displayRect.bottomRight, Offset(displayRect.right - markerLen, displayRect.bottom), markerPaint);
    canvas.drawLine(displayRect.bottomRight, Offset(displayRect.right, displayRect.bottom - markerLen), markerPaint);
  }

  @override
  bool shouldRepaint(covariant _RegionPainter oldDelegate) => true;
}
