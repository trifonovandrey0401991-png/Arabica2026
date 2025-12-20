import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'loyalty_service.dart';
import 'loyalty_storage.dart';
import 'loyalty_promo_management_page.dart';
import 'user_role_service.dart';
import 'user_role_model.dart';
import 'loyalty_cup_widget.dart';

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
      print('Ошибка проверки роли: $e');
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

    final cached = await LoyaltyStorage.read(name: name, phone: phone);
    setState(() {
      _info = cached;
      _loading = false;
    });

    await _refresh(showSpinner: false);
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
      appBar: AppBar(
        title: const Text('Программа лояльности'),
        actions: [
          if (_isAdmin)
            IconButton(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const LoyaltyPromoManagementPage(),
                  ),
                ).then((_) {
                  // Обновляем данные после возврата из управления акциями
                  _refresh();
                });
              },
              icon: const Icon(Icons.settings),
              tooltip: 'Управление условиями акций',
            ),
          IconButton(
            onPressed: () => _refresh(),
            icon: const Icon(Icons.refresh),
            tooltip: 'Обновить',
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : info == null
              ? _errorMessage()
              : RefreshIndicator(
                  onRefresh: _refresh,
                  child: SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _coffeeCupCard(info),
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
    );
  }

  Widget _errorMessage() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 64, color: Colors.red),
            const SizedBox(height: 16),
            Text(
              _error ?? 'Данные не найдены',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () => _refresh(),
              child: const Text('Повторить попытку'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _coffeeCupCard(LoyaltyInfo info) {
    // Отображаем points от 0 до 9 (если points = 10, стакан пустой)
    final displayPoints = info.points >= 10 ? 0 : info.points.clamp(0, 9);
    
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            const Text(
              'Акция 9+1',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            CoffeeCupWidget(
              points: displayPoints,
              width: 200,
              height: 300,
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: () => _showQrFullScreen(context, info),
              icon: const Icon(Icons.qr_code),
              label: const Text('Показать QR'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              info.name,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            Text(
              info.phone,
              style: const TextStyle(color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }

  void _showQrFullScreen(BuildContext context, LoyaltyInfo info) {
    showDialog(
      context: context,
      barrierColor: Colors.black87,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: EdgeInsets.zero,
        child: Container(
          width: double.infinity,
          height: double.infinity,
          color: Colors.white,
          child: SafeArea(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text(
                  'Ваш QR-код',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 24),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.1),
                        blurRadius: 10,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                  child: QrImageView(
                    data: info.qr,
                    version: QrVersions.auto,
                    size: 300,
                    backgroundColor: Colors.white,
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  info.name,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  info.phone,
                  style: const TextStyle(
                    fontSize: 16,
                    color: Colors.grey,
                  ),
                ),
                const SizedBox(height: 32),
                ElevatedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 32,
                      vertical: 16,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text('Закрыть'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _pointsCard(LoyaltyInfo info) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Баллы',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Text('Собрано: ${info.points}/10'),
            const SizedBox(height: 8),
            LinearProgressIndicator(
              value: (info.points.clamp(0, 10)) / 10,
              borderRadius: BorderRadius.circular(8),
              color: info.points >= 10 ? Colors.orange : Colors.teal,
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: List.generate(10, (index) {
                final active = index < info.points;
                return CircleAvatar(
                  radius: 12,
                  backgroundColor: active ? Colors.teal : Colors.grey[300],
                  child: active
                      ? const Icon(Icons.star, size: 14, color: Colors.white)
                      : const SizedBox.shrink(),
                );
              }),
            ),
            if (info.readyForRedeem)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Row(
                  children: const [
                    Icon(Icons.card_giftcard, color: Colors.orange),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Баллов достаточно для бесплатного напитка. Покажите код сотруднику.',
                        style: TextStyle(color: Colors.orange),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _freeDrinksCard(LoyaltyInfo info) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Бесплатные напитки',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Text(
              'Выдано: ${info.freeDrinks}',
              style: const TextStyle(fontSize: 16),
            ),
          ],
        ),
      ),
    );
  }

  Widget _promoCard(String promoText) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Условия акции',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Text(
              promoText,
              style: const TextStyle(fontSize: 15),
            ),
          ],
        ),
      ),
    );
  }
}




