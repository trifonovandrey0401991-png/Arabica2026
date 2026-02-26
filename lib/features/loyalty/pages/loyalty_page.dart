import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/logger.dart';
import '../services/loyalty_service.dart';
import '../services/loyalty_storage.dart';
import '../services/loyalty_gamification_service.dart';
import '../models/loyalty_gamification_model.dart';
import '../widgets/qr_badges_widget.dart';
import 'loyalty_promo_management_page.dart';
import 'client_wheel_page.dart';
import 'pending_prize_page.dart';
import '../../employees/services/user_role_service.dart';
import 'drink_redemption_page.dart';
import '../../shop_catalog/pages/shop_catalog_page.dart';
import '../../employees/models/user_role_model.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

class LoyaltyPage extends StatefulWidget {
  const LoyaltyPage({super.key});

  @override
  State<LoyaltyPage> createState() => _LoyaltyPageState();
}

class _LoyaltyPageState extends State<LoyaltyPage> {
  LoyaltyInfo? _info;
  bool _loading = true;
  String? _error;
  bool _isAdmin = false;

  // Данные геймификации
  ClientGamificationData? _gamificationData;
  GamificationSettings? _gamificationSettings;
  ClientPrize? _pendingPrize; // Pending приз клиента

  @override
  void initState() {
    super.initState();
    _checkAdminRole();
    _loadInitial();
  }

  Future<void> _checkAdminRole() async {
    try {
      final roleData = await UserRoleService.loadUserRole();
      if (mounted) {
        setState(() {
          // Admin и Developer имеют доступ к настройкам
          _isAdmin = roleData?.role == UserRole.admin ||
                     roleData?.role == UserRole.developer;
        });
      }
    } catch (e) {
      Logger.error('Ошибка проверки роли', e);
    }
  }

  Future<void> _loadInitial() async {
    final prefs = await SharedPreferences.getInstance();
    final name = prefs.getString('user_name');
    final phone = prefs.getString('user_phone');

    if (name == null || phone == null) {
      if (mounted) {
        setState(() {
          _error = 'Не удалось прочитать данные клиента';
          _loading = false;
        });
      }
      return;
    }

    // Сначала показываем кэшированные данные (мгновенно, без спиннера)
    final cached = await LoyaltyStorage.read(name: name, phone: phone);
    if (cached != null && mounted) {
      if (mounted) setState(() {
        _info = cached;
        _loading = false;
      });
    }

    // Затем обновляем свежими данными с сервера (в фоне)
    await _refresh(showSpinner: cached == null);
  }

