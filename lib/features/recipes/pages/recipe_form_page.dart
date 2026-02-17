import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import '../models/recipe_model.dart';
import '../services/recipe_service.dart';
import '../../../core/utils/logger.dart';
import '../../../shared/widgets/app_cached_image.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../../core/theme/app_colors.dart';

class RecipeFormPage extends StatefulWidget {
  final Recipe? recipe; // Если передан, то редактирование, иначе создание

  const RecipeFormPage({
    super.key,
    this.recipe,
  });

  @override
  State<RecipeFormPage> createState() => _RecipeFormPageState();
}

class _RecipeFormPageState extends State<RecipeFormPage> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _categoryController = TextEditingController();
  final _priceController = TextEditingController();
  final _ingredientsController = TextEditingController();
  final _stepsController = TextEditingController();

  File? _selectedPhoto;
  String? _photoUrl;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    if (widget.recipe != null) {
      _nameController.text = widget.recipe!.name;
      _categoryController.text = widget.recipe!.category;
      _priceController.text = widget.recipe!.price ?? '';
      _ingredientsController.text = widget.recipe!.ingredients;
      _stepsController.text = widget.recipe!.steps;
      _photoUrl = widget.recipe!.photoUrl;
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _categoryController.dispose();
    _priceController.dispose();
    _ingredientsController.dispose();
    _stepsController.dispose();
    super.dispose();
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      final ImagePicker picker = ImagePicker();
      final XFile? image = await picker.pickImage(
        source: source,
        maxWidth: 1920,
        maxHeight: 1920,
        imageQuality: 85,
      );

      if (image != null) {
        setState(() {
          _selectedPhoto = File(image.path);
          _photoUrl = null; // Сбрасываем URL, так как выбрано новое фото
        });
      }
    } catch (e) {
      Logger.error('❌ Ошибка выбора фото', e);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка выбора фото: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _showImageSourceDialog() async {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (BuildContext context) {
        return Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(24.r),
              topRight: Radius.circular(24.r),
            ),
          ),
          child: SafeArea(
            child: Padding(
              padding: EdgeInsets.all(20.w),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Индикатор
                  Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey[300],
                      borderRadius: BorderRadius.circular(2.r),
                    ),
                  ),
                  SizedBox(height: 20),
                  // Заголовок
                  Row(
                    children: [
                      Icon(Icons.add_photo_alternate_rounded, color: AppColors.primaryGreen, size: 28),
                      SizedBox(width: 12),
                      Text(
                        'Выберите источник фото',
                        style: TextStyle(
                          fontSize: 18.sp,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 20),
                  // Галерея
                  _buildImageSourceOption(
                    icon: Icons.photo_library_rounded,
                    title: 'Галерея',
                    subtitle: 'Выбрать из фотографий',
                    color: Colors.purple,
                    onTap: () {
                      Navigator.pop(context);
                      _pickImage(ImageSource.gallery);
                    },
                  ),
                  SizedBox(height: 12),
                  // Камера
                  _buildImageSourceOption(
                    icon: Icons.camera_alt_rounded,
                    title: 'Камера',
                    subtitle: 'Сделать новое фото',
                    color: Colors.blue,
                    onTap: () {
                      Navigator.pop(context);
                      _pickImage(ImageSource.camera);
                    },
                  ),
                  SizedBox(height: 12),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildImageSourceOption({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14.r),
        child: Container(
          padding: EdgeInsets.all(14.w),
          decoration: BoxDecoration(
            border: Border.all(color: color.withOpacity(0.3)),
            borderRadius: BorderRadius.circular(14.r),
          ),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: color.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(12.r),
                ),
                child: Icon(icon, color: color, size: 26),
              ),
              SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 16.sp,
                        fontWeight: FontWeight.w600,
                        color: color,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 13.sp,
                        color: Colors.grey[600],
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: color, size: 24),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _saveRecipe() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() => _isSaving = true);

    try {
      Recipe? savedRecipe;

      if (widget.recipe == null) {
        // Создание нового рецепта
        savedRecipe = await RecipeService.createRecipe(
          name: _nameController.text.trim(),
          category: _categoryController.text.trim(),
          price: _priceController.text.trim().isNotEmpty ? _priceController.text.trim() : null,
          ingredients: _ingredientsController.text.trim(),
          steps: _stepsController.text.trim(),
        );

        if (savedRecipe == null) {
          throw Exception('Не удалось создать рецепт');
        }

        // Загружаем фото, если выбрано
        if (_selectedPhoto != null) {
          final photoUrl = await RecipeService.uploadPhoto(
            recipeId: savedRecipe.id,
            photoFile: _selectedPhoto!,
          );
          if (photoUrl != null) {
            // Обновляем рецепт с URL фото
            savedRecipe = await RecipeService.updateRecipe(
              id: savedRecipe.id,
              photoUrl: photoUrl,
            );
          } else {
            Logger.warning('Фото не загружено для рецепта ${savedRecipe.id}');
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Рецепт создан, но фото не удалось загрузить. Попробуйте добавить фото через редактирование.'),
                  backgroundColor: Colors.orange,
                  duration: Duration(seconds: 4),
                ),
              );
            }
          }
        }
      } else {
        // Обновление существующего рецепта
        savedRecipe = await RecipeService.updateRecipe(
          id: widget.recipe!.id,
          name: _nameController.text.trim(),
          category: _categoryController.text.trim(),
          price: _priceController.text.trim().isNotEmpty ? _priceController.text.trim() : null,
          ingredients: _ingredientsController.text.trim(),
          steps: _stepsController.text.trim(),
        );

        if (savedRecipe == null) {
          throw Exception('Не удалось обновить рецепт');
        }

        // Загружаем новое фото, если выбрано
        if (_selectedPhoto != null) {
          final photoUrl = await RecipeService.uploadPhoto(
            recipeId: widget.recipe!.id,
            photoFile: _selectedPhoto!,
          );
          if (photoUrl != null) {
            savedRecipe = await RecipeService.updateRecipe(
              id: widget.recipe!.id,
              photoUrl: photoUrl,
            );
          } else {
            Logger.warning('Фото не загружено для рецепта ${widget.recipe!.id}');
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Рецепт сохранён, но фото не удалось загрузить. Попробуйте ещё раз.'),
                  backgroundColor: Colors.orange,
                  duration: Duration(seconds: 4),
                ),
              );
            }
          }
        }
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Рецепт успешно сохранен'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 2),
          ),
        );
        Navigator.pop(context, savedRecipe);
      }
    } catch (e) {
      Logger.error('❌ Ошибка сохранения рецепта', e);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка сохранения: ${e.toString()}'),
            backgroundColor: Colors.red,
            duration: Duration(seconds: 5),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.recipe != null;

    return Scaffold(
      appBar: AppBar(
        title: Text(isEditing ? 'Редактировать рецепт' : 'Новый рецепт'),
        backgroundColor: AppColors.primaryGreen,
        elevation: 0,
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              AppColors.primaryGreen,
              AppColors.primaryGreen.withOpacity(0.85),
            ],
          ),
        ),
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            padding: EdgeInsets.all(16.w),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Заголовок секции с фото
                _buildSectionHeader(
                  icon: Icons.photo_camera_rounded,
                  title: 'Фото напитка',
                  subtitle: 'Добавьте красивое фото',
                ),
                SizedBox(height: 12),
                // Карточка фото
                _buildPhotoCard(),
                SizedBox(height: 20),

                // Основная информация
                _buildSectionHeader(
                  icon: Icons.info_outline_rounded,
                  title: 'Основная информация',
                  subtitle: 'Название, категория и цена',
                ),
                SizedBox(height: 12),
                _buildFormCard(
                  children: [
                    _buildTextField(
                      controller: _nameController,
                      label: 'Название напитка',
                      hint: 'Введите название',
                      icon: Icons.local_cafe_rounded,
                      isRequired: true,
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'Название напитка обязательно';
                        }
                        return null;
                      },
                    ),
                    Divider(height: 24),
                    _buildTextField(
                      controller: _categoryController,
                      label: 'Категория',
                      hint: 'Например: Кофе, Чай, Десерты',
                      icon: Icons.category_rounded,
                    ),
                    Divider(height: 24),
                    _buildTextField(
                      controller: _priceController,
                      label: 'Цена',
                      hint: 'Например: 150',
                      icon: Icons.payments_rounded,
                      keyboardType: TextInputType.number,
                      suffix: 'руб.',
                    ),
                  ],
                ),
                SizedBox(height: 20),

                // Ингредиенты
                _buildSectionHeader(
                  icon: Icons.restaurant_menu_rounded,
                  title: 'Ингредиенты',
                  subtitle: 'Список компонентов',
                ),
                SizedBox(height: 12),
                _buildFormCard(
                  children: [
                    _buildMultilineTextField(
                      controller: _ingredientsController,
                      label: 'Список ингредиентов',
                      hint: 'Молоко - 200 мл\nЭспрессо - 30 мл\nСахар - по вкусу',
                      minLines: 4,
                      maxLines: 8,
                    ),
                  ],
                ),
                SizedBox(height: 20),

                // Приготовление
                _buildSectionHeader(
                  icon: Icons.menu_book_rounded,
                  title: 'Приготовление',
                  subtitle: 'Пошаговая инструкция',
                ),
                SizedBox(height: 12),
                _buildFormCard(
                  children: [
                    _buildMultilineTextField(
                      controller: _stepsController,
                      label: 'Шаги приготовления',
                      hint: '1. Взбейте молоко\n2. Приготовьте эспрессо\n3. Соедините и украсьте',
                      minLines: 6,
                      maxLines: 15,
                    ),
                  ],
                ),
                SizedBox(height: 28),

                // Кнопка сохранения
                _buildSaveButton(),
                SizedBox(height: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Заголовок секции
  Widget _buildSectionHeader({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Row(
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.2),
            borderRadius: BorderRadius.circular(10.r),
          ),
          child: Icon(icon, color: Colors.white, size: 22),
        ),
        SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: TextStyle(
                fontSize: 17.sp,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            Text(
              subtitle,
              style: TextStyle(
                fontSize: 13.sp,
                color: Colors.white.withOpacity(0.7),
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// Карточка с фото
  Widget _buildPhotoCard() {
    final hasPhoto = _selectedPhoto != null || _photoUrl != null;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20.r),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.15),
            blurRadius: 12,
            offset: Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        children: [
          // Область для фото
          GestureDetector(
            onTap: _isSaving ? null : _showImageSourceDialog,
            child: Container(
              height: hasPhoto ? 220 : 160,
              width: double.infinity,
              decoration: BoxDecoration(
                color: AppColors.primaryGreen.withOpacity(0.08),
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(20.r),
                  topRight: Radius.circular(20.r),
                ),
              ),
              child: hasPhoto
                  ? ClipRRect(
                      borderRadius: BorderRadius.only(
                        topLeft: Radius.circular(20.r),
                        topRight: Radius.circular(20.r),
                      ),
                      child: _selectedPhoto != null
                          ? Image.file(
                              _selectedPhoto!,
                              fit: BoxFit.cover,
                              width: double.infinity,
                            )
                          : _photoUrl != null
                              ? AppCachedImage(
                                  imageUrl: _photoUrl!,
                                  fit: BoxFit.cover,
                                  width: double.infinity,
                                  errorWidget: (_, __, ___) => _buildPhotoPlaceholder(),
                                )
                              : _buildPhotoPlaceholder(),
                    )
                  : _buildPhotoPlaceholder(),
            ),
          ),
          // Кнопка выбора фото
          Padding(
            padding: EdgeInsets.all(16.w),
            child: Material(
              color: AppColors.primaryGreen.withOpacity(0.1),
              borderRadius: BorderRadius.circular(14.r),
              child: InkWell(
                onTap: _isSaving ? null : _showImageSourceDialog,
                borderRadius: BorderRadius.circular(14.r),
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 14.h, horizontal: 20.w),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        hasPhoto ? Icons.edit_rounded : Icons.add_photo_alternate_rounded,
                        color: AppColors.primaryGreen,
                        size: 22,
                      ),
                      SizedBox(width: 10),
                      Text(
                        hasPhoto ? 'Изменить фото' : 'Добавить фото',
                        style: TextStyle(
                          fontSize: 15.sp,
                          fontWeight: FontWeight.w600,
                          color: AppColors.primaryGreen,
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
    );
  }

  /// Заглушка для фото
  Widget _buildPhotoPlaceholder() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.add_a_photo_rounded,
            size: 48,
            color: AppColors.primaryGreen.withOpacity(0.3),
          ),
          SizedBox(height: 10),
          Text(
            'Нажмите, чтобы добавить фото',
            style: TextStyle(
              fontSize: 14.sp,
              color: AppColors.primaryGreen.withOpacity(0.5),
            ),
          ),
        ],
      ),
    );
  }

  /// Карточка формы
  Widget _buildFormCard({required List<Widget> children}) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20.r),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.12),
            blurRadius: 10,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: EdgeInsets.all(18.w),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: children,
        ),
      ),
    );
  }

  /// Текстовое поле
  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    String? hint,
    required IconData icon,
    bool isRequired = false,
    String? suffix,
    TextInputType? keyboardType,
    String? Function(String?)? validator,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: AppColors.primaryGreen.withOpacity(0.1),
            borderRadius: BorderRadius.circular(12.r),
          ),
          child: Icon(icon, color: AppColors.primaryGreen, size: 22),
        ),
        SizedBox(width: 14),
        Expanded(
          child: TextFormField(
            controller: controller,
            keyboardType: keyboardType,
            decoration: InputDecoration(
              labelText: isRequired ? '$label *' : label,
              labelStyle: TextStyle(color: AppColors.primaryGreen.withOpacity(0.7)),
              hintText: hint,
              hintStyle: TextStyle(color: Colors.grey[400]),
              suffixText: suffix,
              suffixStyle: TextStyle(
                color: AppColors.primaryGreen,
                fontWeight: FontWeight.bold,
                fontSize: 16.sp,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12.r),
                borderSide: BorderSide(color: Colors.grey[300]!),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12.r),
                borderSide: BorderSide(color: AppColors.primaryGreen, width: 2),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12.r),
                borderSide: BorderSide(color: Colors.grey[300]!),
              ),
              contentPadding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 14.h),
            ),
            validator: validator,
          ),
        ),
      ],
    );
  }

  /// Многострочное текстовое поле
  Widget _buildMultilineTextField({
    required TextEditingController controller,
    required String label,
    String? hint,
    int minLines = 3,
    int maxLines = 5,
  }) {
    return TextFormField(
      controller: controller,
      minLines: minLines,
      maxLines: maxLines,
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: AppColors.primaryGreen.withOpacity(0.7)),
        hintText: hint,
        hintStyle: TextStyle(color: Colors.grey[400]),
        alignLabelWithHint: true,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14.r),
          borderSide: BorderSide(color: Colors.grey[300]!),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14.r),
          borderSide: BorderSide(color: AppColors.primaryGreen, width: 2),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14.r),
          borderSide: BorderSide(color: Colors.grey[300]!),
        ),
        contentPadding: EdgeInsets.all(16.w),
      ),
    );
  }

  /// Кнопка сохранения
  Widget _buildSaveButton() {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.white, Colors.white.withOpacity(0.95)],
        ),
        borderRadius: BorderRadius.circular(18.r),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 12,
            offset: Offset(0, 5),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: _isSaving ? null : _saveRecipe,
          borderRadius: BorderRadius.circular(18.r),
          child: Padding(
            padding: EdgeInsets.symmetric(vertical: 18.h),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (_isSaving) ...[
                  SizedBox(
                    height: 24,
                    width: 24,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      valueColor: AlwaysStoppedAnimation<Color>(AppColors.primaryGreen),
                    ),
                  ),
                  SizedBox(width: 14),
                  Text(
                    'Сохранение...',
                    style: TextStyle(
                      fontSize: 17.sp,
                      fontWeight: FontWeight.bold,
                      color: AppColors.primaryGreen,
                    ),
                  ),
                ] else ...[
                  Icon(Icons.check_circle_rounded, color: AppColors.primaryGreen, size: 26),
                  SizedBox(width: 12),
                  Text(
                    widget.recipe == null ? 'Создать рецепт' : 'Сохранить изменения',
                    style: TextStyle(
                      fontSize: 17.sp,
                      fontWeight: FontWeight.bold,
                      color: AppColors.primaryGreen,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
