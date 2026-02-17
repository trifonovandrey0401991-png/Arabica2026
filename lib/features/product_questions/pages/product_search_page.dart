import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../../../core/constants/api_constants.dart';
import '../../../core/utils/logger.dart';
import '../../../core/widgets/shop_icon.dart';
import '../../../shared/widgets/app_cached_image.dart';
import '../../shops/models/shop_model.dart';
import '../../shops/services/shop_products_service.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../../core/theme/app_colors.dart';

/// Режимы отображения страницы
enum _SearchMode {
  shopsList, // Список магазинов + кнопка "Искать везде"
  search, // Поле поиска + результаты
}

/// Страница поиска товара с выбором магазина
class ProductSearchPage extends StatefulWidget {
  const ProductSearchPage({super.key});

  @override
  State<ProductSearchPage> createState() => _ProductSearchPageState();
}

class _ProductSearchPageState extends State<ProductSearchPage> {
  /// Таймаут для определения устаревших данных (5 минут)
  static final Duration _staleDataTimeout = Duration(minutes: 5);

  // Состояние
  _SearchMode _mode = _SearchMode.shopsList;
  bool _isLoading = true;
  bool _isSearching = false;

  // Данные магазинов
  List<Shop> _shops = [];
  Map<String, ShopSyncInfo> _shopsSyncInfo = {};
  Map<String, String> _productPhotos = {};