  Future<void> _refresh({bool showSpinner = true}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final phone = prefs.getString('user_phone');
      final name = prefs.getString('user_name');
      if (phone == null || name == null) {
        return;
      }

      if (showSpinner && mounted) {
        if (mounted) setState(() {
          _loading = true;
        });
      }

      // Запускаем все запросы параллельно (вместо последовательно)
      final infoFuture = LoyaltyService.fetchByPhone(phone);
      final settingsFuture = LoyaltyGamificationService.fetchSettings();
      final clientDataFuture = LoyaltyGamificationService.fetchClientData(phone);
      final prizeFuture = LoyaltyGamificationService.fetchPendingPrize(phone);

      final info = await infoFuture;
      await LoyaltyStorage.save(info);
      final gamificationSettings = await settingsFuture;
      final gamificationData = await clientDataFuture;
      final pendingPrize = await prizeFuture;

      if (mounted) {
        setState(() {
          _info = info;
          _gamificationSettings = gamificationSettings;
          _gamificationData = gamificationData;
          _pendingPrize = pendingPrize;
          _error = null;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        String errorMessage = 'Не удалось обновить данные';
        final errorString = e.toString().toLowerCase();

        if (errorString.contains('не найден') ||
            errorString.contains('not found') ||
            errorString.contains('клиент не найден')) {
          errorMessage = 'Клиент не найден в базе данных';
        } else if (errorString.contains('failed to fetch') ||
                   errorString.contains('connection') ||
                   errorString.contains('network')) {
          errorMessage = 'Ошибка подключения к серверу. Проверьте интернет-соединение.';
        } else if (errorString.contains('timeout')) {
          errorMessage = 'Превышено время ожидания. Попробуйте еще раз.';
        } else if (errorString.contains('ошибка сервера')) {
          errorMessage = 'Сервер временно недоступен. Попробуйте позже.';
        }

        if (mounted) setState(() {
          _error = errorMessage;
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final info = _info;

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
              _buildAppBar(),
              Expanded(
                child: _loading
                    ? Center(
                        child: CircularProgressIndicator(
                          color: Colors.white.withOpacity(0.8),
                        ),
                      )
                    : info == null
                        ? _errorMessage()
                        : RefreshIndicator(
                            onRefresh: _refresh,
                            color: AppColors.emerald,
                            child: SingleChildScrollView(
                              physics: AlwaysScrollableScrollPhysics(),
                              padding: EdgeInsets.fromLTRB(20.w, 8.h, 20.w, 20.h),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  _qrCard(info),
                                  // Баланс кошелька
                                  SizedBox(height: 16),
                                  _walletBalanceCard(info),
                                  // Две кнопки: Бесплатный напиток + В магазин
                                  SizedBox(height: 16),
                                  _actionButtonsRow(),
                                  // Уровень клиента
                                  if (_gamificationData != null) ...[
                                    SizedBox(height: 16),
                                    _levelCard(),
                                  ],
                                  // Карточка приза или Колесо удачи
                                  if (_gamificationSettings != null &&
                                      _gamificationSettings!.wheel.enabled &&
                                      _gamificationData != null) ...[
                                    SizedBox(height: 16),
                                    // Если есть pending приз - показываем карточку приза
                                    if (_pendingPrize != null)
                                      _pendingPrizeCard()
                                    else
                                      _wheelCard(),
                                  ],
                                  if (info.promoText.isNotEmpty) ...[
                                    SizedBox(height: 16),
                                    _promoCard(info.promoText),
                                  ],
                                ],
                              ),
                            ),
                          ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAppBar() {
    return Padding(
      padding: EdgeInsets.fromLTRB(8.w, 8.h, 8.w, 16.h),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.pop(context),
            icon: Icon(
              Icons.arrow_back_ios_new_rounded,
              color: Colors.white.withOpacity(0.8),
              size: 22,
            ),
          ),
          Expanded(
            child: Text(
              'Программа лояльности',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                fontSize: 20.sp,
                fontWeight: FontWeight.w400,
                letterSpacing: 1,
              ),
            ),
          ),
          if (_isAdmin)
            IconButton(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => LoyaltyPromoManagementPage(),
                  ),
                ).then((_) {
                  _refresh();
                });
              },
              icon: Icon(
                Icons.settings_outlined,
                color: Colors.white.withOpacity(0.8),
                size: 22,
              ),
              tooltip: 'Управление условиями акций',
            )
          else
            SizedBox(width: 48),
          IconButton(
            onPressed: () => _refresh(),
            icon: Icon(
              Icons.refresh_rounded,
              color: Colors.white.withOpacity(0.8),
              size: 22,
            ),
            tooltip: 'Обновить',
          ),
        ],
      ),
    );
  }

  Widget _errorMessage() {
    return Center(
      child: Padding(
        padding: EdgeInsets.all(24.w),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.error_outline_rounded,
              size: 64,
              color: Colors.white.withOpacity(0.5),
            ),
            SizedBox(height: 16),
            Text(
              _error ?? 'Данные не найдены',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 16.sp,
                color: Colors.white.withOpacity(0.7),
              ),
            ),
            SizedBox(height: 24),
            Material(
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(12.r),
              child: InkWell(
                onTap: () => _refresh(),
                borderRadius: BorderRadius.circular(12.r),
                splashColor: Colors.white.withOpacity(0.1),
                child: Container(
                  padding: EdgeInsets.symmetric(horizontal: 24.w, vertical: 12.h),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12.r),
                    border: Border.all(color: Colors.white.withOpacity(0.3)),
                  ),
                  child: Text(
                    'Повторить попытку',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.9),
                      fontSize: 15.sp,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _qrCard(LoyaltyInfo info) {
    // Получаем заработанные уровни для значков
    final earnedLevels = _gamificationData != null && _gamificationSettings != null
        ? _gamificationSettings!.levels
            .where((l) => _gamificationData!.earnedBadges.contains(l.id))
            .toList()
        : <LoyaltyLevel>[];

    final qrWidget = Container(
      padding: EdgeInsets.all(12.w),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12.r),
      ),
      child: QrImageView(
        data: info.qr,
        version: QrVersions.auto,
        size: 180,
      ),
    );

    return Container(
      padding: EdgeInsets.all(24.w),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16.r),
        border: Border.all(color: Colors.white.withOpacity(0.15)),
      ),
      child: Column(
        children: [
          Text(
            'Ваш QR-код',
            style: TextStyle(
              fontSize: 18.sp,
              fontWeight: FontWeight.w500,
              color: Colors.white.withOpacity(0.9),
            ),
          ),
          SizedBox(height: 72),
          // QR с значками вокруг
          if (earnedLevels.isNotEmpty)
            QrBadgesWidget(
              qrWidget: qrWidget,
              earnedLevels: earnedLevels,
            )
          else
            qrWidget,
          SizedBox(height: 72),
          Text(
            info.name,
            style: TextStyle(
              fontSize: 16.sp,
              fontWeight: FontWeight.w500,
              color: Colors.white.withOpacity(0.9),
            ),
          ),
          SizedBox(height: 4),
          Text(
            info.phone,
            style: TextStyle(
              fontSize: 14.sp,
              color: Colors.white.withOpacity(0.5),
            ),
          ),
        ],
      ),
    );
  }

  Widget _walletBalanceCard(LoyaltyInfo info) {
    return Container(
      padding: EdgeInsets.all(20.w),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16.r),
        border: Border.all(color: Color(0xFFD4AF37).withOpacity(0.4)),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFFD4AF37).withOpacity(0.15),
            Color(0xFFD4AF37).withOpacity(0.05),
          ],
        ),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFFD4AF37), Color(0xFFB8960C)],
                  ),
                  borderRadius: BorderRadius.circular(12.r),
                ),
                child: Icon(Icons.account_balance_wallet, color: Colors.white, size: 28),
              ),
              SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Ваши баллы',
                      style: TextStyle(
                        fontSize: 14.sp,
                        color: Colors.white.withOpacity(0.7),
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      '${info.loyaltyPoints}',
                      style: TextStyle(
                        fontSize: 32.sp,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFFD4AF37),
                      ),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    'Всего накоплено',
                    style: TextStyle(
                      fontSize: 11.sp,
                      color: Colors.white.withOpacity(0.5),
                    ),
                  ),
                  Text(
                    '${info.totalPointsEarned}',
                    style: TextStyle(
                      fontSize: 16.sp,
                      fontWeight: FontWeight.w500,
                      color: Colors.white.withOpacity(0.7),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _actionButtonsRow() {
    return Row(
      children: [
        // Кнопка «Бесплатный напиток»
        Expanded(
          child: GestureDetector(
            onTap: () {
              Navigator.push(context, MaterialPageRoute(builder: (_) => const DrinkRedemptionPage()));
            },
            child: Container(
              padding: EdgeInsets.all(16.w),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16.r),
                border: Border.all(color: Color(0xFFFF9800).withOpacity(0.4)),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color(0xFFFF9800).withOpacity(0.15),
                    Color(0xFFFF9800).withOpacity(0.05),
                  ],
                ),
              ),
              child: Column(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Color(0xFFFF9800), Color(0xFFE65100)],
                      ),
                      borderRadius: BorderRadius.circular(12.r),
                    ),
                    child: Icon(Icons.local_cafe, color: Colors.white, size: 28),
                  ),
                  SizedBox(height: 10),
                  Text(
                    'Бесплатный\nнапиток',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 13.sp,
                      fontWeight: FontWeight.w600,
                      color: Colors.white.withOpacity(0.9),
                      height: 1.2,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        SizedBox(width: 12),
        // Кнопка «В магазин»
        Expanded(
          child: GestureDetector(
            onTap: () {
              Navigator.push(context, MaterialPageRoute(builder: (_) => ShopCatalogPage()));
            },
            child: Container(
              padding: EdgeInsets.all(16.w),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16.r),
                border: Border.all(color: Color(0xFF4CAF50).withOpacity(0.4)),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color(0xFF4CAF50).withOpacity(0.15),
                    Color(0xFF4CAF50).withOpacity(0.05),
                  ],
                ),
              ),
              child: Column(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Color(0xFF4CAF50), Color(0xFF2E7D32)],
                      ),
                      borderRadius: BorderRadius.circular(12.r),
                    ),
                    child: Icon(Icons.storefront, color: Colors.white, size: 28),
                  ),
                  SizedBox(height: 10),
                  Text(
                    'В магазин',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 13.sp,
                      fontWeight: FontWeight.w600,
                      color: Colors.white.withOpacity(0.9),
                      height: 1.2,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _promoCard(String promoText) {
    return Container(
      padding: EdgeInsets.all(20.w),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16.r),
        border: Border.all(color: Colors.white.withOpacity(0.15)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.info_outline_rounded,
                color: Colors.white.withOpacity(0.7),
                size: 20,
              ),
              SizedBox(width: 8),
              Text(
                'Условия акции',
                style: TextStyle(
                  fontSize: 16.sp,
                  fontWeight: FontWeight.w500,
                  color: Colors.white.withOpacity(0.9),
                ),
              ),
            ],
          ),
          SizedBox(height: 12),
          Text(
            promoText,
            style: TextStyle(
              fontSize: 14.sp,
              color: Colors.white.withOpacity(0.7),
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  Widget _levelCard() {
    final data = _gamificationData!;
    final level = data.currentLevel;

    return Container(
      padding: EdgeInsets.all(20.w),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16.r),
        border: Border.all(color: level.color.withOpacity(0.4)),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            level.color.withOpacity(0.15),
            level.color.withOpacity(0.05),
          ],
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: level.color,
              borderRadius: BorderRadius.circular(12.r),
            ),
            child: Center(
              child: level.badge.type == 'icon'
                  ? Icon(
                      level.badge.getIcon() ?? Icons.workspace_premium,
                      color: Colors.white,
                      size: 28,
                    )
                  : Icon(
                      Icons.emoji_events,
                      color: Colors.white,
                      size: 28,
                    ),
            ),
          ),
          SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Уровень: ${level.name}',
                  style: TextStyle(
                    fontSize: 16.sp,
                    fontWeight: FontWeight.bold,
                    color: Colors.white.withOpacity(0.95),
                  ),
                ),
                SizedBox(height: 4),
                if (data.pointsToNextLevel != null && data.nextLevel != null)
                  Text(
                    'До "${data.nextLevel!.name}": ${data.pointsToNextLevel} баллов',
                    style: TextStyle(
                      fontSize: 13.sp,
                      color: Colors.white.withOpacity(0.7),
                    ),
                  )
                else
                  Text(
                    'Максимальный уровень!',
                    style: TextStyle(
                      fontSize: 13.sp,
                      color: Colors.amber.withOpacity(0.9),
                      fontStyle: FontStyle.italic,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _wheelCard() {
    final data = _gamificationData!;
    final settings = _gamificationSettings!;

    // Прогресс: сколько баллов собрано к следующей прокрутке
    final pointsPerSpin = settings.wheel.freeDrinksPerSpin * 10;
    final currentProgressPoints = pointsPerSpin - data.pointsToNextSpin;

    return GestureDetector(
      onTap: _openWheelPage,
      child: Container(
        padding: EdgeInsets.all(20.w),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16.r),
          border: Border.all(color: Color(0xFF8E2DE2).withOpacity(0.4)),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFF8E2DE2).withOpacity(0.15),
              Color(0xFF4A00E0).withOpacity(0.05),
            ],
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFF8E2DE2), Color(0xFF4A00E0)],
                ),
                borderRadius: BorderRadius.circular(12.r),
              ),
              child: Icon(
                Icons.casino,
                color: Colors.white,
                size: 28,
              ),
            ),
            SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Колесо удачи',
                    style: TextStyle(
                      fontSize: 16.sp,
                      fontWeight: FontWeight.bold,
                      color: Colors.white.withOpacity(0.95),
                    ),
                  ),
                  SizedBox(height: 4),
                  Text(
                    data.wheelSpinsAvailable > 0
                        ? 'Доступно прокруток: ${data.wheelSpinsAvailable}'
                        : 'До прокрутки: ${data.pointsToNextSpin} баллов ($currentProgressPoints/$pointsPerSpin)',
                    style: TextStyle(
                      fontSize: 13.sp,
                      color: data.wheelSpinsAvailable > 0
                          ? AppColors.success
                          : Colors.white.withOpacity(0.7),
                      fontWeight: data.wheelSpinsAvailable > 0
                          ? FontWeight.bold
                          : FontWeight.normal,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right,
              color: Colors.white.withOpacity(0.5),
              size: 24,
            ),
          ],
        ),
      ),
    );
  }

  void _openWheelPage() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ClientWheelPage(
          phone: _info!.phone,
          clientName: _info!.name,
          wheelSettings: _gamificationSettings!.wheel,
          spinsAvailable: _gamificationData!.wheelSpinsAvailable,
        ),
      ),
    ).then((_) => _refresh());
  }

  /// Карточка "Получить приз" (вместо колеса, когда есть pending приз)
  Widget _pendingPrizeCard() {
    final prize = _pendingPrize!;

    return GestureDetector(
      onTap: _openPrizePage,
      child: Container(
        padding: EdgeInsets.all(20.w),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16.r),
          border: Border.all(color: prize.prizeColor.withOpacity(0.5)),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              prize.prizeColor.withOpacity(0.25),
              prize.prizeColor.withOpacity(0.1),
            ],
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    prize.prizeColor,
                    prize.prizeColor.withOpacity(0.7),
                  ],
                ),
                borderRadius: BorderRadius.circular(12.r),
                boxShadow: [
                  BoxShadow(
                    color: prize.prizeColor.withOpacity(0.4),
                    blurRadius: 8,
                    offset: Offset(0, 4),
                  ),
                ],
              ),
              child: Icon(
                prize.prizeIcon,
                color: Colors.white,
                size: 28,
              ),
            ),
            SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Ваш приз!',
                    style: TextStyle(
                      fontSize: 16.sp,
                      fontWeight: FontWeight.bold,
                      color: Colors.white.withOpacity(0.95),
                    ),
                  ),
                  SizedBox(height: 4),
                  Text(
                    prize.prize,
                    style: TextStyle(
                      fontSize: 14.sp,
                      fontWeight: FontWeight.w500,
                      color: prize.prizeColor,
                    ),
                  ),
                  Text(
                    'Нажмите, чтобы получить',
                    style: TextStyle(
                      fontSize: 12.sp,
                      color: Colors.white.withOpacity(0.6),
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right,
              color: Colors.white.withOpacity(0.5),
              size: 24,
            ),
          ],
        ),
      ),
    );
  }

  void _openPrizePage() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => PendingPrizePage(prize: _pendingPrize!),
      ),
    ).then((_) => _refresh());
  }
}
