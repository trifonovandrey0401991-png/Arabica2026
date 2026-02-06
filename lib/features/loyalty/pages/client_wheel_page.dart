import 'dart:math';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../models/loyalty_gamification_model.dart';
import '../services/loyalty_gamification_service.dart';

/// Премиум страница колеса удачи для клиента
class ClientWheelPage extends StatefulWidget {
  final String phone;
  final String clientName;
  final WheelSettings wheelSettings;
  final int spinsAvailable;

  const ClientWheelPage({
    super.key,
    required this.phone,
    required this.clientName,
    required this.wheelSettings,
    required this.spinsAvailable,
  });

  @override
  State<ClientWheelPage> createState() => _ClientWheelPageState();
}

class _ClientWheelPageState extends State<ClientWheelPage>
    with TickerProviderStateMixin {
  late AnimationController _spinController;
  late AnimationController _glowController;
  late AnimationController _pulseController;
  late Animation<double> _spinAnimation;
  late Animation<double> _glowAnimation;
  late Animation<double> _pulseAnimation;

  double _currentRotation = 0;
  bool _isSpinning = false;
  int _spinsLeft = 0;
  WheelSpinResult? _lastResult;

  // Премиум цвета
  static const _goldColor = Color(0xFFFFD700);
  static const _darkGold = Color(0xFFB8860B);

  @override
  void initState() {
    super.initState();
    _spinsLeft = widget.spinsAvailable;

    // Контроллер вращения
    _spinController = AnimationController(
      duration: const Duration(milliseconds: 5000),
      vsync: this,
    );

    _spinAnimation = Tween<double>(begin: 0, end: 0).animate(
      CurvedAnimation(parent: _spinController, curve: Curves.easeOutCubic),
    );

    _spinController.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        setState(() => _isSpinning = false);
        if (_lastResult != null) {
          _showResultDialog();
        }
      }
    });

    // Контроллер свечения
    _glowController = AnimationController(
      duration: const Duration(milliseconds: 2000),
      vsync: this,
    )..repeat(reverse: true);

    _glowAnimation = Tween<double>(begin: 0.3, end: 0.7).animate(
      CurvedAnimation(parent: _glowController, curve: Curves.easeInOut),
    );

    // Пульсация для кнопки
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.08).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _spinController.dispose();
    _glowController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  Future<void> _spin() async {
    if (_isSpinning || _spinsLeft <= 0) return;

    setState(() => _isSpinning = true);

    final result = await LoyaltyGamificationService.spinWheel(widget.phone);

    if (result != null) {
      _lastResult = result;
      _animateToSector(result.sectorIndex);
      setState(() => _spinsLeft--);
    } else {
      setState(() => _isSpinning = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Row(
              children: [
                Icon(Icons.error_outline, color: Colors.white),
                SizedBox(width: 12),
                Text('Ошибка прокрутки. Попробуйте позже.'),
              ],
            ),
            backgroundColor: Colors.red[700],
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );
      }
    }
  }

  void _animateToSector(int sectorIndex) {
    final sectors = widget.wheelSettings.sectors;
    final sectorAngle = 2 * pi / sectors.length;
    final targetAngle = sectorAngle * sectorIndex + sectorAngle / 2;
    final fullRotations = 6 * 2 * pi;
    final totalRotation = fullRotations + (2 * pi - targetAngle);

    _spinAnimation = Tween<double>(
      begin: _currentRotation,
      end: _currentRotation + totalRotation,
    ).animate(CurvedAnimation(
      parent: _spinController,
      curve: Curves.easeOutCubic,
    ));

    _spinController.forward(from: 0).then((_) {
      _currentRotation = _spinAnimation.value % (2 * pi);
    });
  }

  void _showResultDialog() {
    if (_lastResult == null) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => _buildPremiumResultDialog(),
    );
  }

  Widget _buildPremiumResultDialog() {
    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 340),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF1A1A2E), Color(0xFF16213E)],
          ),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            width: 2,
            color: _goldColor.withOpacity(0.5),
          ),
          boxShadow: [
            BoxShadow(
              color: _goldColor.withOpacity(0.3),
              blurRadius: 30,
              spreadRadius: 5,
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Верхняя часть
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    _goldColor.withOpacity(0.2),
                    Colors.transparent,
                  ],
                ),
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(22),
                ),
              ),
              child: Column(
                children: [
                  const _AnimatedStars(),
                  const SizedBox(height: 16),
                  ShaderMask(
                    shaderCallback: (bounds) => const LinearGradient(
                      colors: [_goldColor, Color(0xFFFFF8DC), _goldColor],
                    ).createShader(bounds),
                    child: const Text(
                      'ПОЗДРАВЛЯЕМ!',
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                        letterSpacing: 2,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Приз
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                children: [
                  Text(
                    'Вам выпало:',
                    style: TextStyle(
                      fontSize: 16,
                      color: Colors.white.withOpacity(0.7),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          const Color(0xFF8E2DE2).withOpacity(0.3),
                          const Color(0xFF4A00E0).withOpacity(0.1),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: const Color(0xFF8E2DE2),
                        width: 2,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF8E2DE2).withOpacity(0.4),
                          blurRadius: 20,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                    child: Column(
                      children: [
                        Container(
                          width: 60,
                          height: 60,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: const LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [Color(0xFF8E2DE2), Color(0xFF4A00E0)],
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFF8E2DE2).withOpacity(0.5),
                                blurRadius: 15,
                              ),
                            ],
                          ),
                          child: Icon(
                            _getPrizeIcon(_lastResult!.prizeType),
                            color: Colors.white,
                            size: 30,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          _lastResult!.prize,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // Нижняя часть
            Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.05),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          _spinsLeft > 0 ? Icons.casino : Icons.info_outline,
                          color: Colors.white.withOpacity(0.6),
                          size: 20,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            _spinsLeft > 0
                                ? 'Осталось прокруток: $_spinsLeft'
                                : 'Все прокрутки использованы',
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.white.withOpacity(0.6),
                              height: 1.4,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      if (_spinsLeft > 0) ...[
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () {
                              Navigator.pop(context);
                              _spin();
                            },
                            style: OutlinedButton.styleFrom(
                              side: const BorderSide(color: _goldColor),
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(25),
                              ),
                            ),
                            child: const Text(
                              'ЕЩЁ РАЗ',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                color: _goldColor,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                      ],
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () {
                            Navigator.pop(context);
                            Navigator.pop(context);
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _goldColor,
                            foregroundColor: Colors.black,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(25),
                            ),
                            elevation: 8,
                            shadowColor: _goldColor.withOpacity(0.5),
                          ),
                          child: const Text(
                            'ГОТОВО',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  IconData _getPrizeIcon(String prizeType) {
    switch (prizeType) {
      case 'bonus_points':
        return Icons.stars;
      case 'discount':
        return Icons.local_offer;
      case 'free_drink':
        return Icons.local_cafe;
      case 'merch':
        return Icons.card_giftcard;
      default:
        return Icons.emoji_events;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFF1A1A2E),
              Color(0xFF16213E),
              Color(0xFF0F3460),
            ],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              // Кастомный AppBar
              _buildCustomAppBar(),

              // Контент
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      const SizedBox(height: 16),

                      // Заголовок
                      _buildHeader(),

                      const SizedBox(height: 8),

                      // Счетчик прокруток
                      _buildSpinsCounter(),

                      const SizedBox(height: 24),

                      // Колесо
                      _buildWheelSection(),

                      const SizedBox(height: 24),

                      // Кнопка прокрутки
                      _buildSpinButton(),

                      const SizedBox(height: 32),

                      // Информационные карточки
                      _buildInfoCards(),

                      const SizedBox(height: 24),
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

  Widget _buildCustomAppBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.pop(context),
            icon: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(
                Icons.arrow_back_ios_new,
                color: Colors.white,
                size: 20,
              ),
            ),
          ),
          const Spacer(),
          Text(
            widget.clientName,
            style: TextStyle(
              color: Colors.white.withOpacity(0.9),
              fontSize: 16,
              fontWeight: FontWeight.w500,
            ),
          ),
          const Spacer(),
          const SizedBox(width: 48),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Column(
      children: [
        Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [_goldColor, _darkGold],
            ),
            boxShadow: [
              BoxShadow(
                color: _goldColor.withOpacity(0.4),
                blurRadius: 20,
                spreadRadius: 2,
              ),
            ],
          ),
          child: const Icon(
            Icons.casino,
            color: Colors.white,
            size: 32,
          ),
        ),
        const SizedBox(height: 16),
        ShaderMask(
          shaderCallback: (bounds) => const LinearGradient(
            colors: [_goldColor, Color(0xFFFFF8DC), _goldColor],
          ).createShader(bounds),
          child: const Text(
            'КОЛЕСО УДАЧИ',
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w900,
              color: Colors.white,
              letterSpacing: 3,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Испытай свою удачу!',
          style: TextStyle(
            fontSize: 16,
            color: Colors.white.withOpacity(0.6),
            letterSpacing: 1,
          ),
        ),
      ],
    );
  }

  Widget _buildSpinsCounter() {
    return AnimatedBuilder(
      animation: _glowAnimation,
      builder: (context, child) {
        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 48),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: _spinsLeft > 0
                  ? [
                      _goldColor.withOpacity(0.2),
                      _goldColor.withOpacity(0.1),
                      _goldColor.withOpacity(0.2),
                    ]
                  : [
                      Colors.grey.withOpacity(0.2),
                      Colors.grey.withOpacity(0.1),
                      Colors.grey.withOpacity(0.2),
                    ],
            ),
            borderRadius: BorderRadius.circular(30),
            border: Border.all(
              color: _spinsLeft > 0
                  ? _goldColor.withOpacity(0.5)
                  : Colors.grey.withOpacity(0.3),
              width: 1.5,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                _spinsLeft > 0 ? Icons.stars : Icons.hourglass_empty,
                color: _spinsLeft > 0 ? _goldColor : Colors.grey,
                size: 24,
              ),
              const SizedBox(width: 12),
              Text(
                _spinsLeft > 0
                    ? 'Доступно прокруток: $_spinsLeft'
                    : 'Прокрутки недоступны',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: _spinsLeft > 0 ? _goldColor : Colors.grey,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildWheelSection() {
    final screenWidth = MediaQuery.of(context).size.width;
    final wheelSize = screenWidth * 0.85;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Внешнее свечение
          Container(
            width: wheelSize + 40,
            height: wheelSize + 40,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: _goldColor.withOpacity(0.3),
                  blurRadius: 40,
                  spreadRadius: 10,
                ),
              ],
            ),
          ),
          // Декоративное кольцо
          Container(
            width: wheelSize + 20,
            height: wheelSize + 20,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [_goldColor, _darkGold, _goldColor],
              ),
            ),
          ),
          // Колесо
          Padding(
            padding: const EdgeInsets.all(10),
            child: AnimatedBuilder(
              animation: Listenable.merge([_spinAnimation, _glowAnimation]),
              builder: (context, child) {
                return Stack(
                  alignment: Alignment.center,
                  children: [
                    // Колесо с тенью
                    Transform.rotate(
                      angle: _spinAnimation.value,
                      child: Container(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.4),
                              blurRadius: 20,
                              offset: const Offset(0, 10),
                            ),
                          ],
                        ),
                        child: CustomPaint(
                          size: Size(wheelSize, wheelSize),
                          painter: _PremiumWheelPainter(
                            sectors: widget.wheelSettings.sectors,
                            glowIntensity: _glowAnimation.value,
                          ),
                        ),
                      ),
                    ),

                    // Стрелка
                    Positioned(
                      top: -5,
                      child: _buildPremiumPointer(),
                    ),

                    // Центральная кнопка
                    _buildPremiumCenterButton(),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPremiumPointer() {
    return Container(
      width: 50,
      height: 55,
      decoration: BoxDecoration(
        boxShadow: [
          BoxShadow(
            color: _goldColor.withOpacity(0.5),
            blurRadius: 15,
            spreadRadius: 2,
          ),
        ],
      ),
      child: CustomPaint(
        size: const Size(50, 55),
        painter: _PremiumPointerPainter(),
      ),
    );
  }

  Widget _buildPremiumCenterButton() {
    return Container(
      width: 80,
      height: 80,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFFFFD700),
            Color(0xFFFFA500),
            Color(0xFFB8860B),
          ],
          stops: [0.0, 0.5, 1.0],
        ),
        border: Border.all(
          color: const Color(0xFFFFF8DC),
          width: 3,
        ),
        boxShadow: [
          BoxShadow(
            color: _goldColor.withOpacity(0.6),
            blurRadius: 20,
            spreadRadius: 5,
          ),
          const BoxShadow(
            color: Colors.black26,
            blurRadius: 10,
            offset: Offset(0, 5),
          ),
        ],
      ),
      child: Container(
        margin: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [
              Colors.white.withOpacity(0.3),
              Colors.transparent,
            ],
            stops: const [0.0, 1.0],
          ),
        ),
        child: const Center(
          child: Icon(
            Icons.star,
            color: Colors.white,
            size: 36,
            shadows: [
              Shadow(
                color: Colors.black38,
                offset: Offset(2, 2),
                blurRadius: 4,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSpinButton() {
    final bool canSpin = _spinsLeft > 0 && !_isSpinning;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 48),
      child: AnimatedBuilder(
        animation: _pulseAnimation,
        builder: (context, child) {
          return Transform.scale(
            scale: canSpin ? _pulseAnimation.value : 1.0,
            child: Container(
              width: double.infinity,
              height: 60,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(30),
                gradient: canSpin
                    ? const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [_goldColor, _darkGold],
                      )
                    : LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [Colors.grey[600]!, Colors.grey[700]!],
                      ),
                boxShadow: canSpin
                    ? [
                        BoxShadow(
                          color: _goldColor.withOpacity(0.5),
                          blurRadius: 20,
                          spreadRadius: 2,
                          offset: const Offset(0, 4),
                        ),
                      ]
                    : null,
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: canSpin ? _spin : null,
                  borderRadius: BorderRadius.circular(30),
                  child: Center(
                    child: _isSpinning
                        ? Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              SizedBox(
                                width: 24,
                                height: 24,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.5,
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                    Colors.white.withOpacity(0.9),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              const Text(
                                'ВРАЩАЕМ...',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w800,
                                  color: Colors.white,
                                  letterSpacing: 2,
                                ),
                              ),
                            ],
                          )
                        : Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                canSpin ? Icons.casino : Icons.lock_outline,
                                color: Colors.white,
                                size: 26,
                              ),
                              const SizedBox(width: 12),
                              Text(
                                canSpin ? 'КРУТИТЬ!' : 'НЕТ ПРОКРУТОК',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w800,
                                  color: Colors.white.withOpacity(canSpin ? 1.0 : 0.7),
                                  letterSpacing: 2,
                                ),
                              ),
                            ],
                          ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildInfoCards() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        children: [
          _buildInfoCard(
            icon: Icons.local_cafe,
            title: 'Как получить прокрутки?',
            description:
                'Получайте бесплатные напитки по программе лояльности и зарабатывайте прокрутки колеса!',
            gradient: const [Color(0xFF6366F1), Color(0xFF8B5CF6)],
          ),
          const SizedBox(height: 12),
          _buildInfoCard(
            icon: Icons.card_giftcard,
            title: 'Призы',
            description:
                'Выигрывайте бонусные баллы, скидки, бесплатные напитки и фирменный мерч!',
            gradient: const [Color(0xFF10B981), Color(0xFF34D399)],
          ),
        ],
      ),
    );
  }

  Widget _buildInfoCard({
    required IconData icon,
    required String title,
    required String description,
    required List<Color> gradient,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Colors.white.withOpacity(0.1),
          width: 1,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: gradient,
              ),
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: gradient[0].withOpacity(0.4),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Icon(icon, color: Colors.white, size: 24),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  description,
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.white.withOpacity(0.6),
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Премиум рисование колеса
class _PremiumWheelPainter extends CustomPainter {
  final List<WheelSector> sectors;
  final double glowIntensity;

  _PremiumWheelPainter({
    required this.sectors,
    this.glowIntensity = 0.5,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;
    final sectorAngle = 2 * pi / sectors.length;

    // Внешнее кольцо с лампочками
    _drawOuterRing(canvas, center, radius);

    // Секторы
    for (int i = 0; i < sectors.length; i++) {
      final startAngle = -pi / 2 + i * sectorAngle;
      _drawPremiumSector(canvas, center, radius - 15, startAngle, sectorAngle, sectors[i], i);
    }

    // Внутреннее украшение
    _drawInnerDecoration(canvas, center, radius);
  }

  void _drawOuterRing(Canvas canvas, Offset center, double radius) {
    final ringPaint = Paint()
      ..shader = ui.Gradient.sweep(
        center,
        [
          const Color(0xFFFFD700),
          const Color(0xFFFFA500),
          const Color(0xFFB8860B),
          const Color(0xFFFFD700),
        ],
        [0.0, 0.33, 0.66, 1.0],
      )
      ..style = PaintingStyle.stroke
      ..strokeWidth = 15;

    canvas.drawCircle(center, radius - 7.5, ringPaint);

    // Лампочки
    final numLights = sectors.length * 2;
    final lightRadius = 5.0;

    for (int i = 0; i < numLights; i++) {
      final angle = (2 * pi / numLights) * i - pi / 2;
      final lightCenter = Offset(
        center.dx + (radius - 7.5) * cos(angle),
        center.dy + (radius - 7.5) * sin(angle),
      );

      final isActive = i % 2 == 0;
      final brightness = isActive ? glowIntensity : (1 - glowIntensity) * 0.5;

      final glowPaint = Paint()
        ..color = Colors.white.withOpacity(brightness * 0.8)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);

      canvas.drawCircle(lightCenter, lightRadius + 2, glowPaint);

      final lightPaint = Paint()
        ..color = isActive
            ? Color.lerp(const Color(0xFFFFD700), Colors.white, brightness)!
            : const Color(0xFFB8860B).withOpacity(0.7)
        ..style = PaintingStyle.fill;

      canvas.drawCircle(lightCenter, lightRadius, lightPaint);

      final highlightPaint = Paint()
        ..color = Colors.white.withOpacity(isActive ? 0.6 : 0.2);

      canvas.drawCircle(
        Offset(lightCenter.dx - 1.5, lightCenter.dy - 1.5),
        lightRadius * 0.4,
        highlightPaint,
      );
    }
  }

  void _drawPremiumSector(
    Canvas canvas,
    Offset center,
    double radius,
    double startAngle,
    double sectorAngle,
    WheelSector sector,
    int index,
  ) {
    final sectorColor = sector.color;
    final lighterColor = Color.lerp(sectorColor, Colors.white, 0.3)!;
    final darkerColor = Color.lerp(sectorColor, Colors.black, 0.2)!;

    final sectorPaint = Paint()
      ..shader = ui.Gradient.sweep(
        center,
        [lighterColor, sectorColor, darkerColor],
        [0.0, 0.5, 1.0],
        TileMode.clamp,
        startAngle,
        startAngle + sectorAngle,
      )
      ..style = PaintingStyle.fill;

    final path = Path()
      ..moveTo(center.dx, center.dy)
      ..arcTo(
        Rect.fromCircle(center: center, radius: radius),
        startAngle,
        sectorAngle,
        false,
      )
      ..close();

    canvas.drawPath(path, sectorPaint);

    final borderPaint = Paint()
      ..color = Colors.white.withOpacity(0.4)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    canvas.drawPath(path, borderPaint);

    final innerShadowPaint = Paint()
      ..shader = ui.Gradient.radial(
        center,
        radius,
        [Colors.transparent, Colors.black.withOpacity(0.15)],
        [0.7, 1.0],
      )
      ..style = PaintingStyle.fill;

    canvas.drawPath(path, innerShadowPaint);

    _drawSectorText(canvas, center, radius, startAngle + sectorAngle / 2, sector.text);
  }

  void _drawSectorText(
    Canvas canvas,
    Offset center,
    double radius,
    double angle,
    String text,
  ) {
    final fontSize = radius * 0.08;

    final textPainter = TextPainter(
      text: TextSpan(
        text: _truncateText(text, 14),
        style: TextStyle(
          color: Colors.white,
          fontSize: fontSize.clamp(11.0, 15.0),
          fontWeight: FontWeight.w800,
          letterSpacing: 0.5,
          shadows: const [
            Shadow(color: Colors.black87, offset: Offset(1, 1), blurRadius: 4),
            Shadow(color: Colors.black54, offset: Offset(2, 2), blurRadius: 6),
          ],
        ),
      ),
      textDirection: TextDirection.ltr,
    );

    textPainter.layout();

    final textRadius = radius * 0.6;

    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(angle);

    textPainter.paint(
      canvas,
      Offset(textRadius - textPainter.width / 2, -textPainter.height / 2),
    );

    canvas.restore();
  }

  void _drawInnerDecoration(Canvas canvas, Offset center, double radius) {
    final innerRingRadius = radius * 0.25;

    final innerRingPaint = Paint()
      ..shader = ui.Gradient.radial(
        center,
        innerRingRadius,
        [const Color(0xFFFFD700), const Color(0xFFB8860B)],
      )
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;

    canvas.drawCircle(center, innerRingRadius, innerRingPaint);

    final numStars = 8;
    final starRadius = innerRingRadius + 10;

    for (int i = 0; i < numStars; i++) {
      final starAngle = (2 * pi / numStars) * i - pi / 2;
      final starCenter = Offset(
        center.dx + starRadius * cos(starAngle),
        center.dy + starRadius * sin(starAngle),
      );

      _drawStar(canvas, starCenter, 4, const Color(0xFFFFD700));
    }
  }

  void _drawStar(Canvas canvas, Offset center, double radius, Color color) {
    final starPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    final glowPaint = Paint()
      ..color = color.withOpacity(0.5)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2);

    canvas.drawCircle(center, radius + 1, glowPaint);
    canvas.drawCircle(center, radius, starPaint);
  }

  String _truncateText(String text, int maxLength) {
    if (text.length <= maxLength) return text;
    return '${text.substring(0, maxLength - 1)}…';
  }

  @override
  bool shouldRepaint(covariant _PremiumWheelPainter oldDelegate) {
    return oldDelegate.glowIntensity != glowIntensity;
  }
}

