import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../../core/theme/app_colors.dart';
import '../../ai_training/models/master_product_model.dart';
import '../../ai_training/services/master_catalog_service.dart';
import '../models/oos_settings_model.dart';
import '../services/oos_service.dart';
import '../widgets/oos_product_tile.dart';

/// Settings tab: select products for OOS tracking + configure interval
class OosSettingsTab extends StatefulWidget {
  const OosSettingsTab({super.key});

  @override
  State<OosSettingsTab> createState() => _OosSettingsTabState();
}

class _OosSettingsTabState extends State<OosSettingsTab>
    with AutomaticKeepAliveClientMixin {
  List<MasterProduct> _allProducts = [];
  Set<String> _flaggedIds = {};
  bool _isLoading = true;
  bool _isSaving = false;
  bool _hasChanges = false;
  String _searchQuery = '';
  bool _showFlaggedOnly = false;
  int _selectedInterval = 60;
  Timer? _searchDebounce;
  final _searchController = TextEditingController();

  static const List<int> _intervalOptions = [15, 30, 60, 120, 240];

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);

    final results = await Future.wait([
      MasterCatalogService.getProducts(),
      OosService.getSettings(),
    ]);

    if (!mounted) return;

    final products = results[0] as List<MasterProduct>;
    final settings = results[1] as OosSettings;

    setState(() {
      _allProducts = products..sort((a, b) => a.name.compareTo(b.name));
      _flaggedIds = Set<String>.from(settings.flaggedProductIds);
      _selectedInterval = settings.checkIntervalMinutes;
      _isLoading = false;
    });
  }

  void _onSearchChanged(String value) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 300), () {
      if (mounted) {
        setState(() => _searchQuery = value.toLowerCase());
      }
    });
  }

  void _toggleProduct(String productId) {
    setState(() {
      if (_flaggedIds.contains(productId)) {
        _flaggedIds.remove(productId);
      } else {
        _flaggedIds.add(productId);
      }
      _hasChanges = true;
    });
  }

  Future<void> _saveSettings() async {
    setState(() => _isSaving = true);

    final newSettings = OosSettings(
      flaggedProductIds: _flaggedIds.toList(),
      checkIntervalMinutes: _selectedInterval,
    );

    final success = await OosService.saveSettings(newSettings);

    if (!mounted) return;

    setState(() {
      _isSaving = false;
      if (success) _hasChanges = false;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(success ? 'Настройки сохранены' : 'Ошибка сохранения'),
        backgroundColor: success ? AppColors.emerald : Colors.red,
      ),
    );
  }

  List<MasterProduct> get _filteredProducts {
    var list = _allProducts;

    if (_showFlaggedOnly) {
      list = list.where((p) => _flaggedIds.contains(p.id)).toList();
    }

    if (_searchQuery.isNotEmpty) {
      list = list.where((p) {
        final name = p.name.toLowerCase();
        final barcode = (p.barcode ?? '').toLowerCase();
        final words = _searchQuery.split(RegExp(r'\s+'));
        return words.every((w) => name.contains(w) || barcode.contains(w));
      }).toList();
    }

    return list;
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.gold),
      );
    }

    return Column(
      children: [
        _buildSearchAndFilter(),
        _buildIntervalSelector(),
        Expanded(child: _buildProductList()),
        if (_hasChanges) _buildSaveButton(),
      ],
    );
  }

  Widget _buildSearchAndFilter() {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 8.h),
      color: AppColors.emeraldDark.withOpacity(0.3),
      child: Column(
        children: [
          // Search field
          TextField(
            controller: _searchController,
            onChanged: _onSearchChanged,
            style: TextStyle(color: Colors.white, fontSize: 14.sp),
            decoration: InputDecoration(
              hintText: 'Поиск товара...',
              hintStyle: TextStyle(color: Colors.white38, fontSize: 14.sp),
              prefixIcon: const Icon(Icons.search, color: Colors.white38),
              suffixIcon: _searchController.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.close, color: Colors.white38),
                      onPressed: () {
                        _searchController.clear();
                        setState(() => _searchQuery = '');
                      },
                    )
                  : null,
              filled: true,
              fillColor: AppColors.night,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12.r),
                borderSide: BorderSide.none,
              ),
              contentPadding: EdgeInsets.symmetric(vertical: 10.h),
            ),
          ),
          SizedBox(height: 8.h),
          // Filter tabs
          Row(
            children: [
              _buildFilterChip('Все', !_showFlaggedOnly),
              SizedBox(width: 8.w),
              _buildFilterChip(
                'С флагом (${_flaggedIds.length})',
                _showFlaggedOnly,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String label, bool selected) {
    return GestureDetector(
      onTap: () {
        setState(() => _showFlaggedOnly = !_showFlaggedOnly);
      },
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 6.h),
        decoration: BoxDecoration(
          color: selected ? AppColors.emerald : Colors.transparent,
          borderRadius: BorderRadius.circular(20.r),
          border: Border.all(
            color: selected ? AppColors.emerald : Colors.white30,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.white : Colors.white60,
            fontSize: 13.sp,
            fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
      ),
    );
  }

  Widget _buildIntervalSelector() {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 8.h),
      color: AppColors.emeraldDark.withOpacity(0.15),
      child: Row(
        children: [
          Icon(Icons.timer_outlined, color: Colors.white60, size: 20.sp),
          SizedBox(width: 8.w),
          Text(
            'Интервал проверки:',
            style: TextStyle(color: Colors.white70, fontSize: 13.sp),
          ),
          SizedBox(width: 8.w),
          Container(
            padding: EdgeInsets.symmetric(horizontal: 12.w),
            decoration: BoxDecoration(
              color: AppColors.night,
              borderRadius: BorderRadius.circular(8.r),
              border: Border.all(color: AppColors.emerald),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<int>(
                value: _selectedInterval,
                dropdownColor: AppColors.emeraldDark,
                style: TextStyle(color: Colors.white, fontSize: 13.sp),
                items: _intervalOptions.map((min) {
                  final label = min < 60 ? '$min мин' : '${min ~/ 60} ч';
                  return DropdownMenuItem(value: min, child: Text(label));
                }).toList(),
                onChanged: (value) {
                  if (value != null) {
                    setState(() {
                      _selectedInterval = value;
                      _hasChanges = true;
                    });
                  }
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProductList() {
    final products = _filteredProducts;

    if (products.isEmpty) {
      return Center(
        child: Text(
          _showFlaggedOnly
              ? 'Нет отмеченных товаров'
              : 'Товары не найдены',
          style: TextStyle(color: Colors.white38, fontSize: 15.sp),
        ),
      );
    }

    return ListView.builder(
      padding: EdgeInsets.symmetric(vertical: 4.h),
      itemCount: products.length,
      itemBuilder: (context, index) {
        final product = products[index];
        final isFlagged = _flaggedIds.contains(product.id);
        return OosProductTile(
          product: product,
          isFlagged: isFlagged,
          onToggle: () => _toggleProduct(product.id),
        );
      },
    );
  }

  Widget _buildSaveButton() {
    return Container(
      padding: EdgeInsets.all(16.w),
      decoration: BoxDecoration(
        color: AppColors.emeraldDark,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.3),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        child: SizedBox(
          width: double.infinity,
          height: 48.h,
          child: ElevatedButton(
            onPressed: _isSaving ? null : _saveSettings,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.gold,
              foregroundColor: AppColors.night,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12.r),
              ),
            ),
            child: _isSaving
                ? SizedBox(
                    width: 24.w,
                    height: 24.w,
                    child: const CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppColors.night,
                    ),
                  )
                : Text(
                    'Сохранить (${_flaggedIds.length} товаров)',
                    style: TextStyle(
                      fontSize: 16.sp,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}
