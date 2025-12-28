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
    
    // Цвета бренда Арабика
    final cupColor = const Color(0xFF1B4D5E); // Темно-бирюзовый/синий
    final goldColor = const Color(0xFFD4AF37); // Золотой/бронзовый
    final lidColor = Colors.black87;
    
    // Параметры стакана - высокий цилиндрический (слегка сужающийся)
    final topWidth = size.width * 0.75;
    final bottomWidth = size.width * 0.7;
    final cupBodyHeight = size.height * 0.75; // Высота тела стакана
    final lidHeight = size.height * 0.1; // Высота крышки
    final cupTop = size.height * 0.05;
    final bodyTop = cupTop + lidHeight;
    final topLeft = (size.width - topWidth) / 2;
    final bottomLeft = (size.width - bottomWidth) / 2;
    final borderRadius = 8.0;

    // Рисуем тело стакана (цилиндр с легким сужением)
    final cupPath = Path();
    
    // Верхняя часть тела (под крышкой)
    cupPath.moveTo(topLeft + borderRadius, bodyTop);
    cupPath.lineTo(topLeft + topWidth - borderRadius, bodyTop);
    cupPath.quadraticBezierTo(
      topLeft + topWidth, bodyTop,
      topLeft + topWidth, bodyTop + borderRadius,
    );
    
    // Правая сторона (слегка сужается вниз)
    cupPath.lineTo(bottomLeft + bottomWidth, bodyTop + cupBodyHeight - borderRadius);
    cupPath.quadraticBezierTo(
      bottomLeft + bottomWidth, bodyTop + cupBodyHeight,
      bottomLeft + bottomWidth - borderRadius, bodyTop + cupBodyHeight,
    );
    
    // Нижняя часть
    cupPath.lineTo(bottomLeft + borderRadius, bodyTop + cupBodyHeight);
    cupPath.quadraticBezierTo(
      bottomLeft, bodyTop + cupBodyHeight,
      bottomLeft, bodyTop + cupBodyHeight - borderRadius,
    );
    
    // Левая сторона (слегка сужается вверх)
    cupPath.lineTo(topLeft, bodyTop + borderRadius);
    cupPath.quadraticBezierTo(
      topLeft, bodyTop,
      topLeft + borderRadius, bodyTop,
    );
    cupPath.close();
    
    // Фон стакана (цвет бренда)
    paint.color = cupColor;
    paint.style = PaintingStyle.fill;
    canvas.drawPath(cupPath, paint);
    
    // Контур стакана
    final strokePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = cupColor.withOpacity(0.8);
    canvas.drawPath(cupPath, strokePaint);

    // Рисуем кофе (заполнение)
    if (fillLevel > 0) {
      final fillHeight = cupBodyHeight * fillLevel;
      final fillTop = bodyTop + cupBodyHeight - fillHeight;
      
      // Ширина на уровне заполнения (линейная интерполяция)
      final fillTopWidth = topWidth - (topWidth - bottomWidth) * 
          ((bodyTop + cupBodyHeight - fillTop) / cupBodyHeight);
      final fillBottomWidth = bottomWidth;
      final fillTopLeft = (size.width - fillTopWidth) / 2;
      final fillBottomLeft = (size.width - fillBottomWidth) / 2;
      
      // Градиент для кофе
      final coffeeGradient = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Colors.brown[400]!,
          Colors.brown[600]!,
          Colors.brown[800]!,
          Colors.brown[900]!,
        ],
        stops: const [0.0, 0.3, 0.7, 1.0],
      );
      
      // Путь для кофе
      final coffeePath = Path();
      coffeePath.moveTo(fillTopLeft, fillTop);
      coffeePath.lineTo(fillTopLeft + fillTopWidth, fillTop);
      coffeePath.lineTo(fillBottomLeft + fillBottomWidth, bodyTop + cupBodyHeight);
      coffeePath.lineTo(fillBottomLeft, bodyTop + cupBodyHeight);
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
      
      // Верхняя линия кофе (более темная)
      final topLinePaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = Colors.brown[900]!;
      canvas.drawLine(
        Offset(fillTopLeft, fillTop),
        Offset(fillTopLeft + fillTopWidth, fillTop),
        topLinePaint,
      );
    }

    // Рисуем крышку (черная пластиковая)
    final lidPath = Path();
    final lidTopWidth = topWidth * 1.05; // Крышка немного шире
    final lidTopLeft = (size.width - lidTopWidth) / 2;
    final lidRadius = 6.0;
    
    lidPath.moveTo(lidTopLeft + lidRadius, cupTop);
    lidPath.lineTo(lidTopLeft + lidTopWidth - lidRadius, cupTop);
    lidPath.quadraticBezierTo(
      lidTopLeft + lidTopWidth, cupTop,
      lidTopLeft + lidTopWidth, cupTop + lidRadius,
    );
    lidPath.lineTo(lidTopLeft + lidTopWidth, bodyTop - 2);
    lidPath.lineTo(topLeft + topWidth, bodyTop);
    lidPath.lineTo(topLeft, bodyTop);
    lidPath.lineTo(lidTopLeft, bodyTop - 2);
    lidPath.lineTo(lidTopLeft, cupTop + lidRadius);
    lidPath.quadraticBezierTo(
      lidTopLeft, cupTop,
      lidTopLeft + lidRadius, cupTop,
    );
    lidPath.close();
    
    paint.shader = null;
    paint.color = lidColor;
    paint.style = PaintingStyle.fill;
    canvas.drawPath(lidPath, paint);
    
    // Ободок крышки
    final lidRimPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = Colors.black;
    canvas.drawLine(
      Offset(topLeft, bodyTop),
      Offset(topLeft + topWidth, bodyTop),
      lidRimPaint,
    );
    
    // Рисуем брендинг (золотые элементы)
    final textPaint = Paint()
      ..color = goldColor
      ..style = PaintingStyle.fill;
    
    // Логотип (стилизованное кофейное зерно) - в верхней части стакана
    final logoCenterX = size.width / 2;
    final logoCenterY = bodyTop + cupBodyHeight * 0.25;
    final logoSize = topWidth * 0.15;
    
    // Рисуем простой логотип (овал с линией)
    final logoPath = Path();
    logoPath.addOval(Rect.fromCenter(
      center: Offset(logoCenterX, logoCenterY),
      width: logoSize,
      height: logoSize * 0.7,
    ));
    logoPath.moveTo(logoCenterX - logoSize * 0.3, logoCenterY);
    logoPath.lineTo(logoCenterX + logoSize * 0.3, logoCenterY);
    
    final logoPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = goldColor;
    canvas.drawPath(logoPath, logoPaint);
    
    // Текст "Арабика"
    final arabicaY = bodyTop + cupBodyHeight * 0.4;
    final arabicaText = TextSpan(
      text: 'Арабика',
      style: TextStyle(
        color: goldColor,
        fontSize: topWidth * 0.12,
        fontWeight: FontWeight.bold,
        letterSpacing: 1.2,
      ),
    );
    final arabicaPainter = TextPainter(
      text: arabicaText,
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
    );
    arabicaPainter.layout();
    arabicaPainter.paint(
      canvas,
      Offset(logoCenterX - arabicaPainter.width / 2, arabicaY),
    );
  }

  @override
  bool shouldRepaint(CoffeeCupPainter oldDelegate) {
    return oldDelegate.fillLevel != fillLevel || oldDelegate.points != points;
  }
}

