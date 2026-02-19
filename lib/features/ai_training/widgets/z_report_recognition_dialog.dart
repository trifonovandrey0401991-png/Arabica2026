import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../models/z_report_sample_model.dart';
import '../services/z_report_service.dart';
import 'z_report_region_selector.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

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
  final Map<String, dynamic>? expectedRanges; // Intelligence: ожидаемые диапазоны

  const ZReportRecognitionDialog({
    super.key,
    required this.imageBase64,
    this.recognizedData,
    this.shopAddress,
    this.employeeName,
    this.expectedRanges,
  });

  /// Показать диалог и вернуть результат
  static Future<ZReportRecognitionResult?> show(
    BuildContext context, {
    required String imageBase64,
    ZReportData? recognizedData,
    String? shopAddress,
    String? employeeName,
    Map<String, dynamic>? expectedRanges,
  }) {
    return showDialog<ZReportRecognitionResult>(
      context: context,
      barrierDismissible: false,
      builder: (context) => ZReportRecognitionDialog(
        imageBase64: imageBase64,
        recognizedData: recognizedData,
        shopAddress: shopAddress,
        employeeName: employeeName,
        expectedRanges: expectedRanges,
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
  Map<String, Map<String, double>>? _fieldRegions;

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
      if (mounted) setState(() => _isSaving = true);

      await ZReportService.saveSample(
        imageBase64: widget.imageBase64,
        totalSum: revenue,
        cashSum: cash,
        ofdNotSent: ofdNotSent,
        resourceKeys: resourceKeys,
        shopAddress: widget.shopAddress,
        employeeName: widget.employeeName,
        fieldRegions: _fieldRegions,
      );

      if (mounted) setState(() => _isSaving = false);
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
    if (mounted) setState(() => _isEditing = true);
  }

  void _cancel() {
    Navigator.of(context).pop(null);
  }

  Future<void> _openRegionSelector() async {
    final regions = await ZReportRegionSelector.show(
      context,
      imageBase64: widget.imageBase64,
      initialRegions: _fieldRegions,
    );
    if (regions != null && mounted) {
      setState(() {
        _fieldRegions = regions;
        _isEditing = true;
      });
    }
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
          SizedBox(width: 8),
          Expanded(
            child: Text(
              hasData ? 'Распознано с Z-отчёта' : 'Не удалось распознать',
              style: TextStyle(fontSize: 18.sp),
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
              Text(
                'Введите данные вручную. Это поможет обучить ИИ.',
                style: TextStyle(color: Colors.grey),
              ),
              SizedBox(height: 16),
            ],

            // Выручка
            _buildField(
              controller: _revenueController,
              label: 'Выручка (общая сумма)',
              icon: Icons.currency_ruble,
              confidence: data?.confidence['totalSum'],
              enabled: _isEditing || !hasData,
              isMoney: true,
              expectedRange: _getRangeForField('totalSum'),
            ),
            SizedBox(height: 12),

            // Наличные
            _buildField(
              controller: _cashController,
              label: 'Наличные',
              icon: Icons.payments_outlined,
              confidence: data?.confidence['cashSum'],
              enabled: _isEditing || !hasData,
              isMoney: true,
              expectedRange: _getRangeForField('cashSum'),
            ),
            SizedBox(height: 12),

            // Не переданы в ОФД
            _buildField(
              controller: _ofdNotSentController,
              label: 'Не переданы в ОФД',
              icon: Icons.cloud_off,
              confidence: data?.confidence['ofdNotSent'],
              enabled: _isEditing || !hasData,
              isInteger: true,
              expectedRange: _getRangeForField('ofdNotSent'),
            ),
            SizedBox(height: 12),

            // Ресурс ключей
            _buildField(
              controller: _resourceKeysController,
              label: 'Ресурс ключей',
              icon: Icons.key,
              confidence: data?.confidence['resourceKeys'],
              enabled: _isEditing || !hasData,
              isInteger: true,
              expectedRange: _getRangeForField('resourceKeys'),
            ),

            if (_isEditing) ...[
              SizedBox(height: 16),
              Container(
                padding: EdgeInsets.all(8.w),
                decoration: BoxDecoration(
                  color: Colors.blue[50],
                  borderRadius: BorderRadius.circular(8.r),
                ),
                child: Row(
                  children: [
                    Icon(Icons.school, color: Colors.blue, size: 20),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Исправленные данные будут использованы для обучения ИИ',
                        style: TextStyle(fontSize: 12.sp, color: Colors.blue),
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
            child: Text('Отмена'),
          ),
          TextButton(
            onPressed: _startEditing,
            child: Text('Исправить'),
          ),
          ElevatedButton(
            onPressed: _confirm,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primaryGreen,
            ),
            child: Text('Подтвердить'),
          ),
        ] else ...[
          TextButton(
            onPressed: _cancel,
            child: Text('Отмена'),
          ),
          IconButton(
            onPressed: _openRegionSelector,
            icon: Icon(Icons.crop_free, color: AppColors.primaryGreen),
            tooltip: 'Указать области',
          ),
          ElevatedButton(
            onPressed: _isSaving ? null : _confirm,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primaryGreen,
            ),
            child: _isSaving
                ? SizedBox(
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

  /// Извлечь диапазон для поля из expectedRanges
  Map<String, dynamic>? _getRangeForField(String fieldName) {
    final ranges = widget.expectedRanges;
    if (ranges == null) return null;
    final fieldRange = ranges[fieldName];
    if (fieldRange is Map<String, dynamic> &&
        fieldRange['min'] != null &&
        fieldRange['max'] != null) {
      return fieldRange;
    }
    return null;
  }

  /// Форматирование числа для подсказки (12 345 вместо 12345.00)
  String _formatHint(num value, bool isMoney) {
    if (isMoney) {
      final intVal = value.round();
      // Разделитель тысяч пробелом
      final str = intVal.toString();
      final buf = StringBuffer();
      for (int i = 0; i < str.length; i++) {
        if (i > 0 && (str.length - i) % 3 == 0) buf.write(' ');
        buf.write(str[i]);
      }
      return buf.toString();
    }
    return value is double ? value.toStringAsFixed(1) : value.toString();
  }

  Widget _buildField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    String? confidence,
    bool enabled = true,
    bool isInteger = false,
    bool isMoney = false,
    Map<String, dynamic>? expectedRange,
  }) {
    final isConfirmed = confidence == 'high' ||
        confidence == 'intelligence_confirmed' ||
        confidence == 'learned';

    // Проверяем попадание значения в ожидаемый диапазон
    bool? isInRange;
    if (expectedRange != null && controller.text.isNotEmpty) {
      final value = double.tryParse(controller.text);
      if (value != null) {
        final min = (expectedRange['min'] as num).toDouble();
        final max = (expectedRange['max'] as num).toDouble();
        isInRange = value >= min && value <= max;
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12.r),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 4,
                offset: Offset(0, 2),
              ),
            ],
          ),
          child: TextField(
            controller: controller,
            enabled: enabled,
            keyboardType: isInteger
                ? TextInputType.number
                : TextInputType.numberWithOptions(decimal: true),
            style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.w500),
            decoration: InputDecoration(
              labelText: label,
              labelStyle: TextStyle(color: Colors.grey.shade600),
              prefixIcon: Container(
                margin: EdgeInsets.all(8.w),
                padding: EdgeInsets.all(8.w),
                decoration: BoxDecoration(
                  color: isMoney ? Colors.teal.shade50 : Colors.blueGrey.shade50,
                  borderRadius: BorderRadius.circular(8.r),
                ),
                child: Icon(
                  icon,
                  color: isMoney ? Colors.teal.shade700 : Colors.blueGrey.shade700,
                  size: 20,
                ),
              ),
              suffixText: isMoney ? 'руб' : null,
              suffixStyle: TextStyle(
                color: Colors.teal.shade700,
                fontWeight: FontWeight.bold,
                fontSize: 16.sp,
              ),
              suffixIcon: confidence != null
                  ? Icon(
                      isConfirmed ? Icons.check_circle : Icons.help_outline,
                      color: isConfirmed ? Colors.green : Colors.orange,
                      size: 20,
                    )
                  : null,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12.r),
                borderSide: BorderSide(color: Colors.grey.shade300),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12.r),
                borderSide: BorderSide(color: Colors.grey.shade300),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12.r),
                borderSide: BorderSide(color: Colors.teal.shade400, width: 2),
              ),
              disabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12.r),
                borderSide: BorderSide(color: Colors.grey.shade200),
              ),
              filled: true,
              fillColor: enabled ? Colors.white : Colors.grey.shade50,
              contentPadding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 14.h),
            ),
          ),
        ),
        // Подсказка ожидаемого диапазона от Intelligence
        if (expectedRange != null) ...[
          Padding(
            padding: EdgeInsets.only(left: 12.w, top: 4.h),
            child: Row(
              children: [
                Icon(
                  isInRange == true
                      ? Icons.trending_flat
                      : isInRange == false
                          ? Icons.warning_amber_rounded
                          : Icons.insights,
                  size: 14,
                  color: isInRange == true
                      ? Colors.green.shade600
                      : isInRange == false
                          ? Colors.orange.shade700
                          : Colors.grey.shade500,
                ),
                SizedBox(width: 4),
                Text(
                  'Обычно: ${_formatHint(expectedRange['min'] as num, isMoney)}'
                  ' – ${_formatHint(expectedRange['max'] as num, isMoney)}'
                  '${isMoney ? ' руб' : ''}',
                  style: TextStyle(
                    fontSize: 11.sp,
                    color: isInRange == true
                        ? Colors.green.shade600
                        : isInRange == false
                            ? Colors.orange.shade700
                            : Colors.grey.shade500,
                    fontWeight: isInRange != null ? FontWeight.w500 : FontWeight.normal,
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

/// Показать диалог ошибки распознавания
Future<void> showRecognitionErrorDialog(BuildContext context) {
  return showDialog(
    context: context,
    builder: (context) => AlertDialog(
      title: Row(
        children: [
          Icon(Icons.error_outline, color: Colors.red),
          SizedBox(width: 8),
          Text('Ошибка распознавания'),
        ],
      ),
      content: Text(
        'Не удалось распознать данные с фото Z-отчёта. '
        'Пожалуйста, введите данные вручную на следующем шаге.',
      ),
      actions: [
        ElevatedButton(
          onPressed: () => Navigator.pop(context),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primaryGreen,
          ),
          child: Text('Понятно'),
        ),
      ],
    ),
  );
}
