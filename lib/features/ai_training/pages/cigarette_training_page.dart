import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../../../core/theme/app_colors.dart';
import '../services/master_catalog_service.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/constants/api_constants.dart';
import '../../employees/services/user_role_service.dart';
import '../models/cigarette_training_model.dart';
import '../services/cigarette_vision_service.dart';
import '../../employees/pages/employees_page.dart';
import '../../shops/services/shop_service.dart';
import '../../shops/models/shop_model.dart';
import 'cigarette_annotation_page.dart';
import 'photo_templates_page.dart';
import 'training_settings_page.dart';
import 'pending_codes_page.dart';
import '../../../shared/widgets/app_cached_image.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'cigarette_shop_selection_dialog.dart';
import 'cigarette_shop_details_dialog.dart';
import 'cigarette_photos_management_dialog.dart';

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

  // Pagination state
  int _totalProducts = 0;
  int _currentPage = 1;
  bool _hasMoreProducts = false;
  bool _isLoadingMore = false;

  // Products for "Обученные" and "Настройки" tabs (loaded separately)
  List<CigaretteProduct> _trainedProducts = [];
  List<CigaretteProduct> _productsWithPhotos = [];

  // Поиск по наименованию (вкладка Товары)
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  Timer? _searchDebounce;

  // Поиск по наименованию (вкладка Фото)
  final TextEditingController _photoSearchController = TextEditingController();
  String _photoSearchQuery = '';
  Timer? _photoSearchDebounce;

  // Сортировка по точности ИИ
  String _accuracySortMode = 'none'; // 'none', 'worst', 'best'

  // Вкладка "Ожидают" — фото с пересчёта для подтверждения
  List<TrainingSample> _pendingCountingSamples = [];
  bool _isPendingSelectionMode = false;
  Set<String> _selectedPendingIds = {};

  // Цвета и градиенты
  static final _greenGradient = [AppColors.emeraldGreen, AppColors.emeraldGreenLight];
  static final _blueGradient = [AppColors.info, AppColors.infoLight];
  static final _orangeGradient = [AppColors.warning, AppColors.warningLight];
  static final _purpleGradient = [AppColors.indigo, AppColors.purple];
  static final _redGradient = [AppColors.error, AppColors.errorLight];

  /// Количество вкладок зависит от роли
  /// Для админа: Фото, Товары, Новые, Ожидают, Обученные, Статистика, Настройки = 7
  /// Для сотрудника: Фото, Статистика = 2
  int get _tabCount => _isAdmin ? 7 : 2;

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
    final roleData = await UserRoleService.loadUserRole();
    final prefs = await SharedPreferences.getInstance();
    final shopAddress = prefs.getString('selectedShopAddress');

    // Загружаем магазины (ShopService кэширует на диск + в память)
    final shops = await ShopService.getShops();

    if (mounted) {
      setState(() {
        _isAdmin = roleData?.isAdmin == true || roleData?.isDeveloper == true;
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
    _photoSearchController.dispose();
    _searchDebounce?.cancel();
    _photoSearchDebounce?.cancel();
    super.dispose();
  }

  Future<void> _loadData() async {
    if (mounted) setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      // Перезагружаем выбранный магазин из SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      final shopAddress = prefs.getString('selectedShopAddress');

      // Determine sort for server
      String? sortParam;
      if (_accuracySortMode == 'worst') sortParam = 'accuracy-asc';
      if (_accuracySortMode == 'best') sortParam = 'accuracy-desc';

      final groups = await CigaretteVisionService.getProductGroups();
      // Paginated: first page only (50 items, ~250KB instead of 15MB)
      final response = await CigaretteVisionService.getProductsPaginated(
        productGroup: _selectedGroup,
        shopAddress: shopAddress,
        search: _searchQuery.isNotEmpty ? _searchQuery : null,
        sort: sortParam ?? 'progress-asc',
        page: 1,
        limit: 50,
      );
      final stats = await CigaretteVisionService.getStats();

      // Загружаем все pending-фото с пересчёта (для вкладки "Ожидают")
      final pendingSamples = _isAdmin
          ? await CigaretteVisionService.getAllPendingCountingSamples()
          : <TrainingSample>[];

      // Load trained products for "Обученные" tab (separate lightweight call)
      final trainedResponse = await CigaretteVisionService.getProductsPaginated(
        shopAddress: shopAddress,
        filter: 'counting-complete',
        sort: 'accuracy-asc',
        limit: 200,
      );

      // Load products with photos for "Настройки" tab
      final photosResponse = await CigaretteVisionService.getProductsPaginated(
        shopAddress: shopAddress,
        filter: 'has-photos',
        limit: 200,
      );

      if (mounted) {
        setState(() {
          _selectedShopAddress = shopAddress;
          _productGroups = groups;
          _products = response.products;
          _totalProducts = response.total;
          _currentPage = response.page;
          _hasMoreProducts = response.hasNextPage;
          _trainedProducts = trainedResponse.products;
          _productsWithPhotos = photosResponse.products;
          _stats = stats;
          _pendingCountingSamples = pendingSamples;
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

  /// Load next page of products (for "Показать ещё" button)
  Future<void> _loadMoreProducts() async {
    if (_isLoadingMore || !_hasMoreProducts) return;

    if (mounted) setState(() => _isLoadingMore = true);

    try {
      String? sortParam;
      if (_accuracySortMode == 'worst') sortParam = 'accuracy-asc';
      if (_accuracySortMode == 'best') sortParam = 'accuracy-desc';

      final response = await CigaretteVisionService.getProductsPaginated(
        productGroup: _selectedGroup,
        shopAddress: _selectedShopAddress,
        search: _searchQuery.isNotEmpty ? _searchQuery : null,
        sort: sortParam ?? 'progress-asc',
        page: _currentPage + 1,
        limit: 50,
      );

      if (mounted) {
        setState(() {
          _products.addAll(response.products);
          _currentPage = response.page;
          _hasMoreProducts = response.hasNextPage;
          _isLoadingMore = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoadingMore = false);
    }
  }

  /// Server-side search with debounce
  void _onProductSearchChanged(String value) {
    if (mounted) setState(() => _searchQuery = value);
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 400), () {
      _searchFromServer(value);
    });
  }

  Future<void> _searchFromServer(String query) async {
    if (!mounted) return;
    setState(() => _isLoading = true);

    try {
      String? sortParam;
      if (_accuracySortMode == 'worst') sortParam = 'accuracy-asc';
      if (_accuracySortMode == 'best') sortParam = 'accuracy-desc';

      final response = await CigaretteVisionService.getProductsPaginated(
        productGroup: _selectedGroup,
        shopAddress: _selectedShopAddress,
        search: query.isNotEmpty ? query : null,
        sort: sortParam ?? 'progress-asc',
        page: 1,
        limit: 50,
      );

      if (mounted) {
        setState(() {
          _products = response.products;
          _totalProducts = response.total;
          _currentPage = 1;
          _hasMoreProducts = response.hasNextPage;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// Photo search debounce (same as product search, reuses _products)
  void _onPhotoSearchChanged(String value) {
    if (mounted) setState(() => _photoSearchQuery = value);
    _photoSearchDebounce?.cancel();
    _photoSearchDebounce = Timer(const Duration(milliseconds: 400), () {
      _photoSearchFromServer(value);
    });
  }

  Future<void> _photoSearchFromServer(String query) async {
    if (!mounted) return;
    setState(() => _isLoading = true);

    try {
      final response = await CigaretteVisionService.getProductsPaginated(
        productGroup: _selectedGroup,
        shopAddress: _selectedShopAddress,
        search: query.isNotEmpty ? query : null,
        sort: 'progress-asc',
        page: 1,
        limit: 50,
      );

      if (mounted) {
        setState(() {
          _products = response.products;
          _totalProducts = response.total;
          _currentPage = 1;
          _hasMoreProducts = response.hasNextPage;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
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
              // Custom AppBar
              _buildCustomAppBar(),

              // TabBar
              _buildTabBar(),

              // Контент
              Expanded(
                child: _isLoading || _tabController == null
                    ? Center(
                        child: CircularProgressIndicator(color: Colors.white),
                      )
                    : _error != null
                        ? _buildErrorView()
                        : TabBarView(
                            controller: _tabController,
                            children: [
                              _buildAddPhotoTab(),                          // 0: Фото
                              if (_isAdmin) _buildProductsTab(),            // 1: Товары
                              if (_isAdmin) PendingCodesPage(onCodeApproved: _loadData), // 2: Новые
                              if (_isAdmin) _buildPendingTab(),             // 3: Ожидают
                              if (_isAdmin) _buildTrainedProductsTab(),     // 4: Обученные
                              _buildStatsTab(),                             // 5(admin)/1(emp): Статистика
                              if (_isAdmin) _buildSettingsTab(),            // 6: Настройки
                            ],
                          ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Получить короткое название магазина из адреса
  String _getShopDisplayName() {
    if (_selectedShopAddress == null) return '';
    final shop = _shops.where((s) => s.address == _selectedShopAddress).firstOrNull;
    return shop?.name ?? _selectedShopAddress!;
  }

  Widget _buildCustomAppBar() {
    final shopName = _getShopDisplayName();
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
            child: GestureDetector(
              onTap: _shops.isNotEmpty ? _showShopSelectionDialog : null,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Подсчёт сигарет',
                    textAlign: TextAlign.center,
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 20.sp,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (shopName.isNotEmpty) ...[
                    SizedBox(height: 2),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.store_rounded,
                          color: Colors.white.withOpacity(0.5),
                          size: 13,
                        ),
                        SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            shopName,
                            textAlign: TextAlign.center,
                            overflow: TextOverflow.ellipsis,
                            maxLines: 1,
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.5),
                              fontSize: 12.sp,
                              fontWeight: FontWeight.w400,
                            ),
                          ),
                        ),
                        SizedBox(width: 4),
                        Icon(
                          Icons.keyboard_arrow_down_rounded,
                          color: Colors.white.withOpacity(0.4),
                          size: 16,
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
          SizedBox(width: 48),
        ],
      ),
    );
  }

  Widget _buildTabBar() {
    if (_tabController == null) return SizedBox.shrink();

    // Для сотрудника — простая однорядная TabBar (2 вкладки)
    if (!_isAdmin) {
      return Container(
        margin: EdgeInsets.symmetric(horizontal: 16.w, vertical: 8.h),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.05),
          borderRadius: BorderRadius.circular(16.r),
          border: Border.all(color: Colors.white.withOpacity(0.1)),
        ),
        child: TabBar(
          controller: _tabController,
          indicator: BoxDecoration(
            gradient: LinearGradient(colors: _greenGradient),
            borderRadius: BorderRadius.circular(12.r),
            boxShadow: [BoxShadow(color: _greenGradient[0].withOpacity(0.4), blurRadius: 8, offset: Offset(0, 2))],
          ),
          indicatorSize: TabBarIndicatorSize.tab,
          indicatorPadding: EdgeInsets.all(4.w),
          dividerColor: Colors.transparent,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white.withOpacity(0.5),
          labelStyle: TextStyle(fontSize: 11.sp, fontWeight: FontWeight.w600),
          tabs: [
            Tab(icon: Icon(Icons.add_a_photo, size: 20), text: 'Фото'),
            Tab(icon: Icon(Icons.bar_chart, size: 20), text: 'Статистика'),
          ],
        ),
      );
    }

    // Для админа — 2 ряда: 4 сверху + 3 снизу
    // Ряд 1: Фото(0), Товары(1), Новые(2), Ожидают(3)
    // Ряд 2: Обученные(4), Статистика(5), Настройки(6)
    return AnimatedBuilder(
      animation: _tabController!,
      builder: (context, _) {
        final cur = _tabController!.index;
        return Container(
          margin: EdgeInsets.symmetric(horizontal: 16.w, vertical: 8.h),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.05),
            borderRadius: BorderRadius.circular(16.r),
            border: Border.all(color: Colors.white.withOpacity(0.1)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Ряд 1: 4 вкладки
              Row(children: [
                _tabItem(cur, 0, Icons.add_a_photo,    'Фото'),
                _tabItem(cur, 1, Icons.inventory_2,    'Товары'),
                _tabItem(cur, 2, Icons.new_releases,   'Новые'),
                _tabItem(cur, 3, Icons.schedule,       'Ожидают',
                    badge: _pendingCountingSamples.length),
              ]),
              Container(height: 0.5, color: Colors.white.withOpacity(0.1)),
              // Ряд 2: 3 вкладки
              Row(children: [
                _tabItem(cur, 4, Icons.model_training, 'Обученные'),
                _tabItem(cur, 5, Icons.bar_chart,      'Статистика'),
                _tabItem(cur, 6, Icons.settings,       'Настройки'),
              ]),
            ],
          ),
        );
      },
    );
  }

  /// Одна кнопка-вкладка для 2-рядного TabBar
  Widget _tabItem(int current, int index, IconData icon, String label, {int badge = 0}) {
    final selected = current == index;
    return Expanded(
      child: GestureDetector(
        onTap: () => _tabController!.animateTo(index),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          margin: EdgeInsets.all(4.w),
          padding: EdgeInsets.symmetric(vertical: 6.h),
          decoration: BoxDecoration(
            gradient: selected ? LinearGradient(colors: _greenGradient) : null,
            borderRadius: BorderRadius.circular(10.r),
            boxShadow: selected
                ? [BoxShadow(color: _greenGradient[0].withOpacity(0.4), blurRadius: 8, offset: Offset(0, 2))]
                : null,
          ),
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.center,
            children: [
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 18,
                      color: selected ? Colors.white : Colors.white.withOpacity(0.5)),
                  SizedBox(height: 2.h),
                  Text(label,
                      style: TextStyle(
                        fontSize: 10.sp,
                        fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                        color: selected ? Colors.white : Colors.white.withOpacity(0.5),
                      )),
                ],
              ),
              if (badge > 0)
                Positioned(
                  top: -2,
                  right: 4,
                  child: Container(
                    padding: EdgeInsets.all(3),
                    decoration: BoxDecoration(color: Colors.orange, shape: BoxShape.circle),
                    child: Text('$badge',
                        style: TextStyle(color: Colors.white, fontSize: 9.sp, fontWeight: FontWeight.bold)),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildErrorView() {
    return Center(
      child: Container(
        margin: EdgeInsets.all(24.w),
        padding: EdgeInsets.all(24.w),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.05),
          borderRadius: BorderRadius.circular(20.r),
          border: Border.all(
            color: AppColors.error.withOpacity(0.3),
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
                gradient: LinearGradient(colors: _redGradient),
                borderRadius: BorderRadius.circular(16.r),
              ),
              child: Icon(Icons.error_outline, size: 32, color: Colors.white),
            ),
            SizedBox(height: 16),
            Text(
              _error ?? 'Неизвестная ошибка',
              style: TextStyle(
                color: Colors.white.withOpacity(0.7),
                fontSize: 14.sp,
              ),
              textAlign: TextAlign.center,
            ),
            SizedBox(height: 16),
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
      padding: EdgeInsets.all(16.w),
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
        SizedBox(height: 16),

        // Поиск по наименованию (server-side)
        _buildPhotoSearchField(),
        SizedBox(height: 12),

        // Фильтр по группе
        if (_productGroups.isNotEmpty) ...[
          _buildGroupDropdown(),
          SizedBox(height: 16),
        ],

        // Счётчик товаров
        Padding(
          padding: EdgeInsets.only(bottom: 12.h),
          child: Text(
            _photoSearchQuery.isNotEmpty
                ? 'Найдено: $_totalProducts'
                : 'Показано: ${_products.length} из $_totalProducts',
            style: TextStyle(
              fontSize: 13.sp,
              color: Colors.white.withOpacity(0.6),
            ),
          ),
        ),

        // Список товаров для добавления фото (server-paginated)
        ..._products.map((product) => _buildProductCard(product, forUpload: true)),

        // Кнопка "Показать ещё"
        if (_hasMoreProducts)
          Padding(
            padding: EdgeInsets.symmetric(vertical: 16.h),
            child: Center(
              child: _isLoadingMore
                  ? CircularProgressIndicator(color: _greenGradient[0])
                  : OutlinedButton.icon(
                      onPressed: _loadMoreProducts,
                      icon: Icon(Icons.expand_more, color: Colors.white70),
                      label: Text(
                        'Показать ещё (${_products.length} из $_totalProducts)',
                        style: TextStyle(color: Colors.white70),
                      ),
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(color: Colors.white24),
                        padding: EdgeInsets.symmetric(horizontal: 24.w, vertical: 12.h),
                      ),
                    ),
            ),
          ),
      ],
    );
  }

  /// Поле поиска для вкладки Фото (с поддержкой опечаток)
  Widget _buildPhotoSearchField() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(12.r),
        border: Border.all(
          color: Colors.white.withOpacity(0.1),
          width: 1,
        ),
      ),
      child: TextField(
        controller: _photoSearchController,
        style: TextStyle(color: Colors.white),
        decoration: InputDecoration(
          hintText: 'Поиск по названию или штрихкоду...',
          hintStyle: TextStyle(color: Colors.white.withOpacity(0.4)),
          prefixIcon: Icon(
            Icons.search,
            color: Colors.white.withOpacity(0.5),
          ),
          suffixIcon: _photoSearchQuery.isNotEmpty
              ? IconButton(
                  icon: Icon(
                    Icons.clear,
                    color: Colors.white.withOpacity(0.5),
                  ),
                  onPressed: () {
                    _photoSearchController.clear();
                    _onPhotoSearchChanged('');
                  },
                )
              : null,
          border: InputBorder.none,
          contentPadding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 14.h),
        ),
        onChanged: _onPhotoSearchChanged,
      ),
    );
  }

  /// Вкладка списка товаров
  Widget _buildProductsTab() {
    // Server-side search/sort/filter — _products already contains the right page
    return RefreshIndicator(
      onRefresh: _loadData,
      color: _greenGradient[0],
      backgroundColor: AppColors.darkNavy,
      child: ListView(
        padding: EdgeInsets.all(16.w),
        children: [
          // Поиск по наименованию (server-side)
          _buildSearchField(),
          SizedBox(height: 12),

          // Фильтры: группа и точность
          Row(
            children: [
              if (_productGroups.isNotEmpty)
                Expanded(child: _buildGroupDropdown()),
              if (_productGroups.isNotEmpty)
                SizedBox(width: 12),
              Expanded(child: _buildAccuracySortDropdown()),
            ],
          ),
          SizedBox(height: 16),

          // Счётчик: показано N из M
          Padding(
            padding: EdgeInsets.only(bottom: 12.h),
            child: Text(
              _searchQuery.isNotEmpty
                  ? 'Найдено: $_totalProducts'
                  : 'Показано: ${_products.length} из $_totalProducts',
              style: TextStyle(
                fontSize: 13.sp,
                color: Colors.white.withOpacity(0.6),
              ),
            ),
          ),

          // Список товаров
          ..._products.map((product) => _buildProductCard(product)),

          // Кнопка "Показать ещё"
          if (_hasMoreProducts)
            Padding(
              padding: EdgeInsets.symmetric(vertical: 16.h),
              child: Center(
                child: _isLoadingMore
                    ? CircularProgressIndicator(color: _greenGradient[0])
                    : OutlinedButton.icon(
                        onPressed: _loadMoreProducts,
                        icon: Icon(Icons.expand_more, color: Colors.white70),
                        label: Text(
                          'Показать ещё (${_products.length} из $_totalProducts)',
                          style: TextStyle(color: Colors.white70),
                        ),
                        style: OutlinedButton.styleFrom(
                          side: BorderSide(color: Colors.white24),
                          padding: EdgeInsets.symmetric(horizontal: 24.w, vertical: 12.h),
                        ),
                      ),
              ),
            ),
        ],
      ),
    );
  }

  /// Поле поиска по наименованию
  Widget _buildSearchField() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(12.r),
        border: Border.all(
          color: Colors.white.withOpacity(0.1),
          width: 1,
        ),
      ),
      child: TextField(
        controller: _searchController,
        style: TextStyle(color: Colors.white),
        decoration: InputDecoration(
          hintText: 'Поиск по названию или штрихкоду...',
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
                    _onProductSearchChanged('');
                  },
                )
              : null,
          border: InputBorder.none,
          contentPadding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 14.h),
        ),
        onChanged: _onProductSearchChanged,
      ),
    );
  }

  /// Вкладка статистики
  Widget _buildStatsTab() {
    return RefreshIndicator(
      onRefresh: _loadData,
      color: _greenGradient[0],
      backgroundColor: AppColors.darkNavy,
      child: ListView(
        padding: EdgeInsets.all(16.w),
        children: [
          // Общий прогресс
          _buildOverallProgressCard(),
          SizedBox(height: 16),

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
              SizedBox(width: 12),
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
          SizedBox(height: 12),
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
              SizedBox(width: 12),
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
          SizedBox(height: 16),

          // Статистика фото
          _buildPhotoStatsCard(),
          SizedBox(height: 16),

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
      products: _productsWithPhotos,
      onSettingsChanged: _loadData,
    );
  }

  // ─── Вкладка "Ожидают" ─────────────────────────────────────────────────────

  /// Все фото с пересчёта, ожидающие подтверждения администратором
  Widget _buildPendingTab() {
    if (_pendingCountingSamples.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check_circle_outline, color: Colors.green, size: 64),
            SizedBox(height: 16.h),
            Text('Нет фото, ожидающих подтверждения',
                style: TextStyle(color: Colors.white70, fontSize: 14.sp)),
            SizedBox(height: 8.h),
            Text('Новые фото появятся после пересчёта сотрудниками',
                style: TextStyle(color: Colors.white38, fontSize: 12.sp),
                textAlign: TextAlign.center),
          ],
        ),
      );
    }

    return Column(
      children: [
        // ── Заголовок ──────────────────────────────────────────────────────────
        Padding(
          padding: EdgeInsets.fromLTRB(12.w, 10.h, 12.w, 6.h),
          child: _isPendingSelectionMode
              ? _buildSelectionHeader()
              : _buildNormalHeader(),
        ),
        // ── Сетка фото ─────────────────────────────────────────────────────────
        Expanded(
          child: GridView.builder(
            padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 4.h),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: 10.w,
              mainAxisSpacing: 10.h,
              childAspectRatio: 0.62,
            ),
            itemCount: _pendingCountingSamples.length,
            itemBuilder: (context, index) {
              final sample = _pendingCountingSamples[index];
              return _buildPendingCard(
                sample,
                isSelected: _selectedPendingIds.contains(sample.id),
                selectionMode: _isPendingSelectionMode,
              );
            },
          ),
        ),
      ],
    );
  }

  /// Обычный заголовок: счётчик + кнопка "Выбрать"
  Widget _buildNormalHeader() {
    return Row(
      children: [
        Icon(Icons.schedule, color: Colors.orange, size: 18),
        SizedBox(width: 8.w),
        Expanded(
          child: Text('Ожидают: ${_pendingCountingSamples.length}',
              style: TextStyle(color: Colors.white, fontSize: 14.sp, fontWeight: FontWeight.w600)),
        ),
        TextButton.icon(
          onPressed: _showSelectBottomSheet,
          icon: Icon(Icons.checklist, color: Colors.orange, size: 16),
          label: Text('Выбрать', style: TextStyle(color: Colors.orange, fontSize: 12.sp)),
          style: TextButton.styleFrom(
            padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 4.h),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
        ),
      ],
    );
  }

  /// Заголовок режима выбора: Отмена + счётчик + Подтвердить + Отклонить
  Widget _buildSelectionHeader() {
    final n = _selectedPendingIds.length;
    return Row(
      children: [
        // Отмена
        GestureDetector(
          onTap: () => setState(() {
            _isPendingSelectionMode = false;
            _selectedPendingIds.clear();
          }),
          child: Icon(Icons.close, color: Colors.white70, size: 22),
        ),
        SizedBox(width: 8.w),
        // Счётчик
        Expanded(
          child: Text(
            n == 0 ? 'Отметьте фото' : 'Выбрано: $n',
            style: TextStyle(
              color: n == 0 ? Colors.white38 : Colors.white,
              fontSize: 13.sp,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        // Подтвердить
        ElevatedButton.icon(
          onPressed: n == 0 ? null : _bulkApprovePending,
          icon: Icon(Icons.check, size: 14),
          label: Text('Одобрить', style: TextStyle(fontSize: 11.sp)),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.green[700],
            disabledBackgroundColor: Colors.green[900]!.withOpacity(0.4),
            padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 6.h),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8.r)),
          ),
        ),
        SizedBox(width: 6.w),
        // Отклонить
        ElevatedButton.icon(
          onPressed: n == 0 ? null : _bulkRejectPending,
          icon: Icon(Icons.close, size: 14),
          label: Text('Удалить', style: TextStyle(fontSize: 11.sp)),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.red[700],
            disabledBackgroundColor: Colors.red[900]!.withOpacity(0.4),
            padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 6.h),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8.r)),
          ),
        ),
      ],
    );
  }

  /// Шторка выбора режима: "Выбрать все" / "Отметить"
  void _showSelectBottomSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        decoration: BoxDecoration(
          color: AppColors.darkNavy,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20.r)),
          border: Border.all(color: Colors.white.withOpacity(0.1)),
        ),
        padding: EdgeInsets.fromLTRB(20.w, 16.h, 20.w, 32.h),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 36.w, height: 4.h,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2.r),
              ),
            ),
            SizedBox(height: 16.h),
            // Выбрать все
            ListTile(
              leading: Container(
                padding: EdgeInsets.all(8.w),
                decoration: BoxDecoration(color: Colors.green.withOpacity(0.15), shape: BoxShape.circle),
                child: Icon(Icons.select_all, color: Colors.green, size: 22),
              ),
              title: Text('Выбрать все', style: TextStyle(color: Colors.white, fontSize: 15.sp, fontWeight: FontWeight.w600)),
              subtitle: Text('Выделить все ${_pendingCountingSamples.length} фото сразу',
                  style: TextStyle(color: Colors.white54, fontSize: 12.sp)),
              onTap: () {
                Navigator.pop(context);
                setState(() {
                  _isPendingSelectionMode = true;
                  _selectedPendingIds = _pendingCountingSamples.map((s) => s.id).toSet();
                });
              },
            ),
            SizedBox(height: 8.h),
            // Отметить
            ListTile(
              leading: Container(
                padding: EdgeInsets.all(8.w),
                decoration: BoxDecoration(color: Colors.orange.withOpacity(0.15), shape: BoxShape.circle),
                child: Icon(Icons.touch_app, color: Colors.orange, size: 22),
              ),
              title: Text('Отметить', style: TextStyle(color: Colors.white, fontSize: 15.sp, fontWeight: FontWeight.w600)),
              subtitle: Text('Выбрать фото вручную по одному',
                  style: TextStyle(color: Colors.white54, fontSize: 12.sp)),
              onTap: () {
                Navigator.pop(context);
                setState(() {
                  _isPendingSelectionMode = true;
                  _selectedPendingIds.clear();
                });
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPendingCard(TrainingSample sample,
      {required bool isSelected, required bool selectionMode}) {
    return GestureDetector(
      onTap: selectionMode
          ? () => setState(() {
                if (isSelected) {
                  _selectedPendingIds.remove(sample.id);
                } else {
                  _selectedPendingIds.add(sample.id);
                }
              })
          : () => _showPendingDetailDialog(sample),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        decoration: BoxDecoration(
          color: isSelected
              ? Colors.green.withOpacity(0.12)
              : Colors.white.withOpacity(0.05),
          borderRadius: BorderRadius.circular(12.r),
          border: Border.all(
            color: isSelected ? Colors.green : Colors.orange.withOpacity(0.35),
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Фото с оверлеем галочки при выборе
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.vertical(top: Radius.circular(12.r)),
                    child: _PendingImageWithBoxes(
                      imageUrl: sample.imageUrl.startsWith('http')
                          ? sample.imageUrl
                          : '${ApiConstants.serverUrl}${sample.imageUrl}',
                      boundingBoxes: sample.boundingBoxes,
                      fit: BoxFit.cover,
                    ),
                  ),
                  // Значок аннотаций (рамки от сотрудника)
                  if (sample.hasAnnotations && !isSelected)
                    Positioned(
                      top: 6, left: 6,
                      child: Container(
                        padding: EdgeInsets.symmetric(horizontal: 6.w, vertical: 2.h),
                        decoration: BoxDecoration(
                          color: Colors.green.shade700,
                          borderRadius: BorderRadius.circular(8.r),
                          boxShadow: [BoxShadow(color: Colors.black54, blurRadius: 3)],
                        ),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          Icon(Icons.draw, color: Colors.white, size: 10),
                          SizedBox(width: 3),
                          Text('${sample.annotationCount}', style: TextStyle(color: Colors.white, fontSize: 10.sp, fontWeight: FontWeight.bold)),
                        ]),
                      ),
                    ),
                  // Галочка выбора
                  if (isSelected)
                    Positioned(
                      top: 8, right: 8,
                      child: Container(
                        width: 28, height: 28,
                        decoration: BoxDecoration(color: Colors.green, shape: BoxShape.circle,
                            boxShadow: [BoxShadow(color: Colors.black38, blurRadius: 4)]),
                        child: Icon(Icons.check, color: Colors.white, size: 18),
                      ),
                    ),
                  // Затемнение невыбранных в режиме выбора
                  if (selectionMode && !isSelected)
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.3),
                        borderRadius: BorderRadius.vertical(top: Radius.circular(12.r)),
                      ),
                    ),
                ],
              ),
            ),
            // Название товара
            Padding(
              padding: EdgeInsets.fromLTRB(8.w, 6.h, 8.w, 2.h),
              child: Text(sample.productName,
                  style: TextStyle(color: Colors.white, fontSize: 10.sp, fontWeight: FontWeight.w500),
                  maxLines: 2, overflow: TextOverflow.ellipsis),
            ),
            // Ответ сотрудника
            if (sample.employeeAnswer != null)
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 8.w),
                child: Row(children: [
                  Icon(Icons.person_outline, color: Colors.orange, size: 12),
                  SizedBox(width: 4.w),
                  Text('Ответ: ${sample.employeeAnswer}',
                      style: TextStyle(color: Colors.orange, fontSize: 10.sp, fontWeight: FontWeight.w600)),
                ]),
              ),
            // Магазин
            if (sample.shopAddress != null)
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 2.h),
                child: Text(sample.shopAddress!,
                    style: TextStyle(color: Colors.white38, fontSize: 9.sp),
                    maxLines: 1, overflow: TextOverflow.ellipsis),
              ),
            // Кнопки ✓/✗ — только в обычном режиме
            if (!selectionMode)
              Padding(
                padding: EdgeInsets.fromLTRB(6.w, 4.h, 6.w, 6.h),
                child: Row(children: [
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => _approvePendingSample(sample),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green[700], padding: EdgeInsets.zero,
                        minimumSize: Size(0, 30.h),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8.r)),
                      ),
                      child: Icon(Icons.check, color: Colors.white, size: 16),
                    ),
                  ),
                  SizedBox(width: 6.w),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => _rejectPendingSample(sample),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red[700], padding: EdgeInsets.zero,
                        minimumSize: Size(0, 30.h),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8.r)),
                      ),
                      child: Icon(Icons.close, color: Colors.white, size: 16),
                    ),
                  ),
                ]),
              ),
          ],
        ),
      ),
    );
  }

  /// Полноэкранный просмотр pending фото с наложенными bounding boxes
  void _showPendingDetailDialog(TrainingSample sample) {
    final imageUrl = sample.imageUrl.startsWith('http')
        ? sample.imageUrl
        : '${ApiConstants.serverUrl}${sample.imageUrl}';

    showDialog(
      context: context,
      barrierColor: Colors.black87,
      builder: (ctx) => Dialog.fullscreen(
        backgroundColor: Colors.black,
        child: SafeArea(
          child: Column(
            children: [
              // Шапка: название + закрыть
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 4.h),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: () => Navigator.pop(ctx),
                      icon: Icon(Icons.close, color: Colors.white, size: 24),
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(sample.productName,
                              style: TextStyle(color: Colors.white, fontSize: 14.sp, fontWeight: FontWeight.w600),
                              maxLines: 1, overflow: TextOverflow.ellipsis),
                          if (sample.employeeAnswer != null)
                            Text('Ответ сотрудника: ${sample.employeeAnswer}',
                                style: TextStyle(color: Colors.orange, fontSize: 12.sp)),
                        ],
                      ),
                    ),
                    if (sample.hasAnnotations)
                      Container(
                        padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 4.h),
                        decoration: BoxDecoration(
                          color: Colors.green.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(8.r),
                        ),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          Icon(Icons.draw, color: Colors.green, size: 14),
                          SizedBox(width: 4),
                          Text('${sample.annotationCount} рамок',
                              style: TextStyle(color: Colors.green, fontSize: 12.sp, fontWeight: FontWeight.w600)),
                        ]),
                      ),
                  ],
                ),
              ),
              // Фото с рамками
              Expanded(
                child: _PendingImageWithBoxes(
                  imageUrl: imageUrl,
                  boundingBoxes: sample.boundingBoxes,
                ),
              ),
              // Инфо + кнопки
              Container(
                padding: EdgeInsets.fromLTRB(16.w, 8.h, 16.w, 12.h),
                color: Colors.black,
                child: Column(
                  children: [
                    if (sample.shopAddress != null)
                      Padding(
                        padding: EdgeInsets.only(bottom: 8.h),
                        child: Row(children: [
                          Icon(Icons.store, color: Colors.white38, size: 14),
                          SizedBox(width: 6),
                          Expanded(child: Text(sample.shopAddress!,
                              style: TextStyle(color: Colors.white38, fontSize: 12.sp))),
                        ]),
                      ),
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: () {
                              Navigator.pop(ctx);
                              _approvePendingSample(sample);
                            },
                            icon: Icon(Icons.check, size: 18),
                            label: Text('Одобрить'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.green[700],
                              foregroundColor: Colors.white,
                              padding: EdgeInsets.symmetric(vertical: 12.h),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.r)),
                            ),
                          ),
                        ),
                        SizedBox(width: 12.w),
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: () {
                              Navigator.pop(ctx);
                              _rejectPendingSample(sample);
                            },
                            icon: Icon(Icons.close, size: 18),
                            label: Text('Отклонить'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.red[700],
                              foregroundColor: Colors.white,
                              padding: EdgeInsets.symmetric(vertical: 12.h),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.r)),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _approvePendingSample(TrainingSample sample) async {
    final success = await CigaretteVisionService.approvePendingCountingSample(sample.id);
    if (success && mounted) {
      setState(() => _pendingCountingSamples.removeWhere((s) => s.id == sample.id));
    }
  }

  Future<void> _rejectPendingSample(TrainingSample sample) async {
    final success = await CigaretteVisionService.rejectPendingCountingSample(sample.id);
    if (success && mounted) {
      setState(() => _pendingCountingSamples.removeWhere((s) => s.id == sample.id));
    }
  }

  Future<void> _bulkApprovePending() async {
    final ids = _selectedPendingIds.toList();
    for (final id in ids) {
      await CigaretteVisionService.approvePendingCountingSample(id);
    }
    if (mounted) {
      setState(() {
        _pendingCountingSamples.removeWhere((s) => ids.contains(s.id));
        _selectedPendingIds.clear();
        _isPendingSelectionMode = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Одобрено: ${ids.length}')),
      );
    }
  }

  Future<void> _bulkRejectPending() async {
    final ids = _selectedPendingIds.toList();
    for (final id in ids) {
      await CigaretteVisionService.rejectPendingCountingSample(id);
    }
    if (mounted) {
      setState(() {
        _pendingCountingSamples.removeWhere((s) => ids.contains(s.id));
        _selectedPendingIds.clear();
        _isPendingSelectionMode = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Удалено: ${ids.length}')),
      );
    }
  }

  Widget _buildInfoCard({
    required IconData icon,
    required String title,
    required String description,
    required List<Color> gradient,
  }) {
    return Container(
      padding: EdgeInsets.all(16.w),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(16.r),
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
                  borderRadius: BorderRadius.circular(10.r),
                ),
                child: Icon(icon, color: Colors.white, size: 20),
              ),
              SizedBox(width: 12),
              Text(
                title,
                style: TextStyle(
                  fontSize: 16.sp,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
            ],
          ),
          SizedBox(height: 12),
          Text(
            description,
            style: TextStyle(
              fontSize: 13.sp,
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
      padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 4.h),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(12.r),
        border: Border.all(
          color: Colors.white.withOpacity(0.1),
          width: 1,
        ),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: _selectedGroup,
          isExpanded: true,
          dropdownColor: AppColors.darkNavy,
          icon: Icon(Icons.expand_more, color: Colors.white.withOpacity(0.5)),
          hint: Row(
            children: [
              Icon(Icons.filter_list, color: Colors.white.withOpacity(0.5), size: 18),
              SizedBox(width: 6),
              Flexible(child: Text(
                'Все группы',
                style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 13.sp),
                overflow: TextOverflow.ellipsis,
              )),
            ],
          ),
          items: [
            DropdownMenuItem(
              value: null,
              child: Row(
                children: [
                  Icon(Icons.filter_list, color: Colors.white.withOpacity(0.5), size: 18),
                  SizedBox(width: 6),
                  Flexible(child: Text('Все группы', style: TextStyle(color: Colors.white, fontSize: 13.sp), overflow: TextOverflow.ellipsis)),
                ],
              ),
            ),
            ..._productGroups.map((group) => DropdownMenuItem(
              value: group,
              child: Text(group, style: TextStyle(color: Colors.white)),
            )),
          ],
          onChanged: (value) {
            if (mounted) setState(() {
              _selectedGroup = value;
            });
            _loadData();
          },
        ),
      ),
    );
  }

  /// Dropdown сортировки по точности ИИ
  Widget _buildAccuracySortDropdown() {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 4.h),
      decoration: BoxDecoration(
        color: _accuracySortMode != 'none'
            ? (_accuracySortMode == 'worst' ? _redGradient[0] : _greenGradient[0]).withOpacity(0.1)
            : Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(12.r),
        border: Border.all(
          color: _accuracySortMode != 'none'
              ? (_accuracySortMode == 'worst' ? _redGradient[0] : _greenGradient[0]).withOpacity(0.3)
              : Colors.white.withOpacity(0.1),
          width: 1,
        ),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: _accuracySortMode,
          isExpanded: true,
          dropdownColor: AppColors.darkNavy,
          icon: Icon(Icons.expand_more, color: Colors.white.withOpacity(0.5)),
          items: [
            DropdownMenuItem(
              value: 'none',
              child: Row(
                children: [
                  Icon(Icons.sort, color: Colors.white.withOpacity(0.5), size: 18),
                  SizedBox(width: 6),
                  Flexible(child: Text('По прогрессу', style: TextStyle(color: Colors.white, fontSize: 13.sp), overflow: TextOverflow.ellipsis)),
                ],
              ),
            ),
            DropdownMenuItem(
              value: 'worst',
              child: Row(
                children: [
                  Icon(Icons.trending_down, color: _redGradient[0], size: 18),
                  SizedBox(width: 6),
                  Flexible(child: Text('Худшая точность', style: TextStyle(color: _redGradient[0], fontSize: 13.sp), overflow: TextOverflow.ellipsis)),
                ],
              ),
            ),
            DropdownMenuItem(
              value: 'best',
              child: Row(
                children: [
                  Icon(Icons.trending_up, color: _greenGradient[0], size: 18),
                  SizedBox(width: 6),
                  Flexible(child: Text('Лучшая точность', style: TextStyle(color: _greenGradient[0], fontSize: 13.sp), overflow: TextOverflow.ellipsis)),
                ],
              ),
            ),
          ],
          onChanged: (value) {
            if (mounted) setState(() {
              _accuracySortMode = value ?? 'none';
            });
            _searchFromServer(_searchQuery);
          },
        ),
      ),
    );
  }

  Widget _buildOverallProgressCard() {
    final progress = _stats.overallProgress / 100;
    final progressColor = _getProgressGradient(_stats.overallProgress);

    return Container(
      padding: EdgeInsets.all(20.w),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(20.r),
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
                  borderRadius: BorderRadius.circular(12.r),
                ),
                child: Icon(Icons.trending_up, color: Colors.white, size: 24),
              ),
              SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Общий прогресс обучения',
                  style: TextStyle(
                    fontSize: 16.sp,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
              ),
              ShaderMask(
                shaderCallback: (bounds) => LinearGradient(colors: progressColor).createShader(bounds),
                child: Text(
                  '${_stats.overallProgress.toStringAsFixed(1)}%',
                  style: TextStyle(
                    fontSize: 24.sp,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: 16),
          Container(
            height: 12,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.1),
              borderRadius: BorderRadius.circular(6.r),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(6.r),
              child: Stack(
                children: [
                  FractionallySizedBox(
                    widthFactor: progress,
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(colors: progressColor),
                        borderRadius: BorderRadius.circular(6.r),
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
      padding: EdgeInsets.all(16.w),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(16.r),
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
              borderRadius: BorderRadius.circular(12.r),
              boxShadow: [
                BoxShadow(
                  color: gradient[0].withOpacity(0.4),
                  blurRadius: 8,
                  offset: Offset(0, 2),
                ),
              ],
            ),
            child: Icon(icon, color: Colors.white, size: 24),
          ),
          SizedBox(height: 12),
          ShaderMask(
            shaderCallback: (bounds) => LinearGradient(colors: gradient).createShader(bounds),
            child: Text(
              value,
              style: TextStyle(
                fontSize: 28.sp,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
          ),
          SizedBox(height: 4),
          Text(
            title,
            style: TextStyle(
              fontSize: 12.sp,
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
      padding: EdgeInsets.all(20.w),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(20.r),
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
                  gradient: LinearGradient(colors: _purpleGradient),
                  borderRadius: BorderRadius.circular(10.r),
                ),
                child: Icon(Icons.photo_library, color: Colors.white, size: 20),
              ),
              SizedBox(width: 12),
              Text(
                'Загружено фотографий',
                style: TextStyle(
                  fontSize: 16.sp,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
            ],
          ),
          SizedBox(height: 20),
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
            borderRadius: BorderRadius.circular(10.r),
          ),
          child: Icon(icon, color: Colors.white, size: 20),
        ),
        SizedBox(height: 8),
        ShaderMask(
          shaderCallback: (bounds) => LinearGradient(colors: gradient).createShader(bounds),
          child: Text(
            '$value',
            style: TextStyle(
              fontSize: 24.sp,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
        ),
        Text(
          label,
          style: TextStyle(
            fontSize: 12.sp,
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
    final countingGradient = _getProgressGradient(product.countingProgress);

    return Container(
      margin: EdgeInsets.only(bottom: 6.h),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(12.r),
        border: Border.all(
          color: Colors.white.withOpacity(0.1),
          width: 1,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: forUpload ? () => _showPhotoTypeDialog(product) : () => _showProductDetails(product),
          borderRadius: BorderRadius.circular(12.r),
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 8.h),
            child: Column(
              children: [
                // Заголовок: иконка + название + кнопка справа
                Row(
                  children: [
                    // Фото товара или иконка статуса
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        gradient: product.productPhotoUrl == null
                            ? LinearGradient(colors: progressGradient)
                            : null,
                        borderRadius: BorderRadius.circular(8.r),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: product.productPhotoUrl != null
                          ? AppCachedImage(
                              imageUrl: '${ApiConstants.serverUrl}${product.productPhotoUrl}',
                              width: 32,
                              height: 32,
                              fit: BoxFit.cover,
                              errorWidget: (ctx, url, err) => Container(
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(colors: progressGradient),
                                ),
                                child: Icon(Icons.inventory_2, color: Colors.white, size: 16),
                              ),
                            )
                          : Icon(
                              product.isTrainingComplete
                                  ? Icons.check_circle
                                  : Icons.add_a_photo,
                              color: Colors.white,
                              size: 16,
                            ),
                    ),
                    SizedBox(width: 8),

                    // Название товара
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            product.productName,
                            style: TextStyle(
                              fontSize: 12.sp,
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (product.productGroup.isNotEmpty || product.barcodes.length > 1)
                            Row(
                              children: [
                                if (product.productGroup.isNotEmpty)
                                  Flexible(
                                    child: Text(
                                      product.productGroup,
                                      style: TextStyle(fontSize: 10.sp, color: Colors.white.withOpacity(0.5)),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                if (product.barcodes.length > 1) ...[
                                  if (product.productGroup.isNotEmpty)
                                    Text(' \u2022 ', style: TextStyle(fontSize: 10.sp, color: Colors.white.withOpacity(0.3))),
                                  Text(
                                    '${product.barcodes.length} шт-кодов',
                                    style: TextStyle(fontSize: 10.sp, color: Colors.white.withOpacity(0.5)),
                                  ),
                                ],
                              ],
                            ),
                        ],
                      ),
                    ),
                    SizedBox(width: 6),

                    // Кнопка добавления фото или Toggle ИИ
                    if (forUpload)
                      Icon(Icons.camera_alt, color: Colors.white.withOpacity(0.5), size: 18)
                    else if (_isAdmin)
                      _buildAiToggle(product)
                    else
                      SizedBox(width: 32),
                  ],
                ),
                SizedBox(height: 6),

                // Прогресс-бары
                _buildProgressRow(
                  icon: Icons.crop_free,
                  progress: product.recountProgress / 100,
                  label: '${product.recountPhotosCount}/${product.requiredRecountPhotos}',
                  gradient: recountGradient,
                  isComplete: product.isRecountComplete,
                ),
                SizedBox(height: 4),
                if (_isAdmin)
                  _buildShopsSummaryRow(product, displayGradient)
                else if (_selectedShopAddress != null && _selectedShopAddress!.isNotEmpty)
                  _buildShopProgressRow(product, displayGradient)
                else
                  _buildNoShopSelectedRow(),
                SizedBox(height: 4),
                _buildCountingProgressRow(product, countingGradient),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Компактная плашка прогресса (иконка + бар + лейбл в одну строку)
  Widget _buildProgressRow({
    required IconData icon,
    required double progress,
    required String label,
    required List<Color> gradient,
    required bool isComplete,
  }) {
    final mainColor = isComplete ? _greenGradient[0] : gradient[0];

    return Padding(
      padding: EdgeInsets.symmetric(vertical: 1.h),
      child: Row(
        children: [
          Icon(icon, size: 14, color: mainColor),
          SizedBox(width: 6),
          Expanded(
            child: Container(
              height: 5,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.1),
                borderRadius: BorderRadius.circular(3.r),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(3.r),
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
          SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(fontSize: 10.sp, fontWeight: FontWeight.w600, color: mainColor),
          ),
          if (isComplete) ...[
            SizedBox(width: 3),
            Icon(Icons.check_circle, size: 12, color: _greenGradient[0]),
          ],
        ],
      ),
    );
  }

  /// Сводка по магазинам для админа (X/Y магазинов готовы)
  /// Двухстрочный дизайн: прогресс-бар сверху, бейджи снизу
  Widget _buildShopsSummaryRow(CigaretteProduct product, List<Color> gradient) {
    final ready = product.shopsWithAiReady;
    final total = product.totalShops;
    final isComplete = ready > 0;
    final progress = total > 0 ? ready / total : 0.0;
    final summaryGradient = _getProgressGradient(progress * 100);
    final mainColor = isComplete ? _greenGradient[0] : summaryGradient[0];

    return InkWell(
      onTap: () => _showShopDetailsDialog(product),
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: 1.h),
        child: Row(
          children: [
            Icon(Icons.store, size: 14, color: mainColor),
            SizedBox(width: 6),
            Expanded(
              child: Container(
                height: 5,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(3.r),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(3.r),
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
            SizedBox(width: 6),
            Text(
              '$ready/$total',
              style: TextStyle(fontSize: 10.sp, fontWeight: FontWeight.w600, color: mainColor),
            ),
            if (isComplete) ...[
              SizedBox(width: 3),
              Icon(Icons.check_circle, size: 12, color: _greenGradient[0]),
            ],
            if (product.displayAccuracy != null) ...[
              SizedBox(width: 4),
              _buildAccuracyBadge(product.displayAccuracy!, product.displayAttempts),
            ],
            SizedBox(width: 4),
            Icon(Icons.chevron_right, size: 14, color: Colors.white.withOpacity(0.5)),
          ],
        ),
      ),
    );
  }

  /// Прогресс для конкретного магазина (сотрудник)
  /// Двухстрочный дизайн: прогресс-бар сверху, статистика снизу
  Widget _buildShopProgressRow(CigaretteProduct product, List<Color> gradient) {
    final shopStats = product.getShopStats(_selectedShopAddress ?? '');

    if (shopStats == null) {
      return _buildNoShopSelectedRow();
    }

    final isComplete = shopStats.isDisplayComplete;
    final progress = shopStats.progress / 100;
    final shopGradient = _getProgressGradient(shopStats.progress);
    final mainColor = isComplete ? _greenGradient[0] : shopGradient[0];

    return Padding(
      padding: EdgeInsets.symmetric(vertical: 1.h),
      child: Row(
        children: [
          Icon(Icons.grid_view, size: 14, color: mainColor),
          SizedBox(width: 6),
          Expanded(
            child: Container(
              height: 5,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.1),
                borderRadius: BorderRadius.circular(3.r),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(3.r),
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
          SizedBox(width: 6),
          Text(
            '${shopStats.displayPhotosCount}/${shopStats.requiredDisplayPhotos}',
            style: TextStyle(fontSize: 10.sp, fontWeight: FontWeight.w600, color: mainColor),
          ),
          if (isComplete) ...[
            SizedBox(width: 3),
            Icon(Icons.check_circle, size: 12, color: _greenGradient[0]),
          ],
        ],
      ),
    );
  }

  /// Магазин не выбран
  /// Двухстрочный дизайн для единообразия
  Widget _buildNoShopSelectedRow() {
    return InkWell(
      onTap: _showShopSelectionDialog,
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: 1.h),
        child: Row(
          children: [
            Icon(Icons.warning_amber, size: 14, color: _orangeGradient[0]),
            SizedBox(width: 6),
            Expanded(
              child: Text(
                'Выберите магазин',
                style: TextStyle(fontSize: 10.sp, fontWeight: FontWeight.w600, color: _orangeGradient[0]),
              ),
            ),
            Icon(Icons.chevron_right, size: 14, color: _orangeGradient[0]),
          ],
        ),
      ),
    );
  }

  /// Прогресс фото пересчёта (counting) для обучения ИИ
  /// Двухстрочный дизайн: прогресс-бар сверху, бейджи снизу
  Widget _buildCountingProgressRow(CigaretteProduct product, List<Color> gradient) {
    final isComplete = product.isCountingComplete;
    final progress = product.countingProgress / 100;
    final hasPending = product.pendingCountingPhotosCount > 0;
    final hasPhotos = product.countingPhotosCount > 0 || hasPending;
    final mainColor = isComplete ? _greenGradient[0] : gradient[0];

    return InkWell(
      onTap: hasPhotos ? () => _showCountingSamplesDialog(product) : null,
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: 1.h),
        child: Row(
          children: [
            Icon(Icons.calculate, size: 14, color: mainColor),
            SizedBox(width: 6),
            Expanded(
              child: Container(
                height: 5,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(3.r),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(3.r),
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
            SizedBox(width: 6),
            Text(
              '${product.countingPhotosCount}/${product.requiredCountingPhotos}',
              style: TextStyle(fontSize: 10.sp, fontWeight: FontWeight.w600, color: mainColor),
            ),
            if (isComplete) ...[
              SizedBox(width: 3),
              Icon(Icons.check_circle, size: 12, color: _greenGradient[0]),
            ],
            if (product.countingAccuracy != null) ...[
              SizedBox(width: 4),
              _buildAccuracyBadge(product.countingAccuracy!, product.countingAttempts),
            ],
            if (hasPending) ...[
              SizedBox(width: 4),
              Text(
                '+${product.pendingCountingPhotosCount}',
                style: TextStyle(fontSize: 10.sp, fontWeight: FontWeight.bold, color: AppColors.amberLight),
              ),
            ],
            if (hasPhotos) ...[
              SizedBox(width: 4),
              Icon(Icons.chevron_right, size: 14, color: Colors.white.withOpacity(0.5)),
            ],
          ],
        ),
      ),
    );
  }

  /// Бейдж с процентом точности ИИ
  /// Цвет зависит от точности: зелёный (>=70%), оранжевый (40-69%), красный (<40%)
  Widget _buildAccuracyBadge(int accuracy, int attempts) {
    Color badgeColor;
    Color textColor;
    if (accuracy >= 70) {
      badgeColor = _greenGradient[0].withOpacity(0.2);
      textColor = _greenGradient[0];
    } else if (accuracy >= 40) {
      badgeColor = _orangeGradient[0].withOpacity(0.2);
      textColor = _orangeGradient[0];
    } else {
      badgeColor = _redGradient[0].withOpacity(0.2);
      textColor = _redGradient[0];
    }

    return Tooltip(
      message: 'Точность ИИ: $accuracy% (из $attempts попыток)',
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 6.w, vertical: 3.h),
        decoration: BoxDecoration(
          color: badgeColor,
          borderRadius: BorderRadius.circular(6.r),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              accuracy >= 70 ? Icons.trending_up : (accuracy >= 40 ? Icons.trending_flat : Icons.trending_down),
              size: 12,
              color: textColor,
            ),
            SizedBox(width: 3),
            Text(
              '$accuracy%',
              style: TextStyle(
                fontSize: 11.sp,
                fontWeight: FontWeight.bold,
                color: textColor,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ==================== Вкладка "Обученные" ====================

  /// Вкладка со списком товаров, у которых собраны все фото для обучения
  Widget _buildTrainedProductsTab() {
    // _trainedProducts already loaded from server with filter=counting-complete, sort=accuracy-asc
    final trainedProducts = _trainedProducts;

    if (trainedProducts.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.model_training, size: 64, color: Colors.white.withOpacity(0.3)),
            SizedBox(height: 16),
            Text(
              'Нет обученных товаров',
              style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 16.sp),
            ),
            SizedBox(height: 8),
            Text(
              'Здесь появятся товары, у которых\nсобраны все фото для обучения',
              style: TextStyle(color: Colors.white.withOpacity(0.3), fontSize: 13.sp),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        // Заголовок с количеством
        Padding(
          padding: EdgeInsets.fromLTRB(16.w, 12.h, 16.w, 8.h),
          child: Row(
            children: [
              Container(
                padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 4.h),
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: _greenGradient),
                  borderRadius: BorderRadius.circular(12.r),
                ),
                child: Text(
                  '${trainedProducts.length}',
                  style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.bold, color: Colors.white),
                ),
              ),
              SizedBox(width: 8),
              Text(
                'Обученные товары',
                style: TextStyle(fontSize: 14.sp, color: Colors.white.withOpacity(0.7)),
              ),
            ],
          ),
        ),

        // Список товаров
        Expanded(
          child: ListView.builder(
            padding: EdgeInsets.symmetric(horizontal: 16.w),
            itemCount: trainedProducts.length,
            itemBuilder: (context, index) {
              final product = trainedProducts[index];
              return _buildTrainedProductRow(product);
            },
          ),
        ),
      ],
    );
  }

  /// Строка товара во вкладке "Обученные"
  Widget _buildTrainedProductRow(CigaretteProduct product) {
    final accuracy = product.countingAccuracy;
    final hasAccuracy = accuracy != null;

    // Цвет зависит от точности
    Color accuracyColor;
    String accuracyText;
    if (!hasAccuracy) {
      accuracyColor = Colors.white.withOpacity(0.4);
      accuracyText = '—';
    } else if (accuracy >= 70) {
      accuracyColor = AppColors.success;
      accuracyText = '$accuracy%';
    } else if (accuracy >= 40) {
      accuracyColor = AppColors.warning;
      accuracyText = '$accuracy%';
    } else {
      accuracyColor = AppColors.error;
      accuracyText = '$accuracy%';
    }

    return Container(
      margin: EdgeInsets.only(bottom: 8.h),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(12.r),
        border: Border.all(
          color: hasAccuracy && accuracy < 40
              ? AppColors.error.withOpacity(0.4)
              : Colors.white.withOpacity(0.1),
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _showTrainingSamplesReview(product),
          borderRadius: BorderRadius.circular(12.r),
          child: Padding(
            padding: EdgeInsets.all(12.w),
            child: Row(
              children: [
                // Иконка товара
                Container(
                  width: 40.w,
                  height: 40.w,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(colors: _blueGradient),
                    borderRadius: BorderRadius.circular(10.r),
                  ),
                  child: Icon(Icons.inventory_2, color: Colors.white, size: 20),
                ),
                SizedBox(width: 12),

                // Название + кол-во фото
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        product.productName,
                        style: TextStyle(
                          fontSize: 13.sp,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      SizedBox(height: 4),
                      Text(
                        '${product.countingPhotosCount} фото  •  ${product.countingAttempts} попыток',
                        style: TextStyle(fontSize: 11.sp, color: Colors.white.withOpacity(0.5)),
                      ),
                    ],
                  ),
                ),
                SizedBox(width: 12),

                // Процент точности
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 6.h),
                  decoration: BoxDecoration(
                    color: accuracyColor.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(8.r),
                    border: Border.all(color: accuracyColor.withOpacity(0.4)),
                  ),
                  child: Text(
                    accuracyText,
                    style: TextStyle(
                      fontSize: 14.sp,
                      fontWeight: FontWeight.bold,
                      color: accuracyColor,
                    ),
                  ),
                ),

                SizedBox(width: 8),
                Icon(Icons.chevron_right, color: Colors.white.withOpacity(0.3), size: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Просмотр обучающих фото товара с возможностью удаления неэффективных
  void _showTrainingSamplesReview(CigaretteProduct product) async {
    // Показать индикатор загрузки
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => Center(
        child: CircularProgressIndicator(color: Colors.white),
      ),
    );

    final samples = await CigaretteVisionService.getCountingSamplesForProduct(product.barcode);

    if (!mounted) return;
    Navigator.pop(context); // Закрыть индикатор

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => DraggableScrollableSheet(
          initialChildSize: 0.85,
          minChildSize: 0.5,
          maxChildSize: 0.95,
          expand: false,
          builder: (context, scrollController) => Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [AppColors.darkNavy, AppColors.navy],
              ),
              borderRadius: BorderRadius.vertical(top: Radius.circular(24.r)),
            ),
            child: Column(
              children: [
                // Заголовок
                Padding(
                  padding: EdgeInsets.all(16.w),
                  child: Column(
                    children: [
                      Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.3),
                          borderRadius: BorderRadius.circular(2.r),
                        ),
                      ),
                      SizedBox(height: 16),
                      Row(
                        children: [
                          Container(
                            padding: EdgeInsets.all(10.w),
                            decoration: BoxDecoration(
                              gradient: LinearGradient(colors: _greenGradient),
                              borderRadius: BorderRadius.circular(12.r),
                            ),
                            child: Icon(Icons.model_training, color: Colors.white, size: 24),
                          ),
                          SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Обучающие фото',
                                  style: TextStyle(
                                    fontSize: 18.sp,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                  ),
                                ),
                                Text(
                                  product.productName,
                                  style: TextStyle(
                                    fontSize: 13.sp,
                                    color: Colors.white.withOpacity(0.6),
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                          // Бейдж точности
                          if (product.countingAccuracy != null)
                            Container(
                              padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 4.h),
                              decoration: BoxDecoration(
                                color: (product.countingAccuracy! >= 70
                                        ? AppColors.success
                                        : product.countingAccuracy! >= 40
                                            ? AppColors.warning
                                            : AppColors.error)
                                    .withOpacity(0.2),
                                borderRadius: BorderRadius.circular(8.r),
                              ),
                              child: Text(
                                '${product.countingAccuracy}%',
                                style: TextStyle(
                                  fontSize: 14.sp,
                                  fontWeight: FontWeight.bold,
                                  color: product.countingAccuracy! >= 70
                                      ? AppColors.success
                                      : product.countingAccuracy! >= 40
                                          ? AppColors.warning
                                          : AppColors.error,
                                ),
                              ),
                            ),
                          SizedBox(width: 8),
                          IconButton(
                            onPressed: () => Navigator.pop(context),
                            icon: Icon(Icons.close, color: Colors.white),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                // Контент — сетка фото
                Expanded(
                  child: samples.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.photo_library_outlined,
                                  size: 64, color: Colors.white.withOpacity(0.3)),
                              SizedBox(height: 16),
                              Text(
                                'Нет обучающих фото',
                                style: TextStyle(
                                  color: Colors.white.withOpacity(0.5),
                                  fontSize: 16.sp,
                                ),
                              ),
                            ],
                          ),
                        )
                      : GridView.builder(
                          controller: scrollController,
                          padding: EdgeInsets.symmetric(horizontal: 16.w),
                          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 2,
                            crossAxisSpacing: 12,
                            mainAxisSpacing: 12,
                            childAspectRatio: 0.85,
                          ),
                          itemCount: samples.length,
                          itemBuilder: (context, index) {
                            final sample = samples[index];
                            return _buildCountingPhotoCard(sample, product, setDialogState);
                          },
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Диалог просмотра и управления counting фото (фото с пересчёта)
  void _showCountingSamplesDialog(CigaretteProduct product) async {
    // Показать индикатор загрузки
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => Center(
        child: CircularProgressIndicator(color: Colors.white),
      ),
    );

    // Загрузить counting samples
    final countingSamples = await CigaretteVisionService.getCountingSamplesForProduct(product.barcode);
    final pendingSamples = await CigaretteVisionService.getPendingCountingSamplesForProduct(product.barcode);

    if (!mounted) return;
    Navigator.pop(context); // Закрыть индикатор

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => DraggableScrollableSheet(
          initialChildSize: 0.85,
          minChildSize: 0.5,
          maxChildSize: 0.95,
          expand: false,
          builder: (context, scrollController) => Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [AppColors.darkNavy, AppColors.navy],
              ),
              borderRadius: BorderRadius.vertical(top: Radius.circular(24.r)),
            ),
            child: Column(
              children: [
                // Заголовок
                Padding(
                  padding: EdgeInsets.all(16.w),
                  child: Column(
                    children: [
                      Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.3),
                          borderRadius: BorderRadius.circular(2.r),
                        ),
                      ),
                      SizedBox(height: 16),
                      Row(
                        children: [
                          Container(
                            padding: EdgeInsets.all(10.w),
                            decoration: BoxDecoration(
                              gradient: LinearGradient(colors: _greenGradient),
                              borderRadius: BorderRadius.circular(12.r),
                            ),
                            child: Icon(Icons.calculate, color: Colors.white, size: 24),
                          ),
                          SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Фото пересчёта',
                                  style: TextStyle(
                                    fontSize: 18.sp,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                  ),
                                ),
                                Text(
                                  product.productName,
                                  style: TextStyle(
                                    fontSize: 13.sp,
                                    color: Colors.white.withOpacity(0.6),
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            onPressed: () => Navigator.pop(context),
                            icon: Icon(Icons.close, color: Colors.white),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                // Контент
                Expanded(
                  child: (countingSamples.isEmpty && pendingSamples.isEmpty)
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.photo_library_outlined,
                                  size: 64, color: Colors.white.withOpacity(0.3)),
                              SizedBox(height: 16),
                              Text(
                                'Нет загруженных фото',
                                style: TextStyle(
                                  color: Colors.white.withOpacity(0.5),
                                  fontSize: 16.sp,
                                ),
                              ),
                            ],
                          ),
                        )
                      : ListView(
                          controller: scrollController,
                          padding: EdgeInsets.symmetric(horizontal: 16.w),
                          children: [
                            // Секция "Ожидают подтверждения"
                            if (pendingSamples.isNotEmpty) ...[
                              _buildSectionHeader(
                                icon: Icons.hourglass_empty,
                                title: 'Ожидают подтверждения',
                                count: pendingSamples.length,
                                total: null,
                              ),
                              SizedBox(height: 12),
                              _buildPendingCountingGrid(pendingSamples, setDialogState),
                              SizedBox(height: 24),
                            ],

                            // Секция "Подтверждённые"
                            if (countingSamples.isNotEmpty) ...[
                              _buildSectionHeader(
                                icon: Icons.check_circle,
                                title: 'Подтверждённые',
                                count: countingSamples.length,
                                total: product.requiredCountingPhotos,
                              ),
                              SizedBox(height: 12),
                              _buildCountingPhotosGrid(countingSamples, product, setDialogState),
                              SizedBox(height: 24),
                            ],
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

  /// Сетка pending counting фото с кнопками подтверждения/отклонения
  Widget _buildPendingCountingGrid(List<TrainingSample> samples, StateSetter setDialogState) {
    return GridView.builder(
      shrinkWrap: true,
      physics: NeverScrollableScrollPhysics(),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 0.7,
      ),
      itemCount: samples.length,
      itemBuilder: (context, index) {
        final sample = samples[index];
        return _buildPendingCountingCard(sample, setDialogState);
      },
    );
  }

  Widget _buildPendingCountingCard(TrainingSample sample, StateSetter setDialogState) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(12.r),
        border: Border.all(color: AppColors.amber.withOpacity(0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Изображение
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.vertical(top: Radius.circular(12.r)),
              child: AppCachedImage(
                imageUrl: '${ApiConstants.serverUrl}${sample.imageUrl}',
                fit: BoxFit.cover,
                errorWidget: (context, error, stackTrace) => Container(
                  color: Colors.grey[800],
                  child: Icon(Icons.broken_image, color: Colors.white38, size: 40),
                ),
              ),
            ),
          ),
          // Бейдж "Ожидает"
          Container(
            padding: EdgeInsets.symmetric(vertical: 4.h),
            color: AppColors.amber.withOpacity(0.2),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.hourglass_empty, size: 12, color: AppColors.amber),
                SizedBox(width: 4),
                Text(
                  'Ожидает',
                  style: TextStyle(fontSize: 10.sp, color: AppColors.amber, fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
          // Кнопки
          Padding(
            padding: EdgeInsets.all(8.w),
            child: Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: () async {
                      final success = await CigaretteVisionService.approvePendingCountingSample(sample.id);
                      if (success && mounted) {
                        setDialogState(() {});
                        _loadData(); // Обновить данные
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Фото подтверждено'), backgroundColor: AppColors.success),
                        );
                        Navigator.pop(context); // Закрыть диалог для обновления
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.success,
                      padding: EdgeInsets.symmetric(vertical: 6.h),
                      minimumSize: Size.zero,
                    ),
                    child: Icon(Icons.check, size: 16, color: Colors.white),
                  ),
                ),
                SizedBox(width: 6),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () async {
                      final success = await CigaretteVisionService.rejectPendingCountingSample(sample.id);
                      if (success && mounted) {
                        setDialogState(() {});
                        _loadData();
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Фото отклонено'), backgroundColor: AppColors.warning),
                        );
                        Navigator.pop(context);
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.error,
                      padding: EdgeInsets.symmetric(vertical: 6.h),
                      minimumSize: Size.zero,
                    ),
                    child: Icon(Icons.close, size: 16, color: Colors.white),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Сетка подтверждённых counting фото с возможностью удаления
  Widget _buildCountingPhotosGrid(List<TrainingSample> samples, CigaretteProduct product, StateSetter setDialogState) {
    return GridView.builder(
      shrinkWrap: true,
      physics: NeverScrollableScrollPhysics(),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 0.85,
      ),
      itemCount: samples.length,
      itemBuilder: (context, index) {
        final sample = samples[index];
        return _buildCountingPhotoCard(sample, product, setDialogState);
      },
    );
  }

  Widget _buildCountingPhotoCard(TrainingSample sample, CigaretteProduct product, StateSetter setDialogState) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(12.r),
        border: Border.all(color: _greenGradient[0].withOpacity(0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Изображение
          Expanded(
            child: Stack(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.vertical(top: Radius.circular(12.r)),
                  child: AppCachedImage(
                    imageUrl: '${ApiConstants.serverUrl}${sample.imageUrl}',
                    fit: BoxFit.cover,
                    width: double.infinity,
                    height: double.infinity,
                    errorWidget: (context, error, stackTrace) => Container(
                      color: Colors.grey[800],
                      child: Icon(Icons.broken_image, color: Colors.white38, size: 40),
                    ),
                  ),
                ),
                // Бейдж "Подтверждено"
                Positioned(
                  top: 6.h,
                  left: 6.w,
                  child: Container(
                    padding: EdgeInsets.symmetric(horizontal: 6.w, vertical: 2.h),
                    decoration: BoxDecoration(
                      color: _greenGradient[0].withOpacity(0.9),
                      borderRadius: BorderRadius.circular(4.r),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.check, size: 10, color: Colors.white),
                        SizedBox(width: 2),
                        Text('OK', style: TextStyle(fontSize: 9.sp, color: Colors.white, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
                ),
                // Кнопка удаления
                Positioned(
                  top: 6.h,
                  right: 6.w,
                  child: Material(
                    color: AppColors.error.withOpacity(0.9),
                    borderRadius: BorderRadius.circular(6.r),
                    child: InkWell(
                      onTap: () => _confirmDeleteCountingSample(sample, product, setDialogState),
                      borderRadius: BorderRadius.circular(6.r),
                      child: Padding(
                        padding: EdgeInsets.all(4.w),
                        child: Icon(Icons.delete, size: 16, color: Colors.white),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Информация
          Container(
            padding: EdgeInsets.all(8.w),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  sample.shopAddress ?? 'Неизвестный магазин',
                  style: TextStyle(fontSize: 10.sp, color: Colors.white.withOpacity(0.7)),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                SizedBox(height: 2),
                Text(
                  _formatDate(sample.createdAt),
                  style: TextStyle(fontSize: 9.sp, color: Colors.white.withOpacity(0.5)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Подтверждение удаления counting фото
  void _confirmDeleteCountingSample(TrainingSample sample, CigaretteProduct product, StateSetter setDialogState) {
    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: AppColors.darkNavy,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16.r)),
        title: Row(
          children: [
            Icon(Icons.delete_outline, color: AppColors.error),
            SizedBox(width: 8),
            Text('Удалить фото?', style: TextStyle(color: Colors.white)),
          ],
        ),
        content: Text(
          'Фото будет удалено из обучающего датасета.',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx),
            child: Text('Отмена'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(dialogCtx); // Закрыть диалог подтверждения
              final success = await CigaretteVisionService.deleteCountingSample(sample.id);
              if (success && mounted) {
                setDialogState(() {});
                _loadData();
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Фото удалено'), backgroundColor: AppColors.success),
                );
                Navigator.pop(context); // Закрыть диалог фото для обновления
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
            child: Text('Удалить', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime date) {
    return '${date.day.toString().padLeft(2, '0')}.${date.month.toString().padLeft(2, '0')}.${date.year} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }

  /// Диалог выбора магазина
  void _showShopSelectionDialog() {
    CigaretteShopSelectionDialog.show(
      context: context,
      shops: _shops,
      selectedShopAddress: _selectedShopAddress,
      onShopSelected: (shopAddress) {
        if (mounted) {
          setState(() {
            _selectedShopAddress = shopAddress;
          });
          _loadData();
        }
      },
    );
  }

  /// Диалог детализации по магазинам (для админа)
  void _showShopDetailsDialog(CigaretteProduct product) {
    CigaretteShopDetailsDialog.show(
      context: context,
      product: product,
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
            borderRadius: BorderRadius.circular(12.r),
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
        SizedBox(height: 4),
        Text(
          'ИИ',
          style: TextStyle(
            fontSize: 9.sp,
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
            SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
              ),
            ),
            SizedBox(width: 12),
            Text(newStatus ? 'Включаю ИИ проверку...' : 'Выключаю ИИ проверку...'),
          ],
        ),
        duration: Duration(seconds: 1),
        backgroundColor: AppColors.darkNavy,
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
              SizedBox(width: 12),
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
          duration: Duration(seconds: 2),
        ),
      );

      // Перезагружаем данные
      _loadData();
    } else {
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
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
        borderRadius: BorderRadius.circular(12.r),
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: 20.w, vertical: 12.h),
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: gradient),
            borderRadius: BorderRadius.circular(12.r),
            boxShadow: [
              BoxShadow(
                color: gradient[0].withOpacity(0.4),
                blurRadius: 8,
                offset: Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: Colors.white, size: 20),
              SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
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
        backgroundColor: AppColors.darkNavy,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20.r)),
        child: Container(
          padding: EdgeInsets.all(20.w),
          decoration: BoxDecoration(
            color: AppColors.darkNavy,
            borderRadius: BorderRadius.circular(20.r),
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
                style: TextStyle(
                  fontSize: 16.sp,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              SizedBox(height: 8),
              Text(
                'Выберите тип фото для обучения:',
                style: TextStyle(
                  fontSize: 13.sp,
                  color: Colors.white.withOpacity(0.6),
                ),
              ),
              SizedBox(height: 20),

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
              SizedBox(height: 12),

              // Кнопка: Выкладка (per-shop)
              _buildPhotoTypeOption(
                onTap: () {
                  // Проверяем выбран ли магазин
                  if (!hasShop) {
                    Navigator.pop(context);
                    _showShopSelectionDialog();
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
              SizedBox(height: 16),

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
        borderRadius: BorderRadius.circular(16.r),
        child: Container(
          padding: EdgeInsets.all(16.w),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.05),
            borderRadius: BorderRadius.circular(16.r),
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
                  borderRadius: BorderRadius.circular(12.r),
                ),
                child: Icon(icon, color: Colors.white, size: 24),
              ),
              SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 12.sp,
                        color: Colors.white.withOpacity(0.5),
                      ),
                    ),
                    SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: Container(
                            height: 4,
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(2.r),
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(2.r),
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
                          SizedBox(width: 8),
                          Text(
                            progressLabel,
                            style: TextStyle(
                              fontSize: 11.sp,
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
                    gradient: LinearGradient(colors: _greenGradient),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.check, color: Colors.white, size: 18),
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

    await Navigator.push<bool>(
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

    // Перезагружаем всегда — шаблоны могли быть добавлены
    if (mounted) _loadData();
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
      if (!mounted) return;
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
          backgroundColor: AppColors.error,
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
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                AppColors.darkNavy,
                AppColors.navy,
              ],
            ),
            borderRadius: BorderRadius.vertical(top: Radius.circular(24.r)),
          ),
          child: ListView(
            controller: scrollController,
            padding: EdgeInsets.all(20.w),
            children: [
              // Индикатор
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.3),
                    borderRadius: BorderRadius.circular(2.r),
                  ),
                ),
              ),
              SizedBox(height: 20),

              // Заголовок
              Row(
                children: [
                  Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(colors: progressGradient),
                      borderRadius: BorderRadius.circular(14.r),
                    ),
                    child: Icon(
                      product.isTrainingComplete ? Icons.check_circle : Icons.hourglass_empty,
                      color: Colors.white,
                      size: 28,
                    ),
                  ),
                  SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          product.productName,
                          style: TextStyle(
                            fontSize: 18.sp,
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
              SizedBox(height: 24),

              // Прогресс
              _buildDetailProgressCard(product),
              SizedBox(height: 16),

              // Информация
              _buildDetailInfoCard(product),
              SizedBox(height: 20),

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

              // Кнопка управления фото (только для админа)
              if (_isAdmin && product.trainingPhotosCount > 0) ...[
                SizedBox(height: 12),
                _buildGradientButton(
                  onTap: () {
                    Navigator.pop(context);
                    _showPhotosManagementDialog(product);
                  },
                  gradient: _purpleGradient,
                  icon: Icons.photo_library,
                  label: 'Управление фото (${product.trainingPhotosCount})',
                ),
              ],

              // Кнопка перемещения штрих-кодов (только админ)
              if (_isAdmin) ...[
                SizedBox(height: 12),
                _buildGradientButton(
                  onTap: () {
                    Navigator.pop(context);
                    if (product.barcodes.length == 1) {
                      // Один баркод — сразу к поиску цели
                      _showMoveBarcodesSearch(product, product.barcodes);
                    } else {
                      _showMoveBarcodes(product);
                    }
                  },
                  gradient: _orangeGradient,
                  icon: Icons.swap_horiz,
                  label: product.barcodes.length == 1
                    ? 'Переместить в другую карточку'
                    : 'Переместить штрих-коды (${product.barcodes.length})',
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// Шаг 1: Выбрать штрих-коды для перемещения
  void _showMoveBarcodes(CigaretteProduct product) {
    final selectedBarcodes = <String>{};

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => DraggableScrollableSheet(
          initialChildSize: 0.5,
          minChildSize: 0.3,
          maxChildSize: 0.7,
          expand: false,
          builder: (context, scrollController) => Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [AppColors.darkNavy, AppColors.navy],
              ),
              borderRadius: BorderRadius.vertical(top: Radius.circular(24.r)),
            ),
            child: Column(
              children: [
                Padding(
                  padding: EdgeInsets.all(16.w),
                  child: Column(
                    children: [
                      Container(
                        width: 40, height: 4,
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.3),
                          borderRadius: BorderRadius.circular(2.r),
                        ),
                      ),
                      SizedBox(height: 16),
                      Row(
                        children: [
                          Container(
                            padding: EdgeInsets.all(10.w),
                            decoration: BoxDecoration(
                              gradient: LinearGradient(colors: _orangeGradient),
                              borderRadius: BorderRadius.circular(12.r),
                            ),
                            child: Icon(Icons.swap_horiz, color: Colors.white, size: 24),
                          ),
                          SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Переместить штрих-коды',
                                  style: TextStyle(fontSize: 18.sp, fontWeight: FontWeight.bold, color: Colors.white)),
                                Text(product.productName,
                                  style: TextStyle(fontSize: 13.sp, color: Colors.white.withOpacity(0.6)),
                                  maxLines: 1, overflow: TextOverflow.ellipsis),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView.builder(
                    controller: scrollController,
                    padding: EdgeInsets.symmetric(horizontal: 16.w),
                    itemCount: product.barcodes.length,
                    itemBuilder: (ctx, i) {
                      final barcode = product.barcodes[i];
                      final isSelected = selectedBarcodes.contains(barcode);
                      return Container(
                        margin: EdgeInsets.only(bottom: 8.h),
                        decoration: BoxDecoration(
                          color: isSelected
                            ? _orangeGradient[0].withOpacity(0.15)
                            : Colors.white.withOpacity(0.05),
                          borderRadius: BorderRadius.circular(12.r),
                          border: isSelected
                            ? Border.all(color: _orangeGradient[0], width: 1)
                            : null,
                        ),
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            onTap: () {
                              setDialogState(() {
                                if (isSelected) {
                                  selectedBarcodes.remove(barcode);
                                } else {
                                  selectedBarcodes.add(barcode);
                                }
                              });
                            },
                            borderRadius: BorderRadius.circular(12.r),
                            child: Padding(
                              padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 12.h),
                              child: Row(
                                children: [
                                  Icon(
                                    isSelected ? Icons.check_box : Icons.check_box_outline_blank,
                                    color: isSelected ? _orangeGradient[0] : Colors.white.withOpacity(0.5),
                                  ),
                                  SizedBox(width: 12),
                                  Text(
                                    barcode,
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontFamily: 'monospace',
                                      fontSize: 14.sp,
                                    ),
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
                Padding(
                  padding: EdgeInsets.all(16.w),
                  child: SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: selectedBarcodes.isEmpty ? null : () {
                        Navigator.pop(context);
                        _showMoveBarcodesSearch(product, selectedBarcodes.toList());
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _orangeGradient[0],
                        foregroundColor: Colors.white,
                        disabledBackgroundColor: Colors.white.withOpacity(0.1),
                        padding: EdgeInsets.symmetric(vertical: 14.h),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12.r),
                        ),
                      ),
                      child: Text(
                        selectedBarcodes.isEmpty
                          ? 'Выберите штрих-коды'
                          : 'Далее (${selectedBarcodes.length} выбрано)',
                        style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15.sp),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Шаг 2: Поиск целевой карточки для перемещения
  void _showMoveBarcodesSearch(CigaretteProduct sourceProduct, List<String> barcodes) {
    final searchController = TextEditingController();
    List<AssignSearchProduct> results = [];
    bool isSearching = false;
    bool isMoving = false;
    Timer? debounce;

    showDialog(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (dialogCtx, setDialogState) {
          void onSearchChanged(String query) {
            debounce?.cancel();
            debounce = Timer(const Duration(milliseconds: 300), () async {
              if (query.length < 2) {
                setDialogState(() => results = []);
                return;
              }
              setDialogState(() => isSearching = true);
              final searchResults = await MasterCatalogService.searchForAssign(query);
              searchResults.removeWhere((p) => p.name == sourceProduct.productName);
              if (dialogCtx.mounted) {
                setDialogState(() {
                  results = searchResults;
                  isSearching = false;
                });
              }
            });
          }

          Future<void> onTargetSelected(AssignSearchProduct target) async {
            final confirmed = await showDialog<bool>(
              context: dialogCtx,
              builder: (ctx) => AlertDialog(
                backgroundColor: AppColors.darkNavy,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16.r)),
                title: Text('Подтвердите перемещение', style: TextStyle(color: Colors.white)),
                content: Text(
                  'Переместить ${barcodes.length} шт-код(ов)\nиз "${sourceProduct.productName}"\nв "${target.name}"?'
                  '${barcodes.length >= sourceProduct.barcodes.length ? "\n\nКарточка \"${sourceProduct.productName}\" будет удалена." : ""}',
                  style: TextStyle(color: Colors.white.withOpacity(0.7)),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    child: Text('Отмена', style: TextStyle(color: Colors.white.withOpacity(0.6))),
                  ),
                  ElevatedButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _orangeGradient[0],
                      foregroundColor: Colors.white,
                    ),
                    child: Text('Переместить'),
                  ),
                ],
              ),
            );

            if (confirmed != true) return;

            setDialogState(() => isMoving = true);

            final success = await MasterCatalogService.moveBarcodes(
              barcodes: barcodes,
              targetProductId: target.id,
            );

            if (mounted && dialogCtx.mounted) {
              if (success) {
                Navigator.pop(dialogCtx);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('${barcodes.length} шт-код(ов) перемещено в "${target.name}"'),
                    backgroundColor: _greenGradient[0],
                  ),
                );
                _loadData();
              } else {
                setDialogState(() => isMoving = false);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Ошибка перемещения'), backgroundColor: Colors.red),
                );
              }
            }
          }

          return Dialog(
            backgroundColor: AppColors.darkNavy,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20.r)),
            insetPadding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 40.h),
            child: Container(
              constraints: BoxConstraints(maxHeight: 500),
              padding: EdgeInsets.all(20.w),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(children: [
                    Container(
                      width: 40, height: 40,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(colors: _orangeGradient),
                        borderRadius: BorderRadius.circular(10.r),
                      ),
                      child: Icon(Icons.search, color: Colors.white, size: 22),
                    ),
                    SizedBox(width: 12),
                    Expanded(child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Выберите карточку', style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.w600, color: Colors.white)),
                        Text('${barcodes.length} шт-код(ов) для перемещения', style: TextStyle(fontSize: 11.sp, color: Colors.white.withOpacity(0.5))),
                      ],
                    )),
                    IconButton(
                      icon: Icon(Icons.close, color: Colors.white.withOpacity(0.5)),
                      onPressed: () {
                        debounce?.cancel();
                        searchController.dispose();
                        Navigator.pop(dialogCtx);
                      },
                    ),
                  ]),
                  SizedBox(height: 16),
                  TextField(
                    controller: searchController,
                    autofocus: true,
                    style: TextStyle(color: Colors.white),
                    onChanged: onSearchChanged,
                    decoration: InputDecoration(
                      hintText: 'Введите название товара...',
                      hintStyle: TextStyle(color: Colors.white.withOpacity(0.3)),
                      prefixIcon: Icon(Icons.search, color: Colors.white.withOpacity(0.5)),
                      suffixIcon: isSearching
                        ? Padding(padding: EdgeInsets.all(12.w),
                            child: SizedBox(width: 20, height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)))
                        : searchController.text.isNotEmpty
                          ? IconButton(
                              icon: Icon(Icons.clear, color: Colors.white.withOpacity(0.5)),
                              onPressed: () {
                                searchController.clear();
                                setDialogState(() => results = []);
                              })
                          : null,
                      filled: true,
                      fillColor: Colors.white.withOpacity(0.05),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12.r), borderSide: BorderSide.none),
                      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12.r), borderSide: BorderSide(color: _orangeGradient[0])),
                    ),
                  ),
                  SizedBox(height: 12),
                  Flexible(
                    child: isMoving
                      ? Center(child: CircularProgressIndicator(color: Colors.white))
                      : results.isEmpty
                        ? Center(child: Text(
                            searchController.text.length < 2 ? 'Введите минимум 2 символа' : 'Ничего не найдено',
                            style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 13.sp)))
                        : ListView.builder(
                            itemCount: results.length,
                            itemBuilder: (ctx, i) {
                              final product = results[i];
                              return Container(
                                margin: EdgeInsets.only(bottom: 8.h),
                                decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(0.05),
                                  borderRadius: BorderRadius.circular(12.r),
                                ),
                                child: Material(
                                  color: Colors.transparent,
                                  child: InkWell(
                                    onTap: () => onTargetSelected(product),
                                    borderRadius: BorderRadius.circular(12.r),
                                    child: Padding(
                                      padding: EdgeInsets.all(12.w),
                                      child: Row(children: [
                                        Container(
                                          width: 40, height: 40,
                                          decoration: BoxDecoration(
                                            color: Colors.white.withOpacity(0.1),
                                            borderRadius: BorderRadius.circular(10.r),
                                          ),
                                          clipBehavior: Clip.antiAlias,
                                          child: product.productPhotoUrl != null
                                            ? AppCachedImage(
                                                imageUrl: '${ApiConstants.serverUrl}${product.productPhotoUrl}',
                                                width: 40, height: 40, fit: BoxFit.cover,
                                                errorWidget: (_, __, ___) => Icon(Icons.inventory_2, color: Colors.white54, size: 20))
                                            : Icon(Icons.inventory_2, color: Colors.white54, size: 20),
                                        ),
                                        SizedBox(width: 12),
                                        Expanded(child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(product.name, style: TextStyle(color: Colors.white, fontSize: 13.sp, fontWeight: FontWeight.w500),
                                              maxLines: 2, overflow: TextOverflow.ellipsis),
                                            Row(children: [
                                              if (product.group.isNotEmpty)
                                                Text(product.group, style: TextStyle(fontSize: 11.sp, color: Colors.white.withOpacity(0.5))),
                                              if (product.barcodesCount > 1) ...[
                                                if (product.group.isNotEmpty)
                                                  Text(' \u2022 ', style: TextStyle(color: Colors.white.withOpacity(0.3))),
                                                Text('${product.barcodesCount} шт-кодов', style: TextStyle(fontSize: 11.sp, color: Colors.white.withOpacity(0.5))),
                                              ],
                                            ]),
                                          ],
                                        )),
                                        Icon(Icons.arrow_forward_ios, color: Colors.white.withOpacity(0.3), size: 14),
                                      ]),
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    ).then((_) {
      debounce?.cancel();
    });
  }

  Widget _buildDetailProgressCard(CigaretteProduct product) {
    return Container(
      padding: EdgeInsets.all(20.w),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(16.r),
        border: Border.all(
          color: Colors.white.withOpacity(0.1),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Прогресс обучения',
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: Colors.white,
              fontSize: 16.sp,
            ),
          ),
          SizedBox(height: 16),

          // Крупный план
          _buildDetailProgressRow(
            icon: Icons.crop_free,
            label: 'Крупный план',
            current: product.recountPhotosCount,
            total: product.requiredRecountPhotos,
            progress: product.recountProgress,
            isComplete: product.isRecountComplete,
          ),
          SizedBox(height: 16),

          // Выкладка
          _buildDetailProgressRow(
            icon: Icons.grid_view,
            label: 'Выкладка',
            current: product.displayPhotosCount,
            total: product.requiredDisplayPhotos,
            progress: product.displayProgress,
            isComplete: product.isDisplayComplete,
          ),
          SizedBox(height: 16),

          // Общий статус
          Center(
            child: Container(
              padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 8.h),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: _getProgressGradient(product.trainingProgress),
                ),
                borderRadius: BorderRadius.circular(20.r),
              ),
              child: Text(
                product.isTrainingComplete
                    ? '✅ Обучение завершено!'
                    : 'Всего: ${product.trainingPhotosCount}/${product.requiredPhotosCount} фото',
                style: TextStyle(
                  fontSize: 14.sp,
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
            SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(color: Colors.white.withOpacity(0.8)),
            ),
            Spacer(),
            Text(
              '$current/$total',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: gradient[0],
              ),
            ),
            if (isComplete) ...[
              SizedBox(width: 4),
              Icon(Icons.check_circle, color: _greenGradient[0], size: 18),
            ],
          ],
        ),
        SizedBox(height: 8),
        Container(
          height: 8,
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.1),
            borderRadius: BorderRadius.circular(4.r),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4.r),
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
      padding: EdgeInsets.all(20.w),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(16.r),
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
      padding: EdgeInsets.symmetric(vertical: 6.h),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(color: Colors.white.withOpacity(0.6)),
          ),
          Text(
            value,
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  /// Диалог управления фотографиями товара (только для админа)
  void _showPhotosManagementDialog(CigaretteProduct product) {
    CigarettePhotosManagementDialog.show(
      context: context,
      product: product,
      photosGridBuilder: _buildPhotosGrid,
    );
  }

  Widget _buildSectionHeader({
    required IconData icon,
    required String title,
    required int count,
    int? total,
  }) {
    return Row(
      children: [
        Container(
          padding: EdgeInsets.all(8.w),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8.r),
          ),
          child: Icon(icon, color: Colors.white, size: 18),
        ),
        SizedBox(width: 10),
        Text(
          title,
          style: TextStyle(
            fontSize: 16.sp,
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
        ),
        Spacer(),
        Container(
          padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 4.h),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.1),
            borderRadius: BorderRadius.circular(12.r),
          ),
          child: Text(
            total != null ? '$count/$total' : '$count фото',
            style: TextStyle(
              fontSize: 13.sp,
              color: Colors.white.withOpacity(0.8),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPhotosGrid(List<TrainingSample> samples, CigaretteProduct product, {required bool isRecount}) {
    return GridView.builder(
      shrinkWrap: true,
      physics: NeverScrollableScrollPhysics(),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
        childAspectRatio: 1,
      ),
      itemCount: samples.length,
      itemBuilder: (context, index) {
        final sample = samples[index];
        return _buildPhotoTile(sample, product, isRecount: isRecount);
      },
    );
  }

  Widget _buildPhotoTile(TrainingSample sample, CigaretteProduct product, {required bool isRecount}) {
    final subtitle = isRecount
        ? 'Шаблон ${sample.templateId ?? "?"}'
        : sample.shopAddress ?? 'Без магазина';

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12.r),
        border: Border.all(color: Colors.white.withOpacity(0.2)),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(11.r),
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Фото (тап → превью)
            GestureDetector(
              onTap: () => _showPhotoPreview(sample, product),
              child: AppCachedImage(
                imageUrl: '${ApiConstants.serverUrl}${sample.imageUrl}',
                fit: BoxFit.cover,
                errorWidget: (_, __, ___) => Container(
                  color: Colors.grey[800],
                  child: Icon(Icons.broken_image, color: Colors.grey),
                ),
              ),
            ),

            // Градиент снизу
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: IgnorePointer(
                child: Container(
                  padding: EdgeInsets.all(6.w),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.transparent,
                        Colors.black.withOpacity(0.8),
                      ],
                    ),
                  ),
                  child: Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 10.sp,
                      color: Colors.white,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            ),

            // Кнопка удаления
            if (_isAdmin)
              Positioned(
                top: 4.h,
                right: 4.w,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => _confirmDeletePhoto(sample, product),
                  child: Container(
                    padding: EdgeInsets.all(6.w),
                    decoration: BoxDecoration(
                      color: AppColors.error.withOpacity(0.9),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.close,
                      color: Colors.white,
                      size: 14,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// Показать превью фото в полном размере
  void _showPhotoPreview(TrainingSample sample, CigaretteProduct product) {
    final isRecount = sample.type == TrainingSampleType.recount;
    final subtitle = isRecount
        ? 'Шаблон ${sample.templateId ?? "?"}'
        : sample.shopAddress ?? 'Без магазина';

    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Заголовок
            Container(
              width: double.infinity,
              padding: EdgeInsets.all(16.w),
              decoration: BoxDecoration(
                color: AppColors.darkNavy,
                borderRadius: BorderRadius.vertical(top: Radius.circular(16.r)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        isRecount ? Icons.crop_free : Icons.grid_view,
                        color: Colors.white,
                        size: 20,
                      ),
                      SizedBox(width: 8),
                      Text(
                        isRecount ? 'Крупный план' : 'Выкладка',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 16.sp,
                        ),
                      ),
                      Spacer(),
                      IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon: Icon(Icons.close, color: Colors.white),
                        padding: EdgeInsets.zero,
                        constraints: BoxConstraints(),
                      ),
                    ],
                  ),
                  SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.6),
                      fontSize: 13.sp,
                    ),
                  ),
                ],
              ),
            ),

            // Фото
            Container(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.5,
              ),
              child: AppCachedImage(
                imageUrl: '${ApiConstants.serverUrl}${sample.imageUrl}',
                fit: BoxFit.contain,
                errorWidget: (_, __, ___) => Container(
                  height: 200,
                  color: Colors.grey[800],
                  child: Center(
                    child: Icon(Icons.broken_image, color: Colors.grey, size: 48),
                  ),
                ),
              ),
            ),

            // Кнопка удаления
            Container(
              width: double.infinity,
              padding: EdgeInsets.all(16.w),
              decoration: BoxDecoration(
                color: AppColors.darkNavy,
                borderRadius: BorderRadius.vertical(bottom: Radius.circular(16.r)),
              ),
              child: ElevatedButton.icon(
                onPressed: () {
                  Navigator.pop(context);
                  _confirmDeletePhoto(sample, product);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.error,
                  foregroundColor: Colors.white,
                  padding: EdgeInsets.symmetric(vertical: 12.h),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12.r),
                  ),
                ),
                icon: Icon(Icons.delete),
                label: Text('Удалить фото'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Подтверждение удаления фото
  void _confirmDeletePhoto(TrainingSample sample, CigaretteProduct product) {
    final isRecount = sample.type == TrainingSampleType.recount;
    final typeLabel = isRecount ? 'крупного плана' : 'выкладки';
    final positionLabel = isRecount
        ? 'Шаблон ${sample.templateId ?? "?"}'
        : sample.shopAddress ?? 'Без магазина';

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.darkNavy,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16.r)),
        title: Row(
          children: [
            Container(
              padding: EdgeInsets.all(8.w),
              decoration: BoxDecoration(
                color: AppColors.error.withOpacity(0.2),
                borderRadius: BorderRadius.circular(8.r),
              ),
              child: Icon(Icons.warning, color: AppColors.error, size: 24),
            ),
            SizedBox(width: 12),
            Text(
              'Удалить фото?',
              style: TextStyle(color: Colors.white, fontSize: 18.sp),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Вы собираетесь удалить фото $typeLabel:',
              style: TextStyle(color: Colors.white.withOpacity(0.8)),
            ),
            SizedBox(height: 8),
            Container(
              padding: EdgeInsets.all(12.w),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.05),
                borderRadius: BorderRadius.circular(8.r),
              ),
              child: Row(
                children: [
                  Icon(
                    isRecount ? Icons.crop_free : Icons.store,
                    color: Colors.white.withOpacity(0.6),
                    size: 20,
                  ),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      positionLabel,
                      style: TextStyle(color: Colors.white),
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(height: 12),
            Text(
              'Прогресс обучения будет пересчитан.',
              style: TextStyle(
                color: AppColors.warning.withOpacity(0.8),
                fontSize: 13.sp,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              'Отмена',
              style: TextStyle(color: Colors.white.withOpacity(0.6)),
            ),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _deletePhoto(sample, product);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
              foregroundColor: Colors.white,
            ),
            child: Text('Удалить'),
          ),
        ],
      ),
    );
  }

  /// Удалить фото и обновить данные
  Future<void> _deletePhoto(TrainingSample sample, CigaretteProduct product) async {
    // Закрыть photos management bottom sheet
    if (mounted) Navigator.of(context).pop();

    // Показать индикатор загрузки на основной странице
    if (mounted) setState(() => _isLoading = true);

    try {
      debugPrint('[DELETE] === START === sample=${sample.id} product=${product.id}');
      final success = await CigaretteVisionService.deleteSample(sample.id);
      debugPrint('[DELETE] === RESULT === success=$success mounted=$mounted');

      if (!mounted) return;

      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Фото удалено'),
            backgroundColor: AppColors.success,
            behavior: SnackBarBehavior.floating,
          ),
        );

        await _loadData();
        debugPrint('[DELETE] Data reloaded, products: ${_products.length}');

        if (!mounted) return;
        final updatedProduct = _products.firstWhere(
          (p) => p.id == product.id,
          orElse: () => product,
        );
        debugPrint('[DELETE] Updated photos: ${updatedProduct.trainingPhotosCount}');
        _showPhotosManagementDialog(updatedProduct);
      } else {
        if (!mounted) return;
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Сервер вернул ошибку при удалении'),
            backgroundColor: AppColors.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      debugPrint('[DELETE] === ERROR === $e');
      if (!mounted) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Ошибка сети: $e'),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }
}

/// Виджет: фото с наложенными bounding boxes для просмотра pending образцов.
/// [fit] — BoxFit.cover для превью в карточке, BoxFit.contain для полноэкранного просмотра.
class _PendingImageWithBoxes extends StatefulWidget {
  final String imageUrl;
  final List<AnnotationBox> boundingBoxes;
  final BoxFit fit;

  const _PendingImageWithBoxes({
    required this.imageUrl,
    required this.boundingBoxes,
    this.fit = BoxFit.contain,
  });

  @override
  State<_PendingImageWithBoxes> createState() => _PendingImageWithBoxesState();
}

class _PendingImageWithBoxesState extends State<_PendingImageWithBoxes> {
  ui.Image? _image;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadImage();
  }

  Future<void> _loadImage() async {
    try {
      final response = await http.get(
        Uri.parse(widget.imageUrl),
        headers: ApiConstants.jsonHeaders,
      ).timeout(ApiConstants.longTimeout);

      if (response.statusCode == 200) {
        final codec = await ui.instantiateImageCodec(response.bodyBytes);
        final frame = await codec.getNextFrame();
        if (mounted) {
          setState(() {
            _image = frame.image;
            _loading = false;
          });
        }
      } else {
        if (mounted) {
          setState(() {
            _error = 'HTTP ${response.statusCode}';
            _loading = false;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = '$e';
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Center(child: CircularProgressIndicator(color: Colors.orange));
    }
    if (_error != null || _image == null) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.broken_image, color: Colors.white38, size: 32),
          SizedBox(height: 4),
          Text(_error ?? 'Ошибка', style: TextStyle(color: Colors.white38, fontSize: 10)),
        ]),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        return SizedBox(
          width: constraints.maxWidth,
          height: constraints.maxHeight,
          child: CustomPaint(
            painter: _BoundingBoxOverlayPainter(
              image: _image!,
              boxes: widget.boundingBoxes,
              fit: widget.fit,
            ),
          ),
        );
      },
    );
  }
}

/// Painter: рисует фото + зелёные рамки bounding boxes.
/// Поддерживает BoxFit.cover (для превью) и BoxFit.contain (для полноэкрана).
class _BoundingBoxOverlayPainter extends CustomPainter {
  final ui.Image image;
  final List<AnnotationBox> boxes;
  final BoxFit fit;

  _BoundingBoxOverlayPainter({
    required this.image,
    required this.boxes,
    this.fit = BoxFit.contain,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final imgW = image.width.toDouble();
    final imgH = image.height.toDouble();
    final srcRect = Rect.fromLTWH(0, 0, imgW, imgH);

    // Вычисляем dstRect с учётом BoxFit
    final FittedSizes fittedSizes = applyBoxFit(fit, Size(imgW, imgH), size);
    final Rect dstRect = Alignment.center.inscribe(fittedSizes.destination, Offset.zero & size);

    // Для BoxFit.cover обрезаем то, что выходит за пределы канваса
    if (fit == BoxFit.cover) {
      canvas.save();
      canvas.clipRect(Offset.zero & size);
    }

    // srcRect при cover тоже нужен только видимая часть
    final Rect actualSrc = Alignment.center.inscribe(fittedSizes.source, srcRect);
    canvas.drawImageRect(image, actualSrc, dstRect, Paint());

    if (boxes.isNotEmpty) {
      final borderPaint = Paint()
        ..color = Colors.green
        ..style = PaintingStyle.stroke
        ..strokeWidth = fit == BoxFit.cover ? 1.5 : 2.5;

      final fillPaint = Paint()
        ..color = Colors.green.withOpacity(0.15)
        ..style = PaintingStyle.fill;

      // Масштабирование: нормализованные координаты → координаты на исходном изображении → на dstRect
      // При cover видна только часть изображения (actualSrc), нужно учесть смещение
      for (int i = 0; i < boxes.length; i++) {
        final box = boxes[i];
        // Координаты в пикселях исходного изображения
        final pixLeft = (box.xCenter - box.width / 2) * imgW;
        final pixTop = (box.yCenter - box.height / 2) * imgH;
        final pixRight = (box.xCenter + box.width / 2) * imgW;
        final pixBottom = (box.yCenter + box.height / 2) * imgH;

        // Переводим из координат исходного изображения в координаты канваса
        final scaleX = dstRect.width / actualSrc.width;
        final scaleY = dstRect.height / actualSrc.height;

        final drawLeft = dstRect.left + (pixLeft - actualSrc.left) * scaleX;
        final drawTop = dstRect.top + (pixTop - actualSrc.top) * scaleY;
        final drawRight = dstRect.left + (pixRight - actualSrc.left) * scaleX;
        final drawBottom = dstRect.top + (pixBottom - actualSrc.top) * scaleY;

        final rect = Rect.fromLTRB(drawLeft, drawTop, drawRight, drawBottom);

        canvas.drawRect(rect, fillPaint);
        canvas.drawRect(rect, borderPaint);

        // Номер рамки (только если рамка достаточно большая)
        if (rect.width > 16 && rect.height > 16) {
          final textPainter = TextPainter(
            text: TextSpan(
              text: '${i + 1}',
              style: TextStyle(
                color: Colors.white,
                fontSize: fit == BoxFit.cover ? 9 : 13,
                fontWeight: FontWeight.bold,
                backgroundColor: Colors.green,
              ),
            ),
            textDirection: TextDirection.ltr,
          );
          textPainter.layout();
          textPainter.paint(canvas, Offset(rect.left + 2, rect.top + 2));
        }
      }
    }

    if (fit == BoxFit.cover) {
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _BoundingBoxOverlayPainter old) =>
      old.image != image || old.boxes != boxes || old.fit != fit;
}
