import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../models/training_model.dart';
import '../models/content_block.dart';
import '../services/training_article_service.dart';

/// Страница редактора статьи обучения с поддержкой блоков контента
class TrainingArticleEditorPage extends StatefulWidget {
  final TrainingArticle? article;

  const TrainingArticleEditorPage({super.key, this.article});

  @override
  State<TrainingArticleEditorPage> createState() => _TrainingArticleEditorPageState();
}

class _TrainingArticleEditorPageState extends State<TrainingArticleEditorPage> {
  static const _primaryColor = Color(0xFF004D40);
  static const _gradientStart = Color(0xFF00695C);
  static const _gradientEnd = Color(0xFF004D40);

  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _groupController = TextEditingController();
  final _urlController = TextEditingController();

  List<ContentBlock> _contentBlocks = [];
  bool _isSaving = false;
  bool _showUrlField = false;
  final ImagePicker _imagePicker = ImagePicker();

  @override
  void initState() {
    super.initState();
    if (widget.article != null) {
      _titleController.text = widget.article!.title;
      _groupController.text = widget.article!.group;
      _urlController.text = widget.article!.url ?? '';
      _showUrlField = widget.article!.hasUrl;

      // Загружаем блоки контента
      if (widget.article!.contentBlocks.isNotEmpty) {
        _contentBlocks = List.from(widget.article!.contentBlocks);
      } else if (widget.article!.content.isNotEmpty) {
        // Мигрируем старый контент в блок текста
        _contentBlocks = [ContentBlock.text(widget.article!.content)];
      }
    }

    // Если нет блоков, добавляем пустой текстовый блок
    if (_contentBlocks.isEmpty) {
      _contentBlocks.add(ContentBlock.text(''));
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _groupController.dispose();
    _urlController.dispose();
    super.dispose();
  }

  void _addTextBlock() {
    setState(() {
      _contentBlocks.add(ContentBlock(
        id: 'block_${DateTime.now().millisecondsSinceEpoch}',
        type: ContentBlockType.text,
        content: '',
      ));
    });
  }

  Future<void> _addImageBlock() async {
    try {
      final XFile? image = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1920,
        maxHeight: 1920,
        imageQuality: 85,
      );

      if (image == null) return;

      // Показываем индикатор загрузки
      if (!mounted) return;
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(
          child: Card(
            child: Padding(
              padding: EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(color: _primaryColor),
                  SizedBox(height: 16),
                  Text('Загрузка изображения...'),
                ],
              ),
            ),
          ),
        ),
      );

      // Загружаем изображение на сервер
      final imageUrl = await TrainingArticleService.uploadImage(File(image.path));

      if (!mounted) return;
      Navigator.pop(context); // Закрываем индикатор

      if (imageUrl != null) {
        setState(() {
          _contentBlocks.add(ContentBlock.image(imageUrl));
        });
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Ошибка загрузки изображения'),
            backgroundColor: Colors.red[600],
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context); // Закрываем индикатор если открыт
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка: $e'),
            backgroundColor: Colors.red[600],
          ),
        );
      }
    }
  }

  void _removeBlock(int index) {
    if (_contentBlocks.length > 1) {
      setState(() {
        _contentBlocks.removeAt(index);
      });
    }
  }

  void _moveBlockUp(int index) {
    if (index > 0) {
      setState(() {
        final block = _contentBlocks.removeAt(index);
        _contentBlocks.insert(index - 1, block);
      });
    }
  }

  void _moveBlockDown(int index) {
    if (index < _contentBlocks.length - 1) {
      setState(() {
        final block = _contentBlocks.removeAt(index);
        _contentBlocks.insert(index + 1, block);
      });
    }
  }

  void _updateTextBlock(int index, String text) {
    setState(() {
      _contentBlocks[index] = _contentBlocks[index].copyWith(content: text);
    });
  }

  void _updateImageCaption(int index, String caption) {
    setState(() {
      _contentBlocks[index] = _contentBlocks[index].copyWith(caption: caption);
    });
  }

  bool _isValidUrl(String url) {
    if (url.isEmpty) return true;
    try {
      final uri = Uri.parse(url);
      return uri.hasScheme && (uri.scheme == 'http' || uri.scheme == 'https');
    } catch (e) {
      return false;
    }
  }

  Future<void> _saveArticle() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    // Проверяем что есть хоть какой-то контент
    final hasContent = _contentBlocks.any((b) =>
      (b.type == ContentBlockType.text && b.content.trim().isNotEmpty) ||
      (b.type == ContentBlockType.image && b.content.isNotEmpty)
    );

    if (!hasContent && !_showUrlField) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Добавьте контент статьи или внешнюю ссылку'),
          backgroundColor: Colors.orange[600],
        ),
      );
      return;
    }

    setState(() {
      _isSaving = true;
    });

    try {
      // Фильтруем пустые текстовые блоки
      final filteredBlocks = _contentBlocks.where((b) =>
        (b.type == ContentBlockType.text && b.content.trim().isNotEmpty) ||
        (b.type == ContentBlockType.image && b.content.isNotEmpty)
      ).toList();

      // Формируем простой контент из текстовых блоков для обратной совместимости
      final simpleContent = filteredBlocks
          .where((b) => b.type == ContentBlockType.text)
          .map((b) => b.content.trim())
          .join('\n\n');

      TrainingArticle? result;
      final url = _showUrlField ? _urlController.text.trim() : null;

      if (widget.article != null) {
        result = await TrainingArticleService.updateArticle(
          id: widget.article!.id,
          group: _groupController.text.trim(),
          title: _titleController.text.trim(),
          content: simpleContent,
          url: url,
          contentBlocks: filteredBlocks,
        );
      } else {
        result = await TrainingArticleService.createArticle(
          group: _groupController.text.trim(),
          title: _titleController.text.trim(),
          content: simpleContent,
          url: url,
          contentBlocks: filteredBlocks,
        );
      }

      if (result != null && mounted) {
        Navigator.pop(context, result);
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Ошибка сохранения статьи'),
              backgroundColor: Colors.red[600],
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка: $e'),
            backgroundColor: Colors.red[600],
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.article != null;

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [_gradientStart, _gradientEnd],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              _buildAppBar(isEditing),
              Expanded(
                child: Container(
                  decoration: const BoxDecoration(
                    color: Color(0xFFF5F5F5),
                    borderRadius: BorderRadius.only(
                      topLeft: Radius.circular(24),
                      topRight: Radius.circular(24),
                    ),
                  ),
                  child: ClipRRect(
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(24),
                      topRight: Radius.circular(24),
                    ),
                    child: _buildContent(),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAppBar(bool isEditing) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 16),
      child: Row(
        children: [
          Container(
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: IconButton(
              icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 20),
              onPressed: () => Navigator.pop(context),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isEditing ? 'Редактировать статью' : 'Новая статья',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  '${_contentBlocks.length} ${_getBlocksEnding(_contentBlocks.length)}',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.8),
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
          // Кнопка сохранения
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
            ),
            child: IconButton(
              icon: _isSaving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: _primaryColor,
                      ),
                    )
                  : const Icon(Icons.check_rounded, color: _primaryColor, size: 24),
              onPressed: _isSaving ? null : _saveArticle,
            ),
          ),
        ],
      ),
    );
  }

  String _getBlocksEnding(int count) {
    if (count % 100 >= 11 && count % 100 <= 19) return 'блоков';
    switch (count % 10) {
      case 1: return 'блок';
      case 2:
      case 3:
      case 4: return 'блока';
      default: return 'блоков';
    }
  }

  Widget _buildContent() {
    return Form(
      key: _formKey,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Основная информация
          _buildInfoCard(),
          const SizedBox(height: 16),

          // Блоки контента
          _buildContentBlocksSection(),
          const SizedBox(height: 16),

          // Кнопки добавления блоков
          _buildAddBlockButtons(),
          const SizedBox(height: 16),

          // Внешняя ссылка
          _buildUrlSection(),

          const SizedBox(height: 80),
        ],
      ),
    );
  }

  Widget _buildInfoCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: _primaryColor.withOpacity(0.08),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: _primaryColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.info_outline, color: _primaryColor, size: 20),
              ),
              const SizedBox(width: 12),
              const Text(
                'Основная информация',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: _primaryColor,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _buildTextField(
            controller: _titleController,
            label: 'Название статьи',
            hint: 'Введите название',
            icon: Icons.title_rounded,
            validator: (value) {
              if (value == null || value.trim().isEmpty) {
                return 'Введите название статьи';
              }
              return null;
            },
          ),
          const SizedBox(height: 12),
          _buildTextField(
            controller: _groupController,
            label: 'Группа',
            hint: 'Введите группу',
            icon: Icons.folder_rounded,
            validator: (value) {
              if (value == null || value.trim().isEmpty) {
                return 'Введите группу';
              }
              return null;
            },
          ),
        ],
      ),
    );
  }

  Widget _buildContentBlocksSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: _primaryColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.view_agenda_rounded, color: _primaryColor, size: 20),
            ),
            const SizedBox(width: 12),
            const Text(
              'Контент статьи',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: _primaryColor,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        ...List.generate(_contentBlocks.length, (index) {
          final block = _contentBlocks[index];
          return _buildContentBlockCard(block, index);
        }),
      ],
    );
  }

  Widget _buildContentBlockCard(ContentBlock block, int index) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: _primaryColor.withOpacity(0.06),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Заголовок блока с кнопками
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: block.type == ContentBlockType.image
                  ? Colors.blue.withOpacity(0.08)
                  : _primaryColor.withOpacity(0.05),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(16),
                topRight: Radius.circular(16),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  block.type == ContentBlockType.image
                      ? Icons.image_rounded
                      : Icons.text_fields_rounded,
                  size: 18,
                  color: block.type == ContentBlockType.image
                      ? Colors.blue[600]
                      : _primaryColor,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    block.type == ContentBlockType.image ? 'Изображение' : 'Текст',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: block.type == ContentBlockType.image
                          ? Colors.blue[700]
                          : _primaryColor,
                    ),
                  ),
                ),
                // Кнопки управления
                _buildBlockActionButton(
                  icon: Icons.keyboard_arrow_up_rounded,
                  onTap: index > 0 ? () => _moveBlockUp(index) : null,
                ),
                _buildBlockActionButton(
                  icon: Icons.keyboard_arrow_down_rounded,
                  onTap: index < _contentBlocks.length - 1 ? () => _moveBlockDown(index) : null,
                ),
                _buildBlockActionButton(
                  icon: Icons.delete_outline_rounded,
                  color: Colors.red[400],
                  onTap: _contentBlocks.length > 1 ? () => _removeBlock(index) : null,
                ),
              ],
            ),
          ),
          // Контент блока
          Padding(
            padding: const EdgeInsets.all(12),
            child: block.type == ContentBlockType.image
                ? _buildImageBlockContent(block, index)
                : _buildTextBlockContent(block, index),
          ),
        ],
      ),
    );
  }

  Widget _buildBlockActionButton({
    required IconData icon,
    Color? color,
    VoidCallback? onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.all(4),
        child: Icon(
          icon,
          size: 20,
          color: onTap != null ? (color ?? Colors.grey[600]) : Colors.grey[300],
        ),
      ),
    );
  }

  Widget _buildTextBlockContent(ContentBlock block, int index) {
    return TextFormField(
      initialValue: block.content,
      maxLines: null,
      minLines: 3,
      style: const TextStyle(fontSize: 14, height: 1.6),
      decoration: InputDecoration(
        hintText: 'Введите текст...',
        hintStyle: TextStyle(color: Colors.grey[400]),
        filled: true,
        fillColor: Colors.grey[50],
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey[200]!),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey[200]!),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: _primaryColor, width: 2),
        ),
        contentPadding: const EdgeInsets.all(14),
      ),
      onChanged: (value) => _updateTextBlock(index, value),
    );
  }

  Widget _buildImageBlockContent(ContentBlock block, int index) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Превью изображения
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Image.network(
            block.content,
            width: double.infinity,
            height: 200,
            fit: BoxFit.cover,
            loadingBuilder: (context, child, loadingProgress) {
              if (loadingProgress == null) return child;
              return Container(
                width: double.infinity,
                height: 200,
                color: Colors.grey[100],
                child: Center(
                  child: CircularProgressIndicator(
                    value: loadingProgress.expectedTotalBytes != null
                        ? loadingProgress.cumulativeBytesLoaded / loadingProgress.expectedTotalBytes!
                        : null,
                    color: _primaryColor,
                  ),
                ),
              );
            },
            errorBuilder: (context, error, stackTrace) => Container(
              width: double.infinity,
              height: 200,
              color: Colors.grey[100],
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.broken_image_rounded, color: Colors.grey[400], size: 48),
                  const SizedBox(height: 8),
                  Text(
                    'Ошибка загрузки',
                    style: TextStyle(color: Colors.grey[500], fontSize: 12),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        // Поле подписи
        TextFormField(
          initialValue: block.caption ?? '',
          style: const TextStyle(fontSize: 13),
          decoration: InputDecoration(
            hintText: 'Подпись к изображению (опционально)',
            hintStyle: TextStyle(color: Colors.grey[400], fontSize: 13),
            prefixIcon: Icon(Icons.short_text_rounded, color: Colors.grey[400], size: 20),
            filled: true,
            fillColor: Colors.grey[50],
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: Colors.grey[200]!),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: Colors.grey[200]!),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: Colors.blue[400]!, width: 1.5),
            ),
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            isDense: true,
          ),
          onChanged: (value) => _updateImageCaption(index, value),
        ),
      ],
    );
  }

  Widget _buildAddBlockButtons() {
    return Row(
      children: [
        Expanded(
          child: _buildAddButton(
            icon: Icons.text_fields_rounded,
            label: 'Добавить текст',
            color: _primaryColor,
            onTap: _addTextBlock,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildAddButton(
            icon: Icons.add_photo_alternate_rounded,
            label: 'Добавить фото',
            color: Colors.blue[600]!,
            onTap: _addImageBlock,
          ),
        ),
      ],
    );
  }

  Widget _buildAddButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: color.withOpacity(0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withOpacity(0.2)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildUrlSection() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: _primaryColor.withOpacity(0.06),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () {
              setState(() {
                _showUrlField = !_showUrlField;
                if (!_showUrlField) {
                  _urlController.clear();
                }
              });
            },
            borderRadius: BorderRadius.circular(10),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: _showUrlField ? Colors.blue.withOpacity(0.08) : Colors.grey[50],
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  Icon(
                    _showUrlField ? Icons.check_box_rounded : Icons.check_box_outline_blank_rounded,
                    color: _showUrlField ? Colors.blue[600] : Colors.grey[400],
                    size: 22,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Внешняя ссылка',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: _showUrlField ? Colors.blue[700] : Colors.grey[700],
                          ),
                        ),
                        Text(
                          'Дополнительный источник информации',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey[500],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (_showUrlField) ...[
            const SizedBox(height: 12),
            _buildTextField(
              controller: _urlController,
              label: 'URL',
              hint: 'https://example.com',
              icon: Icons.link_rounded,
              keyboardType: TextInputType.url,
              validator: (value) {
                if (value != null && value.trim().isNotEmpty && !_isValidUrl(value.trim())) {
                  return 'Введите корректный URL';
                }
                return null;
              },
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    TextInputType? keyboardType,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      style: const TextStyle(fontSize: 14),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        hintStyle: TextStyle(color: Colors.grey[400]),
        prefixIcon: Icon(icon, color: _primaryColor, size: 20),
        filled: true,
        fillColor: Colors.grey[50],
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey[200]!),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey[200]!),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: _primaryColor, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.red[300]!),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        isDense: true,
      ),
      validator: validator,
    );
  }
}
