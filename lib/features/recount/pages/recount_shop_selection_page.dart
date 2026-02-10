import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/utils/logger.dart';
import '../../../core/widgets/shop_icon.dart';
import '../../shops/models/shop_model.dart';
import '../../shops/services/shop_service.dart';
import '../../shops/services/shop_products_service.dart';
import '../../efficiency/services/points_settings_service.dart';
import '../../efficiency/models/points_settings_model.dart';
import '../models/pending_recount_report_model.dart';
import '../services/pending_recount_service.dart';
import 'recount_questions_page.dart';

/// Страница выбора магазина для пересчета
class RecountShopSelectionPage extends StatefulWidget {
  const RecountShopSelectionPage({super.key});

  @override
  State<RecountShopSelectionPage> createState() => _RecountShopSelectionPageState();
}

class _RecountShopSelectionPageState extends State<RecountShopSelectionPage> {
  bool _isLoading = true;
  String? _employeeName;
  String? _employeePhone;
  Map<String, ShopSyncInfo> _shopsSyncInfo = {}; // Информация о синхронизации магазинов
  List<PendingRecountReport> _pendingRecounts = []; // Ожидающие пересчёты
  RecountPointsSettings? _recountSettings; // Настройки интервалов

  /// Таймаут для определения устаревших данных (5 минут)
  static const Duration _staleDataTimeout = Duration(minutes: 5);

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  /// Загрузить все данные параллельно
  Future<void> _loadData() async {
    // Запускаем все запросы параллельно
    await Future.wait([
      _loadEmployeeData(),
      _loadShopsWithProducts(),
      _loadPendingRecounts(),
      _loadRecountSettings(),
    ]);

    // Только после завершения всех запросов убираем loading
    setState(() {
      _isLoading = false;
    });
  }

  /// Загрузить pending пересчёты
  Future<void> _loadPendingRecounts() async {
    try {
      final pending = await PendingRecountService.getPendingReports();
      _pendingRecounts = pending;
      Logger.debug('📋 Ожидающие пересчёты: ${pending.length}');
    } catch (e) {
      Logger.error('Ошибка загрузки pending пересчётов', e);
    }
  }

  /// Загрузить настройки интервалов
  Future<void> _loadRecountSettings() async {
    try {
      final settings = await PointsSettingsService.getRecountPointsSettings();
      _recountSettings = settings;
    } catch (e) {
      Logger.error('Ошибка загрузки настроек пересчёта', e);
    }
  }

  /// Проверить есть ли pending пересчёт для магазина
  bool _hasPendingRecount(String shopAddress) {
    return _pendingRecounts.any((p) => p.shopAddress == shopAddress && p.status == 'pending');
  }

  /// Получить информацию о следующем интервале пересчёта
  String _getNextIntervalInfo() {
    final now = DateTime.now();
    final settings = _recountSettings;

    if (settings == null) {
      return 'Настройки не загружены';
    }

    // Парсим время начала интервалов
    final morningStart = _parseTime(settings.morningStartTime);
    final eveningStart = _parseTime(settings.eveningStartTime);
    final morningEnd = _parseTime(settings.morningEndTime);
    final eveningEnd = _parseTime(settings.eveningEndTime);

    final currentMinutes = now.hour * 60 + now.minute;
    final morningStartMinutes = morningStart.hour * 60 + morningStart.minute;
    final eveningStartMinutes = eveningStart.hour * 60 + eveningStart.minute;
    final morningEndMinutes = morningEnd.hour * 60 + morningEnd.minute;
    final eveningEndMinutes = eveningEnd.hour * 60 + eveningEnd.minute;

    String nextTime;
    int minutesUntil;

    if (currentMinutes < morningStartMinutes) {
      // До начала утреннего интервала
      nextTime = settings.morningStartTime;
      minutesUntil = morningStartMinutes - currentMinutes;
    } else if (currentMinutes >= morningStartMinutes && currentMinutes < morningEndMinutes) {
      // Внутри утреннего интервала
      return 'Сейчас утренний интервал (${settings.morningStartTime} - ${settings.morningEndTime})';
    } else if (currentMinutes < eveningStartMinutes) {
      // Между интервалами
      nextTime = settings.eveningStartTime;
      minutesUntil = eveningStartMinutes - currentMinutes;
    } else if (currentMinutes >= eveningStartMinutes && currentMinutes < eveningEndMinutes) {
      // Внутри вечернего интервала
      return 'Сейчас вечерний интервал (${settings.eveningStartTime} - ${settings.eveningEndTime})';
    } else {
      // После вечернего интервала - следующий утренний завтра
      nextTime = settings.morningStartTime;
      minutesUntil = (24 * 60 - currentMinutes) + morningStartMinutes;
    }

    final hours = minutesUntil ~/ 60;
    final mins = minutesUntil % 60;
    final untilStr = hours > 0 ? '$hours ч $mins мин' : '$mins мин';

    return 'Следующий интервал в $nextTime (через $untilStr)';
  }

