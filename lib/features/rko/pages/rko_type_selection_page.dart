import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'rko_amount_input_page.dart';
import '../../shops/models/shop_model.dart';
import '../../attendance/services/attendance_service.dart';
import '../../shift_handover/services/shift_handover_report_service.dart';
import '../../recount/services/recount_service.dart';
import '../../employees/pages/employees_page.dart';
import '../../../core/utils/logger.dart';

/// Страница выбора типа РКО
class RKOTypeSelectionPage extends StatefulWidget {
  const RKOTypeSelectionPage({super.key});

  @override
  State<RKOTypeSelectionPage> createState() => _RKOTypeSelectionPageState();
}

class _RKOTypeSelectionPageState extends State<RKOTypeSelectionPage> {
  static const _primaryColor = Color(0xFF004D40);

  List<Shop> _shops = [];
  bool _isLoadingShops = false;
  String? _employeeName;
  bool _isLoadingEmployee = true;

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
    setState(() => _isLoadingShops = true);
    try {
      _shops = await Shop.loadShopsFromGoogleSheets();
    } catch (e) {
      Logger.error('Ошибка загрузки магазинов', e);
    }
    if (mounted) setState(() => _isLoadingShops = false);
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
    if (mounted) setState(() => _isLoadingEmployee = false);
  }

  /// Открыть страницу выбора магазина для "ЗП после смены"
  Future<void> _openShopSelectionForShift() async {
    if (_shops.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Загрузка списка магазинов...'),
          backgroundColor: Colors.orange,
        ),
      );
      await _loadShops();
      if (_shops.isEmpty) return;
    }

    // Открываем страницу выбора магазина
    final selectedShop = await Navigator.push<Shop>(
      context,
      MaterialPageRoute(
        builder: (context) => _RKOShopSelectionPage(
          shops: _shops,
          primaryColor: _primaryColor,
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
      appBar: AppBar(
        title: const Text('РКО'),
        backgroundColor: _primaryColor,
        elevation: 0,
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              _primaryColor,
              _primaryColor.withOpacity(0.85),
            ],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                const SizedBox(height: 20),
                // Заголовок
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Column(
                    children: [
                      Container(
                        width: 70,
                        height: 70,
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Icon(
                          Icons.receipt_long_rounded,
                          size: 36,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'Расходный кассовый ордер',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Выберите тип выплаты',
                        style: TextStyle(
                          fontSize: 15,
                          color: Colors.white.withOpacity(0.8),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 32),
                // Карточка "ЗП после смены"
                _buildTypeCard(
                  context: context,
                  icon: Icons.access_time_rounded,
                  iconColor: Colors.orange,
                  title: 'ЗП после смены',
                  subtitle: 'Выплата за отработанную смену',
                  description: 'Оформить РКО на зарплату сотруднику после завершения рабочей смены',
                  onTap: _openShopSelectionForShift,
                ),
                const SizedBox(height: 16),
                // Карточка "ЗП за месяц"
                _buildTypeCard(
                  context: context,
                  icon: Icons.calendar_month_rounded,
                  iconColor: Colors.blue,
                  title: 'ЗП за месяц',
                  subtitle: 'Месячная выплата заработной платы',
                  description: 'Оформить РКО на зарплату сотруднику за весь расчётный месяц',
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const RKOAmountInputPage(
                          rkoType: 'ЗП за месяц',
                        ),
                      ),
                    );
                  },
                ),
                const Spacer(),
                // Подсказка внизу
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.info_outline_rounded,
                        color: Colors.white.withOpacity(0.7),
                        size: 22,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'После оформления РКО будет сформирован PDF документ',
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.white.withOpacity(0.7),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
              ],
            ),
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
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.15),
            blurRadius: 12,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(20),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                // Иконка
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: iconColor.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Icon(
                    icon,
                    size: 32,
                    color: iconColor,
                  ),
                ),
                const SizedBox(width: 16),
                // Текст
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF2D2D2D),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: iconColor,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        description,
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[600],
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                // Стрелка
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: _primaryColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    Icons.arrow_forward_ios_rounded,
                    color: _primaryColor,
                    size: 18,
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

  const _RKOShopSelectionPage({
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
    final yesterday = now.subtract(const Duration(hours: 24));
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
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 28),
            const SizedBox(width: 12),
            const Text('Внимание'),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Вы уверены что ваш выбор правильный?',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              const SizedBox(height: 16),
              const Text('За последние 24 часа у вас была активность на другом магазине:'),
              const SizedBox(height: 12),
              ...shopActivities.entries.map((entry) => Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.orange.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.orange.withOpacity(0.3)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.store, size: 18, color: Colors.orange[700]),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            entry.key,
                            style: TextStyle(fontWeight: FontWeight.bold, color: Colors.orange[800]),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    ...entry.value.map((a) => Padding(
                      padding: const EdgeInsets.only(left: 26),
                      child: Text(
                        '• ${a.type}',
                        style: TextStyle(fontSize: 13, color: Colors.grey[700]),
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
            child: const Text('Отмена'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: widget.primaryColor),
            child: const Text('Да, продолжить', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    return confirmed ?? false;
  }

  Future<void> _onShopTap(Shop shop) async {
    setState(() => _isValidating = true);

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
      appBar: AppBar(
        title: const Text('РКО'),
        backgroundColor: widget.primaryColor,
        elevation: 0,
      ),
      body: Stack(
        children: [
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  widget.primaryColor,
                  widget.primaryColor.withOpacity(0.85),
                ],
              ),
            ),
            child: SafeArea(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Заголовок
                  const Padding(
                    padding: EdgeInsets.fromLTRB(20, 16, 20, 16),
                    child: Text(
                      'Выберите магазин:',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ),

                  // Список магазинов
                  Expanded(
                    child: ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
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
              child: const Center(
                child: CircularProgressIndicator(color: Colors.white),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildShopCard(Shop shop) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: widget.primaryColor.withOpacity(0.6),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Colors.white.withOpacity(0.3),
          width: 1.5,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: _isValidating ? null : () => _onShopTap(shop),
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                // Иконка магазина
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.storefront_rounded,
                    color: Colors.white,
                    size: 28,
                  ),
                ),
                const SizedBox(width: 14),
                // Название магазина
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
                const SizedBox(width: 8),
                // Стрелка
                Icon(
                  Icons.chevron_right_rounded,
                  color: Colors.white.withOpacity(0.7),
                  size: 28,
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
