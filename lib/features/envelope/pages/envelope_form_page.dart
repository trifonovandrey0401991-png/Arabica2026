import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:io';
import 'package:image_picker/image_picker.dart';
import '../models/envelope_report_model.dart';
import '../models/envelope_question_model.dart';
import '../services/envelope_report_service.dart';
import '../services/envelope_question_service.dart';
import '../widgets/add_expense_dialog.dart';
import '../../suppliers/services/supplier_service.dart';
import '../../suppliers/models/supplier_model.dart';
import '../../ai_training/services/z_report_service.dart';
import '../../ai_training/widgets/z_report_recognition_dialog.dart';
import '../../ai_training/widgets/z_report_region_selector.dart';
import '../../../core/services/media_upload_service.dart';
import '../../../core/utils/logger.dart';
import '../../efficiency/services/points_settings_service.dart';
import '../../../shared/widgets/app_cached_image.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../../core/theme/app_colors.dart';
import '../../ai_training/services/ai_toggle_service.dart';

class EnvelopeFormPage extends StatefulWidget {
  final String employeeName;
  final String shopAddress;

  const EnvelopeFormPage({
    super.key,
    required this.employeeName,
    required this.shopAddress,
  });

  @override
  State<EnvelopeFormPage> createState() => _EnvelopeFormPageState();
}

class _EnvelopeFormPageState extends State<EnvelopeFormPage> {
  final _imagePicker = ImagePicker();

  int _currentStep = 0;
  bool _isLoading = false;
  bool _isSaving = false;
  List<Supplier> _suppliers = [];
  List<EnvelopeQuestion> _questions = [];

  // Проверка временного окна
  bool _isCheckingTime = true;
  bool _isTimeWindowOpen = false;
  String? _nextWindowTime;

  // Данные формы
  String _shiftType = 'morning';

  // ООО
  File? _oooZReportPhoto;
  String? _oooZReportPhotoUrl;
  final _oooRevenueController = TextEditingController();
  final _oooCashController = TextEditingController();
  File? _oooEnvelopePhoto;
  String? _oooEnvelopePhotoUrl;

  // ООО расходы
  final List<ExpenseItem> _oooExpenses = [];

  // ООО - чеки не переданные в ОФД
  final _oooOfdNotSentController = TextEditingController();
  // ООО - ресурс ключей
  final _oooResourceKeysController = TextEditingController();

  // ИП
  File? _ipZReportPhoto;
  String? _ipZReportPhotoUrl;
  final _ipRevenueController = TextEditingController();
  final _ipCashController = TextEditingController();
  final List<ExpenseItem> _expenses = [];
  File? _ipEnvelopePhoto;
  String? _ipEnvelopePhotoUrl;

  // ИП - чеки не переданные в ОФД
  final _ipOfdNotSentController = TextEditingController();
  // ИП - ресурс ключей
  final _ipResourceKeysController = TextEditingController();

  // Регионы полей Z-отчёта (из ZReportRegionSelector)
  Map<String, Map<String, double>>? _oooFieldRegions;
  Map<String, Map<String, double>>? _ipFieldRegions;

  // Флаги ручного исправления Z-отчёта
  bool _oooZReportEdited = false;
  bool _ipZReportEdited = false;

  // Защита от параллельных вызовов OCR
  bool _isOcrInProgress = false;

  @override
  void initState() {
    super.initState();
    _checkTimeWindow();
    _loadData();
  }

  /// Парсинг времени из строки "HH:MM"
  TimeOfDay _parseTime(String timeStr) {
    final parts = timeStr.split(':');
    return TimeOfDay(
      hour: int.parse(parts[0]),
      minute: int.parse(parts[1]),
    );
  }

  /// Проверка находится ли время в диапазоне (с поддержкой перехода через полночь)
  bool _isTimeInRange(TimeOfDay current, TimeOfDay start, TimeOfDay end) {
    final currentMinutes = current.hour * 60 + current.minute;
    final startMinutes = start.hour * 60 + start.minute;
    final endMinutes = end.hour * 60 + end.minute;
    if (startMinutes <= endMinutes) {
      return currentMinutes >= startMinutes && currentMinutes < endMinutes;
    } else {
      return currentMinutes >= startMinutes || currentMinutes < endMinutes;
    }
  }

  /// Проверка временного окна для сдачи конверта
  Future<void> _checkTimeWindow() async {
    try {
      final settings = await PointsSettingsService.getEnvelopePointsSettings();
      final now = TimeOfDay.now();

      final morningStart = _parseTime(settings.morningStartTime);
      final morningEnd = _parseTime(settings.morningEndTime);
      final eveningStart = _parseTime(settings.eveningStartTime);
      final eveningEnd = _parseTime(settings.eveningEndTime);

      bool isOpen = false;
      String? nextWindow;

      if (_isTimeInRange(now, morningStart, morningEnd)) {
        isOpen = true;
      } else if (_isTimeInRange(now, eveningStart, eveningEnd)) {
        isOpen = true;
      } else {
        // Определяем следующее окно
        final currentMinutes = now.hour * 60 + now.minute;
        final morningStartMinutes = morningStart.hour * 60 + morningStart.minute;
        final eveningStartMinutes = eveningStart.hour * 60 + eveningStart.minute;

        if (currentMinutes < morningStartMinutes) {
          nextWindow = '${settings.morningStartTime} - ${settings.morningEndTime}';
        } else if (currentMinutes < eveningStartMinutes) {
          nextWindow = '${settings.eveningStartTime} - ${settings.eveningEndTime}';
        } else {
          nextWindow = '${settings.morningStartTime} - ${settings.morningEndTime} (завтра)';
        }
      }

      if (mounted) {
        setState(() {
          _isCheckingTime = false;
          _isTimeWindowOpen = isOpen;
          _nextWindowTime = nextWindow;
        });
      }
    } catch (e) {
      Logger.error('Ошибка проверки временного окна', e);
      if (mounted) {
        setState(() {
          _isCheckingTime = false;
          _isTimeWindowOpen = true; // В случае ошибки разрешаем доступ
        });
      }
    }
  }

  Future<void> _loadData() async {
    if (mounted) setState(() => _isLoading = true);
    try {
      // Загружаем вопросы и поставщиков параллельно
      final results = await Future.wait([
        EnvelopeQuestionService.getQuestions(),
        SupplierService.getSuppliers(),
      ]);

      if (!mounted) return;
      setState(() {
        _questions = results[0] as List<EnvelopeQuestion>;
        _suppliers = results[1] as List<Supplier>;
      });

      Logger.debug('Загружено ${_questions.length} вопросов конверта');
    } catch (e) {
      Logger.error('Ошибка загрузки данных', e);
    }
    if (mounted) setState(() => _isLoading = false);
  }

