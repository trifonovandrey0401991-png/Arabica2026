import 'package:flutter/material.dart';
import 'package:app_settings/app_settings.dart';
import '../../core/theme/app_colors.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

/// Диалог с просьбой включить уведомления
class NotificationRequiredDialog extends StatelessWidget {
  final bool showBackButton;

  const NotificationRequiredDialog({
    super.key,
    this.showBackButton = true,
  });

  /// Показать диалог
  ///
  /// [showBackButton] - показывать ли кнопку "Назад"
  /// Возвращает true если нажали "Включить", false если "Назад"
  static Future<bool?> show(BuildContext context, {bool showBackButton = true}) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => NotificationRequiredDialog(showBackButton: showBackButton),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        padding: EdgeInsets.all(24.w),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24.r),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.2),
              blurRadius: 20,
              offset: Offset(0, 10),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Иконка
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Colors.orange[400]!, Colors.deepOrange[600]!],
                ),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Colors.orange.withOpacity(0.4),
                    blurRadius: 12,
                    offset: Offset(0, 6),
                  ),
                ],
              ),
              child: Icon(
                Icons.notifications_off_rounded,
                color: Colors.white,
                size: 40,
              ),
            ),
            SizedBox(height: 24),

            // Заголовок
            Text(
              'Включите уведомления',
              style: TextStyle(
                fontSize: 22.sp,
                fontWeight: FontWeight.bold,
                color: AppColors.darkGray,
              ),
              textAlign: TextAlign.center,
            ),
            SizedBox(height: 16),

            // Текст
            Text(
              'Пожалуйста, включите уведомления. Без них вы не сможете видеть Новинки и не сможете пользоваться Программой лояльности',
              style: TextStyle(
                fontSize: 15.sp,
                color: Colors.grey[700],
                height: 1.5,
              ),
              textAlign: TextAlign.center,
            ),
            SizedBox(height: 28),

            // Кнопки
            Row(
              children: [
                if (showBackButton) ...[
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context, false),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.grey[700],
                        side: BorderSide(color: Colors.grey[300]!),
                        padding: EdgeInsets.symmetric(vertical: 14.h),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12.r),
                        ),
                      ),
                      child: Text(
                        'Назад',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                  SizedBox(width: 12),
                ],
                Expanded(
                  flex: showBackButton ? 1 : 1,
                  child: ElevatedButton(
                    onPressed: () {
                      AppSettings.openAppSettings(type: AppSettingsType.notification);
                      Navigator.pop(context, true);
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primaryGreen,
                      foregroundColor: Colors.white,
                      padding: EdgeInsets.symmetric(vertical: 14.h),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12.r),
                      ),
                      elevation: 2,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.settings_rounded, size: 20),
                        SizedBox(width: 8),
                        Text(
                          'Включить',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
