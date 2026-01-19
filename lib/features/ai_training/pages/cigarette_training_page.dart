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

/// Страница обучения ИИ распознаванию сигарет
class CigaretteTrainingPage extends StatefulWidget {
  const CigaretteTrainingPage({super.key});

  @override
  State<CigaretteTrainingPage> createState() => _CigaretteTrainingPageState();
}

class _CigaretteTrainingPageState extends State<CigaretteTrainingPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  List<CigaretteProduct> _products = [];
  List<String> _productGroups = [];
  TrainingStats _stats = TrainingStats.empty();

  String? _selectedGroup;
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
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
      appBar: AppBar(
        title: const Text('Подсчёт сигарет'),
        backgroundColor: const Color(0xFF004D40),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          isScrollable: true,
          tabs: const [
            Tab(text: 'Добавить фото', icon: Icon(Icons.add_a_photo)),
            Tab(text: 'Товары', icon: Icon(Icons.inventory_2)),
            Tab(text: 'Статистика', icon: Icon(Icons.bar_chart)),
            Tab(text: 'Настройки', icon: Icon(Icons.settings)),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _buildErrorView()
              : TabBarView(
                  controller: _tabController,
                  children: [
                    _buildAddPhotoTab(),
                    _buildProductsTab(),
                    _buildStatsTab(),
                    _buildSettingsTab(),
                  ],
                ),
    );
  }

  Widget _buildErrorView() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.error_outline, size: 64, color: Colors.red),
          const SizedBox(height: 16),
          Text(_error ?? 'Неизвестная ошибка'),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: _loadData,
            child: const Text('Повторить'),
          ),
        ],
      ),
    );
  }

  /// Вкладка добавления фото
  Widget _buildAddPhotoTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Заголовок и инструкция
        Card(
          color: Colors.blue[50],
          child: const Padding(
            padding: EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.info_outline, color: Colors.blue),
                    SizedBox(width: 8),
                    Text(
                      'Как добавлять фото',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.blue,
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 8),
                Text(
                  '1. Выберите товар из списка ниже\n'
                  '2. Сфотографируйте товар на полке\n'
                  '3. ИИ определит достаточно ли фото для обучения\n\n'
                  'Чем больше разных фото - тем точнее будет распознавание!',
                  style: TextStyle(fontSize: 14),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),

        // Фильтр по группе
        if (_productGroups.isNotEmpty) ...[
          DropdownButtonFormField<String>(
            value: _selectedGroup,
            decoration: InputDecoration(
              labelText: 'Группа товаров',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              prefixIcon: const Icon(Icons.filter_list),
            ),
            items: [
              const DropdownMenuItem(
                value: null,
                child: Text('Все группы'),
              ),
              ..._productGroups.map((group) => DropdownMenuItem(
                value: group,
                child: Text(group),
              )),
            ],
            onChanged: (value) {
              setState(() {
                _selectedGroup = value;
              });
              _loadData();
            },
          ),
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
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Фильтр по группе
          if (_productGroups.isNotEmpty) ...[
            DropdownButtonFormField<String>(
              value: _selectedGroup,
              decoration: InputDecoration(
                labelText: 'Группа товаров',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                prefixIcon: const Icon(Icons.filter_list),
              ),
              items: [
                const DropdownMenuItem(
                  value: null,
                  child: Text('Все группы'),
                ),
                ..._productGroups.map((group) => DropdownMenuItem(
                  value: group,
                  child: Text(group),
                )),
              ],
              onChanged: (value) {
                setState(() {
                  _selectedGroup = value;
                });
                _loadData();
              },
            ),
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
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Общий прогресс
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Общий прогресс обучения',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 16),
                  LinearProgressIndicator(
                    value: _stats.overallProgress / 100,
                    backgroundColor: Colors.grey[300],
                    valueColor: AlwaysStoppedAnimation<Color>(
                      _getProgressColor(_stats.overallProgress),
                    ),
                    minHeight: 12,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${_stats.overallProgress.toStringAsFixed(1)}%',
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Статистика товаров
          Row(
            children: [
              Expanded(
                child: _buildStatCard(
                  'Всего товаров',
                  _stats.totalProducts.toString(),
                  Icons.inventory_2,
                  Colors.blue,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildStatCard(
                  'С фото',
                  _stats.productsWithPhotos.toString(),
                  Icons.photo_library,
                  Colors.orange,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _buildStatCard(
                  'Обучены',
                  _stats.productsFullyTrained.toString(),
                  Icons.check_circle,
                  Colors.green,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildStatCard(
                  'Нужно фото',
                  '${_stats.totalProducts - _stats.productsFullyTrained}',
                  Icons.add_a_photo,
                  Colors.red,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Статистика фото
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Загружено фотографий',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      Column(
                        children: [
                          const Icon(Icons.calculate, size: 32, color: Colors.blue),
                          const SizedBox(height: 4),
                          Text(
                            '${_stats.totalRecountPhotos}',
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const Text('Для пересчёта'),
                        ],
                      ),
                      Column(
                        children: [
                          const Icon(Icons.grid_view, size: 32, color: Colors.green),
                          const SizedBox(height: 4),
                          Text(
                            '${_stats.totalDisplayPhotos}',
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const Text('Для выкладки'),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Инструкция
          Card(
            color: Colors.amber[50],
            child: const Padding(
              padding: EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.lightbulb, color: Colors.amber),
                      SizedBox(width: 8),
                      Text(
                        'Как ускорить обучение',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 8),
                  Text(
                    '• Крупный план: 10 фото с 1-3 пачками вблизи\n'
                    '• Выкладка: 10 фото витрины с 5-15 пачками\n'
                    '• Фотографируйте с разных ракурсов\n'
                    '• Делайте фото при разном освещении',
                    style: TextStyle(fontSize: 14),
                  ),
                ],
              ),
            ),
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

  Widget _buildStatCard(String title, String value, IconData icon, Color color) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Icon(icon, size: 32, color: color),
            const SizedBox(height: 8),
            Text(
              value,
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            Text(
              title,
              style: const TextStyle(fontSize: 12),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProductCard(CigaretteProduct product, {bool forUpload = false}) {
    final progressColor = _getProgressColor(product.trainingProgress);
    final recountColor = _getProgressColor(product.recountProgress);
    final displayColor = _getProgressColor(product.displayProgress);

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: forUpload ? () => _showPhotoTypeDialog(product) : () => _showProductDetails(product),
        borderRadius: BorderRadius.circular(4),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              // Иконка статуса
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: progressColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  product.isTrainingComplete
                      ? Icons.check_circle
                      : Icons.add_a_photo,
                  color: progressColor,
                  size: 28,
                ),
              ),
              const SizedBox(width: 12),

              // Информация о товаре
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      product.productName,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (product.productGroup.isNotEmpty)
                      Text(
                        product.productGroup,
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[600],
                        ),
                      ),
                    const SizedBox(height: 6),
                    // Раздельный прогресс: крупный план
                    Row(
                      children: [
                        Icon(
                          Icons.crop_free,
                          size: 14,
                          color: product.isRecountComplete ? Colors.green : Colors.blue,
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(3),
                            child: LinearProgressIndicator(
                              value: product.recountProgress / 100,
                              backgroundColor: Colors.grey[300],
                              valueColor: AlwaysStoppedAnimation<Color>(recountColor),
                              minHeight: 4,
                            ),
                          ),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '${product.recountPhotosCount}/${product.requiredRecountPhotos}',
                          style: TextStyle(
                            fontSize: 10,
                            color: recountColor,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    // Раздельный прогресс: выкладка
                    Row(
                      children: [
                        Icon(
                          Icons.grid_view,
                          size: 14,
                          color: product.isDisplayComplete ? Colors.green : Colors.orange,
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(3),
                            child: LinearProgressIndicator(
                              value: product.displayProgress / 100,
                              backgroundColor: Colors.grey[300],
                              valueColor: AlwaysStoppedAnimation<Color>(displayColor),
                              minHeight: 4,
                            ),
                          ),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '${product.displayPhotosCount}/${product.requiredDisplayPhotos}',
                          style: TextStyle(
                            fontSize: 10,
                            color: displayColor,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              // Кнопка добавления фото
              if (forUpload)
                IconButton(
                  icon: const Icon(Icons.camera_alt),
                  color: const Color(0xFF004D40),
                  onPressed: () => _showPhotoTypeDialog(product),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Color _getProgressColor(double progress) {
    if (progress >= 100) return Colors.green;
    if (progress >= 50) return Colors.orange;
    if (progress >= 25) return Colors.amber;
    return Colors.red;
  }

  /// Диалог выбора типа фото
  void _showPhotoTypeDialog(CigaretteProduct product) {
    final recountColor = _getProgressColor(product.recountProgress);
    final displayColor = _getProgressColor(product.displayProgress);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          product.productName,
          style: const TextStyle(fontSize: 16),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Выберите тип фото для обучения:'),
            const SizedBox(height: 16),
            // Кнопка: Крупный план (10 шаблонов)
            InkWell(
              onTap: () {
                Navigator.pop(context);
                _openPhotoTemplates(product);
              },
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  border: Border.all(
                    color: product.isRecountComplete ? Colors.green : Colors.blue,
                    width: 2,
                  ),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.crop_free,
                      size: 36,
                      color: product.isRecountComplete ? Colors.green : Colors.blue,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Крупный план',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                          Text(
                            '10 шаблонов: ${product.completedTemplates.length}/10',
                            style: const TextStyle(fontSize: 12, color: Colors.grey),
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Expanded(
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(2),
                                  child: LinearProgressIndicator(
                                    value: product.completedTemplates.length / 10,
                                    backgroundColor: Colors.grey[300],
                                    valueColor: AlwaysStoppedAnimation<Color>(recountColor),
                                    minHeight: 4,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                '${product.completedTemplates.length}/10',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: recountColor,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    if (product.isRecountComplete)
                      const Icon(Icons.check_circle, color: Colors.green),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            // Кнопка: Выкладка
            InkWell(
              onTap: () {
                Navigator.pop(context);
                _takePhoto(product, TrainingSampleType.display);
              },
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  border: Border.all(
                    color: product.isDisplayComplete ? Colors.green : Colors.orange,
                    width: 2,
                  ),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.grid_view,
                      size: 36,
                      color: product.isDisplayComplete ? Colors.green : Colors.orange,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Выкладка',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                          const Text(
                            'Фото витрины с 5-15 пачками',
                            style: TextStyle(fontSize: 12, color: Colors.grey),
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Expanded(
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(2),
                                  child: LinearProgressIndicator(
                                    value: product.displayProgress / 100,
                                    backgroundColor: Colors.grey[300],
                                    valueColor: AlwaysStoppedAnimation<Color>(displayColor),
                                    minHeight: 4,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                '${product.displayPhotosCount}/${product.requiredDisplayPhotos}',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: displayColor,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    if (product.isDisplayComplete)
                      const Icon(Icons.check_circle, color: Colors.green),
                  ],
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Отмена'),
          ),
        ],
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
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize: 0.3,
        maxChildSize: 0.9,
        expand: false,
        builder: (context, scrollController) => Container(
          padding: const EdgeInsets.all(16),
          child: ListView(
            controller: scrollController,
            children: [
              // Заголовок
              Row(
                children: [
                  Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      color: _getProgressColor(product.trainingProgress).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      product.isTrainingComplete ? Icons.check_circle : Icons.hourglass_empty,
                      color: _getProgressColor(product.trainingProgress),
                      size: 32,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          product.productName,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          product.productGroup,
                          style: TextStyle(color: Colors.grey[600]),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Прогресс
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Прогресс обучения',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 12),
                      // Крупный план
                      Row(
                        children: [
                          Icon(
                            Icons.crop_free,
                            size: 20,
                            color: product.isRecountComplete ? Colors.green : Colors.blue,
                          ),
                          const SizedBox(width: 8),
                          const Text('Крупный план:'),
                          const Spacer(),
                          Text(
                            '${product.recountPhotosCount}/${product.requiredRecountPhotos}',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: _getProgressColor(product.recountProgress),
                            ),
                          ),
                          if (product.isRecountComplete)
                            const Padding(
                              padding: EdgeInsets.only(left: 4),
                              child: Icon(Icons.check_circle, color: Colors.green, size: 18),
                            ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: product.recountProgress / 100,
                          backgroundColor: Colors.grey[300],
                          valueColor: AlwaysStoppedAnimation<Color>(
                            _getProgressColor(product.recountProgress),
                          ),
                          minHeight: 8,
                        ),
                      ),
                      const SizedBox(height: 12),
                      // Выкладка
                      Row(
                        children: [
                          Icon(
                            Icons.grid_view,
                            size: 20,
                            color: product.isDisplayComplete ? Colors.green : Colors.orange,
                          ),
                          const SizedBox(width: 8),
                          const Text('Выкладка:'),
                          const Spacer(),
                          Text(
                            '${product.displayPhotosCount}/${product.requiredDisplayPhotos}',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: _getProgressColor(product.displayProgress),
                            ),
                          ),
                          if (product.isDisplayComplete)
                            const Padding(
                              padding: EdgeInsets.only(left: 4),
                              child: Icon(Icons.check_circle, color: Colors.green, size: 18),
                            ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: product.displayProgress / 100,
                          backgroundColor: Colors.grey[300],
                          valueColor: AlwaysStoppedAnimation<Color>(
                            _getProgressColor(product.displayProgress),
                          ),
                          minHeight: 8,
                        ),
                      ),
                      const SizedBox(height: 12),
                      // Общий статус
                      Center(
                        child: Text(
                          product.isTrainingComplete
                              ? '✅ Обучение завершено!'
                              : 'Всего: ${product.trainingPhotosCount}/${product.requiredPhotosCount} фото',
                          style: TextStyle(
                            fontSize: 16,
                            color: _getProgressColor(product.trainingProgress),
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Информация
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildInfoRow('Штрих-код', product.barcode),
                      _buildInfoRow('Группа', product.productGroup),
                      _buildInfoRow('Грейд', '${product.grade}'),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Кнопка добавления фото
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () {
                    Navigator.pop(context);
                    _showPhotoTypeDialog(product);
                  },
                  icon: const Icon(Icons.add_a_photo),
                  label: const Text('Добавить фото'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF004D40),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: Colors.grey[600])),
          Text(value, style: const TextStyle(fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}
