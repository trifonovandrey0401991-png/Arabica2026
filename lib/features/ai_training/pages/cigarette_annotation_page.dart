import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../models/cigarette_training_model.dart';
import '../widgets/bounding_box_painter.dart';
import '../services/cigarette_vision_service.dart';

/// Страница разметки фото для обучения ИИ
class CigaretteAnnotationPage extends StatefulWidget {
  final Uint8List imageBytes;
  final CigaretteProduct product;
  final TrainingSampleType type;
  final String? shopAddress;
  final String? employeeName;

  const CigaretteAnnotationPage({
    super.key,
    required this.imageBytes,
    required this.product,
    required this.type,
    this.shopAddress,
    this.employeeName,
  });

  @override
  State<CigaretteAnnotationPage> createState() => _CigaretteAnnotationPageState();
}

class _CigaretteAnnotationPageState extends State<CigaretteAnnotationPage> {
  final GlobalKey<BoundingBoxPainterState> _painterKey = GlobalKey();
  List<Rect> _boxes = [];
  bool _isUploading = false;
  bool _showInstructions = true;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.product.productName,
          style: const TextStyle(fontSize: 14),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          if (_boxes.isNotEmpty)
            TextButton(
              onPressed: _clearAll,
              child: const Text('Очистить', style: TextStyle(color: Colors.red)),
            ),
        ],
      ),
      body: Column(
        children: [
          // Инструкция
          if (_showInstructions)
            Container(
              color: Colors.blue.shade50,
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  const Icon(Icons.info_outline, color: Colors.blue, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Обведите пальцем все пачки "${widget.product.productName}" на фото.\nДвойной тап на рамку — удалить.',
                      style: TextStyle(fontSize: 13, color: Colors.blue.shade800),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 18),
                    onPressed: () => setState(() => _showInstructions = false),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
            ),

          // Область рисования
          Expanded(
            child: Container(
              color: Colors.black,
              child: BoundingBoxPainter(
                key: _painterKey,
                imageBytes: widget.imageBytes,
                onBoxesChanged: (boxes) {
                  setState(() {
                    _boxes = boxes;
                  });
                },
              ),
            ),
          ),

          // Нижняя панель
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 4,
                  offset: const Offset(0, -2),
                ),
              ],
            ),
            child: SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Счётчик рамок
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.crop_free,
                        color: _boxes.isEmpty ? Colors.grey : Colors.green,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Выделено: ${_boxes.length}',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: _boxes.isEmpty ? Colors.grey : Colors.green,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // Кнопки
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: _isUploading ? null : () => Navigator.pop(context),
                          child: const Text('Отмена'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 2,
                        child: ElevatedButton(
                          onPressed: _boxes.isEmpty || _isUploading ? null : _save,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green,
                            foregroundColor: Colors.white,
                          ),
                          child: _isUploading
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Text('Сохранить'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
      // FAB для вызова инструкций
      floatingActionButton: !_showInstructions
          ? FloatingActionButton.small(
              onPressed: _showHelpDialog,
              child: const Icon(Icons.help_outline),
            )
          : null,
    );
  }

  void _clearAll() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Очистить все?'),
        content: const Text('Все нарисованные рамки будут удалены.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Отмена'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _painterKey.currentState?.clearBoxes();
            },
            child: const Text('Очистить', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  Future<void> _save() async {
    if (_boxes.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Выделите хотя бы одну пачку')),
      );
      return;
    }

    setState(() => _isUploading = true);

    try {
      // Конвертируем Rect в AnnotationBox
      final annotations = _boxes.map((rect) {
        // Rect уже нормализован (0-1), но нужно конвертировать в center-width-height
        final width = rect.width.abs();
        final height = rect.height.abs();
        final xCenter = rect.left + width / 2;
        final yCenter = rect.top + height / 2;

        return AnnotationBox(
          xCenter: xCenter.clamp(0.0, 1.0),
          yCenter: yCenter.clamp(0.0, 1.0),
          width: width.clamp(0.0, 1.0),
          height: height.clamp(0.0, 1.0),
        );
      }).toList();

      final success = await CigaretteVisionService.uploadAnnotatedSample(
        imageBytes: widget.imageBytes,
        productId: widget.product.id,
        barcode: widget.product.barcode,
        productName: widget.product.productName,
        type: widget.type,
        boundingBoxes: annotations,
        shopAddress: widget.shopAddress,
        employeeName: widget.employeeName,
      );

      if (!mounted) return;

      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Сохранено! Рамок: ${_boxes.length}'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context, true); // true = успешно сохранено
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Ошибка сохранения'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Ошибка: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isUploading = false);
      }
    }
  }

  void _showHelpDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Как размечать'),
        content: const SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'ПРАВИЛЬНО:',
                style: TextStyle(fontWeight: FontWeight.bold, color: Colors.green),
              ),
              SizedBox(height: 4),
              Text('• Рамка плотно вокруг пачки'),
              Text('• Обведите ВСЕ пачки нужного товара'),
              Text('• Можно размечать частично видимые (>50%)'),
              SizedBox(height: 12),
              Text(
                'НЕПРАВИЛЬНО:',
                style: TextStyle(fontWeight: FontWeight.bold, color: Colors.red),
              ),
              SizedBox(height: 4),
              Text('• Не обводите другие товары'),
              Text('• Не делайте слишком большую рамку'),
              Text('• Не объединяйте несколько пачек'),
              SizedBox(height: 12),
              Text(
                'УПРАВЛЕНИЕ:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              SizedBox(height: 4),
              Text('• Рисуйте пальцем'),
              Text('• Тап на рамку — выделить'),
              Text('• Двойной тап — удалить'),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Понятно'),
          ),
        ],
      ),
    );
  }
}
