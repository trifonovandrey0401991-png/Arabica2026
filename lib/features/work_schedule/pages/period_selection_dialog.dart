import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';

// Диалог для выбора периода (числа месяца)
class PeriodSelectionDialog extends StatefulWidget {
  final int startDay;
  final int endDay;
  final int maxDay;

  const PeriodSelectionDialog({
    super.key,
    required this.startDay,
    required this.endDay,
    required this.maxDay,
  });

  @override
  State<PeriodSelectionDialog> createState() => _PeriodSelectionDialogState();
}

class _PeriodSelectionDialogState extends State<PeriodSelectionDialog> {
  late int _startDay;
  late int _endDay;

  @override
  void initState() {
    super.initState();
    // Ограничиваем значения максимальным днём месяца
    _startDay = widget.startDay.clamp(1, widget.maxDay);
    _endDay = widget.endDay.clamp(_startDay, widget.maxDay);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.emeraldDark,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.white.withOpacity(0.15)),
      ),
      title: Text('Выберите период', style: TextStyle(color: Colors.white.withOpacity(0.95))),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Text('С: ', style: TextStyle(color: Colors.white.withOpacity(0.7))),
              Expanded(
                child: Theme(
                  data: Theme.of(context).copyWith(
                    canvasColor: AppColors.emeraldDark,
                  ),
                  child: DropdownButtonFormField<int>(
                    value: _startDay,
                    dropdownColor: AppColors.emeraldDark,
                    style: TextStyle(color: Colors.white.withOpacity(0.9)),
                    decoration: InputDecoration(
                      border: OutlineInputBorder(
                        borderSide: BorderSide(color: Colors.white.withOpacity(0.2)),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderSide: BorderSide(color: Colors.white.withOpacity(0.2)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderSide: BorderSide(color: AppColors.gold),
                      ),
                    ),
                    items: List.generate(widget.maxDay, (i) => i + 1).map((day) {
                      return DropdownMenuItem<int>(
                        value: day,
                        child: Text('$day'),
                      );
                    }).toList(),
                    onChanged: (value) {
                      if (value != null) {
                        setState(() {
                          _startDay = value;
                          if (_endDay < _startDay) {
                            _endDay = _startDay;
                          }
                        });
                      }
                    },
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: 16),
          Row(
            children: [
              Text('По: ', style: TextStyle(color: Colors.white.withOpacity(0.7))),
              Expanded(
                child: Theme(
                  data: Theme.of(context).copyWith(
                    canvasColor: AppColors.emeraldDark,
                  ),
                  child: DropdownButtonFormField<int>(
                    value: _endDay,
                    dropdownColor: AppColors.emeraldDark,
                    style: TextStyle(color: Colors.white.withOpacity(0.9)),
                    decoration: InputDecoration(
                      border: OutlineInputBorder(
                        borderSide: BorderSide(color: Colors.white.withOpacity(0.2)),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderSide: BorderSide(color: Colors.white.withOpacity(0.2)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderSide: BorderSide(color: AppColors.gold),
                      ),
                    ),
                    items: List.generate(widget.maxDay - _startDay + 1, (i) => _startDay + i).map((day) {
                      return DropdownMenuItem<int>(
                        value: day,
                        child: Text('$day'),
                      );
                    }).toList(),
                    onChanged: (value) {
                      if (value != null) {
                        setState(() {
                          _endDay = value;
                        });
                      }
                    },
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text('Отмена', style: TextStyle(color: Colors.white.withOpacity(0.7))),
        ),
        ElevatedButton(
          onPressed: () {
            Navigator.of(context).pop({
              'startDay': _startDay,
              'endDay': _endDay,
            });
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.gold,
            foregroundColor: Colors.white,
          ),
          child: Text('Применить'),
        ),
      ],
    );
  }
}
