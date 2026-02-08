import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
import '../../employees/models/user_role_model.dart';

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

  // ═══════════════════════════════════════════════════════════════
  // МИНИМАЛИСТИЧНАЯ ПАЛИТРА
  // ═══════════════════════════════════════════════════════════════
  static const Color _emerald = Color(0xFF1A4D4D);
  static const Color _emeraldDark = Color(0xFF0D2E2E);
  static const Color _night = Color(0xFF051515);

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
      setState(() {
        _error = 'Не удалось прочитать данные клиента';
        _loading = false;
      });
      return;
    }

    await _refresh(showSpinner: true);
  }

  Future<void> _refresh({bool showSpinner = true}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final phone = prefs.getString('user_phone');
      final name = prefs.getString('user_name');
      if (phone == null || name == null) {
        return;
      }

      if (showSpinner) {
        setState(() {
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

        setState(() {
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
                            color: _emerald,
                            child: SingleChildScrollView(
                              physics: const AlwaysScrollableScrollPhysics(),
                              padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  _qrCard(info),
                                  // Уровень клиента
                                  if (_gamificationData != null) ...[
                                    const SizedBox(height: 16),
                                    _levelCard(),
                                  ],
                                  // Карточка приза или Колесо удачи
                                  if (_gamificationSettings != null &&
                                      _gamificationSettings!.wheel.enabled &&
                                      _gamificationData != null) ...[
                                    const SizedBox(height: 16),
                                    // Если есть pending приз - показываем карточку приза
                                    if (_pendingPrize != null)
                                      _pendingPrizeCard()
                                    else
                                      _wheelCard(),
                                  ],
                                  const SizedBox(height: 16),
                                  _pointsCard(info),
                                  const SizedBox(height: 16),
                                  _freeDrinksCard(info),
                                  if (info.promoText.isNotEmpty) ...[
                                    const SizedBox(height: 16),
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
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 16),
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
          const Expanded(
            child: Text(
              'Программа лояльности',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                fontSize: 20,
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
                    builder: (context) => const LoyaltyPromoManagementPage(),
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
            const SizedBox(width: 48),
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
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.error_outline_rounded,
              size: 64,
              color: Colors.white.withOpacity(0.5),
            ),
            const SizedBox(height: 16),
            Text(
              _error ?? 'Данные не найдены',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 16,
                color: Colors.white.withOpacity(0.7),
              ),
            ),
            const SizedBox(height: 24),
            Material(
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(12),
              child: InkWell(
                onTap: () => _refresh(),
                borderRadius: BorderRadius.circular(12),
                splashColor: Colors.white.withOpacity(0.1),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.white.withOpacity(0.3)),
                  ),
                  child: Text(
                    'Повторить попытку',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.9),
                      fontSize: 15,
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
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: QrImageView(
        data: info.qr,
        version: QrVersions.auto,
        size: 180,
      ),
    );

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.15)),
      ),
      child: Column(
        children: [
          Text(
            'Ваш QR-код',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w500,
              color: Colors.white.withOpacity(0.9),
            ),
          ),
          const SizedBox(height: 72),
          // QR с значками вокруг
          if (earnedLevels.isNotEmpty)
            QrBadgesWidget(
              qrWidget: qrWidget,
              earnedLevels: earnedLevels,
            )
          else
            qrWidget,
          const SizedBox(height: 72),
          Text(
            info.name,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w500,
              color: Colors.white.withOpacity(0.9),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            info.phone,
            style: TextStyle(
              fontSize: 14,
              color: Colors.white.withOpacity(0.5),
            ),
          ),
        ],
      ),
    );
  }

  Widget _pointsCard(LoyaltyInfo info) {
    final pointsRequired = info.pointsRequired;
    final drinksToGive = info.drinksToGive;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.15)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Баллы',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w500,
                  color: Colors.white.withOpacity(0.9),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white.withOpacity(0.2)),
                ),
                child: Text(
                  '$pointsRequired + $drinksToGive',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: Colors.white.withOpacity(0.9),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'Собрано: ${info.points}/$pointsRequired',
            style: TextStyle(
              fontSize: 14,
              color: Colors.white.withOpacity(0.7),
            ),
          ),
          const SizedBox(height: 8),
          Container(
            height: 6,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(3),
              color: Colors.white.withOpacity(0.1),
            ),
            child: FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: pointsRequired > 0
                  ? (info.points.clamp(0, pointsRequired)) / pointsRequired
                  : 0.0,
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(3),
                  color: info.readyForRedeem
                      ? const Color(0xFFFF9800)
                      : Colors.white.withOpacity(0.7),
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          if (pointsRequired > 0)
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: List.generate(pointsRequired, (index) {
                final active = index < info.points;
                return Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: active
                        ? Colors.white.withOpacity(0.8)
                        : Colors.white.withOpacity(0.1),
                    border: Border.all(
                      color: Colors.white.withOpacity(active ? 0.9 : 0.2),
                    ),
                  ),
                  child: active
                      ? Icon(
                          Icons.star_rounded,
                          size: 14,
                          color: _emerald,
                        )
                      : null,
                );
              }),
            ),
          if (info.readyForRedeem)
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  color: const Color(0xFFFF9800).withOpacity(0.15),
                  border: Border.all(
                    color: const Color(0xFFFF9800).withOpacity(0.3),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.card_giftcard_outlined,
                      color: Color(0xFFFF9800),
                      size: 22,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Баллов достаточно для $drinksToGive бесплатн${drinksToGive > 1 ? "ых напитков" : "ого напитка"}. Покажите код сотруднику.',
                        style: const TextStyle(
                          color: Color(0xFFFF9800),
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _freeDrinksCard(LoyaltyInfo info) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.15)),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              color: Colors.white.withOpacity(0.1),
            ),
            child: Icon(
              Icons.local_cafe_outlined,
              color: Colors.white.withOpacity(0.8),
              size: 24,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Бесплатные напитки',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    color: Colors.white.withOpacity(0.9),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Выдано: ${info.freeDrinks}',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.white.withOpacity(0.6),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _promoCard(String promoText) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
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
              const SizedBox(width: 8),
              Text(
                'Условия акции',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  color: Colors.white.withOpacity(0.9),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            promoText,
            style: TextStyle(
              fontSize: 14,
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
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
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
              borderRadius: BorderRadius.circular(12),
            ),
            child: Center(
              child: level.badge.type == 'icon'
                  ? Icon(
                      level.badge.getIcon() ?? Icons.workspace_premium,
                      color: Colors.white,
                      size: 28,
                    )
                  : const Icon(
                      Icons.emoji_events,
                      color: Colors.white,
                      size: 28,
                    ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Уровень: ${level.name}',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.white.withOpacity(0.95),
                  ),
                ),
                const SizedBox(height: 4),
                if (data.drinksToNextLevel != null && data.nextLevel != null)
                  Text(
                    'До "${data.nextLevel!.name}": ${data.drinksToNextLevel} напитков',
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.white.withOpacity(0.7),
                    ),
                  )
                else
                  Text(
                    'Максимальный уровень!',
                    style: TextStyle(
                      fontSize: 13,
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

    // Прогресс: сколько напитков собрано к следующей прокрутке
    final currentProgress = settings.wheel.freeDrinksPerSpin - data.drinksToNextSpin;

    return GestureDetector(
      onTap: _openWheelPage,
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFF8E2DE2).withOpacity(0.4)),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              const Color(0xFF8E2DE2).withOpacity(0.15),
              const Color(0xFF4A00E0).withOpacity(0.05),
            ],
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF8E2DE2), Color(0xFF4A00E0)],
                ),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(
                Icons.casino,
                color: Colors.white,
                size: 28,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Колесо удачи',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.white.withOpacity(0.95),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    data.wheelSpinsAvailable > 0
                        ? 'Доступно прокруток: ${data.wheelSpinsAvailable}'
                        : 'До прокрутки: ${data.drinksToNextSpin} напитков ($currentProgress/${settings.wheel.freeDrinksPerSpin})',
                    style: TextStyle(
                      fontSize: 13,
                      color: data.wheelSpinsAvailable > 0
                          ? const Color(0xFF4CAF50)
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
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
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
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: prize.prizeColor.withOpacity(0.4),
                    blurRadius: 8,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Icon(
                prize.prizeIcon,
                color: Colors.white,
                size: 28,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Ваш приз!',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.white.withOpacity(0.95),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    prize.prize,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: prize.prizeColor,
                    ),
                  ),
                  Text(
                    'Нажмите, чтобы получить',
                    style: TextStyle(
                      fontSize: 12,
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
