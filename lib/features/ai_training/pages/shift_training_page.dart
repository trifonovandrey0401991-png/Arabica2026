import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../services/shift_ai_verification_service.dart';
import '../models/shift_ai_verification_model.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

/// Страница управления товарами для ИИ проверки при пересменке
class ShiftTrainingPage extends StatefulWidget {
  const ShiftTrainingPage({super.key});

  @override
  State<ShiftTrainingPage> createState() => _ShiftTrainingPageState();
}

class _ShiftTrainingPageState extends State<ShiftTrainingPage> {
  bool _isLoading = true;
  List<ShiftTrainingProduct> _products = [];
  List<String> _groups = [];
  String? _selectedGroup;
  Map<String, dynamic> _stats = {};
  Map<String, dynamic> _modelStatus = {};
  final _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  /// Получить отфильтрованный список товаров по поисковому запросу
  List<ShiftTrainingProduct> get _filteredProducts {
    if (_searchQuery.isEmpty) return _products;

    final query = _searchQuery.toLowerCase().trim();
    final queryWords = query.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    if (queryWords.isEmpty) return _products;

    final scored = <_ScoredProduct>[];

    for (final product in _products) {
      final name = product.productName.toLowerCase();
      final barcode = product.barcode.toLowerCase();

      // Точное совпадение по штрихкоду
      if (barcode.contains(query)) {
        scored.add(_ScoredProduct(product, 1000));
        continue;
      }

      // Проверяем каждое слово запроса
      int totalScore = 0;
      bool allWordsMatch = true;

      for (final qWord in queryWords) {
        final wordScore = _bestWordScore(qWord, name);
        if (wordScore == 0) {
          allWordsMatch = false;
          break;
        }
        totalScore += wordScore;
      }

      if (allWordsMatch && totalScore > 0) {
        scored.add(_ScoredProduct(product, totalScore));
      }
    }

    // Сортируем по релевантности (высший балл = лучше)
    scored.sort((a, b) => b.score.compareTo(a.score));
    return scored.map((s) => s.product).toList();
  }

  /// Лучший балл совпадения слова запроса с любым словом в названии товара
  int _bestWordScore(String queryWord, String productName) {
    // Ищем как подстроку целого названия (для поиска со 2-го слова)
    if (productName.contains(queryWord)) {
      // Бонус за совпадение с началом слова
      final words = productName.split(RegExp(r'[\s\(\)"]+'));
      for (final w in words) {
        if (w.startsWith(queryWord)) return 100; // Начало слова
      }
      return 80; // Подстрока
    }

    // Нечёткий поиск (допускаем опечатки)
    if (queryWord.length < 3) return 0; // Слишком короткое для fuzzy

    final words = productName.split(RegExp(r'[\s\(\)"]+'));
    int best = 0;

    for (final w in words) {
      if (w.isEmpty) continue;

      // Проверяем нечёткое начало слова
      final prefixLen = queryWord.length.clamp(0, w.length);
      final dist = _levenshtein(
        queryWord,
        w.substring(0, prefixLen.clamp(0, w.length)),
      );

      // Допускаем 1 ошибку на 3 символа
      final maxErrors = (queryWord.length / 3).ceil();
      if (dist <= maxErrors) {
        final score = 60 - dist * 10;
        if (score > best) best = score;
      }

      // Также проверяем полное слово
      if (w.length >= queryWord.length - 1) {
        final fullDist = _levenshtein(queryWord, w);
        if (fullDist <= maxErrors) {
          final score = 70 - fullDist * 10;
          if (score > best) best = score;
        }
      }
    }

    return best;
  }

