import 'package:flutter/material.dart';
import '../../../core/widgets/shop_icon.dart';
import '../../shops/models/shop_model.dart';
import '../../efficiency/services/points_settings_service.dart';
import 'shift_questions_page.dart';

/// Страница выбора магазина для пересменки
class ShiftShopSelectionPage extends StatefulWidget {
  final String employeeName;

  const ShiftShopSelectionPage({
    super.key,
    required this.employeeName,
  });

  @override
  State<ShiftShopSelectionPage> createState() => _ShiftShopSelectionPageState();
}

class _ShiftShopSelectionPageState extends State<ShiftShopSelectionPage> {
  String? _currentShiftType;
  bool _isLoadingSettings = true;

  @override
  void initState() {
    super.initState();
    _loadShiftType();
  }

  /// Парсинг времени из строки "HH:MM"
  TimeOfDay _parseTime(String timeStr) {
    final parts = timeStr.split(':');
    return TimeOfDay(
      hour: int.parse(parts[0]),
      minute: int.parse(parts[1]),
    );
  }

  /// Проверка находится ли время в диапазоне
  bool _isTimeInRange(TimeOfDay current, TimeOfDay start, TimeOfDay end) {
    final currentMinutes = current.hour * 60 + current.minute;
    final startMinutes = start.hour * 60 + start.minute;
    final endMinutes = end.hour * 60 + end.minute;
    return currentMinutes >= startMinutes && currentMinutes < endMinutes;
  }

  /// Определить текущий тип смены на основе настроек
  Future<void> _loadShiftType() async {
    try {
      final settings = await PointsSettingsService.getShiftPointsSettings();
      final now = TimeOfDay.now();

      final morningStart = _parseTime(settings.morningStartTime ?? '07:00');
      final morningEnd = _parseTime(settings.morningEndTime ?? '13:00');
      final eveningStart = _parseTime(settings.eveningStartTime ?? '14:00');
      final eveningEnd = _parseTime(settings.eveningEndTime ?? '23:00');

      String? shiftType;
      if (_isTimeInRange(now, morningStart, morningEnd)) {
        shiftType = 'morning';
      } else if (_isTimeInRange(now, eveningStart, eveningEnd)) {
        shiftType = 'evening';
      }

      if (mounted) {
        setState(() {
          _currentShiftType = shiftType;
          _isLoadingSettings = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoadingSettings = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Выберите магазин'),
        backgroundColor: const Color(0xFF004D40),
      ),
      body: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF004D40),
          image: DecorationImage(
            image: AssetImage('assets/images/arabica_background.png'),
            fit: BoxFit.cover,
            opacity: 0.6,
          ),
        ),
        child: _isLoadingSettings
            ? const Center(child: CircularProgressIndicator())
            : FutureBuilder<List<Shop>>(
                future: Shop.loadShopsFromGoogleSheets(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  if (snapshot.hasError) {
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.error_outline, size: 64, color: Colors.red),
                          const SizedBox(height: 16),
                          const Text(
                            'Что-то пошло не так, попробуйте позже',
                            style: TextStyle(color: Colors.white, fontSize: 18),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 16),
                          ElevatedButton(
                            onPressed: () => Navigator.pop(context),
                            child: const Text('Назад'),
                          ),
                        ],
                      ),
                    );
                  }

                  final shops = snapshot.data ?? [];
                  if (shops.isEmpty) {
                    return const Center(
                      child: Text(
                        'Магазины не найдены',
                        style: TextStyle(color: Colors.white, fontSize: 18),
                      ),
                    );
                  }

                  // Проверяем, активен ли интервал пересменки
                  if (_currentShiftType == null) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.timer_off, size: 64, color: Colors.orange),
                            const SizedBox(height: 16),
                            const Text(
                              'Сейчас не время для пересменки',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                              ),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 8),
                            const Text(
                              'Пересменку можно пройти только в установленные временные интервалы',
                              style: TextStyle(color: Colors.white70, fontSize: 14),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 24),
                            ElevatedButton(
                              onPressed: () => Navigator.pop(context),
                              child: const Text('Назад'),
                            ),
                          ],
                        ),
                      ),
                    );
                  }

                  return ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: shops.length,
                    itemBuilder: (context, index) {
                      final shop = shops[index];
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Material(
                          color: Colors.white.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(12),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(12),
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => ShiftQuestionsPage(
                                    employeeName: widget.employeeName,
                                    shopAddress: shop.address,
                                    shiftType: _currentShiftType,
                                  ),
                                ),
                              );
                            },
                            child: Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: Colors.white.withOpacity(0.5),
                                  width: 2,
                                ),
                              ),
                              child: Row(
                                children: [
                                  const ShopIcon(size: 56),
                                  const SizedBox(width: 16),
                                  Expanded(
                                    child: Text(
                                      shop.address,
                                      style: const TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w600,
                                        color: Colors.white,
                                      ),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  const Icon(
                                    Icons.chevron_right,
                                    color: Colors.white70,
                                    size: 28,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
      ),
    );
  }
}


















