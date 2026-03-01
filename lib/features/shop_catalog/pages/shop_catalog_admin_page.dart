import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/logger.dart';
import '../models/shop_product.dart';
import '../models/shop_product_group.dart';
import '../services/shop_catalog_service.dart';


/// Админка каталога товаров (встраивается во вкладку «Управление сетью»)
class ShopCatalogAdminPage extends StatefulWidget {
  const ShopCatalogAdminPage({super.key});

  @override
  State<ShopCatalogAdminPage> createState() => _ShopCatalogAdminPageState();
}

class _ShopCatalogAdminPageState extends State<ShopCatalogAdminPage> with SingleTickerProviderStateMixin {
  static const _goldColor = Color(0xFFD4AF37);

  late TabController _tabController;
  bool _loading = true;

  List<ShopProductGroup> _groups = [];
  List<ShopProduct> _products = [];
  List<ShopProduct> _filteredProducts = [];
  List<Map<String, dynamic>> _authorizedEmployees = [];
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadAll();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadAll() async {
    try {
      // Invalidate client cache so clients see fresh data
      ShopCatalogService.invalidateCache();

      final results = await Future.wait([
        ShopCatalogService.getGroups(),
        ShopCatalogService.getProducts(),
        ShopCatalogService.getAuthorizedEmployees(),
      ]);
      if (mounted) setState(() {
        _groups = results[0] as List<ShopProductGroup>;
        _products = results[1] as List<ShopProduct>;
        _filteredProducts = _applyAdminSearch(_searchQuery);
        _authorizedEmployees = results[2] as List<Map<String, dynamic>>;
        _loading = false;
      });
    } catch (e) {
      Logger.error('Admin catalog load error', e);
      if (mounted) setState(() => _loading = false);
    }
  }

  List<ShopProduct> _applyAdminSearch(String query) {
    if (query.isEmpty) return List.of(_products);
    final q = query.toLowerCase();
    return _products.where((p) {
      if (p.name.toLowerCase().contains(q)) return true;
      if (p.description.toLowerCase().contains(q)) return true;
      if (p.groupId != null) {
        final group = _groups.where((g) => g.id == p.groupId).firstOrNull;
        if (group != null && group.name.toLowerCase().contains(q)) return true;
      }
      return false;
    }).toList();
  }

  String? _groupNameForId(String? groupId) {
    if (groupId == null) return null;
    return _groups.where((g) => g.id == groupId).firstOrNull?.name;
  }

