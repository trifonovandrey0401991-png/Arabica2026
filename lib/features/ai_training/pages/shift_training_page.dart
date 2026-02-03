import 'package:flutter/material.dart';
import '../services/shift_ai_verification_service.dart';
import '../models/shift_ai_verification_model.dart';

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

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);

    try {
      final results = await Future.wait([
        ShiftAiVerificationService.getAllProducts(group: _selectedGroup),
        ShiftAiVerificationService.getProductGroups(),
        ShiftAiVerificationService.getTrainingStats(),
        ShiftAiVerificationService.getModelStatus(),
      ]);

      setState(() {
        _products = results[0] as List<ShiftTrainingProduct>;
        _groups = results[1] as List<String>;
        _stats = results[2] as Map<String, dynamic>;
        _modelStatus = results[3] as Map<String, dynamic>;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
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
    setState(() {
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
      setState(() {
        final index = _products.indexWhere((p) => p.barcode == product.barcode);
        if (index != -1) {
          _products[index] = product.copyWith(isAiActive: !newValue);
        }
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Ошибка сохранения')),
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
              _buildAppBar(),
              _buildStatsHeader(),
              _buildGroupFilter(),
              Expanded(
                child: _isLoading
                    ? const Center(
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
              'Пересменка',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          IconButton(
            onPressed: _loadData,
            icon: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(
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
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            const Color(0xFFF59E0B).withOpacity(0.2),
            const Color(0xFFFBBF24).withOpacity(0.1),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: const Color(0xFFF59E0B).withOpacity(0.3),
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
                color: const Color(0xFF10B981),
              ),
              _buildStatItem(
                icon: Icons.inventory_2,
                value: '$totalCount',
                label: 'Всего',
                color: const Color(0xFF6366F1),
              ),
              _buildStatItem(
                icon: Icons.photo_library,
                value: '$trainingPhotos',
                label: 'Фото',
                color: const Color(0xFFF59E0B),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: isTrained
                  ? const Color(0xFF10B981).withOpacity(0.2)
                  : const Color(0xFFEF4444).withOpacity(0.2),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  isTrained ? Icons.check_circle : Icons.pending,
                  color: isTrained
                      ? const Color(0xFF10B981)
                      : const Color(0xFFEF4444),
                  size: 16,
                ),
                const SizedBox(width: 6),
                Text(
                  isTrained ? 'Модель обучена' : 'Модель не обучена',
                  style: TextStyle(
                    color: isTrained
                        ? const Color(0xFF10B981)
                        : const Color(0xFFEF4444),
                    fontSize: 12,
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
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: color, size: 24),
        ),
        const SizedBox(height: 8),
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.w700,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            color: Colors.white.withOpacity(0.6),
            fontSize: 12,
          ),
        ),
      ],
    );
  }

  Widget _buildGroupFilter() {
    return Container(
      height: 50,
      margin: const EdgeInsets.symmetric(horizontal: 16),
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          _buildFilterChip(
            label: 'Все',
            isSelected: _selectedGroup == null,
            onTap: () {
              setState(() => _selectedGroup = null);
              _loadData();
            },
          ),
          ..._groups.map((group) => _buildFilterChip(
                label: group,
                isSelected: _selectedGroup == group,
                onTap: () {
                  setState(() => _selectedGroup = group);
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
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected
              ? const Color(0xFFF59E0B)
              : Colors.white.withOpacity(0.1),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected
                ? const Color(0xFFF59E0B)
                : Colors.white.withOpacity(0.2),
            width: 1,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.black : Colors.white,
            fontSize: 14,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
      ),
    );
  }

  Widget _buildProductsList() {
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
            const SizedBox(height: 16),
            Text(
              'Нет товаров',
              style: TextStyle(
                color: Colors.white.withOpacity(0.6),
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Добавьте товары в мастер-каталог',
              style: TextStyle(
                color: Colors.white.withOpacity(0.4),
                fontSize: 14,
              ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _products.length,
      itemBuilder: (context, index) {
        final product = _products[index];
        return _buildProductCard(product);
      },
    );
  }

  Widget _buildProductCard(ShiftTrainingProduct product) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: product.isAiActive
              ? const Color(0xFF10B981).withOpacity(0.5)
              : Colors.white.withOpacity(0.1),
          width: 1,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _toggleProductAi(product),
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                // Чекбокс
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: product.isAiActive
                        ? const Color(0xFF10B981)
                        : Colors.white.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: product.isAiActive
                          ? const Color(0xFF10B981)
                          : Colors.white.withOpacity(0.3),
                      width: 2,
                    ),
                  ),
                  child: product.isAiActive
                      ? const Icon(
                          Icons.check,
                          color: Colors.white,
                          size: 18,
                        )
                      : null,
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
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Text(
                            product.barcode,
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.5),
                              fontSize: 12,
                            ),
                          ),
                          if (product.productGroup != null) ...[
                            Text(
                              ' • ',
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.3),
                                fontSize: 12,
                              ),
                            ),
                            Text(
                              product.productGroup!,
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.5),
                                fontSize: 12,
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
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF59E0B).withOpacity(0.2),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.photo,
                          color: Color(0xFFF59E0B),
                          size: 14,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '${product.trainingPhotosCount}',
                          style: const TextStyle(
                            color: Color(0xFFF59E0B),
                            fontSize: 12,
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
