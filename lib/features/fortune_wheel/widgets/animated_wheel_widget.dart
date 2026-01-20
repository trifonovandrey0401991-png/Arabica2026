import 'dart:math';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../models/fortune_wheel_model.dart';

/// Премиум анимированное колесо удачи с 3D эффектами
class AnimatedWheelWidget extends StatefulWidget {
  final List<FortuneWheelSector> sectors;
  final int? targetSectorIndex;
  final VoidCallback? onSpinComplete;
  final bool isSpinning;

  const AnimatedWheelWidget({
    super.key,
    required this.sectors,
    this.targetSectorIndex,
    this.onSpinComplete,
    this.isSpinning = false,
  });

  @override
  State<AnimatedWheelWidget> createState() => AnimatedWheelWidgetState();
}

class AnimatedWheelWidgetState extends State<AnimatedWheelWidget>
    with TickerProviderStateMixin {
  late AnimationController _spinController;
  late AnimationController _glowController;
  late Animation<double> _spinAnimation;
  late Animation<double> _glowAnimation;
  double _currentRotation = 0;

  // Цвета
  static const _goldColor = Color(0xFFFFD700);

  @override
  void initState() {
    super.initState();

    // Контроллер вращения
    _spinController = AnimationController(
      duration: const Duration(milliseconds: 5000),
      vsync: this,
    );

    _spinAnimation = CurvedAnimation(
      parent: _spinController,
      curve: Curves.easeOutCubic,
    );

    _spinController.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        widget.onSpinComplete?.call();
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
  }

  @override
  void dispose() {
    _spinController.dispose();
    _glowController.dispose();
    super.dispose();
  }

  /// Запустить вращение к указанному сектору
  void spinToSector(int sectorIndex) {
    if (_spinController.isAnimating) return;

    final sectorAngle = 2 * pi / widget.sectors.length;
    // Центр сектора
    final targetAngle = sectorAngle * sectorIndex + sectorAngle / 2;
    // Минимум 6 полных оборотов + нужный угол
    final fullRotations = 6 * 2 * pi;
    // Вращаем против часовой стрелки, стрелка сверху
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

  @override
  Widget build(BuildContext context) {
    // Получаем размер экрана для адаптивного колеса
    final screenWidth = MediaQuery.of(context).size.width;
    final wheelSize = screenWidth * 0.85;

    return AnimatedBuilder(
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
                  painter: PremiumWheelPainter(
                    sectors: widget.sectors,
                    glowIntensity: _glowAnimation.value,
                  ),
                ),
              ),
            ),

            // Стрелка-указатель премиум
            Positioned(
              top: -5,
              child: _buildPremiumPointer(),
            ),

            // Центральная кнопка премиум
            _buildPremiumCenterButton(),
          ],
        );
      },
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
        painter: PremiumPointerPainter(),
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
}

/// Премиум рисование колеса с 3D эффектами
class PremiumWheelPainter extends CustomPainter {
  final List<FortuneWheelSector> sectors;
  final double glowIntensity;

