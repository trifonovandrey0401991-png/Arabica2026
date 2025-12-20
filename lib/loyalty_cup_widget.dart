import 'package:flutter/material.dart';
import 'dart:math' as math;

class CoffeeCupWidget extends StatefulWidget {
  final int points; // 0-9 баллов для отображения
  final double? width;
  final double? height;

  const CoffeeCupWidget({
    super.key,
    required this.points,
    this.width,
    this.height,
  });

  @override
  State<CoffeeCupWidget> createState() => _CoffeeCupWidgetState();
}

class _CoffeeCupWidgetState extends State<CoffeeCupWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _fillAnimation;
  int _previousPoints = 0;

  @override
  void initState() {
    super.initState();
    _previousPoints = widget.points;
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    );
    _fillAnimation = Tween<double>(
      begin: _previousPoints / 9.0,
      end: widget.points / 9.0,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeInOut,
    ));
    _animationController.forward();
  }

  @override
  void didUpdateWidget(CoffeeCupWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.points != widget.points) {
      // Сохраняем текущее значение для начала анимации
      final currentFillLevel = _fillAnimation.value;
      _previousPoints = (currentFillLevel * 9).round().clamp(0, 9);
      
      _fillAnimation = Tween<double>(
        begin: _previousPoints / 9.0,
        end: widget.points / 9.0,
      ).animate(CurvedAnimation(
        parent: _animationController,
        curve: Curves.easeInOut,
      ));
      _animationController.reset();
      _animationController.forward();
    }
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cupWidth = widget.width ?? 200.0;
    final cupHeight = widget.height ?? 300.0;
    final scaleWidth = 40.0; // Ширина линейки
    final totalWidth = cupWidth + scaleWidth + 20; // Общая ширина с отступами

    return SizedBox(
      width: totalWidth,
      height: cupHeight,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Кофейный стакан
          Expanded(
            child: AnimatedBuilder(
              animation: _fillAnimation,
              builder: (context, child) {
                return CustomPaint(
                  size: Size(cupWidth, cupHeight),
                  painter: CoffeeCupPainter(
                    fillLevel: _fillAnimation.value.clamp(0.0, 1.0),
                    points: widget.points,
                  ),
                );
              },
            ),
          ),
          const SizedBox(width: 20),
          // Вертикальная линейка с делениями
          _buildScale(cupHeight),
        ],
      ),
    );
  }

  Widget _buildScale(double height) {
    return SizedBox(
      width: 40,
      height: height,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: List.generate(9, (index) {
          final scaleNumber = index + 1;
          final isActive = scaleNumber <= widget.points;
          
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Container(
                    width: 20,
                    height: 2,
                    color: isActive ? Colors.brown[700] : Colors.grey[300],
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '$scaleNumber',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
                      color: isActive ? Colors.brown[700] : Colors.grey[400],
                    ),
                  ),
                ],
              ),
              if (index < 8) // Не добавляем отступ после последнего деления
                SizedBox(height: (height - 18) / 9), // Равномерное распределение
            ],
          );
        }),
      ),
    );
  }
}

class CoffeeCupPainter extends CustomPainter {
  final double fillLevel; // 0.0 - 1.0
  final int points;

  CoffeeCupPainter({
    required this.fillLevel,
    required this.points,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint();
    final strokePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..color = Colors.brown[800]!;

    // Параметры стакана
    final cupWidth = size.width * 0.7;
    final cupHeight = size.height * 0.9;
    final cupLeft = (size.width - cupWidth) / 2;
    final cupTop = size.height * 0.05;
    final borderRadius = 15.0;

    // Рисуем контур стакана (закругленный прямоугольник)
    final cupRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(cupLeft, cupTop, cupWidth, cupHeight),
      Radius.circular(borderRadius),
    );
    
    // Фон стакана (белый/прозрачный)
    paint.color = Colors.white;
    paint.style = PaintingStyle.fill;
    canvas.drawRRect(cupRect, paint);

    // Рисуем кофе (заполнение)
    if (fillLevel > 0) {
      final fillHeight = cupHeight * fillLevel;
      final fillTop = cupTop + cupHeight - fillHeight;
      
      // Градиент для кофе
      final coffeeGradient = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Colors.brown[400]!,
          Colors.brown[700]!,
          Colors.brown[900]!,
        ],
      );
      
      paint.shader = coffeeGradient.createShader(
        Rect.fromLTWH(cupLeft, fillTop, cupWidth, fillHeight),
      );
      paint.style = PaintingStyle.fill;
      
      // Закругленный верхний край кофе
      final fillRect = RRect.fromRectAndRadius(
        Rect.fromLTWH(cupLeft, fillTop, cupWidth, fillHeight),
        Radius.circular(borderRadius),
      );
      canvas.drawRRect(fillRect, paint);
      
      // Верхняя линия кофе (более темная)
      final topLinePaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = Colors.brown[900]!;
      canvas.drawLine(
        Offset(cupLeft + borderRadius, fillTop),
        Offset(cupLeft + cupWidth - borderRadius, fillTop),
        topLinePaint,
      );
    }

    // Контур стакана
    canvas.drawRRect(cupRect, strokePaint);

    // Ручка стакана (опционально, справа)
    final handlePath = Path();
    final handleCenterX = cupLeft + cupWidth + 15;
    final handleCenterY = cupTop + cupHeight * 0.4;
    final handleRadius = 12.0;
    
    handlePath.addArc(
      Rect.fromCircle(
        center: Offset(handleCenterX, handleCenterY),
        radius: handleRadius,
      ),
      -math.pi / 2,
      math.pi,
    );
    
    strokePaint.strokeWidth = 3;
    canvas.drawPath(handlePath, strokePaint);
  }

  @override
  bool shouldRepaint(CoffeeCupPainter oldDelegate) {
    return oldDelegate.fillLevel != fillLevel || oldDelegate.points != points;
  }
}

