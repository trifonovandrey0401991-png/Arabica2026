import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import '../models/coffee_machine_template_model.dart';
import '../models/coffee_machine_report_model.dart';
import '../services/coffee_machine_template_service.dart';
import '../services/coffee_machine_report_service.dart';
import '../services/coffee_machine_ocr_service.dart';
import '../widgets/counter_region_selector.dart';
import '../../../core/services/media_upload_service.dart';
import '../../../core/theme/app_colors.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

/// Форма сдачи показаний счётчиков кофемашин
class CoffeeMachineFormPage extends StatefulWidget {
  final String employeeName;
  final String shopAddress;

  const CoffeeMachineFormPage({
    super.key,
    required this.employeeName,
    required this.shopAddress,
  });

  @override
  State<CoffeeMachineFormPage> createState() => _CoffeeMachineFormPageState();
}

class _CoffeeMachineFormPageState extends State<CoffeeMachineFormPage> {
  final _imagePicker = ImagePicker();

  bool _isLoading = true;
  bool _isSaving = false;
  String? _error;

  // Шаблоны машин для этого магазина
  List<CoffeeMachineTemplate> _machineTemplates = [];

  // Данные по каждой машине: templateId -> {photo, aiNumber, confirmedNumber, wasEdited}
  final Map<String, File?> _machinePhotos = {};
  final Map<String, int?> _machineAiNumbers = {};
  final Map<String, TextEditingController> _machineControllers = {};
  final Map<String, bool> _machineWasEdited = {};
  final Map<String, Map<String, double>?> _machineSelectedRegions = {};
  final Map<String, String> _machineBase64 = {}; // base64 фото для повторного OCR

  // Шаблон и данные компьютера
  CoffeeMachineTemplate? _computerTemplate;
  File? _computerPhoto;
  int? _computerAiNumber;
  final _computerController = TextEditingController();
  String? _computerBase64;

