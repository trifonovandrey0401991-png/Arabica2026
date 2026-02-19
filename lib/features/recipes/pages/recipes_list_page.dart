import 'package:flutter/material.dart';
import '../models/recipe_model.dart';
import 'recipe_view_page.dart';
import 'recipe_list_edit_page.dart';
import '../../employees/services/user_role_service.dart';
import '../../employees/models/user_role_model.dart';
import '../../../core/utils/logger.dart';
import '../../../shared/widgets/app_cached_image.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../../core/theme/app_colors.dart';

class RecipesListPage extends StatefulWidget {
  const RecipesListPage({super.key});

  @override
  State<RecipesListPage> createState() => _RecipesListPageState();
}

class _RecipesListPageState extends State<RecipesListPage> with TickerProviderStateMixin {
  TabController? _tabController;
  late Future<List<Recipe>> _recipesFuture;
  String _searchQuery = '';
  String? _selectedCategory;
  UserRole? _userRole;
  bool _isLoadingRole = true;

  @override
  void initState() {
    super.initState();
    _recipesFuture = Recipe.loadRecipesFromServer();
    _loadUserRole();
  }

  void _refreshRecipes() {
    if (mounted) setState(() {
      _recipesFuture = Recipe.loadRecipesFromServer();
    });
  }

  Future<void> _loadUserRole() async {
    try {
      final roleData = await UserRoleService.loadUserRole();
      if (mounted) {
        // Удаляем старый TabController, если он существует
        _tabController?.dispose();
        
        if (mounted) setState(() {
          _userRole = roleData?.role;
          _isLoadingRole = false;
          // Создаем TabController в зависимости от роли
          if (_userRole == UserRole.admin || _userRole == UserRole.developer) {
            _tabController = TabController(length: 2, vsync: this);
            _tabController!.addListener(() {
              if (_tabController!.index == 0 && !_tabController!.indexIsChanging) {
                _refreshRecipes();
              }
            });
          } else {
            _tabController = TabController(length: 1, vsync: this);
          }
        });
      }
    } catch (e) {
      Logger.error('❌ Ошибка загрузки роли', e);
      if (mounted) {
        _tabController?.dispose();
        if (mounted) setState(() {
          _isLoadingRole = false;
          _tabController = TabController(length: 1, vsync: this);
        });
      }
    }
  }

