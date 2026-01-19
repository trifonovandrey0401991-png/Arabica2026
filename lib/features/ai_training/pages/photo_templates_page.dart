import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../models/photo_template.dart';
import '../models/cigarette_training_model.dart';
import '../widgets/template_overlay_painter.dart';
import 'template_camera_page.dart';
import 'cigarette_annotation_page.dart';

/// Страница со списком 10 шаблонов для фотографирования
class PhotoTemplatesPage extends StatefulWidget {
  final CigaretteProduct product;
  final List<int> completedTemplates;
  final String? shopAddress;
  final String? employeeName;

  const PhotoTemplatesPage({
    super.key,
    required this.product,
    required this.completedTemplates,
    this.shopAddress,
    this.employeeName,
  });

  @override
  State<PhotoTemplatesPage> createState() => _PhotoTemplatesPageState();
}

class _PhotoTemplatesPageState extends State<PhotoTemplatesPage> {
  late List<int> _completedTemplates;

  @override
  void initState() {
    super.initState();
    _completedTemplates = List.from(widget.completedTemplates);
  }

  @override
  Widget build(BuildContext context) {
    final templates = PhotoTemplate.recountTemplates;
    final completedCount = _completedTemplates.length;

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Крупный план',
              style: TextStyle(fontSize: 16),
            ),
            Text(
              widget.product.productName,
              style: const TextStyle(fontSize: 12, color: Colors.white70),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
        backgroundColor: const Color(0xFF004D40),
      ),
      body: Column(
        children: [
          // Прогресс сверху
          Container(
            padding: const EdgeInsets.all(16),
            color: completedCount == 10 ? Colors.green.shade50 : Colors.blue.shade50,
            child: Row(
              children: [
                Icon(
                  completedCount == 10 ? Icons.check_circle : Icons.camera_alt,
                  color: completedCount == 10 ? Colors.green : Colors.blue,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        completedCount == 10
                            ? 'Все шаблоны выполнены!'
                            : 'Выполните все 10 шаблонов',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: completedCount == 10 ? Colors.green : Colors.blue,
                        ),
                      ),
                      const SizedBox(height: 4),
                      LinearProgressIndicator(
                        value: completedCount / 10,
                        backgroundColor: Colors.grey.shade300,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          completedCount == 10 ? Colors.green : Colors.blue,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  '$completedCount/10',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: completedCount == 10 ? Colors.green : Colors.blue,
                  ),
                ),
              ],
            ),
          ),

          // Список шаблонов
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: templates.length,
              itemBuilder: (context, index) {
                final template = templates[index];
                final isCompleted = _completedTemplates.contains(template.id);

                return _buildTemplateCard(template, isCompleted);
              },
            ),
          ),

          // Кнопка готово
          if (completedCount == 10)
            Container(
              padding: const EdgeInsets.all(16),
              child: SafeArea(
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(context, true),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                    child: const Text(
                      'Готово',
                      style: TextStyle(fontSize: 16, color: Colors.white),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildTemplateCard(PhotoTemplate template, bool isCompleted) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: () => _openTemplate(template),
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              // Превью схемы
              Container(
                width: 60,
                height: 80,
                decoration: BoxDecoration(
                  color: isCompleted ? Colors.green.shade50 : Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: isCompleted ? Colors.green : Colors.grey.shade300,
                    width: isCompleted ? 2 : 1,
                  ),
                ),
                child: Stack(
                  children: [
                    // Мини-схема
                    CustomPaint(
                      painter: TemplateOverlayPainter(
                        template: template,
                        overlayColor: isCompleted ? Colors.green : Colors.grey,
                        strokeWidth: 1.5,
                      ),
                      child: const SizedBox.expand(),
                    ),
                    // Галочка если выполнено
                    if (isCompleted)
                      Positioned(
                        right: 2,
                        top: 2,
                        child: Container(
                          padding: const EdgeInsets.all(2),
                          decoration: const BoxDecoration(
                            color: Colors.green,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.check,
                            color: Colors.white,
                            size: 12,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 12),

              // Информация
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: isCompleted ? Colors.green : Colors.grey.shade200,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            '#${template.id}',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: isCompleted ? Colors.white : Colors.grey.shade700,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            template.name,
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: isCompleted ? Colors.green : Colors.black87,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      template.description,
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey.shade600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      template.hint,
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey.shade500,
                        fontStyle: FontStyle.italic,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),

              // Иконка
              Icon(
                isCompleted ? Icons.check_circle : Icons.camera_alt,
                color: isCompleted ? Colors.green : Colors.blue,
                size: 28,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openTemplate(PhotoTemplate template) async {
    // Открываем камеру с overlay
    final Uint8List? imageBytes = await Navigator.push<Uint8List>(
      context,
      MaterialPageRoute(
        builder: (context) => TemplateCameraPage(
          template: template,
          productName: widget.product.productName,
        ),
      ),
    );

    if (imageBytes == null || !mounted) return;

    // Открываем экран разметки
    final bool? annotationResult = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (context) => CigaretteAnnotationPage(
          imageBytes: imageBytes,
          product: widget.product,
          type: TrainingSampleType.recount,
          templateId: template.id,
          shopAddress: widget.shopAddress,
          employeeName: widget.employeeName,
        ),
      ),
    );

    // Если успешно сохранено — отмечаем шаблон как выполненный
    if (annotationResult == true && mounted) {
      setState(() {
        if (!_completedTemplates.contains(template.id)) {
          _completedTemplates.add(template.id);
        }
      });
    }
  }
}
