import 'dart:math';
import 'package:flutter/material.dart';
import '../models/loyalty_gamification_model.dart';
import '../../../core/constants/api_constants.dart';

/// Виджет отображения значков (ачивок) вокруг QR-кода
class QrBadgesWidget extends StatefulWidget {
  final Widget qrWidget;
  final List<LoyaltyLevel> earnedLevels;
  final double qrSize;

  const QrBadgesWidget({
    super.key,
    required this.qrWidget,
    required this.earnedLevels,
    this.qrSize = 200,
  });

  @override
  State<QrBadgesWidget> createState() => _QrBadgesWidgetState();
}

class _QrBadgesWidgetState extends State<QrBadgesWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _scaleAnimation;

  bool _animationStarted = false;

  // Размеры
  static const double _badgeSize = 88.0; // Размер значков (увеличен в 2 раза)
  static const double _containerPadding = 100.0; // Отступ для значков вокруг QR

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );
    _scaleAnimation = CurvedAnimation(
      parent: _animationController,
      curve: Curves.elasticOut,
    );
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  /// 8 фиксированных позиций вокруг QR-кода (как показано на скриншоте)
  /// Позиции: 4 угла карточки + 4 позиции по середине сторон QR
  List<Offset> _getFixedPositions() {
    final containerSize = widget.qrSize + _containerPadding * 2;
    final qrStart = _containerPadding;
    final qrEnd = _containerPadding + widget.qrSize;
    final halfBadge = _badgeSize / 2;

    // 8 позиций: углы внешние и по сторонам QR-кода
    return [
      // Верхний левый угол карточки
      Offset(0, 0),
      // Верхний правый угол карточки
      Offset(containerSize - _badgeSize, 0),
      // Нижний левый угол карточки
      Offset(0, containerSize - _badgeSize),
      // Нижний правый угол карточки
      Offset(containerSize - _badgeSize, containerSize - _badgeSize),
      // Слева от QR (по центру высоты)
      Offset(0, (containerSize - _badgeSize) / 2),
      // Справа от QR (по центру высоты)
      Offset(containerSize - _badgeSize, (containerSize - _badgeSize) / 2),
      // Сверху QR слева
      Offset(qrStart - halfBadge, 0),
      // Сверху QR справа
      Offset(qrEnd - halfBadge, 0),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final containerSize = widget.qrSize + _containerPadding * 2;
    final positions = _getFixedPositions();

    // Запускаем анимацию при первом построении
    if (!_animationStarted && widget.earnedLevels.isNotEmpty) {
      _animationStarted = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _animationController.forward();
      });
    }

    return SizedBox(
      width: containerSize,
      height: containerSize,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // QR-код по центру
          Positioned(
            left: _containerPadding,
            top: _containerPadding,
            child: SizedBox(
              width: widget.qrSize,
              height: widget.qrSize,
              child: widget.qrWidget,
            ),
          ),
          // Значки в фиксированных позициях (до 8 штук)
          for (int i = 0; i < widget.earnedLevels.length && i < positions.length; i++)
            Positioned(
              left: positions[i].dx,
              top: positions[i].dy,
              child: ScaleTransition(
                scale: _scaleAnimation,
                child: _StickerBadge(
                  level: widget.earnedLevels[i],
                  size: _badgeSize,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Значок в форме "наклейки" с зубчатыми краями
class _StickerBadge extends StatelessWidget {
  final LoyaltyLevel level;
  final double size;

  const _StickerBadge({
    required this.level,
    required this.size,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: level.name,
      child: SizedBox(
        width: size,
        height: size,
        child: level.badge.type == 'icon'
            ? CustomPaint(
                painter: _StickerPainter(
                  color: level.color,
                  teethCount: 12,
                ),
                child: Center(
                  child: Icon(
                    level.badge.getIcon() ?? Icons.emoji_events,
                    color: Colors.white,
                    size: size * 0.5,
                  ),
                ),
              )
            : ClipPath(
                clipper: _StickerClipper(teethCount: 12),
                child: Image.network(
                  _getImageUrl(level.badge.value),
                  width: size,
                  height: size,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => CustomPaint(
                    painter: _StickerPainter(
                      color: level.color,
                      teethCount: 12,
                    ),
                    child: Center(
                      child: Icon(
                        Icons.emoji_events,
                        color: Colors.white,
                        size: size * 0.5,
                      ),
                    ),
                  ),
                ),
              ),
      ),
    );
  }

  String _getImageUrl(String value) {
    if (value.startsWith('http://') || value.startsWith('https://')) {
      return value;
    }
    // Если путь начинается с /, это уже путь от корня сервера
    if (value.startsWith('/')) {
      return '${ApiConstants.serverUrl}$value';
    }
    // Иначе добавляем путь к значкам
    return '${ApiConstants.serverUrl}/loyalty-gamification/badges/$value';
  }
}

/// Clipper для обрезки изображения по зубчатой форме
class _StickerClipper extends CustomClipper<Path> {
  final int teethCount;

  _StickerClipper({this.teethCount = 12});

  @override
  Path getClip(Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final outerRadius = size.width / 2;
    final innerRadius = outerRadius * 0.82;
    final teethAngle = 2 * pi / teethCount;

    final path = Path();

    for (int i = 0; i < teethCount; i++) {
      final angle1 = i * teethAngle - pi / 2;

      if (i == 0) {
        path.moveTo(
          center.dx + outerRadius * cos(angle1),
          center.dy + outerRadius * sin(angle1),
        );
      }

      path.lineTo(
        center.dx + outerRadius * cos(angle1),
        center.dy + outerRadius * sin(angle1),
      );

      final controlAngle = angle1 + teethAngle / 2;

      path.quadraticBezierTo(
        center.dx + innerRadius * cos(controlAngle),
        center.dy + innerRadius * sin(controlAngle),
        center.dx + outerRadius * cos(angle1 + teethAngle),
        center.dy + outerRadius * sin(angle1 + teethAngle),
      );
    }

    path.close();
    return path;
  }

  @override
  bool shouldReclip(covariant _StickerClipper oldClipper) {
    return oldClipper.teethCount != teethCount;
  }
}

/// Рисует зубчатую форму "наклейки/медали"
class _StickerPainter extends CustomPainter {
  final Color color;
  final int teethCount;

  _StickerPainter({
    required this.color,
    this.teethCount = 12,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final outerRadius = size.width / 2;
    final innerRadius = outerRadius * 0.82; // Глубина зубцов
    final teethAngle = 2 * pi / teethCount;

    // Тень
    final shadowPaint = Paint()
      ..color = color.withOpacity(0.4)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);

    final shadowPath = _createStickerPath(
      center + const Offset(0, 2),
      outerRadius,
      innerRadius,
      teethAngle,
    );
    canvas.drawPath(shadowPath, shadowPaint);

    // Основная форма с градиентом
    final gradient = RadialGradient(
      colors: [
        Color.lerp(color, Colors.white, 0.2)!,
        color,
        Color.lerp(color, Colors.black, 0.1)!,
      ],
      stops: const [0.0, 0.5, 1.0],
    );

    final mainPaint = Paint()
      ..shader = gradient.createShader(
        Rect.fromCircle(center: center, radius: outerRadius),
      );

    final mainPath = _createStickerPath(
      center,
      outerRadius,
      innerRadius,
      teethAngle,
    );
    canvas.drawPath(mainPath, mainPaint);

    // Внутренний круг (светлее)
    final innerCirclePaint = Paint()
      ..color = Color.lerp(color, Colors.white, 0.15)!;

    canvas.drawCircle(center, innerRadius * 0.85, innerCirclePaint);

    // Блик сверху
    final highlightPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.center,
        colors: [
          Colors.white.withOpacity(0.3),
          Colors.white.withOpacity(0.0),
        ],
      ).createShader(
        Rect.fromCircle(center: center, radius: innerRadius * 0.8),
      );

    canvas.drawCircle(
      center - Offset(0, innerRadius * 0.2),
      innerRadius * 0.5,
      highlightPaint,
    );
  }

  Path _createStickerPath(
    Offset center,
    double outerRadius,
    double innerRadius,
    double teethAngle,
  ) {
    final path = Path();

    for (int i = 0; i < teethCount; i++) {
      final angle1 = i * teethAngle - pi / 2;
      final angle2 = angle1 + teethAngle / 2;

      if (i == 0) {
        path.moveTo(
          center.dx + outerRadius * cos(angle1),
          center.dy + outerRadius * sin(angle1),
        );
      }

      // Внешняя точка зубца
      path.lineTo(
        center.dx + outerRadius * cos(angle1),
        center.dy + outerRadius * sin(angle1),
      );

      // Внутренняя точка между зубцами (плавная кривая)
      final controlAngle = angle2;

      path.quadraticBezierTo(
        center.dx + innerRadius * cos(controlAngle),
        center.dy + innerRadius * sin(controlAngle),
        center.dx + outerRadius * cos(angle1 + teethAngle),
        center.dy + outerRadius * sin(angle1 + teethAngle),
      );
    }

    path.close();
    return path;
  }

  @override
  bool shouldRepaint(covariant _StickerPainter oldDelegate) {
    return oldDelegate.color != color || oldDelegate.teethCount != teethCount;
  }
}
