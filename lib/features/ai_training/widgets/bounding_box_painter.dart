import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';

/// Виджет для рисования bounding boxes на изображении
class BoundingBoxPainter extends StatefulWidget {
  final Uint8List imageBytes;
  final List<Rect> initialBoxes;
  final Function(List<Rect>) onBoxesChanged;
  final Color boxColor;
  final double boxStrokeWidth;

  const BoundingBoxPainter({
    super.key,
    required this.imageBytes,
    this.initialBoxes = const [],
    required this.onBoxesChanged,
    this.boxColor = Colors.green,
    this.boxStrokeWidth = 2.0,
  });

  @override
  BoundingBoxPainterState createState() => BoundingBoxPainterState();
}

class BoundingBoxPainterState extends State<BoundingBoxPainter> {
  ui.Image? _image;
  Size? _imageSize;
  List<Rect> _boxes = [];

  // Состояние рисования
  Offset? _startPoint;
  Offset? _currentPoint;
  bool _isDrawing = false;

  // Состояние удаления
  int? _selectedBoxIndex;

  @override
  void initState() {
    super.initState();
    _boxes = List.from(widget.initialBoxes);
    _loadImage();
  }

  Future<void> _loadImage() async {
    final codec = await ui.instantiateImageCodec(widget.imageBytes);
    final frame = await codec.getNextFrame();
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
    if (_image == null) {
      return const Center(child: CircularProgressIndicator());
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        // Вычисляем размер отображаемого изображения
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
          onPanStart: (details) => _onPanStart(details, displaySize),
          onPanUpdate: (details) => _onPanUpdate(details, displaySize),
          onPanEnd: (details) => _onPanEnd(displaySize),
          onTapUp: (details) => _onTap(details, displaySize),
          child: Center(
            child: SizedBox(
              width: displaySize.width,
              height: displaySize.height,
              child: CustomPaint(
                painter: _BoxPainter(
                  image: _image!,
                  boxes: _boxes,
                  currentRect: _isDrawing && _startPoint != null && _currentPoint != null
                      ? Rect.fromPoints(_startPoint!, _currentPoint!)
                      : null,
                  selectedIndex: _selectedBoxIndex,
                  boxColor: widget.boxColor,
                  strokeWidth: widget.boxStrokeWidth,
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  void _onPanStart(DragStartDetails details, Size displaySize) {
    final localPosition = details.localPosition;

    // Проверяем, не попали ли в существующий box для выделения
    final normalizedX = localPosition.dx / displaySize.width;
    final normalizedY = localPosition.dy / displaySize.height;

    int? tappedIndex;
    for (int i = _boxes.length - 1; i >= 0; i--) {
      if (_boxes[i].contains(Offset(normalizedX, normalizedY))) {
        tappedIndex = i;
        break;
      }
    }

    if (tappedIndex != null) {
      // Выделяем box для удаления
      setState(() {
        _selectedBoxIndex = tappedIndex;
      });
    } else {
      // Начинаем рисовать новый box
      setState(() {
        _selectedBoxIndex = null;
        _isDrawing = true;
        _startPoint = Offset(
          localPosition.dx / displaySize.width,
          localPosition.dy / displaySize.height,
        );
        _currentPoint = _startPoint;
      });
    }
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

  void _onPanEnd(Size displaySize) {
    if (!_isDrawing || _startPoint == null || _currentPoint == null) {
      setState(() {
        _isDrawing = false;
      });
      return;
    }

    // Создаём rect из точек
    final rect = Rect.fromPoints(_startPoint!, _currentPoint!);

    // Минимальный размер 2% от изображения
    if (rect.width > 0.02 && rect.height > 0.02) {
      setState(() {
        _boxes.add(rect);
      });
      widget.onBoxesChanged(_boxes);
    }

    setState(() {
      _isDrawing = false;
      _startPoint = null;
      _currentPoint = null;
    });
  }

  void _onTap(TapUpDetails details, Size displaySize) {
    final normalizedX = details.localPosition.dx / displaySize.width;
    final normalizedY = details.localPosition.dy / displaySize.height;

    // Проверяем попадание в существующий box
    for (int i = _boxes.length - 1; i >= 0; i--) {
      if (_boxes[i].contains(Offset(normalizedX, normalizedY))) {
        if (_selectedBoxIndex == i) {
          // Повторный тап — удаляем
          setState(() {
            _boxes.removeAt(i);
            _selectedBoxIndex = null;
          });
          widget.onBoxesChanged(_boxes);
        } else {
          // Первый тап — выделяем
          setState(() {
            _selectedBoxIndex = i;
          });
        }
        return;
      }
    }

    // Тап в пустое место — снять выделение
    setState(() {
      _selectedBoxIndex = null;
    });
  }

  /// Очистить все рамки
  void clearBoxes() {
    setState(() {
      _boxes.clear();
      _selectedBoxIndex = null;
    });
    widget.onBoxesChanged(_boxes);
  }

  /// Удалить выбранную рамку
  void deleteSelected() {
    if (_selectedBoxIndex != null && _selectedBoxIndex! < _boxes.length) {
      setState(() {
        _boxes.removeAt(_selectedBoxIndex!);
        _selectedBoxIndex = null;
      });
      widget.onBoxesChanged(_boxes);
    }
  }

  /// Получить список рамок
  List<Rect> get boxes => List.from(_boxes);
}

/// CustomPainter для отрисовки изображения и рамок
class _BoxPainter extends CustomPainter {
  final ui.Image image;
  final List<Rect> boxes;
  final Rect? currentRect;
  final int? selectedIndex;
  final Color boxColor;
  final double strokeWidth;

  _BoxPainter({
    required this.image,
    required this.boxes,
    this.currentRect,
    this.selectedIndex,
    required this.boxColor,
    required this.strokeWidth,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Рисуем изображение
    final srcRect = Rect.fromLTWH(
      0,
      0,
      image.width.toDouble(),
      image.height.toDouble(),
    );
    final dstRect = Rect.fromLTWH(0, 0, size.width, size.height);
    canvas.drawImageRect(image, srcRect, dstRect, Paint());

    // Рисуем существующие рамки
    final boxPaint = Paint()
      ..color = boxColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;

    final selectedPaint = Paint()
      ..color = Colors.red
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth + 1;

    final fillPaint = Paint()
      ..color = boxColor.withOpacity(0.2)
      ..style = PaintingStyle.fill;

    for (int i = 0; i < boxes.length; i++) {
      final box = boxes[i];
      final displayRect = Rect.fromLTRB(
        box.left * size.width,
        box.top * size.height,
        box.right * size.width,
        box.bottom * size.height,
      );

      // Заливка
      canvas.drawRect(displayRect, fillPaint);

      // Рамка
      canvas.drawRect(
        displayRect,
        i == selectedIndex ? selectedPaint : boxPaint,
      );

      // Номер рамки
      final textPainter = TextPainter(
        text: TextSpan(
          text: '${i + 1}',
          style: TextStyle(
            color: Colors.white,
            fontSize: 14,
            fontWeight: FontWeight.bold,
            backgroundColor: i == selectedIndex ? Colors.red : boxColor,
          ),
        ),
        textDirection: TextDirection.ltr,
      );
      textPainter.layout();
      textPainter.paint(
        canvas,
        Offset(displayRect.left + 4, displayRect.top + 4),
      );
    }

    // Рисуем текущую (рисуемую) рамку
    if (currentRect != null) {
      final displayRect = Rect.fromLTRB(
        currentRect!.left * size.width,
        currentRect!.top * size.height,
        currentRect!.right * size.width,
        currentRect!.bottom * size.height,
      );

      final drawingPaint = Paint()
        ..color = Colors.blue
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth;

      canvas.drawRect(displayRect, drawingPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _BoxPainter oldDelegate) {
    return true; // Всегда перерисовывать для плавности
  }
}
