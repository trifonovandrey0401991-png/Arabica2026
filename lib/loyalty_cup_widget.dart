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
    final scaleWidth = 50.0; // Ширина линейки
    final totalWidth = cupWidth + scaleWidth + 20; // Общая ширина с отступами
    
    // Высота стакана (без учета верхнего отступа)
    final actualCupHeight = cupHeight * 0.9;

    return SizedBox(
      width: totalWidth,
      height: cupHeight,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Кофейный стакан
          SizedBox(
            width: cupWidth,
            height: cupHeight,
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
          // Вертикальная линейка с делениями - точно такой же высоты как стакан
          _buildScale(actualCupHeight, cupHeight * 0.05),
        ],
      ),
    );
  }

  Widget _buildScale(double scaleHeight, double topOffset) {
    // Каждое деление = 1/9 высоты стакана
    final divisionHeight = scaleHeight / 9;
    
    return SizedBox(
      width: 50,
      height: scaleHeight + topOffset,
      child: Stack(
        children: [
          // Вертикальная линия линейки
          Positioned(
            left: 0,
            top: topOffset,
            child: Container(
              width: 3,
              height: scaleHeight,
              color: Colors.grey[400],
            ),
          ),
          // Деления и цифры
          ...List.generate(9, (index) {
            final scaleNumber = index + 1;
            final isActive = scaleNumber <= widget.points;
            // Позиция деления: снизу вверх
            // Деление 1 на высоте 1/9 от дна, деление 9 на высоте 9/9 (верх)
            final positionFromBottom = scaleNumber * divisionHeight;
            final positionFromTop = topOffset + scaleHeight - positionFromBottom;
            
            return Positioned(
              left: 0,
              top: positionFromTop - 1.5, // Центрируем деление (высота деления 3)
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Container(
                    width: 18,
                    height: 3,
                    decoration: BoxDecoration(
                      color: isActive ? Colors.brown[700] : Colors.grey[300],
                      borderRadius: BorderRadius.circular(1.5),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '$scaleNumber',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
                      color: isActive ? Colors.brown[700] : Colors.grey[400],
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
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
      ..strokeWidth = 4
      ..color = Colors.brown[800]!;

    // Параметры стакана - трапециевидная форма (сверху шире)
    final topWidth = size.width * 0.85;
    final bottomWidth = size.width * 0.65;
    final cupHeight = size.height * 0.9;
    final cupTop = size.height * 0.05;
    final topLeft = (size.width - topWidth) / 2;
    final bottomLeft = (size.width - bottomWidth) / 2;
    final borderRadius = 12.0;

    // Создаем путь для стакана (трапеция с закругленными углами)
    final cupPath = Path();
    
    // Верхняя часть (закругленная)
    cupPath.moveTo(topLeft + borderRadius, cupTop);
    cupPath.lineTo(topLeft + topWidth - borderRadius, cupTop);
    cupPath.quadraticBezierTo(
      topLeft + topWidth, cupTop,
      topLeft + topWidth, cupTop + borderRadius,
    );
    
    // Правая сторона (сужается вниз)
    cupPath.lineTo(bottomLeft + bottomWidth, cupTop + cupHeight - borderRadius);
    cupPath.quadraticBezierTo(
      bottomLeft + bottomWidth, cupTop + cupHeight,
      bottomLeft + bottomWidth - borderRadius, cupTop + cupHeight,
    );
    
    // Нижняя часть
    cupPath.lineTo(bottomLeft + borderRadius, cupTop + cupHeight);
    cupPath.quadraticBezierTo(
      bottomLeft, cupTop + cupHeight,
      bottomLeft, cupTop + cupHeight - borderRadius,
    );
    
    // Левая сторона (сужается вверх)
    cupPath.lineTo(topLeft, cupTop + borderRadius);
    cupPath.quadraticBezierTo(
      topLeft, cupTop,
      topLeft + borderRadius, cupTop,
    );
    cupPath.close();
    
    // Фон стакана (белый)
    paint.color = Colors.white;
    paint.style = PaintingStyle.fill;
    canvas.drawPath(cupPath, paint);

    // Рисуем кофе (заполнение)
    if (fillLevel > 0) {
      final fillHeight = cupHeight * fillLevel;
      final fillTop = cupTop + cupHeight - fillHeight;
      
      // Ширина на уровне заполнения (линейная интерполяция)
      final fillTopWidth = topWidth - (topWidth - bottomWidth) * 
          ((cupTop + cupHeight - fillTop) / cupHeight);
      final fillBottomWidth = bottomWidth;
      final fillTopLeft = (size.width - fillTopWidth) / 2;
      final fillBottomLeft = (size.width - fillBottomWidth) / 2;
      
      // Градиент для кофе
      final coffeeGradient = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Colors.brown[300]!,
          Colors.brown[600]!,
          Colors.brown[800]!,
          Colors.brown[900]!,
        ],
        stops: const [0.0, 0.3, 0.7, 1.0],
      );
      
      // Путь для кофе (трапеция)
      final coffeePath = Path();
      coffeePath.moveTo(fillTopLeft, fillTop);
      coffeePath.lineTo(fillTopLeft + fillTopWidth, fillTop);
      coffeePath.lineTo(fillBottomLeft + fillBottomWidth, cupTop + cupHeight);
      coffeePath.lineTo(fillBottomLeft, cupTop + cupHeight);
      coffeePath.close();
      
      paint.shader = coffeeGradient.createShader(
        Rect.fromLTWH(
          fillBottomLeft,
          fillTop,
          fillBottomWidth,
          fillHeight,
        ),
      );
      paint.style = PaintingStyle.fill;
      canvas.drawPath(coffeePath, paint);
      
      // Верхняя линия кофе (более темная, с пенкой)
      final topLinePaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..color = Colors.brown[900]!;
      canvas.drawLine(
        Offset(fillTopLeft, fillTop),
        Offset(fillTopLeft + fillTopWidth, fillTop),
        topLinePaint,
      );
      
      // Пенка (светлая полоска сверху)
      final foamPaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = Colors.brown[200]!;
      canvas.drawLine(
        Offset(fillTopLeft + 5, fillTop - 2),
        Offset(fillTopLeft + fillTopWidth - 5, fillTop - 2),
        foamPaint,
      );
    }

    // Контур стакана
    canvas.drawPath(cupPath, strokePaint);

    // Ручка стакана (полукруг справа)
    final handlePath = Path();
    final handleCenterX = topLeft + topWidth + 20;
    final handleCenterY = cupTop + cupHeight * 0.45;
    final handleRadius = 18.0;
    final handleThickness = 8.0;
    
    // Внешняя дуга ручки
    handlePath.addArc(
      Rect.fromCircle(
        center: Offset(handleCenterX, handleCenterY),
        radius: handleRadius,
      ),
      -math.pi / 2 - 0.3,
      math.pi + 0.6,
    );
    
    strokePaint.strokeWidth = 5;
    strokePaint.strokeCap = StrokeCap.round;
    canvas.drawPath(handlePath, strokePaint);
  }

  @override
  bool shouldRepaint(CoffeeCupPainter oldDelegate) {
    return oldDelegate.fillLevel != fillLevel || oldDelegate.points != points;
  }
}