  PremiumWheelPainter({
    required this.sectors,
    this.glowIntensity = 0.5,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;
    final sectorAngle = 2 * pi / sectors.length;

    // Рисуем внешнее декоративное кольцо с лампочками
    _drawOuterRing(canvas, center, radius);

    // Рисуем секторы
    for (int i = 0; i < sectors.length; i++) {
      final startAngle = -pi / 2 + i * sectorAngle;
      _drawPremiumSector(canvas, center, radius - 15, startAngle, sectorAngle, sectors[i], i);
    }

    // Внутренний декоративный круг
    _drawInnerDecoration(canvas, center, radius);
  }

  void _drawOuterRing(Canvas canvas, Offset center, double radius) {
    // Основное кольцо с градиентом
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

    // Декоративные "лампочки" по кругу
    final numLights = sectors.length * 2;
    final lightRadius = 5.0;

    for (int i = 0; i < numLights; i++) {
      final angle = (2 * pi / numLights) * i - pi / 2;
      final lightCenter = Offset(
        center.dx + (radius - 7.5) * cos(angle),
        center.dy + (radius - 7.5) * sin(angle),
      );

      // Свечение лампочки (чередуем яркие и тусклые)
      final isActive = i % 2 == 0;
      final brightness = isActive ? glowIntensity : (1 - glowIntensity) * 0.5;

      final glowPaint = Paint()
        ..color = Colors.white.withOpacity(brightness * 0.8)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);

      canvas.drawCircle(lightCenter, lightRadius + 2, glowPaint);

      // Основная лампочка
      final lightPaint = Paint()
        ..color = isActive
            ? Color.lerp(const Color(0xFFFFD700), Colors.white, brightness)!
            : const Color(0xFFB8860B).withOpacity(0.7)
        ..style = PaintingStyle.fill;

      canvas.drawCircle(lightCenter, lightRadius, lightPaint);

      // Блик на лампочке
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
    FortuneWheelSector sector,
    int index,
  ) {
    // Градиент для сектора
    final sectorColor = sector.color;
    final lighterColor = Color.lerp(sectorColor, Colors.white, 0.3)!;
    final darkerColor = Color.lerp(sectorColor, Colors.black, 0.2)!;

    // Основная заливка с градиентом
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

    // Граница сектора с 3D эффектом
    final borderPaint = Paint()
      ..color = Colors.white.withOpacity(0.4)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    canvas.drawPath(path, borderPaint);

    // Внутренняя тень для 3D эффекта
    final innerShadowPaint = Paint()
      ..shader = ui.Gradient.radial(
        center,
        radius,
        [Colors.transparent, Colors.black.withOpacity(0.15)],
        [0.7, 1.0],
      )
      ..style = PaintingStyle.fill;

    canvas.drawPath(path, innerShadowPaint);

    // Текст сектора
    _drawSectorText(
      canvas,
      center,
      radius,
      startAngle + sectorAngle / 2,
      sector.text,
    );
  }

  void _drawSectorText(
    Canvas canvas,
    Offset center,
    double radius,
    double angle,
    String text,
  ) {
    // Адаптивный размер шрифта
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
            Shadow(
              color: Colors.black87,
              offset: Offset(1, 1),
              blurRadius: 4,
            ),
            Shadow(
              color: Colors.black54,
              offset: Offset(2, 2),
              blurRadius: 6,
            ),
          ],
        ),
      ),
      textDirection: TextDirection.ltr,
    );

    textPainter.layout();

    // Позиционируем текст радиально
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
    // Внутреннее декоративное кольцо
    final innerRingRadius = radius * 0.25;

    final innerRingPaint = Paint()
      ..shader = ui.Gradient.radial(
        center,
        innerRingRadius,
        [
          const Color(0xFFFFD700),
          const Color(0xFFB8860B),
        ],
      )
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;

    canvas.drawCircle(center, innerRingRadius, innerRingPaint);

    // Маленькие звездочки вокруг центра
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
  bool shouldRepaint(covariant PremiumWheelPainter oldDelegate) {
    return oldDelegate.glowIntensity != glowIntensity;
  }
}

/// Премиум стрелка-указатель
class PremiumPointerPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final centerX = size.width / 2;

    // Тень указателя
    final shadowPath = Path()
      ..moveTo(centerX, size.height - 5)
      ..lineTo(5, 10)
      ..lineTo(size.width - 5, 10)
      ..close();

    final shadowPaint = Paint()
      ..color = Colors.black.withOpacity(0.3)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5);

    canvas.drawPath(shadowPath.shift(const Offset(2, 3)), shadowPaint);

    // Основной указатель с градиентом
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

    // Блик на указателе
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

    // Маленький кружок внизу указателя (крепление)
    final attachPaint = Paint()
      ..shader = ui.Gradient.radial(
        Offset(centerX, 12),
        8,
        [
          const Color(0xFFFFD700),
          const Color(0xFFB8860B),
        ],
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
