import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:vector_math/vector_math_64.dart' show Vector3;
import '../models/z_report_template_model.dart';

/// Виджет для выделения областей на изображении Z-отчёта
class RegionSelectorWidget extends StatefulWidget {
  final Uint8List imageBytes;
  final List<FieldRegion> initialRegions;
  final String? currentField; // Какое поле сейчас выделяем
  final Function(List<FieldRegion> regions) onRegionsChanged;

  const RegionSelectorWidget({
    super.key,
    required this.imageBytes,
    this.initialRegions = const [],
    this.currentField,
    required this.onRegionsChanged,
  });

  @override
  State<RegionSelectorWidget> createState() => _RegionSelectorWidgetState();
}

/// Тип ручки для изменения размера
enum _ResizeHandle {
  topLeft,
  topRight,
  bottomLeft,
  bottomRight,
  top,
  bottom,
  left,
  right,
}

class _RegionSelectorWidgetState extends State<RegionSelectorWidget> {
  ui.Image? _image;
  Size? _imageSize;
  List<FieldRegion> _regions = [];

  // Для рисования новой области
  Offset? _startPoint;
  Offset? _currentPoint;
  String? _drawingField;

  // Для масштабирования и перемещения
  final TransformationController _transformController = TransformationController();
  double _currentScale = 1.0;
  bool _isDrawing = false;

  // Для редактирования существующей области
  String? _editingRegionField;
  _ResizeHandle? _activeHandle;
  Rect? _editingRect; // Текущий прямоугольник в displaySize координатах
  Size? _currentDisplaySize; // Текущий размер отображения изображения

  // Цвета для разных полей
  static const Map<String, Color> _fieldColors = {
    'totalSum': Colors.green,
    'cashSum': Colors.blue,
    'ofdNotSent': Colors.orange,
  };

  // Размер ручки для изменения размера
  static const double _handleSize = 20.0;

  @override
  void initState() {
    super.initState();
    _regions = List.from(widget.initialRegions);
    _loadImage();
    _transformController.addListener(_onTransformChanged);
  }

  @override
  void dispose() {
    _transformController.removeListener(_onTransformChanged);
    _transformController.dispose();
    super.dispose();
  }

  void _onTransformChanged() {
    final scale = _transformController.value.getMaxScaleOnAxis();
    if (scale != _currentScale) {
      setState(() {
        _currentScale = scale;
      });
    }
  }

  void _resetZoom() {
    _transformController.value = Matrix4.identity();
  }

  @override
  void didUpdateWidget(RegionSelectorWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.imageBytes != widget.imageBytes) {
      _loadImage();
    }
    if (oldWidget.initialRegions != widget.initialRegions) {
      _regions = List.from(widget.initialRegions);
    }
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

  Color _getFieldColor(String fieldName) {
    return _fieldColors[fieldName] ?? Colors.purple;
  }

  /// Преобразует координаты экрана в координаты изображения с учётом зума и панорамирования
  Offset _transformToImageCoordinates(Offset screenPoint, Size displaySize) {
    // Получаем матрицу трансформации и инвертируем её
    final Matrix4 matrix = _transformController.value.clone();
    final Matrix4 inverseMatrix = Matrix4.inverted(matrix);

    // Применяем инверсную трансформацию к точке
    final vector = inverseMatrix.transform3(
      Vector3(screenPoint.dx, screenPoint.dy, 0),
    );

    // Ограничиваем координаты размерами изображения
    return Offset(
      vector.x.clamp(0, displaySize.width),
      vector.y.clamp(0, displaySize.height),
    );
  }

  void _onPanStart(DragStartDetails details, Size displaySize) {
    if (widget.currentField == null) return;

    setState(() {
      _startPoint = details.localPosition;
      _currentPoint = details.localPosition;
      _drawingField = widget.currentField;
    });
  }

  void _onPanUpdate(DragUpdateDetails details, Size displaySize) {
    if (_startPoint == null) return;

    setState(() {
      _currentPoint = details.localPosition;
    });
  }