  @override
  void dispose() {
    _tabController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoadingRole) {
      return Scaffold(
        appBar: AppBar(
          title: Text('Рецепты'),
          backgroundColor: AppColors.primaryGreen,
        ),
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final isAdmin = _userRole == UserRole.admin || _userRole == UserRole.developer;

    return Scaffold(
      appBar: AppBar(
        title: Text('Рецепты'),
        backgroundColor: AppColors.primaryGreen,
        bottom: isAdmin && _tabController != null
            ? TabBar(
                controller: _tabController!,
                labelColor: Colors.white,
                unselectedLabelColor: Colors.white70,
                indicatorColor: Colors.white,
                tabs: [
                  Tab(text: 'Рецепты'),
                  Tab(text: 'Редактировать'),
                ],
              )
            : null,
      ),
      body: Container(
        decoration: BoxDecoration(
          color: AppColors.primaryGreen,
          image: DecorationImage(
            image: AssetImage('assets/images/arabica_background.png'),
            fit: BoxFit.cover,
            opacity: 0.6,
          ),
        ),
        child: isAdmin && _tabController != null
            ? TabBarView(
                controller: _tabController!,
                children: [
                  _buildRecipesList(),
                  RecipeListEditPage(),
                ],
              )
            : _buildRecipesList(),
      ),
    );
  }

  Widget _buildRecipesList() {
    return Column(
      children: [
        // Поиск и фильтр
        Container(
          padding: EdgeInsets.fromLTRB(16.w, 16.h, 16.w, 12.h),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.15),
            borderRadius: BorderRadius.only(
              bottomLeft: Radius.circular(24.r),
              bottomRight: Radius.circular(24.r),
            ),
          ),
          child: Column(
            children: [
              // Поле поиска
              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16.r),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.1),
                      blurRadius: 8,
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
                      borderRadius: BorderRadius.circular(16.r),
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
              FutureBuilder<List<String>>(
                future: Recipe.getUniqueCategories(),
                builder: (context, snapshot) {
                  if (snapshot.hasData) {
                    return Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16.r),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.1),
                            blurRadius: 8,
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
                            borderRadius: BorderRadius.circular(16.r),
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
                          ...snapshot.data!.map((cat) => DropdownMenuItem(
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
                    );
                  }
                  return SizedBox();
                },
              ),
            ],
          ),
        ),
        // Список рецептов
        Expanded(
          child: FutureBuilder<List<Recipe>>(
            future: _recipesFuture,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return Center(
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
                );
              }

              if (!snapshot.hasData || snapshot.data!.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.menu_book_outlined, size: 64, color: Colors.white54),
                      SizedBox(height: 16),
                      Text(
                        'Рецепты не найдены',
                        style: TextStyle(color: Colors.white, fontSize: 18.sp),
                      ),
                    ],
                  ),
                );
              }

              // Фильтрация
              var recipes = snapshot.data!;

              if (_searchQuery.isNotEmpty) {
                recipes = recipes
                    .where((r) => r.name.toLowerCase().contains(_searchQuery))
                    .toList();
              }

              if (_selectedCategory != null) {
                recipes = recipes.where((r) => r.category == _selectedCategory).toList();
              }

              if (recipes.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.search_off_rounded, size: 64, color: Colors.white54),
                      SizedBox(height: 16),
                      Text(
                        'Ничего не найдено',
                        style: TextStyle(color: Colors.white, fontSize: 18.sp),
                      ),
                      SizedBox(height: 8),
                      Text(
                        'Попробуйте изменить запрос',
                        style: TextStyle(color: Colors.white60, fontSize: 14.sp),
                      ),
                    ],
                  ),
                );
              }

              // Группировка по категориям
              final categories = recipes.map((r) => r.category).toSet().toList();
              categories.sort();

              return ListView.builder(
                padding: EdgeInsets.all(16.w),
                itemCount: categories.length,
                itemBuilder: (context, catIndex) {
                  final category = categories[catIndex];
                  final categoryRecipes =
                      recipes.where((r) => r.category == category).toList();

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Заголовок категории
                      Container(
                        margin: EdgeInsets.only(bottom: 12.h, top: catIndex > 0 ? 20 : 0),
                        padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 10.h),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              Colors.white.withOpacity(0.25),
                              Colors.white.withOpacity(0.1),
                            ],
                          ),
                          borderRadius: BorderRadius.circular(12.r),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              _getCategoryIcon(category),
                              color: Colors.white,
                              size: 24,
                            ),
                            SizedBox(width: 10),
                            Text(
                              category,
                              style: TextStyle(
                                fontSize: 18.sp,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                            Spacer(),
                            Container(
                              padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 4.h),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.2),
                                borderRadius: BorderRadius.circular(12.r),
                              ),
                              child: Text(
                                '${categoryRecipes.length}',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      // Карточки рецептов
                      ...categoryRecipes.map((recipe) => _buildRecipeCard(recipe)),
                    ],
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  /// Карточка рецепта
  Widget _buildRecipeCard(Recipe recipe) {
    return Container(
      margin: EdgeInsets.only(bottom: 12.h),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16.r),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.15),
            blurRadius: 10,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => RecipeViewPage(recipe: recipe),
              ),
            );
          },
          borderRadius: BorderRadius.circular(16.r),
          child: Padding(
            padding: EdgeInsets.all(12.w),
            child: Row(
              children: [
                // Фото рецепта
                Hero(
                  tag: 'recipe_photo_${recipe.id}',
                  child: Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14.r),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.primaryGreen.withOpacity(0.2),
                          blurRadius: 8,
                          offset: Offset(0, 2),
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(14.r),
                      child: _buildRecipeImage(recipe),
                    ),
                  ),
                ),
                SizedBox(width: 14),
                // Информация о рецепте
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        recipe.name,
                        style: TextStyle(
                          fontSize: 16.sp,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF2D2D2D),
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      SizedBox(height: 6),
                      if (recipe.price != null && recipe.price!.isNotEmpty)
                        Container(
                          padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 4.h),
                          decoration: BoxDecoration(
                            color: AppColors.primaryGreen.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(8.r),
                          ),
                          child: Text(
                            '${recipe.price} руб.',
                            style: TextStyle(
                              color: AppColors.primaryGreen,
                              fontWeight: FontWeight.bold,
                              fontSize: 14.sp,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                // Стрелка
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: AppColors.primaryGreen.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10.r),
                  ),
                  child: Icon(
                    Icons.arrow_forward_ios_rounded,
                    color: AppColors.primaryGreen,
                    size: 16,
                  ),
                ),
              ],
            ),
          ),
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
          width: 80,
          height: 80,
          fit: BoxFit.cover,
          errorWidget: (_, __, ___) => _buildNoPhoto(),
        );
      } else {
        return Image.asset(
          'assets/images/${recipe.photoId}.jpg',
          width: 80,
          height: 80,
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
      width: 80,
      height: 80,
      color: AppColors.primaryGreen.withOpacity(0.1),
      child: Icon(
        Icons.coffee_rounded,
        size: 36,
        color: AppColors.primaryGreen.withOpacity(0.4),
      ),
    );
  }

  /// Иконка для категории
  IconData _getCategoryIcon(String category) {
    final lowerCategory = category.toLowerCase();
    if (lowerCategory.contains('кофе') || lowerCategory.contains('coffee')) {
      return Icons.coffee_rounded;
    } else if (lowerCategory.contains('чай') || lowerCategory.contains('tea')) {
      return Icons.emoji_food_beverage_rounded;
    } else if (lowerCategory.contains('десерт') || lowerCategory.contains('выпечк')) {
      return Icons.cake_rounded;
    } else if (lowerCategory.contains('напиток') || lowerCategory.contains('лимонад') || lowerCategory.contains('смузи')) {
      return Icons.local_drink_rounded;
    } else if (lowerCategory.contains('молоч') || lowerCategory.contains('милкшейк')) {
      return Icons.icecream_rounded;
    } else if (lowerCategory.contains('завтрак') || lowerCategory.contains('еда')) {
      return Icons.restaurant_rounded;
    }
    return Icons.local_cafe_rounded;
  }
}
