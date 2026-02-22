import 'dart:convert';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

/// Типы полей Z-отчёта для разметки регионов
enum ZReportField {
  totalSum,
  cashSum,
  ofdNotSent,
  resourceKeys,
}

/// Настройки отображения для каждого поля
class _FieldConfig {
  final String label;
  final Color color;
  final IconData icon;

  const _FieldConfig(this.label, this.color, this.icon);
}

const _fieldConfigs = {
  ZReportField.totalSum: _FieldConfig('Выручка', Colors.red, Icons.currency_ruble),
  ZReportField.cashSum: _FieldConfig('Наличные', Colors.blue, Icons.payments_outlined),
  ZReportField.ofdNotSent: _FieldConfig('ОФД', Colors.orange, Icons.cloud_off),
  ZReportField.resourceKeys: _FieldConfig('Ключи', Colors.green, Icons.key),
};

/// Полноэкранный виджет для выделения 4 областей на фото Z-отчёта
/// Сотрудник поочерёдно выбирает поле и рисует прямоугольник вокруг нужного числа
class ZReportRegionSelector extends StatefulWidget {
  final String imageBase64;
  final Map<String, Map<String, double>>? initialRegions;

  const ZReportRegionSelector({
    super.key,
    required this.imageBase64,
    this.initialRegions,
  });

  /// Показать полноэкранный выбор областей
  /// Возвращает { 'totalSum': {x,y,width,height}, 'cashSum': {...}, ... }
  static Future<Map<String, Map<String, double>>?> show(
    BuildContext context, {
    required String imageBase64,
    Map<String, Map<String, double>>? initialRegions,
  }) async {
    return Navigator.of(context).push<Map<String, Map<String, double>>>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => ZReportRegionSelector(
          imageBase64: imageBase64,
          initialRegions: initialRegions,
        ),
      ),
    );
  }

  @override
  State<ZReportRegionSelector> createState() => _ZReportRegionSelectorState();
}

class _ZReportRegionSelectorState extends State<ZReportRegionSelector> {
  ui.Image? _image;
  Size? _imageSize;

  // Текущее активное поле
  ZReportField _activeField = ZReportField.totalSum;

  // Регионы для каждого поля (нормализованные координаты 0.0-1.0)
  final Map<ZReportField, Rect> _regions = {};

  // Состояние рисования
  Offset? _startPoint;
  Offset? _currentPoint;
  bool _isDrawing = false;

  @override
  void initState() {
    super.initState();
    _loadInitialRegions();
    _loadImage();
  }

  void _loadInitialRegions() {
    if (widget.initialRegions == null) return;
    for (final field in ZReportField.values) {
      final key = field.name;
      final r = widget.initialRegions![key];
      if (r != null && r['width'] != null && r['width']! > 0) {
        _regions[field] = Rect.fromLTWH(
          r['x'] ?? 0,
          r['y'] ?? 0,
          r['width'] ?? 0,
          r['height'] ?? 0,
        );
      }
    }
  }