  void _onPanEnd(DragEndDetails details, Size displaySize) {
    if (_startPoint == null || _currentPoint == null || _drawingField == null) {
      return;
    }
    if (_imageSize == null) return;

    // Вычисляем прямоугольник
    final rect = Rect.fromPoints(_startPoint!, _currentPoint!);

    // Минимальный размер области (5 пикселей - для узких строк)
    if (rect.width.abs() < 5 && rect.height.abs() < 5) {
      setState(() {
        _startPoint = null;
        _currentPoint = null;
        _drawingField = null;
      });
      return;
    }

    // Преобразуем в относительные координаты
    final scaleX = _imageSize!.width / displaySize.width;
    final scaleY = _imageSize!.height / displaySize.height;

    final region = FieldRegion(
      fieldName: _drawingField!,
      x: (rect.left * scaleX) / _imageSize!.width,
      y: (rect.top * scaleY) / _imageSize!.height,
      width: (rect.width * scaleX) / _imageSize!.width,
      height: (rect.height * scaleY) / _imageSize!.height,
    );

    // Удаляем старую область для этого поля и добавляем новую
    setState(() {
      _regions.removeWhere((r) => r.fieldName == _drawingField);
      _regions.add(region);
      _startPoint = null;
      _currentPoint = null;
      _drawingField = null;
    });

    widget.onRegionsChanged(_regions);
  }

  void _removeRegion(String fieldName) {
    setState(() {
      _regions.removeWhere((r) => r.fieldName == fieldName);
      if (_editingRegionField == fieldName) {
        _editingRegionField = null;
        _editingRect = null;
        _activeHandle = null;
      }
    });
    widget.onRegionsChanged(_regions);
  }

  /// Начать редактирование области
  void _startEditingRegion(String fieldName) {
    if (_currentDisplaySize == null || _imageSize == null) return;

    final region = _regions.firstWhere(
      (r) => r.fieldName == fieldName,
      orElse: () => FieldRegion(fieldName: '', x: 0, y: 0, width: 0, height: 0),
    );
    if (region.fieldName.isEmpty) return;

    final scaleX = _currentDisplaySize!.width / _imageSize!.width;
    final scaleY = _currentDisplaySize!.height / _imageSize!.height;

    setState(() {
      _editingRegionField = fieldName;
      _editingRect = Rect.fromLTWH(
        region.x * _imageSize!.width * scaleX,
        region.y * _imageSize!.height * scaleY,
        region.width * _imageSize!.width * scaleX,
        region.height * _imageSize!.height * scaleY,
      );
    });
  }

  /// Завершить редактирование и сохранить изменения
  void _finishEditingRegion(Size displaySize) {
    if (_editingRegionField == null || _editingRect == null || _imageSize == null) {
      return;
    }

    final scaleX = _imageSize!.width / displaySize.width;
    final scaleY = _imageSize!.height / displaySize.height;

    // Нормализуем прямоугольник (положительные width/height)
    final normalizedRect = Rect.fromLTRB(
      _editingRect!.left < _editingRect!.right ? _editingRect!.left : _editingRect!.right,
      _editingRect!.top < _editingRect!.bottom ? _editingRect!.top : _editingRect!.bottom,
      _editingRect!.left > _editingRect!.right ? _editingRect!.left : _editingRect!.right,
      _editingRect!.top > _editingRect!.bottom ? _editingRect!.top : _editingRect!.bottom,
    );

    final newRegion = FieldRegion(
      fieldName: _editingRegionField!,
      x: (normalizedRect.left * scaleX) / _imageSize!.width,
      y: (normalizedRect.top * scaleY) / _imageSize!.height,
      width: (normalizedRect.width * scaleX) / _imageSize!.width,
      height: (normalizedRect.height * scaleY) / _imageSize!.height,
    );

    setState(() {
      _regions.removeWhere((r) => r.fieldName == _editingRegionField);
      _regions.add(newRegion);
      _editingRegionField = null;
      _editingRect = null;
      _activeHandle = null;
    });

    widget.onRegionsChanged(_regions);
  }

