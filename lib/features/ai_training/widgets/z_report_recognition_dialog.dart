import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../models/z_report_sample_model.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

/// Результат диалога распознавания Z-отчёта
class ZReportRecognitionResult {
  final double revenue;
  final double cash;
  final int ofdNotSent;
  final int resourceKeys;
  final bool wasEdited;
  final bool needsRegionSelection;

  ZReportRecognitionResult({
    required this.revenue,
    required this.cash,
    required this.ofdNotSent,
    required this.resourceKeys,
    this.wasEdited = false,
    this.needsRegionSelection = false,
  });
}

/// Состояния единого диалога распознавания
enum _DialogState {
  initialSuccess,
  initialFail,
  afterRegionsSuccess,
  afterRegionsFail,
  editing,
}

/// Единый диалог распознавания Z-отчёта (Dark Emerald Bottom Sheet)
class ZReportRecognitionDialog extends StatefulWidget {
  final String imageBase64;
  final ZReportData? recognizedData;
  final String? shopAddress;
  final String? employeeName;
  final Map<String, dynamic>? expectedRanges;
  final bool isSecondAttempt;
  final bool secondAttemptFailed;

  const ZReportRecognitionDialog({
    super.key,
    required this.imageBase64,
    this.recognizedData,
    this.shopAddress,
    this.employeeName,
    this.expectedRanges,
    this.isSecondAttempt = false,
    this.secondAttemptFailed = false,
  });

