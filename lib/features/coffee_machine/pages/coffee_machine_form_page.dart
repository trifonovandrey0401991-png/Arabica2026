import 'dart:convert';
import 'dart:io';
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
  static const Color _emerald = Color(0xFF1A4D4D);
  static const Color _emeraldDark = Color(0xFF0D2E2E);
  static const Color _night = Color(0xFF051515);
  static const Color _gold = Color(0xFFD4AF37);

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
  final Map<String, bool> _machineOcrDone = {};
  final Map<String, Map<String, double>?> _machineSelectedRegions = {};
  final Map<String, String> _machineBase64 = {}; // base64 фото для повторного OCR

  // Фото и данные компьютера
  File? _computerPhoto;
  int? _computerAiNumber;
  final _computerController = TextEditingController();
  bool _computerOcrDone = false;
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
        setState(() {
          _isLoading = false;
          _error = 'Шаблоны кофемашин не найдены';
        });
        return;
      }

      // Инициализировать контроллеры
      for (final t in templates) {
        _machineControllers[t.id] = TextEditingController();
        _machineOcrDone[t.id] = false;
      }

      setState(() {
        _machineTemplates = templates;
        _isLoading = false;
      });
    } catch (e) {
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

    setState(() {
      if (isComputer) {
        _computerAiNumber = result.number;
        _computerOcrDone = true;
      } else {
        _machineAiNumbers[templateId] = result.number;
        _machineOcrDone[templateId] = true;
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
      builder: (_) => const Center(
        child: Card(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(color: _emerald),
                SizedBox(height: 16),
                Text('Распознавание числа...'),
              ],
            ),
          ),
        ),
      ),
    );

    // Определить region: пользовательский или из шаблона
    Map<String, double>? region = userRegion;
    if (region == null && !isComputer) {
      final template = _machineTemplates.firstWhere((t) => t.id == templateId);
      if (template.counterRegion != null) {
        region = {
          'x': template.counterRegion!.x,
          'y': template.counterRegion!.y,
          'width': template.counterRegion!.width,
          'height': template.counterRegion!.height,
        };
      }
    }

    // Пресет OCR
    String? preset;
    if (isComputer) {
      preset = 'computer';
    } else {
      final template = _machineTemplates.firstWhere((t) => t.id == templateId);
      preset = template.ocrPreset;
    }

    // Имя машины для поиска обученного region на сервере
    String? machineNameForTraining;
    if (!isComputer) {
      final tmpl = _machineTemplates.firstWhere((t) => t.id == templateId);
      machineNameForTraining = tmpl.name;
    }

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
        backgroundColor: const Color(0xFF1A2E2E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            const Icon(Icons.smart_toy, color: _gold, size: 24),
            const SizedBox(width: 8),
            Text(
              isRetry ? 'Повторное распознавание' : 'Результат распознавания',
              style: const TextStyle(color: Colors.white, fontSize: 16),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.08),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                '$number',
                style: const TextStyle(
                  fontSize: 36,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                  letterSpacing: 2,
                ),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Число верное?',
              style: TextStyle(color: Colors.white70, fontSize: 15),
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
              style: const TextStyle(color: Colors.orange, fontSize: 15),
            ),
          ),
          // Кнопка "Верно"
          ElevatedButton.icon(
            onPressed: () {
              Navigator.pop(ctx);
              _acceptOcrNumber(number, templateId: templateId, isComputer: isComputer);
            },
            icon: const Icon(Icons.check, color: Colors.white, size: 20),
            label: const Text(
              'Верно',
              style: TextStyle(color: Colors.white, fontSize: 15),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green.shade700,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
          ),
        ],
      ),
    );
  }

  /// Принять OCR-число
  void _acceptOcrNumber(int number, {required String templateId, required bool isComputer}) {
    setState(() {
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
        backgroundColor: const Color(0xFF1A2E2E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.edit, color: _gold, size: 22),
            SizedBox(width: 8),
            Text('Введите число', style: TextStyle(color: Colors.white, fontSize: 16)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Введите показание счётчика вручную',
              style: TextStyle(color: Colors.white70, fontSize: 14),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: manualController,
              autofocus: true,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.bold),
              decoration: InputDecoration(
                hintText: '12345',
                hintStyle: TextStyle(color: Colors.white.withOpacity(0.2)),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: Colors.white.withOpacity(0.2)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: _gold, width: 2),
                ),
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Отмена', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            onPressed: () {
              final text = manualController.text.trim();
              if (text.isEmpty) return;
              Navigator.pop(ctx);
              setState(() {
                if (isComputer) {
                  _computerController.text = text;
                } else {
                  _machineControllers[templateId]?.text = text;
                  _machineWasEdited[templateId] = true;
                }
              });
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: _gold,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: const Text('Подтвердить', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  /// Диалог при ошибке OCR: только выделить область
  void _showOcrFailedDialog({required String templateId, required bool isComputer}) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A2E2E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 24),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                'Не удалось распознать',
                style: TextStyle(color: Colors.white, fontSize: 16),
              ),
            ),
          ],
        ),
        content: const Text(
          'ИИ не смог определить число на фото.\nВыделите область со счётчиком на фото.',
          style: TextStyle(color: Colors.white70, fontSize: 14),
        ),
        actions: [
          ElevatedButton.icon(
            onPressed: () {
              Navigator.pop(ctx);
              _openRegionSelector(templateId: templateId, isComputer: isComputer);
            },
            icon: const Icon(Icons.crop_free, color: Colors.white, size: 20),
            label: const Text('Выделить область', style: TextStyle(color: Colors.white)),
            style: ElevatedButton.styleFrom(
              backgroundColor: _gold,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
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

    setState(() => _isSaving = true);

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
        id: 'cm_report_${DateTime.now().millisecondsSinceEpoch}',
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
      } else {
        _showSnackBar('Ошибка отправки отчёта', isError: true);
      }
    } catch (e) {
      _showSnackBar('Ошибка: $e', isError: true);
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
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
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [_emerald, _emeraldDark, _night],
            stops: [0.0, 0.3, 1.0],
          ),
        ),
        child: SafeArea(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator(color: _gold))
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
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.coffee_outlined, size: 64, color: Colors.white.withOpacity(0.3)),
            const SizedBox(height: 16),
            Text(
              _error!,
              style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 16),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () => Navigator.pop(context),
              style: ElevatedButton.styleFrom(backgroundColor: _emerald),
              child: const Text('Назад', style: TextStyle(color: Colors.white)),
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
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.arrow_back, color: Colors.white),
          ),
          const SizedBox(width: 8),
          Icon(Icons.coffee_outlined, color: _gold, size: 24),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Счётчик кофемашин',
                  style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                ),
                Text(
                  widget.shopAddress,
                  style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 12),
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
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Шаг ${_currentStep + 1} из $_totalSteps',
                style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 12),
              ),
              Text(
                _getStepTitle(),
                style: TextStyle(color: _gold, fontSize: 12, fontWeight: FontWeight.w600),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progress,
              backgroundColor: Colors.white.withOpacity(0.1),
              valueColor: const AlwaysStoppedAnimation<Color>(_gold),
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
    final ocrDone = _machineOcrDone[template.id] ?? false;
    final controller = _machineControllers[template.id]!;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Название машины
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.06),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.white.withOpacity(0.1)),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: _gold.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(Icons.coffee, color: _gold, size: 28),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        template.name,
                        style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      Text(
                        CoffeeMachineTypes.getDisplayName(template.machineType),
                        style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 13),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Кнопка фото
          _buildPhotoButton(
            photo: photo,
            label: 'Сфотографировать счётчик',
            onTap: () => _pickAndRecognize(template.id),
          ),
          const SizedBox(height: 20),

          // Поле ввода числа
          _buildNumberInput(
            controller: controller,
            label: 'Показание счётчика',
            ocrDone: ocrDone,
            aiNumber: _machineAiNumbers[template.id],
          ),
        ],
      ),
    );
  }

  Widget _buildComputerStep() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Заголовок
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.06),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.white.withOpacity(0.1)),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.blue.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.computer, color: Colors.blue, size: 28),
                ),
                const SizedBox(width: 14),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Показание компьютера',
                        style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      Text(
                        'Сфотографируйте экран компьютера с остатком',
                        style: TextStyle(color: Colors.white54, fontSize: 13),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Фото
          _buildPhotoButton(
            photo: _computerPhoto,
            label: 'Сфотографировать компьютер',
            onTap: () => _pickAndRecognize('', isComputer: true),
          ),
          const SizedBox(height: 20),

          // Поле ввода (разрешаем минус, пробел, запятую, точку для компьютерного числа)
          _buildComputerNumberInput(),
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
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Заголовок
          Text(
            'Итоги',
            style: TextStyle(color: _gold, fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),

          // Показания машин
          ...(_machineTemplates.map((t) {
            final val = _machineControllers[t.id]?.text ?? '0';
            return _buildSummaryRow(t.name, val);
          })),

          const Divider(color: Colors.white24, height: 24),

          // Сумма
          _buildSummaryRow('Сумма машин', '+$sum', isBold: true, color: _gold),
          const SizedBox(height: 8),
          _buildSummaryRow('Компьютер', '${computer.toStringAsFixed(2)}', isBold: true, color: Colors.blue),

          const Divider(color: Colors.white24, height: 24),

          // Итог: компьютер + сумма
          _buildSummaryRow(
            'Итого (комп + машины)',
            '${(computer + sum).toStringAsFixed(2)}',
            isBold: true,
            color: discrepancy ? Colors.orange : Colors.green,
          ),

          const SizedBox(height: 16),

          // Расхождение
          if (discrepancy)
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.orange.withOpacity(0.15),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.orange.withOpacity(0.3)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 28),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Не сходится!',
                          style: TextStyle(color: Colors.orange, fontWeight: FontWeight.bold, fontSize: 16),
                        ),
                        Text(
                          'Разница: ${diff.toStringAsFixed(2)}',
                          style: const TextStyle(color: Colors.orange, fontSize: 14),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            )
          else
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.green.withOpacity(0.15),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.green.withOpacity(0.3)),
              ),
              child: const Row(
                children: [
                  Icon(Icons.check_circle, color: Colors.green, size: 28),
                  SizedBox(width: 12),
                  Text(
                    'Счётчик сходится!',
                    style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                ],
              ),
            ),

          const SizedBox(height: 24),

          // Информация
          Text(
            'Сотрудник: ${widget.employeeName}',
            style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 13),
          ),
          const SizedBox(height: 4),
          Text(
            'Магазин: ${widget.shopAddress}',
            style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 13),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryRow(String label, String value, {bool isBold = false, Color? color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              color: Colors.white.withOpacity(0.7),
              fontSize: 14,
              fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              color: color ?? Colors.white,
              fontSize: 16,
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
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: photo != null ? _gold.withOpacity(0.4) : Colors.white.withOpacity(0.15),
            width: photo != null ? 2 : 1,
          ),
        ),
        child: photo != null
            ? ClipRRect(
                borderRadius: BorderRadius.circular(13),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Image.file(photo, fit: BoxFit.cover),
                    Positioned(
                      bottom: 8,
                      right: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: _gold,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.camera_alt, color: Colors.white, size: 16),
                            SizedBox(width: 4),
                            Text('Переснять', style: TextStyle(color: Colors.white, fontSize: 12)),
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
                  const SizedBox(height: 10),
                  Text(
                    label,
                    style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 14),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _buildNumberInput({
    required TextEditingController controller,
    required String label,
    required bool ocrDone,
    int? aiNumber,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (ocrDone && aiNumber != null) ...[
            Row(
              children: [
                const Icon(Icons.smart_toy, color: _gold, size: 18),
                const SizedBox(width: 6),
                Text(
                  'ИИ распознал: $aiNumber',
                  style: TextStyle(color: _gold, fontSize: 13),
                ),
              ],
            ),
            const SizedBox(height: 10),
          ],
          TextField(
            controller: controller,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold),
            decoration: InputDecoration(
              labelText: label,
              labelStyle: TextStyle(color: Colors.white.withOpacity(0.5)),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: Colors.white.withOpacity(0.2)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: _gold, width: 2),
              ),
              prefixIcon: Icon(Icons.numbers, color: Colors.white.withOpacity(0.4)),
            ),
            onChanged: (_) => setState(() {}),
          ),
        ],
      ),
    );
  }

  /// Поле ввода числа компьютера (только цифры, минус добавляется автоматически)
  Widget _buildComputerNumberInput() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_computerOcrDone && _computerAiNumber != null) ...[
            Row(
              children: [
                const Icon(Icons.smart_toy, color: _gold, size: 18),
                const SizedBox(width: 6),
                Text(
                  'ИИ распознал: $_computerAiNumber',
                  style: TextStyle(color: _gold, fontSize: 13),
                ),
              ],
            ),
            const SizedBox(height: 10),
          ],
          TextField(
            controller: _computerController,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold),
            decoration: InputDecoration(
              labelText: 'Остаток по компьютеру',
              hintText: '138141',
              hintStyle: TextStyle(color: Colors.white.withOpacity(0.2), fontSize: 16),
              labelStyle: TextStyle(color: Colors.white.withOpacity(0.5)),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: Colors.white.withOpacity(0.2)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: _gold, width: 2),
              ),
              prefixIcon: Icon(Icons.computer, color: Colors.white.withOpacity(0.4)),
              prefixText: '− ',
              prefixStyle: const TextStyle(color: Colors.red, fontSize: 24, fontWeight: FontWeight.bold),
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 6),
          Text(
            'Минус применяется автоматически',
            style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomButtons() {
    final isLastStep = _currentStep == _totalSteps - 1;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.3),
        border: Border(top: BorderSide(color: Colors.white.withOpacity(0.1))),
      ),
      child: Row(
        children: [
          if (_currentStep > 0)
            Expanded(
              child: OutlinedButton(
                onPressed: () => setState(() => _currentStep--),
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: Colors.white.withOpacity(0.3)),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: const Text('Назад', style: TextStyle(color: Colors.white)),
              ),
            ),
          if (_currentStep > 0) const SizedBox(width: 12),
          Expanded(
            flex: 2,
            child: ElevatedButton(
              onPressed: _isSaving
                  ? null
                  : !_canProceedToNext
                      ? null
                      : isLastStep
                          ? _submitReport
                          : () => setState(() => _currentStep++),
              style: ElevatedButton.styleFrom(
                backgroundColor: isLastStep ? _gold : _emerald,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: _isSaving
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                    )
                  : Text(
                      isLastStep ? 'Отправить' : 'Далее',
                      style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
