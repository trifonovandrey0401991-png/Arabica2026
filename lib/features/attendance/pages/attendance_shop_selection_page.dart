import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import '../../shops/models/shop_model.dart';
import '../services/attendance_service.dart';

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

  /// Диалог выбора смены (когда время вне интервала)
  Future<String?> _showShiftSelectionDialog() {
    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.schedule, color: Color(0xFF004D40)),
            SizedBox(width: 8),
            Expanded(child: Text('На какую смену вы заступили?')),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Время отметки не попадает в интервал смен.\nВыберите вашу смену:',
              style: TextStyle(fontSize: 14, color: Colors.grey),
            ),
            const SizedBox(height: 16),
            _buildShiftOption(
              context: context,
              icon: Icons.wb_sunny,
              color: Colors.orange,
              label: 'Утренняя смена',
              value: 'morning',
            ),
            const SizedBox(height: 8),
            _buildShiftOption(
              context: context,
              icon: Icons.wb_cloudy,
              color: Colors.blue,
              label: 'Дневная смена',
              value: 'day',
            ),
            const SizedBox(height: 8),
            _buildShiftOption(
              context: context,
              icon: Icons.nights_stay,
              color: Colors.indigo,
              label: 'Ночная смена',
              value: 'night',
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, null),
            child: const Text('Отмена'),
          ),
        ],
      ),
    );
  }

  Widget _buildShiftOption({
    required BuildContext context,
    required IconData icon,
    required Color color,
    required String label,
    required String value,
  }) {
    return InkWell(
      onTap: () => Navigator.pop(context, value),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          border: Border.all(color: color.withOpacity(0.5)),
          borderRadius: BorderRadius.circular(8),
          color: color.withOpacity(0.1),
        ),
        child: Row(
          children: [
            Icon(icon, color: color),
            const SizedBox(width: 12),
            Text(
              label,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w500,
                color: color,
              ),
            ),
            const Spacer(),
            Icon(Icons.chevron_right, color: color),
          ],
        ),
      ),
    );
  }

  /// Показать диалог с результатом отметки
  void _showAttendanceResultDialog(AttendanceResult result) {
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
      if (result.penaltyCreated) {
        message += '\nНачислен штраф.';
      }
      backgroundColor = Colors.orange;
      icon = Icons.warning;
    } else if (result.isOnTime == null) {
      title = 'Отметка сохранена';
      message = result.message ?? 'Отметка сделана';
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
          // Проверяем, нужен ли выбор смены
          if (result.needsShiftSelection && result.recordId != null) {
            // Показываем диалог выбора смены
            final selectedShift = await _showShiftSelectionDialog();
            if (selectedShift != null && mounted) {
              setState(() => _isMarking = true);

              // Подтверждаем выбор смены
              final confirmResult = await AttendanceService.confirmShift(
                recordId: result.recordId!,
                selectedShift: selectedShift,
                employeeName: widget.employeeName,
                shopAddress: shop.address,
              );

              if (mounted) {
                setState(() => _isMarking = false);
                _showAttendanceResultDialog(confirmResult);
              }
            }
            return;
          }

          // Показываем диалог с информацией о статусе
          _showAttendanceResultDialog(result);
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
                        leading: shop.leadingIcon,
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












