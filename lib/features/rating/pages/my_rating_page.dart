import 'package:flutter/material.dart';
import '../models/employee_rating_model.dart';
import '../services/rating_service.dart';
import '../widgets/rating_badge_widget.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../../core/theme/app_colors.dart';

/// Страница "Мой рейтинг" с историей за 3 месяца
class MyRatingPage extends StatefulWidget {
  final String employeeId;
  final String employeeName;

  const MyRatingPage({
    super.key,
    required this.employeeId,
    required this.employeeName,
  });

  @override
  State<MyRatingPage> createState() => _MyRatingPageState();
}

class _MyRatingPageState extends State<MyRatingPage> {
  List<MonthlyRating> _history = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    setState(() => _isLoading = true);

    final history = await RatingService.getEmployeeRatingHistory(
      widget.employeeId,
      months: 3,
    );

    if (mounted) {
      setState(() {
        _history = history;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.night,
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [AppColors.emerald, AppColors.emeraldDark, AppColors.night],
            stops: [0.0, 0.3, 1.0],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              // Custom AppBar
              Padding(
                padding: EdgeInsets.fromLTRB(8.w, 8.h, 8.w, 0),
                child: Row(
                  children: [
                    GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(12.r),
                          border: Border.all(color: Colors.white.withOpacity(0.1)),
                        ),
                        child: Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white.withOpacity(0.8), size: 20),
                      ),
                    ),
                    Expanded(
                      child: Center(
                        child: Text(
                          'Мой рейтинг',
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.95),
                            fontSize: 18.sp,
                            fontWeight: FontWeight.w400,
                            letterSpacing: 1,
                          ),
                        ),
                      ),
                    ),
                    GestureDetector(
                      onTap: _loadHistory,
                      child: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(12.r),
                          border: Border.all(color: Colors.white.withOpacity(0.1)),
                        ),
                        child: Icon(Icons.refresh, color: Colors.white.withOpacity(0.8), size: 20),
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(height: 12.h),
              // Body
              Expanded(
                child: _isLoading
                    ? Center(child: CircularProgressIndicator(color: AppColors.gold, strokeWidth: 3))
                    : RefreshIndicator(
                        onRefresh: _loadHistory,
                        color: AppColors.gold,
                        child: _history.isEmpty
                            ? _buildEmptyState()
                            : ListView.builder(
                                padding: EdgeInsets.all(16.w),
                                itemCount: _history.length,
                                itemBuilder: (context, index) {
                                  return _buildMonthCard(_history[index]);
                                },
                              ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: EdgeInsets.all(24.w),
            decoration: BoxDecoration(
              color: AppColors.emerald.withOpacity(0.3),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.leaderboard_outlined,
              size: 64,
              color: Colors.white.withOpacity(0.4),
            ),
          ),
          SizedBox(height: 20),
          Text(
            'Нет данных о рейтинге',
            style: TextStyle(
              fontSize: 18.sp,
              fontWeight: FontWeight.bold,
              color: Colors.white.withOpacity(0.9),
            ),
          ),
          SizedBox(height: 8),
          Text(
            'Рейтинг появится после первых смен',
            style: TextStyle(
              fontSize: 14.sp,
              color: Colors.white.withOpacity(0.5),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMonthCard(MonthlyRating rating) {
    return Container(
      margin: EdgeInsets.only(bottom: 16.h),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.06),
        borderRadius: BorderRadius.circular(14.r),
        border: Border.all(
          color: rating.isTop3
              ? _getBorderColor(rating.position).withOpacity(0.6)
              : Colors.white.withOpacity(0.1),
          width: rating.isTop3 ? 1.5 : 1,
        ),
      ),
      child: Padding(
        padding: EdgeInsets.all(16.w),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Заголовок с месяцем и позицией
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  rating.monthName,
                  style: TextStyle(
                    fontSize: 18.sp,
                    fontWeight: FontWeight.bold,
                    color: Colors.white.withOpacity(0.95),
                  ),
                ),
                RatingBadgeInline(
                  position: rating.position,
                  totalEmployees: rating.totalEmployees,
                ),
              ],
            ),
            SizedBox(height: 16),

            // Статистика
            Row(
              children: [
                _buildStatItem(
                  'Баллы',
                  rating.totalPoints.toStringAsFixed(1),
                  Icons.star,
                  Colors.amber,
                ),
                SizedBox(width: 10),
                _buildStatItem(
                  'Смен',
                  rating.shiftsCount.toString(),
                  Icons.work,
                  Colors.blue[300]!,
                ),
                SizedBox(width: 10),
                _buildStatItem(
                  'Рефералы',
                  rating.referralPoints.toInt().toString(),
                  Icons.person_add,
                  Colors.green[400]!,
                ),
              ],
            ),
            SizedBox(height: 14),

            // Нормализованный рейтинг
            Container(
              padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 8.h),
              decoration: BoxDecoration(
                color: AppColors.emerald.withOpacity(0.4),
                borderRadius: BorderRadius.circular(10.r),
                border: Border.all(color: Colors.white.withOpacity(0.08)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.trending_up,
                    size: 18,
                    color: AppColors.gold,
                  ),
                  SizedBox(width: 8),
                  Text(
                    'Нормализованный рейтинг: ${rating.normalizedRating.toStringAsFixed(2)}',
                    style: TextStyle(
                      fontSize: 13.sp,
                      fontWeight: FontWeight.w500,
                      color: Colors.white.withOpacity(0.7),
                    ),
                  ),
                ],
              ),
            ),

