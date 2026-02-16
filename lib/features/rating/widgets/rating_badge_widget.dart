import 'package:flutter/material.dart';
import '../models/employee_rating_model.dart';
import '../services/rating_service.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

/// Виджет бейджа рейтинга для главного меню
class RatingBadgeWidget extends StatefulWidget {
  final String employeeId;

  const RatingBadgeWidget({
    super.key,
    required this.employeeId,
  });

  @override
  State<RatingBadgeWidget> createState() => _RatingBadgeWidgetState();
}

class _RatingBadgeWidgetState extends State<RatingBadgeWidget> {
  EmployeeRating? _rating;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadRating();
  }

  Future<void> _loadRating() async {
    final rating = await RatingService.getCurrentEmployeeRating(widget.employeeId);
    if (mounted) {
      setState(() {
        _rating = rating;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return SizedBox(
        height: 24,
        width: 60,
        child: Center(
          child: SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }

    if (_rating == null || _rating!.position == 0) {
      return SizedBox.shrink();
    }

    final rating = _rating!;

    return Container(
      padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 6.h),
      decoration: BoxDecoration(
        color: _getBadgeColor(rating.position),
        borderRadius: BorderRadius.circular(20.r),
        boxShadow: [
          BoxShadow(
            color: _getBadgeColor(rating.position).withOpacity(0.3),
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            rating.positionIcon,
            style: TextStyle(fontSize: 16.sp),
          ),
          SizedBox(width: 6),
          Text(
            rating.positionString,
            style: TextStyle(
              color: Colors.white,
              fontSize: 14.sp,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Color _getBadgeColor(int position) {
    switch (position) {
      case 1:
        return Color(0xFFFFD700); // Золото
      case 2:
        return Color(0xFFC0C0C0); // Серебро
      case 3:
        return Color(0xFFCD7F32); // Бронза
      default:
        return Color(0xFF004D40); // Тёмно-зелёный
    }
  }
}

/// Компактный виджет рейтинга для строки
class RatingBadgeInline extends StatelessWidget {
  final int position;
  final int totalEmployees;

  const RatingBadgeInline({
    super.key,
    required this.position,
    required this.totalEmployees,
  });

  @override
  Widget build(BuildContext context) {
    if (position == 0) return SizedBox.shrink();

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          _getPositionIcon(),
          style: TextStyle(fontSize: 16.sp),
        ),
        SizedBox(width: 4),
        Text(
          '$position/$totalEmployees',
          style: TextStyle(
            fontSize: 14.sp,
            fontWeight: FontWeight.bold,
            color: _getPositionColor(),
          ),
        ),
      ],
    );
  }

  String _getPositionIcon() {
    switch (position) {
      case 1:
        return '🥇';
      case 2:
        return '🥈';
      case 3:
        return '🥉';
      default:
        return '📊';
    }
  }

  Color _getPositionColor() {
    switch (position) {
      case 1:
        return Color(0xFFFFD700);
      case 2:
        return Color(0xFFC0C0C0);
      case 3:
        return Color(0xFFCD7F32);
      default:
        return Color(0xFFD4AF37);
    }
  }
}
