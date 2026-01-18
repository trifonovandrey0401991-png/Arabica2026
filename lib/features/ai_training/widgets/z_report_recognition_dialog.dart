import 'package:flutter/material.dart';
import '../models/z_report_sample_model.dart';
import '../services/z_report_service.dart';

/// Результат диалога распознавания Z-отчёта
class ZReportRecognitionResult {
  final double revenue;
  final double cash;
  final int ofdNotSent;
  final int resourceKeys;
  final bool wasEdited;

  ZReportRecognitionResult({
    required this.revenue,
    required this.cash,
    required this.ofdNotSent,
    required this.resourceKeys,
    this.wasEdited = false,
  });
}

/// Диалог распознавания Z-отчёта
/// Показывает распознанные данные и позволяет их редактировать
class ZReportRecognitionDialog extends StatefulWidget {
  final String imageBase64;
  final ZReportData? recognizedData;
  final String? shopAddress;
  final String? employeeName;

  const ZReportRecognitionDialog({
    super.key,
    required this.imageBase64,
    this.recognizedData,
    this.shopAddress,
    this.employeeName,
  });

  /// Показать диалог и вернуть результат
  static Future<ZReportRecognitionResult?> show(
    BuildContext context, {
    required String imageBase64,
    ZReportData? recognizedData,
    String? shopAddress,
    String? employeeName,
  }) {
    return showDialog<ZReportRecognitionResult>(
      context: context,
      barrierDismissible: false,
      builder: (context) => ZReportRecognitionDialog(
        imageBase64: imageBase64,
        recognizedData: recognizedData,
        shopAddress: shopAddress,
        employeeName: employeeName,
      ),
    );
  }

  @override
  State<ZReportRecognitionDialog> createState() =>
      _ZReportRecognitionDialogState();
}

class _ZReportRecognitionDialogState extends State<ZReportRecognitionDialog> {
  final _revenueController = TextEditingController();
  final _cashController = TextEditingController();
  final _ofdNotSentController = TextEditingController();
  final _resourceKeysController = TextEditingController();

