import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/utils/logger.dart';
import '../../shops/models/shop_model.dart';
import '../../shops/services/shop_service.dart';
import '../../shops/services/shop_products_service.dart';
import '../../efficiency/services/points_settings_service.dart';
import '../../efficiency/models/points_settings_model.dart';
import '../models/pending_recount_report_model.dart';
import '../services/pending_recount_service.dart';
import '../../ai_training/services/cigarette_vision_service.dart';
import 'recount_questions_page.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../../core/theme/app_colors.dart';

/// Страница выбора магазина для пересчета
class RecountShopSelectionPage extends StatefulWidget {
  const RecountShopSelectionPage({super.key});

  @override
  State<RecountShopSelectionPage> createState() => _RecountShopSelectionPageState();
}

class _RecountShopSelectionPageState extends State<RecountShopSelectionPage> {
  bool _isLoading = true;
  String? _errorMessage;
  String? _employeeName;
  String? _employeePhone;
  List<Shop> _shops = [];
  Map<String, ShopSyncInfo> _shopsSyncInfo = {}; // Информация о синхронизации магазинов
  List<PendingRecountReport> _pendingRecounts = []; // Ожидающие пересчёты
  RecountPointsSettings? _recountSettings; // Настройки интервалов
  bool _isAiModelTrained = false; // Обучена ли модель ИИ

