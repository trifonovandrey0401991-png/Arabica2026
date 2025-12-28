import 'package:flutter/material.dart';
import '../../work_schedule/models/work_schedule_model.dart';
import '../../shops/models/shop_model.dart';

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
      title: Text('Смена: ${widget.employeeName}'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Дата: ${_formatDate(widget.date)}',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            const Text('Магазин:', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              value: _selectedShopAddress,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: 'Выберите магазин',
              ),
              items: widget.shops.map((shop) {
                return DropdownMenuItem<String>(
                  value: shop.address,
                  child: Text(shop.address),
                );
              }).toList(),
              onChanged: (value) {
                setState(() {
                  _selectedShopAddress = value;
                });
              },
            ),
            const SizedBox(height: 16),
            const Text('Тип смены:', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            ...ShiftType.values.map((type) {
              return RadioListTile<ShiftType>(
                title: Text('${type.label} (${type.timeRange})'),
                value: type,
                groupValue: _selectedShiftType,
                onChanged: (value) {
                  setState(() {
                    _selectedShiftType = value;
                  });
                },
                activeColor: type.color,
              );
            }),
            const SizedBox(height: 8),
            ElevatedButton(
              onPressed: () {
                setState(() {
                  _selectedShopAddress = null;
                  _selectedShiftType = null;
                });
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.grey,
              ),
              child: const Text('Очистить (выходной)'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isLoading ? null : () => Navigator.of(context).pop(),
          child: const Text('Отмена'),
        ),
        ElevatedButton(
          onPressed: _isLoading ? null : _save,
          child: _isLoading
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Сохранить'),
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


