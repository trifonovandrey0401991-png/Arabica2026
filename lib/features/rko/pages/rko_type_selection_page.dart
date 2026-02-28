import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'rko_amount_input_page.dart';
import '../../shops/models/shop_model.dart';
import '../../shops/services/shop_service.dart';
import '../../attendance/services/attendance_service.dart';
import '../../shift_handover/services/shift_handover_report_service.dart';
import '../../recount/services/recount_service.dart';
import '../../employees/pages/employees_page.dart';
import '../../../core/utils/logger.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../../core/theme/app_colors.dart';

/// Страница выбора типа РКО
class RKOTypeSelectionPage extends StatefulWidget {
  const RKOTypeSelectionPage({super.key});

  @override
  State<RKOTypeSelectionPage> createState() => _RKOTypeSelectionPageState();
}

class _RKOTypeSelectionPageState extends State<RKOTypeSelectionPage> {
  List<Shop> _shops = [];
  String? _employeeName;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    await Future.wait([
      _loadShops(),
      _loadEmployeeName(),
    ]);
  }

  Future<void> _loadShops() async {
    try {
      _shops = await ShopService.getShopsForCurrentUser();
    } catch (e) {
      Logger.error('Ошибка загрузки магазинов', e);
    }
    if (mounted) setState(() {});
  }

  Future<void> _loadEmployeeName() async {
    try {
      final employees = await EmployeesPage.loadEmployeesForNotifications();
      final prefs = await SharedPreferences.getInstance();
      final phone = prefs.getString('userPhone') ?? prefs.getString('user_phone');

      if (phone != null && employees.isNotEmpty) {
        final normalizedPhone = phone.replaceAll(RegExp(r'[\s\+]'), '');
        final currentEmployee = employees.firstWhere(
          (e) => e.phone != null && e.phone!.replaceAll(RegExp(r'[\s\+]'), '') == normalizedPhone,
          orElse: () => employees.first,
        );
        _employeeName = currentEmployee.name;
      } else {
        _employeeName = await EmployeesPage.getCurrentEmployeeName();
      }
    } catch (e) {
      Logger.error('Ошибка загрузки имени сотрудника', e);
    }
    if (mounted) setState(() {});
  }

  /// Открыть страницу выбора магазина для "ЗП после смены"
  Future<void> _openShopSelectionForShift() async {
    if (_shops.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Загрузка списка магазинов...'),
          backgroundColor: Colors.orange,
        ),
      );
      await _loadShops();
      if (_shops.isEmpty) return;
    }

    // Открываем страницу выбора магазина
    if (!mounted) return;
    final selectedShop = await Navigator.push<Shop>(
      context,
      MaterialPageRoute(
        builder: (context) => _RKOShopSelectionPage(
          shops: _shops,
          primaryColor: AppColors.primaryGreen,
          employeeName: _employeeName,
        ),
      ),
    );

    if (selectedShop != null && mounted) {
      // Переходим к странице РКО с выбранным магазином
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => RKOAmountInputPage(
            rkoType: 'ЗП после смены',
            preselectedShop: selectedShop,
          ),
        ),
      );
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
              AppColors.emerald,
              AppColors.emeraldDark,
              AppColors.night,
            ],
            stops: [0.0, 0.5, 1.0],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              // Кастомный хедер
              Padding(
                padding: EdgeInsets.fromLTRB(8.w, 8.h, 20.w, 0),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: Icon(Icons.arrow_back, color: Colors.white),
                    ),
                    Expanded(
                      child: Text(
                        'РКО',
                        style: TextStyle(
                          fontSize: 20.sp,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    SizedBox(width: 48),
                  ],
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: EdgeInsets.all(20.w),
                  child: Column(
                    children: [
                      SizedBox(height: 12),
                      // Заголовок с золотой иконкой
                      Container(
                        padding: EdgeInsets.all(20.w),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.06),
                          borderRadius: BorderRadius.circular(20.r),
                          border: Border.all(
                            color: AppColors.gold.withOpacity(0.3),
                          ),
                        ),
                        child: Column(
                          children: [
                            Container(
                              width: 70,
                              height: 70,
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [
                                    AppColors.gold.withOpacity(0.3),
                                    AppColors.darkGold.withOpacity(0.2),
                                  ],
                                ),
                                borderRadius: BorderRadius.circular(20.r),
                              ),
                              child: Icon(
                                Icons.receipt_long_rounded,
                                size: 36,
                                color: AppColors.gold,
                              ),
                            ),
                            SizedBox(height: 16),
                            Text(
                              'Расходный кассовый ордер',
                              style: TextStyle(
                                fontSize: 20.sp,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                              textAlign: TextAlign.center,
                            ),
                            SizedBox(height: 8),
                            Text(
                              'Выберите тип выплаты',
                              style: TextStyle(
                                fontSize: 15.sp,
                                color: Colors.white.withOpacity(0.6),
                              ),
                            ),
                          ],
                        ),
                      ),
                      SizedBox(height: 28),
                      // Карточка "ЗП после смены"
                      _buildTypeCard(
                        context: context,
                        icon: Icons.access_time_rounded,
                        iconColor: AppColors.gold,
                        title: 'ЗП после смены',
                        subtitle: 'Выплата за отработанную смену',
                        description: 'Оформить РКО на зарплату сотруднику после завершения рабочей смены',
                        onTap: _openShopSelectionForShift,
                      ),
                      SizedBox(height: 14),
                      // Карточка "ЗП за месяц"
                      _buildTypeCard(
                        context: context,
                        icon: Icons.calendar_month_rounded,
                        iconColor: AppColors.turquoise,
                        title: 'ЗП за месяц',
                        subtitle: 'Месячная выплата заработной платы',
                        description: 'Оформить РКО на зарплату сотруднику за весь расчётный месяц',
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => RKOAmountInputPage(
                                rkoType: 'ЗП за месяц',
                              ),
                            ),
                          );
                        },
                      ),
                      SizedBox(height: 28),
                      // Подсказка внизу
                      Container(
                        padding: EdgeInsets.all(14.w),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.06),
                          borderRadius: BorderRadius.circular(14.r),
                          border: Border.all(
                            color: Colors.white.withOpacity(0.1),
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.info_outline_rounded,
                              color: AppColors.gold.withOpacity(0.7),
                              size: 22,
                            ),
                            SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                'После оформления РКО будет сформирован PDF документ',
                                style: TextStyle(
                                  fontSize: 13.sp,
                                  color: Colors.white.withOpacity(0.5),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      SizedBox(height: 10),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTypeCard({
    required BuildContext context,
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required String description,
    required VoidCallback onTap,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.07),
        borderRadius: BorderRadius.circular(18.r),
        border: Border.all(
          color: iconColor.withOpacity(0.3),
          width: 1.5,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(18.r),
          child: Padding(
            padding: EdgeInsets.all(18.w),
            child: Row(
              children: [
                // Иконка
                Container(
                  width: 60,
                  height: 60,
                  decoration: BoxDecoration(
                    color: iconColor.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(16.r),
                  ),
                  child: Icon(
                    icon,
                    size: 30,
                    color: iconColor,
                  ),
                ),
                SizedBox(width: 14),
                // Текст
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontSize: 17.sp,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: TextStyle(
                          fontSize: 13.sp,
                          fontWeight: FontWeight.w500,
                          color: iconColor,
                        ),
                      ),
                      SizedBox(height: 6),
                      Text(
                        description,
                        style: TextStyle(
                          fontSize: 12.sp,
                          color: Colors.white.withOpacity(0.45),
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                SizedBox(width: 8),
                // Стрелка
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: iconColor.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(12.r),
                  ),
                  child: Icon(
                    Icons.arrow_forward_ios_rounded,
                    color: iconColor,
                    size: 16,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Страница выбора магазина для РКО
class _RKOShopSelectionPage extends StatefulWidget {
  final List<Shop> shops;
  final Color primaryColor;
  final String? employeeName;

  _RKOShopSelectionPage({
    required this.shops,
    required this.primaryColor,
    this.employeeName,
  });

  @override
  State<_RKOShopSelectionPage> createState() => _RKOShopSelectionPageState();
}

class _RKOShopSelectionPageState extends State<_RKOShopSelectionPage> {
  bool _isValidating = false;

  /// Получить список магазинов где была активность сотрудника за последние 24 часа
  Future<List<_ActivityRecord>> _getRecentActivityShops() async {
    if (widget.employeeName == null) return [];

    final now = DateTime.now();
    final yesterday = now.subtract(Duration(hours: 24));
    final activities = <_ActivityRecord>[];

    try {
      // 1. Проверяем отметки "Я на работе"
      final attendanceRecords = await AttendanceService.getAttendanceRecords(
        employeeName: widget.employeeName,
      );
      for (final record in attendanceRecords) {
        if (record.timestamp.isAfter(yesterday)) {
          activities.add(_ActivityRecord(
            shopAddress: record.shopAddress,
            type: 'Отметка "Я на работе"',
            timestamp: record.timestamp,
          ));
        }
      }

      // 2. Проверяем пересменки
      final shiftReports = await ShiftHandoverReportService.getReports(
        employeeName: widget.employeeName,
      );
      for (final report in shiftReports) {
        if (report.createdAt.isAfter(yesterday)) {
          activities.add(_ActivityRecord(
            shopAddress: report.shopAddress,
            type: 'Пересменка',
            timestamp: report.createdAt,
          ));
        }
      }

      // 3. Проверяем пересчёты
      final recountReports = await RecountService.getReports(
        employeeName: widget.employeeName,
      );
      for (final report in recountReports) {
        if (report.completedAt.isAfter(yesterday)) {
          activities.add(_ActivityRecord(
            shopAddress: report.shopAddress,
            type: 'Пересчёт',
            timestamp: report.completedAt,
          ));
        }
      }
    } catch (e) {
      Logger.error('Ошибка получения активности', e);
    }

    return activities;
  }

  /// Проверить выбор магазина и показать предупреждение если нужно
  Future<bool> _validateShopSelection(Shop selectedShop) async {
    final activities = await _getRecentActivityShops();

    if (activities.isEmpty) return true; // Нет активности — разрешаем

    // Находим активности НЕ на выбранном магазине
    final otherShopActivities = activities.where(
      (a) => a.shopAddress.toLowerCase().trim() != selectedShop.address.toLowerCase().trim()
    ).toList();

    if (otherShopActivities.isEmpty) return true; // Вся активность на выбранном магазине

    // Группируем по магазинам
    final shopActivities = <String, List<_ActivityRecord>>{};
    for (final activity in otherShopActivities) {
      shopActivities.putIfAbsent(activity.shopAddress, () => []).add(activity);
    }

    // Показываем диалог
    if (!mounted) return false;
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 28),
            SizedBox(width: 12),
            Text('Внимание'),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Вы уверены что ваш выбор правильный?',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16.sp),
              ),
              SizedBox(height: 16),
              Text('За последние 24 часа у вас была активность на другом магазине:'),
              SizedBox(height: 12),
              ...shopActivities.entries.map((entry) => Container(
                margin: EdgeInsets.only(bottom: 8.h),
                padding: EdgeInsets.all(12.w),
                decoration: BoxDecoration(
                  color: Colors.orange.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8.r),
                  border: Border.all(color: Colors.orange.withOpacity(0.3)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.store, size: 18, color: Colors.orange[700]),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            entry.key,
                            style: TextStyle(fontWeight: FontWeight.bold, color: Colors.orange[800]),
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: 4),
                    ...entry.value.map((a) => Padding(
                      padding: EdgeInsets.only(left: 26.w),
                      child: Text(
                        '• ${a.type}',
                        style: TextStyle(fontSize: 13.sp, color: Colors.grey[700]),
                      ),
                    )),
                  ],
                ),
              )),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Отмена'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: widget.primaryColor),
            child: Text('Да, продолжить', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    return confirmed ?? false;
  }

  Future<void> _onShopTap(Shop shop) async {
    if (mounted) setState(() => _isValidating = true);

    try {
      final confirmed = await _validateShopSelection(shop);
      if (confirmed && mounted) {
        Navigator.pop(context, shop);
      }
    } finally {
      if (mounted) {
        setState(() => _isValidating = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  AppColors.emerald,
                  AppColors.emeraldDark,
                  AppColors.night,
                ],
                stops: [0.0, 0.5, 1.0],
              ),
            ),
            child: SafeArea(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Кастомный хедер
                  Padding(
                    padding: EdgeInsets.fromLTRB(8.w, 8.h, 20.w, 0),
                    child: Row(
                      children: [
                        IconButton(
                          onPressed: () => Navigator.pop(context),
                          icon: Icon(Icons.arrow_back, color: Colors.white),
                        ),
                        Expanded(
                          child: Text(
                            'Выберите магазин',
                            style: TextStyle(
                              fontSize: 20.sp,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                        SizedBox(width: 48),
                      ],
                    ),
                  ),
                  SizedBox(height: 8.h),

                  // Список магазинов
                  Expanded(
                    child: ListView.builder(
                      padding: EdgeInsets.symmetric(horizontal: 16.w),
                      itemCount: widget.shops.length,
                      itemBuilder: (context, index) {
                        final shop = widget.shops[index];
                        return _buildShopCard(shop);
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
          // Индикатор загрузки
          if (_isValidating)
            Container(
              color: Colors.black.withOpacity(0.3),
              child: Center(
                child: CircularProgressIndicator(color: AppColors.gold),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildShopCard(Shop shop) {
    return Container(
      margin: EdgeInsets.only(bottom: 12.h),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.07),
        borderRadius: BorderRadius.circular(16.r),
        border: Border.all(
          color: AppColors.gold.withOpacity(0.2),
          width: 1.5,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: _isValidating ? null : () => _onShopTap(shop),
          borderRadius: BorderRadius.circular(16.r),
          child: Padding(
            padding: EdgeInsets.all(16.w),
            child: Row(
              children: [
                // Иконка магазина
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: AppColors.gold.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(14.r),
                  ),
                  child: Icon(
                    Icons.storefront_rounded,
                    color: AppColors.gold,
                    size: 26,
                  ),
                ),
                SizedBox(width: 14),
                // Название магазина
                Expanded(
                  child: Text(
                    shop.address,
                    style: TextStyle(
                      fontSize: 15.sp,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                SizedBox(width: 8),
                // Стрелка
                Icon(
                  Icons.chevron_right_rounded,
                  color: AppColors.gold.withOpacity(0.5),
                  size: 26,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Запись об активности сотрудника
class _ActivityRecord {
  final String shopAddress;
  final String type;
  final DateTime timestamp;

  _ActivityRecord({
    required this.shopAddress,
    required this.type,
    required this.timestamp,
  });
}
