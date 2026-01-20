import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../models/fortune_wheel_model.dart';
import '../services/fortune_wheel_service.dart';
import '../widgets/animated_wheel_widget.dart';

/// Страница Колеса Удачи - Премиум версия
class FortuneWheelPage extends StatefulWidget {
  final String employeeId;
  final String employeeName;

  const FortuneWheelPage({
    super.key,
    required this.employeeId,
    required this.employeeName,
  });

  @override
  State<FortuneWheelPage> createState() => _FortuneWheelPageState();
}

class _FortuneWheelPageState extends State<FortuneWheelPage>
    with TickerProviderStateMixin {
  List<FortuneWheelSector> _sectors = [];
  int _availableSpins = 0;
  bool _isLoading = true;
  bool _isSpinning = false;
  WheelSpinResult? _lastResult;
  final GlobalKey<AnimatedWheelWidgetState> _wheelKey = GlobalKey();

  // Анимации для эффектов
  late AnimationController _pulseController;
  late AnimationController _shimmerController;
  late Animation<double> _pulseAnimation;
  late Animation<double> _shimmerAnimation;

  // Цвета
  static const _primaryColor = Color(0xFF004D40);
  static const _accentColor = Color(0xFF00897B);
  static const _goldColor = Color(0xFFFFD700);
  static const _darkGold = Color(0xFFB8860B);

  @override
  void initState() {
    super.initState();
    _initAnimations();
    _loadData();
  }

  void _initAnimations() {
    // Пульсация для кнопки
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.08).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    // Shimmer эффект
    _shimmerController = AnimationController(
      duration: const Duration(milliseconds: 2000),
      vsync: this,
    )..repeat();

    _shimmerAnimation = Tween<double>(begin: -1.0, end: 2.0).animate(
      CurvedAnimation(parent: _shimmerController, curve: Curves.linear),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _shimmerController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);

    final settings = await FortuneWheelService.getSettings();
    final spins =
        await FortuneWheelService.getAvailableSpins(widget.employeeId);

    if (mounted) {
      setState(() {
        _sectors = settings?.sectors ?? [];
        _availableSpins = spins.availableSpins;
        _isLoading = false;
      });
    }
  }

  Future<void> _spin() async {
    if (_isSpinning || _availableSpins <= 0) return;

    setState(() => _isSpinning = true);

    final result = await FortuneWheelService.spin(
      employeeId: widget.employeeId,
      employeeName: widget.employeeName,
    );

    if (result != null) {
      _wheelKey.currentState?.spinToSector(result.sector.index);
      _lastResult = result;
    } else {
      setState(() => _isSpinning = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Row(
              children: [
                Icon(Icons.error_outline, color: Colors.white),
                SizedBox(width: 12),
                Text('Ошибка при прокрутке колеса'),
              ],
            ),
            backgroundColor: Colors.red[700],
            behavior: SnackBarBehavior.floating,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );
      }
    }
  }

  void _onSpinComplete() {
    setState(() {
      _isSpinning = false;
      _availableSpins = _lastResult?.remainingSpins ?? 0;
    });

    if (_lastResult != null) {
      _showResultDialog(_lastResult!);
    }
  }

  void _showResultDialog(WheelSpinResult result) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => _buildPremiumResultDialog(result),
    );
  }

  Widget _buildPremiumResultDialog(WheelSpinResult result) {
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
            // Верхняя часть с конфетти эффектом
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
                  // Звезды анимация
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
                          result.sector.color.withOpacity(0.3),
                          result.sector.color.withOpacity(0.1),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: result.sector.color,
                        width: 2,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: result.sector.color.withOpacity(0.4),
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
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [
                                result.sector.color,
                                result.sector.color.withOpacity(0.6),
                              ],
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: result.sector.color.withOpacity(0.5),
                                blurRadius: 15,
                              ),
                            ],
                          ),
                          child: const Icon(
                            Icons.card_giftcard,
                            color: Colors.white,
                            size: 30,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          result.sector.text,
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

            // Информация
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
                          Icons.info_outline,
                          color: Colors.white.withOpacity(0.6),
                          size: 20,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'Результат записан.\nАдминистратор свяжется с вами.',
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
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(context),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _goldColor,
                        foregroundColor: Colors.black,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(25),
                        ),
                        elevation: 8,
                        shadowColor: _goldColor.withOpacity(0.5),
                      ),
                      child: const Text(
                        'ОТЛИЧНО!',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1,
                        ),
                      ),
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
          child: _isLoading
              ? _buildLoadingState()
              : _sectors.isEmpty
                  ? _buildNoSectorsState()
                  : _buildWheelContent(),
        ),
      ),
    );
  }

  Widget _buildLoadingState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            width: 60,
            height: 60,
            child: CircularProgressIndicator(
              strokeWidth: 3,
              valueColor: AlwaysStoppedAnimation<Color>(
                _goldColor.withOpacity(0.8),
              ),
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'Загрузка колеса...',
            style: TextStyle(
              fontSize: 16,
              color: Colors.white.withOpacity(0.7),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNoSectorsState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 100,
            height: 100,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Colors.grey[700]!,
                  Colors.grey[800]!,
                ],
              ),
            ),
            child: Icon(
              Icons.hourglass_empty,
              size: 50,
              color: Colors.white.withOpacity(0.5),
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'Колесо не настроено',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w600,
              color: Colors.white.withOpacity(0.7),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Обратитесь к администратору',
            style: TextStyle(
              fontSize: 14,
              color: Colors.white.withOpacity(0.4),
            ),
          ),
          const SizedBox(height: 32),
          TextButton.icon(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.arrow_back, color: _goldColor),
            label: const Text(
              'Вернуться',
              style: TextStyle(color: _goldColor, fontSize: 16),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWheelContent() {
    return Column(
      children: [
        // Кастомный AppBar
        _buildCustomAppBar(),

        // Контент
        Expanded(
          child: SingleChildScrollView(
            child: Column(
              children: [
                const SizedBox(height: 16),

                // Заголовок с эффектом
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
          IconButton(
            onPressed: _loadData,
            icon: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(
                Icons.refresh,
                color: Colors.white,
                size: 20,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Column(
      children: [
        // Иконка колеса
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
      animation: _shimmerAnimation,
      builder: (context, child) {
        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 48),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: _availableSpins > 0
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
              color: _availableSpins > 0
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
                _availableSpins > 0 ? Icons.stars : Icons.hourglass_empty,
                color: _availableSpins > 0 ? _goldColor : Colors.grey,
                size: 24,
              ),
              const SizedBox(width: 12),
              Text(
                _availableSpins > 0
                    ? 'Доступно прокруток: $_availableSpins'
                    : 'Прокрутки недоступны',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: _availableSpins > 0 ? _goldColor : Colors.grey,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildWheelSection() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Внешнее свечение
          Container(
            width: MediaQuery.of(context).size.width * 0.85 + 40,
            height: MediaQuery.of(context).size.width * 0.85 + 40,
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
            width: MediaQuery.of(context).size.width * 0.85 + 20,
            height: MediaQuery.of(context).size.width * 0.85 + 20,
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
            child: AnimatedWheelWidget(
              key: _wheelKey,
              sectors: _sectors,
              isSpinning: _isSpinning,
              onSpinComplete: _onSpinComplete,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSpinButton() {
    final bool canSpin = _availableSpins > 0 && !_isSpinning;

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
                                canSpin
                                    ? Icons.casino
                                    : Icons.lock_outline,
                                color: Colors.white,
                                size: 26,
                              ),
                              const SizedBox(width: 12),
                              Text(
                                canSpin ? 'КРУТИТЬ!' : 'НЕТ ПРОКРУТОК',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w800,
                                  color: Colors.white.withOpacity(
                                      canSpin ? 1.0 : 0.7),
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
          // Как получить прокрутки
          _buildInfoCard(
            icon: Icons.emoji_events,
            title: 'Как получить прокрутки?',
            description:
                'Войдите в топ-3 по эффективности за месяц и получите возможность крутить колесо удачи!',
            gradient: const [Color(0xFF6366F1), Color(0xFF8B5CF6)],
          ),
          const SizedBox(height: 12),
          // Призы
          _buildInfoCard(
            icon: Icons.card_giftcard,
            title: 'Призы',
            description:
                'Выигрывайте денежные бонусы, подарки и другие приятные сюрпризы!',
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

/// Анимированные звезды для диалога результата
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
              // Большая звезда в центре
              Transform.scale(
                scale: 0.9 + (_controller.value * 0.2),
                child: const Icon(
                  Icons.star,
                  color: Color(0xFFFFD700),
                  size: 50,
                ),
              ),
              // Маленькие звезды
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
