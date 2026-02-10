import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import '../../../core/constants/api_constants.dart';
import '../../../core/utils/logger.dart';
import '../../../core/widgets/shop_icon.dart';
import '../../employees/services/user_role_service.dart';
import '../../employees/models/user_role_model.dart';
import '../models/shop_model.dart';
import '../services/shop_service.dart';

/// Страница списка магазинов с возможностью построения маршрута
class ShopsOnMapPage extends StatefulWidget {
  const ShopsOnMapPage({super.key});

  @override
  State<ShopsOnMapPage> createState() => _ShopsOnMapPageState();
}

class _ShopsOnMapPageState extends State<ShopsOnMapPage> with TickerProviderStateMixin {
  List<Shop> _shops = [];
  bool _isLoading = true;
  String? _error;
  Position? _currentPosition;
  bool _isLoadingLocation = false;
  late AnimationController _animationController;

  // TabBar для админа
  TabController? _tabController;
  UserRole? _userRole;
  bool _isLoadingRole = true;

  // Настройки геозоны
  bool _geofenceEnabled = true;
  final _radiusController = TextEditingController(text: '500');
  final _titleController = TextEditingController(text: 'Arabica рядом!');
  final _bodyController = TextEditingController(text: 'Вы рядом с нашей кофейней. Заходите за ароматным кофе!');
  int _cooldownHours = 24;
  bool _isSavingSettings = false;
  bool _isLoadingSettings = false;

