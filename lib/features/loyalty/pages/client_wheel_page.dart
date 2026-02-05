import 'dart:math';
import 'package:flutter/material.dart';
import '../models/loyalty_gamification_model.dart';
import '../services/loyalty_gamification_service.dart';

/// Страница колеса удачи для клиента
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
  late Animation<double> _spinAnimation;

  double _currentRotation = 0;
  bool _isSpinning = false;
  int _spinsLeft = 0;
  WheelSpinResult? _lastResult;

  @override
  void initState() {
    super.initState();
    _spinsLeft = widget.spinsAvailable;

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
  }

  @override
  void dispose() {
    _spinController.dispose();
    super.dispose();
  }

  Future<void> _spin() async {
    if (_isSpinning || _spinsLeft <= 0) return;

    setState(() => _isSpinning = true);

    // Вызываем API для прокрутки
    final result = await LoyaltyGamificationService.spinWheel(widget.phone);

    if (result != null) {
      _lastResult = result;
      _animateToSector(result.sectorIndex);
      setState(() => _spinsLeft--);
    } else {
      setState(() => _isSpinning = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Ошибка прокрутки. Попробуйте позже.'),
            backgroundColor: Colors.red,
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
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFFFFD700), Color(0xFFFFA500)],
                ),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.celebration, color: Colors.white, size: 28),
            ),
            const SizedBox(width: 12),
            const Expanded(child: Text('Поздравляем!')),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Text(
              'Вы выиграли:',
              style: TextStyle(color: Colors.grey[600], fontSize: 14),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    const Color(0xFF8E2DE2).withOpacity(0.1),
                    const Color(0xFF4A00E0).withOpacity(0.1),
                  ],
                ),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(_getPrizeIcon(_lastResult!.prizeType),
                      color: const Color(0xFF8E2DE2), size: 32),
                  const SizedBox(width: 12),
                  Flexible(
                    child: Text(
                      _lastResult!.prize,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF8E2DE2),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Text(
              _spinsLeft > 0
                  ? 'Осталось прокруток: $_spinsLeft'
                  : 'Все прокрутки использованы',
              style: TextStyle(
                color: Colors.grey[600],
                fontSize: 13,
              ),
            ),
          ],
        ),
        actions: [
          if (_spinsLeft > 0)
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                _spin();
              },
              child: const Text('КРУТИТЬ ЕЩЁ'),
            ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              Navigator.pop(context); // Вернуться на страницу лояльности
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF8E2DE2),
            ),
            child: const Text('ГОТОВО', style: TextStyle(color: Colors.white)),
          ),
        ],
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
      backgroundColor: const Color(0xFF0D0D1A),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text('Колесо удачи', style: TextStyle(color: Colors.white)),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 20),
            // Инфо о клиенте
            Text(
              widget.clientName,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFF4CAF50),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                'Прокруток: $_spinsLeft',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const Spacer(),
            // Колесо
            _buildWheel(),
            const Spacer(),
            // Кнопка
            Padding(
              padding: const EdgeInsets.all(24),
              child: SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed: _spinsLeft > 0 && !_isSpinning ? _spin : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF8E2DE2),
                    disabledBackgroundColor: Colors.grey,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: _isSpinning
                      ? const CircularProgressIndicator(color: Colors.white)
                      : Text(
                          _spinsLeft > 0 ? 'КРУТИТЬ' : 'НЕТ ПРОКРУТОК',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
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

  Widget _buildWheel() {
    final screenWidth = MediaQuery.of(context).size.width;
    final wheelSize = screenWidth * 0.85;

    return AnimatedBuilder(
      animation: _spinAnimation,
      builder: (context, child) {
        return Stack(
          alignment: Alignment.center,
          children: [
            // Колесо
            Transform.rotate(
              angle: _spinAnimation.value,
              child: Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF8E2DE2).withOpacity(0.5),
                      blurRadius: 30,
                      spreadRadius: 5,
                    ),
                  ],
                ),
                child: CustomPaint(
                  size: Size(wheelSize, wheelSize),
                  painter: _WheelPainter(sectors: widget.wheelSettings.sectors),
                ),
              ),
            ),
            // Стрелка сверху
            Positioned(
              top: -10,
              child: _buildPointer(),
            ),
            // Центр
            Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const LinearGradient(
                  colors: [Color(0xFFFFD700), Color(0xFFFFA500)],
                ),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFFFFD700).withOpacity(0.5),
                    blurRadius: 15,
                  ),
                ],
              ),
              child: const Icon(Icons.casino, color: Colors.white, size: 32),
            ),
          ],
        );
      },
    );
  }

  Widget _buildPointer() {
    return Container(
      width: 30,
      height: 40,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFFFFD700), Color(0xFFFFA500)],
        ),
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(4),
          topRight: Radius.circular(4),
          bottomLeft: Radius.circular(15),
          bottomRight: Radius.circular(15),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black26,
            blurRadius: 8,
            offset: Offset(0, 4),
          ),
        ],
      ),
    );
  }
}

class _WheelPainter extends CustomPainter {
  final List<WheelSector> sectors;

  _WheelPainter({required this.sectors});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;
    final sectorAngle = 2 * pi / sectors.length;

    for (int i = 0; i < sectors.length; i++) {
      final startAngle = -pi / 2 + i * sectorAngle;
      final sector = sectors[i];

      // Рисуем сектор
      final paint = Paint()
        ..shader = RadialGradient(
          colors: [
            sector.color.withOpacity(0.9),
            sector.color,
          ],
        ).createShader(Rect.fromCircle(center: center, radius: radius));

      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        startAngle,
        sectorAngle,
        true,
        paint,
      );

      // Граница сектора
      final borderPaint = Paint()
        ..color = Colors.white.withOpacity(0.3)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2;

      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        startAngle,
        sectorAngle,
        true,
        borderPaint,
      );

      // Текст
      final textAngle = startAngle + sectorAngle / 2;
      final textRadius = radius * 0.65;
      final textX = center.dx + textRadius * cos(textAngle);
      final textY = center.dy + textRadius * sin(textAngle);

      canvas.save();
      canvas.translate(textX, textY);
      canvas.rotate(textAngle + pi / 2);

      final textPainter = TextPainter(
        text: TextSpan(
          text: sector.text,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 12,
            fontWeight: FontWeight.bold,
            shadows: [
              Shadow(color: Colors.black54, blurRadius: 4),
            ],
          ),
        ),
        textAlign: TextAlign.center,
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: radius * 0.5);

      textPainter.paint(
        canvas,
        Offset(-textPainter.width / 2, -textPainter.height / 2),
      );

      canvas.restore();
    }

    // Внешний обод
    final rimPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 8
      ..shader = const LinearGradient(
        colors: [Color(0xFFFFD700), Color(0xFFFFA500), Color(0xFFFFD700)],
      ).createShader(Rect.fromCircle(center: center, radius: radius));

    canvas.drawCircle(center, radius - 4, rimPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
