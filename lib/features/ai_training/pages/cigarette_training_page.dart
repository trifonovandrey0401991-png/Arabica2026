import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/cigarette_training_model.dart';
import '../services/cigarette_vision_service.dart';
import '../../employees/pages/employees_page.dart';
import 'cigarette_annotation_page.dart';
import 'photo_templates_page.dart';
import 'training_settings_page.dart';

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

  // Цвета и градиенты
  static const _greenGradient = [Color(0xFF10B981), Color(0xFF34D399)];
  static const _blueGradient = [Color(0xFF3B82F6), Color(0xFF60A5FA)];
  static const _orangeGradient = [Color(0xFFF59E0B), Color(0xFFFBBF24)];
  static const _purpleGradient = [Color(0xFF6366F1), Color(0xFF8B5CF6)];
  static const _redGradient = [Color(0xFFEF4444), Color(0xFFF87171)];

  /// Количество вкладок зависит от роли
  int get _tabCount => _isAdmin ? 4 : 3;

  @override
  void initState() {
    super.initState();
    _initTabController();
    _loadData();
  }

  Future<void> _initTabController() async {
    final prefs = await SharedPreferences.getInstance();
    final role = prefs.getString('user_role') ?? '';

    if (mounted) {
      setState(() {
        _isAdmin = role == 'admin';
        _tabController = TabController(length: _tabCount, vsync: this);
      });
    }
  }

  @override
  void dispose() {
    _tabController?.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final groups = await CigaretteVisionService.getProductGroups();
      final products = await CigaretteVisionService.getProducts(
        productGroup: _selectedGroup,
      );
      final stats = await CigaretteVisionService.getStats();

      if (mounted) {
        setState(() {
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
                              _buildProductsTab(),
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
          const Tab(
            icon: Icon(Icons.inventory_2, size: 20),
            text: 'Товары',
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
    // Сортируем: сначала с меньшим прогрессом
    final sortedProducts = List<CigaretteProduct>.from(_products)
      ..sort((a, b) => a.trainingProgress.compareTo(b.trainingProgress));

    return RefreshIndicator(
      onRefresh: _loadData,
      color: _greenGradient[0],
      backgroundColor: const Color(0xFF1A1A2E),
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Фильтр по группе
          if (_productGroups.isNotEmpty) ...[
            _buildGroupDropdown(),
            const SizedBox(height: 16),
          ],

          // Список товаров
          ...sortedProducts.map((product) => _buildProductCard(product)),
        ],
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
                      // Раздельный прогресс: выкладка
                      _buildProgressRow(
                        icon: Icons.grid_view,
                        progress: product.displayProgress / 100,
                        label: '${product.displayPhotosCount}/${product.requiredDisplayPhotos}',
                        gradient: displayGradient,
                        isComplete: product.isDisplayComplete,
                      ),
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
    final displayGradient = _getProgressGradient(product.displayProgress);

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

              // Кнопка: Крупный план
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

              // Кнопка: Выкладка
              _buildPhotoTypeOption(
                onTap: () {
                  Navigator.pop(context);
                  _takePhoto(product, TrainingSampleType.display);
                },
                icon: Icons.grid_view,
                title: 'Выкладка',
                subtitle: 'Фото витрины с 5-15 пачками',
                progress: product.displayProgress / 100,
                progressLabel: '${product.displayPhotosCount}/${product.requiredDisplayPhotos}',
                gradient: displayGradient,
                isComplete: product.isDisplayComplete,
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
