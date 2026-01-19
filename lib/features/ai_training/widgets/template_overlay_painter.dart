import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../models/photo_template.dart';

/// CustomPainter для отрисовки overlay-схемы поверх камеры
class TemplateOverlayPainter extends CustomPainter {
  final PhotoTemplate template;
  final Color overlayColor;
  final double strokeWidth;

  TemplateOverlayPainter({
    required this.template,
    this.overlayColor = Colors.yellow,
    this.strokeWidth = 3.0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = overlayColor.withOpacity(0.7)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;

    final fillPaint = Paint()
      ..color = overlayColor.withOpacity(0.15)
      ..style = PaintingStyle.fill;

    final center = Offset(size.width / 2, size.height / 2);

    switch (template.overlayType) {
      case OverlayType.center:
        _drawCenterPack(canvas, size, center, paint, fillPaint);
        break;
      case OverlayType.angled:
        _drawAngledPack(canvas, size, center, paint, fillPaint);
        break;
      case OverlayType.row:
        _drawRowPacks(canvas, size, center, paint, fillPaint);
        break;
      case OverlayType.stack:
        _drawStackPacks(canvas, size, center, paint, fillPaint);
        break;
      case OverlayType.hand:
        _drawHandWithPack(canvas, size, center, paint, fillPaint);
        break;
      case OverlayType.shelf:
        _drawShelfWithPack(canvas, size, center, paint, fillPaint);
        break;
      case OverlayType.side:
        _drawSidePack(canvas, size, center, paint, fillPaint);
        break;
      case OverlayType.large:
        _drawLargePack(canvas, size, center, paint, fillPaint);
        break;
      case OverlayType.small:
        _drawSmallPack(canvas, size, center, paint, fillPaint);
        break;
    }
  }

  /// Одна пачка по центру
  void _drawCenterPack(Canvas canvas, Size size, Offset center, Paint paint, Paint fillPaint) {
    final packWidth = size.width * template.packScale;
    final packHeight = packWidth * 1.6; // Соотношение сторон пачки сигарет

    final rect = Rect.fromCenter(
      center: center,
      width: packWidth,
      height: packHeight,
    );

    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(8)),
      fillPaint,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(8)),
      paint,
    );

    // Крестик по центру
    _drawCrosshair(canvas, center, paint);
  }

  /// Пачка под углом 45°
  void _drawAngledPack(Canvas canvas, Size size, Offset center, Paint paint, Paint fillPaint) {
    final packWidth = size.width * template.packScale;
    final packHeight = packWidth * 1.6;

    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(template.packAngle * math.pi / 180);

    final rect = Rect.fromCenter(
      center: Offset.zero,
      width: packWidth,
      height: packHeight,
    );

    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(8)),
      fillPaint,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(8)),
      paint,
    );

    canvas.restore();

    // Стрелка показывающая направление поворота
    _drawRotationArrow(canvas, center, size, paint);
  }

  /// Несколько пачек в ряд
  void _drawRowPacks(Canvas canvas, Size size, Offset center, Paint paint, Paint fillPaint) {
    final packWidth = size.width * template.packScale;
    final packHeight = packWidth * 1.6;
    final gap = packWidth * 0.15;

    final totalWidth = template.packCount * packWidth + (template.packCount - 1) * gap;
    final startX = center.dx - totalWidth / 2 + packWidth / 2;

    for (int i = 0; i < template.packCount; i++) {
      final packCenter = Offset(startX + i * (packWidth + gap), center.dy);
      final rect = Rect.fromCenter(
        center: packCenter,
        width: packWidth,
        height: packHeight,
      );

      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(6)),
        fillPaint,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(6)),
        paint,
      );
    }
  }

  /// Пачки стопкой вертикально
  void _drawStackPacks(Canvas canvas, Size size, Offset center, Paint paint, Paint fillPaint) {
    final packWidth = size.width * template.packScale;
    final packHeight = packWidth * 0.4; // Видим сверху — тоньше
    final gap = packHeight * 0.3;

    final totalHeight = template.packCount * packHeight + (template.packCount - 1) * gap;
    final startY = center.dy - totalHeight / 2 + packHeight / 2;

    for (int i = 0; i < template.packCount; i++) {
      final packCenter = Offset(center.dx, startY + i * (packHeight + gap));
      final rect = Rect.fromCenter(
        center: packCenter,
        width: packWidth,
        height: packHeight,
      );

      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(4)),
        fillPaint,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(4)),
        paint,
      );
    }

    // Стрелка вверх показывающая стопку
    final arrowPaint = Paint()
      ..color = overlayColor.withOpacity(0.5)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    final arrowPath = Path()
      ..moveTo(center.dx - packWidth / 2 - 20, center.dy + totalHeight / 2)
      ..lineTo(center.dx - packWidth / 2 - 20, center.dy - totalHeight / 2 - 10)
      ..lineTo(center.dx - packWidth / 2 - 30, center.dy - totalHeight / 2 + 10)
      ..moveTo(center.dx - packWidth / 2 - 20, center.dy - totalHeight / 2 - 10)
      ..lineTo(center.dx - packWidth / 2 - 10, center.dy - totalHeight / 2 + 10);

    canvas.drawPath(arrowPath, arrowPaint);
  }

  /// Пачка в руке
  void _drawHandWithPack(Canvas canvas, Size size, Offset center, Paint paint, Paint fillPaint) {
    // Контур руки (упрощённый)
    final handPaint = Paint()
      ..color = overlayColor.withOpacity(0.3)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    final handPath = Path();
    final handCenter = Offset(center.dx, center.dy + size.height * 0.1);

    // Ладонь
    handPath.addOval(Rect.fromCenter(
      center: Offset(handCenter.dx, handCenter.dy + 40),
      width: size.width * 0.35,
      height: size.width * 0.25,
    ));

    // Пальцы (упрощённо)
    for (int i = 0; i < 4; i++) {
      final fingerX = handCenter.dx - 40 + i * 25;
      handPath.moveTo(fingerX, handCenter.dy + 20);
      handPath.lineTo(fingerX, handCenter.dy - 30);
    }

    canvas.drawPath(handPath, handPaint);

    // Пачка в руке
    final packWidth = size.width * template.packScale;
    final packHeight = packWidth * 1.6;
    final packCenter = Offset(center.dx, center.dy - packHeight * 0.2);

    final rect = Rect.fromCenter(
      center: packCenter,
      width: packWidth,
      height: packHeight,
    );

    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(8)),
      fillPaint,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(8)),
      paint,
    );
  }

  /// Пачка на полке
  void _drawShelfWithPack(Canvas canvas, Size size, Offset center, Paint paint, Paint fillPaint) {
    // Линия полки
    final shelfPaint = Paint()
      ..color = overlayColor.withOpacity(0.4)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4;

    final shelfY = center.dy + size.height * 0.15;
    canvas.drawLine(
      Offset(size.width * 0.1, shelfY),
      Offset(size.width * 0.9, shelfY),
      shelfPaint,
    );

    // Пачка на полке
    final packWidth = size.width * template.packScale;
    final packHeight = packWidth * 1.6;
    final packCenter = Offset(center.dx, shelfY - packHeight / 2 - 5);

    final rect = Rect.fromCenter(
      center: packCenter,
      width: packWidth,
      height: packHeight,
    );

    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(8)),
      fillPaint,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(8)),
      paint,
    );
  }

  /// Боковая грань пачки
  void _drawSidePack(Canvas canvas, Size size, Offset center, Paint paint, Paint fillPaint) {
    final packWidth = size.width * template.packScale;
    final packHeight = packWidth * 5; // Узкая боковая грань

    final rect = Rect.fromCenter(
      center: center,
      width: packWidth,
      height: packHeight,
    );

    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(4)),
      fillPaint,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(4)),
      paint,
    );

    // Стрелка показывающая поворот
    _drawRotationArrow(canvas, center, size, paint, isVertical: true);
  }

  /// Крупный план — большая пачка
  void _drawLargePack(Canvas canvas, Size size, Offset center, Paint paint, Paint fillPaint) {
    final packWidth = size.width * template.packScale;
    final packHeight = packWidth * 1.4; // Чуть меньше соотношение для большого размера

    final rect = Rect.fromCenter(
      center: center,
      width: packWidth,
      height: packHeight,
    );

    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(12)),
      fillPaint,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(12)),
      paint,
    );

    // Стрелки внутрь показывающие приближение
    _drawZoomInArrows(canvas, center, size, paint);
  }

  /// Средний план — маленькая пачка
  void _drawSmallPack(Canvas canvas, Size size, Offset center, Paint paint, Paint fillPaint) {
    final packWidth = size.width * template.packScale;
    final packHeight = packWidth * 1.6;

    final rect = Rect.fromCenter(
      center: center,
      width: packWidth,
      height: packHeight,
    );

    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(6)),
      fillPaint,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(6)),
      paint,
    );

    // Стрелки наружу показывающие отдаление
    _drawZoomOutArrows(canvas, center, size, paint);
  }

  /// Крестик по центру
  void _drawCrosshair(Canvas canvas, Offset center, Paint paint) {
    final crossPaint = Paint()
      ..color = paint.color.withOpacity(0.5)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    const crossSize = 20.0;
    canvas.drawLine(
      Offset(center.dx - crossSize, center.dy),
      Offset(center.dx + crossSize, center.dy),
      crossPaint,
    );
    canvas.drawLine(
      Offset(center.dx, center.dy - crossSize),
      Offset(center.dx, center.dy + crossSize),
      crossPaint,
    );
  }

  /// Стрелка поворота
  void _drawRotationArrow(Canvas canvas, Offset center, Size size, Paint paint, {bool isVertical = false}) {
    final arrowPaint = Paint()
      ..color = overlayColor.withOpacity(0.5)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    final radius = size.width * 0.25;
    final rect = Rect.fromCircle(center: center, radius: radius);

    canvas.drawArc(rect, isVertical ? -math.pi / 4 : math.pi / 4, math.pi / 2, false, arrowPaint);
  }

  /// Стрелки приближения
  void _drawZoomInArrows(Canvas canvas, Offset center, Size size, Paint paint) {
    final arrowPaint = Paint()
      ..color = overlayColor.withOpacity(0.4)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    const arrowLength = 30.0;
    const offset = 60.0;

    // 4 стрелки к центру
    final directions = [
      Offset(-offset, 0),
      Offset(offset, 0),
      Offset(0, -offset),
      Offset(0, offset),
    ];

    for (final dir in directions) {
      final start = center + dir * 1.5;
      final end = center + dir;
      canvas.drawLine(start, end, arrowPaint);

      // Наконечник стрелки
      final angle = math.atan2(end.dy - start.dy, end.dx - start.dx);
      final arrowHead1 = Offset(
        end.dx - arrowLength * 0.3 * math.cos(angle - math.pi / 6),
        end.dy - arrowLength * 0.3 * math.sin(angle - math.pi / 6),
      );
      final arrowHead2 = Offset(
        end.dx - arrowLength * 0.3 * math.cos(angle + math.pi / 6),
        end.dy - arrowLength * 0.3 * math.sin(angle + math.pi / 6),
      );
      canvas.drawLine(end, arrowHead1, arrowPaint);
      canvas.drawLine(end, arrowHead2, arrowPaint);
    }
  }

  /// Стрелки отдаления
  void _drawZoomOutArrows(Canvas canvas, Offset center, Size size, Paint paint) {
    final arrowPaint = Paint()
      ..color = overlayColor.withOpacity(0.4)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    const arrowLength = 30.0;
    const offset = 80.0;

    // 4 стрелки от центра
    final directions = [
      Offset(-offset, 0),
      Offset(offset, 0),
      Offset(0, -offset),
      Offset(0, offset),
    ];

    for (final dir in directions) {
      final start = center + dir * 0.6;
      final end = center + dir;
      canvas.drawLine(start, end, arrowPaint);

      // Наконечник стрелки
      final angle = math.atan2(end.dy - start.dy, end.dx - start.dx);
      final arrowHead1 = Offset(
        end.dx - arrowLength * 0.3 * math.cos(angle - math.pi / 6),
        end.dy - arrowLength * 0.3 * math.sin(angle - math.pi / 6),
      );
      final arrowHead2 = Offset(
        end.dx - arrowLength * 0.3 * math.cos(angle + math.pi / 6),
        end.dy - arrowLength * 0.3 * math.sin(angle + math.pi / 6),
      );
      canvas.drawLine(end, arrowHead1, arrowPaint);
      canvas.drawLine(end, arrowHead2, arrowPaint);
    }
  }

  @override
  bool shouldRepaint(covariant TemplateOverlayPainter oldDelegate) {
    return oldDelegate.template.id != template.id;
  }
}

/// Виджет для отображения overlay поверх камеры или превью
class TemplateOverlayWidget extends StatelessWidget {
  final PhotoTemplate template;
  final Color color;

  const TemplateOverlayWidget({
    super.key,
    required this.template,
    this.color = Colors.yellow,
  });

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: TemplateOverlayPainter(
        template: template,
        overlayColor: color,
      ),
      child: const SizedBox.expand(),
    );
  }
}
