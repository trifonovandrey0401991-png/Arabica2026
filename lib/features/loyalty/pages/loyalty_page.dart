import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/utils/logger.dart';
import '../services/loyalty_service.dart';
import '../services/loyalty_storage.dart';
import 'loyalty_promo_management_page.dart';
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
          _isAdmin = roleData?.role == UserRole.admin;
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

    // Сначала загружаем актуальные настройки акции с сервера
    final settings = await LoyaltyService.fetchPromoSettings();

    // Проверяем, изменились ли настройки - если да, очищаем локальный кэш
    final cachedPointsRequired = prefs.getInt('loyalty_points_required');
    final cachedDrinksToGive = prefs.getInt('loyalty_drinks_to_give');

    if (cachedPointsRequired != null && cachedDrinksToGive != null) {
      if (cachedPointsRequired != settings.pointsRequired ||
          cachedDrinksToGive != settings.drinksToGive) {
        // Настройки изменились - обновляем локальный кэш
        await prefs.setInt('loyalty_points_required', settings.pointsRequired);
        await prefs.setInt('loyalty_drinks_to_give', settings.drinksToGive);
      }
    }

    // Не показываем кэшированные данные - сразу загружаем с сервера
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

      final info = await LoyaltyService.fetchByPhone(phone);
      await LoyaltyStorage.save(info);

      if (mounted) {
        setState(() {
          _info = info;
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
          const SizedBox(height: 16),
          Container(
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
          ),
          const SizedBox(height: 16),
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
}
