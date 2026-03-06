import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../models/training_model.dart';
import '../models/content_block.dart';
import '../services/training_article_service.dart';
import '../../../shared/widgets/app_cached_image.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../../core/theme/app_colors.dart';

/// Страница редактора статьи обучения с поддержкой блоков контента
class TrainingArticleEditorPage extends StatefulWidget {
  final TrainingArticle? article;

  const TrainingArticleEditorPage({super.key, this.article});

  @override
  State<TrainingArticleEditorPage> createState() => _TrainingArticleEditorPageState();
}

class _TrainingArticleEditorPageState extends State<TrainingArticleEditorPage> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _groupController = TextEditingController();
  final _urlController = TextEditingController();

  List<ContentBlock> _contentBlocks = [];
  bool _isSaving = false;
  bool _showUrlField = false;
  String _visibility = 'all';  // 'all' или 'managers'
  final ImagePicker _imagePicker = ImagePicker();
  List<String> _existingGroups = [];
  TextEditingController? _syncedAutocompleteController;

  @override
  void initState() {
    super.initState();
    if (widget.article != null) {
      _titleController.text = widget.article!.title;
      _groupController.text = widget.article!.group;
      _urlController.text = widget.article!.url ?? '';
      _showUrlField = widget.article!.hasUrl;
      _visibility = widget.article!.visibility;

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
    _loadExistingGroups();
  }

  Future<void> _loadExistingGroups() async {
    try {
      final articles = await TrainingArticleService.getArticles();
      final groups = articles
          .map((a) => a.group)
          .where((g) => g.isNotEmpty)
          .toSet()
          .toList()
        ..sort();
      if (mounted) {
        setState(() => _existingGroups = groups);
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _titleController.dispose();
    _groupController.dispose();
    _urlController.dispose();
    super.dispose();
  }

  void _addTextBlock() {
    if (mounted) setState(() {
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
        builder: (context) => Center(
          child: Container(
            padding: EdgeInsets.all(24.w),
            decoration: BoxDecoration(
              color: AppColors.emeraldDark,
              borderRadius: BorderRadius.circular(16.r),
              border: Border.all(color: Colors.white.withOpacity(0.08)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(color: AppColors.gold),
                SizedBox(height: 16),
                Text(
                  'Загрузка изображения...',
                  style: TextStyle(color: Colors.white),
                ),
              ],
            ),
          ),
        ),
      );

      // Загружаем изображение на сервер
      final imageUrl = await TrainingArticleService.uploadImage(File(image.path));

      if (!mounted) return;
      Navigator.pop(context); // Закрываем индикатор

      if (imageUrl != null) {
        if (mounted) setState(() {
          _contentBlocks.add(ContentBlock.image(imageUrl));
        });
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка загрузки изображения'),
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
      if (mounted) setState(() {
        _contentBlocks.removeAt(index);
      });
    }
  }

  void _moveBlockUp(int index) {
    if (index > 0) {
      if (mounted) setState(() {
        final block = _contentBlocks.removeAt(index);
        _contentBlocks.insert(index - 1, block);
      });
    }
  }

  void _moveBlockDown(int index) {
    if (index < _contentBlocks.length - 1) {
      if (mounted) setState(() {
        final block = _contentBlocks.removeAt(index);
        _contentBlocks.insert(index + 1, block);
      });
    }
  }

  void _updateTextBlock(int index, String text) {
    if (mounted) setState(() {
      _contentBlocks[index] = _contentBlocks[index].copyWith(content: text);
    });
  }

  void _updateImageCaption(int index, String caption) {
    if (mounted) setState(() {
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
          content: Text('Добавьте контент статьи или внешнюю ссылку'),
          backgroundColor: Colors.orange[600],
        ),
      );
      return;
    }

    if (mounted) setState(() {
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
          visibility: _visibility,
        );
      } else {
        result = await TrainingArticleService.createArticle(
          group: _groupController.text.trim(),
          title: _titleController.text.trim(),
          content: simpleContent,
          url: url,
          contentBlocks: filteredBlocks,
          visibility: _visibility,
        );
      }

      if (result != null && mounted) {
        Navigator.pop(context, result);
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Ошибка сохранения статьи'),
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
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [AppColors.emerald, AppColors.emeraldDark, AppColors.night],
            stops: [0.0, 0.3, 1.0],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              _buildAppBar(isEditing),
              Expanded(
                child: _buildContent(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAppBar(bool isEditing) {
    return Padding(
      padding: EdgeInsets.fromLTRB(8.w, 8.h, 8.w, 16.h),
      child: Row(
        children: [
          Container(
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.08),
              borderRadius: BorderRadius.circular(12.r),
              border: Border.all(color: Colors.white.withOpacity(0.06)),
            ),
            child: IconButton(
              icon: Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 20),
              onPressed: () => Navigator.pop(context),
            ),
          ),
          SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isEditing ? 'Редактировать статью' : 'Новая статья',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20.sp,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  '${_contentBlocks.length} ${_getBlocksEnding(_contentBlocks.length)}',
                  style: TextStyle(
                    color: AppColors.gold.withOpacity(0.8),
                    fontSize: 13.sp,
                  ),
                ),
              ],
            ),
          ),
          // Кнопка сохранения
          Container(
            decoration: BoxDecoration(
              color: AppColors.gold.withOpacity(0.2),
              borderRadius: BorderRadius.circular(12.r),
              border: Border.all(color: AppColors.gold.withOpacity(0.4)),
            ),
            child: IconButton(
              icon: _isSaving
                  ? SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppColors.gold,
                      ),
                    )
                  : Icon(Icons.check_rounded, color: AppColors.gold, size: 24),
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
        padding: EdgeInsets.all(16.w),
        children: [
          // Основная информация
          _buildInfoCard(),
          SizedBox(height: 16),

          // Блоки контента
          _buildContentBlocksSection(),
          SizedBox(height: 16),

          // Кнопки добавления блоков
          _buildAddBlockButtons(),
          SizedBox(height: 16),

          // Внешняя ссылка
          _buildUrlSection(),

          SizedBox(height: 80),
        ],
      ),
    );
  }

  Widget _buildInfoCard() {
    return Container(
      padding: EdgeInsets.all(16.w),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.06),
        borderRadius: BorderRadius.circular(16.r),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: EdgeInsets.all(8.w),
                decoration: BoxDecoration(
                  color: AppColors.gold.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(8.r),
                  border: Border.all(color: AppColors.gold.withOpacity(0.3)),
                ),
                child: Icon(Icons.info_outline, color: AppColors.gold, size: 20),
              ),
              SizedBox(width: 12),
              Text(
                'Основная информация',
                style: TextStyle(
                  fontSize: 16.sp,
                  fontWeight: FontWeight.bold,
                  color: AppColors.gold,
                ),
              ),
            ],
          ),
          SizedBox(height: 16),
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
          SizedBox(height: 12),
          _buildGroupField(),
          SizedBox(height: 16),
          // Выбор видимости
          _buildVisibilitySelector(),
        ],
      ),
    );
  }

  Widget _buildVisibilitySelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.visibility_rounded, color: Colors.white.withOpacity(0.5), size: 18),
            SizedBox(width: 8),
            Text(
              'Кто может видеть',
              style: TextStyle(
                fontSize: 13.sp,
                fontWeight: FontWeight.w500,
                color: Colors.white.withOpacity(0.5),
              ),
            ),
          ],
        ),
        SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _buildVisibilityOption(
                value: 'all',
                label: 'Все',
                icon: Icons.people_rounded,
              ),
            ),
            SizedBox(width: 12),
            Expanded(
              child: _buildVisibilityOption(
                value: 'managers',
                label: 'Заведующие',
                icon: Icons.supervisor_account_rounded,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildVisibilityOption({
    required String value,
    required String label,
    required IconData icon,
  }) {
    final isSelected = _visibility == value;
    return InkWell(
      onTap: () {
        if (mounted) setState(() {
          _visibility = value;
        });
      },
      borderRadius: BorderRadius.circular(10.r),
      child: Container(
        padding: EdgeInsets.symmetric(vertical: 12.h, horizontal: 12.w),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.gold.withOpacity(0.15) : Colors.white.withOpacity(0.04),
          borderRadius: BorderRadius.circular(10.r),
          border: Border.all(
            color: isSelected ? AppColors.gold.withOpacity(0.4) : Colors.white.withOpacity(0.08),
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 18,
              color: isSelected ? AppColors.gold : Colors.white.withOpacity(0.4),
            ),
            SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                fontSize: 13.sp,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                color: isSelected ? AppColors.gold : Colors.white.withOpacity(0.5),
              ),
            ),
          ],
        ),
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
              padding: EdgeInsets.all(8.w),
              decoration: BoxDecoration(
                color: AppColors.gold.withOpacity(0.15),
                borderRadius: BorderRadius.circular(8.r),
                border: Border.all(color: AppColors.gold.withOpacity(0.3)),
              ),
              child: Icon(Icons.view_agenda_rounded, color: AppColors.gold, size: 20),
            ),
            SizedBox(width: 12),
            Text(
              'Контент статьи',
              style: TextStyle(
                fontSize: 16.sp,
                fontWeight: FontWeight.bold,
                color: AppColors.gold,
              ),
            ),
          ],
        ),
        SizedBox(height: 12),
        ...List.generate(_contentBlocks.length, (index) {
          final block = _contentBlocks[index];
          return _buildContentBlockCard(block, index);
        }),
      ],
    );
  }

  Widget _buildContentBlockCard(ContentBlock block, int index) {
    return Container(
      margin: EdgeInsets.only(bottom: 12.h),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.06),
        borderRadius: BorderRadius.circular(16.r),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Заголовок блока с кнопками
          Container(
            padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 8.h),
            decoration: BoxDecoration(
              color: block.type == ContentBlockType.image
                  ? Colors.blue.withOpacity(0.1)
                  : AppColors.gold.withOpacity(0.08),
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(16.r),
                topRight: Radius.circular(16.r),
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
                      ? Colors.blue[300]
                      : AppColors.gold,
                ),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    block.type == ContentBlockType.image ? 'Изображение' : 'Текст',
                    style: TextStyle(
                      fontSize: 13.sp,
                      fontWeight: FontWeight.w600,
                      color: block.type == ContentBlockType.image
                          ? Colors.blue[300]
                          : AppColors.gold,
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
                  color: Colors.red[300],
                  onTap: _contentBlocks.length > 1 ? () => _removeBlock(index) : null,
                ),
              ],
            ),
          ),
          // Контент блока
          Padding(
            padding: EdgeInsets.all(12.w),
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
      borderRadius: BorderRadius.circular(6.r),
      child: Container(
        padding: EdgeInsets.all(4.w),
        child: Icon(
          icon,
          size: 20,
          color: onTap != null ? (color ?? Colors.white.withOpacity(0.6)) : Colors.white.withOpacity(0.2),
        ),
      ),
    );
  }

  Widget _buildTextBlockContent(ContentBlock block, int index) {
    return TextFormField(
      initialValue: block.content,
      maxLines: null,
      minLines: 3,
      style: TextStyle(fontSize: 14.sp, height: 1.6, color: Colors.white.withOpacity(0.9)),
      decoration: InputDecoration(
        hintText: 'Введите текст...',
        hintStyle: TextStyle(color: Colors.white.withOpacity(0.3)),
        filled: true,
        fillColor: Colors.white.withOpacity(0.04),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12.r),
          borderSide: BorderSide(color: Colors.white.withOpacity(0.1)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12.r),
          borderSide: BorderSide(color: Colors.white.withOpacity(0.1)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12.r),
          borderSide: BorderSide(color: AppColors.gold.withOpacity(0.5), width: 2),
        ),
        contentPadding: EdgeInsets.all(14.w),
      ),
      cursorColor: AppColors.gold,
      onChanged: (value) => _updateTextBlock(index, value),
    );
  }

  Widget _buildImageBlockContent(ContentBlock block, int index) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Поле подписи (сверху фото)
        TextFormField(
          initialValue: block.caption ?? '',
          style: TextStyle(fontSize: 13.sp, color: Colors.white.withOpacity(0.9)),
          decoration: InputDecoration(
            hintText: 'Подпись к изображению (опционально)',
            hintStyle: TextStyle(color: Colors.white.withOpacity(0.3), fontSize: 13.sp),
            prefixIcon: Icon(Icons.short_text_rounded, color: Colors.white.withOpacity(0.4), size: 20),
            filled: true,
            fillColor: Colors.white.withOpacity(0.04),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10.r),
              borderSide: BorderSide(color: Colors.white.withOpacity(0.1)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10.r),
              borderSide: BorderSide(color: Colors.white.withOpacity(0.1)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10.r),
              borderSide: BorderSide(color: AppColors.gold.withOpacity(0.5), width: 1.5),
            ),
            contentPadding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 10.h),
            isDense: true,
          ),
          cursorColor: AppColors.gold,
          onChanged: (value) => _updateImageCaption(index, value),
        ),
        SizedBox(height: 12),
        // Превью изображения с кнопкой замены
        Stack(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12.r),
              child: AppCachedImage(
                imageUrl: block.content,
                width: double.infinity,
                height: 200,
                fit: BoxFit.cover,
                errorWidget: (context, url, error) => Container(
                  width: double.infinity,
                  height: 200,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.06),
                    borderRadius: BorderRadius.circular(12.r),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.broken_image_rounded, color: Colors.white.withOpacity(0.3), size: 48),
                      SizedBox(height: 8),
                      Text(
                        'Ошибка загрузки',
                        style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 12.sp),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            // Кнопка замены фото
            Positioned(
              right: 8.w,
              bottom: 8.h,
              child: Material(
                color: Colors.black.withOpacity(0.6),
                borderRadius: BorderRadius.circular(8.r),
                child: InkWell(
                  onTap: () => _replaceImage(index),
                  borderRadius: BorderRadius.circular(8.r),
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 8.h),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.edit_rounded, color: Colors.white, size: 16),
                        SizedBox(width: 6),
                        Text(
                          'Заменить',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 12.sp,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _replaceImage(int index) async {
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
        builder: (context) => Center(
          child: Container(
            padding: EdgeInsets.all(24.w),
            decoration: BoxDecoration(
              color: AppColors.emeraldDark,
              borderRadius: BorderRadius.circular(16.r),
              border: Border.all(color: Colors.white.withOpacity(0.08)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(color: AppColors.gold),
                SizedBox(height: 16),
                Text(
                  'Загрузка изображения...',
                  style: TextStyle(color: Colors.white),
                ),
              ],
            ),
          ),
        ),
      );

      // Загружаем новое изображение на сервер
      final imageUrl = await TrainingArticleService.uploadImage(File(image.path));

      if (!mounted) return;
      Navigator.pop(context); // Закрываем индикатор

      if (imageUrl != null) {
        // Сохраняем подпись при замене изображения
        final currentCaption = _contentBlocks[index].caption;
        if (mounted) setState(() {
          _contentBlocks[index] = ContentBlock(
            id: _contentBlocks[index].id,
            type: ContentBlockType.image,
            content: imageUrl,
            caption: currentCaption,
          );
        });

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  Icon(Icons.check_circle, color: Colors.white, size: 20),
                  SizedBox(width: 8),
                  Text('Изображение заменено'),
                ],
              ),
              backgroundColor: Colors.green[600],
              behavior: SnackBarBehavior.floating,
              duration: Duration(seconds: 2),
            ),
          );
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка загрузки изображения'),
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

  Widget _buildAddBlockButtons() {
    return Row(
      children: [
        Expanded(
          child: _buildAddButton(
            icon: Icons.text_fields_rounded,
            label: 'Добавить текст',
            color: AppColors.gold,
            onTap: _addTextBlock,
          ),
        ),
        SizedBox(width: 12),
        Expanded(
          child: _buildAddButton(
            icon: Icons.add_photo_alternate_rounded,
            label: 'Добавить фото',
            color: Colors.blue[300]!,
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
      borderRadius: BorderRadius.circular(12.r),
      child: Container(
        padding: EdgeInsets.symmetric(vertical: 14.h),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12.r),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color, size: 20),
            SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 13.sp,
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
      padding: EdgeInsets.all(16.w),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.06),
        borderRadius: BorderRadius.circular(16.r),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () {
              if (mounted) setState(() {
                _showUrlField = !_showUrlField;
                if (!_showUrlField) {
                  _urlController.clear();
                }
              });
            },
            borderRadius: BorderRadius.circular(10.r),
            child: Container(
              padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 10.h),
              decoration: BoxDecoration(
                color: _showUrlField ? AppColors.gold.withOpacity(0.1) : Colors.white.withOpacity(0.04),
                borderRadius: BorderRadius.circular(10.r),
                border: Border.all(
                  color: _showUrlField ? AppColors.gold.withOpacity(0.3) : Colors.white.withOpacity(0.08),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    _showUrlField ? Icons.check_box_rounded : Icons.check_box_outline_blank_rounded,
                    color: _showUrlField ? AppColors.gold : Colors.white.withOpacity(0.4),
                    size: 22,
                  ),
                  SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Внешняя ссылка',
                          style: TextStyle(
                            fontSize: 14.sp,
                            fontWeight: FontWeight.w600,
                            color: _showUrlField ? AppColors.gold : Colors.white.withOpacity(0.7),
                          ),
                        ),
                        Text(
                          'Дополнительный источник информации',
                          style: TextStyle(
                            fontSize: 11.sp,
                            color: Colors.white.withOpacity(0.4),
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
            SizedBox(height: 12),
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

  Widget _buildGroupField() {
    return Autocomplete<String>(
      initialValue: _groupController.value,
      optionsBuilder: (TextEditingValue textEditingValue) {
        if (textEditingValue.text.isEmpty) {
          return _existingGroups;
        }
        final query = textEditingValue.text.toLowerCase();
        return _existingGroups.where(
          (g) => g.toLowerCase().contains(query),
        );
      },
      onSelected: (String selection) {
        _groupController.text = selection;
      },
      optionsViewOpenDirection: OptionsViewOpenDirection.down,
      optionsViewBuilder: (context, onSelected, options) {
        return Align(
          alignment: Alignment.topLeft,
          child: Material(
            elevation: 8,
            borderRadius: BorderRadius.circular(12.r),
            color: AppColors.emeraldDark,
            child: Container(
              constraints: BoxConstraints(maxHeight: 200),
              width: MediaQuery.of(context).size.width - 72.w,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12.r),
                border: Border.all(color: AppColors.gold.withOpacity(0.3)),
              ),
              child: ListView.builder(
                padding: EdgeInsets.symmetric(vertical: 4),
                shrinkWrap: true,
                itemCount: options.length,
                itemBuilder: (context, index) {
                  final option = options.elementAt(index);
                  return ListTile(
                    dense: true,
                    leading: Icon(Icons.folder_rounded, color: AppColors.gold, size: 18),
                    title: Text(
                      option,
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.9),
                        fontSize: 14.sp,
                      ),
                    ),
                    onTap: () => onSelected(option),
                  );
                },
              ),
            ),
          ),
        );
      },
      fieldViewBuilder: (context, textController, focusNode, onFieldSubmitted) {
        // Sync controllers (add listener only once per controller instance)
        if (_syncedAutocompleteController != textController) {
          _syncedAutocompleteController = textController;
          textController.addListener(() {
            if (_groupController.text != textController.text) {
              _groupController.text = textController.text;
            }
          });
        }
        return TextFormField(
          controller: textController,
          focusNode: focusNode,
          style: TextStyle(fontSize: 14.sp, color: Colors.white.withOpacity(0.9)),
          decoration: InputDecoration(
            labelText: 'Группа',
            labelStyle: TextStyle(color: Colors.white.withOpacity(0.5)),
            hintText: 'Введите группу',
            hintStyle: TextStyle(color: Colors.white.withOpacity(0.3)),
            prefixIcon: Icon(Icons.folder_rounded, color: AppColors.gold, size: 20),
            filled: true,
            fillColor: Colors.white.withOpacity(0.06),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12.r),
              borderSide: BorderSide(color: Colors.white.withOpacity(0.1)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12.r),
              borderSide: BorderSide(color: Colors.white.withOpacity(0.1)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12.r),
              borderSide: BorderSide(color: AppColors.gold.withOpacity(0.5), width: 2),
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12.r),
              borderSide: BorderSide(color: Colors.red[300]!),
            ),
            contentPadding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 14.h),
            isDense: true,
            errorStyle: TextStyle(color: Colors.red[300]),
          ),
          cursorColor: AppColors.gold,
          validator: (value) {
            if (value == null || value.trim().isEmpty) {
              return 'Введите группу';
            }
            return null;
          },
        );
      },
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
      style: TextStyle(fontSize: 14.sp, color: Colors.white.withOpacity(0.9)),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: Colors.white.withOpacity(0.5)),
        hintText: hint,
        hintStyle: TextStyle(color: Colors.white.withOpacity(0.3)),
        prefixIcon: Icon(icon, color: AppColors.gold, size: 20),
        filled: true,
        fillColor: Colors.white.withOpacity(0.06),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12.r),
          borderSide: BorderSide(color: Colors.white.withOpacity(0.1)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12.r),
          borderSide: BorderSide(color: Colors.white.withOpacity(0.1)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12.r),
          borderSide: BorderSide(color: AppColors.gold.withOpacity(0.5), width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12.r),
          borderSide: BorderSide(color: Colors.red[300]!),
        ),
        contentPadding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 14.h),
        isDense: true,
        errorStyle: TextStyle(color: Colors.red[300]),
      ),
      cursorColor: AppColors.gold,
      validator: validator,
    );
  }
}