  /// Расстояние Левенштейна (количество правок для превращения a в b)
  int _levenshtein(String a, String b) {
    if (a == b) return 0;
    if (a.isEmpty) return b.length;
    if (b.isEmpty) return a.length;

    // Оптимизация: используем одну строку матрицы
    var prev = List.generate(b.length + 1, (i) => i);
    var curr = List.filled(b.length + 1, 0);

    for (int i = 1; i <= a.length; i++) {
      curr[0] = i;
      for (int j = 1; j <= b.length; j++) {
        final cost = a[i - 1] == b[j - 1] ? 0 : 1;
        curr[j] = [
          prev[j] + 1,      // удаление
          curr[j - 1] + 1,   // вставка
          prev[j - 1] + cost, // замена
        ].reduce((a, b) => a < b ? a : b);
      }
      final tmp = prev;
      prev = curr;
      curr = tmp;
    }

    return prev[b.length];
  }

  Future<void> _loadData() async {
    if (mounted) setState(() => _isLoading = true);

    try {
      final results = await Future.wait([
        ShiftAiVerificationService.getAllProducts(group: _selectedGroup),
        ShiftAiVerificationService.getProductGroups(),
        ShiftAiVerificationService.getTrainingStats(),
        ShiftAiVerificationService.getModelStatus(),
      ]);

      if (mounted) {
        setState(() {
          _products = results[0] as List<ShiftTrainingProduct>;
          _groups = results[1] as List<String>;
          _stats = results[2] as Map<String, dynamic>;
          _modelStatus = results[3] as Map<String, dynamic>;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка загрузки: $e')),
        );
      }
    }
  }

  Future<void> _toggleProductAi(ShiftTrainingProduct product) async {
    final newValue = !product.isAiActive;

    // Оптимистичное обновление
    if (mounted) setState(() {
      final index = _products.indexWhere((p) => p.barcode == product.barcode);
      if (index != -1) {
        _products[index] = product.copyWith(isAiActive: newValue);
      }
    });

    final success = await ShiftAiVerificationService.updateProductAiSettings(
      barcode: product.barcode,
      isAiActive: newValue,
    );

    if (!success) {
      // Откат при ошибке
      if (mounted) {
        setState(() {
          final index = _products.indexWhere((p) => p.barcode == product.barcode);
          if (index != -1) {
            _products[index] = product.copyWith(isAiActive: !newValue);
          }
        });
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка сохранения')),
        );
      }
    } else {
      // Обновляем статистику
      _loadStats();
    }
  }