  /// Парсить время из строки "HH:MM"
  TimeOfDay _parseTime(String timeStr) {
    final parts = timeStr.split(':');
    return TimeOfDay(
      hour: int.parse(parts[0]),
      minute: parts.length > 1 ? int.parse(parts[1]) : 0,
    );
  }

  /// Показать диалог "Нет активных пересчётов"
  void _showNoActiveRecountsDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.orange.withOpacity(0.2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.schedule, color: Colors.orange, size: 24),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                'Нет активных пересчётов',
                style: TextStyle(fontSize: 18),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Для этого магазина сейчас нет ожидающих пересчётов.',
              style: TextStyle(fontSize: 14),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(Icons.info_outline, color: Colors.blue, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _getNextIntervalInfo(),
                      style: const TextStyle(fontSize: 13, color: Colors.blue),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Понятно'),
          ),
        ],
      ),
    );
  }

  /// Загрузить список магазинов с синхронизированными товарами (DBF)
  Future<void> _loadShopsWithProducts() async {
    try {
      final syncedShops = await ShopProductsService.getShopsWithProducts();
      _shopsSyncInfo = {for (var s in syncedShops) s.shopId: s};
      Logger.debug('📦 Магазины с DBF товарами: ${_shopsSyncInfo.keys}');
    } catch (e) {
      Logger.error('Ошибка загрузки магазинов с товарами', e);
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
      return true; // Если нет данных о синхронизации, считаем устаревшими
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

  /// Загрузить данные сотрудника
  Future<void> _loadEmployeeData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      // Используем user_display_name (короткое имя "Андрей В") вместо user_name (полное имя)
      final employeeName = prefs.getString('user_display_name') ?? prefs.getString('user_name');
      // Проверяем оба ключа для телефона (userPhone для сотрудников, user_phone для клиентов)
      final employeePhone = prefs.getString('userPhone') ?? prefs.getString('user_phone');

      Logger.debug('Загружены данные: displayName=$employeeName, phone=${Logger.maskPhone(employeePhone)}');

      _employeeName = employeeName;
      _employeePhone = employeePhone;
    } catch (e) {
      Logger.error('Ошибка загрузки данных сотрудника', e);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Пересчет товаров'),
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
        child: _isLoading
            ? const Center(
                child: CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              )
            : _employeeName == null || _employeeName!.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24.0),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(
                            Icons.person_off,
                            size: 80,
                            color: Colors.orange,
                          ),
                          const SizedBox(height: 24),
                          const Text(
                            'Требуется авторизация',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 16),
                          const Text(
                            'Для начала пересчета необходимо войти в систему.',
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 16,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 32),
                          ElevatedButton.icon(
                            onPressed: () => Navigator.pop(context),
                            icon: const Icon(Icons.arrow_back),
                            label: const Text('Назад'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.white,
                              foregroundColor: const Color(0xFF004D40),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 32,
                                vertical: 16,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                : FutureBuilder<List<Shop>>(
                    future: ShopService.getShopsForCurrentUser(),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Center(
                          child: CircularProgressIndicator(
                            valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        );
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

                      return Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Padding(
                              padding: EdgeInsets.only(bottom: 16),
                              child: Text(
                                'Выберите магазин:',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            Expanded(
                              child: ListView.builder(
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
                                          // Проверяем есть ли pending пересчёт для магазина
                                          if (!_hasPendingRecount(shop.address)) {
                                            _showNoActiveRecountsDialog();
                                            return;
                                          }
                                          Navigator.push(
                                            context,
                                            MaterialPageRoute(
                                              builder: (context) => RecountQuestionsPage(
                                                employeeName: _employeeName!,
                                                shopAddress: shop.address,
                                                employeePhone: _employeePhone,
                                              ),
                                            ),
                                          );
                                        },
                                        child: Container(
                                          padding: const EdgeInsets.all(12),
                                          decoration: BoxDecoration(
                                            borderRadius: BorderRadius.circular(12),
                                            border: Border.all(
                                              color: _hasDbfData(shop.id)
                                                  ? (_isDbfDataStale(shop.id) ? Colors.red : Colors.green)
                                                  : Colors.white.withOpacity(0.5),
                                              width: _hasDbfData(shop.id) ? 3 : 2,
                                            ),
                                          ),
                                          child: Row(
                                            children: [
                                              const ShopIcon(size: 56),
                                              const SizedBox(width: 16),
                                              Expanded(
                                                child: Column(
                                                  crossAxisAlignment: CrossAxisAlignment.start,
                                                  children: [
                                                    Text(
                                                      shop.address,
                                                      style: const TextStyle(
                                                        fontSize: 16,
                                                        fontWeight: FontWeight.w600,
                                                        color: Colors.white,
                                                      ),
                                                      maxLines: 2,
                                                      overflow: TextOverflow.ellipsis,
                                                    ),
                                                    if (_hasDbfData(shop.id)) ...[
                                                      const SizedBox(height: 4),
                                                      Container(
                                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                                        decoration: BoxDecoration(
                                                          color: _isDbfDataStale(shop.id) ? Colors.red : Colors.green,
                                                          borderRadius: BorderRadius.circular(8),
                                                        ),
                                                        child: Row(
                                                          mainAxisSize: MainAxisSize.min,
                                                          children: [
                                                            Icon(
                                                              _isDbfDataStale(shop.id) ? Icons.warning : Icons.inventory_2,
                                                              color: Colors.white,
                                                              size: 12,
                                                            ),
                                                            const SizedBox(width: 4),
                                                            Text(
                                                              _isDbfDataStale(shop.id)
                                                                  ? 'DBF: ${_getTimeSinceSync(shop.id)}'
                                                                  : 'Остатки из DBF',
                                                              style: const TextStyle(
                                                                color: Colors.white,
                                                                fontSize: 11,
                                                                fontWeight: FontWeight.bold,
                                                              ),
                                                            ),
                                                          ],
                                                        ),
                                                      ),
                                                    ],
                                                    // Индикатор активного пересчёта
                                                    if (_hasPendingRecount(shop.address)) ...[
                                                      const SizedBox(height: 4),
                                                      Container(
                                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                                        decoration: BoxDecoration(
                                                          color: Colors.orange,
                                                          borderRadius: BorderRadius.circular(8),
                                                        ),
                                                        child: const Row(
                                                          mainAxisSize: MainAxisSize.min,
                                                          children: [
                                                            Icon(Icons.schedule, color: Colors.white, size: 12),
                                                            SizedBox(width: 4),
                                                            Text(
                                                              'Ожидает пересчёт',
                                                              style: TextStyle(
                                                                color: Colors.white,
                                                                fontSize: 11,
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
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
      ),
    );
  }
}
