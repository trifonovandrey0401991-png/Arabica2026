import 'dart:math';
import 'package:flutter/material.dart';
import '../models/loyalty_gamification_model.dart';
import '../../../core/constants/api_constants.dart';

/// Виджет отображения значков (ачивок) вокруг QR-кода
class QrBadgesWidget extends StatefulWidget {
  final Widget qrWidget;
  final List<LoyaltyLevel> earnedLevels;

  const QrBadgesWidget({
    super.key,
    required this.qrWidget,
    required this.earnedLevels,
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
  static const double _badgeSize = 80.0;
  // Смещение = badgeSize - 12 (белая рамка QR = 12px), бейджи не заходят на данные QR
  static const double _edgeOffset = _badgeSize - 12;

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

  @override
  Widget build(BuildContext context) {
    // Запускаем анимацию при первом построении
    if (!_animationStarted && widget.earnedLevels.isNotEmpty) {
      _animationStarted = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _animationController.forward();
      });
    }

    // Распределяем значки по 4 сторонам: сверху, справа, снизу, слева
    final badges = widget.earnedLevels;
    final n = badges.length.clamp(0, 8);
    final top = <LoyaltyLevel>[];
    final right = <LoyaltyLevel>[];
    final bottom = <LoyaltyLevel>[];
    final left = <LoyaltyLevel>[];

    if (n >= 1) top.add(badges[0]);
    if (n >= 2) bottom.add(badges[1]);
    if (n >= 3) right.add(badges[2]);
    if (n >= 4) left.add(badges[3]);
    if (n >= 5) top.add(badges[4]);
    if (n >= 6) bottom.add(badges[5]);
    if (n >= 7) right.add(badges[6]);
    if (n >= 8) left.add(badges[7]);

    return Stack(
      clipBehavior: Clip.none,
      children: [
        // QR-код определяет размер виджета
        widget.qrWidget,
        // Значки сверху
        if (top.isNotEmpty)
          Positioned(
            top: -_edgeOffset,
            left: 0, right: 0,
            child: _buildBadgeRow(top),
          ),
        // Значки справа
        if (right.isNotEmpty)
          Positioned(
            right: -_edgeOffset,
            top: 0, bottom: 0,
            child: _buildBadgeColumn(right),
          ),
        // Значки снизу
        if (bottom.isNotEmpty)
          Positioned(
            bottom: -_edgeOffset,
            left: 0, right: 0,
            child: _buildBadgeRow(bottom),
          ),
        // Значки слева
        if (left.isNotEmpty)
          Positioned(
            left: -_edgeOffset,
            top: 0, bottom: 0,
            child: _buildBadgeColumn(left),
          ),
      ],
    );
  }

  Widget _buildBadgeRow(List<LoyaltyLevel> levels) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        for (final level in levels)
          ScaleTransition(
            scale: _scaleAnimation,
            child: _StickerBadge(level: level, size: _badgeSize),
          ),
      ],
    );
  }

  Widget _buildBadgeColumn(List<LoyaltyLevel> levels) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        for (final level in levels)
          ScaleTransition(
            scale: _scaleAnimation,
            child: _StickerBadge(level: level, size: _badgeSize),
          ),
      ],
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
