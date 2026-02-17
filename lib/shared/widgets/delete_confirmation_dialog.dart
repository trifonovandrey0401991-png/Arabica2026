import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../core/theme/app_colors.dart';

/// Диалог подтверждения удаления в Dark Emerald стиле.
///
/// Дублировался в shift_questions_management_page и
/// shift_handover_questions_management_page (~140 строк × 2).
///
/// Использование:
/// ```dart
/// final confirmed = await DeleteConfirmationDialog.show(
///   context: context,
///   title: 'Удалить вопрос?',
///   itemText: question.question,
///   warningText: 'Это действие невозможно отменить',
/// );
/// if (confirmed) { ... }
/// ```
class DeleteConfirmationDialog extends StatelessWidget {
  final String title;
  final String itemText;
  final String warningText;
  final String cancelLabel;
  final String confirmLabel;
  final IconData icon;

  const DeleteConfirmationDialog({
    super.key,
    this.title = 'Удалить вопрос?',
    required this.itemText,
    this.warningText = 'Это действие невозможно отменить',
    this.cancelLabel = 'Отмена',
    this.confirmLabel = 'Удалить',
    this.icon = Icons.delete_forever_rounded,
  });

  /// Показать диалог и вернуть true если подтверждено.
  static Future<bool> show({
    required BuildContext context,
    String title = 'Удалить вопрос?',
    required String itemText,
    String warningText = 'Это действие невозможно отменить',
    String cancelLabel = 'Отмена',
    String confirmLabel = 'Удалить',
    IconData icon = Icons.delete_forever_rounded,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (_) => DeleteConfirmationDialog(
        title: title,
        itemText: itemText,
        warningText: warningText,
        cancelLabel: cancelLabel,
        confirmLabel: confirmLabel,
        icon: icon,
      ),
    );
    return result == true;
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        constraints: BoxConstraints(maxWidth: 400),
        decoration: BoxDecoration(
          color: AppColors.emeraldDark,
          borderRadius: BorderRadius.circular(20.r),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Красный заголовок с иконкой
            Container(
              width: double.infinity,
              padding: EdgeInsets.symmetric(vertical: 24.h),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Colors.red[400]!, Colors.red[600]!],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(20.r),
                  topRight: Radius.circular(20.r),
                ),
              ),
              child: Column(
                children: [
                  Container(
                    padding: EdgeInsets.all(16.w),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(icon, color: Colors.white, size: 36),
                  ),
                  SizedBox(height: 12),
                  Text(
                    title,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 20.sp,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
            // Текст элемента + предупреждение
            Padding(
              padding: EdgeInsets.all(20.w),
              child: Column(
                children: [
                  Container(
                    padding: EdgeInsets.all(14.w),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.06),
                      borderRadius: BorderRadius.circular(12.r),
                      border:
                          Border.all(color: Colors.white.withOpacity(0.1)),
                    ),
                    child: Text(
                      itemText,
                      style: TextStyle(
                        fontSize: 14.sp,
                        color: Colors.white.withOpacity(0.7),
                        height: 1.4,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  SizedBox(height: 12),
                  Text(
                    warningText,
                    style: TextStyle(
                      fontSize: 13.sp,
                      color: Colors.white.withOpacity(0.5),
                    ),
                  ),
                ],
              ),
            ),
            // Кнопки
            Padding(
              padding: EdgeInsets.fromLTRB(20.w, 0, 20.w, 20.h),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context, false),
                      style: OutlinedButton.styleFrom(
                        padding: EdgeInsets.symmetric(vertical: 14.h),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12.r),
                        ),
                        side: BorderSide(
                            color: Colors.white.withOpacity(0.2)),
                      ),
                      child: Text(
                        cancelLabel,
                        style: TextStyle(
                          fontSize: 15.sp,
                          fontWeight: FontWeight.w600,
                          color: Colors.white.withOpacity(0.7),
                        ),
                      ),
                    ),
                  ),
                  SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(context, true),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red[500],
                        foregroundColor: Colors.white,
                        padding: EdgeInsets.symmetric(vertical: 14.h),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12.r),
                        ),
                        elevation: 0,
                      ),
                      child: Text(
                        confirmLabel,
                        style: TextStyle(
                          fontSize: 15.sp,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
