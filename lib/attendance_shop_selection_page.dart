import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'shop_model.dart';
import 'attendance_service.dart';
import 'attendance_model.dart';

class AttendanceShopSelectionPage extends StatefulWidget {
  final String employeeName;

  const AttendanceShopSelectionPage({
    super.key,
    required this.employeeName,
  });

  @override
  State<AttendanceShopSelectionPage> createState() => _AttendanceShopSelectionPageState();
}

class _AttendanceShopSelectionPageState extends State<AttendanceShopSelectionPage> {
  List<Shop> _shops = [];
  bool _isLoading = true;
  bool _isMarking = false;
  Position? _currentPosition;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadShops();
  }

  Future<void> _loadShops() async {
    try {
      final shops = await Shop.loadShopsFromGoogleSheets();
      setState(() {
        _shops = shops;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'Ошибка загрузки магазинов: $e';
        _isLoading = false;
      });
    }
  }

  Future<void> _markAttendance(Shop shop) async {
    if (shop.latitude == null || shop.longitude == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Координаты магазина не найдены'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }

    // Получаем геолокацию
    try {
      setState(() {
        _isMarking = true;
        _errorMessage = null;
      });

      final position = await AttendanceService.getCurrentLocation();
      
      // Проверяем, находится ли в радиусе
      final isWithinRadius = AttendanceService.isWithinRadius(
        position.latitude,
        position.longitude,
        shop.latitude!,
        shop.longitude!,
      );

      if (!isWithinRadius) {
        final distance = AttendanceService.calculateDistance(
          position.latitude,
          position.longitude,
          shop.latitude!,
          shop.longitude!,
        );
        
        if (mounted) {
          setState(() {
            _isMarking = false;
          });
          showDialog(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('Вы слишком далеко от магазина'),
              content: Text(
                'Вы находитесь на расстоянии ${distance.toStringAsFixed(0)} м от магазина.\n'
                'Необходимо находиться в радиусе 750 м.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('OK'),
                ),
              ],
            ),
          );
        }
        return;
      }

      // Отмечаем приход
      final distance = AttendanceService.calculateDistance(
        position.latitude,
        position.longitude,
        shop.latitude!,
        shop.longitude!,
      );

      final result = await AttendanceService.markAttendance(
        employeeName: widget.employeeName,
        shopAddress: shop.address,
        latitude: position.latitude,
        longitude: position.longitude,
        distance: distance,
      );

      if (mounted) {
        setState(() {
          _isMarking = false;
        });

        if (result.success) {
          // Показываем диалог с информацией о статусе
          String title;
          String message;
          Color backgroundColor;
          IconData icon;
          
          if (result.isOnTime == true) {
            title = 'Вы пришли вовремя';
            message = result.message ?? 'Отметка успешно сохранена';
            backgroundColor = Colors.green;
            icon = Icons.check_circle;
          } else if (result.isOnTime == false && result.lateMinutes != null) {
            title = 'Вы опоздали';
            message = result.message ?? 'Вы опоздали на ${result.lateMinutes} минут';
            backgroundColor = Colors.orange;
            icon = Icons.warning;
          } else if (result.isOnTime == null) {
            title = 'Отметка вне смены';
            message = result.message ?? 'Отметка сделана вне интервалов смены';
            backgroundColor = Colors.amber;
            icon = Icons.info;
          } else {
            title = 'Отметка сохранена';
            message = result.message ?? 'Отметка успешно сохранена';
            backgroundColor = Colors.blue;
            icon = Icons.check_circle;
          }
          
          showDialog(
            context: context,
            builder: (context) => AlertDialog(
              title: Row(
                children: [
                  Icon(icon, color: backgroundColor),
                  const SizedBox(width: 8),
                  Expanded(child: Text(title)),
                ],
              ),
              content: Text(message),
              backgroundColor: backgroundColor.withOpacity(0.1),
              actions: [
                TextButton(
                  onPressed: () {
                    Navigator.pop(context); // Закрываем диалог
                    Navigator.pop(context); // Закрываем страницу выбора магазина
                  },
                  child: const Text('OK'),
                ),
              ],
            ),
          );
        } else {
          // Показываем ошибку
          showDialog(
            context: context,
            builder: (context) => AlertDialog(
              title: const Row(
                children: [
                  Icon(Icons.error, color: Colors.red),
                  SizedBox(width: 8),
                  Text('Ошибка'),
                ],
              ),
              content: Text(result.error ?? 'Ошибка при отметке. Попробуйте позже'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('OK'),
                ),
              ],
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isMarking = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка: $e'),
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
        title: const Text('Я на работе'),
        backgroundColor: const Color(0xFF004D40),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage != null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Text(
                          _errorMessage!,
                          style: const TextStyle(color: Colors.red),
                          textAlign: TextAlign.center,
                        ),
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: _loadShops,
                        child: const Text('Повторить'),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _shops.length,
                  itemBuilder: (context, index) {
                    final shop = _shops[index];
                    return Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      child: ListTile(
                        leading: Icon(shop.icon, color: const Color(0xFF004D40)),
                        title: Text(shop.name),
                        subtitle: Text(shop.address),
                        trailing: _isMarking
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : IconButton(
                                icon: const Icon(Icons.check_circle),
                                color: Colors.green,
                                onPressed: () => _markAttendance(shop),
                              ),
                      ),
                    );
                  },
                ),
    );
  }
}