  bool get _hasUnsavedData {
    return _currentStep > 0 ||
        _oooRevenueController.text.isNotEmpty ||
        _oooCashController.text.isNotEmpty ||
        _ipRevenueController.text.isNotEmpty ||
        _ipCashController.text.isNotEmpty ||
        _oooZReportPhoto != null ||
        _ipZReportPhoto != null ||
        _oooEnvelopePhoto != null ||
        _ipEnvelopePhoto != null ||
        _oooExpenses.isNotEmpty ||
        _expenses.isNotEmpty;
  }

  Future<bool> _confirmExit() async {
    if (!_hasUnsavedData) return true;
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.emeraldDark,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Выйти из формы?', style: TextStyle(color: Colors.white)),
        content: const Text(
          'Введённые данные будут потеряны.',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Остаться', style: TextStyle(color: AppColors.gold)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Выйти', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  @override
  void dispose() {
    _oooRevenueController.dispose();
    _oooCashController.dispose();
    _oooOfdNotSentController.dispose();
    _oooResourceKeysController.dispose();
    _ipRevenueController.dispose();
    _ipCashController.dispose();
    _ipOfdNotSentController.dispose();
    _ipResourceKeysController.dispose();
    super.dispose();
  }

  /// Получить эталонное фото для текущего шага
  String? _getReferencePhotoForStep(int stepIndex) {
    // Маппинг индекса шага на ID вопроса
    // Шаги: 0-Смена, 1-ООО Z, 2-ООО Выручка, 3-ООО Расходы, 4-ООО Конверт,
    //       5-ИП Z, 6-ИП Выручка, 7-ИП Расходы, 8-ИП Конверт, 9-Итог
    final stepToQuestionId = {
      1: 'envelope_q_2', // ООО: Z-отчет
      4: 'envelope_q_4', // ООО: Фото конверта
      5: 'envelope_q_5', // ИП: Z-отчет
      8: 'envelope_q_8', // ИП: Фото конверта
    };

    final questionId = stepToQuestionId[stepIndex];
    if (questionId == null) return null;

    try {
      final question = _questions.firstWhere((q) => q.id == questionId);
      return question.referencePhotoUrl;
    } catch (e) {
      return null;
    }
  }

  List<String> get _stepTitles => [
    'Выбор смены',         // 0
    'ООО: Z-отчет',        // 1
    'ООО: Выручка и наличные', // 2
    'ООО: Расходы',        // 3
    'ООО: Фото конверта',  // 4
    'ИП: Z-отчет',         // 5
    'ИП: Выручка и наличные', // 6
    'ИП: Расходы',         // 7
    'ИП: Фото конверта',   // 8
    'Итог',                // 9
  ];

  int get _totalSteps => _stepTitles.length;

  double get _progress => (_currentStep + 1) / _totalSteps;

  Future<void> _pickImage(Function(File) onPicked) async {
    try {
      final picked = await _imagePicker.pickImage(
        source: ImageSource.camera,
        maxWidth: 1920,
        maxHeight: 1920,
        imageQuality: 85,
      );
      if (picked != null) {
        onPicked(File(picked.path));
      }
    } catch (e) {
      Logger.error('Ошибка выбора изображения', e);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка камеры: $e')),
        );
      }
    }
  }

  /// Показать индикатор загрузки с текстом
  void _showLoadingDialog(String text) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        content: Row(
          children: [
            SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2.5),
            ),
            SizedBox(width: 16),
            Expanded(
              child: Text(
                text,
                overflow: TextOverflow.ellipsis,
                maxLines: 2,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Заполнить поля формы результатом распознавания
  void _fillFormFields(bool isOoo, ZReportRecognitionResult result) {
    if (!mounted) return;
    setState(() {
      if (isOoo) {
        _oooRevenueController.text = result.revenue.toStringAsFixed(0);
        _oooCashController.text = result.cash.toStringAsFixed(0);
        _oooOfdNotSentController.text = result.ofdNotSent.toString();
        _oooResourceKeysController.text = result.resourceKeys.toString();
      } else {
        _ipRevenueController.text = result.revenue.toStringAsFixed(0);
        _ipCashController.text = result.cash.toStringAsFixed(0);
        _ipOfdNotSentController.text = result.ofdNotSent.toString();
        _ipResourceKeysController.text = result.resourceKeys.toString();
      }
    });
  }

  /// Сфотографировать и распознать Z-отчёт (пошаговый flow)
  Future<void> _pickAndRecognizeZReport({
    required bool isOoo,
    required Function(File) onPhotoPicked,
  }) async {
    // Защита от параллельных вызовов
    if (_isOcrInProgress) return;
    _isOcrInProgress = true;
    try {
      // ШАГ 1: Сделать фото
      final picked = await _imagePicker.pickImage(
        source: ImageSource.camera,
        maxWidth: 1920,
        maxHeight: 1920,
        imageQuality: 85,
      );

      if (picked == null || !mounted) return;

      final file = File(picked.path);
      onPhotoPicked(file);

      // Проверяем переключатель ИИ — если выключен, только фото без OCR
      final aiEnabled = await AiToggleService.isEnabled('zReport');
      if (!aiEnabled) {
        Logger.info('[Z-Report OCR] disabled via toggle - photo only');
        return;
      }

      // ШАГ 2: Сжатие + OCR
      _showLoadingDialog('Распознавание Z-отчёта...');

      final bytes = await file.readAsBytes();
      final compressedBase64 = await ZReportService.compressImage(bytes);
      var lastOcrResult = await ZReportService.parseZReport(
        compressedBase64,
        shopAddress: widget.shopAddress,
      );

      if (mounted) Navigator.of(context).pop(); // закрыть загрузку
      if (!mounted) return;

      // ШАГ 3: Показать единый диалог (1-я попытка)
      var dialogResult = await ZReportRecognitionDialog.show(
        context,
        imageBase64: compressedBase64,
        recognizedData: lastOcrResult.data,
        shopAddress: widget.shopAddress,
        employeeName: widget.employeeName,
        expectedRanges: lastOcrResult.expectedRanges,
      );
      if (dialogResult == null || !mounted) return;

      // ШАГ 4: Если сотрудник нажал "Выделить области"
      if (dialogResult.needsRegionSelection) {
        final regions = await ZReportRegionSelector.show(
          context,
          imageBase64: compressedBase64,
        );
        if (regions == null || !mounted) return;

        // Сохраняем регионы для отчёта
        if (isOoo) {
          _oooFieldRegions = regions;
        } else {
          _ipFieldRegions = regions;
        }

        // ШАГ 5: Повторный OCR с указанными областями
        _showLoadingDialog('Повторное распознавание...');

        lastOcrResult = await ZReportService.parseZReport(
          compressedBase64,
          shopAddress: widget.shopAddress,
          explicitRegions: regions,
        );

        if (mounted) Navigator.of(context).pop(); // закрыть загрузку
        if (!mounted) return;

        final hasData2 = lastOcrResult.success &&
            lastOcrResult.data != null &&
            (lastOcrResult.data!.totalSum != null || lastOcrResult.data!.cashSum != null);

        // ШАГ 6: Показать единый диалог (2-я попытка)
        dialogResult = await ZReportRecognitionDialog.show(
          context,
          imageBase64: compressedBase64,
          recognizedData: hasData2 ? lastOcrResult.data : null,
          shopAddress: widget.shopAddress,
          employeeName: widget.employeeName,
          expectedRanges: lastOcrResult.expectedRanges,
          isSecondAttempt: true,
          secondAttemptFailed: !hasData2,
        );
        if (dialogResult == null || !mounted) return;
      }

      // ШАГ 7: Заполнить форму результатами
      _fillFormFields(isOoo, dialogResult);

      // Сохраняем флаг ручного исправления
      if (dialogResult.wasEdited) {
        if (isOoo) {
          _oooZReportEdited = true;
        } else {
          _ipZReportEdited = true;
        }
      }

      // Сохраняем training sample (rawText + recognizedData для обучения паттернов)
      ZReportService.saveSample(
        imageBase64: compressedBase64,
        totalSum: dialogResult.revenue,
        cashSum: dialogResult.cash,
        ofdNotSent: dialogResult.ofdNotSent,
        resourceKeys: dialogResult.resourceKeys,
        shopAddress: widget.shopAddress,
        employeeName: widget.employeeName,
        fieldRegions: isOoo ? _oooFieldRegions : _ipFieldRegions,
        rawText: lastOcrResult.rawText,
        recognizedData: lastOcrResult.data?.toJson(),
      );
    } catch (e) {
      Logger.error('Ошибка распознавания Z-отчёта', e);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка: $e')),
        );
      }
    } finally {
      _isOcrInProgress = false;
    }
  }

