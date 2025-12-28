import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import 'recipe_model.dart';
import 'recipe_service.dart';
import 'core/utils/logger.dart';

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
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Выберите источник фото'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.photo_library),
                title: const Text('Галерея'),
                onTap: () {
                  Navigator.pop(context);
                  _pickImage(ImageSource.gallery);
                },
              ),
              ListTile(
                leading: const Icon(Icons.camera_alt),
                title: const Text('Камера'),
                onTap: () {
                  Navigator.pop(context);
                  _pickImage(ImageSource.camera);
                },
              ),
            ],
          ),
        );
      },
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
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.recipe == null ? 'Добавить рецепт' : 'Редактировать рецепт'),
        backgroundColor: const Color(0xFF004D40),
      ),
      body: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF004D40),
          image: DecorationImage(
            image: AssetImage('assets/images/arabica_background.png'),
            fit: BoxFit.cover,
            opacity: 0.6,
          ),
        ),
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Фото
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Фото напитка',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 12),
                        if (_selectedPhoto != null || _photoUrl != null)
                          Container(
                            height: 200,
                            width: double.infinity,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.grey),
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: _selectedPhoto != null
                                  ? Image.file(
                                      _selectedPhoto!,
                                      fit: BoxFit.cover,
                                    )
                                  : _photoUrl != null
                                      ? Image.network(
                                          _photoUrl!,
                                          fit: BoxFit.cover,
                                          errorBuilder: (_, __, ___) => const Icon(
                                            Icons.broken_image,
                                            size: 64,
                                          ),
                                        )
                                      : const SizedBox(),
                            ),
                          ),
                        const SizedBox(height: 12),
                        ElevatedButton.icon(
                          onPressed: _isSaving ? null : _showImageSourceDialog,
                          icon: const Icon(Icons.add_photo_alternate),
                          label: Text(_selectedPhoto != null || _photoUrl != null
                              ? 'Изменить фото'
                              : 'Добавить фото'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF004D40),
                            foregroundColor: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                // Название напитка
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: TextFormField(
                      controller: _nameController,
                      decoration: const InputDecoration(
                        labelText: 'Название напитка *',
                        border: OutlineInputBorder(),
                      ),
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'Название напитка обязательно';
                        }
                        return null;
                      },
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                // Категория напитка
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: TextFormField(
                      controller: _categoryController,
                      decoration: const InputDecoration(
                        labelText: 'Категория напитка',
                        border: OutlineInputBorder(),
                        hintText: 'Например: Кофе, Чай, Десерты',
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                // Цена напитка
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: TextFormField(
                      controller: _priceController,
                      decoration: const InputDecoration(
                        labelText: 'Цена напитка',
                        border: OutlineInputBorder(),
                        hintText: 'Например: 150',
                        prefixText: '₽ ',
                      ),
                      keyboardType: TextInputType.number,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                // Ингредиенты
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: TextFormField(
                      controller: _ingredientsController,
                      decoration: const InputDecoration(
                        labelText: 'Ингредиенты',
                        border: OutlineInputBorder(),
                        hintText: 'Введите список ингредиентов',
                      ),
                      maxLines: 5,
                      minLines: 3,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                // Последовательность приготовления
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: TextFormField(
                      controller: _stepsController,
                      decoration: const InputDecoration(
                        labelText: 'Последовательность приготовления',
                        border: OutlineInputBorder(),
                        hintText: 'Опишите шаги приготовления',
                      ),
                      maxLines: 10,
                      minLines: 5,
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                // Кнопка сохранения
                ElevatedButton(
                  onPressed: _isSaving ? null : _saveRecipe,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF004D40),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  child: _isSaving
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        )
                      : const Text(
                          'Сохранить',
                          style: TextStyle(fontSize: 18),
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