  /// Resolve group name to ID: match existing or create new
  Future<String?> _resolveGroupId(String groupName) async {
    if (groupName.isEmpty) return null;
    final existing = _groups.where(
      (g) => g.name.toLowerCase() == groupName.toLowerCase(),
    ).firstOrNull;
    if (existing != null) return existing.id;
    final created = await ShopCatalogService.createGroup(name: groupName);
    if (created != null) {
      _groups.add(created);
      return created.id;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          color: AppColors.emeraldDark,
          child: TabBar(
            controller: _tabController,
            indicatorColor: _goldColor,
            labelColor: _goldColor,
            unselectedLabelColor: Colors.white.withOpacity(0.5),
            tabs: [
              Tab(text: 'Товары', icon: Icon(Icons.inventory_2_rounded, size: 18)),
              Tab(text: 'Группы', icon: Icon(Icons.category_rounded, size: 18)),
              Tab(text: 'Уполном.', icon: Icon(Icons.badge_rounded, size: 18)),
            ],
          ),
        ),
        Expanded(
          child: _loading
              ? Center(child: CircularProgressIndicator(color: _goldColor))
              : TabBarView(
                  controller: _tabController,
                  children: [
                    _buildProductsTab(),
                    _buildGroupsTab(),
                    _buildAuthorizedTab(),
                  ],
                ),
        ),
      ],
    );
  }

  // ==================== PRODUCTS TAB ====================

  Widget _buildProductsTab() {
    return Column(
      children: [
        // Search bar
        Padding(
          padding: EdgeInsets.fromLTRB(12.w, 8.h, 12.w, 0),
          child: TextField(
            style: TextStyle(color: Colors.white, fontSize: 14.sp),
            decoration: InputDecoration(
              hintText: 'Поиск по названию или группе...',
              hintStyle: TextStyle(color: Colors.white.withOpacity(0.3), fontSize: 13.sp),
              prefixIcon: Icon(Icons.search_rounded, color: Colors.white.withOpacity(0.3), size: 20),
              filled: true,
              fillColor: Colors.white.withOpacity(0.08),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12.r), borderSide: BorderSide.none),
              contentPadding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 10.h),
              isDense: true,
            ),
            onChanged: (q) {
              if (mounted) setState(() {
                _searchQuery = q;
                _filteredProducts = _applyAdminSearch(q);
              });
            },
          ),
        ),
        Padding(
          padding: EdgeInsets.fromLTRB(12.w, 8.h, 12.w, 4.h),
          child: ElevatedButton.icon(
            onPressed: _showAddProductDialog,
            icon: Icon(Icons.add, color: Colors.white),
            label: Text('Добавить товар', style: TextStyle(color: Colors.white)),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.emerald,
              minimumSize: Size(double.infinity, 40.h),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.r)),
            ),
          ),
        ),
        Expanded(
          child: _filteredProducts.isEmpty
              ? Center(child: Text(
                  _products.isEmpty ? 'Нет товаров' : 'Ничего не найдено',
                  style: TextStyle(color: Colors.white.withOpacity(0.5)),
                ))
              : GridView.builder(
                  padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 4.h),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    crossAxisSpacing: 10.w,
                    mainAxisSpacing: 10.h,
                    childAspectRatio: 0.48,
                  ),
                  itemCount: _filteredProducts.length,
                  itemBuilder: (ctx, i) => _buildProductTile(_filteredProducts[i]),
                ),
        ),
      ],
    );
  }

  Widget _buildProductTile(ShopProduct product) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20.r),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.15), blurRadius: 12, offset: Offset(0, 6)),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          // Photo card (like drinks menu)
          Expanded(
            child: Stack(
              children: [
                Positioned.fill(
                  child: product.photos.isEmpty
                      ? GestureDetector(
                          onTap: () => _uploadProductPhoto(product),
                          child: Container(
                            color: AppColors.emerald.withOpacity(0.15),
                            child: Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.add_a_photo_rounded, color: AppColors.emerald.withOpacity(0.4), size: 36),
                                  SizedBox(height: 4),
                                  Text('Добавить фото', style: TextStyle(color: AppColors.emerald.withOpacity(0.5), fontSize: 11.sp)),
                                ],
                              ),
                            ),
                          ),
                        )
                      : _ProductPhotoCarousel(
                          product: product,
                          onAddPhoto: () => _uploadProductPhoto(product),
                          onDeletePhoto: (i) => _deleteProductPhoto(product, i),
                        ),
                ),
                // Bottom gradient for name
                Positioned(
                  bottom: 0, left: 0, right: 0,
                  child: Container(
                    height: 60,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Colors.transparent, Colors.black.withOpacity(0.8)],
                      ),
                    ),
                  ),
                ),
                // Inactive badge
                if (!product.isActive)
                  Positioned(
                    top: 8.h, left: 8.w,
                    child: Container(
                      padding: EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                      decoration: BoxDecoration(color: Colors.red.withOpacity(0.85), borderRadius: BorderRadius.circular(8)),
                      child: Text('Скрыт', style: TextStyle(color: Colors.white, fontSize: 9.sp, fontWeight: FontWeight.bold)),
                    ),
                  ),
                // Wholesale badge
                if (product.isWholesale)
                  Positioned(
                    top: product.isActive ? 8.h : 30.h, left: 8.w,
                    child: Container(
                      padding: EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                      decoration: BoxDecoration(color: Colors.orange.withOpacity(0.85), borderRadius: BorderRadius.circular(8)),
                      child: Text('Опт', style: TextStyle(color: Colors.white, fontSize: 9.sp, fontWeight: FontWeight.bold)),
                    ),
                  ),
                // Name on gradient
                Positioned(
                  bottom: 8.h, left: 10.w, right: 10.w,
                  child: Text(
                    product.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white, fontSize: 14.sp, fontWeight: FontWeight.w600,
                      shadows: [Shadow(color: Colors.black54, blurRadius: 4)],
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Prices column under the card
          Container(
            width: double.infinity,
            padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 6.h),
            color: Colors.white,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (product.priceRetail != null)
                  _priceRow('Розница', '${product.priceRetail!.toStringAsFixed(0)} руб.', AppColors.primaryGreen),
                if (product.priceWholesale != null)
                  _priceRow('Опт', '${product.priceWholesale!.toStringAsFixed(0)} руб.', Colors.blueGrey.shade700),
                if (product.pricePoints != null)
                  _priceRow('Баллы', '${product.pricePoints}', Colors.deepPurple),
              ],
            ),
          ),
          // Action bar: 3 tabs
          Container(
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: Colors.grey.shade200)),
            ),
            child: Row(
              children: [
                _actionTab(Icons.add_a_photo_rounded, 'Фото', () => _uploadProductPhoto(product)),
                _actionTab(Icons.edit_rounded, 'Редакт.', () => _showEditProductDialog(product)),
                _actionTab(Icons.delete_outline, 'Удалить', () => _deleteProduct(product), color: Colors.red),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _priceRow(String label, String value, Color color) {
    return Padding(
      padding: EdgeInsets.only(bottom: 2.h),
      child: Row(
        children: [
          SizedBox(
            width: 55.w,
            child: Text(label, style: TextStyle(color: Colors.grey.shade500, fontSize: 10.sp)),
          ),
          Text(value, style: TextStyle(color: color, fontSize: 12.sp, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }

  Widget _actionTab(IconData icon, String label, VoidCallback onTap, {Color? color}) {
    final c = color ?? AppColors.primaryGreen;
    return Expanded(
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 8.h),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: c, size: 18),
              SizedBox(height: 2),
              Text(label, style: TextStyle(color: c, fontSize: 8.sp, fontWeight: FontWeight.w500)),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _deleteProductPhoto(ShopProduct product, int index) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.emeraldDark,
        title: Text('Удалить фото?', style: TextStyle(color: Colors.white)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text('Отмена', style: TextStyle(color: Colors.white60))),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: Text('Удалить', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final photos = await ShopCatalogService.deletePhoto(productId: product.id, index: index);
    if (photos != null) _loadAll();
  }

  Future<void> _showAddProductDialog() async {
    final nameCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    final groupCtrl = TextEditingController();
    final retailCtrl = TextEditingController();
    final wholesaleCtrl = TextEditingController();
    final pointsCtrl = TextEditingController();
    bool isWholesale = false;
    List<ShopProductGroup> groupSuggestions = [];

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setDialogState) => AlertDialog(
        backgroundColor: AppColors.emeraldDark,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16.r)),
        title: Text('Новый товар', style: TextStyle(color: Colors.white)),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _dialogField(nameCtrl, 'Название *'),
              _dialogField(descCtrl, 'Описание', maxLines: 3),
              // Editable group field with autocomplete
              Padding(
                padding: EdgeInsets.only(bottom: 4),
                child: TextField(
                  controller: groupCtrl,
                  style: TextStyle(color: Colors.white),
                  decoration: _dialogDecoration('Группа (введите или выберите)'),
                  onChanged: (val) {
                    setDialogState(() {
                      if (val.isEmpty) {
                        groupSuggestions = [];
                      } else {
                        final q = val.toLowerCase();
                        groupSuggestions = _groups.where((g) => g.name.toLowerCase().contains(q)).toList();
                      }
                    });
                  },
                ),
              ),
              if (groupSuggestions.isNotEmpty)
                Container(
                  constraints: BoxConstraints(maxHeight: 100),
                  margin: EdgeInsets.only(bottom: 8),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(8.r),
                  ),
                  child: ListView.builder(
                    shrinkWrap: true,
                    padding: EdgeInsets.zero,
                    itemCount: groupSuggestions.length,
                    itemBuilder: (_, i) {
                      final g = groupSuggestions[i];
                      return InkWell(
                        onTap: () => setDialogState(() {
                          groupCtrl.text = g.name;
                          groupSuggestions = [];
                        }),
                        child: Padding(
                          padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          child: Text(g.name, style: TextStyle(color: _goldColor, fontSize: 13.sp)),
                        ),
                      );
                    },
                  ),
                ),
              if (groupSuggestions.isEmpty && groupCtrl.text.isNotEmpty &&
                  !_groups.any((g) => g.name.toLowerCase() == groupCtrl.text.toLowerCase()))
                Padding(
                  padding: EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      Icon(Icons.add_circle_outline, color: _goldColor, size: 14),
                      SizedBox(width: 4),
                      Flexible(child: Text(
                        'Будет создана новая группа «${groupCtrl.text}»',
                        style: TextStyle(color: _goldColor.withOpacity(0.7), fontSize: 11.sp),
                      )),
                    ],
                  ),
                ),
              _dialogField(retailCtrl, 'Цена розница (руб)', keyboard: TextInputType.number),
              _dialogField(wholesaleCtrl, 'Цена опт (руб)', keyboard: TextInputType.number),
              _dialogField(pointsCtrl, 'Цена в баллах', keyboard: TextInputType.number),
              SwitchListTile(
                title: Text('Только для опта', style: TextStyle(color: Colors.white)),
                subtitle: Text('Видно только оптовым клиентам', style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 11)),
                value: isWholesale,
                activeColor: Colors.orange,
                contentPadding: EdgeInsets.zero,
                onChanged: (v) => setDialogState(() => isWholesale = v),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text('Отмена', style: TextStyle(color: Colors.white60))),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: _goldColor, foregroundColor: Colors.black),
            child: Text('Создать'),
          ),
        ],
      )),
    );

    if (result != true || nameCtrl.text.trim().isEmpty) return;

    try {
      final groupId = await _resolveGroupId(groupCtrl.text.trim());

      final created = await ShopCatalogService.createProduct(
        name: nameCtrl.text.trim(),
        description: descCtrl.text.trim(),
        groupId: groupId,
        priceRetail: double.tryParse(retailCtrl.text.trim()),
        priceWholesale: double.tryParse(wholesaleCtrl.text.trim()),
        pricePoints: int.tryParse(pointsCtrl.text.trim()),
        isWholesale: isWholesale,
      );
      if (created != null) {
        if (mounted) setState(() {
          _products.add(created);
          _filteredProducts = _applyAdminSearch(_searchQuery);
        });
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Ошибка создания товара'), backgroundColor: Colors.red),
          );
        }
      }
    } catch (e) {
      Logger.error('Create product error', e);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _showEditProductDialog(ShopProduct product) async {
    final nameCtrl = TextEditingController(text: product.name);
    final descCtrl = TextEditingController(text: product.description);
    final groupCtrl = TextEditingController(text: _groupNameForId(product.groupId) ?? '');
    final retailCtrl = TextEditingController(text: product.priceRetail?.toStringAsFixed(0) ?? '');
    final wholesaleCtrl = TextEditingController(text: product.priceWholesale?.toStringAsFixed(0) ?? '');
    final pointsCtrl = TextEditingController(text: product.pricePoints?.toString() ?? '');
    bool isActive = product.isActive;
    bool isWholesale = product.isWholesale;
    List<ShopProductGroup> groupSuggestions = [];

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setDialogState) => AlertDialog(
        backgroundColor: AppColors.emeraldDark,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16.r)),
        title: Text('Редактировать', style: TextStyle(color: Colors.white)),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _dialogField(nameCtrl, 'Название *'),
              _dialogField(descCtrl, 'Описание', maxLines: 3),
              // Editable group field with autocomplete
              Padding(
                padding: EdgeInsets.only(bottom: 4),
                child: TextField(
                  controller: groupCtrl,
                  style: TextStyle(color: Colors.white),
                  decoration: _dialogDecoration('Группа (введите или выберите)'),
                  onChanged: (val) {
                    setDialogState(() {
                      if (val.isEmpty) {
                        groupSuggestions = [];
                      } else {
                        final q = val.toLowerCase();
                        groupSuggestions = _groups.where((g) => g.name.toLowerCase().contains(q)).toList();
                      }
                    });
                  },
                ),
              ),
              if (groupSuggestions.isNotEmpty)
                Container(
                  constraints: BoxConstraints(maxHeight: 100),
                  margin: EdgeInsets.only(bottom: 8),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(8.r),
                  ),
                  child: ListView.builder(
                    shrinkWrap: true,
                    padding: EdgeInsets.zero,
                    itemCount: groupSuggestions.length,
                    itemBuilder: (_, i) {
                      final g = groupSuggestions[i];
                      return InkWell(
                        onTap: () => setDialogState(() {
                          groupCtrl.text = g.name;
                          groupSuggestions = [];
                        }),
                        child: Padding(
                          padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          child: Text(g.name, style: TextStyle(color: _goldColor, fontSize: 13.sp)),
                        ),
                      );
                    },
                  ),
                ),
              if (groupSuggestions.isEmpty && groupCtrl.text.isNotEmpty &&
                  !_groups.any((g) => g.name.toLowerCase() == groupCtrl.text.toLowerCase()))
                Padding(
                  padding: EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      Icon(Icons.add_circle_outline, color: _goldColor, size: 14),
                      SizedBox(width: 4),
                      Flexible(child: Text(
                        'Будет создана новая группа «${groupCtrl.text}»',
                        style: TextStyle(color: _goldColor.withOpacity(0.7), fontSize: 11.sp),
                      )),
                    ],
                  ),
                ),
              _dialogField(retailCtrl, 'Цена розница (руб)', keyboard: TextInputType.number),
              _dialogField(wholesaleCtrl, 'Цена опт (руб)', keyboard: TextInputType.number),
              _dialogField(pointsCtrl, 'Цена в баллах', keyboard: TextInputType.number),
              SizedBox(height: 8),
              SwitchListTile(
                title: Text('Активен', style: TextStyle(color: Colors.white)),
                value: isActive,
                activeColor: _goldColor,
                onChanged: (v) => setDialogState(() => isActive = v),
              ),
              SwitchListTile(
                title: Text('Только для опта', style: TextStyle(color: Colors.white)),
                subtitle: Text('Видно только оптовым клиентам', style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 11)),
                value: isWholesale,
                activeColor: Colors.orange,
                contentPadding: EdgeInsets.zero,
                onChanged: (v) => setDialogState(() => isWholesale = v),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text('Отмена', style: TextStyle(color: Colors.white60))),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: _goldColor, foregroundColor: Colors.black),
            child: Text('Сохранить'),
          ),
        ],
      )),
    );

    if (result != true) return;

    try {
      final groupId = await _resolveGroupId(groupCtrl.text.trim());

      final updated = await ShopCatalogService.updateProduct(
        id: product.id,
        name: nameCtrl.text.trim(),
        description: descCtrl.text.trim(),
        groupId: groupId,
        priceRetail: double.tryParse(retailCtrl.text.trim()),
        priceWholesale: double.tryParse(wholesaleCtrl.text.trim()),
        pricePoints: int.tryParse(pointsCtrl.text.trim()),
        isActive: isActive,
        isWholesale: isWholesale,
      );
      if (updated != null) {
        _loadAll();
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Ошибка сохранения товара'), backgroundColor: Colors.red),
          );
        }
      }
    } catch (e) {
      Logger.error('Update product error', e);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _uploadProductPhoto(ShopProduct product) async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery, maxWidth: 1200, imageQuality: 85);
    if (picked == null) return;

    final photos = await ShopCatalogService.uploadPhoto(productId: product.id, photoFile: File(picked.path));
    if (photos != null) _loadAll();
  }

  Future<void> _deleteProduct(ShopProduct product) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.emeraldDark,
        title: Text('Удалить товар?', style: TextStyle(color: Colors.white)),
        content: Text('«${product.name}» будет удалён', style: TextStyle(color: Colors.white70)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text('Отмена', style: TextStyle(color: Colors.white60))),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: Text('Удалить', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      final ok = await ShopCatalogService.deleteProduct(product.id);
      if (ok) {
        if (mounted) setState(() {
          _products.removeWhere((p) => p.id == product.id);
          _filteredProducts = _applyAdminSearch(_searchQuery);
        });
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Ошибка удаления товара'), backgroundColor: Colors.red),
          );
        }
      }
    } catch (e) {
      Logger.error('Delete product error', e);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  // ==================== GROUPS TAB ====================

  Widget _buildGroupsTab() {
    return Column(
      children: [
        Padding(
          padding: EdgeInsets.all(12.w),
          child: ElevatedButton.icon(
            onPressed: _showAddGroupDialog,
            icon: Icon(Icons.add, color: Colors.white),
            label: Text('Добавить группу', style: TextStyle(color: Colors.white)),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.emerald,
              minimumSize: Size(double.infinity, 44.h),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.r)),
            ),
          ),
        ),
        Expanded(
          child: _groups.isEmpty
              ? Center(child: Text('Нет групп', style: TextStyle(color: Colors.white.withOpacity(0.5))))
              : ListView.builder(
                  itemCount: _groups.length,
                  itemBuilder: (ctx, i) => _buildGroupTile(_groups[i]),
                ),
        ),
      ],
    );
  }

  Widget _buildGroupTile(ShopProductGroup group) {
    return ListTile(
      leading: Icon(Icons.category_rounded, color: _goldColor.withOpacity(0.6)),
      title: Text(group.name, style: TextStyle(color: Colors.white)),
      subtitle: Text(
        group.isWholesaleOnly ? 'Только опт' : 'Для всех',
        style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 12.sp),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: Icon(Icons.edit_rounded, color: Colors.white.withOpacity(0.5), size: 20),
            onPressed: () => _showEditGroupDialog(group),
          ),
          IconButton(
            icon: Icon(Icons.delete_outline, color: Colors.red.withOpacity(0.5), size: 20),
            onPressed: () async {
              final ok = await ShopCatalogService.deleteGroup(group.id);
              if (ok) { if (mounted) setState(() => _groups.removeWhere((g) => g.id == group.id)); }
            },
          ),
        ],
      ),
    );
  }

  Future<void> _showAddGroupDialog() async {
    final nameCtrl = TextEditingController();
    String visibility = 'all';

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setDialogState) => AlertDialog(
        backgroundColor: AppColors.emeraldDark,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16.r)),
        title: Text('Новая группа', style: TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _dialogField(nameCtrl, 'Название *'),
            SizedBox(height: 8),
            DropdownButtonFormField<String>(
              value: visibility,
              decoration: _dialogDecoration('Видимость'),
              dropdownColor: AppColors.emeraldDark,
              style: TextStyle(color: Colors.white),
              items: [
                DropdownMenuItem(value: 'all', child: Text('Для всех', style: TextStyle(color: Colors.white))),
                DropdownMenuItem(value: 'wholesale_only', child: Text('Только опт', style: TextStyle(color: Colors.white))),
              ],
              onChanged: (v) => setDialogState(() => visibility = v ?? 'all'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text('Отмена', style: TextStyle(color: Colors.white60))),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: _goldColor, foregroundColor: Colors.black),
            child: Text('Создать'),
          ),
        ],
      )),
    );

    if (result != true || nameCtrl.text.trim().isEmpty) return;
    final created = await ShopCatalogService.createGroup(name: nameCtrl.text.trim(), visibility: visibility);
    if (created != null) { if (mounted) setState(() => _groups.add(created)); }
  }

  Future<void> _showEditGroupDialog(ShopProductGroup group) async {
    final nameCtrl = TextEditingController(text: group.name);
    String visibility = group.visibility;

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setDialogState) => AlertDialog(
        backgroundColor: AppColors.emeraldDark,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16.r)),
        title: Text('Редактировать группу', style: TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _dialogField(nameCtrl, 'Название *'),
            SizedBox(height: 8),
            DropdownButtonFormField<String>(
              value: visibility,
              decoration: _dialogDecoration('Видимость'),
              dropdownColor: AppColors.emeraldDark,
              style: TextStyle(color: Colors.white),
              items: [
                DropdownMenuItem(value: 'all', child: Text('Для всех', style: TextStyle(color: Colors.white))),
                DropdownMenuItem(value: 'wholesale_only', child: Text('Только опт', style: TextStyle(color: Colors.white))),
              ],
              onChanged: (v) => setDialogState(() => visibility = v ?? 'all'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text('Отмена', style: TextStyle(color: Colors.white60))),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: _goldColor, foregroundColor: Colors.black),
            child: Text('Сохранить'),
          ),
        ],
      )),
    );

    if (result != true) return;
    final updated = await ShopCatalogService.updateGroup(id: group.id, name: nameCtrl.text.trim(), visibility: visibility);
    if (updated != null) _loadAll();
  }

  // ==================== AUTHORIZED EMPLOYEES TAB ====================

  Widget _buildAuthorizedTab() {
    return Column(
      children: [
        Padding(
          padding: EdgeInsets.all(12.w),
          child: ElevatedButton.icon(
            onPressed: _showAddEmployeeDialog,
            icon: Icon(Icons.person_add, color: Colors.white),
            label: Text('Добавить уполномоченного', style: TextStyle(color: Colors.white)),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.emerald,
              minimumSize: Size(double.infinity, 44.h),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.r)),
            ),
          ),
        ),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: 16.w),
          child: Text(
            'Уполномоченные сотрудники видят оптовые заказы и группы товаров с пометкой «только опт»',
            style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 12.sp),
          ),
        ),
        SizedBox(height: 8),
        Expanded(
          child: _authorizedEmployees.isEmpty
              ? Center(child: Text('Нет уполномоченных', style: TextStyle(color: Colors.white.withOpacity(0.5))))
              : ListView.builder(
                  itemCount: _authorizedEmployees.length,
                  itemBuilder: (ctx, i) {
                    final emp = _authorizedEmployees[i];
                    return ListTile(
                      leading: Icon(Icons.badge_rounded, color: _goldColor.withOpacity(0.6)),
                      title: Text(emp['name'] ?? emp['phone'] ?? '', style: TextStyle(color: Colors.white)),
                      subtitle: Text(emp['phone'] ?? '', style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 12.sp)),
                      trailing: IconButton(
                        icon: Icon(Icons.remove_circle_outline, color: Colors.red.withOpacity(0.5)),
                        onPressed: () async {
                          final ok = await ShopCatalogService.removeAuthorizedEmployee(emp['phone'] ?? '');
                          if (ok) { if (mounted) setState(() => _authorizedEmployees.removeAt(i)); }
                        },
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Future<void> _showAddEmployeeDialog() async {
    final phoneCtrl = TextEditingController();
    final nameCtrl = TextEditingController();

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.emeraldDark,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16.r)),
        title: Text('Добавить уполномоченного', style: TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _dialogField(phoneCtrl, 'Телефон *', keyboard: TextInputType.phone),
            _dialogField(nameCtrl, 'Имя'),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text('Отмена', style: TextStyle(color: Colors.white60))),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: _goldColor, foregroundColor: Colors.black),
            child: Text('Добавить'),
          ),
        ],
      ),
    );

    if (result != true || phoneCtrl.text.trim().isEmpty) return;
    final ok = await ShopCatalogService.addAuthorizedEmployee(phone: phoneCtrl.text.trim(), name: nameCtrl.text.trim());
    if (ok) _loadAll();
  }

  // ==================== HELPERS ====================

  Widget _dialogField(TextEditingController ctrl, String label, {TextInputType? keyboard, int maxLines = 1}) {
    return Padding(
      padding: EdgeInsets.only(bottom: 8),
      child: TextField(
        controller: ctrl,
        keyboardType: keyboard,
        maxLines: maxLines,
        style: TextStyle(color: Colors.white),
        decoration: _dialogDecoration(label),
      ),
    );
  }

  InputDecoration _dialogDecoration(String label) {
    return InputDecoration(
      labelText: label,
      labelStyle: TextStyle(color: Colors.white.withOpacity(0.5)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10.r),
        borderSide: BorderSide(color: Colors.white.withOpacity(0.2)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10.r),
        borderSide: BorderSide(color: _goldColor),
      ),
      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    );
  }
}

