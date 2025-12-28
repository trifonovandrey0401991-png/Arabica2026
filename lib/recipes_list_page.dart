import 'package:flutter/material.dart';
import 'recipe_model.dart';
import 'recipe_view_page.dart';
import 'recipe_edit_page.dart';
import 'recipe_list_edit_page.dart';
import 'user_role_service.dart';
import 'user_role_model.dart';
import 'core/utils/logger.dart';

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
          padding: const EdgeInsets.all(16),
          color: Colors.white.withOpacity(0.1),
          child: Column(
            children: [
              TextField(
                decoration: InputDecoration(
                  hintText: 'Поиск по названию...',
                  prefixIcon: const Icon(Icons.search),
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onChanged: (value) {
                  setState(() {
                    _searchQuery = value.toLowerCase();
                  });
                },
              ),
              const SizedBox(height: 12),
              FutureBuilder<List<String>>(
                future: Recipe.getUniqueCategories(),
                builder: (context, snapshot) {
                  if (snapshot.hasData) {
                    return DropdownButtonFormField<String>(
                      value: _selectedCategory,
                      decoration: InputDecoration(
                        labelText: 'Категория',
                        filled: true,
                        fillColor: Colors.white,
                        border: const OutlineInputBorder(),
                      ),
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
                return const Center(child: CircularProgressIndicator());
              }

              if (!snapshot.hasData || snapshot.data!.isEmpty) {
                return const Center(
                  child: Text(
                    'Рецепты не найдены',
                    style: TextStyle(color: Colors.white, fontSize: 18),
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
                return const Center(
                  child: Text(
                    'Рецепты не найдены',
                    style: TextStyle(color: Colors.white, fontSize: 18),
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
                      Padding(
                        padding: EdgeInsets.only(
                            bottom: 8, top: catIndex > 0 ? 16 : 0),
                        child: Text(
                          category,
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ),
                      ...categoryRecipes.map((recipe) => Card(
                            margin: const EdgeInsets.only(bottom: 8),
                            child: ListTile(
                              leading: recipe.photoUrlOrId != null
                                  ? ClipRRect(
                                      borderRadius: BorderRadius.circular(8),
                                      child: recipe.photoUrlOrId!.startsWith('http')
                                          ? Image.network(
                                              recipe.photoUrlOrId!,
                                              width: 50,
                                              height: 50,
                                              fit: BoxFit.cover,
                                              errorBuilder: (_, __, ___) =>
                                                  Image.asset(
                                                'assets/images/no_photo.png',
                                                width: 50,
                                                height: 50,
                                                fit: BoxFit.cover,
                                              ),
                                            )
                                          : Image.asset(
                                              'assets/images/${recipe.photoId}.jpg',
                                              width: 50,
                                              height: 50,
                                              fit: BoxFit.cover,
                                              errorBuilder: (_, __, ___) =>
                                                  Image.asset(
                                                'assets/images/no_photo.png',
                                                width: 50,
                                                height: 50,
                                                fit: BoxFit.cover,
                                              ),
                                            ),
                                    )
                                  : Image.asset(
                                      'assets/images/no_photo.png',
                                      width: 50,
                                      height: 50,
                                      fit: BoxFit.cover,
                                    ),
                              title: Text(
                                recipe.name,
                                style:
                                    const TextStyle(fontWeight: FontWeight.bold),
                              ),
                              subtitle: recipe.price != null && recipe.price!.isNotEmpty
                                  ? Text(
                                      '${recipe.price} ₽',
                                      style: const TextStyle(
                                        color: Colors.green,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    )
                                  : null,
                              trailing: const Icon(Icons.arrow_forward_ios),
                              onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) =>
                                        RecipeViewPage(recipe: recipe),
                                  ),
                                );
                              },
                            ),
                          )),
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
}
