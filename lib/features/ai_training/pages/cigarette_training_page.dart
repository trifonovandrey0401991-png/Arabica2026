import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/cigarette_training_model.dart';
import '../services/cigarette_vision_service.dart';
import '../../employees/pages/employees_page.dart';
import '../../shops/services/shop_service.dart';
import '../../shops/models/shop_model.dart';
import 'cigarette_annotation_page.dart';
import 'photo_templates_page.dart';
import 'training_settings_page.dart';
import 'pending_codes_page.dart';

/// Страница обучения ИИ распознаванию сигарет - Премиум версия
class CigaretteTrainingPage extends StatefulWidget {
  const CigaretteTrainingPage({super.key});

  @override
  State<CigaretteTrainingPage> createState() => _CigaretteTrainingPageState();
}

class _CigaretteTrainingPageState extends State<CigaretteTrainingPage>
    with SingleTickerProviderStateMixin {
  TabController? _tabController;

  List<CigaretteProduct> _products = [];
  List<String> _productGroups = [];
  TrainingStats _stats = TrainingStats.empty();

  String? _selectedGroup;
  bool _isLoading = true;
  String? _error;
  bool _isAdmin = false;

  // НОВОЕ: Выбранный магазин для per-shop прогресса
  String? _selectedShopAddress;
  List<Shop> _shops = [];

  // Поиск по наименованию
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  // Цвета и градиенты
  static const _greenGradient = [Color(0xFF10B981), Color(0xFF34D399)];
  static const _blueGradient = [Color(0xFF3B82F6), Color(0xFF60A5FA)];
  static const _orangeGradient = [Color(0xFFF59E0B), Color(0xFFFBBF24)];
  static const _purpleGradient = [Color(0xFF6366F1), Color(0xFF8B5CF6)];
  static const _redGradient = [Color(0xFFEF4444), Color(0xFFF87171)];

  /// Количество вкладок зависит от роли
  /// Для админа: Фото, Товары, Новые коды, Статистика, Настройки = 5
  /// Для сотрудника: Фото, Статистика = 2
  int get _tabCount => _isAdmin ? 5 : 2;

  @override
  void initState() {
    super.initState();
    _initializePageSequentially();
  }

  /// Инициализация страницы последовательно (сначала контроллер, потом данные)
  Future<void> _initializePageSequentially() async {
    await _initTabController();
    await _loadData();

    // ВСЕГДА показываем диалог выбора магазина для сотрудников при входе
    // (сотрудник может работать в разных магазинах)
    if (mounted && !_isAdmin) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _showShopSelectionDialog();
        }
      });
    }
  }

  Future<void> _initTabController() async {
    final prefs = await SharedPreferences.getInstance();
    final role = prefs.getString('user_role') ?? '';
    final shopAddress = prefs.getString('selectedShopAddress');

    // Загружаем магазины для диалога выбора
    final shops = await ShopService.getShops();

    if (mounted) {
      setState(() {
        _isAdmin = role == 'admin';
        _selectedShopAddress = shopAddress;
        _shops = shops;
        _tabController = TabController(length: _tabCount, vsync: this);
      });
    }
  }

  @override
  void dispose() {
    _tabController?.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      // Перезагружаем выбранный магазин из SharedPreferences
      // (важно для корректного отображения per-shop прогресса)
      final prefs = await SharedPreferences.getInstance();
      final shopAddress = prefs.getString('selectedShopAddress');

      final groups = await CigaretteVisionService.getProductGroups();
      final products = await CigaretteVisionService.getProducts(
        productGroup: _selectedGroup,
      );
      final stats = await CigaretteVisionService.getStats();

      if (mounted) {
        setState(() {
          _selectedShopAddress = shopAddress;
          _productGroups = groups;
          _products = products;
          _stats = stats;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Ошибка загрузки данных: $e';
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFF1A1A2E),
              Color(0xFF16213E),
              Color(0xFF0F3460),
            ],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              // Custom AppBar
              _buildCustomAppBar(),

              // TabBar
              _buildTabBar(),

              // Контент
              Expanded(
                child: _isLoading || _tabController == null
                    ? const Center(
                        child: CircularProgressIndicator(color: Colors.white),
                      )
                    : _error != null
                        ? _buildErrorView()
                        : TabBarView(
                            controller: _tabController,
                            children: [
                              _buildAddPhotoTab(),
                              // Вкладка "Товары" только для админа
                              if (_isAdmin) _buildProductsTab(),
                              if (_isAdmin) PendingCodesPage(onCodeApproved: _loadData),
                              _buildStatsTab(),
                              if (_isAdmin) _buildSettingsTab(),
                            ],
                          ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCustomAppBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.pop(context),
            icon: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(
                Icons.arrow_back_ios_new,
                color: Colors.white,
                size: 20,
              ),
            ),
          ),
          const Expanded(
            child: Text(
              'Подсчёт сигарет',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 48),
        ],
      ),
    );
  }

  Widget _buildTabBar() {
    if (_tabController == null) {
      return const SizedBox.shrink();
    }

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Colors.white.withOpacity(0.1),
          width: 1,
        ),
      ),
      child: TabBar(
        controller: _tabController,
        indicator: BoxDecoration(
          gradient: const LinearGradient(colors: _greenGradient),
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: _greenGradient[0].withOpacity(0.4),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        indicatorSize: TabBarIndicatorSize.tab,
        indicatorPadding: const EdgeInsets.all(4),
        dividerColor: Colors.transparent,
        labelColor: Colors.white,
        unselectedLabelColor: Colors.white.withOpacity(0.5),
        labelStyle: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
        unselectedLabelStyle: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w500,
        ),
        tabs: [
          const Tab(
            icon: Icon(Icons.add_a_photo, size: 20),
            text: 'Фото',
          ),
          // Вкладка "Товары" только для админа
          if (_isAdmin)
            const Tab(
              icon: Icon(Icons.inventory_2, size: 20),
              text: 'Товары',
            ),
          if (_isAdmin)
            const Tab(
              icon: Icon(Icons.new_releases, size: 20),
              text: 'Новые',
            ),
          const Tab(
            icon: Icon(Icons.bar_chart, size: 20),
            text: 'Статистика',
          ),
          if (_isAdmin)
            const Tab(
              icon: Icon(Icons.settings, size: 20),
              text: 'Настройки',
            ),
        ],
      ),
    );
  }

  Widget _buildErrorView() {
    return Center(
      child: Container(
        margin: const EdgeInsets.all(24),
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.05),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: Colors.red.withOpacity(0.3),
            width: 1,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                gradient: const LinearGradient(colors: _redGradient),
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Icon(Icons.error_outline, size: 32, color: Colors.white),
            ),
            const SizedBox(height: 16),
            Text(
              _error ?? 'Неизвестная ошибка',
              style: TextStyle(
                color: Colors.white.withOpacity(0.7),
                fontSize: 14,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            _buildGradientButton(
              onTap: _loadData,
              gradient: _greenGradient,
              icon: Icons.refresh,
              label: 'Повторить',
            ),
          ],
        ),
      ),
    );
  }

  /// Вкладка добавления фото
  Widget _buildAddPhotoTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Информационная карточка
        _buildInfoCard(
          icon: Icons.info_outline,
          title: 'Как добавлять фото',
          description:
              '1. Выберите товар из списка ниже\n'
              '2. Сфотографируйте товар на полке\n'
              '3. ИИ определит достаточно ли фото для обучения\n\n'
              'Чем больше разных фото - тем точнее будет распознавание!',
          gradient: _blueGradient,
        ),
        const SizedBox(height: 16),

        // Фильтр по группе
        if (_productGroups.isNotEmpty) ...[
          _buildGroupDropdown(),
          const SizedBox(height: 16),
        ],

        // Список товаров для добавления фото
        ..._products.map((product) => _buildProductCard(product, forUpload: true)),
      ],
    );
  }

  /// Вкладка списка товаров
  Widget _buildProductsTab() {
    // Фильтруем по поиску
    var filteredProducts = _products.where((product) {
      if (_searchQuery.isEmpty) return true;
      return product.productName.toLowerCase().contains(_searchQuery.toLowerCase());
    }).toList();

    // Сортируем: сначала с меньшим прогрессом
    filteredProducts.sort((a, b) => a.trainingProgress.compareTo(b.trainingProgress));

    return RefreshIndicator(
      onRefresh: _loadData,
      color: _greenGradient[0],
      backgroundColor: const Color(0xFF1A1A2E),
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Поиск по наименованию
          _buildSearchField(),
          const SizedBox(height: 12),

          // Фильтр по группе
          if (_productGroups.isNotEmpty) ...[
            _buildGroupDropdown(),
            const SizedBox(height: 16),
          ],

          // Счётчик найденных товаров
          if (_searchQuery.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                'Найдено: ${filteredProducts.length} из ${_products.length}',
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.white.withOpacity(0.6),
                ),
              ),
            ),
          ],

          // Список товаров
          ...filteredProducts.map((product) => _buildProductCard(product)),
        ],
      ),
    );
  }

  /// Поле поиска по наименованию
  Widget _buildSearchField() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Colors.white.withOpacity(0.1),
          width: 1,
        ),
      ),
      child: TextField(
        controller: _searchController,
        style: const TextStyle(color: Colors.white),
        decoration: InputDecoration(
          hintText: 'Поиск по наименованию...',
          hintStyle: TextStyle(color: Colors.white.withOpacity(0.4)),
          prefixIcon: Icon(
            Icons.search,
            color: Colors.white.withOpacity(0.5),
          ),
          suffixIcon: _searchQuery.isNotEmpty
              ? IconButton(
                  icon: Icon(
                    Icons.clear,
                    color: Colors.white.withOpacity(0.5),
                  ),
                  onPressed: () {
                    _searchController.clear();
                    setState(() {
                      _searchQuery = '';
                    });
                  },
                )
              : null,
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        ),
        onChanged: (value) {
          setState(() {
            _searchQuery = value;
          });
        },
      ),
    );
  }

  /// Вкладка статистики
  Widget _buildStatsTab() {
    return RefreshIndicator(
      onRefresh: _loadData,
      color: _greenGradient[0],
      backgroundColor: const Color(0xFF1A1A2E),
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Общий прогресс
          _buildOverallProgressCard(),
          const SizedBox(height: 16),

          // Статистика товаров
          Row(
            children: [
              Expanded(
                child: _buildStatCard(
                  'Всего товаров',
                  _stats.totalProducts.toString(),
                  Icons.inventory_2,
                  _blueGradient,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildStatCard(
                  'С фото',
                  _stats.productsWithPhotos.toString(),
                  Icons.photo_library,
                  _orangeGradient,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _buildStatCard(
                  'Обучены',
                  _stats.productsFullyTrained.toString(),
                  Icons.check_circle,
                  _greenGradient,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildStatCard(
                  'Нужно фото',
                  '${_stats.totalProducts - _stats.productsFullyTrained}',
                  Icons.add_a_photo,
                  _redGradient,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Статистика фото
          _buildPhotoStatsCard(),
          const SizedBox(height: 16),

          // Инструкция
          _buildInfoCard(
            icon: Icons.lightbulb,
            title: 'Как ускорить обучение',
            description:
                '• Крупный план: 10 фото с 1-3 пачками вблизи\n'
                '• Выкладка: 10 фото витрины с 5-15 пачками\n'
                '• Фотографируйте с разных ракурсов\n'
                '• Делайте фото при разном освещении',
            gradient: _orangeGradient,
          ),
        ],
      ),
    );
  }

  /// Вкладка настроек
  Widget _buildSettingsTab() {
    return TrainingSettingsPage(
      products: _products,
      onSettingsChanged: _loadData,
    );
  }

  Widget _buildInfoCard({
    required IconData icon,
    required String title,
    required String description,
    required List<Color> gradient,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Colors.white.withOpacity(0.1),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: gradient),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: Colors.white, size: 20),
              ),
              const SizedBox(width: 12),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            description,
            style: TextStyle(
              fontSize: 13,
              color: Colors.white.withOpacity(0.7),
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGroupDropdown() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Colors.white.withOpacity(0.1),
          width: 1,
        ),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: _selectedGroup,
          isExpanded: true,
          dropdownColor: const Color(0xFF1A1A2E),
          icon: Icon(Icons.expand_more, color: Colors.white.withOpacity(0.5)),
          hint: Row(
            children: [
              Icon(Icons.filter_list, color: Colors.white.withOpacity(0.5), size: 20),
              const SizedBox(width: 12),
              Text(
                'Все группы',
                style: TextStyle(color: Colors.white.withOpacity(0.7)),
              ),
            ],
          ),
          items: [
            DropdownMenuItem(
              value: null,
              child: Row(
                children: [
                  Icon(Icons.filter_list, color: Colors.white.withOpacity(0.5), size: 20),
                  const SizedBox(width: 12),
                  const Text('Все группы', style: TextStyle(color: Colors.white)),
                ],
              ),
            ),
            ..._productGroups.map((group) => DropdownMenuItem(
              value: group,
              child: Text(group, style: const TextStyle(color: Colors.white)),
            )),
          ],
          onChanged: (value) {
            setState(() {
              _selectedGroup = value;
            });
            _loadData();
          },
        ),
      ),
    );
  }

  Widget _buildOverallProgressCard() {
    final progress = _stats.overallProgress / 100;
    final progressColor = _getProgressGradient(_stats.overallProgress);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: Colors.white.withOpacity(0.1),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: progressColor),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.trending_up, color: Colors.white, size: 24),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'Общий прогресс обучения',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
              ),
              ShaderMask(
                shaderCallback: (bounds) => LinearGradient(colors: progressColor).createShader(bounds),
                child: Text(
                  '${_stats.overallProgress.toStringAsFixed(1)}%',
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            height: 12,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.1),
              borderRadius: BorderRadius.circular(6),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: Stack(
                children: [
                  FractionallySizedBox(
                    widthFactor: progress,
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(colors: progressColor),
                        borderRadius: BorderRadius.circular(6),
                        boxShadow: [
                          BoxShadow(
                            color: progressColor[0].withOpacity(0.5),
                            blurRadius: 8,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard(
    String title,
    String value,
    IconData icon,
    List<Color> gradient,
  ) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Colors.white.withOpacity(0.1),
          width: 1,
        ),
      ),
      child: Column(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: gradient),
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: gradient[0].withOpacity(0.4),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Icon(icon, color: Colors.white, size: 24),
          ),
          const SizedBox(height: 12),
          ShaderMask(
            shaderCallback: (bounds) => LinearGradient(colors: gradient).createShader(bounds),
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            title,
            style: TextStyle(
              fontSize: 12,
              color: Colors.white.withOpacity(0.6),
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildPhotoStatsCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: Colors.white.withOpacity(0.1),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: _purpleGradient),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.photo_library, color: Colors.white, size: 20),
              ),
              const SizedBox(width: 12),
              const Text(
                'Загружено фотографий',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: _buildPhotoStatItem(
                  icon: Icons.crop_free,
                  label: 'Для пересчёта',
                  value: _stats.totalRecountPhotos,
                  gradient: _blueGradient,
                ),
              ),
              Container(
                width: 1,
                height: 60,
                color: Colors.white.withOpacity(0.1),
              ),
              Expanded(
                child: _buildPhotoStatItem(
                  icon: Icons.grid_view,
                  label: 'Для выкладки',
                  value: _stats.totalDisplayPhotos,
                  gradient: _greenGradient,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPhotoStatItem({
    required IconData icon,
    required String label,
    required int value,
    required List<Color> gradient,
  }) {
    return Column(
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: gradient),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: Colors.white, size: 20),
        ),
        const SizedBox(height: 8),
        ShaderMask(
          shaderCallback: (bounds) => LinearGradient(colors: gradient).createShader(bounds),
          child: Text(
            '$value',
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
        ),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: Colors.white.withOpacity(0.6),
          ),
        ),
      ],
    );
  }

  Widget _buildProductCard(CigaretteProduct product, {bool forUpload = false}) {
    final progressGradient = _getProgressGradient(product.trainingProgress);
    final recountGradient = _getProgressGradient(product.recountProgress);
    final displayGradient = _getProgressGradient(product.displayProgress);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Colors.white.withOpacity(0.1),
          width: 1,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: forUpload ? () => _showPhotoTypeDialog(product) : () => _showProductDetails(product),
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                // Иконка статуса
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(colors: progressGradient),
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: [
                      BoxShadow(
                        color: progressGradient[0].withOpacity(0.4),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Icon(
                    product.isTrainingComplete
                        ? Icons.check_circle
                        : Icons.add_a_photo,
                    color: Colors.white,
                    size: 26,
                  ),
                ),
                const SizedBox(width: 14),

                // Информация о товаре
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        product.productName,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (product.productGroup.isNotEmpty)
                        Text(
                          product.productGroup,
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.white.withOpacity(0.5),
                          ),
                        ),
                      const SizedBox(height: 8),
                      // Раздельный прогресс: крупный план
                      _buildProgressRow(
                        icon: Icons.crop_free,
                        progress: product.recountProgress / 100,
                        label: '${product.recountPhotosCount}/${product.requiredRecountPhotos}',
                        gradient: recountGradient,
                        isComplete: product.isRecountComplete,
                      ),
                      const SizedBox(height: 6),
                      // Раздельный прогресс: выкладка (per-shop)
                      if (_isAdmin)
                        // Админ видит сводку по всем магазинам
                        _buildShopsSummaryRow(product, displayGradient)
                      else if (_selectedShopAddress != null && _selectedShopAddress!.isNotEmpty)
                        // Сотрудник видит прогресс своего магазина
                        _buildShopProgressRow(product, displayGradient)
                      else
                        // Магазин не выбран
                        _buildNoShopSelectedRow(),
                    ],
                  ),
                ),

                // Кнопка добавления фото
                if (forUpload)
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      Icons.camera_alt,
                      color: Colors.white.withOpacity(0.7),
                      size: 22,
                    ),
                  ),

                // Toggle ИИ проверки (только на вкладке Товары)
                if (!forUpload && _isAdmin)
                  _buildAiToggle(product),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildProgressRow({
    required IconData icon,
    required double progress,
    required String label,
    required List<Color> gradient,
    required bool isComplete,
  }) {
    return Row(
      children: [
        Icon(
          icon,
          size: 14,
          color: isComplete ? _greenGradient[0] : gradient[0],
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Container(
            height: 4,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.1),
              borderRadius: BorderRadius.circular(2),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: FractionallySizedBox(
                alignment: Alignment.centerLeft,
                widthFactor: progress.clamp(0.0, 1.0),
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(colors: isComplete ? _greenGradient : gradient),
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          label,
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w600,
            color: isComplete ? _greenGradient[0] : gradient[0],
          ),
        ),
        if (isComplete) ...[
          const SizedBox(width: 4),
          Icon(Icons.check_circle, size: 12, color: _greenGradient[0]),
        ],
      ],
    );
  }

  /// Сводка по магазинам для админа (X/Y магазинов готовы)
  Widget _buildShopsSummaryRow(CigaretteProduct product, List<Color> gradient) {
    final ready = product.shopsWithAiReady;
    final total = product.totalShops;
    final isComplete = ready > 0;
    final progress = total > 0 ? ready / total : 0.0;
    final summaryGradient = _getProgressGradient(progress * 100);

    return InkWell(
      onTap: () => _showShopDetailsDialog(product),
      child: Row(
        children: [
          Icon(
            Icons.store,
            size: 14,
            color: isComplete ? _greenGradient[0] : summaryGradient[0],
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Container(
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.1),
                borderRadius: BorderRadius.circular(2),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child: FractionallySizedBox(
                  alignment: Alignment.centerLeft,
                  widthFactor: progress.clamp(0.0, 1.0),
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(colors: isComplete ? _greenGradient : summaryGradient),
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '$ready/$total маг.',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: isComplete ? _greenGradient[0] : summaryGradient[0],
            ),
          ),
          const SizedBox(width: 4),
          Icon(
            Icons.chevron_right,
            size: 14,
            color: Colors.white.withOpacity(0.5),
          ),
        ],
      ),
    );
  }

  /// Прогресс для конкретного магазина (сотрудник)
  Widget _buildShopProgressRow(CigaretteProduct product, List<Color> gradient) {
    final shopStats = product.getShopStats(_selectedShopAddress ?? '');
    if (shopStats == null) {
      return _buildNoShopSelectedRow();
    }

    final isComplete = shopStats.isDisplayComplete;
    final progress = shopStats.progress / 100;
    final shopGradient = _getProgressGradient(shopStats.progress);

    return Row(
      children: [
        Icon(
          Icons.grid_view,
          size: 14,
          color: isComplete ? _greenGradient[0] : shopGradient[0],
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Container(
            height: 4,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.1),
              borderRadius: BorderRadius.circular(2),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: FractionallySizedBox(
                alignment: Alignment.centerLeft,
                widthFactor: progress.clamp(0.0, 1.0),
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(colors: isComplete ? _greenGradient : shopGradient),
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          '${shopStats.displayPhotosCount}/${shopStats.requiredDisplayPhotos}',
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w600,
            color: isComplete ? _greenGradient[0] : shopGradient[0],
          ),
        ),
        if (isComplete) ...[
          const SizedBox(width: 4),
          Icon(Icons.check_circle, size: 12, color: _greenGradient[0]),
        ],
      ],
    );
  }

  /// Магазин не выбран
  Widget _buildNoShopSelectedRow() {
    return InkWell(
      onTap: _showShopSelectionDialog,
      child: Row(
        children: [
          Icon(
            Icons.warning_amber,
            size: 14,
            color: _orangeGradient[0],
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              'Выберите магазин',
              style: TextStyle(
                fontSize: 10,
                color: _orangeGradient[0],
              ),
            ),
          ),
          Icon(
            Icons.chevron_right,
            size: 14,
            color: _orangeGradient[0],
          ),
        ],
      ),
    );
  }

  /// Диалог выбора магазина
  void _showShopSelectionDialog() {
    if (_shops.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Не удалось загрузить список магазинов'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.7,
        ),
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFF1A1A2E),
              Color(0xFF16213E),
            ],
          ),
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Индикатор
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            // Заголовок
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(colors: _blueGradient),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Icon(
                      Icons.store,
                      color: Colors.white,
                      size: 28,
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Выберите магазин',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Для загрузки фото выкладки нужно выбрать магазин',
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.white.withOpacity(0.6),
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
            // Список магазинов
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: _shops.length,
                itemBuilder: (context, index) {
                  final shop = _shops[index];
                  final isSelected = shop.address == _selectedShopAddress;

                  return Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: () async {
                          // Сохраняем выбранный магазин
                          final prefs = await SharedPreferences.getInstance();
                          await prefs.setString('selectedShopAddress', shop.address);

                          if (mounted) {
                            setState(() {
                              _selectedShopAddress = shop.address;
                            });
                            Navigator.pop(context);

                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Row(
                                  children: [
                                    const Icon(Icons.check_circle, color: Colors.white, size: 20),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Text('Выбран магазин: ${shop.name}'),
                                    ),
                                  ],
                                ),
                                backgroundColor: _greenGradient[0],
                                duration: const Duration(seconds: 2),
                              ),
                            );

                            // Перезагружаем данные для обновления статистики
                            _loadData();
                          }
                        },
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? _blueGradient[0].withOpacity(0.2)
                                : Colors.white.withOpacity(0.05),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: isSelected
                                  ? _blueGradient[0]
                                  : Colors.white.withOpacity(0.1),
                              width: isSelected ? 2 : 1,
                            ),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 40,
                                height: 40,
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    colors: isSelected ? _blueGradient : _purpleGradient,
                                  ),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Icon(
                                  isSelected ? Icons.check : Icons.store,
                                  color: Colors.white,
                                  size: 20,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      shop.name,
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                        color: isSelected ? _blueGradient[0] : Colors.white,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      shop.address,
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.white.withOpacity(0.5),
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                ),
                              ),
                              if (isSelected)
                                Icon(
                                  Icons.check_circle,
                                  color: _blueGradient[0],
                                  size: 24,
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            // Кнопка закрытия
            Padding(
              padding: const EdgeInsets.all(16),
              child: TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(
                  'Отмена',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.6),
                    fontSize: 14,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Диалог детализации по магазинам (для админа)
  void _showShopDetailsDialog(CigaretteProduct product) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.7,
        ),
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFF1A1A2E),
              Color(0xFF16213E),
            ],
          ),
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Индикатор
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            // Заголовок
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Text(
                    'Статус по магазинам',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    product.productName,
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.white.withOpacity(0.6),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: _getProgressGradient(
                          product.totalShops > 0
                            ? product.shopsWithAiReady / product.totalShops * 100
                            : 0,
                        ),
                      ),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      '${product.shopsWithAiReady}/${product.totalShops} магазинов готовы',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // Список магазинов
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: product.perShopDisplayStats.length,
                itemBuilder: (context, index) {
                  final stats = product.perShopDisplayStats[index];
                  final shopGradient = _getProgressGradient(stats.progress);

                  return Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.05),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: stats.isDisplayComplete
                            ? _greenGradient[0].withOpacity(0.5)
                            : Colors.white.withOpacity(0.1),
                        width: 1,
                      ),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: stats.isDisplayComplete ? _greenGradient : shopGradient,
                            ),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Icon(
                            stats.isDisplayComplete ? Icons.check : Icons.store,
                            color: Colors.white,
                            size: 18,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                stats.shopName ?? stats.shopAddress,
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.white,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  Expanded(
                                    child: Container(
                                      height: 4,
                                      decoration: BoxDecoration(
                                        color: Colors.white.withOpacity(0.1),
                                        borderRadius: BorderRadius.circular(2),
                                      ),
                                      child: ClipRRect(
                                        borderRadius: BorderRadius.circular(2),
                                        child: FractionallySizedBox(
                                          alignment: Alignment.centerLeft,
                                          widthFactor: (stats.progress / 100).clamp(0.0, 1.0),
                                          child: Container(
                                            decoration: BoxDecoration(
                                              gradient: LinearGradient(
                                                colors: stats.isDisplayComplete ? _greenGradient : shopGradient,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    '${stats.displayPhotosCount}/${stats.requiredDisplayPhotos}',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                      color: stats.isDisplayComplete ? _greenGradient[0] : shopGradient[0],
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  /// Toggle для включения/выключения ИИ проверки товара
  Widget _buildAiToggle(CigaretteProduct product) {
    return Column(
      children: [
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: product.isAiActive
                ? _greenGradient[0].withOpacity(0.2)
                : Colors.white.withOpacity(0.05),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: product.isAiActive
                  ? _greenGradient[0].withOpacity(0.5)
                  : Colors.white.withOpacity(0.1),
              width: 1,
            ),
          ),
          child: IconButton(
            onPressed: () => _toggleAiStatus(product),
            icon: Icon(
              product.isAiActive ? Icons.smart_toy : Icons.smart_toy_outlined,
              color: product.isAiActive ? _greenGradient[0] : Colors.white.withOpacity(0.4),
              size: 24,
            ),
            tooltip: product.isAiActive ? 'ИИ проверка включена' : 'ИИ проверка выключена',
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'ИИ',
          style: TextStyle(
            fontSize: 9,
            color: product.isAiActive ? _greenGradient[0] : Colors.white.withOpacity(0.4),
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  /// Переключить статус ИИ проверки
  Future<void> _toggleAiStatus(CigaretteProduct product) async {
    final newStatus = !product.isAiActive;

    // Показываем индикатор загрузки
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
              ),
            ),
            const SizedBox(width: 12),
            Text(newStatus ? 'Включаю ИИ проверку...' : 'Выключаю ИИ проверку...'),
          ],
        ),
        duration: const Duration(seconds: 1),
        backgroundColor: const Color(0xFF1A1A2E),
      ),
    );

    final success = await CigaretteVisionService.updateProductAiStatus(
      productId: product.id,
      isAiActive: newStatus,
    );

    if (!mounted) return;

    if (success) {
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(
                newStatus ? Icons.check_circle : Icons.cancel,
                color: Colors.white,
                size: 20,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  newStatus
                      ? 'ИИ проверка включена для "${product.productName}"'
                      : 'ИИ проверка выключена для "${product.productName}"',
                ),
              ),
            ],
          ),
          backgroundColor: newStatus ? _greenGradient[0] : Colors.grey[700],
          duration: const Duration(seconds: 2),
        ),
      );

      // Перезагружаем данные
      _loadData();
    } else {
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Row(
            children: [
              Icon(Icons.error_outline, color: Colors.white, size: 20),
              SizedBox(width: 12),
              Text('Ошибка изменения статуса ИИ'),
            ],
          ),
          backgroundColor: _redGradient[0],
        ),
      );
    }
  }

  List<Color> _getProgressGradient(double progress) {
    if (progress >= 100) return _greenGradient;
    if (progress >= 50) return _orangeGradient;
    if (progress >= 25) return _blueGradient;
    return _redGradient;
  }

  Color _getProgressColor(double progress) {
    if (progress >= 100) return _greenGradient[0];
    if (progress >= 50) return _orangeGradient[0];
    if (progress >= 25) return _blueGradient[0];
    return _redGradient[0];
  }

  Widget _buildGradientButton({
    required VoidCallback onTap,
    required List<Color> gradient,
    required IconData icon,
    required String label,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: gradient),
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: gradient[0].withOpacity(0.4),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: Colors.white, size: 20),
              const SizedBox(width: 8),
              Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Диалог выбора типа фото
  void _showPhotoTypeDialog(CigaretteProduct product) {
    final recountGradient = _getProgressGradient(product.recountProgress);

    // Per-shop статистика для выкладки
    final shopStats = product.getShopStats(_selectedShopAddress ?? '');
    final shopProgress = shopStats?.progress ?? 0;
    final displayGradient = _getProgressGradient(shopProgress);
    final hasShop = _selectedShopAddress != null && _selectedShopAddress!.isNotEmpty;

    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: const Color(0xFF1A1A2E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: const Color(0xFF1A1A2E),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: Colors.white.withOpacity(0.1),
              width: 1,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                product.productName,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 8),
              Text(
                'Выберите тип фото для обучения:',
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.white.withOpacity(0.6),
                ),
              ),
              const SizedBox(height: 20),

              // Кнопка: Крупный план (общий для всех магазинов)
              _buildPhotoTypeOption(
                onTap: () {
                  Navigator.pop(context);
                  _openPhotoTemplates(product);
                },
                icon: Icons.crop_free,
                title: 'Крупный план',
                subtitle: '10 шаблонов: ${product.completedTemplates.length}/10',
                progress: product.completedTemplates.length / 10,
                gradient: recountGradient,
                isComplete: product.isRecountComplete,
              ),
              const SizedBox(height: 12),

              // Кнопка: Выкладка (per-shop)
              _buildPhotoTypeOption(
                onTap: () {
                  // Проверяем выбран ли магазин
                  if (!hasShop) {
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Row(
                          children: [
                            const Icon(Icons.warning_amber, color: Colors.white, size: 20),
                            const SizedBox(width: 12),
                            const Expanded(
                              child: Text('Выберите магазин для загрузки фото выкладки'),
                            ),
                          ],
                        ),
                        backgroundColor: _orangeGradient[0],
                        duration: const Duration(seconds: 3),
                      ),
                    );
                    return;
                  }
                  Navigator.pop(context);
                  _takePhoto(product, TrainingSampleType.display);
                },
                icon: Icons.grid_view,
                title: 'Выкладка',
                subtitle: hasShop
                    ? 'Фото для: ${_selectedShopAddress!.length > 25 ? '${_selectedShopAddress!.substring(0, 25)}...' : _selectedShopAddress}'
                    : '⚠️ Выберите магазин',
                progress: hasShop ? shopProgress / 100 : 0,
                progressLabel: hasShop
                    ? '${shopStats?.displayPhotosCount ?? 0}/${shopStats?.requiredDisplayPhotos ?? 3}'
                    : '—',
                gradient: hasShop ? displayGradient : _orangeGradient,
                isComplete: shopStats?.isDisplayComplete ?? false,
              ),
              const SizedBox(height: 16),

              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(
                  'Отмена',
                  style: TextStyle(color: Colors.white.withOpacity(0.6)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPhotoTypeOption({
    required VoidCallback onTap,
    required IconData icon,
    required String title,
    required String subtitle,
    required double progress,
    String? progressLabel,
    required List<Color> gradient,
    required bool isComplete,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.05),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isComplete ? _greenGradient[0].withOpacity(0.5) : gradient[0].withOpacity(0.3),
              width: 2,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: isComplete ? _greenGradient : gradient),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: Colors.white, size: 24),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.white.withOpacity(0.5),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: Container(
                            height: 4,
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(2),
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(2),
                              child: FractionallySizedBox(
                                alignment: Alignment.centerLeft,
                                widthFactor: progress.clamp(0.0, 1.0),
                                child: Container(
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(colors: isComplete ? _greenGradient : gradient),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        if (progressLabel != null) ...[
                          const SizedBox(width: 8),
                          Text(
                            progressLabel,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: isComplete ? _greenGradient[0] : gradient[0],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              if (isComplete)
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(colors: _greenGradient),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.check, color: Colors.white, size: 18),
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// Открыть страницу шаблонов для "Крупного плана"
  Future<void> _openPhotoTemplates(CigaretteProduct product) async {
    // Получаем данные сотрудника
    final employeeName = await EmployeesPage.getCurrentEmployeeName();
    final prefs = await SharedPreferences.getInstance();
    final shopAddress = prefs.getString('selectedShopAddress');

    if (!mounted) return;

    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (context) => PhotoTemplatesPage(
          product: product,
          completedTemplates: product.completedTemplates,
          shopAddress: shopAddress,
          employeeName: employeeName,
        ),
      ),
    );

    // Если были изменения — обновляем данные
    if (result == true && mounted) {
      _loadData();
    }
  }

  /// Сделать фото и открыть экран разметки
  Future<void> _takePhoto(CigaretteProduct product, TrainingSampleType type) async {
    final picker = ImagePicker();
    final image = await picker.pickImage(
      source: ImageSource.camera,
      imageQuality: 85,
    );

    if (image == null) return;
    if (!mounted) return;

    try {
      final imageBytes = await File(image.path).readAsBytes();

      // Получаем данные сотрудника
      final employeeName = await EmployeesPage.getCurrentEmployeeName();
      final prefs = await SharedPreferences.getInstance();
      final shopAddress = prefs.getString('selectedShopAddress');

      // Открываем экран разметки
      final result = await Navigator.push<bool>(
        context,
        MaterialPageRoute(
          builder: (context) => CigaretteAnnotationPage(
            imageBytes: imageBytes,
            product: product,
            type: type,
            shopAddress: shopAddress,
            employeeName: employeeName,
          ),
        ),
      );

      // Если успешно сохранено — обновляем данные
      if (result == true && mounted) {
        _loadData();
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Ошибка: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  /// Показать детали товара
  void _showProductDetails(CigaretteProduct product) {
    final progressGradient = _getProgressGradient(product.trainingProgress);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize: 0.3,
        maxChildSize: 0.9,
        expand: false,
        builder: (context, scrollController) => Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Color(0xFF1A1A2E),
                Color(0xFF16213E),
              ],
            ),
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: ListView(
            controller: scrollController,
            padding: const EdgeInsets.all(20),
            children: [
              // Индикатор
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.3),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 20),

              // Заголовок
              Row(
                children: [
                  Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(colors: progressGradient),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(
                      product.isTrainingComplete ? Icons.check_circle : Icons.hourglass_empty,
                      color: Colors.white,
                      size: 28,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          product.productName,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        Text(
                          product.productGroup,
                          style: TextStyle(color: Colors.white.withOpacity(0.6)),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // Прогресс
              _buildDetailProgressCard(product),
              const SizedBox(height: 16),

              // Информация
              _buildDetailInfoCard(product),
              const SizedBox(height: 20),

              // Кнопка добавления фото
              _buildGradientButton(
                onTap: () {
                  Navigator.pop(context);
                  _showPhotoTypeDialog(product);
                },
                gradient: _greenGradient,
                icon: Icons.add_a_photo,
                label: 'Добавить фото',
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDetailProgressCard(CigaretteProduct product) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Colors.white.withOpacity(0.1),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Прогресс обучения',
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: Colors.white,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 16),

          // Крупный план
          _buildDetailProgressRow(
            icon: Icons.crop_free,
            label: 'Крупный план',
            current: product.recountPhotosCount,
            total: product.requiredRecountPhotos,
            progress: product.recountProgress,
            isComplete: product.isRecountComplete,
          ),
          const SizedBox(height: 16),

          // Выкладка
          _buildDetailProgressRow(
            icon: Icons.grid_view,
            label: 'Выкладка',
            current: product.displayPhotosCount,
            total: product.requiredDisplayPhotos,
            progress: product.displayProgress,
            isComplete: product.isDisplayComplete,
          ),
          const SizedBox(height: 16),

          // Общий статус
          Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: _getProgressGradient(product.trainingProgress),
                ),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                product.isTrainingComplete
                    ? '✅ Обучение завершено!'
                    : 'Всего: ${product.trainingPhotosCount}/${product.requiredPhotosCount} фото',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailProgressRow({
    required IconData icon,
    required String label,
    required int current,
    required int total,
    required double progress,
    required bool isComplete,
  }) {
    final gradient = isComplete ? _greenGradient : _getProgressGradient(progress);

    return Column(
      children: [
        Row(
          children: [
            Icon(icon, size: 20, color: gradient[0]),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(color: Colors.white.withOpacity(0.8)),
            ),
            const Spacer(),
            Text(
              '$current/$total',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: gradient[0],
              ),
            ),
            if (isComplete) ...[
              const SizedBox(width: 4),
              Icon(Icons.check_circle, color: _greenGradient[0], size: 18),
            ],
          ],
        ),
        const SizedBox(height: 8),
        Container(
          height: 8,
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.1),
            borderRadius: BorderRadius.circular(4),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: (progress / 100).clamp(0.0, 1.0),
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: gradient),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDetailInfoCard(CigaretteProduct product) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Colors.white.withOpacity(0.1),
          width: 1,
        ),
      ),
      child: Column(
        children: [
          _buildInfoRow('Штрих-код', product.barcode),
          _buildInfoRow('Группа', product.productGroup),
          _buildInfoRow('Грейд', '${product.grade}'),
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(color: Colors.white.withOpacity(0.6)),
          ),
          Text(
            value,
            style: const TextStyle(
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}