  Future<void> _loadImage() async {
    final cleanBase64 = widget.imageBase64.replaceFirst(
      RegExp(r'^data:image/\w+;base64,'),
      '',
    );
    final bytes = base64Decode(cleanBase64);
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
            colors: [AppColors.emerald, AppColors.night],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              _buildHeader(),
              _buildFieldChips(),
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
                  'Укажите области',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18.sp,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  'Выберите поле и обведите число пальцем',
                  style: TextStyle(color: Colors.white54, fontSize: 13.sp),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFieldChips() {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 6.h),
      child: Row(
        children: ZReportField.values.map((field) {
          final config = _fieldConfigs[field]!;
          final isActive = _activeField == field;
          final hasRegion = _regions.containsKey(field);

          return Expanded(
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 3.w),
              child: GestureDetector(
                onTap: () {
                  if (mounted) setState(() => _activeField = field);
                },
                child: Container(
                  padding: EdgeInsets.symmetric(vertical: 8.h, horizontal: 4.w),
                  decoration: BoxDecoration(
                    color: isActive
                        ? config.color.withOpacity(0.3)
                        : Colors.white.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8.r),
                    border: Border.all(
                      color: isActive ? config.color : Colors.white24,
                      width: isActive ? 2 : 1,
                    ),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        hasRegion ? Icons.check_circle : config.icon,
                        color: hasRegion ? config.color : Colors.white70,
                        size: 18,
                      ),
                      SizedBox(height: 2),
                      Text(
                        config.label,
                        style: TextStyle(
                          color: isActive ? Colors.white : Colors.white70,
                          fontSize: 11.sp,
                          fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        }).toList(),
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

        return Center(
          child: SizedBox(
            width: displaySize.width,
            height: displaySize.height,
            child: GestureDetector(
              onPanStart: (d) => _onPanStart(d, displaySize),
              onPanUpdate: (d) => _onPanUpdate(d, displaySize),
              onPanEnd: (_) => _onPanEnd(),
              child: CustomPaint(
                painter: _MultiRegionPainter(
                  image: _image!,
                  regions: _regions,
                  activeField: _activeField,
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
    final markedCount = _regions.length;

    return Container(
      padding: EdgeInsets.all(16.w),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.3),
        border: Border(
          top: BorderSide(color: Colors.white.withOpacity(0.1)),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_regions.containsKey(_activeField))
            Padding(
              padding: EdgeInsets.only(bottom: 8.h),
              child: TextButton(
                onPressed: () {
                  if (mounted) {
                    setState(() => _regions.remove(_activeField));
                  }
                },
                child: Text(
                  'Сбросить "${_fieldConfigs[_activeField]!.label}"',
                  style: TextStyle(color: Colors.orange, fontSize: 14.sp),
                ),
              ),
            ),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: markedCount >= 1 ? _confirmRegions : null,
              icon: Icon(Icons.check, color: Colors.white),
              label: Text(
                markedCount >= 1
                    ? 'Сохранить ($markedCount из 4)'
                    : 'Отметьте хотя бы 1 область',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16.sp,
                  fontWeight: FontWeight.w600,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor:
                    markedCount >= 1 ? AppColors.gold : Colors.grey,
                padding: EdgeInsets.symmetric(vertical: 14.h),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12.r),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _onPanStart(DragStartDetails details, Size displaySize) {
    if (mounted) {
      setState(() {
        _isDrawing = true;
        _startPoint = Offset(
          (details.localPosition.dx / displaySize.width).clamp(0.0, 1.0),
          (details.localPosition.dy / displaySize.height).clamp(0.0, 1.0),
        );
        _currentPoint = _startPoint;
      });
    }
  }

  void _onPanUpdate(DragUpdateDetails details, Size displaySize) {
    if (!_isDrawing) return;
    if (mounted) {
      setState(() {
        _currentPoint = Offset(
          (details.localPosition.dx / displaySize.width).clamp(0.0, 1.0),
          (details.localPosition.dy / displaySize.height).clamp(0.0, 1.0),
        );
      });
    }
  }

  void _onPanEnd() {
    if (!_isDrawing || _startPoint == null || _currentPoint == null) {
      if (mounted) setState(() => _isDrawing = false);
      return;
    }

    final rect = Rect.fromPoints(_startPoint!, _currentPoint!);

    // Минимум 2% по ширине и высоте
    if (rect.width > 0.02 && rect.height > 0.02) {
      if (mounted) {
        setState(() {
          _regions[_activeField] = rect;
          // Автопереключение на следующее незаполненное поле
          _autoAdvanceField();
        });
      }
    }

    if (mounted) {
      setState(() {
        _isDrawing = false;
        _startPoint = null;
        _currentPoint = null;
      });
    }
  }

  void _autoAdvanceField() {
    // Находим следующее поле без региона
    final fields = ZReportField.values;
    final currentIdx = fields.indexOf(_activeField);
    for (int i = 1; i <= fields.length; i++) {
      final nextField = fields[(currentIdx + i) % fields.length];
      if (!_regions.containsKey(nextField)) {
        _activeField = nextField;
        return;
      }
    }
  }

  void _confirmRegions() {
    final result = <String, Map<String, double>>{};
    for (final entry in _regions.entries) {
      result[entry.key.name] = {
        'x': entry.value.left,
        'y': entry.value.top,
        'width': entry.value.width,
        'height': entry.value.height,
      };
    }
    Navigator.pop(context, result);
  }
}

/// CustomPainter для фото + 4 цветные рамки выбора областей
class _MultiRegionPainter extends CustomPainter {
  final ui.Image image;
  final Map<ZReportField, Rect> regions;
  final ZReportField activeField;
  final Rect? currentRect;

  _MultiRegionPainter({
    required this.image,
    required this.regions,
    required this.activeField,
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

    // Рисуем сохранённые области (каждая своим цветом)
    for (final entry in regions.entries) {
      final config = _fieldConfigs[entry.key]!;
      _drawRegion(canvas, size, entry.value, config.color, 3.0, config.label);
    }

    // Рисуем текущую (в процессе рисования) область
    if (currentRect != null) {
      final config = _fieldConfigs[activeField]!;
      _drawRegion(canvas, size, currentRect!, config.color.withOpacity(0.7), 2.0, null);
    }
  }

  void _drawRegion(Canvas canvas, Size size, Rect rect, Color color, double strokeWidth, String? label) {
    final displayRect = Rect.fromLTRB(
      rect.left * size.width,
      rect.top * size.height,
      rect.right * size.width,
      rect.bottom * size.height,
    );

    // Полупрозрачная заливка
    final fillPaint = Paint()
      ..color = color.withOpacity(0.12)
      ..style = PaintingStyle.fill;
    canvas.drawRect(displayRect, fillPaint);

    // Цветная рамка
    final borderPaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;
    canvas.drawRect(displayRect, borderPaint);

    // Угловые маркеры
    final markerLen = 12.0;
    final markerPaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth + 1;

    canvas.drawLine(displayRect.topLeft, Offset(displayRect.left + markerLen, displayRect.top), markerPaint);
    canvas.drawLine(displayRect.topLeft, Offset(displayRect.left, displayRect.top + markerLen), markerPaint);
    canvas.drawLine(displayRect.topRight, Offset(displayRect.right - markerLen, displayRect.top), markerPaint);
    canvas.drawLine(displayRect.topRight, Offset(displayRect.right, displayRect.top + markerLen), markerPaint);
    canvas.drawLine(displayRect.bottomLeft, Offset(displayRect.left + markerLen, displayRect.bottom), markerPaint);
    canvas.drawLine(displayRect.bottomLeft, Offset(displayRect.left, displayRect.bottom - markerLen), markerPaint);
    canvas.drawLine(displayRect.bottomRight, Offset(displayRect.right - markerLen, displayRect.bottom), markerPaint);
    canvas.drawLine(displayRect.bottomRight, Offset(displayRect.right, displayRect.bottom - markerLen), markerPaint);

    // Метка поля (в верхнем левом углу)
    if (label != null && displayRect.width > 30) {
      final textPainter = TextPainter(
        text: TextSpan(
          text: label,
          style: TextStyle(
            color: Colors.white,
            fontSize: 11,
            fontWeight: FontWeight.bold,
            shadows: [Shadow(color: Colors.black, blurRadius: 3)],
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();

      // Фон под текстом
      final labelRect = Rect.fromLTWH(
        displayRect.left,
        displayRect.top - textPainter.height - 4,
        textPainter.width + 8,
        textPainter.height + 4,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(labelRect, Radius.circular(4)),
        Paint()..color = color.withOpacity(0.85),
      );

      textPainter.paint(canvas, Offset(displayRect.left + 4, displayRect.top - textPainter.height - 2));
    }
  }

  @override
  bool shouldRepaint(covariant _MultiRegionPainter oldDelegate) => true;
}