/// Photo carousel with swipe + dot indicators + delete button
class _ProductPhotoCarousel extends StatefulWidget {
  final ShopProduct product;
  final VoidCallback onAddPhoto;
  final void Function(int index) onDeletePhoto;

  const _ProductPhotoCarousel({
    required this.product,
    required this.onAddPhoto,
    required this.onDeletePhoto,
  });

  @override
  State<_ProductPhotoCarousel> createState() => _ProductPhotoCarouselState();
}

class _ProductPhotoCarouselState extends State<_ProductPhotoCarousel> {
  int _currentPage = 0;

  @override
  Widget build(BuildContext context) {
    final photos = widget.product.photos;
    return Stack(
      children: [
        // PageView carousel
        PageView.builder(
          itemCount: photos.length,
          onPageChanged: (i) { if (mounted) setState(() => _currentPage = i); },
          itemBuilder: (_, i) {
            final url = widget.product.getPhotoUrl(i);
            return Image.network(
              url ?? '',
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Container(
                color: AppColors.emerald.withOpacity(0.15),
                child: Icon(Icons.broken_image, color: Colors.white30, size: 32),
              ),
            );
          },
        ),
        // Dot indicators (if >1 photo)
        if (photos.length > 1)
          Positioned(
            bottom: 6,
            left: 0,
            right: 0,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(photos.length, (i) => Container(
                width: _currentPage == i ? 8 : 6,
                height: _currentPage == i ? 8 : 6,
                margin: EdgeInsets.symmetric(horizontal: 2),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _currentPage == i ? Colors.white : Colors.white.withOpacity(0.4),
                ),
              )),
            ),
          ),
        // Photo count badge
        if (photos.length > 1)
          Positioned(
            top: 6, right: 6,
            child: Container(
              padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.5),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '${_currentPage + 1}/${photos.length}',
                style: TextStyle(color: Colors.white, fontSize: 9.sp),
              ),
            ),
          ),
      ],
    );
  }
}