            // Награда за топ-N (динамически: 1-10)
            if (rating.position >= 1 && rating.position <= 10) ...[
              SizedBox(height: 12),
              Container(
                padding: EdgeInsets.all(12.w),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: _getGradientColors(rating.position),
                  ),
                  borderRadius: BorderRadius.circular(10.r),
                ),
                child: Row(
                  children: [
                    Text(
                      rating.positionIcon,
                      style: TextStyle(fontSize: 24.sp),
                    ),
                    SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        _getRewardText(rating.position),
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildStatItem(
    String label,
    String value,
    IconData icon,
    Color color,
  ) {
    return Expanded(
      child: Container(
        padding: EdgeInsets.symmetric(vertical: 10.h),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.04),
          borderRadius: BorderRadius.circular(10.r),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 22),
            SizedBox(height: 6),
            Text(
              value,
              style: TextStyle(
                fontSize: 18.sp,
                fontWeight: FontWeight.bold,
                color: Colors.white.withOpacity(0.95),
              ),
            ),
            Text(
              label,
              style: TextStyle(
                fontSize: 12.sp,
                color: Colors.white.withOpacity(0.5),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Color _getBorderColor(int position) {
    switch (position) {
      case 1:
        return Color(0xFFFFD700);
      case 2:
        return Color(0xFFC0C0C0);
      case 3:
        return Color(0xFFCD7F32);
      default:
        return Colors.transparent;
    }
  }

  List<Color> _getGradientColors(int position) {
    switch (position) {
      case 1:
        return [Color(0xFFFFD700), Color(0xFFFFA500)];
      case 2:
        return [Color(0xFFC0C0C0), Color(0xFF808080)];
      case 3:
        return [Color(0xFFCD7F32), Color(0xFF8B4513)];
      default:
        return [Colors.grey, Colors.grey];
    }
  }

  String _getRewardText(int position) {
    // Топ-1: 2 прокрутки, остальные (2-N): 1 прокрутка
    // N определяется настройкой topEmployeesCount (1-10)
    if (position == 1) {
      return '1 место! 2 прокрутки Колеса Удачи';
    } else if (position >= 2 && position <= 10) {
      // Показываем награду для позиций 2-10
      // (прокрутки выдаются только если position <= topEmployeesCount)
      return '$position место! 1 прокрутка Колеса Удачи';
    }
    return '';
  }
}
