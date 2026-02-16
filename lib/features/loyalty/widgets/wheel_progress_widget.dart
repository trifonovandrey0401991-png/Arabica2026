import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

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
    if (!wheelEnabled) return SizedBox.shrink();

    final progress = drinksPerSpin > 0
        ? (currentDrinks % drinksPerSpin) / drinksPerSpin
        : 0.0;
    final drinksToNextSpin = drinksPerSpin - (currentDrinks % drinksPerSpin);

    return Container(
      padding: EdgeInsets.all(16.w),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF8E2DE2).withOpacity(0.1),
            Color(0xFF4A00E0).withOpacity(0.1),
          ],
        ),
        borderRadius: BorderRadius.circular(16.r),
        border: Border.all(
          color: Color(0xFF8E2DE2).withOpacity(0.3),
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
                  gradient: LinearGradient(
                    colors: [Color(0xFF8E2DE2), Color(0xFF4A00E0)],
                  ),
                  borderRadius: BorderRadius.circular(10.r),
                ),
                child: Icon(
                  Icons.casino,
                  color: Colors.white,
                  size: 24,
                ),
              ),
              SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Колесо удачи',
                  style: TextStyle(
                    fontSize: 16.sp,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF2D3436),
                  ),
                ),
              ),
              if (spinsAvailable > 0)
                Container(
                  padding:
                      EdgeInsets.symmetric(horizontal: 12.w, vertical: 6.h),
                  decoration: BoxDecoration(
                    color: Color(0xFF4CAF50),
                    borderRadius: BorderRadius.circular(20.r),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.star, color: Colors.white, size: 16),
                      SizedBox(width: 4),
                      Text(
                        '$spinsAvailable',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          SizedBox(height: 16),
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
                      fontSize: 13.sp,
                      color: spinsAvailable > 0
                          ? Color(0xFF4CAF50)
                          : Colors.grey[600],
                      fontWeight: spinsAvailable > 0
                          ? FontWeight.bold
                          : FontWeight.normal,
                    ),
                  ),
                  Text(
                    '${currentDrinks % drinksPerSpin}/$drinksPerSpin',
                    style: TextStyle(
                      fontSize: 13.sp,
                      color: Colors.grey[600],
                    ),
                  ),
                ],
              ),
              SizedBox(height: 8),
              // Визуальный прогресс с точками
              _buildProgressDots(progress),
            ],
          ),
          // Кнопка прокрутки
          if (spinsAvailable > 0) ...[
            SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: onSpinPressed,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Color(0xFF8E2DE2),
                  padding: EdgeInsets.symmetric(vertical: 14.h),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12.r),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.casino, color: Colors.white),
                    SizedBox(width: 8),
                    Text(
                      'КРУТИТЬ КОЛЕСО',
                      style: TextStyle(
                        fontSize: 16.sp,
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
                    ? Color(0xFF8E2DE2)
                    : Colors.grey.shade300,
                borderRadius: BorderRadius.circular(4.r),
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
      padding: EdgeInsets.all(16.w),
      decoration: BoxDecoration(
        color: levelColor.withOpacity(0.1),
        borderRadius: BorderRadius.circular(16.r),
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
              borderRadius: BorderRadius.circular(12.r),
            ),
            child: Icon(
              levelIcon ?? Icons.workspace_premium,
              color: Colors.white,
              size: 28,
            ),
          ),
          SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Уровень: $levelName',
                  style: TextStyle(
                    fontSize: 16.sp,
                    fontWeight: FontWeight.bold,
                    color: levelColor,
                  ),
                ),
                if (drinksToNextLevel != null && nextLevelName != null) ...[
                  SizedBox(height: 4),
                  Text(
                    'До "$nextLevelName": $drinksToNextLevel напитков',
                    style: TextStyle(
                      fontSize: 13.sp,
                      color: Colors.grey[600],
                    ),
                  ),
                ] else ...[
                  SizedBox(height: 4),
                  Text(
                    'Максимальный уровень достигнут!',
                    style: TextStyle(
                      fontSize: 13.sp,
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
