import 'package:flutter/material.dart';

/// Цвета для полей Z-отчёта (общие для overlay и region selector)
const zReportFieldColors = <String, Color>{
  'totalSum': Colors.red,
  'cashSum': Colors.blue,
  'ofdNotSent': Colors.orange,
  'resourceKeys': Colors.green,
};

/// Подписи для полей Z-отчёта
const zReportFieldLabels = <String, String>{
  'totalSum': 'Выручка',
  'cashSum': 'Наличные',
  'ofdNotSent': 'ОФД',
  'resourceKeys': 'Ключи',
};

/// Overlay для отображения рамок полей Z-отчёта поверх фото.
///
/// Помещается поверх Image виджета в Stack:
/// ```dart
/// Stack(
///   children: [
///     Image.network(photoUrl, fit: BoxFit.contain),
///     Positioned.fill(
///       child: ZReportRegionOverlay(fieldRegions: regions),
///     ),
///   ],
/// )
/// ```
///
/// Координаты в fieldRegions — нормализованные (0.0–1.0).
class ZReportRegionOverlay extends StatelessWidget {
  final Map<String, Map<String, double>> fieldRegions;

  const ZReportRegionOverlay({
    super.key,
    required this.fieldRegions,
  });

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _RegionOverlayPainter(fieldRegions: fieldRegions),
    );
  }
}

class _RegionOverlayPainter extends CustomPainter {
  final Map<String, Map<String, double>> fieldRegions;

  _RegionOverlayPainter({required this.fieldRegions});

  @override
  void paint(Canvas canvas, Size size) {
    for (final entry in fieldRegions.entries) {
      final fieldName = entry.key;
      final region = entry.value;
      final color = zReportFieldColors[fieldName] ?? Colors.white;
      final label = zReportFieldLabels[fieldName];

      final x = (region['x'] ?? 0) * size.width;
      final y = (region['y'] ?? 0) * size.height;
      final w = (region['width'] ?? 0) * size.width;
      final h = (region['height'] ?? 0) * size.height;

      if (w <= 0 || h <= 0) continue;

      final rect = Rect.fromLTWH(x, y, w, h);

      // Полупрозрачная заливка
      canvas.drawRect(
        rect,
        Paint()
          ..color = color.withOpacity(0.12)
          ..style = PaintingStyle.fill,
      );

      // Цветная рамка
      canvas.drawRect(
        rect,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3.0,
      );

      // Угловые маркеры
      const markerLen = 12.0;
      final markerPaint = Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4.0;

      canvas.drawLine(rect.topLeft, Offset(rect.left + markerLen, rect.top), markerPaint);
      canvas.drawLine(rect.topLeft, Offset(rect.left, rect.top + markerLen), markerPaint);
      canvas.drawLine(rect.topRight, Offset(rect.right - markerLen, rect.top), markerPaint);
      canvas.drawLine(rect.topRight, Offset(rect.right, rect.top + markerLen), markerPaint);
      canvas.drawLine(rect.bottomLeft, Offset(rect.left + markerLen, rect.bottom), markerPaint);
      canvas.drawLine(rect.bottomLeft, Offset(rect.left, rect.bottom - markerLen), markerPaint);
      canvas.drawLine(rect.bottomRight, Offset(rect.right - markerLen, rect.bottom), markerPaint);
      canvas.drawLine(rect.bottomRight, Offset(rect.right, rect.bottom - markerLen), markerPaint);

      // Метка поля
      if (label != null && w > 30) {
        final textPainter = TextPainter(
          text: TextSpan(
            text: label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.bold,
              shadows: [Shadow(color: Colors.black, blurRadius: 3)],
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();

        final labelRect = Rect.fromLTWH(
          rect.left,
          rect.top - textPainter.height - 4,
          textPainter.width + 8,
          textPainter.height + 4,
        );
        canvas.drawRRect(
          RRect.fromRectAndRadius(labelRect, const Radius.circular(4)),
          Paint()..color = color.withOpacity(0.85),
        );

        textPainter.paint(
          canvas,
          Offset(rect.left + 4, rect.top - textPainter.height - 2),
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _RegionOverlayPainter oldDelegate) {
    return oldDelegate.fieldRegions != fieldRegions;
  }
}