  /// Показать диалог и вернуть результат
  static Future<ZReportRecognitionResult?> show(
    BuildContext context, {
    required String imageBase64,
    ZReportData? recognizedData,
    String? shopAddress,
    String? employeeName,
    Map<String, dynamic>? expectedRanges,
    bool isSecondAttempt = false,
    bool secondAttemptFailed = false,
  }) {
    return showModalBottomSheet<ZReportRecognitionResult>(
      context: context,
      isScrollControlled: true,
      isDismissible: false,
      enableDrag: false,
      backgroundColor: Colors.transparent,
      builder: (context) => ZReportRecognitionDialog(
        imageBase64: imageBase64,
        recognizedData: recognizedData,
        shopAddress: shopAddress,
        employeeName: employeeName,
        expectedRanges: expectedRanges,
        isSecondAttempt: isSecondAttempt,
        secondAttemptFailed: secondAttemptFailed,
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

  late _DialogState _state;

  @override
  void initState() {
    super.initState();
    _initializeState();
    _initializeFields();
  }

  void _initializeState() {
    final data = widget.recognizedData;
    final hasData = data != null &&
        (data.totalSum != null || data.cashSum != null || data.ofdNotSent != null);

    if (widget.isSecondAttempt) {
      if (widget.secondAttemptFailed || !hasData) {
        _state = _DialogState.afterRegionsFail;
      } else {
        _state = _DialogState.afterRegionsSuccess;
      }
    } else {
      _state = hasData ? _DialogState.initialSuccess : _DialogState.initialFail;
    }
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

  bool get _fieldsEnabled =>
      _state == _DialogState.afterRegionsFail ||
      _state == _DialogState.editing;

  void _confirm() {
    final revenue = double.tryParse(_revenueController.text) ?? 0;
    final cash = double.tryParse(_cashController.text) ?? 0;
    final ofdNotSent = int.tryParse(_ofdNotSentController.text) ?? 0;
    final resourceKeys = int.tryParse(_resourceKeysController.text) ?? 0;

    Navigator.of(context).pop(ZReportRecognitionResult(
      revenue: revenue,
      cash: cash,
      ofdNotSent: ofdNotSent,
      resourceKeys: resourceKeys,
      wasEdited: _state == _DialogState.editing ||
                 _state == _DialogState.afterRegionsFail,
    ));
  }

  void _requestRegionSelection() {
    Navigator.of(context).pop(ZReportRecognitionResult(
      revenue: 0,
      cash: 0,
      ofdNotSent: 0,
      resourceKeys: 0,
      needsRegionSelection: true,
    ));
  }

  void _startEditing() {
    if (mounted) setState(() => _state = _DialogState.editing);
  }

  void _cancel() {
    Navigator.of(context).pop(null);
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [AppColors.emerald, AppColors.emeraldDark, AppColors.night],
            stops: [0.0, 0.5, 1.0],
          ),
          borderRadius: BorderRadius.vertical(top: Radius.circular(20.r)),
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            child: Padding(
              padding: EdgeInsets.fromLTRB(20.w, 12.h, 20.w, 16.h),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Drag handle
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.3),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  SizedBox(height: 12.h),

                  // Title
                  _buildTitle(),
                  SizedBox(height: 8.h),

                  // Status message
                  _buildStatusMessage(),
                  SizedBox(height: 16.h),

                  // Fields
                  _buildField(
                    controller: _revenueController,
                    label: 'Выручка (общая сумма)',
                    icon: Icons.currency_ruble,
                    confidence: widget.recognizedData?.confidence['totalSum'],
                    enabled: _fieldsEnabled,
                    isMoney: true,
                    expectedRange: _getRangeForField('totalSum'),
                  ),
                  SizedBox(height: 10.h),

                  _buildField(
                    controller: _cashController,
                    label: 'Наличные',
                    icon: Icons.payments_outlined,
                    confidence: widget.recognizedData?.confidence['cashSum'],
                    enabled: _fieldsEnabled,
                    isMoney: true,
                    expectedRange: _getRangeForField('cashSum'),
                  ),
                  SizedBox(height: 10.h),

                  _buildField(
                    controller: _ofdNotSentController,
                    label: 'Не переданы в ОФД',
                    icon: Icons.cloud_off,
                    confidence: widget.recognizedData?.confidence['ofdNotSent'],
                    enabled: _fieldsEnabled,
                    isInteger: true,
                    expectedRange: _getRangeForField('ofdNotSent'),
                  ),
                  SizedBox(height: 10.h),

                  _buildField(
                    controller: _resourceKeysController,
                    label: 'Ресурс ключей',
                    icon: Icons.key,
                    confidence: widget.recognizedData?.confidence['resourceKeys'],
                    enabled: _fieldsEnabled,
                    isInteger: true,
                    expectedRange: _getRangeForField('resourceKeys'),
                  ),

                  // Training hint
                  if (_fieldsEnabled) ...[
                    SizedBox(height: 12.h),
                    Container(
                      padding: EdgeInsets.all(10.w),
                      decoration: BoxDecoration(
                        color: AppColors.gold.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(10.r),
                        border: Border.all(color: AppColors.gold.withOpacity(0.3)),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.school, color: AppColors.gold, size: 18),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Исправленные данные помогут обучить ИИ',
                              style: TextStyle(fontSize: 12.sp, color: AppColors.gold),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],

                  SizedBox(height: 20.h),

                  // Action buttons
                  _buildActionButtons(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTitle() {
    IconData icon;
    Color iconColor;
    String title;

    switch (_state) {
      case _DialogState.initialSuccess:
      case _DialogState.afterRegionsSuccess:
        icon = Icons.smart_toy;
        iconColor = AppColors.turquoise;
        title = 'ИИ определил:';
      case _DialogState.initialFail:
        icon = Icons.warning_amber;
        iconColor = AppColors.warning;
        title = 'Не удалось распознать';
      case _DialogState.afterRegionsFail:
        icon = Icons.edit_note;
        iconColor = AppColors.warning;
        title = 'Введите вручную';
      case _DialogState.editing:
        icon = Icons.edit;
        iconColor = AppColors.gold;
        title = 'Исправление данных';
    }

    return Row(
      children: [
        Container(
          padding: EdgeInsets.all(8.w),
          decoration: BoxDecoration(
            color: iconColor.withOpacity(0.15),
            borderRadius: BorderRadius.circular(10.r),
          ),
          child: Icon(icon, color: iconColor, size: 22),
        ),
        SizedBox(width: 12),
        Expanded(
          child: Text(
            title,
            style: TextStyle(
              fontSize: 18.sp,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildStatusMessage() {
    String message;

    switch (_state) {
      case _DialogState.initialSuccess:
        message = 'Проверьте данные. Если верно — подтвердите.';
      case _DialogState.initialFail:
        message = 'Выделите области на фото для повторного распознавания.';
      case _DialogState.afterRegionsSuccess:
        message = 'ИИ распознал данные. Подтвердите или исправьте.';
      case _DialogState.afterRegionsFail:
        message = 'ИИ не смог распознать. Введите данные вручную.';
      case _DialogState.editing:
        message = 'Исправьте данные и нажмите Подтвердить.';
    }

    return Text(
      message,
      style: TextStyle(fontSize: 13.sp, color: Colors.white.withOpacity(0.6)),
    );
  }

  Widget _buildActionButtons() {
    switch (_state) {
      case _DialogState.initialSuccess:
        return Row(
          children: [
            Expanded(
              child: _outlineButton(
                label: 'Области',
                icon: Icons.crop_free,
                onPressed: _requestRegionSelection,
              ),
            ),
            SizedBox(width: 10),
            Expanded(
              child: _primaryButton(label: 'Подтвердить', onPressed: _confirm),
            ),
          ],
        );

      case _DialogState.initialFail:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _primaryButton(
              label: 'Выделить области',
              icon: Icons.crop_free,
              onPressed: _requestRegionSelection,
            ),
            SizedBox(height: 8.h),
            _textButton(label: 'Отмена', onPressed: _cancel),
          ],
        );

      case _DialogState.afterRegionsSuccess:
        return Row(
          children: [
            Expanded(
              child: _outlineButton(
                label: 'Исправить',
                onPressed: _startEditing,
                color: AppColors.warning,
              ),
            ),
            SizedBox(width: 10),
            Expanded(
              child: _primaryButton(label: 'Подтвердить', onPressed: _confirm),
            ),
          ],
        );

      case _DialogState.afterRegionsFail:
      case _DialogState.editing:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _primaryButton(label: 'Подтвердить', onPressed: _confirm),
            SizedBox(height: 8.h),
            _textButton(label: 'Отмена', onPressed: _cancel),
          ],
        );
    }
  }

  Widget _primaryButton({
    required String label,
    required VoidCallback onPressed,
    IconData? icon,
  }) {
    return ElevatedButton(
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.gold,
        foregroundColor: AppColors.night,
        padding: EdgeInsets.symmetric(vertical: 14.h),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12.r),
        ),
      ),
      child: icon != null
          ? Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 18),
                SizedBox(width: 8),
                Text(label, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15.sp)),
              ],
            )
          : Text(label, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15.sp)),
    );
  }