  bool _isEditing = false;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _initializeFields();
  }

  void _initializeFields() {
    final data = widget.recognizedData;
    if (data != null) {
      if (data.totalSum != null) {
        _revenueController.text = data.totalSum!.toStringAsFixed(2);
      }
      if (data.cashSum != null) {
        _cashController.text = data.cashSum!.toStringAsFixed(2);
      }
      if (data.ofdNotSent != null) {
        _ofdNotSentController.text = data.ofdNotSent.toString();
      }
      if (data.resourceKeys != null) {
        _resourceKeysController.text = data.resourceKeys.toString();
      }
    }
  }

  @override
  void dispose() {
    _revenueController.dispose();
    _cashController.dispose();
    _ofdNotSentController.dispose();
    _resourceKeysController.dispose();
    super.dispose();
  }

  Future<void> _confirm() async {
    final revenue = double.tryParse(_revenueController.text) ?? 0;
    final cash = double.tryParse(_cashController.text) ?? 0;
    final ofdNotSent = int.tryParse(_ofdNotSentController.text) ?? 0;
    final resourceKeys = int.tryParse(_resourceKeysController.text) ?? 0;

    // Если данные были отредактированы - сохраняем как образец для обучения
    if (_isEditing) {
      setState(() => _isSaving = true);

      await ZReportService.saveSample(
        imageBase64: widget.imageBase64,
        totalSum: revenue,
        cashSum: cash,
        ofdNotSent: ofdNotSent,
        resourceKeys: resourceKeys,
        shopAddress: widget.shopAddress,
        employeeName: widget.employeeName,
      );

      setState(() => _isSaving = false);
    }

    if (mounted) {
      Navigator.of(context).pop(ZReportRecognitionResult(
        revenue: revenue,
        cash: cash,
        ofdNotSent: ofdNotSent,
        resourceKeys: resourceKeys,
        wasEdited: _isEditing,
      ));
    }
  }

  void _startEditing() {
    setState(() => _isEditing = true);
  }

  void _cancel() {
    Navigator.of(context).pop(null);
  }

  @override
  Widget build(BuildContext context) {
    final data = widget.recognizedData;
    final hasData = data != null &&
        (data.totalSum != null || data.cashSum != null || data.ofdNotSent != null);

    return AlertDialog(
      title: Row(
        children: [
          Icon(
            hasData ? Icons.check_circle : Icons.warning_amber,
            color: hasData ? Colors.green : Colors.orange,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              hasData ? 'Распознано с Z-отчёта' : 'Не удалось распознать',
              style: const TextStyle(fontSize: 18),
            ),
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (!hasData) ...[
              const Text(
                'Введите данные вручную. Это поможет обучить ИИ.',
                style: TextStyle(color: Colors.grey),
              ),
              const SizedBox(height: 16),
            ],

            // Выручка
            _buildField(
              controller: _revenueController,
              label: 'Выручка (общая сумма)',
              icon: Icons.currency_ruble,
              confidence: data?.confidence['totalSum'],
              enabled: _isEditing || !hasData,
              isMoney: true,
            ),
            const SizedBox(height: 12),

            // Наличные
            _buildField(
              controller: _cashController,
              label: 'Наличные',
              icon: Icons.payments_outlined,
              confidence: data?.confidence['cashSum'],
              enabled: _isEditing || !hasData,
              isMoney: true,
            ),
            const SizedBox(height: 12),

            // Не переданы в ОФД
            _buildField(
              controller: _ofdNotSentController,
              label: 'Не переданы в ОФД',
              icon: Icons.cloud_off,
              confidence: data?.confidence['ofdNotSent'],
              enabled: _isEditing || !hasData,
              isInteger: true,
            ),
            const SizedBox(height: 12),

            // Ресурс ключей
            _buildField(
              controller: _resourceKeysController,
              label: 'Ресурс ключей',
              icon: Icons.key,
              confidence: data?.confidence['resourceKeys'],
              enabled: _isEditing || !hasData,
              isInteger: true,
            ),

            if (_isEditing) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.blue[50],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.school, color: Colors.blue, size: 20),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Исправленные данные будут использованы для обучения ИИ',
                        style: TextStyle(fontSize: 12, color: Colors.blue),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        if (!_isEditing && hasData) ...[
          TextButton(
            onPressed: _cancel,
            child: const Text('Отмена'),
          ),
          TextButton(
            onPressed: _startEditing,
            child: const Text('Исправить'),
          ),
          ElevatedButton(
            onPressed: _confirm,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF004D40),
            ),
            child: const Text('Подтвердить'),
          ),
        ] else ...[
          TextButton(
            onPressed: _cancel,
            child: const Text('Отмена'),
          ),
          ElevatedButton(
            onPressed: _isSaving ? null : _confirm,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF004D40),
            ),
            child: _isSaving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : Text(_isEditing ? 'Сохранить' : 'Подтвердить'),
          ),
        ],
      ],
    );
  }

  Widget _buildField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    String? confidence,
    bool enabled = true,
    bool isInteger = false,
    bool isMoney = false,
  }) {
    final isFound = confidence == 'high';

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: TextField(
        controller: controller,
        enabled: enabled,
        keyboardType: isInteger
            ? TextInputType.number
            : const TextInputType.numberWithOptions(decimal: true),
        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: TextStyle(color: Colors.grey.shade600),
          prefixIcon: Container(
            margin: const EdgeInsets.all(8),
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: isMoney ? Colors.teal.shade50 : Colors.blueGrey.shade50,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              icon,
              color: isMoney ? Colors.teal.shade700 : Colors.blueGrey.shade700,
              size: 20,
            ),
          ),
          suffixText: isMoney ? '₽' : null,
          suffixStyle: TextStyle(
            color: Colors.teal.shade700,
            fontWeight: FontWeight.bold,
            fontSize: 16,
          ),
          suffixIcon: confidence != null
              ? Icon(
                  isFound ? Icons.check_circle : Icons.help_outline,
                  color: isFound ? Colors.green : Colors.orange,
                  size: 20,
                )
              : null,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: Colors.grey.shade300),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: Colors.grey.shade300),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: Colors.teal.shade400, width: 2),
          ),
          disabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: Colors.grey.shade200),
          ),
          filled: true,
          fillColor: enabled ? Colors.white : Colors.grey.shade50,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        ),
      ),
    );
  }
}

/// Показать диалог ошибки распознавания
Future<void> showRecognitionErrorDialog(BuildContext context) {
  return showDialog(
    context: context,
    builder: (context) => AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.error_outline, color: Colors.red),
          SizedBox(width: 8),
          Text('Ошибка распознавания'),
        ],
      ),
      content: const Text(
        'Не удалось распознать данные с фото Z-отчёта. '
        'Пожалуйста, введите данные вручную на следующем шаге.',
      ),
      actions: [
        ElevatedButton(
          onPressed: () => Navigator.pop(context),
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF004D40),
          ),
          child: const Text('Понятно'),
        ),
      ],
    ),
  );
}