  Future<String?> _uploadPhoto(File photo) async {
    try {
      final url = await MediaUploadService.uploadMedia(photo.path);
      return url;
    } catch (e) {
      Logger.error('Ошибка загрузки фото', e);
      return null;
    }
  }

  void _nextStep() {
    if (_validateCurrentStep()) {
      if (_currentStep < _totalSteps - 1) {
        if (mounted) setState(() => _currentStep++);
      }
    }
  }

  void _prevStep() {
    if (_currentStep > 0) {
      if (mounted) setState(() => _currentStep--);
    }
  }

  bool _validateCurrentStep() {
    switch (_currentStep) {
      case 0: // Выбор смены
        return true;
      case 1: // ООО Z-отчет
        if (_oooZReportPhoto == null && _oooZReportPhotoUrl == null) {
          _showError('Сфотографируйте Z-отчет ООО');
          return false;
        }
        return true;
      case 2: // ООО Выручка
        if (_oooRevenueController.text.isEmpty) {
          _showError('Введите сумму выручки ООО');
          return false;
        }
        if (_oooCashController.text.isEmpty) {
          _showError('Введите сумму наличных ООО');
          return false;
        }
        return true;
      case 3: // ООО Расходы
        return true; // Расходы опциональны
      case 4: // ООО Конверт
        if (_oooEnvelopePhoto == null && _oooEnvelopePhotoUrl == null) {
          _showError('Сфотографируйте конверт ООО');
          return false;
        }
        return true;
      case 5: // ИП Z-отчет
        if (_ipZReportPhoto == null && _ipZReportPhotoUrl == null) {
          _showError('Сфотографируйте Z-отчет ИП');
          return false;
        }
        return true;
      case 6: // ИП Выручка
        if (_ipRevenueController.text.isEmpty) {
          _showError('Введите сумму выручки ИП');
          return false;
        }
        if (_ipCashController.text.isEmpty) {
          _showError('Введите сумму наличных ИП');
          return false;
        }
        return true;
      case 7: // ИП Расходы
        return true; // Расходы опциональны
      case 8: // ИП Конверт
        if (_ipEnvelopePhoto == null && _ipEnvelopePhotoUrl == null) {
          _showError('Сфотографируйте конверт ИП');
          return false;
        }
        return true;
      default:
        return true;
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: TextStyle(color: Colors.white)),
        backgroundColor: Colors.red,
      ),
    );
  }

  double get _oooRevenue => double.tryParse(_oooRevenueController.text) ?? 0;
  double get _oooCash => double.tryParse(_oooCashController.text) ?? 0;
  double get _oooTotalExpenses => _oooExpenses.fold(0.0, (sum, e) => sum + e.amount);
  double get _oooEnvelopeAmount => _oooCash - _oooTotalExpenses;
  double get _ipRevenue => double.tryParse(_ipRevenueController.text) ?? 0;
  double get _ipCash => double.tryParse(_ipCashController.text) ?? 0;
  double get _totalExpenses => _expenses.fold(0.0, (sum, e) => sum + e.amount);
  double get _ipEnvelopeAmount => _ipCash - _totalExpenses;
  double get _totalEnvelopeAmount => _oooEnvelopeAmount + _ipEnvelopeAmount;

  Future<void> _addOooExpense() async {
    // Фильтруем поставщиков - для расходов ООО показываем только поставщиков ООО
    final oooSuppliers = _suppliers.where((s) => s.legalType == 'ООО').toList();

    final result = await showDialog<ExpenseItem>(
      context: context,
      builder: (context) => AddExpenseDialog(suppliers: oooSuppliers),
    );
    if (result != null) {
      if (mounted) setState(() => _oooExpenses.add(result));
    }
  }

  void _removeOooExpense(int index) {
    if (mounted) setState(() => _oooExpenses.removeAt(index));
  }

  Future<void> _addExpense() async {
    // Фильтруем поставщиков - для расходов ИП показываем только поставщиков ИП
    final ipSuppliers = _suppliers.where((s) => s.legalType == 'ИП').toList();

    final result = await showDialog<ExpenseItem>(
      context: context,
      builder: (context) => AddExpenseDialog(suppliers: ipSuppliers),
    );
    if (result != null) {
      if (mounted) setState(() => _expenses.add(result));
    }
  }

  void _removeExpense(int index) {
    if (mounted) setState(() => _expenses.removeAt(index));
  }

  Future<void> _submitReport() async {
    if (_isSaving) return;

    if (mounted) setState(() => _isSaving = true);

    try {
      // Загружаем все фото
      if (_oooZReportPhoto != null) {
        _oooZReportPhotoUrl = await _uploadPhoto(_oooZReportPhoto!);
      }
      if (_oooEnvelopePhoto != null) {
        _oooEnvelopePhotoUrl = await _uploadPhoto(_oooEnvelopePhoto!);
      }
      if (_ipZReportPhoto != null) {
        _ipZReportPhotoUrl = await _uploadPhoto(_ipZReportPhoto!);
      }
      if (_ipEnvelopePhoto != null) {
        _ipEnvelopePhotoUrl = await _uploadPhoto(_ipEnvelopePhoto!);
      }

      final now = DateTime.now();
      final report = EnvelopeReport(
        id: 'envelope_${widget.employeeName.replaceAll(' ', '_')}_${now.millisecondsSinceEpoch}',
        employeeName: widget.employeeName,
        shopAddress: widget.shopAddress,
        shiftType: _shiftType,
        createdAt: now,
        oooZReportPhotoUrl: _oooZReportPhotoUrl,
        oooRevenue: _oooRevenue,
        oooCash: _oooCash,
        oooExpenses: _oooExpenses,
        oooEnvelopePhotoUrl: _oooEnvelopePhotoUrl,
        oooOfdNotSent: int.tryParse(_oooOfdNotSentController.text) ?? 0,
        oooFieldRegions: _oooFieldRegions,
        ipZReportPhotoUrl: _ipZReportPhotoUrl,
        ipRevenue: _ipRevenue,
        ipCash: _ipCash,
        expenses: _expenses,
        ipEnvelopePhotoUrl: _ipEnvelopePhotoUrl,
        ipOfdNotSent: int.tryParse(_ipOfdNotSentController.text) ?? 0,
        ipFieldRegions: _ipFieldRegions,
        oooZReportEdited: _oooZReportEdited,
        ipZReportEdited: _ipZReportEdited,
      );

      final created = await EnvelopeReportService.createReport(report);

      if (created != null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Отчет успешно отправлен!',
              style: TextStyle(color: Colors.white),
            ),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.of(context).pop(true);
        // НЕ вызываем setState после pop — страница уходит из дерева
        return;
      } else {
        _showError('Ошибка отправки отчета');
      }
    } catch (e) {
      Logger.error('Ошибка отправки отчета', e);
      if (mounted) _showError('Ошибка: $e');
    }
    // Сбрасываем _isSaving только если остались на странице
    if (mounted) setState(() => _isSaving = false);
  }

  @override
  Widget build(BuildContext context) {
    // Показываем загрузку пока проверяем время
    if (_isCheckingTime) {
      return Scaffold(
        appBar: AppBar(
          title: Text('Конверт'),
          backgroundColor: AppColors.primaryGreen,
        ),
        body: Center(child: CircularProgressIndicator()),
      );
    }

    // Если временное окно закрыто - показываем сообщение
    if (!_isTimeWindowOpen) {
      return Scaffold(
        appBar: AppBar(
          title: Text('Конверт'),
          backgroundColor: AppColors.primaryGreen,
        ),
        body: Center(
          child: Padding(
            padding: EdgeInsets.all(24.w),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.timer_off, size: 80, color: Colors.orange),
                SizedBox(height: 24),
                Text(
                  'Время вышло',
                  style: TextStyle(
                    fontSize: 24.sp,
                    fontWeight: FontWeight.bold,
                    color: AppColors.primaryGreen,
                  ),
                  textAlign: TextAlign.center,
                ),
                SizedBox(height: 16),
                Text(
                  'Вы можете сдать конверт в:',
                  style: TextStyle(
                    fontSize: 16.sp,
                    color: Colors.grey[700],
                  ),
                  textAlign: TextAlign.center,
                ),
                SizedBox(height: 8),
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 24.w, vertical: 12.h),
                  decoration: BoxDecoration(
                    color: AppColors.primaryGreen.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12.r),
                  ),
                  child: Text(
                    _nextWindowTime ?? 'Следующее окно',
                    style: TextStyle(
                      fontSize: 20.sp,
                      fontWeight: FontWeight.bold,
                      color: AppColors.primaryGreen,
                    ),
                  ),
                ),
                SizedBox(height: 32),
                ElevatedButton.icon(
                  onPressed: () => Navigator.pop(context),
                  icon: Icon(Icons.arrow_back),
                  label: Text('Назад'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primaryGreen,
                    foregroundColor: Colors.white,
                    padding: EdgeInsets.symmetric(horizontal: 32.w, vertical: 16.h),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12.r),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (await _confirmExit()) {
          if (mounted) Navigator.pop(context);
        }
      },
      child: Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [AppColors.emerald, AppColors.emeraldDark, AppColors.night],
            stops: [0.0, 0.3, 1.0],
          ),
        ),
        child: SafeArea(
          child: _isLoading
              ? Center(child: CircularProgressIndicator(color: AppColors.gold))
              : Column(
                  children: [
                    // Header
                    Padding(
                      padding: EdgeInsets.fromLTRB(8.w, 8.h, 16.w, 4.h),
                      child: Row(
                        children: [
                          IconButton(
                            onPressed: () async {
                              if (await _confirmExit()) {
                                if (mounted) Navigator.pop(context);
                              }
                            },
                            icon: Icon(Icons.arrow_back, color: Colors.white),
                          ),
                          Expanded(
                            child: Text(
                              _stepTitles[_currentStep],
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 18.sp,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          SizedBox(width: 48),
                        ],
                      ),
                    ),

                    // Progress bar
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: 16.w),
                      child: Column(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(4.r),
                            child: LinearProgressIndicator(
                              value: _progress,
                              backgroundColor: Colors.white.withOpacity(0.1),
                              valueColor: AlwaysStoppedAnimation<Color>(AppColors.gold),
                              minHeight: 4,
                            ),
                          ),
                          SizedBox(height: 4),
                          Text(
                            'Шаг ${_currentStep + 1} из $_totalSteps',
                            style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 12.sp),
                          ),
                        ],
                      ),
                    ),

                    // Content
                    Expanded(
                      child: SingleChildScrollView(
                        padding: EdgeInsets.all(16.w),
                        child: _buildStepContent(),
                      ),
                    ),

                    // Navigation buttons
                    _buildNavigationButtons(),
                  ],
                ),
        ),
      ),
    ),
    );
  }

  Widget _buildStepContent() {
    switch (_currentStep) {
      case 0:
        return _buildShiftTypeStep();
      case 1:
        return _buildZReportPhotoStep(
          title: 'Сфотографируйте Z-отчет ООО',
          photo: _oooZReportPhoto,
          photoUrl: _oooZReportPhotoUrl,
          isOoo: true,
          onPick: (file) => setState(() => _oooZReportPhoto = file),
          referencePhotoUrl: _getReferencePhotoForStep(1),
        );
      case 2:
        return _buildRevenueStep(
          title: 'ООО',
          revenueController: _oooRevenueController,
          cashController: _oooCashController,
          ofdNotSentController: _oooOfdNotSentController,
          resourceKeysController: _oooResourceKeysController,
        );
      case 3:
        return _buildOooExpensesStep();
      case 4:
        return _buildPhotoStep(
          title: 'Сфотографируйте сформированный конверт ООО',
          photo: _oooEnvelopePhoto,
          photoUrl: _oooEnvelopePhotoUrl,
          onPick: (file) => setState(() => _oooEnvelopePhoto = file),
          referencePhotoUrl: _getReferencePhotoForStep(4),
        );
      case 5:
        return _buildZReportPhotoStep(
          title: 'Сфотографируйте Z-отчет ИП',
          photo: _ipZReportPhoto,
          photoUrl: _ipZReportPhotoUrl,
          isOoo: false,
          onPick: (file) => setState(() => _ipZReportPhoto = file),
          referencePhotoUrl: _getReferencePhotoForStep(5),
        );
      case 6:
        return _buildRevenueStep(
          title: 'ИП',
          revenueController: _ipRevenueController,
          cashController: _ipCashController,
          ofdNotSentController: _ipOfdNotSentController,
          resourceKeysController: _ipResourceKeysController,
        );
      case 7:
        return _buildExpensesStep();
      case 8:
        return _buildPhotoStep(
          title: 'Сфотографируйте сформированный конверт ИП',
          photo: _ipEnvelopePhoto,
          photoUrl: _ipEnvelopePhotoUrl,
          onPick: (file) => setState(() => _ipEnvelopePhoto = file),
          referencePhotoUrl: _getReferencePhotoForStep(8),
        );
      case 9:
        return _buildSummaryStep();
      default:
        return SizedBox();
    }
  }

  Widget _buildShiftTypeStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Заголовок с иконкой
        Container(
          padding: EdgeInsets.all(20.w),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [Colors.teal.shade50, Colors.cyan.shade50],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(16.r),
            border: Border.all(color: Colors.teal.shade100),
          ),
          child: Row(
            children: [
              Container(
                padding: EdgeInsets.all(12.w),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Colors.teal.shade400, Colors.cyan.shade400],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(12.r),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.teal.withOpacity(0.3),
                      blurRadius: 8,
                      offset: Offset(0, 2),
                    ),
                  ],
                ),
                child: Icon(
                  Icons.schedule,
                  color: Colors.white,
                  size: 28,
                ),
              ),
              SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Выберите смену',
                      style: TextStyle(
                        fontSize: 20.sp,
                        fontWeight: FontWeight.bold,
                        color: Colors.grey.shade800,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Укажите какую смену вы сдаёте',
                      style: TextStyle(
                        fontSize: 14.sp,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        SizedBox(height: 32),

        // Утренняя смена
        _buildShiftOption(
          value: 'morning',
          label: 'Утренняя смена',
          subtitle: '00:00 — 14:00',
          icon: Icons.wb_sunny_rounded,
          gradient: [Color(0xFFFF9800), Color(0xFFFFB74D)],
          lightColor: Colors.orange.shade50,
        ),
        SizedBox(height: 16),

        // Вечерняя смена
        _buildShiftOption(
          value: 'evening',
          label: 'Вечерняя смена',
          subtitle: '14:00 — 00:00',
          icon: Icons.nights_stay_rounded,
          gradient: [Color(0xFF3F51B5), Color(0xFF7986CB)],
          lightColor: Colors.indigo.shade50,
        ),
      ],
    );
  }

  Widget _buildShiftOption({
    required String value,
    required String label,
    required String subtitle,
    required IconData icon,
    required List<Color> gradient,
    required Color lightColor,
  }) {
    final isSelected = _shiftType == value;

    return GestureDetector(
      onTap: () => setState(() => _shiftType = value),
      child: AnimatedContainer(
        duration: Duration(milliseconds: 200),
        curve: Curves.easeInOut,
        padding: EdgeInsets.all(20.w),
        decoration: BoxDecoration(
          color: isSelected ? lightColor : Colors.white,
          border: Border.all(
            color: isSelected ? gradient[0] : Colors.grey.shade200,
            width: isSelected ? 2.5 : 1,
          ),
          borderRadius: BorderRadius.circular(20.r),
          boxShadow: [
            BoxShadow(
              color: isSelected
                  ? gradient[0].withOpacity(0.25)
                  : Colors.black.withOpacity(0.06),
              blurRadius: isSelected ? 16 : 8,
              offset: Offset(0, isSelected ? 6 : 2),
            ),
          ],
        ),
        child: Row(
          children: [
            // Иконка с градиентом
            AnimatedContainer(
              duration: Duration(milliseconds: 200),
              padding: EdgeInsets.all(16.w),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: isSelected
                      ? gradient
                      : [Colors.grey.shade200, Colors.grey.shade300],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(16.r),
                boxShadow: isSelected
                    ? [
                        BoxShadow(
                          color: gradient[0].withOpacity(0.4),
                          blurRadius: 12,
                          offset: Offset(0, 4),
                        ),
                      ]
                    : null,
              ),
              child: Icon(
                icon,
                color: isSelected ? Colors.white : Colors.grey.shade500,
                size: 36,
              ),
            ),
            SizedBox(width: 20),

            // Текст
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 18.sp,
                      fontWeight: FontWeight.bold,
                      color: isSelected ? gradient[0] : Colors.grey.shade700,
                    ),
                  ),
                  SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(
                        Icons.access_time,
                        size: 14,
                        color: isSelected ? gradient[0].withOpacity(0.7) : Colors.grey.shade400,
                      ),
                      SizedBox(width: 4),
                      Text(
                        subtitle,
                        style: TextStyle(
                          fontSize: 14.sp,
                          color: isSelected ? gradient[0].withOpacity(0.7) : Colors.grey.shade500,
                          fontWeight: isSelected ? FontWeight.w500 : FontWeight.normal,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // Чекбокс
            AnimatedContainer(
              duration: Duration(milliseconds: 200),
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                gradient: isSelected
                    ? LinearGradient(colors: gradient)
                    : null,
                color: isSelected ? null : Colors.grey.shade100,
                borderRadius: BorderRadius.circular(14.r),
                border: Border.all(
                  color: isSelected ? Colors.transparent : Colors.grey.shade300,
                  width: 2,
                ),
                boxShadow: isSelected
                    ? [
                        BoxShadow(
                          color: gradient[0].withOpacity(0.3),
                          blurRadius: 8,
                          offset: Offset(0, 2),
                        ),
                      ]
                    : null,
              ),
              child: isSelected
                  ? Icon(
                      Icons.check,
                      color: Colors.white,
                      size: 18,
                    )
                  : null,
            ),
          ],
        ),
      ),
    );
  }

  /// Шаг с фото Z-отчёта (с распознаванием)
  Widget _buildZReportPhotoStep({
    required String title,
    required File? photo,
    required String? photoUrl,
    required bool isOoo,
    required Function(File) onPick,
    String? referencePhotoUrl,
  }) {
    final hasPhoto = photo != null || photoUrl != null;
    final typeColor = isOoo ? Color(0xFF1976D2) : Color(0xFFE65100);
    final hasReference = referencePhotoUrl != null && referencePhotoUrl.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Компактный заголовок
        Row(
          children: [
            Container(
              padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 5.h),
              decoration: BoxDecoration(
                color: typeColor,
                borderRadius: BorderRadius.circular(8.r),
              ),
              child: Text(
                isOoo ? 'ООО' : 'ИП',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 12.sp,
                ),
              ),
            ),
            SizedBox(width: 10),
            Text(
              'Z-отчёт',
              style: TextStyle(
                fontSize: 16.sp,
                fontWeight: FontWeight.bold,
                color: Colors.grey.shade800,
              ),
            ),
            Spacer(),
            Container(
              padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 4.h),
              decoration: BoxDecoration(
                color: Color(0xFF00C853).withOpacity(0.15),
                borderRadius: BorderRadius.circular(8.r),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.auto_awesome, color: Color(0xFF00C853), size: 12),
                  SizedBox(width: 3),
                  Text('ИИ', style: TextStyle(fontSize: 11.sp, fontWeight: FontWeight.bold, color: Color(0xFF00C853))),
                ],
              ),
            ),
          ],
        ),
        SizedBox(height: 12),

        // Область фото - фиксированная высота 420
        GestureDetector(
          onTap: () => _pickAndRecognizeZReport(isOoo: isOoo, onPhotoPicked: onPick),
          child: Container(
            height: 420,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16.r),
              border: Border.all(
                color: hasPhoto ? Colors.green.shade400 : typeColor.withOpacity(0.3),
                width: hasPhoto ? 2 : 1,
              ),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(14.r),
              child: hasPhoto
                  ? Stack(
                      fit: StackFit.expand,
                      children: [
                        photo != null
                            ? Image.file(photo, fit: BoxFit.cover)
                            : AppCachedImage(imageUrl: photoUrl!, fit: BoxFit.cover),
                        // Бейдж
                        Positioned(
                          top: 8.h,
                          left: 8.w,
                          child: Container(
                            padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 4.h),
                            decoration: BoxDecoration(
                              color: Colors.green,
                              borderRadius: BorderRadius.circular(8.r),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.check, color: Colors.white, size: 12),
                                SizedBox(width: 4),
                                Text('Готово', style: TextStyle(color: Colors.white, fontSize: 11.sp, fontWeight: FontWeight.w600)),
                              ],
                            ),
                          ),
                        ),
                      ],
                    )
                  : hasReference
                      ? Stack(
                          fit: StackFit.expand,
                          children: [
                            AppCachedImage(
                              imageUrl: referencePhotoUrl,
                              fit: BoxFit.contain,
                              errorWidget: (context, error, stack) => Center(
                                child: Icon(Icons.broken_image, size: 48, color: Colors.grey[400]),
                              ),
                            ),
                            // Бейдж образец
                            Positioned(
                              top: 8.h,
                              left: 8.w,
                              child: Container(
                                padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 4.h),
                                decoration: BoxDecoration(
                                  color: Colors.blue.shade600,
                                  borderRadius: BorderRadius.circular(8.r),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.photo_library, color: Colors.white, size: 12),
                                    SizedBox(width: 4),
                                    Text('Образец', style: TextStyle(color: Colors.white, fontSize: 11.sp, fontWeight: FontWeight.w600)),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        )
                      : Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.add_a_photo_rounded, size: 56, color: typeColor.withOpacity(0.6)),
                            SizedBox(height: 12),
                            Text('Нажмите для фото', style: TextStyle(fontSize: 14.sp, color: Colors.grey.shade500)),
                          ],
                        ),
            ),
          ),
        ),
        SizedBox(height: 12),

        // Кнопка
        GestureDetector(
          onTap: () => _pickAndRecognizeZReport(isOoo: isOoo, onPhotoPicked: onPick),
          child: Container(
            padding: EdgeInsets.symmetric(vertical: 14.h),
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [typeColor, typeColor.withOpacity(0.85)]),
              borderRadius: BorderRadius.circular(12.r),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(hasPhoto ? Icons.refresh : Icons.camera_alt, color: Colors.white, size: 18),
                SizedBox(width: 8),
                Text(
                  hasPhoto ? 'Переснять' : 'Сфотографировать',
                  style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.w600, color: Colors.white),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPhotoStep({
    required String title,
    required File? photo,
    required String? photoUrl,
    required Function(File) onPick,
    String? referencePhotoUrl,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          title,
          style: TextStyle(fontSize: 18.sp, fontWeight: FontWeight.bold),
          textAlign: TextAlign.center,
        ),
        SizedBox(height: 16),

        // Эталонное фото (если есть)
        if (referencePhotoUrl != null && referencePhotoUrl.isNotEmpty) ...[
          Container(
            padding: EdgeInsets.all(12.w),
            decoration: BoxDecoration(
              color: Colors.blue[50],
              borderRadius: BorderRadius.circular(12.r),
              border: Border.all(color: Colors.blue[200]!),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.info_outline, color: Colors.blue[700], size: 20),
                    SizedBox(width: 8),
                    Text(
                      'Образец фото:',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.blue[700],
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(8.r),
                  child: AppCachedImage(
                    imageUrl: referencePhotoUrl,
                    height: 150,
                    width: double.infinity,
                    fit: BoxFit.cover,
                    errorWidget: (context, error, stack) {
                      return Container(
                        height: 80,
                        color: Colors.grey[200],
                        child: Center(
                          child: Text(
                            'Не удалось загрузить образец',
                            style: TextStyle(color: Colors.grey[600]),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
          SizedBox(height: 16),
        ],

        // Ваше фото
        if (photo != null || photoUrl != null) ...[
          Text(
            'Ваше фото:',
            style: TextStyle(
              fontWeight: FontWeight.w500,
              color: Colors.grey[700],
            ),
          ),
          SizedBox(height: 8),
        ],

        if (photo != null)
          ClipRRect(
            borderRadius: BorderRadius.circular(12.r),
            child: Image.file(photo, height: 300, fit: BoxFit.cover),
          )
        else if (photoUrl != null)
          ClipRRect(
            borderRadius: BorderRadius.circular(12.r),
            child: AppCachedImage(imageUrl: photoUrl, height: 300, fit: BoxFit.cover),
          )
        else
          Container(
            height: 200,
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey[300]!),
              borderRadius: BorderRadius.circular(12.r),
            ),
            child: Center(
              child: Icon(Icons.camera_alt, size: 64, color: Colors.grey),
            ),
          ),
        SizedBox(height: 16),
        ElevatedButton.icon(
          onPressed: () => _pickImage(onPick),
          icon: Icon(Icons.camera_alt),
          label: Text(photo != null ? 'Переснять' : 'Сделать фото'),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primaryGreen,
            foregroundColor: Colors.white,
            padding: EdgeInsets.symmetric(vertical: 16.h),
          ),
        ),
      ],
    );
  }

  Widget _buildRevenueStep({
    required String title,
    required TextEditingController revenueController,
    required TextEditingController cashController,
    required TextEditingController ofdNotSentController,
    required TextEditingController resourceKeysController,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Заголовок с градиентом
        Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [Colors.teal.shade50, Colors.blue.shade50],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(12.r),
            border: Border.all(color: Colors.teal.shade200, width: 1),
          ),
          padding: EdgeInsets.all(14.w),
          child: Row(
            children: [
              Container(
                padding: EdgeInsets.all(8.w),
                decoration: BoxDecoration(
                  color: Colors.teal.shade100,
                  borderRadius: BorderRadius.circular(8.r),
                ),
                child: Icon(Icons.edit_note, color: Colors.teal.shade700, size: 24),
              ),
              SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Введите данные $title:',
                  style: TextStyle(
                    fontSize: 16.sp,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        ),
        SizedBox(height: 20),

        // Поля ввода
        _buildEnvelopeTextField(
          revenueController,
          'Сумма выручки *',
          Icons.currency_ruble,
          true,
        ),
        SizedBox(height: 12),
        _buildEnvelopeTextField(
          cashController,
          'Сумма наличных *',
          Icons.payments_outlined,
          true,
        ),
        SizedBox(height: 12),
        _buildEnvelopeTextField(
          ofdNotSentController,
          'Не передано в ОФД',
          Icons.cloud_off,
          false,
        ),
        SizedBox(height: 12),
        _buildEnvelopeTextField(
          resourceKeysController,
          'Ресурс ключей',
          Icons.key,
          false,
        ),
      ],
    );
  }

  Widget _buildOooExpensesStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Итоги ООО
        Card(
          color: Colors.white.withOpacity(0.06),
          child: Padding(
            padding: EdgeInsets.all(16.w),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildSummaryRow('Выручка ООО:', _oooRevenue),
                _buildSummaryRow('Наличные ООО:', _oooCash),
                Divider(color: Colors.white.withOpacity(0.15)),
                if (_oooExpenses.isNotEmpty) ...[
                  Text(
                    'Расходы:',
                    style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
                  ),
                  SizedBox(height: 8),
                  ..._oooExpenses.asMap().entries.map((entry) {
                    final index = entry.key;
                    final expense = entry.value;
                    return Padding(
                      padding: EdgeInsets.symmetric(vertical: 4.h),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text('  ${expense.supplierName}', style: TextStyle(color: Colors.white.withOpacity(0.7))),
                          ),
                          Text(
                            '${expense.amount.toStringAsFixed(0)} руб',
                            style: TextStyle(color: Colors.red[300]),
                          ),
                          IconButton(
                            icon: Icon(Icons.close, size: 20, color: Colors.white.withOpacity(0.5)),
                            onPressed: () => _removeOooExpense(index),
                            padding: EdgeInsets.zero,
                            constraints: BoxConstraints(),
                          ),
                        ],
                      ),
                    );
                  }),
                  Divider(color: Colors.white.withOpacity(0.15)),
                  _buildSummaryRow('Итого расходов:', _oooTotalExpenses, isRed: true),
                ],
                Divider(color: Colors.white.withOpacity(0.15)),
                _buildSummaryRow(
                  'Итого в конверте ООО:',
                  _oooEnvelopeAmount,
                  isBold: true,
                  isGreen: true,
                ),
              ],
            ),
          ),
        ),
        SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: _addOooExpense,
            icon: Icon(Icons.add),
            label: Text('Добавить расход'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primaryGreen,
              foregroundColor: Colors.white,
              padding: EdgeInsets.symmetric(vertical: 16.h),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildExpensesStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Итоги
        Card(
          color: Colors.white.withOpacity(0.06),
          child: Padding(
            padding: EdgeInsets.all(16.w),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildSummaryRow('Выручка ИП:', _ipRevenue),
                _buildSummaryRow('Наличные ИП:', _ipCash),
                Divider(color: Colors.white.withOpacity(0.15)),
                if (_expenses.isNotEmpty) ...[
                  Text(
                    'Расходы:',
                    style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
                  ),
                  SizedBox(height: 8),
                  ..._expenses.asMap().entries.map((entry) {
                    final index = entry.key;
                    final expense = entry.value;
                    return Padding(
                      padding: EdgeInsets.symmetric(vertical: 4.h),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text('  ${expense.supplierName}', style: TextStyle(color: Colors.white.withOpacity(0.7))),
                          ),
                          Text(
                            '${expense.amount.toStringAsFixed(0)} руб',
                            style: TextStyle(color: Colors.red[300]),
                          ),
                          IconButton(
                            icon: Icon(Icons.close, size: 20, color: Colors.white.withOpacity(0.5)),
                            onPressed: () => _removeExpense(index),
                            padding: EdgeInsets.zero,
                            constraints: BoxConstraints(),
                          ),
                        ],
                      ),
                    );
                  }),
                  Divider(color: Colors.white.withOpacity(0.15)),
                  _buildSummaryRow('Итого расходов:', _totalExpenses, isRed: true),
                ],
                Divider(color: Colors.white.withOpacity(0.15)),
                _buildSummaryRow(
                  'Итого в конверте ИП:',
                  _ipEnvelopeAmount,
                  isBold: true,
                  isGreen: true,
                ),
              ],
            ),
          ),
        ),
        SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: _addExpense,
            icon: Icon(Icons.add),
            label: Text('Добавить расход'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primaryGreen,
              foregroundColor: Colors.white,
              padding: EdgeInsets.symmetric(vertical: 16.h),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSummaryRow(
    String label,
    double value, {
    bool isBold = false,
    bool isRed = false,
    bool isGreen = false,
  }) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 4.h),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Flexible(
            child: Text(
              label,
              style: TextStyle(
                fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
                color: Colors.white.withOpacity(isBold ? 1.0 : 0.7),
                fontSize: 14.sp,
              ),
            ),
          ),
          Text(
            '${value.toStringAsFixed(0)} руб',
            style: TextStyle(
              fontWeight: isBold ? FontWeight.bold : FontWeight.w500,
              fontSize: isBold ? 16.sp : 14.sp,
              color: isRed
                  ? Colors.red[300]
                  : (isGreen ? Colors.green[400] : Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEnvelopeTextField(
    TextEditingController controller,
    String label,
    IconData icon,
    bool isMoney,
  ) {
    return Container(
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
      child: TextFormField(
        controller: controller,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.w500),
        decoration: InputDecoration(
          hintText: label,
          hintStyle: TextStyle(color: Colors.grey.shade400),
          prefixIcon: Icon(
            icon,
            color: isMoney ? Colors.teal.shade700 : Colors.blueGrey.shade700,
          ),
          suffixText: isMoney ? 'руб' : null,
          suffixStyle: TextStyle(
            color: Colors.teal.shade700,
            fontWeight: FontWeight.bold,
            fontSize: 16.sp,
          ),
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
          filled: true,
          fillColor: Colors.white,
          contentPadding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 16.h),
        ),
        onChanged: (_) => setState(() {}),
      ),
    );
  }

  Widget _buildSummaryStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Заголовок
        Text(
          'Итоговый отчёт',
          style: TextStyle(
            fontSize: 20.sp,
            fontWeight: FontWeight.bold,
            color: AppColors.gold,
          ),
        ),
        SizedBox(height: 6),
        Text(
          widget.shopAddress,
          style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 13.sp),
        ),
        Text(
          '${_shiftType == 'morning' ? 'Утренняя' : 'Вечерняя'} смена',
          style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 13.sp),
        ),
        SizedBox(height: 20),

        // ООО секция
        Container(
          padding: EdgeInsets.all(16.w),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.06),
            borderRadius: BorderRadius.circular(14.r),
            border: Border.all(color: Colors.blue.withOpacity(0.3)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.business, color: Colors.blue[300], size: 20),
                  SizedBox(width: 8),
                  Text(
                    'ООО',
                    style: TextStyle(
                      fontSize: 17.sp,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
              Divider(color: Colors.white.withOpacity(0.15), height: 20),
              _buildSummaryRow('Выручка:', _oooRevenue),
              _buildSummaryRow('Наличные:', _oooCash),
              if (_oooExpenses.isNotEmpty) ...[
                SizedBox(height: 8),
                Text(
                  'Расходы:',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.white.withOpacity(0.8),
                    fontSize: 14.sp,
                  ),
                ),
                ..._oooExpenses.map((e) => Padding(
                  padding: EdgeInsets.only(left: 8.w, top: 4.h),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Flexible(
                        child: Text(
                          '- ${e.supplierName}',
                          style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 13.sp),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Text(
                        '-${e.amount.toStringAsFixed(0)} руб',
                        style: TextStyle(color: Colors.red[300], fontSize: 13.sp),
                      ),
                    ],
                  ),
                )),
              ],
              Divider(color: Colors.white.withOpacity(0.15), height: 20),
              _buildSummaryRow('В конверте:', _oooEnvelopeAmount, isBold: true, isGreen: true),
            ],
          ),
        ),
        SizedBox(height: 14),

        // ИП секция
        Container(
          padding: EdgeInsets.all(16.w),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.06),
            borderRadius: BorderRadius.circular(14.r),
            border: Border.all(color: Colors.orange.withOpacity(0.3)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.person, color: Colors.orange[300], size: 20),
                  SizedBox(width: 8),
                  Text(
                    'ИП',
                    style: TextStyle(
                      fontSize: 17.sp,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
              Divider(color: Colors.white.withOpacity(0.15), height: 20),
              _buildSummaryRow('Выручка:', _ipRevenue),
              _buildSummaryRow('Наличные:', _ipCash),
              if (_expenses.isNotEmpty) ...[
                SizedBox(height: 8),
                Text(
                  'Расходы:',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.white.withOpacity(0.8),
                    fontSize: 14.sp,
                  ),
                ),
                ..._expenses.map((e) => Padding(
                  padding: EdgeInsets.only(left: 8.w, top: 4.h),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Flexible(
                        child: Text(
                          '- ${e.supplierName}',
                          style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 13.sp),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Text(
                        '-${e.amount.toStringAsFixed(0)} руб',
                        style: TextStyle(color: Colors.red[300], fontSize: 13.sp),
                      ),
                    ],
                  ),
                )),
              ],
              Divider(color: Colors.white.withOpacity(0.15), height: 20),
              _buildSummaryRow('В конверте:', _ipEnvelopeAmount, isBold: true, isGreen: true),
            ],
          ),
        ),
        SizedBox(height: 14),

        // Итого
        Container(
          width: double.infinity,
          padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 14.h),
          decoration: BoxDecoration(
            color: AppColors.gold.withOpacity(0.15),
            borderRadius: BorderRadius.circular(14.r),
            border: Border.all(color: AppColors.gold.withOpacity(0.4)),
          ),
          child: Column(
            children: [
              Text(
                'ИТОГО В КОНВЕРТАХ',
                style: TextStyle(
                  fontSize: 13.sp,
                  fontWeight: FontWeight.w600,
                  color: AppColors.gold.withOpacity(0.8),
                  letterSpacing: 1,
                ),
              ),
              SizedBox(height: 4),
              Text(
                '${_totalEnvelopeAmount.toStringAsFixed(0)} руб',
                style: TextStyle(
                  fontSize: 28.sp,
                  fontWeight: FontWeight.bold,
                  color: AppColors.gold,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildNavigationButtons() {
    final isLastStep = _currentStep == _totalSteps - 1;

    return Container(
      padding: EdgeInsets.all(16.w),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.3),
        border: Border(top: BorderSide(color: Colors.white.withOpacity(0.1))),
      ),
      child: Row(
        children: [
          if (_currentStep > 0)
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _prevStep,
                icon: Icon(Icons.arrow_back, color: Colors.white, size: 18),
                label: Text('Назад', style: TextStyle(color: Colors.white)),
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: Colors.white.withOpacity(0.3)),
                  padding: EdgeInsets.symmetric(vertical: 14.h),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.r)),
                ),
              ),
            ),
          if (_currentStep > 0) SizedBox(width: 12),
          Expanded(
            flex: 2,
            child: ElevatedButton.icon(
              onPressed: isLastStep
                  ? (_isSaving ? null : _submitReport)
                  : _nextStep,
              icon: _isSaving
                  ? SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : Icon(
                      isLastStep ? Icons.check : Icons.arrow_forward,
                      color: Colors.white,
                      size: 18,
                    ),
              label: Text(
                isLastStep
                    ? (_isSaving ? 'Отправка...' : 'Отправить')
                    : 'Далее',
                style: TextStyle(color: Colors.white, fontSize: 16.sp, fontWeight: FontWeight.w600),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: isLastStep ? AppColors.gold : AppColors.emerald,
                padding: EdgeInsets.symmetric(vertical: 14.h),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.r)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
