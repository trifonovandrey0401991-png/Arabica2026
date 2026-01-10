import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/utils/logger.dart';
import '../models/shop_model.dart';
import '../services/shop_service.dart';

/// Страница списка магазинов с возможностью построения маршрута
class ShopsOnMapPage extends StatefulWidget {
  const ShopsOnMapPage({super.key});

  @override
  State<ShopsOnMapPage> createState() => _ShopsOnMapPageState();
}

class _ShopsOnMapPageState extends State<ShopsOnMapPage> {
  List<Shop> _shops = [];
  bool _isLoading = true;
  String? _error;
  Position? _currentPosition;
  bool _isLoadingLocation = false;

  static const _primaryColor = Color(0xFF004D40);

  @override
  void initState() {
    super.initState();
    _loadData();
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
      // Проверяем разрешения
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          setState(() => _isLoadingLocation = false);
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        setState(() => _isLoadingLocation = false);
        return;
      }

      // Получаем текущую позицию
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      setState(() {
        _currentPosition = position;
        _isLoadingLocation = false;
      });
    } catch (e) {
      Logger.error('Ошибка получения геолокации', e);
      setState(() => _isLoadingLocation = false);
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
        const SnackBar(
          content: Text('Координаты магазина не указаны', style: TextStyle(color: Colors.white)),
          backgroundColor: Colors.red,
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
            content: Text('Не удалось открыть карту: $e', style: const TextStyle(color: Colors.white)),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Магазины на карте'),
        backgroundColor: _primaryColor,
        actions: [
          if (_isLoadingLocation)
            const Padding(
              padding: EdgeInsets.all(16),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              ),
            )
          else
            IconButton(
              icon: Icon(
                _currentPosition != null ? Icons.my_location : Icons.location_searching,
                color: _currentPosition != null ? Colors.greenAccent : Colors.white,
              ),
              onPressed: _getCurrentLocation,
              tooltip: 'Определить местоположение',
            ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadData,
            tooltip: 'Обновить',
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 64, color: Colors.red),
            const SizedBox(height: 16),
            Text(_error!, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _loadData,
              child: const Text('Повторить'),
            ),
          ],
        ),
      );
    }

    if (_shops.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.store_outlined, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(
              'Нет магазинов с координатами',
              style: TextStyle(fontSize: 18, color: Colors.grey[600]),
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
        Container(
          padding: const EdgeInsets.all(12),
          color: _currentPosition != null ? Colors.green[50] : Colors.orange[50],
          child: Row(
            children: [
              Icon(
                _currentPosition != null ? Icons.check_circle : Icons.info_outline,
                color: _currentPosition != null ? Colors.green : Colors.orange,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _currentPosition != null
                      ? 'Ваше местоположение определено. Нажмите на магазин для построения маршрута.'
                      : 'Разрешите доступ к геолокации для построения маршрута.',
                  style: TextStyle(
                    color: _currentPosition != null ? Colors.green[800] : Colors.orange[800],
                    fontSize: 13,
                  ),
                ),
              ),
              if (_currentPosition == null)
                TextButton(
                  onPressed: _getCurrentLocation,
                  child: const Text('Разрешить'),
                ),
            ],
          ),
        ),

        // Список магазинов
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: sortedShops.length,
            itemBuilder: (context, index) {
              final shop = sortedShops[index];
              final distance = _calculateDistance(shop);

              return Card(
                margin: const EdgeInsets.only(bottom: 12),
                elevation: 2,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                child: InkWell(
                  onTap: () => _openRoute(shop),
                  borderRadius: BorderRadius.circular(12),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        // Иконка магазина
                        Container(
                          width: 56,
                          height: 56,
                          decoration: BoxDecoration(
                            color: _primaryColor.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(
                            shop.icon,
                            color: _primaryColor,
                            size: 28,
                          ),
                        ),
                        const SizedBox(width: 16),

                        // Информация о магазине
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                shop.name,
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                shop.address,
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Colors.grey[600],
                                ),
                              ),
                              if (distance != null) ...[
                                const SizedBox(height: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.blue[50],
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.directions_walk,
                                        size: 14,
                                        color: Colors.blue[700],
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        _formatDistance(distance),
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w500,
                                          color: Colors.blue[700],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),

                        // Кнопка маршрута
                        Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            color: _primaryColor,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(
                            Icons.directions,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
