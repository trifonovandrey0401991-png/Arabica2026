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
import '../../../core/services/media_upload_service.dart';
import '../../../core/utils/logger.dart';

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
  final _formKey = GlobalKey<FormState>();
  final _imagePicker = ImagePicker();

  int _currentStep = 0;
  bool _isLoading = false;
  bool _isSaving = false;
  List<Supplier> _suppliers = [];
  List<EnvelopeQuestion> _questions = [];

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
  List<ExpenseItem> _oooExpenses = [];

  // ООО - чеки не переданные в ОФД
  final _oooOfdNotSentController = TextEditingController();
  // ООО - ресурс ключей
  final _oooResourceKeysController = TextEditingController();

  // ИП
  File? _ipZReportPhoto;
  String? _ipZReportPhotoUrl;
  final _ipRevenueController = TextEditingController();
  final _ipCashController = TextEditingController();
  List<ExpenseItem> _expenses = [];
  File? _ipEnvelopePhoto;
  String? _ipEnvelopePhotoUrl;

  // ИП - чеки не переданные в ОФД
  final _ipOfdNotSentController = TextEditingController();
  // ИП - ресурс ключей
  final _ipResourceKeysController = TextEditingController();

  static const _primaryColor = Color(0xFF004D40);

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      // Загружаем вопросы и поставщиков параллельно
      final results = await Future.wait([
        EnvelopeQuestionService.getQuestions(),
        SupplierService.getSuppliers(),
      ]);

      setState(() {
        _questions = results[0] as List<EnvelopeQuestion>;
        _suppliers = results[1] as List<Supplier>;
      });

      Logger.debug('Загружено ${_questions.length} вопросов конверта');
    } catch (e) {
      Logger.error('Ошибка загрузки данных', e);
    } finally {
      setState(() => _isLoading = false);
    }
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

  /// Сфотографировать и распознать Z-отчёт
  Future<void> _pickAndRecognizeZReport({
    required bool isOoo,
    required Function(File) onPhotoPicked,
  }) async {
    try {
      final picked = await _imagePicker.pickImage(
        source: ImageSource.camera,
        maxWidth: 1920,
        maxHeight: 1920,
        imageQuality: 85,
      );

      if (picked == null || !mounted) return;

      final file = File(picked.path);
      onPhotoPicked(file);

      // Показываем индикатор загрузки
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => const AlertDialog(
          content: Row(
            children: [
              CircularProgressIndicator(),
              SizedBox(width: 16),
              Text('Распознавание Z-отчёта...'),
            ],
          ),
        ),
      );

      // Конвертируем в base64 со сжатием и отправляем на распознавание
      final bytes = await file.readAsBytes();
      Logger.debug('📸 Размер оригинала: ${(bytes.length / 1024).toStringAsFixed(0)} KB');
      final compressedBase64 = await ZReportService.compressImage(bytes);
      Logger.debug('📦 Размер сжатого base64: ${(compressedBase64.length / 1024).toStringAsFixed(0)} KB');
      final result = await ZReportService.parseZReport(compressedBase64);

      // Закрываем индикатор загрузки
      if (mounted) Navigator.of(context).pop();

      if (!mounted) return;

      // Показываем диалог с результатами распознавания
      final dialogResult = await ZReportRecognitionDialog.show(
        context,
        imageBase64: compressedBase64,
        recognizedData: result.success ? result.data : null,
        shopAddress: widget.shopAddress,
        employeeName: widget.employeeName,
      );

      if (dialogResult != null) {
        // Заполняем поля распознанными/исправленными данными
        setState(() {
          if (isOoo) {
            _oooRevenueController.text = dialogResult.revenue.toStringAsFixed(0);
            _oooCashController.text = dialogResult.cash.toStringAsFixed(0);
            _oooOfdNotSentController.text = dialogResult.ofdNotSent.toString();
            _oooResourceKeysController.text = dialogResult.resourceKeys.toString();
          } else {
            _ipRevenueController.text = dialogResult.revenue.toStringAsFixed(0);
            _ipCashController.text = dialogResult.cash.toStringAsFixed(0);
            _ipOfdNotSentController.text = dialogResult.ofdNotSent.toString();
            _ipResourceKeysController.text = dialogResult.resourceKeys.toString();
          }
        });
      }
    } catch (e) {
      Logger.error('Ошибка распознавания Z-отчёта', e);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка: $e')),
        );
      }
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
        setState(() => _currentStep++);
      }
    }
  }

  void _prevStep() {
    if (_currentStep > 0) {
      setState(() => _currentStep--);
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
        content: Text(message, style: const TextStyle(color: Colors.white)),
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
      setState(() => _oooExpenses.add(result));
    }
  }

  void _removeOooExpense(int index) {
    setState(() => _oooExpenses.removeAt(index));
  }

  Future<void> _addExpense() async {
    // Фильтруем поставщиков - для расходов ИП показываем только поставщиков ИП
    final ipSuppliers = _suppliers.where((s) => s.legalType == 'ИП').toList();

    final result = await showDialog<ExpenseItem>(
      context: context,
      builder: (context) => AddExpenseDialog(suppliers: ipSuppliers),
    );
    if (result != null) {
      setState(() => _expenses.add(result));
    }
  }

  void _removeExpense(int index) {
    setState(() => _expenses.removeAt(index));
  }

  Future<void> _submitReport() async {
    if (_isSaving) return;

    setState(() => _isSaving = true);

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
        ipZReportPhotoUrl: _ipZReportPhotoUrl,
        ipRevenue: _ipRevenue,
        ipCash: _ipCash,
        expenses: _expenses,
        ipEnvelopePhotoUrl: _ipEnvelopePhotoUrl,
        ipOfdNotSent: int.tryParse(_ipOfdNotSentController.text) ?? 0,
      );

      final created = await EnvelopeReportService.createReport(report);

      if (created != null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Отчет успешно отправлен!',
              style: TextStyle(color: Colors.white),
            ),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.of(context).pop(true);
      } else {
        _showError('Ошибка отправки отчета');
      }
    } catch (e) {
      Logger.error('Ошибка отправки отчета', e);
      _showError('Ошибка: $e');
    } finally {
      setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_stepTitles[_currentStep]),
        backgroundColor: _primaryColor,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // Progress bar
                LinearProgressIndicator(
                  value: _progress,
                  backgroundColor: Colors.grey[300],
                  valueColor: const AlwaysStoppedAnimation<Color>(_primaryColor),
                ),
                Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Text(
                    'Шаг ${_currentStep + 1} из $_totalSteps',
                    style: TextStyle(color: Colors.grey[600]),
                  ),
                ),

                // Content
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: _buildStepContent(),
                  ),
                ),

                // Navigation buttons
                _buildNavigationButtons(),
              ],
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
        return const SizedBox();
    }
  }

  Widget _buildShiftTypeStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Выберите тип смены:',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 24),
        _buildShiftOption('morning', 'Утренняя смена', Icons.wb_sunny),
        const SizedBox(height: 16),
        _buildShiftOption('evening', 'Вечерняя смена', Icons.nights_stay),
      ],
    );
  }

  Widget _buildShiftOption(String value, String label, IconData icon) {
    final isSelected = _shiftType == value;
    final color = value == 'morning' ? Colors.orange : Colors.indigo;
    return InkWell(
      onTap: () => setState(() => _shiftType = value),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(
            color: isSelected ? color : Colors.grey[300]!,
            width: isSelected ? 2 : 1,
          ),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: color.withOpacity(0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color, size: 32),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey.shade800,
                ),
              ),
            ),
            if (isSelected)
              Icon(Icons.check_circle, color: color, size: 28),
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          title,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),

        // Подсказка о распознавании
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.green[50],
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.green[200]!),
          ),
          child: Row(
            children: [
              Icon(Icons.auto_awesome, color: Colors.green[700], size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'ИИ автоматически распознает данные с фото',
                  style: TextStyle(fontSize: 13, color: Colors.green[700]),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // Эталонное фото (если есть)
        if (referencePhotoUrl != null && referencePhotoUrl.isNotEmpty) ...[
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.blue[50],
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.blue[200]!),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.info_outline, color: Colors.blue[700], size: 20),
                    const SizedBox(width: 8),
                    Text(
                      'Образец фото:',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.blue[700],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.network(
                    referencePhotoUrl,
                    height: 150,
                    width: double.infinity,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stack) {
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
          const SizedBox(height: 16),
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
          const SizedBox(height: 8),
        ],

        if (photo != null)
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.file(photo, height: 300, fit: BoxFit.cover),
          )
        else if (photoUrl != null)
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.network(photoUrl, height: 300, fit: BoxFit.cover),
          )
        else
          Container(
            height: 200,
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey[300]!),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Center(
              child: Icon(Icons.camera_alt, size: 64, color: Colors.grey),
            ),
          ),
        const SizedBox(height: 16),
        ElevatedButton.icon(
          onPressed: () => _pickAndRecognizeZReport(
            isOoo: isOoo,
            onPhotoPicked: onPick,
          ),
          icon: const Icon(Icons.camera_alt),
          label: Text(photo != null ? 'Переснять и распознать' : 'Сфотографировать'),
          style: ElevatedButton.styleFrom(
            backgroundColor: _primaryColor,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 16),
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
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 16),

        // Эталонное фото (если есть)
        if (referencePhotoUrl != null && referencePhotoUrl.isNotEmpty) ...[
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.blue[50],
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.blue[200]!),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.info_outline, color: Colors.blue[700], size: 20),
                    const SizedBox(width: 8),
                    Text(
                      'Образец фото:',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.blue[700],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.network(
                    referencePhotoUrl,
                    height: 150,
                    width: double.infinity,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stack) {
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
                    loadingBuilder: (context, child, progress) {
                      if (progress == null) return child;
                      return Container(
                        height: 150,
                        color: Colors.grey[100],
                        child: const Center(
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
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
          const SizedBox(height: 8),
        ],

        if (photo != null)
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.file(photo, height: 300, fit: BoxFit.cover),
          )
        else if (photoUrl != null)
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.network(photoUrl, height: 300, fit: BoxFit.cover),
          )
        else
          Container(
            height: 200,
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey[300]!),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Center(
              child: Icon(Icons.camera_alt, size: 64, color: Colors.grey),
            ),
          ),
        const SizedBox(height: 16),
        ElevatedButton.icon(
          onPressed: () => _pickImage(onPick),
          icon: const Icon(Icons.camera_alt),
          label: Text(photo != null ? 'Переснять' : 'Сделать фото'),
          style: ElevatedButton.styleFrom(
            backgroundColor: _primaryColor,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 16),
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
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.teal.shade200, width: 1),
          ),
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.teal.shade100,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(Icons.edit_note, color: Colors.teal.shade700, size: 24),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Введите данные $title:',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),

        // Поля ввода
        _buildEnvelopeTextField(
          revenueController,
          'Сумма выручки *',
          Icons.currency_ruble,
          true,
        ),
        const SizedBox(height: 12),
        _buildEnvelopeTextField(
          cashController,
          'Сумма наличных *',
          Icons.payments_outlined,
          true,
        ),
        const SizedBox(height: 12),
        _buildEnvelopeTextField(
          ofdNotSentController,
          'Не передано в ОФД',
          Icons.cloud_off,
          false,
        ),
        const SizedBox(height: 12),
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
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildSummaryRow('Выручка ООО:', _oooRevenue),
                _buildSummaryRow('Наличные ООО:', _oooCash),
                const Divider(),
                if (_oooExpenses.isNotEmpty) ...[
                  const Text(
                    'Расходы:',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  ..._oooExpenses.asMap().entries.map((entry) {
                    final index = entry.key;
                    final expense = entry.value;
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text('  ${expense.supplierName}'),
                          ),
                          Text(
                            '${expense.amount.toStringAsFixed(0)} ₽',
                            style: const TextStyle(color: Colors.red),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close, size: 20),
                            onPressed: () => _removeOooExpense(index),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                          ),
                        ],
                      ),
                    );
                  }),
                  const Divider(),
                  _buildSummaryRow('Итого расходов:', _oooTotalExpenses, isRed: true),
                ],
                const Divider(),
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
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: _addOooExpense,
            icon: const Icon(Icons.add),
            label: const Text('Добавить расход'),
            style: ElevatedButton.styleFrom(
              backgroundColor: _primaryColor,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
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
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildSummaryRow('Выручка ИП:', _ipRevenue),
                _buildSummaryRow('Наличные ИП:', _ipCash),
                const Divider(),
                if (_expenses.isNotEmpty) ...[
                  const Text(
                    'Расходы:',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  ..._expenses.asMap().entries.map((entry) {
                    final index = entry.key;
                    final expense = entry.value;
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text('  ${expense.supplierName}'),
                          ),
                          Text(
                            '${expense.amount.toStringAsFixed(0)} ₽',
                            style: const TextStyle(color: Colors.red),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close, size: 20),
                            onPressed: () => _removeExpense(index),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                          ),
                        ],
                      ),
                    );
                  }),
                  const Divider(),
                  _buildSummaryRow('Итого расходов:', _totalExpenses, isRed: true),
                ],
                const Divider(),
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
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: _addExpense,
            icon: const Icon(Icons.add),
            label: const Text('Добавить расход'),
            style: ElevatedButton.styleFrom(
              backgroundColor: _primaryColor,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
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
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
            ),
          ),
          Text(
            '${value.toStringAsFixed(0)} ₽',
            style: TextStyle(
              fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
              color: isRed ? Colors.red : (isGreen ? Colors.green : null),
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
    bool isMoney, {
    String? helperText,
  }) {
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
      child: TextFormField(
        controller: controller,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
        decoration: InputDecoration(
          hintText: label,
          hintStyle: TextStyle(color: Colors.grey.shade400),
          prefixIcon: Icon(
            icon,
            color: isMoney ? Colors.teal.shade700 : Colors.blueGrey.shade700,
          ),
          suffixText: isMoney ? '₽' : null,
          suffixStyle: TextStyle(
            color: Colors.teal.shade700,
            fontWeight: FontWeight.bold,
            fontSize: 16,
          ),
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
          filled: true,
          fillColor: Colors.white,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        ),
        onChanged: (_) => setState(() {}),
      ),
    );
  }

  Widget _buildSummaryStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Итоговый отчет',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(
          '${widget.shopAddress}',
          style: TextStyle(color: Colors.grey[600]),
        ),
        Text(
          '${_shiftType == 'morning' ? 'Утренняя' : 'Вечерняя'} смена',
          style: TextStyle(color: Colors.grey[600]),
        ),
        const SizedBox(height: 16),

        // ООО секция
        Card(
          color: Colors.blue[50],
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'ООО',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const Divider(),
                _buildSummaryRow('Выручка:', _oooRevenue),
                _buildSummaryRow('Наличные:', _oooCash),
                if (_oooExpenses.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  const Text('Расходы:', style: TextStyle(fontWeight: FontWeight.bold)),
                  ..._oooExpenses.map((e) => Padding(
                    padding: const EdgeInsets.only(left: 8, top: 4),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('- ${e.supplierName}'),
                        Text(
                          '-${e.amount.toStringAsFixed(0)} ₽',
                          style: const TextStyle(color: Colors.red),
                        ),
                      ],
                    ),
                  )),
                ],
                const Divider(),
                _buildSummaryRow('В конверте:', _oooEnvelopeAmount, isBold: true, isGreen: true),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),

        // ИП секция
        Card(
          color: Colors.orange[50],
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'ИП',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const Divider(),
                _buildSummaryRow('Выручка:', _ipRevenue),
                _buildSummaryRow('Наличные:', _ipCash),
                if (_expenses.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  const Text('Расходы:', style: TextStyle(fontWeight: FontWeight.bold)),
                  ..._expenses.map((e) => Padding(
                    padding: const EdgeInsets.only(left: 8, top: 4),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('- ${e.supplierName}'),
                        Text(
                          '-${e.amount.toStringAsFixed(0)} ₽',
                          style: const TextStyle(color: Colors.red),
                        ),
                      ],
                    ),
                  )),
                ],
                const Divider(),
                _buildSummaryRow('В конверте:', _ipEnvelopeAmount, isBold: true, isGreen: true),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),

        // Итого
        Card(
          color: _primaryColor.withOpacity(0.1),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'ИТОГО В КОНВЕРТАХ:',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                Text(
                  '${_totalEnvelopeAmount.toStringAsFixed(0)} ₽',
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: _primaryColor,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildNavigationButtons() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.2),
            blurRadius: 4,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Row(
        children: [
          if (_currentStep > 0)
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _prevStep,
                icon: const Icon(Icons.arrow_back),
                label: const Text('Назад'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
              ),
            ),
          if (_currentStep > 0) const SizedBox(width: 16),
          Expanded(
            child: _currentStep == _totalSteps - 1
                ? ElevatedButton.icon(
                    onPressed: _isSaving ? null : _submitReport,
                    icon: _isSaving
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.check),
                    label: Text(_isSaving ? 'Отправка...' : 'Отправить'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                  )
                : ElevatedButton.icon(
                    onPressed: _nextStep,
                    icon: const Icon(Icons.arrow_forward),
                    label: const Text('Далее'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _primaryColor,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