  // Поиск
  String? _selectedShopId;
  String? _selectedShopName;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  List<ShopProduct> _searchResults = [];
  Timer? _debounceTimer;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _debounceTimer?.cancel();
    super.dispose();
  }

  /// Загрузить магазины и информацию о синхронизации
  Future<void> _loadData() async {
    setState(() => _isLoading = true);

    try {
      // Загружаем параллельно
      final results = await Future.wait([
        Shop.loadShopsFromServer(),
        ShopProductsService.getShopsWithProducts(),
        _loadProductPhotos(),
      ]);

      final shops = results[0] as List<Shop>;
      final syncInfoList = results[1] as List<ShopSyncInfo>;
      final photos = results[2] as Map<String, String>;

      setState(() {
        _shops = shops;
        _shopsSyncInfo = {for (var s in syncInfoList) s.shopId: s};
        _productPhotos = photos;
        _isLoading = false;
      });

      Logger.debug('📦 Загружено ${shops.length} магазинов, ${syncInfoList.length} с DBF, ${photos.length} фото');
    } catch (e) {
      Logger.error('Ошибка загрузки данных', e);
      setState(() => _isLoading = false);
    }
  }

  /// Проверить, есть ли у магазина синхронизированные данные DBF
  bool _hasDbfData(String shopId) {
    return _shopsSyncInfo.containsKey(shopId);
  }

  /// Проверить, устарели ли данные DBF (более 5 минут с последней синхронизации)
  bool _isDbfDataStale(String shopId) {
    final syncInfo = _shopsSyncInfo[shopId];
    if (syncInfo == null || syncInfo.lastSync == null) {
      return true;
    }
    final now = DateTime.now();
    final timeSinceSync = now.difference(syncInfo.lastSync!);
    return timeSinceSync > _staleDataTimeout;
  }

  /// Получить время с последней синхронизации в читаемом формате
  String _getTimeSinceSync(String shopId) {
    final syncInfo = _shopsSyncInfo[shopId];
    if (syncInfo == null || syncInfo.lastSync == null) {
      return 'нет данных';
    }
    final now = DateTime.now();
    final diff = now.difference(syncInfo.lastSync!);

    if (diff.inDays > 0) {
      return '${diff.inDays} дн. назад';
    } else if (diff.inHours > 0) {
      return '${diff.inHours} ч. назад';
    } else if (diff.inMinutes > 0) {
      return '${diff.inMinutes} мин. назад';
    } else {
      return 'только что';
    }
  }

  /// Переключить в режим поиска
  void _startSearch({String? shopId, String? shopName}) {
    setState(() {
      _mode = _SearchMode.search;
      _selectedShopId = shopId;
      _selectedShopName = shopName;
      _searchQuery = '';
      _searchResults = [];
      _searchController.clear();
    });
  }

  /// Вернуться к списку магазинов
  void _backToShopsList() {
    setState(() {
      _mode = _SearchMode.shopsList;
      _selectedShopId = null;
      _selectedShopName = null;
      _searchQuery = '';
      _searchResults = [];
      _searchController.clear();
    });
  }

  /// Выполнить поиск с debounce
  void _onSearchChanged(String query) {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(Duration(milliseconds: 300), () {
      _performSearch(query);
    });
  }

  /// Выполнить поиск
  Future<void> _performSearch(String query) async {
    if (query.length < 2) {
      setState(() {
        _searchQuery = query;
        _searchResults = [];
      });
      return;
    }

    setState(() {
      _searchQuery = query;
      _isSearching = true;
    });

    try {
      // Загружаем результаты с сервера
      final results = await ShopProductsService.searchProducts(
        query,
        shopId: _selectedShopId,
      );

      // Применяем fuzzy-фильтрацию и сортировку по релевантности
      final scored = results.map((product) {
        final relevance = _calculateSearchRelevance(product.name, query);
        return MapEntry(product, relevance);
      }).where((entry) => entry.value > 0.3).toList();

      // Сортируем по релевантности
      scored.sort((a, b) => b.value.compareTo(a.value));

      setState(() {
        _searchResults = scored.map((e) => e.key).toList();
        _isSearching = false;
      });
    } catch (e) {
      Logger.error('Ошибка поиска', e);
      setState(() => _isSearching = false);
    }
  }

  /// Вычисляет релевантность товара для поискового запроса
  /// Возвращает значение от 0.0 (нет совпадения) до 1.0 (точное совпадение)
  double _calculateSearchRelevance(String productName, String query) {
    if (query.isEmpty) return 1.0;

    final nameLower = productName.toLowerCase();
    final queryLower = query.toLowerCase();

    // 1. Точное совпадение слова - максимальный приоритет
    if (nameLower == queryLower) return 1.0;

    // 2. Начинается с запроса
    if (nameLower.startsWith(queryLower)) return 0.95;

    // 3. Содержит точный запрос
    if (nameLower.contains(queryLower)) return 0.9;

    // 4. Разбиваем запрос на слова и проверяем каждое
    final queryWords = queryLower.split(RegExp(r'\s+'));
    final nameWords = nameLower.split(RegExp(r'[\s\(\)\-\+/]+'));

    double totalScore = 0.0;
    int matchedWords = 0;

    for (final queryWord in queryWords) {
      if (queryWord.length < 2) continue;

      double bestWordScore = 0.0;

      for (final nameWord in nameWords) {
        if (nameWord.isEmpty) continue;

        // Точное совпадение слова
        if (nameWord == queryWord) {
          bestWordScore = 1.0;
          break;
        }

        // Слово начинается с запроса
        if (nameWord.startsWith(queryWord)) {
          bestWordScore = 0.9 > bestWordScore ? 0.9 : bestWordScore;
          continue;
        }

        // Слово содержит запрос
        if (nameWord.contains(queryWord)) {
          bestWordScore = 0.8 > bestWordScore ? 0.8 : bestWordScore;
          continue;
        }

        // Запрос содержит слово (частичное совпадение)
        if (queryWord.contains(nameWord) && nameWord.length >= 3) {
          bestWordScore = 0.7 > bestWordScore ? 0.7 : bestWordScore;
          continue;
        }

        // Fuzzy match - проверяем похожесть (для опечаток)
        final similarity = _stringSimilarity(nameWord, queryWord);
        if (similarity > 0.6) {
          final fuzzyScore = 0.5 + (similarity - 0.6) * 0.5;
          bestWordScore = fuzzyScore > bestWordScore ? fuzzyScore : bestWordScore;
        }
      }

      if (bestWordScore > 0) {
        totalScore += bestWordScore;
        matchedWords++;
      }
    }

    if (matchedWords == 0) return 0.0;

    final avgScore = totalScore / queryWords.length;
    final coverageBonus = matchedWords / queryWords.length;

    return avgScore * 0.7 + coverageBonus * 0.3;
  }

  /// Вычисляет похожесть двух строк (0.0 - 1.0)
  double _stringSimilarity(String s1, String s2) {
    if (s1.isEmpty || s2.isEmpty) return 0.0;
    if (s1 == s2) return 1.0;

    // Для коротких строк используем посимвольное сравнение
    if (s1.length <= 3 || s2.length <= 3) {
      int matches = 0;
      final shorter = s1.length < s2.length ? s1 : s2;
      final longer = s1.length >= s2.length ? s1 : s2;

      for (int i = 0; i < shorter.length; i++) {
        if (longer.contains(shorter[i])) matches++;
      }
      return matches / longer.length;
    }

    // Биграммы для более длинных строк
    final bigrams1 = _getBigrams(s1);
    final bigrams2 = _getBigrams(s2);

    if (bigrams1.isEmpty || bigrams2.isEmpty) return 0.0;

    int matches = 0;
    for (final bigram in bigrams1) {
      if (bigrams2.contains(bigram)) matches++;
    }

    return (2.0 * matches) / (bigrams1.length + bigrams2.length);
  }

  /// Получает биграммы (пары символов) из строки
  Set<String> _getBigrams(String s) {
    final bigrams = <String>{};
    for (int i = 0; i < s.length - 1; i++) {
      bigrams.add(s.substring(i, i + 2));
    }
    return bigrams;
  }

  /// Загрузить фото товаров из обучения ИИ
  static Future<Map<String, String>> _loadProductPhotos() async {
    try {
      final response = await http.get(
        Uri.parse('${ApiConstants.serverUrl}/api/master-catalog/product-photos'),
        headers: ApiConstants.jsonHeaders,
      ).timeout(ApiConstants.defaultTimeout);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true && data['photos'] != null) {
          return Map<String, String>.from(data['photos']);
        }
      }
    } catch (e) {
      Logger.error('Ошибка загрузки фото товаров', e);
    }
    return {};
  }

  /// Получить URL фото товара по коду
  String? _getProductPhotoUrl(String kod) {
    final url = _productPhotos[kod];
    if (url == null || url.isEmpty) return null;
    if (url.startsWith('http')) return url;
    return '${ApiConstants.serverUrl}$url';
  }

  /// Получить название магазина по ID
  String _getShopName(String shopId) {
    if (shopId.isEmpty) return 'Неизвестный магазин';
    final shop = _shops.firstWhere(
      (s) => s.id == shopId,
      orElse: () => Shop(id: shopId, name: shopId, address: shopId),
    );
    return shop.address;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: Text(_mode == _SearchMode.shopsList ? 'Поиск товара' : _getSearchTitle()),
        backgroundColor: AppColors.primaryGreen,
        elevation: 0,
        leading: _mode == _SearchMode.search
            ? IconButton(
                icon: Icon(Icons.arrow_back),
                onPressed: _backToShopsList,
              )
            : null,
      ),
      body: _isLoading
          ? Center(child: CircularProgressIndicator())
          : _mode == _SearchMode.shopsList
              ? _buildShopsListMode()
              : _buildSearchMode(),
    );
  }

  /// Заголовок для режима поиска
  String _getSearchTitle() {
    if (_selectedShopId == null) {
      return 'Поиск везде';
    }
    return _selectedShopName ?? 'Поиск';
  }

  /// Режим списка магазинов
  Widget _buildShopsListMode() {
    return Column(
      children: [
        // Кнопка "Искать везде"
        Padding(
          padding: EdgeInsets.all(16.w),
          child: InkWell(
            onTap: () => _startSearch(),
            borderRadius: BorderRadius.circular(16.r),
            child: Container(
              width: double.infinity,
              padding: EdgeInsets.symmetric(vertical: 16.h),
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: [AppColors.info, const Color(0xFF21CBF3)]),
                borderRadius: BorderRadius.circular(16.r),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.info.withOpacity(0.4),
                    blurRadius: 8,
                    offset: Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.search, color: Colors.white, size: 28),
                  SizedBox(width: 12),
                  Text(
                    'Искать везде',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18.sp,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),

        // Заголовок списка магазинов
        Padding(
          padding: EdgeInsets.symmetric(horizontal: 16.w),
          child: Row(
            children: [
              Text(
                'Или выберите магазин:',
                style: TextStyle(
                  fontSize: 14.sp,
                  color: Colors.grey[600],
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
        SizedBox(height: 8),

        // Список магазинов
        Expanded(
          child: ListView.builder(
            padding: EdgeInsets.symmetric(horizontal: 16.w),
            itemCount: _shops.length,
            itemBuilder: (context, index) {
              final shop = _shops[index];
              return _buildShopCard(shop);
            },
          ),
        ),
      ],
    );
  }

  /// Карточка магазина
  Widget _buildShopCard(Shop shop) {
    final hasDbf = _hasDbfData(shop.id);
    final isStale = hasDbf && _isDbfDataStale(shop.id);

    return Card(
      margin: EdgeInsets.only(bottom: 8.h),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12.r),
        side: hasDbf
            ? BorderSide(color: isStale ? Colors.red : Colors.green, width: 2)
            : BorderSide.none,
      ),
      child: InkWell(
        onTap: () => _startSearch(shopId: shop.id, shopName: shop.address),
        borderRadius: BorderRadius.circular(12.r),
        child: Padding(
          padding: EdgeInsets.all(12.w),
          child: Row(
            children: [
              ShopIcon(size: 48),
              SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      shop.address,
                      style: TextStyle(
                        fontSize: 15.sp,
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (hasDbf) ...[
                      SizedBox(height: 4),
                      Container(
                        padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 2.h),
                        decoration: BoxDecoration(
                          color: isStale ? Colors.red : Colors.green,
                          borderRadius: BorderRadius.circular(8.r),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              isStale ? Icons.warning : Icons.inventory_2,
                              color: Colors.white,
                              size: 12,
                            ),
                            SizedBox(width: 4),
                            Text(
                              isStale ? 'DBF: ${_getTimeSinceSync(shop.id)}' : 'Остатки из DBF',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 11.sp,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: Colors.grey),
            ],
          ),
        ),
      ),
    );
  }

  /// Режим поиска
  Widget _buildSearchMode() {
    return Column(
      children: [
        // Поле поиска
        Container(
          color: Colors.white,
          padding: EdgeInsets.all(16.w),
          child: TextField(
            controller: _searchController,
            autofocus: true,
            decoration: InputDecoration(
              hintText: 'Поиск (поддерживает опечатки)...',
              prefixIcon: Icon(Icons.search),
              suffixIcon: _searchQuery.isNotEmpty
                  ? IconButton(
                      icon: Icon(Icons.clear),
                      onPressed: () {
                        _searchController.clear();
                        _performSearch('');
                      },
                    )
                  : null,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12.r),
                borderSide: BorderSide(color: Colors.grey[300]!),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12.r),
                borderSide: BorderSide(color: AppColors.primaryGreen, width: 2),
              ),
              filled: true,
              fillColor: Colors.grey[50],
            ),
            onChanged: _onSearchChanged,
          ),
        ),

        // Информация о поиске
        if (_searchQuery.length >= 2)
          Container(
            color: Colors.white,
            padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 8.h),
            child: Row(
              children: [
                Text(
                  'Найдено: ${_searchResults.length}',
                  style: TextStyle(
                    color: Colors.grey[600],
                    fontSize: 13.sp,
                  ),
                ),
                if (_selectedShopId != null) ...[
                  Text(
                    ' в магазине',
                    style: TextStyle(color: Colors.grey[600], fontSize: 13.sp),
                  ),
                ] else ...[
                  Text(
                    ' по всем магазинам',
                    style: TextStyle(color: Colors.grey[600], fontSize: 13.sp),
                  ),
                ],
              ],
            ),
          ),

        // Результаты поиска
        Expanded(
          child: _isSearching
              ? Center(child: CircularProgressIndicator())
              : _searchQuery.length < 2
                  ? _buildSearchHint()
                  : _searchResults.isEmpty
                      ? _buildNoResults()
                      : _buildSearchResults(),
        ),
      ],
    );
  }

  /// Подсказка для начала поиска
  Widget _buildSearchHint() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.search, size: 64, color: Colors.grey[400]),
          SizedBox(height: 16),
          Text(
            'Введите минимум 2 символа',
            style: TextStyle(fontSize: 16.sp, color: Colors.grey[600]),
          ),
        ],
      ),
    );
  }

  /// Сообщение об отсутствии результатов
  Widget _buildNoResults() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.search_off, size: 64, color: Colors.grey[400]),
          SizedBox(height: 16),
          Text(
            'Ничего не найдено',
            style: TextStyle(fontSize: 16.sp, color: Colors.grey[600]),
          ),
          SizedBox(height: 8),
          Text(
            'Попробуйте изменить запрос',
            style: TextStyle(fontSize: 14.sp, color: Colors.grey[500]),
          ),
        ],
      ),
    );
  }

  /// Список результатов поиска
  Widget _buildSearchResults() {
    return ListView.builder(
      padding: EdgeInsets.all(16.w),
      itemCount: _searchResults.length,
      itemBuilder: (context, index) {
        final product = _searchResults[index];
        return _buildProductCard(product);
      },
    );
  }

  /// Карточка товара
  Widget _buildProductCard(ShopProduct product) {
    final shopName = _getShopName(product.shopId);
    final photoUrl = _getProductPhotoUrl(product.kod);

    return Card(
      margin: EdgeInsets.only(bottom: 8.h),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.r)),
      child: Padding(
        padding: EdgeInsets.all(12.w),
        child: Row(
          children: [
            // Фото или иконка товара
            ClipRRect(
              borderRadius: BorderRadius.circular(8.r),
              child: SizedBox(
                width: 48,
                height: 48,
                child: photoUrl != null
                    ? AppCachedImage(
                        imageUrl: photoUrl,
                        fit: BoxFit.cover,
                        errorWidget: (context, error, stackTrace) => Container(
                          color: Colors.grey[200],
                          child: Icon(Icons.inventory_2, color: Colors.grey[600]),
                        ),
                      )
                    : Container(
                        color: Colors.grey[200],
                        child: Icon(Icons.inventory_2, color: Colors.grey[600]),
                      ),
              ),
            ),
            SizedBox(width: 12),
            // Информация о товаре
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    product.name,
                    style: TextStyle(
                      fontSize: 15.sp,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(Icons.store, size: 14, color: Colors.grey[600]),
                      SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          shopName,
                          style: TextStyle(fontSize: 13.sp, color: Colors.grey[600]),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            // Количество
            Container(
              padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 6.h),
              decoration: BoxDecoration(
                color: product.stock > 0 ? Colors.green[100] : Colors.red[100],
                borderRadius: BorderRadius.circular(8.r),
              ),
              child: Text(
                '${product.stock} шт.',
                style: TextStyle(
                  fontSize: 14.sp,
                  fontWeight: FontWeight.bold,
                  color: product.stock > 0 ? Colors.green[700] : Colors.red[700],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