  /// Отменить редактирование
  void _cancelEditingRegion() {
    setState(() {
      _editingRegionField = null;
      _editingRect = null;
      _activeHandle = null;
    });
  }

  /// Обработка перетаскивания ручки
  void _onHandleDrag(Offset delta) {
    if (_editingRect == null || _activeHandle == null || _currentDisplaySize == null) return;

    setState(() {
      double left = _editingRect!.left;
      double top = _editingRect!.top;
      double right = _editingRect!.right;
      double bottom = _editingRect!.bottom;

      switch (_activeHandle!) {
        case _ResizeHandle.topLeft:
          left += delta.dx;
          top += delta.dy;
          break;
        case _ResizeHandle.topRight:
          right += delta.dx;
          top += delta.dy;
          break;
        case _ResizeHandle.bottomLeft:
          left += delta.dx;
          bottom += delta.dy;
          break;
        case _ResizeHandle.bottomRight:
          right += delta.dx;
          bottom += delta.dy;
          break;
        case _ResizeHandle.top:
          top += delta.dy;
          break;
        case _ResizeHandle.bottom:
          bottom += delta.dy;
          break;
        case _ResizeHandle.left:
          left += delta.dx;
          break;
        case _ResizeHandle.right:
          right += delta.dx;
          break;
      }

      // Ограничиваем размерами изображения
      left = left.clamp(0, _currentDisplaySize!.width);
      top = top.clamp(0, _currentDisplaySize!.height);
      right = right.clamp(0, _currentDisplaySize!.width);
      bottom = bottom.clamp(0, _currentDisplaySize!.height);

      _editingRect = Rect.fromLTRB(left, top, right, bottom);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_image == null) {
      return const Center(child: CircularProgressIndicator());
    }

    return Column(
      children: [
        // Легенда и кнопки управления
        _buildLegend(),
        const SizedBox(height: 4),
        // Панель масштабирования
        _buildZoomControls(),
        const SizedBox(height: 8),
        // Изображение с областями
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              // Вычисляем размер для отображения с сохранением пропорций
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

              // Сохраняем displaySize для использования в других методах
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (_currentDisplaySize != displaySize) {
                  _currentDisplaySize = displaySize;
                }
              });

              return Center(
                child: InteractiveViewer(
                  transformationController: _transformController,
                  minScale: 1.0,
                  maxScale: 5.0,
                  panEnabled: widget.currentField == null, // Перемещение только когда не рисуем
                  scaleEnabled: true,
                  onInteractionStart: (details) {
                    // Начинаем рисование только если выбрано поле и один палец
                    if (widget.currentField != null && details.pointerCount == 1) {
                      setState(() => _isDrawing = true);
                      // Трансформируем координаты с учётом масштаба
                      final transformedPoint = _transformToImageCoordinates(
                        details.localFocalPoint,
                        displaySize,
                      );
                      _onPanStart(
                        DragStartDetails(
                          localPosition: transformedPoint,
                          globalPosition: details.focalPoint,
                        ),
                        displaySize,
                      );
                    }
                  },
                  onInteractionUpdate: (details) {
                    if (_isDrawing && details.pointerCount == 1) {
                      // Трансформируем координаты с учётом масштаба
                      final transformedPoint = _transformToImageCoordinates(
                        details.localFocalPoint,
                        displaySize,
                      );
                      _onPanUpdate(
                        DragUpdateDetails(
                          localPosition: transformedPoint,
                          globalPosition: details.focalPoint,
                          delta: Offset.zero,
                        ),
                        displaySize,
                      );
                    }
                  },
                  onInteractionEnd: (details) {
                    if (_isDrawing) {
                      _onPanEnd(DragEndDetails(), displaySize);
                      setState(() => _isDrawing = false);
                    }
                  },
                  child: SizedBox(
                    width: displaySize.width,
                    height: displaySize.height,
                    child: Stack(
                      children: [
                        // Изображение
                        Image.memory(
                          widget.imageBytes,
                          fit: BoxFit.contain,
                          width: displaySize.width,
                          height: displaySize.height,
                        ),
                        // Существующие области
                        ..._buildRegionOverlays(displaySize),
                        // Редактируемая область с ручками
                        _buildEditableRegion(displaySize),
                        // Текущая рисуемая область
                        if (_startPoint != null && _currentPoint != null)
                          _buildDrawingRect(),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildZoomControls() {
    return Column(
      children: [
        // Панель редактирования (если редактируем область)
        if (_editingRegionField != null)
          Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            decoration: BoxDecoration(
              color: _getFieldColor(_editingRegionField!).withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: _getFieldColor(_editingRegionField!)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.edit,
                  size: 14,
                  color: _getFieldColor(_editingRegionField!),
                ),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(
                    FieldNames.getDisplayName(_editingRegionField!),
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: _getFieldColor(_editingRegionField!),
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                // Кнопка отмены
                GestureDetector(
                  onTap: _cancelEditingRegion,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: Colors.red.withOpacity(0.1),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.close, size: 16, color: Colors.red),
                  ),
                ),
                const SizedBox(width: 6),
                // Кнопка подтверждения
                GestureDetector(
                  onTap: () {
                    if (_currentDisplaySize != null) {
                      _finishEditingRegion(_currentDisplaySize!);
                    }
                  },
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: Colors.green.withOpacity(0.1),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.check, size: 16, color: Colors.green),
                  ),
                ),
              ],
            ),
          ),
        // Панель зума
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Кнопка уменьшить
            IconButton(
              onPressed: () {
                final newScale = (_currentScale - 0.5).clamp(1.0, 5.0);
                _transformController.value = Matrix4.identity()..scale(newScale);
              },
              icon: const Icon(Icons.remove_circle_outline),
              tooltip: 'Уменьшить',
              iconSize: 28,
            ),
            // Индикатор масштаба
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.grey[200],
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                '${(_currentScale * 100).toInt()}%',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
            // Кнопка увеличить
            IconButton(
              onPressed: () {
                final newScale = (_currentScale + 0.5).clamp(1.0, 5.0);
                _transformController.value = Matrix4.identity()..scale(newScale);
              },
              icon: const Icon(Icons.add_circle_outline),
              tooltip: 'Увеличить',
              iconSize: 28,
            ),
            const SizedBox(width: 8),
            // Кнопка сброса
            TextButton.icon(
              onPressed: _resetZoom,
              icon: const Icon(Icons.fit_screen, size: 18),
              label: const Text('Сброс'),
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 8),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildLegend() {
    return Wrap(
      spacing: 8,
      runSpacing: 4,
      children: FieldNames.all.map((fieldName) {
        final hasRegion = _regions.any((r) => r.fieldName == fieldName);
        final isSelected = widget.currentField == fieldName;
        final color = _getFieldColor(fieldName);

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: isSelected ? color.withOpacity(0.3) : Colors.transparent,
            border: Border.all(
              color: color,
              width: isSelected ? 2 : 1,
            ),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: hasRegion ? color : Colors.transparent,
                  border: Border.all(color: color),
                ),
              ),
              const SizedBox(width: 4),
              Text(
                FieldNames.getDisplayName(fieldName),
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                ),
              ),
              if (hasRegion) ...[
                const SizedBox(width: 4),
                GestureDetector(
                  onTap: () => _removeRegion(fieldName),
                  child: Icon(Icons.close, size: 14, color: color),
                ),
              ],
            ],
          ),
        );
      }).toList(),
    );
  }

  List<Widget> _buildRegionOverlays(Size displaySize) {
    if (_imageSize == null) return [];

    final scaleX = displaySize.width / _imageSize!.width;
    final scaleY = displaySize.height / _imageSize!.height;

    final List<Widget> widgets = [];

    for (final region in _regions) {
      // Пропускаем редактируемую область - она рисуется отдельно
      if (region.fieldName == _editingRegionField) continue;

      final rect = Rect.fromLTWH(
        region.x * _imageSize!.width * scaleX,
        region.y * _imageSize!.height * scaleY,
        region.width * _imageSize!.width * scaleX,
        region.height * _imageSize!.height * scaleY,
      );
      final color = _getFieldColor(region.fieldName);

      widgets.add(
        Positioned(
          left: rect.left,
          top: rect.top,
          width: rect.width,
          height: rect.height,
          child: GestureDetector(
            onTap: () => _startEditingRegion(region.fieldName),
            child: Container(
              decoration: BoxDecoration(
                border: Border.all(color: color, width: 1),
                color: color.withOpacity(0.15),
              ),
            ),
          ),
        ),
      );
    }

    return widgets;
  }

  /// Строит редактируемую область с ручками изменения размера
  Widget _buildEditableRegion(Size displaySize) {
    if (_editingRect == null || _editingRegionField == null) {
      return const SizedBox.shrink();
    }

    final color = _getFieldColor(_editingRegionField!);
    final rect = _editingRect!;

    // Нормализуем для отображения
    final normalizedRect = Rect.fromLTRB(
      rect.left < rect.right ? rect.left : rect.right,
      rect.top < rect.bottom ? rect.top : rect.bottom,
      rect.left > rect.right ? rect.left : rect.right,
      rect.top > rect.bottom ? rect.top : rect.bottom,
    );

    return Stack(
      children: [
        // Основная область
        Positioned(
          left: normalizedRect.left,
          top: normalizedRect.top,
          width: normalizedRect.width,
          height: normalizedRect.height,
          child: Container(
            decoration: BoxDecoration(
              border: Border.all(color: color, width: 1.5),
              color: color.withOpacity(0.2),
            ),
          ),
        ),
        // Ручки по углам
        _buildHandle(normalizedRect.topLeft, _ResizeHandle.topLeft, color),
        _buildHandle(normalizedRect.topRight, _ResizeHandle.topRight, color),
        _buildHandle(normalizedRect.bottomLeft, _ResizeHandle.bottomLeft, color),
        _buildHandle(normalizedRect.bottomRight, _ResizeHandle.bottomRight, color),
        // Ручки по сторонам
        _buildHandle(
          Offset(normalizedRect.center.dx, normalizedRect.top),
          _ResizeHandle.top,
          color,
        ),
        _buildHandle(
          Offset(normalizedRect.center.dx, normalizedRect.bottom),
          _ResizeHandle.bottom,
          color,
        ),
        _buildHandle(
          Offset(normalizedRect.left, normalizedRect.center.dy),
          _ResizeHandle.left,
          color,
        ),
        _buildHandle(
          Offset(normalizedRect.right, normalizedRect.center.dy),
          _ResizeHandle.right,
          color,
        ),
      ],
    );
  }

  /// Строит ручку для изменения размера
  Widget _buildHandle(Offset position, _ResizeHandle handle, Color color) {
    return Positioned(
      left: position.dx - _handleSize / 2,
      top: position.dy - _handleSize / 2,
      width: _handleSize,
      height: _handleSize,
      child: GestureDetector(
        onPanStart: (_) {
          setState(() => _activeHandle = handle);
        },
        onPanUpdate: (details) {
          // Трансформируем дельту с учётом зума
          final scaledDelta = Offset(
            details.delta.dx / _currentScale,
            details.delta.dy / _currentScale,
          );
          _onHandleDrag(scaledDelta);
        },
        onPanEnd: (_) {
          setState(() => _activeHandle = null);
        },
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border.all(color: color, width: 2),
            shape: BoxShape.circle,
          ),
          child: Center(
            child: Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDrawingRect() {
    final rect = Rect.fromPoints(_startPoint!, _currentPoint!);
    final color = _getFieldColor(_drawingField ?? '');

    return Positioned(
      left: rect.left,
      top: rect.top,
      width: rect.width.abs(),
      height: rect.height.abs(),
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(color: color, width: 1),
          color: color.withOpacity(0.15),
        ),
      ),
    );
  }
}
