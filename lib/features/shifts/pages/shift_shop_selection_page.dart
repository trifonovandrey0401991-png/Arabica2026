import 'package:flutter/material.dart';
import '../../../core/widgets/shop_icon.dart';
import '../../shops/models/shop_model.dart';
import '../../shops/services/shop_service.dart';
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
  static const Color _emerald = Color(0xFF1A4D4D);
  static const Color _emeraldDark = Color(0xFF0D2E2E);
  static const Color _night = Color(0xFF051515);
  static const Color _gold = Color(0xFFD4AF37);

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

  Widget _buildAppBar(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
      child: Row(
        children: [
          Container(
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white.withOpacity(0.1)),
            ),
            child: IconButton(
              icon: Icon(Icons.arrow_back_ios_new, color: Colors.white.withOpacity(0.8), size: 20),
              onPressed: () => Navigator.pop(context),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Выберите магазин',
              style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
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
              _buildAppBar(context),
              Expanded(
                child: _isLoadingSettings
                    ? Center(child: CircularProgressIndicator(color: _gold))
                    : FutureBuilder<List<Shop>>(
                        future: ShopService.getShopsForCurrentUser(),
                        builder: (context, snapshot) {
                          if (snapshot.connectionState == ConnectionState.waiting) {
                            return Center(child: CircularProgressIndicator(color: _gold));
                          }

                          if (snapshot.hasError) {
                            return Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.error_outline, size: 64, color: Colors.red.withOpacity(0.8)),
                                  const SizedBox(height: 16),
                                  Text(
                                    'Что-то пошло не так, попробуйте позже',
                                    style: TextStyle(color: Colors.white.withOpacity(0.9), fontSize: 18),
                                    textAlign: TextAlign.center,
                                  ),
                                  const SizedBox(height: 16),
                                  ElevatedButton(
                                    onPressed: () => Navigator.pop(context),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: _gold,
                                      foregroundColor: _night,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                    ),
                                    child: const Text('Назад'),
                                  ),
                                ],
                              ),
                            );
                          }

                          final shops = snapshot.data ?? [];
                          if (shops.isEmpty) {
                            return Center(
                              child: Text(
                                'Магазины не найдены',
                                style: TextStyle(color: Colors.white.withOpacity(0.9), fontSize: 18),
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
                                    Icon(Icons.timer_off, size: 64, color: _gold.withOpacity(0.8)),
                                    const SizedBox(height: 16),
                                    Text(
                                      'Сейчас не время для пересменки',
                                      style: TextStyle(
                                        color: Colors.white.withOpacity(0.9),
                                        fontSize: 20,
                                        fontWeight: FontWeight.bold,
                                      ),
                                      textAlign: TextAlign.center,
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      'Пересменку можно пройти только в установленные временные интервалы',
                                      style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 14),
                                      textAlign: TextAlign.center,
                                    ),
                                    const SizedBox(height: 24),
                                    ElevatedButton(
                                      onPressed: () => Navigator.pop(context),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: _gold,
                                        foregroundColor: _night,
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(12),
                                        ),
                                      ),
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
                                  color: Colors.transparent,
                                  borderRadius: BorderRadius.circular(14),
                                  child: InkWell(
                                    borderRadius: BorderRadius.circular(14),
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
                                        color: Colors.white.withOpacity(0.06),
                                        borderRadius: BorderRadius.circular(14),
                                        border: Border.all(
                                          color: Colors.white.withOpacity(0.1),
                                        ),
                                      ),
                                      child: Row(
                                        children: [
                                          const ShopIcon(size: 56),
                                          const SizedBox(width: 16),
                                          Expanded(
                                            child: Text(
                                              shop.address,
                                              style: TextStyle(
                                                fontSize: 16,
                                                fontWeight: FontWeight.w600,
                                                color: Colors.white.withOpacity(0.9),
                                              ),
                                              maxLines: 2,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                          Icon(
                                            Icons.chevron_right,
                                            color: Colors.white.withOpacity(0.5),
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
            ],
          ),
        ),
      ),
    );
  }
}
