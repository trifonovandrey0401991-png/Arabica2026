import 'package:flutter/material.dart';
import '../models/cleanup_category.dart';
import '../services/cleanup_service.dart';

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
  DateTime _selectedDate = DateTime.now().subtract(const Duration(days: 30));
  int _previewCount = 0;
  bool _isLoadingPreview = false;
  bool _isDeleting = false;

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
      locale: const Locale('ru'),
      helpText: 'Удалить данные ДО этой даты',
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
        title: const Text('Подтверждение'),
        content: Text(
          'Вы уверены, что хотите удалить $_previewCount файлов из категории "${widget.category.name}"?\n\nЭто действие необратимо!',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Отмена'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('Удалить'),
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
            content: Text('Удалено $deletedCount файлов ($freedMB MB)'),
            backgroundColor: Colors.green,
          ),
        );

        Navigator.pop(context, true);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Ошибка при очистке данных'),
            backgroundColor: Colors.red,
          ),
        );
        setState(() => _isDeleting = false);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Ошибка при очистке данных'),
            backgroundColor: Colors.red,
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

    return AlertDialog(
      title: Text('Очистить: ${widget.category.name}'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Удалить данные ДО:',
            style: TextStyle(fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 12),
          InkWell(
            onTap: _selectDate,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey[400]!),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    dateStr,
                    style: const TextStyle(fontSize: 16),
                  ),
                  const Icon(Icons.calendar_today, color: Color(0xFF004D40)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.orange[50],
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.orange[200]!),
            ),
            child: Row(
              children: [
                Icon(Icons.warning_amber_rounded, color: Colors.orange[700]),
                const SizedBox(width: 12),
                Expanded(
                  child: _isLoadingPreview
                      ? const Text('Подсчёт...')
                      : Text(
                          'Будет удалено: $_previewCount файлов',
                          style: TextStyle(
                            color: Colors.orange[900],
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                ),
              ],
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _isDeleting ? null : () => Navigator.pop(context, false),
          child: const Text('Отмена'),
        ),
        ElevatedButton(
          onPressed: (_isDeleting || _previewCount == 0) ? null : _performCleanup,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.red,
            foregroundColor: Colors.white,
          ),
          child: _isDeleting
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Text('Удалить'),
        ),
      ],
    );
  }
}