  // Текущий шаг
  int _currentStep = 0;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    for (final c in _machineControllers.values) {
      c.dispose();
    }
    _computerController.dispose();
    super.dispose();
  }

  int get _totalSteps => _machineTemplates.length + 2; // машины + компьютер + итоги

  Future<void> _loadData() async {
    try {
      // Загрузить конфиг магазина
      final config = await CoffeeMachineTemplateService.getShopConfig(widget.shopAddress);
      if (config == null || config.machineTemplateIds.isEmpty) {
        if (!mounted) return;
        setState(() {
          _isLoading = false;
          _error = 'Для этого магазина не настроены кофемашины';
        });
        return;
      }

      // Загрузить шаблоны
      final allTemplates = await CoffeeMachineTemplateService.getTemplates();
      final templates = allTemplates.where(
        (t) => config.machineTemplateIds.contains(t.id),
      ).toList();

      if (templates.isEmpty) {
        if (!mounted) return;
        setState(() {
          _isLoading = false;
          _error = 'Шаблоны кофемашин не найдены';
        });
        return;
      }

      // Загрузить шаблон компьютера (если привязан)
      CoffeeMachineTemplate? computerTmpl;
      if (config.computerTemplateId != null) {
        computerTmpl = allTemplates.cast<CoffeeMachineTemplate?>().firstWhere(
          (t) => t!.id == config.computerTemplateId,
          orElse: () => null,
        );
      }

      // Инициализировать контроллеры
      for (final t in templates) {
        _machineControllers[t.id] = TextEditingController();
      }

      if (!mounted) return;
      setState(() {
        _machineTemplates = templates;
        _computerTemplate = computerTmpl;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _error = 'Ошибка загрузки: $e';
      });
    }
  }

  Future<void> _pickAndRecognize(String templateId, {bool isComputer = false}) async {
    final picked = await _imagePicker.pickImage(
      source: ImageSource.camera,
      maxWidth: 1920,
      maxHeight: 1920,
      imageQuality: 85,
    );

    if (picked == null) return;

    final file = File(picked.path);
    final bytes = await file.readAsBytes();
    final base64Image = base64Encode(bytes);

    if (!mounted) return;
    setState(() {
      if (isComputer) {
        _computerPhoto = file;
        _computerBase64 = base64Image;
      } else {
        _machinePhotos[templateId] = file;
        _machineBase64[templateId] = base64Image;
      }
    });

    // Первый вызов OCR
    final result = await _callOcr(
      base64Image: base64Image,
      templateId: templateId,
      isComputer: isComputer,
    );

    if (result == null) return; // диалог загрузки был закрыт (unmounted)

    if (!mounted) return;
    setState(() {
      if (isComputer) {
        _computerAiNumber = result.number;
      } else {
        _machineAiNumbers[templateId] = result.number;
      }
    });

    if (result.success && result.number != null) {
      // Показать интерактивный диалог: "Верно?" / "Неверно?"
      _showInteractiveOcrDialog(
        number: result.number!,
        templateId: templateId,
        isComputer: isComputer,
      );
    } else {
      // OCR не смог распознать — предложить выделить область или ввести вручную
      _showOcrFailedDialog(templateId: templateId, isComputer: isComputer);
    }
  }

  /// Вызов OCR с показом loading-диалога
  Future<OcrResult?> _callOcr({
    required String base64Image,
    required String templateId,
    required bool isComputer,
    Map<String, double>? userRegion,
  }) async {
    if (!mounted) return null;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => Center(
        child: Card(
          child: Padding(
            padding: EdgeInsets.all(24.w),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(color: AppColors.emerald),
                SizedBox(height: 16),
                Text('Распознавание числа...'),
              ],
            ),
          ),
        ),
      ),
    );

    // Найти шаблон (машины или компьютера)
    CoffeeMachineTemplate? machineTemplate;
    if (isComputer) {
      machineTemplate = _computerTemplate; // может быть null — тогда fallback на хардкод
    } else {
      final matches = _machineTemplates.where((t) => t.id == templateId);
      if (matches.isEmpty) {
        if (mounted) Navigator.of(context).pop();
        return null;
      }
      machineTemplate = matches.first;
    }

    // Определить region: пользовательский или из шаблона
    Map<String, double>? region = userRegion;
    final counterRegion = machineTemplate?.counterRegion;
    if (region == null && counterRegion != null) {
      region = {
        'x': counterRegion.x,
        'y': counterRegion.y,
        'width': counterRegion.width,
        'height': counterRegion.height,
      };
    }

    // Пресет OCR: из шаблона или fallback 'computer'
    final String? preset = machineTemplate?.ocrPreset ?? (isComputer ? 'computer' : 'standard');

    // Имя машины для поиска обученного region на сервере
    final String? machineNameForTraining = machineTemplate?.name;

    final result = await CoffeeMachineOcrService.recognizeNumber(
      imageBase64: base64Image,
      region: region,
      preset: preset,
      machineName: machineNameForTraining,
    );

    if (!mounted) return null;
    Navigator.of(context).pop(); // Закрыть loading

    return result;
  }

  /// Интерактивный диалог: ИИ распознал X — "Верно?" / "Неверно?"
  void _showInteractiveOcrDialog({
    required int number,
    required String templateId,
    required bool isComputer,
    bool isRetry = false,
  }) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: Color(0xFF1A2E2E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16.r)),
        title: Row(
          children: [
            Icon(Icons.smart_toy, color: AppColors.gold, size: 24),
            SizedBox(width: 8),
            Text(
              isRetry ? 'Повторное распознавание' : 'Результат распознавания',
              style: TextStyle(color: Colors.white, fontSize: 16.sp),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: EdgeInsets.symmetric(vertical: 16.h, horizontal: 24.w),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.08),
                borderRadius: BorderRadius.circular(12.r),
              ),
              child: Text(
                '$number',
                style: TextStyle(
                  fontSize: 36.sp,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                  letterSpacing: 2,
                ),
              ),
            ),
            SizedBox(height: 16),
            Text(
              'Число верное?',
              style: TextStyle(color: Colors.white70, fontSize: 15.sp),
            ),
          ],
        ),
        actions: [
          // Кнопка "Неверно" / "Ввести вручную"
          TextButton.icon(
            onPressed: () {
              Navigator.pop(ctx);
              if (isRetry) {
                // После повторной попытки — ручной ввод
                _promptManualInput(templateId: templateId, isComputer: isComputer);
              } else {
                // Первая попытка — дать выделить область
                _openRegionSelector(templateId: templateId, isComputer: isComputer);
              }
            },
            icon: Icon(
              isRetry ? Icons.edit : Icons.crop_free,
              color: Colors.orange,
              size: 20,
            ),
            label: Text(
              isRetry ? 'Ввести вручную' : 'Неверно',
              style: TextStyle(color: Colors.orange, fontSize: 15.sp),
            ),
          ),
          // Кнопка "Верно"
          ElevatedButton.icon(
            onPressed: () {
              Navigator.pop(ctx);
              _acceptOcrNumber(number, templateId: templateId, isComputer: isComputer);
            },
            icon: Icon(Icons.check, color: Colors.white, size: 20),
            label: Text(
              'Верно',
              style: TextStyle(color: Colors.white, fontSize: 15.sp),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green.shade700,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8.r)),
            ),
          ),
        ],
      ),
    );
  }

  /// Принять OCR-число
  void _acceptOcrNumber(int number, {required String templateId, required bool isComputer}) {
    if (mounted) setState(() {
      if (isComputer) {
        _computerController.text = number.toString();
      } else {
        _machineControllers[templateId]?.text = number.toString();
        _machineWasEdited[templateId] = false;
      }
    });
  }

  /// Открыть экран выделения области и повторить OCR
  Future<void> _openRegionSelector({required String templateId, required bool isComputer}) async {
    final file = isComputer ? _computerPhoto : _machinePhotos[templateId];
    if (file == null) return;

    final region = await CounterRegionSelector.show(
      context,
      imageFile: file,
    );

    if (region == null || !mounted) return;

    // Сохранить выбранную область
    if (!isComputer) {
      _machineSelectedRegions[templateId] = region;
    }

    // Повторный OCR с выделенной областью
    final base64Image = isComputer ? _computerBase64 : _machineBase64[templateId];
    if (base64Image == null) return;

    final result = await _callOcr(
      base64Image: base64Image,
      templateId: templateId,
      isComputer: isComputer,
      userRegion: region,
    );

    if (result == null) return;

    if (!mounted) return;
    setState(() {
      if (isComputer) {
        _computerAiNumber = result.number;
      } else {
        _machineAiNumbers[templateId] = result.number;
      }
    });

    if (result.success && result.number != null) {
      // Показать повторный диалог (isRetry=true: кнопка "Ввести вручную" вместо "Неверно")
      _showInteractiveOcrDialog(
        number: result.number!,
        templateId: templateId,
        isComputer: isComputer,
        isRetry: true,
      );
    } else {
      _promptManualInput(templateId: templateId, isComputer: isComputer);
    }
  }

  /// Диалог ручного ввода числа
  void _promptManualInput({required String templateId, required bool isComputer}) {
    final manualController = TextEditingController();
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: Color(0xFF1A2E2E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16.r)),
        title: Row(
          children: [
            Icon(Icons.edit, color: AppColors.gold, size: 22),
            SizedBox(width: 8),
            Text('Введите число', style: TextStyle(color: Colors.white, fontSize: 16.sp)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Введите показание счётчика вручную',
              style: TextStyle(color: Colors.white70, fontSize: 14.sp),
            ),
            SizedBox(height: 16),
            TextField(
              controller: manualController,
              autofocus: true,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              style: TextStyle(color: Colors.white, fontSize: 28.sp, fontWeight: FontWeight.bold),
              decoration: InputDecoration(
                hintText: '12345',
                hintStyle: TextStyle(color: Colors.white.withOpacity(0.2)),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10.r),
                  borderSide: BorderSide(color: Colors.white.withOpacity(0.2)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10.r),
                  borderSide: BorderSide(color: AppColors.gold, width: 2),
                ),
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Отмена', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            onPressed: () {
              final text = manualController.text.trim();
              if (text.isEmpty) return;
              Navigator.pop(ctx);
              if (mounted) setState(() {
                if (isComputer) {
                  _computerController.text = text;
                } else {
                  _machineControllers[templateId]?.text = text;
                  _machineWasEdited[templateId] = true;
                }
              });
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.gold,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8.r)),
            ),
            child: Text('Подтвердить', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    ).then((_) {
      manualController.dispose();
    });
  }

  /// Диалог при ошибке OCR: только выделить область
  void _showOcrFailedDialog({required String templateId, required bool isComputer}) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: Color(0xFF1A2E2E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16.r)),
        title: Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 24),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                'Не удалось распознать',
                style: TextStyle(color: Colors.white, fontSize: 16.sp),
              ),
            ),
          ],
        ),
        content: Text(
          'ИИ не смог определить число на фото.\nВыделите область со счётчиком на фото.',
          style: TextStyle(color: Colors.white70, fontSize: 14.sp),
        ),
        actions: [
          ElevatedButton.icon(
            onPressed: () {
              Navigator.pop(ctx);
              _openRegionSelector(templateId: templateId, isComputer: isComputer);
            },
            icon: Icon(Icons.crop_free, color: Colors.white, size: 20),
            label: Text('Выделить область', style: TextStyle(color: Colors.white)),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.gold,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8.r)),
            ),
          ),
        ],
      ),
    );
  }

  /// Проверяет, можно ли перейти на следующий шаг
  bool get _canProceedToNext {
    if (_currentStep < _machineTemplates.length) {
      // Шаг машины: нужно фото + число
      final t = _machineTemplates[_currentStep];
      final hasPhoto = _machinePhotos[t.id] != null;
      final hasNumber = (_machineControllers[t.id]?.text ?? '').isNotEmpty;
      return hasPhoto && hasNumber;
    } else if (_currentStep == _machineTemplates.length) {
      // Шаг компьютера: нужно фото + число
      final hasPhoto = _computerPhoto != null;
      final hasNumber = _computerController.text.isNotEmpty;
      return hasPhoto && hasNumber;
    }
    // Итоги — всегда можно отправить (валидация в _submitReport)
    return true;
  }

  int get _sumOfMachines {
    int sum = 0;
    for (final t in _machineTemplates) {
      final text = _machineControllers[t.id]?.text ?? '';
      sum += int.tryParse(text) ?? 0;
    }
    return sum;
  }

  /// Число компьютера: сотрудник вводит обычное число, минус применяется автоматически
  double get _computerNumber {
    final text = _computerController.text.trim();
    if (text.isEmpty) return 0.0;
    final parsed = int.tryParse(text) ?? 0;
    return -parsed.toDouble();
  }

  /// Сверка: компьютер (минус) + сумма машин (плюс) = 0
  bool get _hasDiscrepancy => (_computerNumber + _sumOfMachines).abs() > 0.5;
  double get _discrepancyAmount => (_computerNumber + _sumOfMachines).abs();

  Future<void> _submitReport() async {
    // Валидация
    for (final t in _machineTemplates) {
      if (_machinePhotos[t.id] == null) {
        _showSnackBar('Сфотографируйте счётчик: ${t.name}', isError: true);
        return;
      }
      final text = _machineControllers[t.id]?.text ?? '';
      if (text.isEmpty) {
        _showSnackBar('Введите показание для: ${t.name}', isError: true);
        return;
      }
    }
    if (_computerPhoto == null) {
      _showSnackBar('Сфотографируйте показание компьютера', isError: true);
      return;
    }
    if (_computerController.text.isEmpty) {
      _showSnackBar('Введите показание компьютера', isError: true);
      return;
    }

    if (mounted) setState(() => _isSaving = true);

    try {
      // Загрузить фото машин
      final readings = <CoffeeMachineReading>[];
      for (final t in _machineTemplates) {
        String? photoUrl;
        if (_machinePhotos[t.id] != null) {
          photoUrl = await MediaUploadService.uploadMedia(_machinePhotos[t.id]!.path);
        }

        final confirmedNumber = int.tryParse(_machineControllers[t.id]?.text ?? '') ?? 0;
        final aiNumber = _machineAiNumbers[t.id];
        final wasEdited = (_machineWasEdited[t.id] == true) ||
            (aiNumber != null && aiNumber != confirmedNumber);

        readings.add(CoffeeMachineReading(
          templateId: t.id,
          machineName: t.name,
          photoUrl: photoUrl,
          aiReadNumber: aiNumber,
          confirmedNumber: confirmedNumber,
          wasManuallyEdited: wasEdited,
          selectedRegion: _machineSelectedRegions[t.id],
        ));
      }

      // Загрузить фото компьютера
      String? computerPhotoUrl;
      if (_computerPhoto != null) {
        computerPhotoUrl = await MediaUploadService.uploadMedia(_computerPhoto!.path);
      }

      final computerNum = _computerNumber;
      final sum = _sumOfMachines;
      final discrepancy = (computerNum + sum).abs();

      // Определить смену
      final hour = DateTime.now().hour;
      final shiftType = hour < 14 ? 'morning' : 'evening';

      final report = CoffeeMachineReport(
        id: 'cm_report_${DateTime.now().millisecondsSinceEpoch}_${Random().nextInt(10000)}',
        employeeName: widget.employeeName,
        shopAddress: widget.shopAddress,
        shiftType: shiftType,
        date: DateTime.now().toIso8601String().split('T')[0],
        readings: readings,
        computerNumber: computerNum,
        computerPhotoUrl: computerPhotoUrl,
        sumOfMachines: sum,
        hasDiscrepancy: discrepancy > 0.5,
        discrepancyAmount: discrepancy,
        status: 'pending',
        createdAt: DateTime.now(),
      );

      final result = await CoffeeMachineReportService.createReport(report);

      if (!mounted) return;

      if (result != null) {
        _showSnackBar('Отчёт успешно отправлен!');
        Navigator.of(context).pop(true);
        // НЕ вызываем setState после pop — страница уходит из дерева,
        // иначе rebuild обращается к деактивируемым InheritedWidgets
        return;
      } else {
        _showSnackBar('Ошибка отправки отчёта', isError: true);
      }
    } catch (e) {
      if (mounted) _showSnackBar('Ошибка: $e', isError: true);
    }
    // Сбрасываем _isSaving только если остались на странице
    if (mounted) setState(() => _isSaving = false);
  }

  void _showSnackBar(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red : Colors.green,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
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
              : _error != null
                  ? _buildError()
                  : _buildForm(),
        ),
      ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: EdgeInsets.all(24.w),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.coffee_outlined, size: 64, color: Colors.white.withOpacity(0.3)),
            SizedBox(height: 16),
            Text(
              _error!,
              style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 16.sp),
              textAlign: TextAlign.center,
            ),
            SizedBox(height: 24),
            ElevatedButton(
              onPressed: () => Navigator.pop(context),
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.emerald),
              child: Text('Назад', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildForm() {
    return Column(
      children: [
        // Header
        _buildHeader(),
        // Progress
        _buildProgress(),
        // Content
        Expanded(child: _buildStepContent()),
        // Bottom buttons
        _buildBottomButtons(),
      ],
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 8.h),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.pop(context),
            icon: Icon(Icons.arrow_back, color: Colors.white),
          ),
          SizedBox(width: 8),
          Icon(Icons.coffee_outlined, color: AppColors.gold, size: 24),
          SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Счётчик кофемашин',
                  style: TextStyle(color: Colors.white, fontSize: 18.sp, fontWeight: FontWeight.bold),
                ),
                Text(
                  widget.shopAddress,
                  style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 12.sp),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProgress() {
    final progress = (_currentStep + 1) / _totalSteps;
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 16.w),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Шаг ${_currentStep + 1} из $_totalSteps',
                style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 12.sp),
              ),
              Text(
                _getStepTitle(),
                style: TextStyle(color: AppColors.gold, fontSize: 12.sp, fontWeight: FontWeight.w600),
              ),
            ],
          ),
          SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(4.r),
            child: LinearProgressIndicator(
              value: progress,
              backgroundColor: Colors.white.withOpacity(0.1),
              valueColor: AlwaysStoppedAnimation<Color>(AppColors.gold),
              minHeight: 4,
            ),
          ),
        ],
      ),
    );
  }

  String _getStepTitle() {
    if (_currentStep < _machineTemplates.length) {
      return _machineTemplates[_currentStep].name;
    } else if (_currentStep == _machineTemplates.length) {
      return 'Компьютер';
    } else {
      return 'Итоги';
    }
  }

  Widget _buildStepContent() {
    if (_currentStep < _machineTemplates.length) {
      return _buildMachineStep(_machineTemplates[_currentStep]);
    } else if (_currentStep == _machineTemplates.length) {
      return _buildComputerStep();
    } else {
      return _buildSummaryStep();
    }
  }

  Widget _buildMachineStep(CoffeeMachineTemplate template) {
    final photo = _machinePhotos[template.id];
    final controller = _machineControllers[template.id]!;
    final hasNumber = controller.text.isNotEmpty;

    return SingleChildScrollView(
      padding: EdgeInsets.all(16.w),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Название машины
          Container(
            padding: EdgeInsets.all(16.w),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.06),
              borderRadius: BorderRadius.circular(14.r),
              border: Border.all(color: Colors.white.withOpacity(0.1)),
            ),
            child: Row(
              children: [
                Container(
                  padding: EdgeInsets.all(10.w),
                  decoration: BoxDecoration(
                    color: AppColors.gold.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(10.r),
                  ),
                  child: Icon(Icons.coffee, color: AppColors.gold, size: 28),
                ),
                SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        template.name,
                        style: TextStyle(color: Colors.white, fontSize: 18.sp, fontWeight: FontWeight.bold),
                      ),
                      Text(
                        CoffeeMachineTypes.getDisplayName(template.machineType),
                        style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 13.sp),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          SizedBox(height: 20),

          // Кнопка фото
          _buildPhotoButton(
            photo: photo,
            label: 'Сфотографировать счётчик',
            onTap: () => _pickAndRecognize(template.id),
          ),
          SizedBox(height: 20),

          // Показание: только после фото + распознавания
          if (hasNumber)
            _buildConfirmedNumberDisplay(
              number: controller.text,
              aiNumber: _machineAiNumbers[template.id],
              onRetakePhoto: () => _pickAndRecognize(template.id),
              onManualEdit: () => _promptManualInput(templateId: template.id, isComputer: false),
            )
          else if (photo != null)
            // Фото сделано, но число ещё не подтверждено — кнопки повторить / ввести вручную
            _buildOcrFallbackButtons(
              onRetakePhoto: () => _pickAndRecognize(template.id),
              onManualInput: () => _promptManualInput(templateId: template.id, isComputer: false),
            )
          else
            // Ещё нет фото — подсказка
            _buildPhotoHint(),
        ],
      ),
    );
  }

  Widget _buildComputerStep() {
    final hasNumber = _computerController.text.isNotEmpty;

    return SingleChildScrollView(
      padding: EdgeInsets.all(16.w),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Заголовок
          Container(
            padding: EdgeInsets.all(16.w),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.06),
              borderRadius: BorderRadius.circular(14.r),
              border: Border.all(color: Colors.white.withOpacity(0.1)),
            ),
            child: Row(
              children: [
                Container(
                  padding: EdgeInsets.all(10.w),
                  decoration: BoxDecoration(
                    color: Colors.blue.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(10.r),
                  ),
                  child: Icon(Icons.computer, color: Colors.blue, size: 28),
                ),
                SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _computerTemplate?.name ?? 'Показание компьютера',
                        style: TextStyle(color: Colors.white, fontSize: 18.sp, fontWeight: FontWeight.bold),
                      ),
                      Text(
                        'Сфотографируйте экран компьютера с остатком',
                        style: TextStyle(color: Colors.white54, fontSize: 13.sp),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          SizedBox(height: 20),

          // Фото
          _buildPhotoButton(
            photo: _computerPhoto,
            label: 'Сфотографировать компьютер',
            onTap: () => _pickAndRecognize('', isComputer: true),
          ),
          SizedBox(height: 20),

          // Показание: только после фото + распознавания
          if (hasNumber)
            _buildConfirmedNumberDisplay(
              number: _computerController.text,
              aiNumber: _computerAiNumber,
              isComputer: true,
              onRetakePhoto: () => _pickAndRecognize('', isComputer: true),
              onManualEdit: () => _promptManualInput(templateId: '', isComputer: true),
            )
          else if (_computerPhoto != null)
            _buildOcrFallbackButtons(
              onRetakePhoto: () => _pickAndRecognize('', isComputer: true),
              onManualInput: () => _promptManualInput(templateId: '', isComputer: true),
            )
          else
            _buildPhotoHint(),
        ],
      ),
    );
  }

  Widget _buildSummaryStep() {
    final sum = _sumOfMachines;
    final computer = _computerNumber;
    final discrepancy = _hasDiscrepancy;
    final diff = _discrepancyAmount;

    return SingleChildScrollView(
      padding: EdgeInsets.all(16.w),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Заголовок
          Text(
            'Итоги',
            style: TextStyle(color: AppColors.gold, fontSize: 20.sp, fontWeight: FontWeight.bold),
          ),
          SizedBox(height: 16),

          // Показания машин
          ...(_machineTemplates.map((t) {
            final val = _machineControllers[t.id]?.text ?? '0';
            return _buildSummaryRow(t.name, val);
          })),

          Divider(color: Colors.white24, height: 24),

          // Сумма
          _buildSummaryRow('Сумма машин', '+$sum', isBold: true, color: AppColors.gold),
          SizedBox(height: 8),
          _buildSummaryRow('Компьютер', '${computer.toStringAsFixed(2)}', isBold: true, color: Colors.blue),

          Divider(color: Colors.white24, height: 24),

          // Итог: компьютер + сумма
          _buildSummaryRow(
            'Итого (комп + машины)',
            '${(computer + sum).toStringAsFixed(2)}',
            isBold: true,
            color: discrepancy ? Colors.orange : Colors.green,
          ),

          SizedBox(height: 16),

          // Расхождение
          if (discrepancy)
            Container(
              padding: EdgeInsets.all(14.w),
              decoration: BoxDecoration(
                color: Colors.orange.withOpacity(0.15),
                borderRadius: BorderRadius.circular(12.r),
                border: Border.all(color: Colors.orange.withOpacity(0.3)),
              ),
              child: Row(
                children: [
                  Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 28),
                  SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Не сходится!',
                          style: TextStyle(color: Colors.orange, fontWeight: FontWeight.bold, fontSize: 16.sp),
                        ),
                        Text(
                          'Разница: ${diff.toStringAsFixed(2)}',
                          style: TextStyle(color: Colors.orange, fontSize: 14.sp),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            )
          else
            Container(
              padding: EdgeInsets.all(14.w),
              decoration: BoxDecoration(
                color: Colors.green.withOpacity(0.15),
                borderRadius: BorderRadius.circular(12.r),
                border: Border.all(color: Colors.green.withOpacity(0.3)),
              ),
              child: Row(
                children: [
                  Icon(Icons.check_circle, color: Colors.green, size: 28),
                  SizedBox(width: 12),
                  Text(
                    'Счётчик сходится!',
                    style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold, fontSize: 16.sp),
                  ),
                ],
              ),
            ),

          SizedBox(height: 24),

          // Информация
          Text(
            'Сотрудник: ${widget.employeeName}',
            style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 13.sp),
          ),
          SizedBox(height: 4),
          Text(
            'Магазин: ${widget.shopAddress}',
            style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 13.sp),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryRow(String label, String value, {bool isBold = false, Color? color}) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 4.h),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              color: Colors.white.withOpacity(0.7),
              fontSize: 14.sp,
              fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              color: color ?? Colors.white,
              fontSize: 16.sp,
              fontWeight: isBold ? FontWeight.bold : FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPhotoButton({File? photo, required String label, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        height: photo != null ? 250 : 140,
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.06),
          borderRadius: BorderRadius.circular(14.r),
          border: Border.all(
            color: photo != null ? AppColors.gold.withOpacity(0.4) : Colors.white.withOpacity(0.15),
            width: photo != null ? 2 : 1,
          ),
        ),
        child: photo != null
            ? ClipRRect(
                borderRadius: BorderRadius.circular(13.r),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Image.file(photo, fit: BoxFit.cover),
                    Positioned(
                      bottom: 8.h,
                      right: 8.w,
                      child: Container(
                        padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 5.h),
                        decoration: BoxDecoration(
                          color: AppColors.gold,
                          borderRadius: BorderRadius.circular(8.r),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.camera_alt, color: Colors.white, size: 16),
                            SizedBox(width: 4),
                            Text('Переснять', style: TextStyle(color: Colors.white, fontSize: 12.sp)),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              )
            : Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.camera_alt_outlined, color: Colors.white.withOpacity(0.3), size: 40),
                  SizedBox(height: 10),
                  Text(
                    label,
                    style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 14.sp),
                  ),
                ],
              ),
      ),
    );
  }


  /// Подсказка: сделайте фото счётчика
  Widget _buildPhotoHint() {
    return Container(
      padding: EdgeInsets.all(14.w),
      decoration: BoxDecoration(
        color: Colors.blue.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12.r),
        border: Border.all(color: Colors.blue.withOpacity(0.2)),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline, color: Colors.blue.withOpacity(0.7), size: 22),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'Сделайте фото — ИИ автоматически определит число на счётчике',
              style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 13.sp),
            ),
          ),
        ],
      ),
    );
  }

  /// Подтверждённое число (read-only карточка)
  Widget _buildConfirmedNumberDisplay({
    required String number,
    int? aiNumber,
    bool isComputer = false,
    required VoidCallback onRetakePhoto,
    required VoidCallback onManualEdit,
  }) {
    return Container(
      padding: EdgeInsets.all(16.w),
      decoration: BoxDecoration(
        color: Colors.green.withOpacity(0.08),
        borderRadius: BorderRadius.circular(14.r),
        border: Border.all(color: Colors.green.withOpacity(0.3)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Icon(Icons.check_circle, color: Colors.green, size: 22),
              SizedBox(width: 8),
              Text(
                isComputer ? 'Показание компьютера' : 'Показание счётчика',
                style: TextStyle(color: Colors.green, fontSize: 14.sp, fontWeight: FontWeight.w600),
              ),
            ],
          ),
          SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (isComputer)
                Text(
                  '− ',
                  style: TextStyle(color: Colors.red, fontSize: 32.sp, fontWeight: FontWeight.bold),
                ),
              Text(
                number,
                style: TextStyle(color: Colors.white, fontSize: 32.sp, fontWeight: FontWeight.bold, letterSpacing: 2),
              ),
            ],
          ),
          if (aiNumber != null) ...[
            SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.smart_toy, color: AppColors.gold.withOpacity(0.6), size: 14),
                SizedBox(width: 4),
                Text(
                  'ИИ распознал: $aiNumber',
                  style: TextStyle(color: AppColors.gold.withOpacity(0.6), fontSize: 12.sp),
                ),
              ],
            ),
          ],
          SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onRetakePhoto,
                  icon: Icon(Icons.camera_alt, size: 18),
                  label: Text('Переснять', style: TextStyle(fontSize: 12.sp)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white70,
                    side: BorderSide(color: Colors.white.withOpacity(0.2)),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8.r)),
                    padding: EdgeInsets.symmetric(vertical: 10.h),
                  ),
                ),
              ),
              SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onManualEdit,
                  icon: Icon(Icons.edit, size: 18),
                  label: Text('Исправить', style: TextStyle(fontSize: 12.sp)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.orange,
                    side: BorderSide(color: Colors.orange.withOpacity(0.3)),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8.r)),
                    padding: EdgeInsets.symmetric(vertical: 10.h),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Кнопки-фоллбек: переснять фото / ввести вручную (когда OCR не дал число)
  Widget _buildOcrFallbackButtons({
    required VoidCallback onRetakePhoto,
    required VoidCallback onManualInput,
  }) {
    return Container(
      padding: EdgeInsets.all(14.w),
      decoration: BoxDecoration(
        color: Colors.orange.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12.r),
        border: Border.all(color: Colors.orange.withOpacity(0.2)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 22),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Число не подтверждено. Переснимите фото или введите вручную.',
                  style: TextStyle(color: Colors.orange.withOpacity(0.8), fontSize: 13.sp),
                ),
              ),
            ],
          ),
          SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: onRetakePhoto,
                  icon: Icon(Icons.camera_alt, size: 18),
                  label: Text('Переснять', style: TextStyle(fontSize: 13.sp)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.gold,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8.r)),
                    padding: EdgeInsets.symmetric(vertical: 12.h),
                  ),
                ),
              ),
              SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onManualInput,
                  icon: Icon(Icons.edit, size: 18),
                  label: Text('Вручную', style: TextStyle(fontSize: 13.sp)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.orange,
                    side: BorderSide(color: Colors.orange.withOpacity(0.4)),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8.r)),
                    padding: EdgeInsets.symmetric(vertical: 12.h),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBottomButtons() {
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
              child: OutlinedButton(
                onPressed: () { if (mounted) setState(() => _currentStep--); },
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: Colors.white.withOpacity(0.3)),
                  padding: EdgeInsets.symmetric(vertical: 14.h),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.r)),
                ),
                child: Text('Назад', style: TextStyle(color: Colors.white)),
              ),
            ),
          if (_currentStep > 0) SizedBox(width: 12),
          Expanded(
            flex: 2,
            child: ElevatedButton(
              onPressed: _isSaving
                  ? null
                  : !_canProceedToNext
                      ? null
                      : isLastStep
                          ? _submitReport
                          : () { if (mounted) setState(() => _currentStep++); },
              style: ElevatedButton.styleFrom(
                backgroundColor: isLastStep ? AppColors.gold : AppColors.emerald,
                padding: EdgeInsets.symmetric(vertical: 14.h),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.r)),
              ),
              child: _isSaving
                  ? SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                    )
                  : Text(
                      isLastStep ? 'Отправить' : 'Далее',
                      style: TextStyle(color: Colors.white, fontSize: 16.sp, fontWeight: FontWeight.w600),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
