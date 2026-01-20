import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import '../models/recipe_model.dart';
import '../services/recipe_service.dart';
import '../../../core/utils/logger.dart';

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
  static const _primaryColor = Color(0xFF004D40);
  static const _primaryColorLight = Color(0xFF00695C);

  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _categoryController = TextEditingController();
  final _priceController = TextEditingController();
  final _ingredientsController = TextEditingController();
  final _stepsController = TextEditingController();

  File? _selectedPhoto;
  String? _photoUrl;
  bool _isLoading = false;
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
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(24),
              topRight: Radius.circular(24),
            ),
          ),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Индикатор
                  Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey[300],
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(height: 20),
                  // Заголовок
                  Row(
                    children: [
                      Icon(Icons.add_photo_alternate_rounded, color: _primaryColor, size: 28),
                      const SizedBox(width: 12),
                      const Text(
                        'Выберите источник фото',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
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
                  const SizedBox(height: 12),
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
                  const SizedBox(height: 12),
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
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            border: Border.all(color: color.withOpacity(0.3)),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: color.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: color, size: 26),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: color,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 13,
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
          }
        }
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
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
            duration: const Duration(seconds: 5),
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
        backgroundColor: _primaryColor,
        elevation: 0,
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              _primaryColor,
              _primaryColor.withOpacity(0.85),
            ],
          ),
        ),
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Заголовок секции с фото
                _buildSectionHeader(
                  icon: Icons.photo_camera_rounded,
                  title: 'Фото напитка',
                  subtitle: 'Добавьте красивое фото',
                ),
                const SizedBox(height: 12),
                // Карточка фото
                _buildPhotoCard(),
                const SizedBox(height: 20),

                // Основная информация
                _buildSectionHeader(
                  icon: Icons.info_outline_rounded,
                  title: 'Основная информация',
                  subtitle: 'Название, категория и цена',
                ),
                const SizedBox(height: 12),
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
                    const Divider(height: 24),
                    _buildTextField(
                      controller: _categoryController,
                      label: 'Категория',
                      hint: 'Например: Кофе, Чай, Десерты',
                      icon: Icons.category_rounded,
                    ),
                    const Divider(height: 24),
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
                const SizedBox(height: 20),

                // Ингредиенты
                _buildSectionHeader(
                  icon: Icons.restaurant_menu_rounded,
                  title: 'Ингредиенты',
                  subtitle: 'Список компонентов',
                ),
                const SizedBox(height: 12),
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
                const SizedBox(height: 20),

                // Приготовление
                _buildSectionHeader(
                  icon: Icons.menu_book_rounded,
                  title: 'Приготовление',
                  subtitle: 'Пошаговая инструкция',
                ),
                const SizedBox(height: 12),
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
                const SizedBox(height: 28),

                // Кнопка сохранения
                _buildSaveButton(),
                const SizedBox(height: 20),
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
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: Colors.white, size: 22),
        ),
        const SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            Text(
              subtitle,
              style: TextStyle(
                fontSize: 13,
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
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.15),
            blurRadius: 12,
            offset: const Offset(0, 5),
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
                color: _primaryColor.withOpacity(0.08),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(20),
                  topRight: Radius.circular(20),
                ),
              ),
              child: hasPhoto
                  ? ClipRRect(
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(20),
                        topRight: Radius.circular(20),
                      ),
                      child: _selectedPhoto != null
                          ? Image.file(
                              _selectedPhoto!,
                              fit: BoxFit.cover,
                              width: double.infinity,
                            )
                          : _photoUrl != null
                              ? Image.network(
                                  _photoUrl!,
                                  fit: BoxFit.cover,
                                  width: double.infinity,
                                  errorBuilder: (_, __, ___) => _buildPhotoPlaceholder(),
                                )
                              : _buildPhotoPlaceholder(),
                    )
                  : _buildPhotoPlaceholder(),
            ),
          ),
          // Кнопка выбора фото
          Padding(
            padding: const EdgeInsets.all(16),
            child: Material(
              color: _primaryColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(14),
              child: InkWell(
                onTap: _isSaving ? null : _showImageSourceDialog,
                borderRadius: BorderRadius.circular(14),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 20),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        hasPhoto ? Icons.edit_rounded : Icons.add_photo_alternate_rounded,
                        color: _primaryColor,
                        size: 22,
                      ),
                      const SizedBox(width: 10),
                      Text(
                        hasPhoto ? 'Изменить фото' : 'Добавить фото',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: _primaryColor,
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
            color: _primaryColor.withOpacity(0.3),
          ),
          const SizedBox(height: 10),
          Text(
            'Нажмите, чтобы добавить фото',
            style: TextStyle(
              fontSize: 14,
              color: _primaryColor.withOpacity(0.5),
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
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.12),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
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
            color: _primaryColor.withOpacity(0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: _primaryColor, size: 22),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: TextFormField(
            controller: controller,
            keyboardType: keyboardType,
            decoration: InputDecoration(
              labelText: isRequired ? '$label *' : label,
              labelStyle: TextStyle(color: _primaryColor.withOpacity(0.7)),
              hintText: hint,
              hintStyle: TextStyle(color: Colors.grey[400]),
              suffixText: suffix,
              suffixStyle: TextStyle(
                color: _primaryColor,
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: Colors.grey[300]!),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: _primaryColor, width: 2),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: Colors.grey[300]!),
              ),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
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
        labelStyle: TextStyle(color: _primaryColor.withOpacity(0.7)),
        hintText: hint,
        hintStyle: TextStyle(color: Colors.grey[400]),
        alignLabelWithHint: true,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: Colors.grey[300]!),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: _primaryColor, width: 2),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: Colors.grey[300]!),
        ),
        contentPadding: const EdgeInsets.all(16),
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
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 12,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: _isSaving ? null : _saveRecipe,
          borderRadius: BorderRadius.circular(18),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 18),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (_isSaving) ...[
                  SizedBox(
                    height: 24,
                    width: 24,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      valueColor: AlwaysStoppedAnimation<Color>(_primaryColor),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Text(
                    'Сохранение...',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                      color: _primaryColor,
                    ),
                  ),
                ] else ...[
                  Icon(Icons.check_circle_rounded, color: _primaryColor, size: 26),
                  const SizedBox(width: 12),
                  Text(
                    widget.recipe == null ? 'Создать рецепт' : 'Сохранить изменения',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                      color: _primaryColor,
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

