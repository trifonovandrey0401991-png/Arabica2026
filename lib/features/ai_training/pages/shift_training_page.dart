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

    return ListView.builder(
      padding: EdgeInsets.all(16.w),
      itemCount: _products.length,
      itemBuilder: (context, index) {
        final product = _products[index];
        return _buildProductCard(product);
      },
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