  static const _emerald = Color(0xFF1A4D4D);
  static const _emeraldDark = Color(0xFF0D2E2E);
  static const _night = Color(0xFF051515);
  static const _gold = Color(0xFFD4AF37);

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _loadUserRole();
    _loadData();
  }

  @override
  void dispose() {
    _animationController.dispose();
    _tabController?.dispose();
    _radiusController.dispose();
    _titleController.dispose();
    _bodyController.dispose();
    super.dispose();
  }

  Future<void> _loadUserRole() async {
    try {
      final roleData = await UserRoleService.loadUserRole();
      if (mounted) {
        setState(() {
          _userRole = roleData?.role;
          _isLoadingRole = false;

          // TabController: 2 вкладки для админа/разработчика, 1 для остальных
          if (_userRole == UserRole.admin || _userRole == UserRole.developer) {
            _tabController = TabController(length: 2, vsync: this);
            _loadGeofenceSettings();
          } else {
            _tabController = TabController(length: 1, vsync: this);
          }
        });
      }
    } catch (e) {
      Logger.error('Ошибка загрузки роли', e);
      if (mounted) {
        setState(() {
          _isLoadingRole = false;
          _tabController = TabController(length: 1, vsync: this);
        });
      }
    }
  }

  Future<void> _loadGeofenceSettings() async {
    setState(() => _isLoadingSettings = true);
    try {
      final response = await http.get(
        Uri.parse('${ApiConstants.serverUrl}/api/geofence-settings'),
        headers: ApiConstants.headersWithApiKey,
      ).timeout(ApiConstants.defaultTimeout);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true && data['settings'] != null) {
          final settings = data['settings'];
          setState(() {
            _geofenceEnabled = settings['enabled'] ?? true;
            _radiusController.text = (settings['radiusMeters'] ?? 500).toString();
            _titleController.text = settings['notificationTitle'] ?? 'Arabica рядом!';
            _bodyController.text = settings['notificationBody'] ?? 'Вы рядом с нашей кофейней. Заходите за ароматным кофе!';
            _cooldownHours = settings['cooldownHours'] ?? 24;
          });
        }
      }
    } catch (e) {
      Logger.error('Ошибка загрузки настроек геозоны', e);
    } finally {
      if (mounted) {
        setState(() => _isLoadingSettings = false);
      }
    }
  }

  Future<void> _saveGeofenceSettings() async {
    setState(() => _isSavingSettings = true);
    try {
      final response = await http.post(
        Uri.parse('${ApiConstants.serverUrl}/api/geofence-settings'),
        headers: ApiConstants.headersWithApiKey,
        body: jsonEncode({
          'enabled': _geofenceEnabled,
          'radiusMeters': int.tryParse(_radiusController.text) ?? 500,
          'notificationTitle': _titleController.text,
          'notificationBody': _bodyController.text,
          'cooldownHours': _cooldownHours,
        }),
      ).timeout(ApiConstants.defaultTimeout);

      if (response.statusCode == 200) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Row(
                children: [
                  Icon(Icons.check_circle, color: Colors.white),
                  SizedBox(width: 12),
                  Text('Настройки сохранены'),
                ],
              ),
              backgroundColor: Colors.green[600],
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          );
        }
      } else {
        throw Exception('Ошибка сервера: ${response.statusCode}');
      }
    } catch (e) {
      Logger.error('Ошибка сохранения настроек геозоны', e);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.error_outline, color: Colors.white),
                const SizedBox(width: 12),
                Expanded(child: Text('Ошибка сохранения: $e')),
              ],
            ),
            backgroundColor: Colors.red[600],
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSavingSettings = false);
      }
    }
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      // Загружаем магазины
      final shops = await ShopService.getShops();

      // Фильтруем только магазины с координатами
      final shopsWithCoords = shops.where((s) => s.latitude != null && s.longitude != null).toList();

      setState(() {
        _shops = shopsWithCoords;
        _isLoading = false;
      });

      _animationController.forward(from: 0);

      // Получаем текущую геолокацию
      _getCurrentLocation();
    } catch (e) {
      setState(() {
        _error = 'Ошибка загрузки магазинов: $e';
        _isLoading = false;
      });
    }
  }

  Future<void> _getCurrentLocation() async {
    setState(() => _isLoadingLocation = true);

    try {
      // Проверяем включены ли службы геолокации
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Row(
                children: [
                  Icon(Icons.location_off, color: Colors.white),
                  SizedBox(width: 12),
                  Expanded(child: Text('Включите службы геолокации')),
                ],
              ),
              backgroundColor: Colors.orange[700],
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              action: SnackBarAction(
                label: 'Открыть',
                textColor: Colors.white,
                onPressed: () => Geolocator.openLocationSettings(),
              ),
            ),
          );
        }
        setState(() => _isLoadingLocation = false);
        return;
      }

      // Проверяем разрешения
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          setState(() => _isLoadingLocation = false);
          return;
        }
      }

      // Обработка deniedForever с кнопкой для открытия настроек
      if (permission == LocationPermission.deniedForever) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Row(
                children: [
                  Icon(Icons.location_disabled, color: Colors.white),
                  SizedBox(width: 12),
                  Expanded(child: Text('Разрешите доступ к геолокации в настройках')),
                ],
              ),
              backgroundColor: Colors.red[600],
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              duration: const Duration(seconds: 5),
              action: SnackBarAction(
                label: 'Настройки',
                textColor: Colors.white,
                onPressed: () => Geolocator.openAppSettings(),
              ),
            ),
          );
        }
        setState(() => _isLoadingLocation = false);
        return;
      }

      // Получаем текущую позицию с таймаутом 10 секунд
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 10),
      );

      if (mounted) {
        setState(() {
          _currentPosition = position;
          _isLoadingLocation = false;
        });
      }
    } catch (e) {
      Logger.error('Ошибка получения геолокации', e);
      if (mounted) {
        setState(() => _isLoadingLocation = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Row(
              children: [
                Icon(Icons.error_outline, color: Colors.white),
                SizedBox(width: 12),
                Expanded(child: Text('Ошибка определения местоположения')),
              ],
            ),
            backgroundColor: Colors.red[600],
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );
      }
    }
  }

  /// Рассчитать расстояние до магазина
  double? _calculateDistance(Shop shop) {
    if (_currentPosition == null || shop.latitude == null || shop.longitude == null) {
      return null;
    }

    return Geolocator.distanceBetween(
      _currentPosition!.latitude,
      _currentPosition!.longitude,
      shop.latitude!,
      shop.longitude!,
    );
  }

  /// Форматировать расстояние
  String _formatDistance(double? distance) {
    if (distance == null) return '';

    if (distance < 1000) {
      return '${distance.toStringAsFixed(0)} м';
    } else {
      return '${(distance / 1000).toStringAsFixed(1)} км';
    }
  }

  /// Открыть маршрут в Яндекс Картах
  Future<void> _openRoute(Shop shop) async {
    if (shop.latitude == null || shop.longitude == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Row(
            children: [
              Icon(Icons.error_outline, color: Colors.white),
              SizedBox(width: 12),
              Text('Координаты магазина не указаны', style: TextStyle(color: Colors.white)),
            ],
          ),
          backgroundColor: Colors.red[600],
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
      return;
    }

    String url;

    if (_currentPosition != null) {
      // Маршрут от текущего местоположения до магазина
      url = 'https://yandex.ru/maps/?rtext='
          '${_currentPosition!.latitude},${_currentPosition!.longitude}~'
          '${shop.latitude},${shop.longitude}'
          '&rtt=auto';
    } else {
      // Просто показать точку магазина на карте
      url = 'https://yandex.ru/maps/?pt=${shop.longitude},${shop.latitude}&z=16&l=map';
    }

    final uri = Uri.parse(url);

    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        // Пробуем открыть через браузер
        await launchUrl(uri, mode: LaunchMode.platformDefault);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.error_outline, color: Colors.white),
                const SizedBox(width: 12),
                Expanded(child: Text('Не удалось открыть карту: $e', style: const TextStyle(color: Colors.white))),
              ],
            ),
            backgroundColor: Colors.red[600],
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Показываем загрузку пока определяем роль
    if (_isLoadingRole) {
      return Scaffold(
        backgroundColor: _night,
        body: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [_emerald, _emeraldDark, _night],
              stops: [0.0, 0.3, 1.0],
            ),
          ),
          child: Center(child: CircularProgressIndicator(color: _gold)),
        ),
      );
    }

    final isAdmin = _userRole == UserRole.admin || _userRole == UserRole.developer;

    return Scaffold(
      backgroundColor: _night,
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [_emerald, _emeraldDark, _night],
            stops: [0.0, 0.3, 1.0],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              _buildAppBar(),
              // TabBar для админа
              if (isAdmin && _tabController != null)
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 16),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.06),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.white.withOpacity(0.08)),
                  ),
                  child: TabBar(
                    controller: _tabController!,
                    labelColor: _gold,
                    unselectedLabelColor: Colors.white.withOpacity(0.5),
                    indicatorSize: TabBarIndicatorSize.tab,
                    indicator: BoxDecoration(
                      color: _gold.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    tabs: const [
                      Tab(
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.store, size: 20),
                            SizedBox(width: 8),
                            Text('Магазины'),
                          ],
                        ),
                      ),
                      Tab(
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.notifications_active, size: 20),
                            SizedBox(width: 8),
                            Text('Настройки'),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 8),
              // Контент
              Expanded(
                child: isAdmin && _tabController != null
                    ? TabBarView(
                        controller: _tabController!,
                        children: [
                          _buildBody(),
                          _buildSettingsTab(),
                        ],
                      )
                    : _buildBody(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAppBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white.withOpacity(0.1)),
              ),
              child: const Icon(Icons.arrow_back, color: Colors.white, size: 20),
            ),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Text(
              'Магазины на карте',
              style: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          if (_isLoadingLocation)
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white.withOpacity(0.1)),
              ),
              child: const Center(
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                ),
              ),
            )
          else
            GestureDetector(
              onTap: _getCurrentLocation,
              child: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: _currentPosition != null
                      ? Colors.green.withOpacity(0.15)
                      : Colors.white.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: _currentPosition != null
                        ? Colors.green.withOpacity(0.3)
                        : Colors.white.withOpacity(0.1),
                  ),
                ),
                child: Icon(
                  _currentPosition != null ? Icons.my_location : Icons.location_searching,
                  color: _currentPosition != null ? Colors.green : Colors.white,
                  size: 20,
                ),
              ),
            ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: _loadData,
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white.withOpacity(0.1)),
              ),
              child: const Icon(Icons.refresh, color: Colors.white, size: 20),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: _gold.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: CircularProgressIndicator(color: _gold),
            ),
            const SizedBox(height: 24),
            Text(
              'Загрузка магазинов...',
              style: TextStyle(
                color: Colors.white.withOpacity(0.6),
                fontSize: 16,
              ),
            ),
          ],
        ),
      );
    }

    if (_error != null) {
      return Center(
        child: Container(
          margin: const EdgeInsets.all(24),
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.06),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withOpacity(0.08)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.error_outline, size: 48, color: Colors.red.shade300),
              ),
              const SizedBox(height: 20),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white.withOpacity(0.8), fontSize: 16),
              ),
              const SizedBox(height: 24),
              OutlinedButton.icon(
                onPressed: _loadData,
                icon: Icon(Icons.refresh, color: _gold),
                label: Text('Повторить', style: TextStyle(color: _gold)),
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: _gold.withOpacity(0.4)),
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  backgroundColor: _gold.withOpacity(0.1),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (_shops.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.06),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.store_mall_directory_outlined, size: 40, color: Colors.white.withOpacity(0.3)),
            ),
            const SizedBox(height: 20),
            Text(
              'Нет магазинов с координатами',
              style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 16),
            ),
          ],
        ),
      );
    }

    // Сортируем по расстоянию, если есть геолокация
    final sortedShops = List<Shop>.from(_shops);
    if (_currentPosition != null) {
      sortedShops.sort((a, b) {
        final distA = _calculateDistance(a);
        final distB = _calculateDistance(b);
        if (distA == null) return 1;
        if (distB == null) return -1;
        return distA.compareTo(distB);
      });
    }

    return Column(
      children: [
        // Информация о геолокации
        _buildLocationBanner(),

        // Список магазинов
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            itemCount: sortedShops.length,
            itemBuilder: (context, index) {
              final shop = sortedShops[index];
              final distance = _calculateDistance(shop);

              return AnimatedBuilder(
                animation: _animationController,
                builder: (context, child) {
                  // Ограничиваем delay до 0.9 чтобы избежать деления на 0
                  final delay = (index * 0.1).clamp(0.0, 0.9);
                  final denominator = 1 - delay;
                  // easeOutBack может возвращать значения >1.0, поэтому clamp обязателен
                  final rawValue = denominator > 0
                      ? Curves.easeOutBack.transform(
                          ((_animationController.value - delay) / denominator).clamp(0.0, 1.0),
                        )
                      : 1.0;
                  final animValue = rawValue.clamp(0.0, 1.0);

                  return Transform.translate(
                    offset: Offset(0, 30 * (1 - animValue)),
                    child: Opacity(
                      opacity: animValue,
                      child: child,
                    ),
                  );
                },
                child: _buildShopCard(shop, distance, index),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildLocationBanner() {
    final bannerColor = _currentPosition != null ? Colors.green : Colors.orange;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: bannerColor.withOpacity(0.1),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: bannerColor.withOpacity(0.25)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: bannerColor.withOpacity(0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              _currentPosition != null ? Icons.check_circle : Icons.info_outline,
              color: bannerColor,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              _currentPosition != null
                  ? 'Местоположение определено.\nНажмите на магазин для маршрута.'
                  : 'Разрешите геолокацию для построения маршрута.',
              style: TextStyle(
                color: Colors.white.withOpacity(0.7),
                fontSize: 13,
                height: 1.4,
              ),
            ),
          ),
          if (_currentPosition == null)
            GestureDetector(
              onTap: _getCurrentLocation,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: _gold.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: _gold.withOpacity(0.3)),
                ),
                child: Text(
                  'Разрешить',
                  style: TextStyle(
                    color: _gold,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildShopCard(Shop shop, double? distance, int index) {
    final isNearby = distance != null && distance < 1000;
    final distanceColor = isNearby ? Colors.green : Colors.blue;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _openRoute(shop),
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                // Иконка магазина
                Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.white.withOpacity(0.1)),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: const ShopIcon(size: 56),
                  ),
                ),
                const SizedBox(width: 14),

                // Информация о магазине
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        shop.name,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: Colors.white.withOpacity(0.9),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(Icons.location_on, size: 14, color: Colors.white.withOpacity(0.3)),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              shop.address,
                              style: TextStyle(
                                fontSize: 13,
                                color: Colors.white.withOpacity(0.4),
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      if (distance != null) ...[
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: distanceColor.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: distanceColor.withOpacity(0.25)),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                isNearby ? Icons.directions_walk : Icons.directions_car,
                                size: 14,
                                color: distanceColor,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                _formatDistance(distance),
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: distanceColor,
                                ),
                              ),
                              if (isNearby) ...[
                                const SizedBox(width: 4),
                                Text(
                                  '• Рядом',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: distanceColor.withOpacity(0.7),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),

                // Кнопка маршрута
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: _gold.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: _gold.withOpacity(0.2)),
                  ),
                  child: Icon(
                    Icons.directions,
                    color: _gold.withOpacity(0.8),
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

  /// Вкладка настроек геозоны (только для админа)
  Widget _buildSettingsTab() {
    if (_isLoadingSettings) {
      return Center(
        child: CircularProgressIndicator(color: _gold),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Заголовок
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.06),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white.withOpacity(0.08)),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: _geofenceEnabled ? Colors.green.withOpacity(0.15) : Colors.orange.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    _geofenceEnabled ? Icons.notifications_active : Icons.notifications_off,
                    color: _geofenceEnabled ? Colors.green : Colors.orange,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Push-уведомления',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.9),
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _geofenceEnabled
                            ? 'Клиенты получают уведомления рядом с магазином'
                            : 'Уведомления отключены',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.4),
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
                Switch(
                  value: _geofenceEnabled,
                  onChanged: (v) => setState(() => _geofenceEnabled = v),
                  activeColor: _gold,
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // Радиус
          _buildSettingsCard(
            icon: Icons.radar,
            title: 'Радиус срабатывания',
            subtitle: 'Расстояние до магазина в метрах',
            child: TextField(
              controller: _radiusController,
              keyboardType: TextInputType.number,
              style: const TextStyle(color: Colors.white, fontSize: 16),
              cursorColor: _gold,
              decoration: InputDecoration(
                hintText: '500',
                hintStyle: TextStyle(color: Colors.white.withOpacity(0.3)),
                suffixText: 'м',
                suffixStyle: TextStyle(color: Colors.white.withOpacity(0.5)),
                filled: true,
                fillColor: Colors.white.withOpacity(0.06),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.white.withOpacity(0.08)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: _gold.withOpacity(0.4)),
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              ),
            ),
          ),

          const SizedBox(height: 16),

          // Заголовок уведомления
          _buildSettingsCard(
            icon: Icons.title,
            title: 'Заголовок уведомления',
            subtitle: 'Отображается вверху push-уведомления',
            child: TextField(
              controller: _titleController,
              style: const TextStyle(color: Colors.white, fontSize: 16),
              cursorColor: _gold,
              decoration: InputDecoration(
                hintText: 'Arabica рядом!',
                hintStyle: TextStyle(color: Colors.white.withOpacity(0.3)),
                filled: true,
                fillColor: Colors.white.withOpacity(0.06),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.white.withOpacity(0.08)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: _gold.withOpacity(0.4)),
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              ),
            ),
          ),

          const SizedBox(height: 16),

          // Текст уведомления
          _buildSettingsCard(
            icon: Icons.message,
            title: 'Текст уведомления',
            subtitle: 'Основной текст push-уведомления',
            child: TextField(
              controller: _bodyController,
              maxLines: 3,
              style: const TextStyle(color: Colors.white, fontSize: 16),
              cursorColor: _gold,
              decoration: InputDecoration(
                hintText: 'Заходите за ароматным кофе!',
                hintStyle: TextStyle(color: Colors.white.withOpacity(0.3)),
                filled: true,
                fillColor: Colors.white.withOpacity(0.06),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.white.withOpacity(0.08)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: _gold.withOpacity(0.4)),
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              ),
            ),
          ),

          const SizedBox(height: 16),

          // Интервал между уведомлениями
          _buildSettingsCard(
            icon: Icons.timer,
            title: 'Интервал между уведомлениями',
            subtitle: 'Минимальное время между push для одного клиента',
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.06),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white.withOpacity(0.08)),
              ),
              child: DropdownButtonFormField<int>(
                value: _cooldownHours,
                dropdownColor: _emeraldDark,
                style: const TextStyle(color: Colors.white, fontSize: 16),
                decoration: const InputDecoration(
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                ),
                items: const [
                  DropdownMenuItem(value: 6, child: Text('6 часов')),
                  DropdownMenuItem(value: 12, child: Text('12 часов')),
                  DropdownMenuItem(value: 24, child: Text('24 часа')),
                  DropdownMenuItem(value: 48, child: Text('48 часов')),
                  DropdownMenuItem(value: 72, child: Text('72 часа')),
                ],
                onChanged: (v) => setState(() => _cooldownHours = v ?? 24),
              ),
            ),
          ),

          const SizedBox(height: 24),

          // Кнопка сохранения
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _isSavingSettings ? null : _saveGeofenceSettings,
              icon: _isSavingSettings
                  ? SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: _gold),
                    )
                  : Icon(Icons.save, color: _gold),
              label: Text(
                _isSavingSettings ? 'Сохранение...' : 'Сохранить настройки',
                style: TextStyle(fontSize: 16, color: _gold, fontWeight: FontWeight.bold),
              ),
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: _gold.withOpacity(0.4)),
                padding: const EdgeInsets.symmetric(vertical: 16),
                backgroundColor: _gold.withOpacity(0.1),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
          ),

          const SizedBox(height: 16),

          // Информация
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: _gold.withOpacity(0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _gold.withOpacity(0.15)),
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline, color: _gold.withOpacity(0.7), size: 20),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Уведомления отправляются автоматически, когда клиент находится в радиусе любого магазина.',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.5),
                      fontSize: 13,
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Карточка настройки
  Widget _buildSettingsCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required Widget child,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.06),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: _gold.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, color: _gold.withOpacity(0.8), size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.9),
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.4),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: child,
          ),
        ],
      ),
    );
  }
}
