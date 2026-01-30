import 'package:flutter/material.dart';
import '../models/recipe_model.dart';
import 'recipe_view_page.dart';
import 'recipe_list_edit_page.dart';
import '../../employees/services/user_role_service.dart';
import '../../employees/models/user_role_model.dart';
import '../../../core/utils/logger.dart';

class RecipesListPage extends StatefulWidget {
  const RecipesListPage({super.key});

  @override
  State<RecipesListPage> createState() => _RecipesListPageState();
}

class _RecipesListPageState extends State<RecipesListPage> with TickerProviderStateMixin {
  static const _primaryColor = Color(0xFF004D40);
  static const _primaryColorLight = Color(0xFF00695C);

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
    setState(() {
      _recipesFuture = Recipe.loadRecipesFromServer();
    });
  }

  Future<void> _loadUserRole() async {
    try {
      final roleData = await UserRoleService.loadUserRole();
      if (mounted) {
        // Удаляем старый TabController, если он существует
        _tabController?.dispose();
        
        setState(() {
          _userRole = roleData?.role;
          _isLoadingRole = false;
          // Создаем TabController в зависимости от роли
          if (_userRole == UserRole.admin) {
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
        setState(() {
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
          title: const Text('Рецепты'),
          backgroundColor: const Color(0xFF004D40),
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final isAdmin = _userRole == UserRole.admin;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Рецепты'),
        backgroundColor: const Color(0xFF004D40),
        bottom: isAdmin && _tabController != null
            ? TabBar(
                controller: _tabController!,
                labelColor: Colors.white,
                unselectedLabelColor: Colors.white70,
                indicatorColor: Colors.white,
                tabs: const [
                  Tab(text: 'Рецепты'),
                  Tab(text: 'Редактировать'),
                ],
              )
            : null,
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
        child: isAdmin && _tabController != null
            ? TabBarView(
                controller: _tabController!,
                children: [
                  _buildRecipesList(),
                  const RecipeListEditPage(),
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
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.15),
            borderRadius: const BorderRadius.only(
              bottomLeft: Radius.circular(24),
              bottomRight: Radius.circular(24),
            ),
          ),
          child: Column(
            children: [
              // Поле поиска
              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.1),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: TextField(
                  decoration: InputDecoration(
                    hintText: 'Поиск рецепта...',
                    hintStyle: TextStyle(color: Colors.grey[400]),
                    prefixIcon: Icon(Icons.search_rounded, color: _primaryColor),
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  ),
                  onChanged: (value) {
                    setState(() {
                      _searchQuery = value.toLowerCase();
                    });
                  },
                ),
              ),
              const SizedBox(height: 12),
              // Фильтр категорий
              FutureBuilder<List<String>>(
                future: Recipe.getUniqueCategories(),
                builder: (context, snapshot) {
                  if (snapshot.hasData) {
                    return Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.1),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: DropdownButtonFormField<String>(
                        value: _selectedCategory,
                        decoration: InputDecoration(
                          labelText: 'Категория',
                          labelStyle: TextStyle(color: _primaryColor),
                          prefixIcon: Icon(Icons.category_rounded, color: _primaryColor),
                          filled: true,
                          fillColor: Colors.white,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: BorderSide.none,
                          ),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                        ),
                        dropdownColor: Colors.white,
                        items: [
                          const DropdownMenuItem<String>(
                            value: null,
                            child: Text('Все категории'),
                          ),
                          ...snapshot.data!.map((cat) => DropdownMenuItem(
                                value: cat,
                                child: Text(cat),
                              )),
                        ],
                        onChanged: (value) {
                          setState(() {
                            _selectedCategory = value;
                          });
                        },
                      ),
                    );
                  }
                  return const SizedBox();
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
                      const SizedBox(height: 16),
                      const Text(
                        'Загрузка рецептов...',
                        style: TextStyle(color: Colors.white70, fontSize: 16),
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
                      const SizedBox(height: 16),
                      const Text(
                        'Рецепты не найдены',
                        style: TextStyle(color: Colors.white, fontSize: 18),
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
                      const SizedBox(height: 16),
                      const Text(
                        'Ничего не найдено',
                        style: TextStyle(color: Colors.white, fontSize: 18),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Попробуйте изменить запрос',
                        style: TextStyle(color: Colors.white60, fontSize: 14),
                      ),
                    ],
                  ),
                );
              }

              // Группировка по категориям
              final categories = recipes.map((r) => r.category).toSet().toList();
              categories.sort();

              return ListView.builder(
                padding: const EdgeInsets.all(16),
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
                        margin: EdgeInsets.only(bottom: 12, top: catIndex > 0 ? 20 : 0),
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              Colors.white.withOpacity(0.25),
                              Colors.white.withOpacity(0.1),
                            ],
                          ),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              _getCategoryIcon(category),
                              color: Colors.white,
                              size: 24,
                            ),
                            const SizedBox(width: 10),
                            Text(
                              category,
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                            const Spacer(),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.2),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                '${categoryRecipes.length}',
                                style: const TextStyle(
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
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.15),
            blurRadius: 10,
            offset: const Offset(0, 4),
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
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                // Фото рецепта
                Hero(
                  tag: 'recipe_photo_${recipe.id}',
                  child: Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: [
                        BoxShadow(
                          color: _primaryColor.withOpacity(0.2),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: _buildRecipeImage(recipe),
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                // Информация о рецепте
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        recipe.name,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF2D2D2D),
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 6),
                      if (recipe.price != null && recipe.price!.isNotEmpty)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: _primaryColor.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            '${recipe.price} руб.',
                            style: TextStyle(
                              color: _primaryColor,
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
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
                    color: _primaryColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    Icons.arrow_forward_ios_rounded,
                    color: _primaryColor,
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
        return Image.network(
          recipe.photoUrlOrId!,
          width: 80,
          height: 80,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _buildNoPhoto(),
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
      color: _primaryColor.withOpacity(0.1),
      child: Icon(
        Icons.coffee_rounded,
        size: 36,
        color: _primaryColor.withOpacity(0.4),
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
