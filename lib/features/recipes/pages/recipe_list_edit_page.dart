import 'package:flutter/material.dart';
import '../models/recipe_model.dart';
import '../services/recipe_service.dart';
import 'recipe_form_page.dart';
import '../../../core/utils/logger.dart';
import '../../../shared/widgets/app_cached_image.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../../core/theme/app_colors.dart';

class RecipeListEditPage extends StatefulWidget {
  const RecipeListEditPage({super.key});

  @override
  State<RecipeListEditPage> createState() => _RecipeListEditPageState();
}

class _RecipeListEditPageState extends State<RecipeListEditPage> {
  static final _primaryColorLight = Color(0xFF00695C);

  List<Recipe> _recipes = [];
  bool _isLoading = true;
  String _searchQuery = '';
  String? _selectedCategory;

  @override
  void initState() {
    super.initState();
    _loadRecipes();
  }

  Future<void> _loadRecipes() async {
    if (mounted) setState(() => _isLoading = true);
    try {
      final recipes = await RecipeService.getRecipes();
      if (mounted) {
        setState(() {
          _recipes = recipes;
          _isLoading = false;
          // Сбросить категорию если она больше не существует
          if (_selectedCategory != null) {
            final categories = recipes
                .map((r) => r.category)
                .where((c) => c.isNotEmpty)
                .toSet();
            if (!categories.contains(_selectedCategory)) {
              _selectedCategory = null;
            }
          }
        });
      }
    } catch (e) {
      Logger.error('❌ Ошибка загрузки рецептов', e);
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка загрузки рецептов: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _deleteRecipe(Recipe recipe) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('Удалить рецепт?'),
          content: Text('Вы уверены, что хотите удалить рецепт "${recipe.name}"?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text('Отмена'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              style: TextButton.styleFrom(
                foregroundColor: Colors.red,
              ),
              child: Text('Удалить'),
            ),
          ],
        );
      },
    );

    if (confirmed == true) {
      try {
        final success = await RecipeService.deleteRecipe(recipe.id);
        if (success) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Рецепт успешно удален'),
                backgroundColor: Colors.green,
                duration: Duration(seconds: 2),
              ),
            );
            _loadRecipes(); // Перезагружаем список
          }
        } else {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Ошибка удаления рецепта'),
                backgroundColor: Colors.red,
              ),
            );
          }
        }
      } catch (e) {
        Logger.error('❌ Ошибка удаления рецепта', e);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Ошибка удаления: ${e.toString()}'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  Future<void> _editRecipe(Recipe recipe) async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => RecipeFormPage(recipe: recipe),
      ),
    );

    if (result != null) {
      // Рецепт был обновлен, перезагружаем список
      _loadRecipes();
    }
  }

  List<Recipe> get _filteredRecipes {
    var filtered = _recipes;

    // Фильтр по поисковому запросу
    if (_searchQuery.isNotEmpty) {
      filtered = filtered
          .where((r) => r.name.toLowerCase().contains(_searchQuery.toLowerCase()))
          .toList();
    }

    // Фильтр по категории
    if (_selectedCategory != null) {
      filtered = filtered
          .where((r) => r.category == _selectedCategory)
          .toList();
    }

    return filtered;
  }

  List<String> get _categories {
    final categories = _recipes
        .map((r) => r.category)
        .where((c) => c.isNotEmpty)
        .toSet()
        .toList();
    categories.sort();
    return categories;
  }

  Future<void> _addNewRecipe() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => RecipeFormPage(),
      ),
    );
    if (result != null) {
      // Рецепт был создан, перезагружаем список
      _loadRecipes();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Новый рецепт создан'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 2),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.primaryGreen,
        image: DecorationImage(
          image: AssetImage('assets/images/arabica_background.png'),
          fit: BoxFit.cover,
          opacity: 0.6,
        ),
      ),
      child: Column(
        children: [
          // Красивая кнопка "Добавить новый рецепт"
          Container(
            margin: EdgeInsets.all(16.w),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Colors.white,
                  Colors.white.withOpacity(0.95),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(20.r),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.2),
                  blurRadius: 12,
                  offset: Offset(0, 6),
                ),
              ],
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: _addNewRecipe,
                borderRadius: BorderRadius.circular(20.r),
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 20.h, horizontal: 24.w),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [AppColors.primaryGreen, _primaryColorLight],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(14.r),
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.primaryGreen.withOpacity(0.3),
                              blurRadius: 8,
                              offset: Offset(0, 3),
                            ),
                          ],
                        ),
                        child: Icon(
                          Icons.add_rounded,
                          color: Colors.white,
                          size: 28,
                        ),
                      ),
                      SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Добавить новый рецепт',
                              style: TextStyle(
                                fontSize: 17.sp,
                                fontWeight: FontWeight.bold,
                                color: AppColors.primaryGreen,
                              ),
                            ),
                            SizedBox(height: 2),
                            Text(
                              'Создайте новый рецепт напитка',
                              style: TextStyle(
                                fontSize: 13.sp,
                                color: Colors.grey[600],
                              ),
                            ),
                          ],
                        ),
                      ),
                      Icon(
                        Icons.arrow_forward_ios_rounded,
                        color: AppColors.primaryGreen,
                        size: 20,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          // Поиск и фильтр
          Container(
            margin: EdgeInsets.symmetric(horizontal: 16.w),
            padding: EdgeInsets.all(16.w),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.15),
              borderRadius: BorderRadius.circular(20.r),
            ),
            child: Column(
              children: [
                // Поле поиска
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14.r),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.08),
                        blurRadius: 6,
                        offset: Offset(0, 2),
                      ),
                    ],
                  ),
                  child: TextField(
                    decoration: InputDecoration(
                      hintText: 'Поиск рецепта...',
                      hintStyle: TextStyle(color: Colors.grey[400]),
                      prefixIcon: Icon(Icons.search_rounded, color: AppColors.primaryGreen),
                      filled: true,
                      fillColor: Colors.white,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14.r),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 14.h),
                    ),
                    onChanged: (value) {
                      if (mounted) setState(() {
                        _searchQuery = value.toLowerCase();
                      });
                    },
                  ),
                ),
                SizedBox(height: 12),
                // Фильтр категорий
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14.r),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.08),
                        blurRadius: 6,
                        offset: Offset(0, 2),
                      ),
                    ],
                  ),
                  child: DropdownButtonFormField<String>(
                    value: _selectedCategory,
                    decoration: InputDecoration(
                      labelText: 'Категория',
                      labelStyle: TextStyle(color: AppColors.primaryGreen),
                      prefixIcon: Icon(Icons.category_rounded, color: AppColors.primaryGreen),
                      filled: true,
                      fillColor: Colors.white,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14.r),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 14.h),
                    ),
                    dropdownColor: Colors.white,
                    items: [
                      DropdownMenuItem<String>(
                        value: null,
                        child: Text('Все категории'),
                      ),
                      ..._categories.map((cat) => DropdownMenuItem(
                            value: cat,
                            child: Text(cat),
                          )),
                    ],
                    onChanged: (value) {
                      if (mounted) setState(() {
                        _selectedCategory = value;
                      });
                    },
                  ),
                ),
              ],
            ),
          ),
          SizedBox(height: 12),
          // Счетчик рецептов
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 20.w),
            child: Row(
              children: [
                Icon(Icons.menu_book_outlined, color: Colors.white70, size: 18),
                SizedBox(width: 8),
                Text(
                  'Всего рецептов: ${_filteredRecipes.length}',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 14.sp,
                  ),
                ),
              ],
            ),
          ),
          SizedBox(height: 8),
          // Список рецептов
          Expanded(
            child: _isLoading
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        CircularProgressIndicator(
                          valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                        ),
                        SizedBox(height: 16),
                        Text(
                          'Загрузка рецептов...',
                          style: TextStyle(color: Colors.white70, fontSize: 16.sp),
                        ),
                      ],
                    ),
                  )
                : _filteredRecipes.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.search_off_rounded, size: 64, color: Colors.white54),
                            SizedBox(height: 16),
                            Text(
                              'Рецепты не найдены',
                              style: TextStyle(color: Colors.white, fontSize: 18.sp),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        padding: EdgeInsets.all(16.w),
                        itemCount: _filteredRecipes.length,
                        itemBuilder: (context, index) {
                          final recipe = _filteredRecipes[index];
                          return _buildEditRecipeCard(recipe);
                        },
                      ),
          ),
        ],
      ),
    );
  }

  /// Карточка рецепта для редактирования
  Widget _buildEditRecipeCard(Recipe recipe) {
    return Container(
      margin: EdgeInsets.only(bottom: 12.h),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16.r),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.12),
            blurRadius: 10,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: EdgeInsets.all(12.w),
        child: Row(
          children: [
            // Фото рецепта
            Container(
              width: 70,
              height: 70,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12.r),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.primaryGreen.withOpacity(0.15),
                    blurRadius: 6,
                    offset: Offset(0, 2),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12.r),
                child: _buildRecipeImage(recipe),
              ),
            ),
            SizedBox(width: 14),
            // Информация
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    recipe.name,
                    style: TextStyle(
                      fontSize: 15.sp,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF2D2D2D),
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(Icons.category_outlined, size: 14, color: Colors.grey[500]),
                      SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          recipe.category,
                          style: TextStyle(
                            fontSize: 13.sp,
                            color: Colors.grey[600],
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  if (recipe.price != null && recipe.price!.isNotEmpty) ...[
                    SizedBox(height: 4),
                    Text(
                      '${recipe.price} руб.',
                      style: TextStyle(
                        fontSize: 14.sp,
                        fontWeight: FontWeight.w600,
                        color: AppColors.primaryGreen,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            // Кнопки действий
            Column(
              children: [
                // Редактировать
                Material(
                  color: Colors.blue.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10.r),
                  child: InkWell(
                    onTap: () => _editRecipe(recipe),
                    borderRadius: BorderRadius.circular(10.r),
                    child: Padding(
                      padding: EdgeInsets.all(10.w),
                      child: Icon(
                        Icons.edit_rounded,
                        color: Colors.blue[700],
                        size: 22,
                      ),
                    ),
                  ),
                ),
                SizedBox(height: 8),
                // Удалить
                Material(
                  color: Colors.red.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10.r),
                  child: InkWell(
                    onTap: () => _deleteRecipe(recipe),
                    borderRadius: BorderRadius.circular(10.r),
                    child: Padding(
                      padding: EdgeInsets.all(10.w),
                      child: Icon(
                        Icons.delete_rounded,
                        color: Colors.red[700],
                        size: 22,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// Изображение рецепта
  Widget _buildRecipeImage(Recipe recipe) {
    if (recipe.photoUrlOrId != null) {
      if (recipe.photoUrlOrId!.startsWith('http')) {
        return AppCachedImage(
          imageUrl: recipe.photoUrlOrId!,
          width: 70,
          height: 70,
          fit: BoxFit.cover,
          errorWidget: (_, __, ___) => _buildNoPhoto(),
        );
      } else {
        return Image.asset(
          'assets/images/${recipe.photoId}.jpg',
          width: 70,
          height: 70,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _buildNoPhoto(),
        );
      }
    }
    return _buildNoPhoto();
  }

  /// Заглушка без фото
  Widget _buildNoPhoto() {
    return Container(
      width: 70,
      height: 70,
      color: AppColors.primaryGreen.withOpacity(0.1),
      child: Icon(
        Icons.coffee_rounded,
        size: 32,
        color: AppColors.primaryGreen.withOpacity(0.4),
      ),
    );
  }
}
