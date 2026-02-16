import 'package:flutter/material.dart';
import '../models/cleanup_category.dart';
import '../services/cleanup_service.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

/// Диалог выбора периода для очистки данных.
class CleanupPeriodDialog extends StatefulWidget {
  final CleanupCategory category;

  const CleanupPeriodDialog({
    super.key,
    required this.category,
  });

  @override
  State<CleanupPeriodDialog> createState() => _CleanupPeriodDialogState();
}

class _CleanupPeriodDialogState extends State<CleanupPeriodDialog> {
  DateTime _selectedDate = DateTime.now().subtract(Duration(days: 30));
  int _previewCount = 0;
  bool _isLoadingPreview = false;
  bool _isDeleting = false;

  // Gradient colors
  static final _primaryGradient = [Color(0xFF667eea), Color(0xFF764ba2)];
  static final _dangerGradient = [Color(0xFFeb3349), Color(0xFFf45c43)];
  static final _warningGradient = [Color(0xFFf7971e), Color(0xFFffd200)];

  @override
  void initState() {
    super.initState();
    _loadPreview();
  }

  Future<void> _loadPreview() async {
    setState(() => _isLoadingPreview = true);

    try {
      final count = await CleanupService.getDeleteCount(
        widget.category.id,
        _selectedDate,
      );

      if (mounted) {
        setState(() {
          _previewCount = count;
          _isLoadingPreview = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _previewCount = 0;
          _isLoadingPreview = false;
        });
      }
    }
  }