/// Премиум стрелка
class _PremiumPointerPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final centerX = size.width / 2;

    // Тень
    final shadowPath = Path()
      ..moveTo(centerX, size.height - 5)
      ..lineTo(5, 10)
      ..lineTo(size.width - 5, 10)
      ..close();

    final shadowPaint = Paint()
      ..color = Colors.black.withOpacity(0.3)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5);

    canvas.drawPath(shadowPath.shift(const Offset(2, 3)), shadowPaint);

    // Указатель
    final pointerPath = Path()
      ..moveTo(centerX, size.height - 5)
      ..lineTo(5, 8)
      ..quadraticBezierTo(centerX, 0, size.width - 5, 8)
      ..close();

    final pointerPaint = Paint()
      ..shader = ui.Gradient.linear(
        Offset(0, size.height),
        const Offset(0, 0),
        [
          const Color(0xFFFFD700),
          const Color(0xFFFFA500),
          const Color(0xFFB8860B),
        ],
        [0.0, 0.5, 1.0],
      )
      ..style = PaintingStyle.fill;

    canvas.drawPath(pointerPath, pointerPaint);

    // Блик
    final highlightPath = Path()
      ..moveTo(centerX - 5, size.height - 15)
      ..lineTo(10, 12)
      ..lineTo(centerX - 3, 15)
      ..close();

    final highlightPaint = Paint()
      ..color = Colors.white.withOpacity(0.4)
      ..style = PaintingStyle.fill;

    canvas.drawPath(highlightPath, highlightPaint);

    // Обводка
    final borderPaint = Paint()
      ..color = const Color(0xFFFFF8DC)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    canvas.drawPath(pointerPath, borderPaint);

    // Крепление
    final attachPaint = Paint()
      ..shader = ui.Gradient.radial(
        Offset(centerX, 12),
        8,
        [const Color(0xFFFFD700), const Color(0xFFB8860B)],
      );

    canvas.drawCircle(Offset(centerX, 12), 6, attachPaint);

    final attachBorderPaint = Paint()
      ..color = const Color(0xFFFFF8DC)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    canvas.drawCircle(Offset(centerX, 12), 6, attachBorderPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Анимированные звезды
class _AnimatedStars extends StatefulWidget {
  const _AnimatedStars();

  @override
  State<_AnimatedStars> createState() => _AnimatedStarsState();
}

class _AnimatedStarsState extends State<_AnimatedStars>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return SizedBox(
          width: 100,
          height: 60,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Transform.scale(
                scale: 0.9 + (_controller.value * 0.2),
                child: const Icon(
                  Icons.star,
                  color: Color(0xFFFFD700),
                  size: 50,
                ),
              ),
              Positioned(
                left: 10,
                top: 5,
                child: Transform.scale(
                  scale: 0.8 + ((1 - _controller.value) * 0.3),
                  child: Icon(
                    Icons.star,
                    color: const Color(0xFFFFD700).withOpacity(0.7),
                    size: 20,
                  ),
                ),
              ),
              Positioned(
                right: 10,
                top: 10,
                child: Transform.scale(
                  scale: 0.7 + (_controller.value * 0.3),
                  child: Icon(
                    Icons.star,
                    color: const Color(0xFFFFD700).withOpacity(0.6),
                    size: 18,
                  ),
                ),
              ),
              Positioned(
                left: 20,
                bottom: 0,
                child: Transform.scale(
                  scale: 0.6 + ((1 - _controller.value) * 0.4),
                  child: Icon(
                    Icons.star,
                    color: const Color(0xFFFFD700).withOpacity(0.5),
                    size: 14,
                  ),
                ),
              ),
              Positioned(
                right: 15,
                bottom: 5,
                child: Transform.scale(
                  scale: 0.75 + (_controller.value * 0.25),
                  child: Icon(
                    Icons.star,
                    color: const Color(0xFFFFD700).withOpacity(0.65),
                    size: 16,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
