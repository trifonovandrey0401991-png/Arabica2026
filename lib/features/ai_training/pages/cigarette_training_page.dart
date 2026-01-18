import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/cigarette_training_model.dart';
import '../services/cigarette_vision_service.dart';
import '../../employees/pages/employees_page.dart';

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
    _tabController = TabController(length: 3, vsync: this);
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
          tabs: const [
            Tab(text: 'Добавить фото', icon: Icon(Icons.add_a_photo)),
            Tab(text: 'Товары', icon: Icon(Icons.inventory_2)),
            Tab(text: 'Статистика', icon: Icon(Icons.bar_chart)),
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
                    '• Фотографируйте товар с разных ракурсов\n'
                    '• Делайте фото при разном освещении\n'
                    '• Фотографируйте разное количество пачек\n'
                    '• Минимум 50 фото на каждый товар',
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
                    const SizedBox(height: 4),
                    // Прогресс
                    Row(
                      children: [
                        Expanded(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: LinearProgressIndicator(
                              value: product.trainingProgress / 100,
                              backgroundColor: Colors.grey[300],
                              valueColor: AlwaysStoppedAnimation<Color>(progressColor),
                              minHeight: 6,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '${product.trainingPhotosCount}/${product.requiredPhotosCount}',
                          style: TextStyle(
                            fontSize: 12,
                            color: progressColor,
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
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          product.productName,
          style: const TextStyle(fontSize: 16),
        ),
        content: const Text('Выберите тип фото для обучения:'),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _takePhoto(product, TrainingSampleType.recount);
            },
            child: const Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.calculate, size: 32),
                SizedBox(height: 4),
                Text('Для пересчёта'),
                Text(
                  'Фото пачек на полке',
                  style: TextStyle(fontSize: 10, color: Colors.grey),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _takePhoto(product, TrainingSampleType.display);
            },
            child: const Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.grid_view, size: 32),
                SizedBox(height: 4),
                Text('Для выкладки'),
                Text(
                  'Фото всей витрины',
                  style: TextStyle(fontSize: 10, color: Colors.grey),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Сделать фото и загрузить
  Future<void> _takePhoto(CigaretteProduct product, TrainingSampleType type) async {
    final picker = ImagePicker();
    final image = await picker.pickImage(
      source: ImageSource.camera,
      imageQuality: 85,
    );

    if (image == null) return;

    // Показываем индикатор загрузки
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const AlertDialog(
        content: Row(
          children: [
            CircularProgressIndicator(),
            SizedBox(width: 16),
            Text('Загрузка фото...'),
          ],
        ),
      ),
    );

    try {
      final imageBytes = await File(image.path).readAsBytes();

      // Получаем данные сотрудника
      final employeeName = await EmployeesPage.getCurrentEmployeeName();
      final prefs = await SharedPreferences.getInstance();
      final shopAddress = prefs.getString('selectedShopAddress');

      final success = await CigaretteVisionService.uploadTrainingSample(
        imageBytes: imageBytes,
        productId: product.id,
        barcode: product.barcode,
        productName: product.productName,
        type: type,
        shopAddress: shopAddress,
        employeeName: employeeName,
      );

      if (!mounted) return;
      Navigator.pop(context); // Закрываем диалог загрузки

      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Фото добавлено: ${product.productName}'),
            backgroundColor: Colors.green,
          ),
        );
        // Обновляем данные
        _loadData();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Ошибка загрузки фото'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context);
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
                      const SizedBox(height: 8),
                      LinearProgressIndicator(
                        value: product.trainingProgress / 100,
                        backgroundColor: Colors.grey[300],
                        valueColor: AlwaysStoppedAnimation<Color>(
                          _getProgressColor(product.trainingProgress),
                        ),
                        minHeight: 10,
                      ),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            '${product.trainingPhotosCount} фото',
                            style: const TextStyle(fontSize: 16),
                          ),
                          Text(
                            product.isTrainingComplete
                                ? 'Готово!'
                                : 'Нужно ещё ${product.requiredPhotosCount - product.trainingPhotosCount}',
                            style: TextStyle(
                              fontSize: 16,
                              color: _getProgressColor(product.trainingProgress),
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
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