  Widget _outlineButton({
    required String label,
    required VoidCallback onPressed,
    IconData? icon,
    Color? color,
  }) {
    final c = color ?? AppColors.turquoise;
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        foregroundColor: c,
        side: BorderSide(color: c.withOpacity(0.5)),
        padding: EdgeInsets.symmetric(vertical: 14.h),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12.r),
        ),
      ),
      child: icon != null
          ? Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 18),
                SizedBox(width: 8),
                Text(label, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14.sp)),
              ],
            )
          : Text(label, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14.sp)),
    );
  }

  Widget _textButton({required String label, required VoidCallback onPressed}) {
    return TextButton(
      onPressed: onPressed,
      child: Text(
        label,
        style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 14.sp),
      ),
    );
  }

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

  String _formatHint(num value, bool isMoney) {
    if (isMoney) {
      final intVal = value.round();
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
        TextField(
          controller: controller,
          enabled: enabled,
          keyboardType: isInteger
              ? TextInputType.number
              : TextInputType.numberWithOptions(decimal: true),
          style: TextStyle(
            fontSize: 15.sp,
            fontWeight: FontWeight.w600,
            color: enabled ? Colors.white : Colors.white.withOpacity(0.7),
          ),
          decoration: InputDecoration(
            labelText: label,
            labelStyle: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 13.sp),
            prefixIcon: Icon(
              icon,
              color: isMoney ? AppColors.gold : AppColors.turquoise,
              size: 20,
            ),
            suffixText: isMoney ? 'руб' : null,
            suffixStyle: TextStyle(
              color: AppColors.gold.withOpacity(0.7),
              fontWeight: FontWeight.bold,
              fontSize: 13.sp,
            ),
            suffixIcon: confidence != null
                ? Icon(
                    isConfirmed ? Icons.check_circle : Icons.help_outline,
                    color: isConfirmed ? AppColors.success : AppColors.warning,
                    size: 18,
                  )
                : null,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12.r),
              borderSide: BorderSide(color: Colors.white.withOpacity(0.15)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12.r),
              borderSide: BorderSide(color: Colors.white.withOpacity(0.15)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12.r),
              borderSide: BorderSide(color: AppColors.gold, width: 2),
            ),
            disabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12.r),
              borderSide: BorderSide(color: Colors.white.withOpacity(0.08)),
            ),
            filled: true,
            fillColor: enabled
                ? Colors.white.withOpacity(0.08)
                : Colors.white.withOpacity(0.04),
            isDense: true,
            contentPadding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 14.h),
          ),
        ),
        if (expectedRange != null)
          Padding(
            padding: EdgeInsets.only(left: 12.w, top: 3.h),
            child: Row(
              children: [
                Icon(
                  isInRange == true
                      ? Icons.trending_flat
                      : isInRange == false
                          ? Icons.warning_amber_rounded
                          : Icons.insights,
                  size: 12,
                  color: isInRange == true
                      ? AppColors.success
                      : isInRange == false
                          ? AppColors.warning
                          : Colors.white.withOpacity(0.4),
                ),
                SizedBox(width: 4),
                Flexible(
                  child: Text(
                    'Обычно: ${_formatHint(expectedRange['min'] as num, isMoney)}'
                    ' – ${_formatHint(expectedRange['max'] as num, isMoney)}'
                    '${isMoney ? ' руб' : ''}',
                    style: TextStyle(
                      fontSize: 10.sp,
                      color: isInRange == true
                          ? AppColors.success
                          : isInRange == false
                              ? AppColors.warning
                              : Colors.white.withOpacity(0.4),
                      fontWeight: isInRange != null ? FontWeight.w500 : FontWeight.normal,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// Простой диалог подтверждения: "ИИ определил верно?"
/// Используется на странице обучения Z-Report Training
class ZReportConfirmDialog {
  static String _formatNumber(num value, bool isMoney) {
    if (isMoney) {
      final intVal = value.round();
      final str = intVal.toString();
      final buf = StringBuffer();
      for (int i = 0; i < str.length; i++) {
        if (i > 0 && (str.length - i) % 3 == 0) buf.write(' ');
        buf.write(str[i]);
      }
      return '${buf.toString()} руб';
    }
    return value.toString();
  }

  static Future<bool?> show(
    BuildContext context, {
    required ZReportData data,
    Map<String, dynamic>? expectedRanges,
  }) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.smart_toy, color: AppColors.primaryGreen),
            SizedBox(width: 8),
            Expanded(
              child: Text('ИИ определил:', style: TextStyle(fontSize: 18.sp)),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildRow('Выручка', data.totalSum, 'totalSum', expectedRanges, isMoney: true),
            _buildRow('Наличные', data.cashSum, 'cashSum', expectedRanges, isMoney: true),
            _buildRow('Не передано в ОФД', data.ofdNotSent?.toDouble(), 'ofdNotSent', expectedRanges),
            _buildRow('Ресурс ключей', data.resourceKeys?.toDouble(), 'resourceKeys', expectedRanges),
            SizedBox(height: 16.h),
            Text('Данные верны?', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16.sp)),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Нет', style: TextStyle(color: Colors.red)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.primaryGreen),
            child: Text('Да'),
          ),
        ],
      ),
    );
  }

  static Widget _buildRow(
    String label,
    num? value,
    String fieldKey,
    Map<String, dynamic>? expectedRanges, {
    bool isMoney = false,
  }) {
    final displayValue = value != null ? _formatNumber(value, isMoney) : '—';

    bool? inRange;
    if (value != null && expectedRanges != null) {
      final range = expectedRanges[fieldKey];
      if (range is Map<String, dynamic> && range['min'] != null && range['max'] != null) {
        inRange = value >= (range['min'] as num) && value <= (range['max'] as num);
      }
    }

    return Padding(
      padding: EdgeInsets.symmetric(vertical: 6.h),
      child: Row(
        children: [
          Expanded(
            child: Text(label, style: TextStyle(color: Colors.grey.shade600, fontSize: 14.sp)),
          ),
          if (inRange != null) ...[
            Icon(
              inRange ? Icons.check_circle : Icons.warning_amber,
              color: inRange ? Colors.green : Colors.orange,
              size: 16,
            ),
            SizedBox(width: 4),
          ],
          Text(
            displayValue,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 16.sp,
              color: value != null ? Colors.black87 : Colors.grey,
            ),
          ),
        ],
      ),
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