  /// Таймаут для определения устаревших данных (5 минут)
  static final Duration _staleDataTimeout = Duration(minutes: 5);

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
      _loadShops(),
      _loadShopsWithProducts(),
      _loadPendingRecounts(),
      _loadRecountSettings(),
    ]);

    // Статус ИИ — не блокируем основную загрузку
    try {
      _isAiModelTrained = await CigaretteVisionService.isModelTrained();
    } catch (e) {
      debugPrint('[RecountShopSelection] Не удалось проверить статус ИИ: $e');
    }

    if (mounted) {
      setState(() {
        _isLoading = false;
      });
    }
  }

  /// Загрузить магазины
  Future<void> _loadShops() async {
    try {
      _shops = await ShopService.getShopsForCurrentUser();
      Logger.debug('🏪 Магазины загружены: ${_shops.length}');
    } catch (e) {
      Logger.error('Ошибка загрузки магазинов', e);
      _errorMessage = 'Не удалось загрузить магазины';
    }
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
        backgroundColor: Color(0xFF1A3A3A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16.r)),
        title: Row(
          children: [
            Container(
              padding: EdgeInsets.all(8.w),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Colors.orange.withOpacity(0.3), Colors.orange.withOpacity(0.15)],
                ),
                borderRadius: BorderRadius.circular(10.r),
              ),
              child: Icon(Icons.schedule, color: AppColors.gold, size: 24),
            ),
            SizedBox(width: 12),
            Expanded(
              child: Text(
                'Нет активных пересчётов',
                style: TextStyle(fontSize: 17.sp, color: Colors.white, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Для этого магазина сейчас нет ожидающих пересчётов.',
              style: TextStyle(fontSize: 14.sp, color: Colors.white.withOpacity(0.8)),
            ),
            SizedBox(height: 16),
            Container(
              padding: EdgeInsets.all(12.w),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.06),
                borderRadius: BorderRadius.circular(10.r),
                border: Border.all(color: AppColors.gold.withOpacity(0.3)),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline, color: AppColors.gold, size: 20),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _getNextIntervalInfo(),
                      style: TextStyle(fontSize: 13.sp, color: AppColors.gold),
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
            style: TextButton.styleFrom(foregroundColor: AppColors.gold),
            child: Text('Понятно'),
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
          SizedBox(width: 12.w),
          Container(
            padding: EdgeInsets.all(8.w),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [AppColors.gold.withOpacity(0.3), AppColors.gold.withOpacity(0.1)],
              ),
              borderRadius: BorderRadius.circular(10.r),
            ),
            child: Icon(Icons.inventory, color: AppColors.gold, size: 22),
          ),
          SizedBox(width: 10.w),
          Expanded(
            child: Text(
              'Пересчёт товаров',
              style: TextStyle(color: Colors.white, fontSize: 18.sp, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildShopCard(Shop shop) {
    final hasPending = _hasPendingRecount(shop.address);
    final hasDbf = _hasDbfData(shop.id);
    final isStale = hasDbf && _isDbfDataStale(shop.id);

    return Padding(
      padding: EdgeInsets.only(bottom: 12.h),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(14.r),
        child: InkWell(
          borderRadius: BorderRadius.circular(14.r),
          onTap: () {
            if (!hasPending) {
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
            padding: EdgeInsets.all(14.w),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(hasPending ? 0.08 : 0.04),
              borderRadius: BorderRadius.circular(14.r),
              border: Border.all(
                color: hasPending
                    ? AppColors.gold.withOpacity(0.4)
                    : Colors.white.withOpacity(0.08),
              ),
            ),
            child: Row(
              children: [
                // Иконка магазина
                Container(
                  width: 48.w,
                  height: 48.w,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: hasPending
                          ? [AppColors.gold.withOpacity(0.25), AppColors.gold.withOpacity(0.1)]
                          : [Colors.white.withOpacity(0.1), Colors.white.withOpacity(0.04)],
                    ),
                    borderRadius: BorderRadius.circular(12.r),
                  ),
                  child: Icon(
                    Icons.store,
                    color: hasPending ? AppColors.gold : Colors.white.withOpacity(0.5),
                    size: 24,
                  ),
                ),
                SizedBox(width: 14.w),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        shop.address,
                        style: TextStyle(
                          fontSize: 15.sp,
                          fontWeight: FontWeight.w600,
                          color: Colors.white.withOpacity(0.9),
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      SizedBox(height: 6.h),
                      Row(
                        children: [
                          // DBF бейдж
                          if (hasDbf) ...[
                            _buildBadge(
                              icon: isStale ? Icons.warning_amber_rounded : Icons.check_circle_outline,
                              text: isStale
                                  ? 'DBF: ${_getTimeSinceSync(shop.id)}'
                                  : 'DBF актуален',
                              color: isStale ? Colors.redAccent : Colors.green,
                            ),
                            SizedBox(width: 6.w),
                          ],
                          // AI-статус бейдж (только если есть DBF данные)
                          if (hasDbf) ...[
                            _buildBadge(
                              icon: _isAiModelTrained
                                  ? Icons.smart_toy
                                  : Icons.smart_toy_outlined,
                              text: _isAiModelTrained ? 'ИИ активен' : 'ИИ обучается',
                              color: _isAiModelTrained ? Colors.blue[300]! : Colors.orange,
                            ),
                            SizedBox(width: 6.w),
                          ],
                          // Pending бейдж
                          if (hasPending)
                            _buildBadge(
                              icon: Icons.schedule,
                              text: 'Ожидает',
                              color: AppColors.gold,
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_right,
                  color: hasPending ? AppColors.gold.withOpacity(0.7) : Colors.white.withOpacity(0.3),
                  size: 24,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBadge({
    required IconData icon,
    required String text,
    required Color color,
  }) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 7.w, vertical: 3.h),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(6.r),
        border: Border.all(color: color.withOpacity(0.3), width: 0.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 11),
          SizedBox(width: 3.w),
          Text(
            text,
            style: TextStyle(
              color: color,
              fontSize: 10.sp,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState({
    required IconData icon,
    required String title,
    required String subtitle,
    Color? iconColor,
  }) {
    return Center(
      child: Padding(
        padding: EdgeInsets.all(32.w),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: EdgeInsets.all(20.w),
              decoration: BoxDecoration(
                color: (iconColor ?? AppColors.gold).withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 48, color: (iconColor ?? AppColors.gold).withOpacity(0.7)),
            ),
            SizedBox(height: 20.h),
            Text(
              title,
              style: TextStyle(
                color: Colors.white.withOpacity(0.9),
                fontSize: 18.sp,
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.center,
            ),
            SizedBox(height: 8.h),
            Text(
              subtitle,
              style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 14.sp),
              textAlign: TextAlign.center,
            ),
            SizedBox(height: 24.h),
            TextButton.icon(
              onPressed: () => Navigator.pop(context),
              icon: Icon(Icons.arrow_back, size: 18),
              label: Text('Назад'),
              style: TextButton.styleFrom(
                foregroundColor: AppColors.gold,
                padding: EdgeInsets.symmetric(horizontal: 24.w, vertical: 12.h),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_employeeName == null || _employeeName!.isEmpty) {
      return _buildEmptyState(
        icon: Icons.person_off_outlined,
        title: 'Требуется авторизация',
        subtitle: 'Для начала пересчёта необходимо войти в систему.',
        iconColor: Colors.orange,
      );
    }

    if (_errorMessage != null && _shops.isEmpty) {
      return _buildEmptyState(
        icon: Icons.cloud_off_outlined,
        title: 'Ошибка загрузки',
        subtitle: _errorMessage!,
        iconColor: Colors.redAccent,
      );
    }

    if (_shops.isEmpty) {
      return _buildEmptyState(
        icon: Icons.store_outlined,
        title: 'Магазины не найдены',
        subtitle: 'Нет доступных магазинов для пересчёта.',
      );
    }

    // Показываем только магазины с pending отчётами
    final pendingShops = _shops.where((s) => _hasPendingRecount(s.address)).toList();

    if (pendingShops.isEmpty) {
      return _buildEmptyState(
        icon: Icons.check_circle_outline,
        title: 'Нет ожидающих пересчётов',
        subtitle: _getNextIntervalInfo(),
        iconColor: Colors.green,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Информационная панель
        Padding(
          padding: EdgeInsets.fromLTRB(16.w, 12.h, 16.w, 4.h),
          child: Container(
            padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 10.h),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.05),
              borderRadius: BorderRadius.circular(12.r),
              border: Border.all(color: Colors.white.withOpacity(0.06)),
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline, color: AppColors.gold.withOpacity(0.7), size: 18),
                SizedBox(width: 10.w),
                Expanded(
                  child: Text(
                    'Ожидают пересчёт: ${pendingShops.length}',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.6),
                      fontSize: 13.sp,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        // Список магазинов
        Expanded(
          child: ListView.builder(
            padding: EdgeInsets.fromLTRB(16.w, 8.h, 16.w, 16.h),
            itemCount: pendingShops.length,
            itemBuilder: (context, index) {
              return _buildShopCard(pendingShops[index]);
            },
          ),
        ),
      ],
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
                child: _isLoading
                    ? Center(child: CircularProgressIndicator(color: AppColors.gold))
                    : _buildBody(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
