import 'package:flutter/material.dart';
import '../../work_schedule/models/work_schedule_model.dart';
import '../../shops/models/shop_model.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

class ShiftEditDialog extends StatefulWidget {
  final String employeeId;
  final String employeeName;
  final DateTime date;
  final WorkScheduleEntry? existingEntry;
  final List<Shop> shops;

  const ShiftEditDialog({
    super.key,
    required this.employeeId,
    required this.employeeName,
    required this.date,
    this.existingEntry,
    required this.shops,
  });

  @override
  State<ShiftEditDialog> createState() => _ShiftEditDialogState();
}

class _ShiftEditDialogState extends State<ShiftEditDialog> {
  static final Color _emeraldDark = Color(0xFF0D2E2E);
  static final Color _night = Color(0xFF051515);
  static final Color _gold = Color(0xFFD4AF37);

  String? _selectedShopAddress;
  ShiftType? _selectedShiftType;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    if (widget.existingEntry != null) {
      _selectedShopAddress = widget.existingEntry!.shopAddress;
      _selectedShiftType = widget.existingEntry!.shiftType;
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: _emeraldDark,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20.r)),
      title: Text(
        'Смена: ${widget.employeeName}',
        style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Дата: ${_formatDate(widget.date)}',
              style: TextStyle(
                fontSize: 16.sp,
                fontWeight: FontWeight.bold,
                color: Colors.white.withOpacity(0.7),
              ),
            ),
            SizedBox(height: 16),
            Text(
              'Магазин:',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: Colors.white.withOpacity(0.7),
              ),
            ),
            SizedBox(height: 8),
            Theme(
              data: Theme.of(context).copyWith(
                canvasColor: _night,
              ),
              child: DropdownButtonFormField<String>(
                value: _selectedShopAddress,
                dropdownColor: _night,
                style: TextStyle(color: Colors.white, fontSize: 14.sp),
                iconEnabledColor: _gold,
                decoration: InputDecoration(
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12.r),
                    borderSide: BorderSide(color: Colors.white.withOpacity(0.1)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12.r),
                    borderSide: BorderSide(color: Colors.white.withOpacity(0.1)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12.r),
                    borderSide: BorderSide(color: _gold, width: 1.5),
                  ),
                  filled: true,
                  fillColor: Colors.white.withOpacity(0.06),
                  hintText: 'Выберите магазин',
                  hintStyle: TextStyle(color: Colors.white.withOpacity(0.4)),
                ),
                items: widget.shops.map((shop) {
                  return DropdownMenuItem<String>(
                    value: shop.address,
                    child: Text(
                      shop.address,
                      style: TextStyle(color: Colors.white),
                    ),
                  );
                }).toList(),
                onChanged: (value) {
                  setState(() {
                    _selectedShopAddress = value;
                  });
                },
              ),
            ),
            SizedBox(height: 16),
            Text(
              'Тип смены:',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: Colors.white.withOpacity(0.7),
              ),
            ),
            SizedBox(height: 8),
            ...ShiftType.values.map((type) {
              return RadioListTile<ShiftType>(
                title: Text(
                  '${type.label} (${type.timeRange})',
                  style: TextStyle(color: Colors.white, fontSize: 14.sp),
                ),
                value: type,
                groupValue: _selectedShiftType,
                onChanged: (value) {
                  setState(() {
                    _selectedShiftType = value;
                  });
                },
                activeColor: _gold,
                tileColor: Colors.transparent,
              );
            }),
            Divider(color: Colors.white.withOpacity(0.1)),
            SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () {
                  setState(() {
                    _selectedShopAddress = null;
                    _selectedShiftType = null;
                  });
                },
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: Colors.white.withOpacity(0.2)),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12.r),
                  ),
                  padding: EdgeInsets.symmetric(vertical: 12.h),
                ),
                child: Text(
                  'Очистить (выходной)',
                  style: TextStyle(color: Colors.white.withOpacity(0.6)),
                ),
              ),
            ),
          ],
        ),
      ),
      actionsPadding: EdgeInsets.fromLTRB(16.w, 0.h, 16.w, 16.h),
      actions: [
        TextButton(
          onPressed: _isLoading ? null : () => Navigator.of(context).pop(),
          style: TextButton.styleFrom(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12.r),
            ),
            padding: EdgeInsets.symmetric(horizontal: 20.w, vertical: 12.h),
          ),
          child: Text(
            'Отмена',
            style: TextStyle(color: Colors.white.withOpacity(0.6)),
          ),
        ),
        ElevatedButton(
          onPressed: _isLoading ? null : _save,
          style: ElevatedButton.styleFrom(
            backgroundColor: _gold,
            foregroundColor: _night,
            disabledBackgroundColor: _gold.withOpacity(0.4),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12.r),
            ),
            padding: EdgeInsets.symmetric(horizontal: 24.w, vertical: 12.h),
          ),
          child: _isLoading
              ? SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: _night,
                  ),
                )
              : Text(
                  'Сохранить',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
        ),
      ],
    );
  }

  String _formatDate(DateTime date) {
    return '${date.day.toString().padLeft(2, '0')}.${date.month.toString().padLeft(2, '0')}.${date.year}';
  }

  Future<void> _save() async {
    if (_selectedShopAddress == null || _selectedShiftType == null) {
      // Если ничего не выбрано, это выходной - удаляем запись, если она была
      if (widget.existingEntry != null) {
        Navigator.of(context).pop({
          'action': 'delete',
          'entry': widget.existingEntry,
        });
      } else {
        Navigator.of(context).pop();
      }
      return;
    }

    setState(() {
      _isLoading = true;
    });

    // Создаем или обновляем запись
    final entry = WorkScheduleEntry(
      id: widget.existingEntry?.id ?? '',
      employeeId: widget.employeeId,
      employeeName: widget.employeeName,
      shopAddress: _selectedShopAddress!,
      date: widget.date,
      shiftType: _selectedShiftType!,
    );

    Navigator.of(context).pop({
      'action': 'save',
      'entry': entry,
    });
  }
}
