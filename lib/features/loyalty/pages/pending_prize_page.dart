import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../core/theme/app_colors.dart';
import '../models/loyalty_gamification_model.dart';
import '../services/loyalty_gamification_service.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

/// Страница получения приза - показывает QR-код для сотрудника
class PendingPrizePage extends StatefulWidget {
  final ClientPrize prize;

  const PendingPrizePage({
    super.key,
    required this.prize,
  });

  @override
  State<PendingPrizePage> createState() => _PendingPrizePageState();
}

class _PendingPrizePageState extends State<PendingPrizePage> {
  late ClientPrize _prize;
  bool _regenerating = false;

  @override
  void initState() {
    super.initState();
    _prize = widget.prize;
  }

  Future<void> _regenerateQr() async {
    if (mounted) setState(() => _regenerating = true);

    final newToken = await LoyaltyGamificationService.generateNewQrToken(_prize.id);

    if (newToken != null && mounted) {
      if (mounted) setState(() {
        _prize = _prize.copyWith(qrToken: newToken, qrUsed: false);
        _regenerating = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('QR-код обновлён'),
          backgroundColor: AppColors.success,
        ),
      );
    } else if (mounted) {
      setState(() => _regenerating = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Не удалось обновить QR-код'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.night,
      appBar: AppBar(
        backgroundColor: AppColors.emeraldDark,
        title: Text('Ваш приз'),
        centerTitle: true,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.all(24.w),
          child: Column(
            children: [
              // Заголовок с анимированным текстом
              Container(
                padding: EdgeInsets.symmetric(vertical: 16.h),
                child: Column(
                  children: [
                    Text(
                      'Поздравляем!',
                      style: TextStyle(
                        fontSize: 28.sp,
                        fontWeight: FontWeight.bold,
                        color: Colors.white.withOpacity(0.95),
                      ),
                    ),
                    SizedBox(height: 8),
                    Text(
                      'Вы выиграли приз',
                      style: TextStyle(
                        fontSize: 16.sp,
                        color: Colors.white.withOpacity(0.7),
                      ),
                    ),
                  ],
                ),
              ),

              SizedBox(height: 16),

              // Карточка приза
              Container(
                padding: EdgeInsets.all(24.w),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      _prize.prizeColor.withOpacity(0.3),
                      _prize.prizeColor.withOpacity(0.1),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(20.r),
                  border: Border.all(
                    color: _prize.prizeColor.withOpacity(0.5),
                    width: 2,
                  ),
                ),
                child: Column(
                  children: [
                    // Иконка приза
                    Container(
                      width: 80,
                      height: 80,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            _prize.prizeColor,
                            _prize.prizeColor.withOpacity(0.7),
                          ],
                        ),
                        borderRadius: BorderRadius.circular(20.r),
                        boxShadow: [
                          BoxShadow(
                            color: _prize.prizeColor.withOpacity(0.4),
                            blurRadius: 20,
                            offset: Offset(0, 8),
                          ),
                        ],
                      ),
                      child: Icon(
                        _prize.prizeIcon,
                        color: Colors.white,
                        size: 40,
                      ),
                    ),
                    SizedBox(height: 16),
                    // Название приза
                    Text(
                      _prize.prize,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 24.sp,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    SizedBox(height: 8),
                    Text(
                      _formatDate(_prize.spinDate),
                      style: TextStyle(
                        fontSize: 14.sp,
                        color: Colors.white.withOpacity(0.6),
                      ),
                    ),
                  ],
                ),
              ),

              SizedBox(height: 32),

              // QR-код
              Container(
                padding: EdgeInsets.all(20.w),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20.r),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.emerald.withOpacity(0.3),
                      blurRadius: 20,
                      offset: Offset(0, 10),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    QrImageView(
                      data: _prize.qrToken,
                      version: QrVersions.auto,
                      size: 200,
                      backgroundColor: Colors.white,
                      eyeStyle: QrEyeStyle(
                        eyeShape: QrEyeShape.square,
                        color: AppColors.emeraldDark,
                      ),
                      dataModuleStyle: QrDataModuleStyle(
                        dataModuleShape: QrDataModuleShape.square,
                        color: AppColors.emeraldDark,
                      ),
                    ),
                    if (_prize.qrUsed) ...[
                      SizedBox(height: 12),
                      Container(
                        padding: EdgeInsets.symmetric(
                          horizontal: 16.w,
                          vertical: 8.h,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.orange.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8.r),
                          border: Border.all(color: Colors.orange),
                        ),
                        child: Text(
                          'QR был отсканирован',
                          style: TextStyle(
                            color: Colors.orange,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),

              SizedBox(height: 24),

              // Инструкция
              Container(
                padding: EdgeInsets.all(16.w),
                decoration: BoxDecoration(
                  color: AppColors.emerald.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(12.r),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.info_outline,
                      color: Colors.white.withOpacity(0.7),
                    ),
                    SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Покажите этот QR-код сотруднику для получения приза',
                        style: TextStyle(
                          fontSize: 14.sp,
                          color: Colors.white.withOpacity(0.8),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              SizedBox(height: 24),

              // Кнопка обновить QR
              if (_prize.qrUsed)
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _regenerating ? null : _regenerateQr,
                    icon: _regenerating
                        ? SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : Icon(Icons.refresh),
                    label: Text(_regenerating ? 'Обновление...' : 'Обновить QR-код'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.emerald,
                      foregroundColor: Colors.white,
                      padding: EdgeInsets.symmetric(vertical: 16.h),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12.r),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatDate(DateTime date) {
    final months = [
      '', 'января', 'февраля', 'марта', 'апреля', 'мая', 'июня',
      'июля', 'августа', 'сентября', 'октября', 'ноября', 'декабря',
    ];
    return '${date.day} ${months[date.month]} ${date.year}';
  }
}
