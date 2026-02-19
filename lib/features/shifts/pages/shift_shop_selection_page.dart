import 'package:flutter/material.dart';
import '../../../core/widgets/shop_icon.dart';
import '../../shops/models/shop_model.dart';
import '../../shops/services/shop_service.dart';
import '../../efficiency/services/points_settings_service.dart';
import '../services/shift_report_service.dart';
import 'shift_questions_page.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../../core/theme/app_colors.dart';

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
  Set<String> _submittedShops = {};

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

  /// Проверка находится ли время в диапазоне (с поддержкой перехода через полночь)
  bool _isTimeInRange(TimeOfDay current, TimeOfDay start, TimeOfDay end) {
    final currentMinutes = current.hour * 60 + current.minute;
    final startMinutes = start.hour * 60 + start.minute;
    final endMinutes = end.hour * 60 + end.minute;
    if (startMinutes <= endMinutes) {
      return currentMinutes >= startMinutes && currentMinutes < endMinutes;
    } else {
      // Переход через полночь (например 23:01 - 13:00)
      return currentMinutes >= startMinutes || currentMinutes < endMinutes;
    }
  }

  /// Определить текущий тип смены на основе настроек
  Future<void> _loadShiftType() async {
    try {
      final settings = await PointsSettingsService.getShiftPointsSettings();
      final now = TimeOfDay.now();

      final morningStart = _parseTime(settings.morningStartTime);
      final morningEnd = _parseTime(settings.morningEndTime);
      final eveningStart = _parseTime(settings.eveningStartTime);
      final eveningEnd = _parseTime(settings.eveningEndTime);

      String? shiftType;
      if (_isTimeInRange(now, morningStart, morningEnd)) {
        shiftType = 'morning';
      } else if (_isTimeInRange(now, eveningStart, eveningEnd)) {
        shiftType = 'evening';
      }

      // Загружаем магазины, где уже пройдена пересменка
      if (shiftType != null) {
        await _loadSubmittedShops(shiftType);
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

  /// Загрузить магазины, где уже есть отчёт за сегодня (статус != pending)
  Future<void> _loadSubmittedShops(String shiftType) async {
    try {
      final reports = await ShiftReportService.getReports(date: DateTime.now());
      _submittedShops = reports
          .where((r) => r.shiftType == shiftType && r.status != 'pending')
          .map((r) => r.shopAddress)
          .toSet();
    } catch (e) {
      // Ошибка загрузки — показываем все магазины
      _submittedShops = {};
    }
  }

  Widget _buildAppBar(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(8.w, 8.h, 8.w, 4.h),
      child: Row(
        children: [
          Container(
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.08),
              borderRadius: BorderRadius.circular(12.r),
              border: Border.all(color: Colors.white.withOpacity(0.1)),
            ),
            child: IconButton(
              icon: Icon(Icons.arrow_back_ios_new, color: Colors.white.withOpacity(0.8), size: 20),
              onPressed: () => Navigator.pop(context),
            ),
          ),
          SizedBox(width: 12),
          Expanded(
            child: Text(
              'Выберите магазин',
              style: TextStyle(color: Colors.white, fontSize: 18.sp, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.night,
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [AppColors.emerald, AppColors.emeraldDark, AppColors.night],
            stops: [0.0, 0.3, 1.0],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              _buildAppBar(context),
              Expanded(
                child: _isLoadingSettings
                    ? Center(child: CircularProgressIndicator(color: AppColors.gold))
                    : FutureBuilder<List<Shop>>(
                        future: ShopService.getShopsForCurrentUser(),
                        builder: (context, snapshot) {
                          if (snapshot.connectionState == ConnectionState.waiting) {
                            return Center(child: CircularProgressIndicator(color: AppColors.gold));
                          }

                          if (snapshot.hasError) {
                            return Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.error_outline, size: 64, color: Colors.red.withOpacity(0.8)),
                                  SizedBox(height: 16),
                                  Text(
                                    'Что-то пошло не так, попробуйте позже',
                                    style: TextStyle(color: Colors.white.withOpacity(0.9), fontSize: 18.sp),
                                    textAlign: TextAlign.center,
                                  ),
                                  SizedBox(height: 16),
                                  ElevatedButton(
                                    onPressed: () => Navigator.pop(context),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: AppColors.gold,
                                      foregroundColor: AppColors.night,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12.r),
                                      ),
                                    ),
                                    child: Text('Назад'),
                                  ),
                                ],
                              ),
                            );
                          }

                          final allShops = snapshot.data ?? [];
                          // Фильтруем магазины, где уже пройдена пересменка
                          final shops = allShops
                              .where((s) => !_submittedShops.contains(s.address))
                              .toList();

                          if (allShops.isEmpty) {
                            return Center(
                              child: Text(
                                'Магазины не найдены',
                                style: TextStyle(color: Colors.white.withOpacity(0.9), fontSize: 18.sp),
                              ),
                            );
                          }

                          if (shops.isEmpty) {
                            return Center(
                              child: Padding(
                                padding: EdgeInsets.all(24.w),
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.check_circle_outline, size: 64, color: Colors.green.withOpacity(0.8)),
                                    SizedBox(height: 16),
                                    Text(
                                      'Все пересменки пройдены',
                                      style: TextStyle(
                                        color: Colors.white.withOpacity(0.9),
                                        fontSize: 20.sp,
                                        fontWeight: FontWeight.bold,
                                      ),
                                      textAlign: TextAlign.center,
                                    ),
                                    SizedBox(height: 8),
                                    Text(
                                      'Все магазины уже прошли пересменку для текущей смены',
                                      style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 14.sp),
                                      textAlign: TextAlign.center,
                                    ),
                                    SizedBox(height: 24),
                                    ElevatedButton(
                                      onPressed: () => Navigator.pop(context),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: AppColors.gold,
                                        foregroundColor: AppColors.night,
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(12.r),
                                        ),
                                      ),
                                      child: Text('Назад'),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          }

                          // Проверяем, активен ли интервал пересменки
                          if (_currentShiftType == null) {
                            return Center(
                              child: Padding(
                                padding: EdgeInsets.all(24.w),
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.timer_off, size: 64, color: AppColors.gold.withOpacity(0.8)),
                                    SizedBox(height: 16),
                                    Text(
                                      'Сейчас не время для пересменки',
                                      style: TextStyle(
                                        color: Colors.white.withOpacity(0.9),
                                        fontSize: 20.sp,
                                        fontWeight: FontWeight.bold,
                                      ),
                                      textAlign: TextAlign.center,
                                    ),
                                    SizedBox(height: 8),
                                    Text(
                                      'Пересменку можно пройти только в установленные временные интервалы',
                                      style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 14.sp),
                                      textAlign: TextAlign.center,
                                    ),
                                    SizedBox(height: 24),
                                    ElevatedButton(
                                      onPressed: () => Navigator.pop(context),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: AppColors.gold,
                                        foregroundColor: AppColors.night,
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(12.r),
                                        ),
                                      ),
                                      child: Text('Назад'),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          }

                          return ListView.builder(
                            padding: EdgeInsets.all(16.w),
                            itemCount: shops.length,
                            itemBuilder: (context, index) {
                              final shop = shops[index];
                              return Padding(
                                padding: EdgeInsets.only(bottom: 12.h),
                                child: Material(
                                  color: Colors.transparent,
                                  borderRadius: BorderRadius.circular(14.r),
                                  child: InkWell(
                                    borderRadius: BorderRadius.circular(14.r),
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
                                      padding: EdgeInsets.all(12.w),
                                      decoration: BoxDecoration(
                                        color: Colors.white.withOpacity(0.06),
                                        borderRadius: BorderRadius.circular(14.r),
                                        border: Border.all(
                                          color: Colors.white.withOpacity(0.1),
                                        ),
                                      ),
                                      child: Row(
                                        children: [
                                          ShopIcon(size: 56),
                                          SizedBox(width: 16),
                                          Expanded(
                                            child: Text(
                                              shop.address,
                                              style: TextStyle(
                                                fontSize: 16.sp,
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