  Future<void> _loadStats() async {
    final stats = await ShiftAiVerificationService.getTrainingStats();
    if (mounted) {
      setState(() => _stats = stats);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              AppColors.darkNavy,
              AppColors.navy,
              AppColors.deepBlue,
            ],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              _buildAppBar(),
              _buildStatsHeader(),
              _buildSearchBar(),
              _buildGroupFilter(),
              Expanded(
                child: _isLoading
                    ? Center(
                        child: CircularProgressIndicator(color: Colors.white),
                      )
                    : _buildProductsList(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAppBar() {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 8.h),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.pop(context),
            icon: Container(
              padding: EdgeInsets.all(8.w),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12.r),
              ),
              child: Icon(
                Icons.arrow_back_ios_new,
                color: Colors.white,
                size: 20,
              ),
            ),
          ),
          Expanded(
            child: Text(
              'Пересменка',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                fontSize: 20.sp,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          IconButton(
            onPressed: _loadData,
            icon: Container(
              padding: EdgeInsets.all(8.w),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12.r),
              ),
              child: Icon(
                Icons.refresh,
                color: Colors.white,
                size: 20,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatsHeader() {
    final activeCount = _stats['activeProducts'] ?? 0;
    final totalCount = _stats['totalProducts'] ?? 0;
    final trainingPhotos = _stats['totalTrainingPhotos'] ?? 0;
    final isTrained = _modelStatus['isTrained'] ?? false;

    return Container(
      margin: EdgeInsets.all(16.w),
      padding: EdgeInsets.all(16.w),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppColors.warning.withOpacity(0.2),
            AppColors.warningLight.withOpacity(0.1),
          ],
        ),
        borderRadius: BorderRadius.circular(16.r),
        border: Border.all(
          color: AppColors.warning.withOpacity(0.3),
          width: 1,
        ),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildStatItem(
                icon: Icons.check_circle,
                value: '$activeCount',
                label: 'Активных',
                color: AppColors.emeraldGreen,
              ),
              _buildStatItem(
                icon: Icons.inventory_2,
                value: '$totalCount',
                label: 'Всего',
                color: AppColors.indigo,
              ),
              _buildStatItem(
                icon: Icons.photo_library,
                value: '$trainingPhotos',
                label: 'Фото',
                color: AppColors.warning,
              ),
            ],
          ),
          SizedBox(height: 12),
          Container(
            padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 6.h),
            decoration: BoxDecoration(
              color: isTrained
                  ? AppColors.emeraldGreen.withOpacity(0.2)
                  : AppColors.error.withOpacity(0.2),
              borderRadius: BorderRadius.circular(8.r),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  isTrained ? Icons.check_circle : Icons.pending,
                  color: isTrained
                      ? AppColors.emeraldGreen
                      : AppColors.error,
                  size: 16,
                ),
                SizedBox(width: 6),
                Text(
                  isTrained ? 'Модель обучена' : 'Модель не обучена',
                  style: TextStyle(
                    color: isTrained
                        ? AppColors.emeraldGreen
                        : AppColors.error,
                    fontSize: 12.sp,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatItem({
    required IconData icon,
    required String value,
    required String label,
    required Color color,
  }) {
    return Column(
      children: [
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: color.withOpacity(0.2),
            borderRadius: BorderRadius.circular(12.r),
          ),
          child: Icon(icon, color: color, size: 24),
        ),
        SizedBox(height: 8),
        Text(
          value,
          style: TextStyle(
            color: Colors.white,
            fontSize: 20.sp,
            fontWeight: FontWeight.w700,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            color: Colors.white.withOpacity(0.6),
            fontSize: 12.sp,
          ),
        ),
      ],
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 16.w),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.08),
          borderRadius: BorderRadius.circular(12.r),
          border: Border.all(
            color: Colors.white.withOpacity(0.15),
          ),
        ),
        child: TextField(
          controller: _searchController,
          style: TextStyle(color: Colors.white, fontSize: 15.sp),
          decoration: InputDecoration(
            hintText: 'Поиск по названию или штрихкоду...',
            hintStyle: TextStyle(
              color: Colors.white.withOpacity(0.35),
              fontSize: 14.sp,
            ),
            prefixIcon: Icon(
              Icons.search,
              color: Colors.white.withOpacity(0.5),
              size: 22,
            ),
            suffixIcon: _searchQuery.isNotEmpty
                ? IconButton(
                    icon: Icon(
                      Icons.close,
                      color: Colors.white.withOpacity(0.5),
                      size: 20,
                    ),
                    onPressed: () {
                      _searchController.clear();
                      if (mounted) setState(() => _searchQuery = '');
                    },
                  )
                : null,
            border: InputBorder.none,
            contentPadding: EdgeInsets.symmetric(
              horizontal: 16.w,
              vertical: 12.h,
            ),
          ),
          onChanged: (value) {
            if (mounted) setState(() => _searchQuery = value);
          },
        ),
      ),
    );
  }

  Widget _buildGroupFilter() {
    return Container(
      height: 50,
      margin: EdgeInsets.symmetric(horizontal: 16.w),
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          _buildFilterChip(
            label: 'Все',
            isSelected: _selectedGroup == null,
            onTap: () {
              if (mounted) setState(() => _selectedGroup = null);
              _loadData();
            },
          ),
          ..._groups.map((group) => _buildFilterChip(
                label: group,
                isSelected: _selectedGroup == group,
                onTap: () {
                  if (mounted) setState(() => _selectedGroup = group);
                  _loadData();
                },
              )),
        ],
      ),
    );
  }

  Widget _buildFilterChip({
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: EdgeInsets.only(right: 8.w),
        padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 8.h),
        decoration: BoxDecoration(
          color: isSelected
              ? AppColors.warning
              : Colors.white.withOpacity(0.1),
          borderRadius: BorderRadius.circular(20.r),
          border: Border.all(
            color: isSelected
                ? AppColors.warning
                : Colors.white.withOpacity(0.2),
            width: 1,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.black : Colors.white,
            fontSize: 14.sp,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
      ),
    );
  }

  Widget _buildProductsList() {
    final products = _filteredProducts;

    if (_products.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.inventory_2_outlined,
              size: 64,
              color: Colors.white.withOpacity(0.3),
            ),
            SizedBox(height: 16),
            Text(
              'Нет товаров',
              style: TextStyle(
                color: Colors.white.withOpacity(0.6),
                fontSize: 16.sp,
              ),
            ),
            SizedBox(height: 8),
            Text(
              'Добавьте товары в мастер-каталог',
              style: TextStyle(
                color: Colors.white.withOpacity(0.4),
                fontSize: 14.sp,
              ),
            ),
          ],
        ),
      );
    }

    if (products.isEmpty && _searchQuery.isNotEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.search_off,
              size: 64,
              color: Colors.white.withOpacity(0.3),
            ),
            SizedBox(height: 16),
            Text(
              'Ничего не найдено',
              style: TextStyle(
                color: Colors.white.withOpacity(0.6),
                fontSize: 16.sp,
              ),
            ),
            SizedBox(height: 8),
            Text(
              'Попробуйте изменить запрос',
              style: TextStyle(
                color: Colors.white.withOpacity(0.4),
                fontSize: 14.sp,
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        if (_searchQuery.isNotEmpty)
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 4.h),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Найдено: ${products.length}',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.5),
                  fontSize: 12.sp,
                ),
              ),
            ),
          ),
        Expanded(
          child: ListView.builder(
            padding: EdgeInsets.all(16.w),
            itemCount: products.length,
            itemBuilder: (context, index) {
              final product = products[index];
              return _buildProductCard(product);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildProductCard(ShiftTrainingProduct product) {
    return Container(
      margin: EdgeInsets.only(bottom: 12.h),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(16.r),
        border: Border.all(
          color: product.isAiActive
              ? AppColors.emeraldGreen.withOpacity(0.5)
              : Colors.white.withOpacity(0.1),
          width: 1,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _toggleProductAi(product),
          borderRadius: BorderRadius.circular(16.r),
          child: Padding(
            padding: EdgeInsets.all(16.w),
            child: Row(
              children: [
                // Чекбокс
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: product.isAiActive
                        ? AppColors.emeraldGreen
                        : Colors.white.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8.r),
                    border: Border.all(
                      color: product.isAiActive
                          ? AppColors.emeraldGreen
                          : Colors.white.withOpacity(0.3),
                      width: 2,
                    ),
                  ),
                  child: product.isAiActive
                      ? Icon(
                          Icons.check,
                          color: Colors.white,
                          size: 18,
                        )
                      : null,
                ),

                SizedBox(width: 14),

                // Информация о товаре
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        product.productName,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 15.sp,
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      SizedBox(height: 4),
                      Row(
                        children: [
                          Text(
                            product.barcode,
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.5),
                              fontSize: 12.sp,
                            ),
                          ),
                          if (product.productGroup != null) ...[
                            Text(
                              ' • ',
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.3),
                                fontSize: 12.sp,
                              ),
                            ),
                            Text(
                              product.productGroup!,
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.5),
                                fontSize: 12.sp,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),

                // Счётчик фото
                if (product.trainingPhotosCount > 0)
                  Container(
                    padding: EdgeInsets.symmetric(
                      horizontal: 8.w,
                      vertical: 4.h,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.warning.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(8.r),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.photo,
                          color: AppColors.warning,
                          size: 14,
                        ),
                        SizedBox(width: 4),
                        Text(
                          '${product.trainingPhotosCount}',
                          style: TextStyle(
                            color: AppColors.warning,
                            fontSize: 12.sp,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
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

/// Вспомогательный класс для сортировки по релевантности
class _ScoredProduct {
  final ShiftTrainingProduct product;
  final int score;
  _ScoredProduct(this.product, this.score);
}
