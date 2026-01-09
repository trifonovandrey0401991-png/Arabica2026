import 'dart:math';
import 'package:flutter/material.dart';
import '../models/fortune_wheel_model.dart';

/// Анимированное колесо удачи
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
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;
  double _currentRotation = 0;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 4000),
      vsync: this,
    );

    _animation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
    );

    _controller.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        widget.onSpinComplete?.call();
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Запустить вращение к указанному сектору
  void spinToSector(int sectorIndex) {
    if (_controller.isAnimating) return;

    final sectorAngle = 2 * pi / widget.sectors.length;
    // Центр сектора
    final targetAngle = sectorAngle * sectorIndex + sectorAngle / 2;
    // Минимум 5 полных оборотов + нужный угол
    final fullRotations = 5 * 2 * pi;
    // Вращаем против часовой стрелки, стрелка сверху
    final totalRotation = fullRotations + (2 * pi - targetAngle);

    _animation = Tween<double>(
      begin: _currentRotation,
      end: _currentRotation + totalRotation,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
    ));

    _controller.forward(from: 0).then((_) {
      _currentRotation = _animation.value % (2 * pi);
    });
  }

  @override
  Widget build(BuildContext context) {
    // Получаем размер экрана для адаптивного колеса
    final screenWidth = MediaQuery.of(context).size.width;
    final wheelSize = screenWidth * 0.9; // 90% ширины экрана

    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        return Stack(
          alignment: Alignment.center,
          children: [
            // Колесо
            Transform.rotate(
              angle: _animation.value,
              child: CustomPaint(
                size: Size(wheelSize, wheelSize),
                painter: WheelPainter(sectors: widget.sectors),
              ),
            ),
            // Стрелка сверху
            Positioned(
              top: 0,
              child: CustomPaint(
                size: const Size(40, 35),
                painter: PointerPainter(),
              ),
            ),
            // Центральный круг
            Container(
              width: 70,
              height: 70,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white,
                border: Border.all(color: const Color(0xFF004D40), width: 4),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.3),
                    blurRadius: 10,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: const Icon(
                Icons.star,
                color: Color(0xFF004D40),
                size: 35,
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Рисование колеса
class WheelPainter extends CustomPainter {
  final List<FortuneWheelSector> sectors;

  WheelPainter({required this.sectors});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;
    final sectorAngle = 2 * pi / sectors.length;

    // Рисуем секторы
    for (int i = 0; i < sectors.length; i++) {
      final startAngle = -pi / 2 + i * sectorAngle;

      // Заливка сектора
      final paint = Paint()
        ..color = sectors[i].color
        ..style = PaintingStyle.fill;

      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        startAngle,
        sectorAngle,
        true,
        paint,
      );

      // Граница сектора
      final borderPaint = Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2;

      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        startAngle,
        sectorAngle,
        true,
        borderPaint,
      );

      // Текст сектора
      _drawSectorText(canvas, center, radius, startAngle + sectorAngle / 2, sectors[i].text);
    }

    // Внешний круг
    final outerBorderPaint = Paint()
      ..color = const Color(0xFF004D40)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4;

    canvas.drawCircle(center, radius, outerBorderPaint);
  }

  void _drawSectorText(Canvas canvas, Offset center, double radius,
      double angle, String text) {
    // Адаптивный размер шрифта в зависимости от радиуса
    final fontSize = radius * 0.07;

    final textPainter = TextPainter(
      text: TextSpan(
        text: _truncateText(text, 15),
        style: TextStyle(
          color: Colors.white,
          fontSize: fontSize.clamp(10.0, 14.0),
          fontWeight: FontWeight.bold,
          shadows: const [
            Shadow(
              color: Colors.black87,
              offset: Offset(1, 1),
              blurRadius: 3,
            ),
          ],
        ),
      ),
      textDirection: TextDirection.ltr,
    );

    textPainter.layout();

    // Позиционируем текст радиально - от центра к краю
    // Располагаем текст в середине сектора по радиусу
    final textRadius = radius * 0.6;

    canvas.save();

    // Перемещаемся к центру колеса
    canvas.translate(center.dx, center.dy);

    // Поворачиваем на угол сектора
    canvas.rotate(angle);

    // Рисуем текст вдоль радиуса (от центра наружу)
    // Смещаем текст к внешнему краю
    textPainter.paint(
      canvas,
      Offset(textRadius - textPainter.width / 2, -textPainter.height / 2),
    );

    canvas.restore();
  }

  String _truncateText(String text, int maxLength) {
    if (text.length <= maxLength) return text;
    return '${text.substring(0, maxLength - 1)}…';
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Рисование стрелки-указателя
class PointerPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF004D40)
      ..style = PaintingStyle.fill;

    final path = Path();
    path.moveTo(size.width / 2, size.height);
    path.lineTo(0, 0);
    path.lineTo(size.width, 0);
    path.close();

    canvas.drawPath(path, paint);

    // Тень
    final shadowPaint = Paint()
      ..color = Colors.black.withOpacity(0.3)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);

    canvas.drawPath(path.shift(const Offset(2, 2)), shadowPaint);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
