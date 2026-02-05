import 'package:flutter/material.dart';

/// Виджет прогресса до прокрутки колеса удачи
class WheelProgressWidget extends StatelessWidget {
  final int currentDrinks; // Текущее кол-во напитков (текущий прогресс)
  final int drinksPerSpin; // Сколько напитков нужно для прокрутки
  final int spinsAvailable; // Доступные прокрутки
  final bool wheelEnabled; // Включено ли колесо
  final VoidCallback? onSpinPressed;

  const WheelProgressWidget({
    super.key,
    required this.currentDrinks,
    required this.drinksPerSpin,
    required this.spinsAvailable,
    this.wheelEnabled = true,
    this.onSpinPressed,
  });

  @override
  Widget build(BuildContext context) {
    if (!wheelEnabled) return const SizedBox.shrink();

    final progress = drinksPerSpin > 0
        ? (currentDrinks % drinksPerSpin) / drinksPerSpin
        : 0.0;
    final drinksToNextSpin = drinksPerSpin - (currentDrinks % drinksPerSpin);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            const Color(0xFF8E2DE2).withOpacity(0.1),
            const Color(0xFF4A00E0).withOpacity(0.1),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: const Color(0xFF8E2DE2).withOpacity(0.3),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Заголовок
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF8E2DE2), Color(0xFF4A00E0)],
                  ),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.casino,
                  color: Colors.white,
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'Колесо удачи',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF2D3436),
                  ),
                ),
              ),
              if (spinsAvailable > 0)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: const Color(0xFF4CAF50),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.star, color: Colors.white, size: 16),
                      const SizedBox(width: 4),
                      Text(
                        '$spinsAvailable',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),
          // Прогресс бар
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    spinsAvailable > 0
                        ? 'Прокрутки доступны!'
                        : 'До прокрутки: $drinksToNextSpin напитков',
                    style: TextStyle(
                      fontSize: 13,
                      color: spinsAvailable > 0
                          ? const Color(0xFF4CAF50)
                          : Colors.grey[600],
                      fontWeight: spinsAvailable > 0
                          ? FontWeight.bold
                          : FontWeight.normal,
                    ),
                  ),
                  Text(
                    '${currentDrinks % drinksPerSpin}/$drinksPerSpin',
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.grey[600],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              // Визуальный прогресс с точками
              _buildProgressDots(progress),
            ],
          ),
          // Кнопка прокрутки
          if (spinsAvailable > 0) ...[
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: onSpinPressed,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF8E2DE2),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.casino, color: Colors.white),
                    SizedBox(width: 8),
                    Text(
                      'КРУТИТЬ КОЛЕСО',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildProgressDots(double progress) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final dotsCount = drinksPerSpin.clamp(1, 10);
        final filledDots = (currentDrinks % drinksPerSpin);

        return Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: List.generate(dotsCount, (index) {
            final isFilled = index < filledDots;
            return Container(
              width: constraints.maxWidth / dotsCount - 4,
              height: 8,
              decoration: BoxDecoration(
                color: isFilled
                    ? const Color(0xFF8E2DE2)
                    : Colors.grey.shade300,
                borderRadius: BorderRadius.circular(4),
              ),
            );
          }),
        );
      },
    );
  }
}

/// Виджет строки уровня клиента
class LevelInfoWidget extends StatelessWidget {
  final String levelName;
  final Color levelColor;
  final IconData? levelIcon;
  final int? drinksToNextLevel;
  final String? nextLevelName;

  const LevelInfoWidget({
    super.key,
    required this.levelName,
    required this.levelColor,
    this.levelIcon,
    this.drinksToNextLevel,
    this.nextLevelName,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: levelColor.withOpacity(0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: levelColor.withOpacity(0.3),
          width: 1,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: levelColor,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              levelIcon ?? Icons.workspace_premium,
              color: Colors.white,
              size: 28,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Уровень: $levelName',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: levelColor,
                  ),
                ),
                if (drinksToNextLevel != null && nextLevelName != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    'До "$nextLevelName": $drinksToNextLevel напитков',
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.grey[600],
                    ),
                  ),
                ] else ...[
                  const SizedBox(height: 4),
                  Text(
                    'Максимальный уровень достигнут!',
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.grey[600],
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
