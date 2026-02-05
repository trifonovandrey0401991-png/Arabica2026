import 'dart:math';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
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

  // Позиции значков (сохраняются для стабильности)
  Map<int, Offset> _badgePositions = {};
  final Random _random = Random();
  bool _positionsLoaded = false;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    );
    _scaleAnimation = CurvedAnimation(
      parent: _animationController,
      curve: Curves.elasticOut,
    );
    _loadPositions();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  Future<void> _loadPositions() async {
    final prefs = await SharedPreferences.getInstance();
    final storedPositions = prefs.getString('badge_positions');

    if (storedPositions != null) {
      // Загружаем сохраненные позиции
      final parts = storedPositions.split(';');
      for (final part in parts) {
        if (part.isEmpty) continue;
        final kv = part.split(':');
        if (kv.length == 2) {
          final id = int.tryParse(kv[0]);
          final coords = kv[1].split(',');
          if (id != null && coords.length == 2) {
            final x = double.tryParse(coords[0]);
            final y = double.tryParse(coords[1]);
            if (x != null && y != null) {
              _badgePositions[id] = Offset(x, y);
            }
          }
        }
      }
    }

    // Генерируем позиции для новых значков
    _generateMissingPositions();

    if (mounted) {
      setState(() => _positionsLoaded = true);
      _animationController.forward();
    }
  }

  void _generateMissingPositions() {
    final badgeSize = 36.0;
    final containerSize = widget.qrSize + 100; // Добавляем место для значков
    final qrCenter = containerSize / 2;
    final minRadius = widget.qrSize / 2 + 20; // Минимальное расстояние от центра QR
    final maxRadius = containerSize / 2 - badgeSize / 2; // Максимальное расстояние

    for (final level in widget.earnedLevels) {
      if (!_badgePositions.containsKey(level.id)) {
        // Генерируем случайную позицию вокруг QR
        bool positionValid = false;
        Offset newPosition = Offset.zero;

        for (int attempt = 0; attempt < 20; attempt++) {
          final angle = _random.nextDouble() * 2 * pi;
          final radius = minRadius + _random.nextDouble() * (maxRadius - minRadius);

          newPosition = Offset(
            qrCenter + radius * cos(angle) - badgeSize / 2,
            qrCenter + radius * sin(angle) - badgeSize / 2,
          );

          // Проверяем, не перекрывается ли с другими значками
          positionValid = true;
          for (final existingPos in _badgePositions.values) {
            if ((newPosition - existingPos).distance < badgeSize + 8) {
              positionValid = false;
              break;
            }
          }

          if (positionValid) break;
        }

        _badgePositions[level.id] = newPosition;
      }
    }

    // Сохраняем позиции
    _savePositions();
  }

  Future<void> _savePositions() async {
    final prefs = await SharedPreferences.getInstance();
    final positionsStr = _badgePositions.entries
        .map((e) => '${e.key}:${e.value.dx},${e.value.dy}')
        .join(';');
    await prefs.setString('badge_positions', positionsStr);
  }

  @override
  Widget build(BuildContext context) {
    final containerSize = widget.qrSize + 100;

    return SizedBox(
      width: containerSize,
      height: containerSize,
      child: Stack(
        children: [
          // QR-код по центру
          Positioned(
            left: 50,
            top: 50,
            child: SizedBox(
              width: widget.qrSize,
              height: widget.qrSize,
              child: widget.qrWidget,
            ),
          ),
          // Значки вокруг
          if (_positionsLoaded)
            ...widget.earnedLevels.map((level) {
              final position = _badgePositions[level.id];
              if (position == null) return const SizedBox.shrink();

              return Positioned(
                left: position.dx,
                top: position.dy,
                child: ScaleTransition(
                  scale: _scaleAnimation,
                  child: _BadgeItem(level: level),
                ),
              );
            }),
        ],
      ),
    );
  }
}

class _BadgeItem extends StatelessWidget {
  final LoyaltyLevel level;

  const _BadgeItem({required this.level});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: level.name,
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: level.color,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: level.color.withOpacity(0.4),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Center(
          child: level.badge.type == 'icon'
              ? Icon(
                  level.badge.getIcon() ?? Icons.emoji_events,
                  color: Colors.white,
                  size: 20,
                )
              : ClipOval(
                  child: Image.network(
                    _getImageUrl(level.badge.value),
                    width: 30,
                    height: 30,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => const Icon(
                      Icons.emoji_events,
                      color: Colors.white,
                      size: 20,
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
    return '${ApiConstants.serverUrl}/media/$value';
  }
}
