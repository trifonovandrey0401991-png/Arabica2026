import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../shops/models/shop_model.dart';
import '../services/review_service.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../../core/theme/app_colors.dart';

/// Страница ввода текста отзыва
class ReviewTextInputPage extends StatefulWidget {
  final String reviewType;
  final Shop shop;

  const ReviewTextInputPage({
    super.key,
    required this.reviewType,
    required this.shop,
  });

  @override
  State<ReviewTextInputPage> createState() => _ReviewTextInputPageState();
}

class _ReviewTextInputPageState extends State<ReviewTextInputPage> {
  final _textController = TextEditingController();
  bool _isLoading = false;

  bool get _isPositive => widget.reviewType == 'positive';
  Color get _accentColor => _isPositive
      ? AppColors.success
      : Color(0xFFEF5350);

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  Future<void> _submitReview() async {
    if (_textController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Пожалуйста, введите текст отзыва'),
          backgroundColor: Colors.red.shade700,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.r)),
        ),
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final prefs = await SharedPreferences.getInstance();
      final clientPhone = prefs.getString('user_phone') ?? '';
      final clientName = prefs.getString('user_name') ?? '';

      if (clientPhone.isEmpty || clientName.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Ошибка: данные пользователя не найдены'),
              backgroundColor: Colors.red.shade700,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.r)),
            ),
          );
        }
        return;
      }

      final review = await ReviewService.createReview(
        clientPhone: clientPhone,
        clientName: clientName,
        shopAddress: widget.shop.address,
        reviewType: widget.reviewType,
        reviewText: _textController.text.trim(),
      );

      if (mounted) {
        if (review != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Отзыв успешно отправлен!'),
              backgroundColor: AppColors.success,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.r)),
            ),
          );
          Navigator.of(context).popUntil((route) => route.isFirst);
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Ошибка при отправке отзыва'),
              backgroundColor: Colors.red.shade700,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.r)),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка: $e'),
            backgroundColor: Colors.red.shade700,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.r)),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
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
              _buildAppBar(),
              Expanded(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(20.w, 0.h, 20.w, 20.h),
                  child: Column(
                    children: [
                      // Магазин + тип отзыва
                      _buildInfoCard(),
                      SizedBox(height: 16),
                      // Поле ввода
                      Expanded(child: _buildTextInput()),
                      SizedBox(height: 16),
                      // Кнопки
                      _buildButtons(),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAppBar() {
    return Padding(
      padding: EdgeInsets.fromLTRB(8.w, 8.h, 8.w, 16.h),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.pop(context),
            icon: Icon(
              Icons.arrow_back_ios_new_rounded,
              color: Colors.white.withOpacity(0.8),
              size: 22,
            ),
          ),
          Expanded(
            child: Text(
              'Напишите отзыв',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                fontSize: 20.sp,
                fontWeight: FontWeight.w400,
                letterSpacing: 1,
              ),
            ),
          ),
          SizedBox(width: 48),
        ],
      ),
    );
  }

  Widget _buildInfoCard() {
    return Container(
      padding: EdgeInsets.all(16.w),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16.r),
        border: Border.all(color: Colors.white.withOpacity(0.15)),
      ),
      child: Column(
        children: [
          // Магазин
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10.r),
                ),
                child: Icon(
                  Icons.store_rounded,
                  color: Colors.white.withOpacity(0.8),
                  size: 22,
                ),
              ),
              SizedBox(width: 12),
              Expanded(
                child: Text(
                  widget.shop.address,
                  style: TextStyle(
                    fontSize: 15.sp,
                    fontWeight: FontWeight.w500,
                    color: Colors.white.withOpacity(0.9),
                  ),
                ),
              ),
            ],
          ),
          Padding(
            padding: EdgeInsets.symmetric(vertical: 12.h),
            child: Divider(
              color: Colors.white.withOpacity(0.1),
              height: 1,
            ),
          ),
          // Тип отзыва
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: _accentColor,
                  borderRadius: BorderRadius.circular(10.r),
                ),
                child: Icon(
                  _isPositive ? Icons.thumb_up_rounded : Icons.thumb_down_rounded,
                  color: Colors.white,
                  size: 20,
                ),
              ),
              SizedBox(width: 12),
              Text(
                _isPositive ? 'Положительный отзыв' : 'Отрицательный отзыв',
                style: TextStyle(
                  fontSize: 15.sp,
                  fontWeight: FontWeight.w500,
                  color: _accentColor,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTextInput() {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16.r),
        border: Border.all(color: _accentColor.withOpacity(0.3)),
        color: Colors.white.withOpacity(0.05),
      ),
      child: TextField(
        controller: _textController,
        maxLines: null,
        expands: true,
        textAlignVertical: TextAlignVertical.top,
        style: TextStyle(
          fontSize: 16.sp,
          color: Colors.white.withOpacity(0.9),
          height: 1.5,
        ),
        cursorColor: _accentColor,
        decoration: InputDecoration(
          hintText: 'Введите ваш отзыв...',
          hintStyle: TextStyle(
            color: Colors.white.withOpacity(0.3),
            fontSize: 16.sp,
          ),
          contentPadding: EdgeInsets.all(20.w),
          border: InputBorder.none,
        ),
      ),
    );
  }

  Widget _buildButtons() {
    return Row(
      children: [
        // Вернуться
        Expanded(
          child: GestureDetector(
            onTap: _isLoading ? null : () => Navigator.pop(context),
            child: Container(
              padding: EdgeInsets.symmetric(vertical: 16.h),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14.r),
                border: Border.all(color: Colors.white.withOpacity(0.2)),
              ),
              child: Center(
                child: Text(
                  'Вернуться',
                  style: TextStyle(
                    fontSize: 16.sp,
                    fontWeight: FontWeight.w500,
                    color: Colors.white.withOpacity(0.7),
                  ),
                ),
              ),
            ),
          ),
        ),
        SizedBox(width: 12),
        // Отправить
        Expanded(
          child: GestureDetector(
            onTap: _isLoading ? null : _submitReview,
            child: Container(
              padding: EdgeInsets.symmetric(vertical: 16.h),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14.r),
                gradient: LinearGradient(
                  colors: [
                    _accentColor,
                    _accentColor.withOpacity(0.8),
                  ],
                ),
              ),
              child: Center(
                child: _isLoading
                    ? SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            Colors.white,
                          ),
                        ),
                      )
                    : Text(
                        'Отправить',
                        style: TextStyle(
                          fontSize: 16.sp,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