  Future<void> _selectDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      locale: Locale('ru'),
      helpText: 'Удалить данные ДО этой даты',
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: ColorScheme.light(
              primary: _primaryGradient[0],
              onPrimary: Colors.white,
              surface: Colors.white,
              onSurface: Colors.black,
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null && picked != _selectedDate) {
      setState(() => _selectedDate = picked);
      _loadPreview();
    }
  }

  Future<void> _performCleanup() async {
    // Подтверждение
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20.r)),
        title: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: _dangerGradient),
                borderRadius: BorderRadius.circular(12.r),
              ),
              child: Icon(Icons.warning_amber_rounded, color: Colors.white, size: 24),
            ),
            SizedBox(width: 12),
            Text('Подтверждение'),
          ],
        ),
        content: Text(
          'Вы уверены, что хотите удалить $_previewCount файлов из категории "${widget.category.name}"?\n\nЭто действие необратимо!',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(
              'Отмена',
              style: TextStyle(color: Colors.grey[600]),
            ),
          ),
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: _dangerGradient),
              borderRadius: BorderRadius.circular(10.r),
            ),
            child: ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.transparent,
                shadowColor: Colors.transparent,
                foregroundColor: Colors.white,
                padding: EdgeInsets.symmetric(horizontal: 20.w, vertical: 10.h),
              ),
              child: Text('Удалить'),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _isDeleting = true);

    try {
      final result = await CleanupService.cleanupCategory(
        widget.category.id,
        _selectedDate,
      );

      if (!mounted) return;

      if (result != null) {
        final deletedCount = result['deletedCount'] ?? 0;
        final freedBytes = result['freedBytes'] ?? 0;
        final freedMB = (freedBytes / (1024 * 1024)).toStringAsFixed(2);

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(8.r),
                  ),
                  child: Icon(Icons.check_circle, color: Colors.white, size: 20),
                ),
                SizedBox(width: 12),
                Text('Удалено $deletedCount файлов ($freedMB MB)'),
              ],
            ),
            backgroundColor: Color(0xFF11998e),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.r)),
          ),
        );

        Navigator.pop(context, true);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(8.r),
                  ),
                  child: Icon(Icons.error_outline, color: Colors.white, size: 20),
                ),
                SizedBox(width: 12),
                Text('Ошибка при очистке данных'),
              ],
            ),
            backgroundColor: _dangerGradient[0],
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.r)),
          ),
        );
        setState(() => _isDeleting = false);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(8.r),
                  ),
                  child: Icon(Icons.error_outline, color: Colors.white, size: 20),
                ),
                SizedBox(width: 12),
                Text('Ошибка при очистке данных'),
              ],
            ),
            backgroundColor: _dangerGradient[0],
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.r)),
          ),
        );
        setState(() => _isDeleting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final dateStr =
        '${_selectedDate.day.toString().padLeft(2, '0')}.${_selectedDate.month.toString().padLeft(2, '0')}.${_selectedDate.year}';

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24.r)),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header with gradient
          Container(
            padding: EdgeInsets.all(20.w),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: _primaryGradient,
              ),
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(24.r),
                topRight: Radius.circular(24.r),
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(14.r),
                  ),
                  child: Icon(
                    Icons.delete_sweep,
                    color: Colors.white,
                    size: 26,
                  ),
                ),
                SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Очистить данные',
                        style: TextStyle(
                          fontSize: 18.sp,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      Text(
                        widget.category.name,
                        style: TextStyle(
                          fontSize: 14.sp,
                          color: Colors.white.withOpacity(0.9),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Content
          Padding(
            padding: EdgeInsets.all(20.w),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Date label
                Row(
                  children: [
                    Container(
                      width: 4,
                      height: 20,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: _primaryGradient,
                        ),
                        borderRadius: BorderRadius.circular(2.r),
                      ),
                    ),
                    SizedBox(width: 10),
                    Text(
                      'Удалить данные ДО:',
                      style: TextStyle(
                        fontSize: 15.sp,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF2D3748),
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 14),

                // Date selector
                InkWell(
                  onTap: _selectDate,
                  borderRadius: BorderRadius.circular(16.r),
                  child: Container(
                    padding: EdgeInsets.symmetric(horizontal: 20.w, vertical: 16.h),
                    decoration: BoxDecoration(
                      color: Color(0xFFF5F7FA),
                      borderRadius: BorderRadius.circular(16.r),
                      border: Border.all(color: _primaryGradient[0].withOpacity(0.3)),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(colors: _primaryGradient),
                            borderRadius: BorderRadius.circular(12.r),
                          ),
                          child: Icon(Icons.calendar_today, color: Colors.white, size: 22),
                        ),
                        SizedBox(width: 14),
                        Text(
                          dateStr,
                          style: TextStyle(
                            fontSize: 20.sp,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF2D3748),
                          ),
                        ),
                        Spacer(),
                        Icon(
                          Icons.edit,
                          color: _primaryGradient[0],
                          size: 20,
                        ),
                      ],
                    ),
                  ),
                ),
                SizedBox(height: 20),

                // Warning box
                Container(
                  padding: EdgeInsets.all(16.w),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        _warningGradient[0].withOpacity(0.1),
                        _warningGradient[1].withOpacity(0.1),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(16.r),
                    border: Border.all(color: _warningGradient[0].withOpacity(0.3)),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(colors: _warningGradient),
                          borderRadius: BorderRadius.circular(12.r),
                        ),
                        child: Icon(Icons.warning_amber_rounded, color: Colors.white, size: 24),
                      ),
                      SizedBox(width: 14),
                      Expanded(
                        child: _isLoadingPreview
                            ? Row(
                                children: [
                                  SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      valueColor: AlwaysStoppedAnimation(_warningGradient[0]),
                                    ),
                                  ),
                                  SizedBox(width: 12),
                                  Text(
                                    'Подсчёт файлов...',
                                    style: TextStyle(
                                      color: _warningGradient[0],
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              )
                            : Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Будет удалено:',
                                    style: TextStyle(
                                      fontSize: 13.sp,
                                      color: Color(0xFF2D3748),
                                    ),
                                  ),
                                  Text(
                                    '$_previewCount файлов',
                                    style: TextStyle(
                                      fontSize: 18.sp,
                                      fontWeight: FontWeight.bold,
                                      color: _warningGradient[0],
                                    ),
                                  ),
                                ],
                              ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Actions
          Container(
            padding: EdgeInsets.fromLTRB(20.w, 0.h, 20.w, 20.h),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _isDeleting ? null : () => Navigator.pop(context, false),
                    style: OutlinedButton.styleFrom(
                      padding: EdgeInsets.symmetric(vertical: 14.h),
                      side: BorderSide(color: Colors.grey[300]!),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14.r),
                      ),
                    ),
                    child: Text(
                      'Отмена',
                      style: TextStyle(
                        color: Colors.grey[600],
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
                SizedBox(width: 12),
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: (_isDeleting || _previewCount == 0)
                            ? [Colors.grey[400]!, Colors.grey[500]!]
                            : _dangerGradient,
                      ),
                      borderRadius: BorderRadius.circular(14.r),
                      boxShadow: (_isDeleting || _previewCount == 0)
                          ? []
                          : [
                              BoxShadow(
                                color: _dangerGradient[0].withOpacity(0.4),
                                blurRadius: 8,
                                offset: Offset(0, 4),
                              ),
                            ],
                    ),
                    child: ElevatedButton(
                      onPressed: (_isDeleting || _previewCount == 0) ? null : _performCleanup,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.transparent,
                        shadowColor: Colors.transparent,
                        foregroundColor: Colors.white,
                        padding: EdgeInsets.symmetric(vertical: 14.h),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14.r),
                        ),
                      ),
                      child: _isDeleting
                          ? SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.5,
                                color: Colors.white,
                              ),
                            )
                          : Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.delete_outline, size: 20),
                                SizedBox(width: 8),
                                Text(
                                  'Удалить',
                                  style: TextStyle(fontWeight: FontWeight.bold),
                                ),
                              ],
                            ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
