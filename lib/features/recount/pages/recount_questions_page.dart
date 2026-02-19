import 'dart:io';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import '../../../core/utils/logger.dart';
import '../../../core/services/report_notification_service.dart';
import '../models/recount_question_model.dart';
import '../models/recount_answer_model.dart';
import '../models/recount_report_model.dart';
import '../services/recount_service.dart';
import '../../../shared/widgets/app_cached_image.dart';
import '../models/recount_settings_model.dart';
import '../services/recount_points_service.dart';
import '../services/recount_question_service.dart';
import '../../shops/services/shop_service.dart';
import '../../ai_training/services/cigarette_vision_service.dart';
import '../../coffee_machine/widgets/counter_region_selector.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../../core/theme/app_colors.dart';

/// Страница с вопросами пересчета
class RecountQuestionsPage extends StatefulWidget {
  final String employeeName;
  final String shopAddress;
  final String? employeePhone;

  const RecountQuestionsPage({
    super.key,
    required this.employeeName,
    required this.shopAddress,
    this.employeePhone,
  });

  @override
  State<RecountQuestionsPage> createState() => _RecountQuestionsPageState();
}

class _RecountQuestionsPageState extends State<RecountQuestionsPage> {
  static final Color _goldLight = Color(0xFFE8C860);

  List<RecountQuestion>? _selectedQuestions; // 30 выбранных вопросов
  Set<int> _photoRequiredIndices = {}; // Индексы вопросов, для которых требуется фото
  bool _isLoading = true;
  List<RecountAnswer> _answers = [];
  int _currentQuestionIndex = 0;
  // Контроллеры для полей "Больше на" и "Меньше на"
  final TextEditingController _moreByController = TextEditingController();
  final TextEditingController _lessByController = TextEditingController();
  String? _selectedAnswer; // "сходится" или "не сходится"
  String? _photoPath;
  bool _isSubmitting = false;
  bool _isVerifyingAI = false; // Флаг проверки ИИ
  DateTime? _startedAt;
  DateTime? _completedAt;
  bool _answerSaved = false; // Флаг, что ответ сохранен и заблокирован для изменения
  bool _isModelTrained = false; // Обучена ли модель ИИ
  Map<String, double>? _selectedRegion; // Выделенная область для текущего вопроса

  @override
  void initState() {
    super.initState();
    _startedAt = DateTime.now();
    _loadQuestions();
  }

  Future<void> _loadQuestions() async {
    try {
      // СНАЧАЛА загружаем настройки (лёгкий запрос) — до тяжёлых запросов товаров
      int requiredPhotos = 3;
      int questionsCount = 30;

      RecountSettings? settings;
      for (int attempt = 0; attempt < 2; attempt++) {
        try {
          settings = await RecountPointsService.getSettings();
          questionsCount = settings.questionsCount;
          Logger.debug('📦 [RECOUNT] Настройки загружены: questionsCount=$questionsCount');
          break;
        } catch (e) {
          if (attempt == 0) {
            Logger.warning('Ошибка загрузки настроек (попытка 1), повтор...');
            await Future.delayed(Duration(seconds: 1));
          } else {
            Logger.warning('Ошибка загрузки настроек (попытка 2), дефолт: $questionsCount');
          }
        }
      }

      // Загружаем баллы сотрудника для расчёта кол-ва фото
      if (settings != null && widget.employeePhone != null && widget.employeePhone!.isNotEmpty) {
        try {
          final points = await RecountPointsService.getPointsByPhone(widget.employeePhone!);
          if (points != null) {
            requiredPhotos = settings.calculateRequiredPhotos(points.points);
            Logger.debug('Баллы сотрудника: ${points.points}, требуется фото: $requiredPhotos, вопросов: $questionsCount');
          }
        } catch (e) {
          Logger.warning('Ошибка загрузки баллов сотрудника: $e');
        }
      }

      // Пытаемся найти магазин по адресу и загрузить с остатками из DBF
      List<RecountQuestion> allQuestions;

      Logger.debug('📦 [RECOUNT] ========================================');
      Logger.debug('📦 [RECOUNT] Начало загрузки, адрес: "${widget.shopAddress}"');

      final shopId = await ShopService.findShopIdByAddress(widget.shopAddress);
      Logger.debug('📦 [RECOUNT] Результат поиска shopId: $shopId');

      if (shopId != null) {
        // Проверяем, есть ли синхронизированные товары для этого магазина
        final hasProducts = await RecountQuestionService.hasShopProducts(shopId);
        Logger.debug('📦 [RECOUNT] hasShopProducts($shopId) = $hasProducts');

        if (hasProducts) {
          Logger.debug('📦 [RECOUNT] Загружаем товары из DBF каталога магазина...');
          allQuestions = await RecountQuestionService.getQuestionsFromShopProducts(
            shopId: shopId,
            onlyWithStock: true,
          );

          final withStock = allQuestions.where((q) => q.stock > 0).length;
          Logger.debug('📦 [RECOUNT] Загружено из DBF: ${allQuestions.length} товаров, с остатком > 0: $withStock');
        } else {
          Logger.debug('📦 [RECOUNT] Нет синхронизированных товаров, загружаем из общего каталога');
          allQuestions = await RecountQuestion.loadQuestions();
        }
      } else {
        Logger.debug('📦 [RECOUNT] Магазин НЕ НАЙДЕН по адресу, загружаем из общего каталога');
        allQuestions = await RecountQuestion.loadQuestions();
      }

      Logger.debug('📦 [RECOUNT] ========================================');

      // Выбираем вопросы по алгоритму с учетом настройки
      Logger.debug('📦 [RECOUNT] Вызов selectQuestions с totalCount=$questionsCount, всего вопросов: ${allQuestions.length}');
      final selectedQuestions = RecountQuestion.selectQuestions(allQuestions, totalCount: questionsCount);
      Logger.debug('📦 [RECOUNT] После selectQuestions: ${selectedQuestions.length} вопросов');

      // Логируем остатки выбранных товаров и статус AI
      int aiActiveQuestions = selectedQuestions.where((q) => q.isAiActive).length;
      Logger.info('🤖 [RECOUNT] Вопросов с AI активным: $aiActiveQuestions из ${selectedQuestions.length}');
      for (var i = 0; i < min(5, selectedQuestions.length); i++) {
        final q = selectedQuestions[i];
        Logger.info('📦 [RECOUNT] Вопрос $i: "${q.productName}" stock=${q.stock} isAiActive=${q.isAiActive}');
      }

      // Случайно выбираем нужное количество вопросов для фото
      final random = Random();
      final photoIndices = <int>{};
      final maxPhotos = min(requiredPhotos, selectedQuestions.length);
      while (photoIndices.length < maxPhotos) {
        photoIndices.add(random.nextInt(selectedQuestions.length));
      }

      // Проверяем обучена ли модель ИИ (не блокируем загрузку)
      CigaretteVisionService.isModelTrained().then((trained) {
        if (mounted) setState(() => _isModelTrained = trained);
      });

      if (!mounted) return;
      setState(() {
        _selectedQuestions = selectedQuestions;
        _photoRequiredIndices = photoIndices;
        _isLoading = false;
        // Инициализируем список ответов
        _answers = List.generate(
          selectedQuestions.length,
          (index) => RecountAnswer(
            question: selectedQuestions[index].question,
            grade: selectedQuestions[index].grade,
            answer: '',
            photoRequired: photoIndices.contains(index),
            productId: selectedQuestions[index].barcode, // ID товара для обучения ИИ
          ),
        );
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Ошибка загрузки вопросов: $e'),
          backgroundColor: Colors.red,
        ),
      );
      Navigator.pop(context);
    }
  }

  @override
  void dispose() {
    _moreByController.dispose();
    _lessByController.dispose();
    super.dispose();
  }

  Future<void> _takePhoto() async {
    try {
      // Только камера, без выбора из галереи
      final ImagePicker picker = ImagePicker();
      final XFile? photo = await picker.pickImage(
        source: ImageSource.camera, // Только камера
        imageQuality: kIsWeb ? 60 : 85,
        maxWidth: kIsWeb ? 1920 : null,
        maxHeight: kIsWeb ? 1080 : null,
      );

      if (photo != null) {
        String savedPhotoPath;

        if (kIsWeb) {
          final bytes = await photo.readAsBytes();
          final base64String = base64Encode(bytes);
          savedPhotoPath = 'data:image/jpeg;base64,$base64String';
        } else {
          final appDir = await getApplicationDocumentsDirectory();
          final fileName = 'recount_photo_${DateTime.now().millisecondsSinceEpoch}.jpg';
          final savedFile = File(path.join(appDir.path, fileName));
          final bytes = await photo.readAsBytes();
          await savedFile.writeAsBytes(bytes);
          savedPhotoPath = savedFile.path;
        }

        if (!mounted) return;
        setState(() {
          _photoPath = savedPhotoPath;
        });

        // Сразу обновляем ответ с фото для ИИ проверки
        if (_selectedQuestions != null && _currentQuestionIndex < _answers.length) {
          final answer = _answers[_currentQuestionIndex];
          _answers[_currentQuestionIndex] = answer.copyWith(photoPath: savedPhotoPath);

          // Проверяем товар с помощью ИИ сразу после фото
          final question = _selectedQuestions![_currentQuestionIndex];
          if (question.isAiActive) {
            await _verifyWithAI(_currentQuestionIndex);
          }
        }
      }
    } catch (e) {
      Logger.error('Ошибка при выборе фото', e);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _saveAnswer() {
    if (_selectedQuestions == null || _currentQuestionIndex >= _selectedQuestions!.length) {
      return;
    }

    final question = _selectedQuestions![_currentQuestionIndex];
    final isPhotoRequired = _photoRequiredIndices.contains(_currentQuestionIndex);
    // Остаток из DBF
    final stockFromDbf = question.stock;

    RecountAnswer answer;

    if (_selectedAnswer == 'сходится') {
      // При "Сходится" количество берётся автоматически из DBF
      answer = RecountAnswer.matching(
        question: question.question,
        grade: question.grade,
        stockFromDbf: stockFromDbf,
        photoPath: _photoPath,
        photoRequired: isPhotoRequired,
      );
    } else if (_selectedAnswer == 'не сходится') {
      // При "Не сходится" - указываем расхождение
      final moreBy = int.tryParse(_moreByController.text.trim());
      final lessBy = int.tryParse(_lessByController.text.trim());

      answer = RecountAnswer.notMatching(
        question: question.question,
        grade: question.grade,
        stockFromDbf: stockFromDbf,
        moreBy: moreBy != null && moreBy > 0 ? moreBy : null,
        lessBy: lessBy != null && lessBy > 0 ? lessBy : null,
        photoPath: _photoPath,
        photoRequired: isPhotoRequired,
      );
    } else {
      // Ответ не выбран
      return;
    }

    _answers[_currentQuestionIndex] = answer;
    // Помечаем, что ответ сохранен
    if (mounted) setState(() {
      _answerSaved = true;
    });
  }

  /// Новый интерактивный поток проверки с ИИ (по паттерну кофемашины)
  /// Фото → ИИ → "Верно?" → (Обвести область) → Повторный ИИ → Подтвердить/Ввести вручную
  Future<void> _verifyWithAI(int questionIndex) async {
    if (_selectedQuestions == null || questionIndex >= _selectedQuestions!.length) return;

    final question = _selectedQuestions![questionIndex];
    final answer = _answers[questionIndex];

    if (!question.isAiActive || answer.photoPath == null) {
      Logger.debug('ИИ проверка пропущена: isAiActive=${question.isAiActive}, hasPhoto=${answer.photoPath != null}');
      return;
    }

    // Проверяем не отключен ли ИИ для этого товара
    final isAiDisabled = await CigaretteVisionService.isProductAiDisabled(question.barcode);
    if (isAiDisabled) {
      Logger.warning('ИИ отключен для товара ${question.barcode}');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Icon(Icons.warning_amber, color: Colors.white, size: 20),
                SizedBox(width: 8),
                Flexible(child: Text('ИИ отключен для "${question.productName}" (требуется переобучение)')),
              ],
            ),
            backgroundColor: Colors.orange,
            duration: Duration(seconds: 3),
          ),
        );
      }
      return;
    }

    if (mounted) setState(() => _isVerifyingAI = true);

    try {
      // Читаем фото
      Uint8List imageBytes;
      if (kIsWeb) {
        final base64Data = answer.photoPath!.split(',').last;
        imageBytes = base64Decode(base64Data);
      } else {
        imageBytes = await File(answer.photoPath!).readAsBytes();
      }

      // Первый вызов ИИ (без региона)
      Logger.info('🤖 Отправка фото на ИИ для товара: ${question.productName}');
      final result = await CigaretteVisionService.detectAndCountWithTraining(
        imageBytes: imageBytes,
        productId: question.barcode,
        productName: question.productName,
        shopAddress: widget.shopAddress,
        isAiActive: question.isAiActive,
      );

      if (!mounted) return;

      if (result.success && result.count > 0) {
        // ИИ успешно — показываем диалог "ИИ насчитал X. Верно?"
        final aiCount = result.count;
        Logger.info('🤖 ИИ насчитал: $aiCount');

        _answers[questionIndex] = answer.copyWith(
          aiVerified: true,
          aiQuantity: aiCount,
          aiConfidence: result.confidence,
          aiAnnotatedImageUrl: result.annotatedImageUrl,
        );

        await _showAiResultDialog(
          questionIndex: questionIndex,
          aiCount: aiCount,
          question: question,
          imageBytes: imageBytes,
        );
      } else {
        // ИИ не смог — "Перефотографировать" / "Обвести товар"
        Logger.warning('ИИ не смог определить количество: ${result.error}');
        _answers[questionIndex] = answer.copyWith(aiVerified: false);
        await _showAiFailedDialog(
          questionIndex: questionIndex,
          question: question,
          imageBytes: imageBytes,
        );
      }
    } catch (e) {
      Logger.error('Ошибка ИИ проверки', e);
    } finally {
      if (mounted) setState(() => _isVerifyingAI = false);
    }
  }

  /// Диалог "ИИ насчитал X шт. Верно?"
  Future<void> _showAiResultDialog({
    required int questionIndex,
    required int aiCount,
    required RecountQuestion question,
    required Uint8List imageBytes,
  }) async {
    final result = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.emeraldDark,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16.r)),
        title: Row(
          children: [
            Icon(Icons.smart_toy, color: AppColors.gold, size: 28),
            SizedBox(width: 8),
            Flexible(child: Text('Результат ИИ', style: TextStyle(color: Colors.white))),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: double.infinity,
              padding: EdgeInsets.all(16.w),
              decoration: BoxDecoration(
                color: Colors.blue.withOpacity(0.15),
                borderRadius: BorderRadius.circular(12.r),
                border: Border.all(color: Colors.blue.withOpacity(0.3)),
              ),
              child: Column(
                children: [
                  Text(
                    '$aiCount шт.',
                    style: TextStyle(fontSize: 32.sp, fontWeight: FontWeight.bold, color: Colors.white),
                  ),
                  SizedBox(height: 4),
                  Text(
                    'ИИ насчитал',
                    style: TextStyle(fontSize: 14.sp, color: Colors.white.withOpacity(0.6)),
                  ),
                ],
              ),
            ),
            SizedBox(height: 16),
            Text(
              'Количество верное?',
              style: TextStyle(fontSize: 16.sp, color: Colors.white.withOpacity(0.9)),
            ),
          ],
        ),
        actionsAlignment: MainAxisAlignment.spaceEvenly,
        actions: [
          TextButton.icon(
            onPressed: () => Navigator.pop(ctx, 'wrong'),
            icon: Icon(Icons.close, color: Colors.red[300], size: 18),
            label: Text('Неверно', style: TextStyle(color: Colors.red[300])),
          ),
          ElevatedButton.icon(
            onPressed: () => Navigator.pop(ctx, 'correct'),
            icon: Icon(Icons.check, size: 18),
            label: Text('Верно'),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
          ),
        ],
      ),
    );

    if (!mounted) return;

    if (result == 'correct') {
      // Сотрудник подтвердил — сохраняем employeeConfirmedQuantity
      _answers[questionIndex] = _answers[questionIndex].copyWith(
        employeeConfirmedQuantity: aiCount,
        aiMismatch: false,
      );
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(Icons.check_circle, color: Colors.white, size: 20),
              SizedBox(width: 8),
              Text('Подтверждено: $aiCount шт.'),
            ],
          ),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 2),
        ),
      );
    } else {
      // Неверно → предлагаем обвести область или ввести вручную
      await _openRegionAndRetry(
        questionIndex: questionIndex,
        question: question,
        imageBytes: imageBytes,
      );
    }
  }

  /// Диалог "ИИ не смог определить"
  Future<void> _showAiFailedDialog({
    required int questionIndex,
    required RecountQuestion question,
    required Uint8List imageBytes,
  }) async {
    final result = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.emeraldDark,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16.r)),
        title: Row(
          children: [
            Icon(Icons.smart_toy_outlined, color: Colors.orange, size: 28),
            SizedBox(width: 8),
            Flexible(child: Text('ИИ не смог определить', style: TextStyle(color: Colors.white))),
          ],
        ),
        content: Text(
          'Попробуйте обвести товар на фото или сделать новое фото.',
          style: TextStyle(fontSize: 14.sp, color: Colors.white.withOpacity(0.8)),
        ),
        actionsAlignment: MainAxisAlignment.spaceEvenly,
        actions: [
          TextButton.icon(
            onPressed: () => Navigator.pop(ctx, 'retake'),
            icon: Icon(Icons.camera_alt, color: Colors.white70, size: 18),
            label: Text('Перефотографировать', style: TextStyle(color: Colors.white70)),
          ),
          ElevatedButton.icon(
            onPressed: () => Navigator.pop(ctx, 'region'),
            icon: Icon(Icons.crop, size: 18),
            label: Text('Обвести товар'),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.gold),
          ),
        ],
      ),
    );

    if (!mounted) return;

    if (result == 'retake') {
      // Перефото — очищаем и открываем камеру
      if (mounted) setState(() => _photoPath = null);
      _answers[questionIndex] = _answers[questionIndex].copyWith(photoPath: null);
      await _takePhoto();
    } else if (result == 'region') {
      await _openRegionAndRetry(
        questionIndex: questionIndex,
        question: question,
        imageBytes: imageBytes,
      );
    }
  }

  /// Открыть CounterRegionSelector → повторный ИИ с регионом → подтвердить/ввести вручную
  Future<void> _openRegionAndRetry({
    required int questionIndex,
    required RecountQuestion question,
    required Uint8List imageBytes,
  }) async {
    final answer = _answers[questionIndex];
    if (answer.photoPath == null) return;

    // Открываем выбор области
    final region = await CounterRegionSelector.show(
      context,
      imageFile: File(answer.photoPath!),
      initialRegion: _selectedRegion,
    );

    if (region == null || !mounted) return;

    // Сохраняем выбранную область
    if (!mounted) return;
    setState(() => _selectedRegion = region);
    _answers[questionIndex] = _answers[questionIndex].copyWith(selectedRegion: region);

    // Повторный ИИ с регионом
    if (!mounted) return;
    setState(() => _isVerifyingAI = true);
    try {
      Logger.info('🤖 Повторная проверка ИИ с регионом для: ${question.productName}');
      final result = await CigaretteVisionService.detectAndCountWithTraining(
        imageBytes: imageBytes,
        productId: question.barcode,
        productName: question.productName,
        shopAddress: widget.shopAddress,
        isAiActive: question.isAiActive,
        selectedRegion: region,
      );

      if (!mounted) return;

      if (result.success && result.count > 0) {
        final aiCount = result.count;
        Logger.info('🤖 Повторный ИИ с регионом: $aiCount');

        _answers[questionIndex] = _answers[questionIndex].copyWith(
          aiVerified: true,
          aiQuantity: aiCount,
          aiConfidence: result.confidence,
          aiAnnotatedImageUrl: result.annotatedImageUrl,
        );

        // Показываем повторный результат с возможностью ввести вручную
        await _showRetryResultDialog(
          questionIndex: questionIndex,
          aiCount: aiCount,
          question: question,
        );
      } else {
        // ИИ снова не смог — ручной ввод
        Logger.warning('Повторный ИИ не смог определить');
        await _promptManualQuantity(questionIndex: questionIndex, question: question);
      }
    } catch (e) {
      Logger.error('Ошибка повторной ИИ проверки', e);
      await _promptManualQuantity(questionIndex: questionIndex, question: question);
    } finally {
      if (mounted) setState(() => _isVerifyingAI = false);
    }
  }

  /// Диалог повторного результата после региона: "ИИ насчитал Y. Верно?" + "Ввести вручную"
  Future<void> _showRetryResultDialog({
    required int questionIndex,
    required int aiCount,
    required RecountQuestion question,
  }) async {
    final result = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.emeraldDark,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16.r)),
        title: Row(
          children: [
            Icon(Icons.smart_toy, color: AppColors.gold, size: 28),
            SizedBox(width: 8),
            Flexible(child: Text('Повторный результат', style: TextStyle(color: Colors.white))),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: double.infinity,
              padding: EdgeInsets.all(16.w),
              decoration: BoxDecoration(
                color: Colors.blue.withOpacity(0.15),
                borderRadius: BorderRadius.circular(12.r),
                border: Border.all(color: Colors.blue.withOpacity(0.3)),
              ),
              child: Column(
                children: [
                  Text(
                    '$aiCount шт.',
                    style: TextStyle(fontSize: 32.sp, fontWeight: FontWeight.bold, color: Colors.white),
                  ),
                  SizedBox(height: 4),
                  Text(
                    'ИИ насчитал (с выделенной областью)',
                    style: TextStyle(fontSize: 12.sp, color: Colors.white.withOpacity(0.6)),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
            SizedBox(height: 16),
            Text(
              'Количество верное?',
              style: TextStyle(fontSize: 16.sp, color: Colors.white.withOpacity(0.9)),
            ),
          ],
        ),
        actionsAlignment: MainAxisAlignment.spaceEvenly,
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'manual'),
            child: Text('Ввести вручную', style: TextStyle(color: Colors.orange[300])),
          ),
          ElevatedButton.icon(
            onPressed: () => Navigator.pop(ctx, 'correct'),
            icon: Icon(Icons.check, size: 18),
            label: Text('Верно'),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
          ),
        ],
      ),
    );

    if (!mounted) return;

    if (result == 'correct') {
      _answers[questionIndex] = _answers[questionIndex].copyWith(
        employeeConfirmedQuantity: aiCount,
        aiMismatch: false,
      );
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(Icons.check_circle, color: Colors.white, size: 20),
              SizedBox(width: 8),
              Text('Подтверждено: $aiCount шт.'),
            ],
          ),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 2),
        ),
      );
    } else {
      await _promptManualQuantity(questionIndex: questionIndex, question: question);
    }
  }

  /// Диалог ручного ввода количества
  Future<void> _promptManualQuantity({
    required int questionIndex,
    required RecountQuestion question,
  }) async {
    final controller = TextEditingController();
    final result = await showDialog<int?>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.emeraldDark,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16.r)),
        title: Text('Введите количество', style: TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              question.productName,
              style: TextStyle(fontSize: 14.sp, color: Colors.white.withOpacity(0.7)),
              textAlign: TextAlign.center,
            ),
            SizedBox(height: 16),
            TextField(
              controller: controller,
              keyboardType: TextInputType.number,
              autofocus: true,
              style: TextStyle(color: Colors.white, fontSize: 24.sp),
              textAlign: TextAlign.center,
              decoration: InputDecoration(
                hintText: '0',
                hintStyle: TextStyle(color: Colors.white.withOpacity(0.3)),
                filled: true,
                fillColor: Colors.white.withOpacity(0.08),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12.r),
                  borderSide: BorderSide(color: AppColors.gold.withOpacity(0.3)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12.r),
                  borderSide: BorderSide(color: AppColors.gold),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, null),
            child: Text('Пропустить', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            onPressed: () {
              final value = int.tryParse(controller.text.trim());
              Navigator.pop(ctx, value);
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.gold),
            child: Text('Подтвердить'),
          ),
        ],
      ),
    );

    if (!mounted) return;

    if (result != null) {
      _answers[questionIndex] = _answers[questionIndex].copyWith(
        employeeConfirmedQuantity: result,
        aiMismatch: true,
      );
      // Отправляем employeeAnswer на сервер для pending sample
      try {
        await CigaretteVisionService.detectAndCountWithTraining(
          imageBytes: await File(_answers[questionIndex].photoPath!).readAsBytes(),
          productId: question.barcode,
          productName: question.productName,
          shopAddress: widget.shopAddress,
          isAiActive: question.isAiActive,
          employeeAnswer: result,
          selectedRegion: _selectedRegion,
        );
      } catch (_) {}

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(Icons.edit, color: Colors.white, size: 20),
              SizedBox(width: 8),
              Text('Записано: $result шт.'),
            ],
          ),
          backgroundColor: Colors.blue,
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  bool _canProceed() {
    if (_selectedQuestions == null || _currentQuestionIndex >= _selectedQuestions!.length) {
      return false;
    }

    // Если ответ еще не сохранен, проверяем только базовые поля
    if (!_answerSaved) {
      if (_selectedAnswer == null) {
        return false;
      }

      if (_selectedAnswer == 'сходится') {
        // При "Сходится" ничего вводить не нужно - количество берётся из DBF
        return true;
      } else if (_selectedAnswer == 'не сходится') {
        // При "Не сходится" должно быть заполнено ОДНО из полей (но не оба)
        final moreBy = int.tryParse(_moreByController.text.trim());
        final lessBy = int.tryParse(_lessByController.text.trim());

        final hasMoreBy = moreBy != null && moreBy > 0;
        final hasLessBy = lessBy != null && lessBy > 0;

        // Должно быть заполнено ровно одно поле
        if (hasMoreBy && hasLessBy) {
          return false; // Оба заполнены - ошибка
        }
        if (!hasMoreBy && !hasLessBy) {
          return false; // Ни одно не заполнено - ошибка
        }
        return true;
      }
      return true;
    }

    // Если ответ сохранен, проверяем фото (если требуется)
    final isPhotoRequired = _photoRequiredIndices.contains(_currentQuestionIndex);
    if (isPhotoRequired && _photoPath == null) {
      return false;
    }

    return true;
  }

  Future<void> _nextQuestion() async {
    // Если ответ еще не сохранен, сохраняем его
    if (!_answerSaved) {
      if (!_canProceed()) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Пожалуйста, заполните все поля'),
            backgroundColor: Colors.orange,
          ),
        );
        return;
      }
      _saveAnswer();
      
      // Если требуется фото, показываем запрос и не переходим дальше
      final isPhotoRequired = _photoRequiredIndices.contains(_currentQuestionIndex);
      if (isPhotoRequired) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Пожалуйста, сделайте фото для подтверждения'),
            backgroundColor: Colors.orange,
            duration: Duration(seconds: 3),
          ),
        );
        return; // Остаемся на этом вопросе, пока не сделают фото
      }
    } else {
      // Ответ сохранен, проверяем фото (если требуется)
      if (!_canProceed()) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Пожалуйста, сделайте фото для подтверждения'),
            backgroundColor: Colors.orange,
          ),
        );
        return;
      }
    }

    // Обновляем фото в сохраненном ответе
    if (_answerSaved && _photoPath != null) {
      final answer = _answers[_currentQuestionIndex];
      _answers[_currentQuestionIndex] = answer.copyWith(photoPath: _photoPath);
    }

    // Примечание: ИИ проверка теперь вызывается сразу после съёмки фото в _takePhoto()
    // Дополнительный вызов здесь не нужен

    if (_currentQuestionIndex < _selectedQuestions!.length - 1) {
      if (mounted) setState(() {
        _currentQuestionIndex++;
        _selectedAnswer = null;
        _moreByController.clear();
        _lessByController.clear();
        _photoPath = null;
        _answerSaved = false; // Сбрасываем флаг для нового вопроса
        _selectedRegion = null; // Сбрасываем регион для нового вопроса

        // Загружаем сохраненный ответ, если есть
        if (_currentQuestionIndex < _answers.length) {
          final savedAnswer = _answers[_currentQuestionIndex];
          if (savedAnswer.answer.isNotEmpty) {
            // Если ответ уже сохранен, показываем его как заблокированный
            _selectedAnswer = savedAnswer.answer;
            _answerSaved = true; // Помечаем как сохраненный
            if (savedAnswer.answer == 'не сходится') {
              _moreByController.text = savedAnswer.moreBy?.toString() ?? '';
              _lessByController.text = savedAnswer.lessBy?.toString() ?? '';
            }
            _photoPath = savedAnswer.photoPath;
          }
        }
      });
    } else {
      // Последний вопрос - завершаем
      await _submitReport();
    }
  }

  Future<void> _submitReport() async {
    if (!_canProceed()) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Пожалуйста, заполните все поля'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    _saveAnswer();

    // Проверяем, что все вопросы отвечены
    for (var i = 0; i < _answers.length; i++) {
      if (_answers[i].answer.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Пожалуйста, ответьте на вопрос ${i + 1}'),
            backgroundColor: Colors.orange,
          ),
        );
        if (mounted) setState(() {
          _currentQuestionIndex = i;
        });
        return;
      }
    }

    if (mounted) setState(() {
      _isSubmitting = true;
      _completedAt = DateTime.now();
    });

    try {
      final duration = _completedAt!.difference(_startedAt!);
      
      final report = RecountReport(
        id: RecountReport.generateId(
          widget.employeeName,
          widget.shopAddress,
          _startedAt!,
        ),
        employeeName: widget.employeeName,
        shopAddress: widget.shopAddress,
        employeePhone: widget.employeePhone,
        startedAt: _startedAt!,
        completedAt: _completedAt!,
        duration: duration,
        answers: _answers,
      );

      final success = await RecountService.createReport(report);

      if (mounted) {
        if (success) {
          // Отправляем уведомление админу о новом отчёте
          await ReportNotificationService.createNotification(
            reportType: ReportType.recount,
            reportId: report.id,
            employeeName: widget.employeeName,
            shopName: widget.shopAddress,
          );

          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Отчет успешно отправлен'),
              backgroundColor: Colors.green,
            ),
          );
          Navigator.of(context).popUntil((route) => route.isFirst);
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Ошибка отправки отчета. Попробуйте позже'),
              backgroundColor: Colors.red,
            ),
          );
          if (mounted) setState(() {
            _isSubmitting = false;
          });
        }
      }
    } catch (e) {
      Logger.error('Ошибка отправки отчета', e);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
        if (mounted) setState(() {
          _isSubmitting = false;
        });
      }
    }
  }

  Widget _buildAppBar(BuildContext context, String title, {String? subtitle}) {
    return Padding(
      padding: EdgeInsets.fromLTRB(8.w, 8.h, 8.w, 4.h),
      child: Row(
        children: [
          Container(
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.08),
              borderRadius: BorderRadius.circular(12.r),
              border: Border.all(color: Colors.white.withOpacity(0.1)),
            ),
            child: IconButton(
              icon: Icon(Icons.arrow_back_ios_new, color: Colors.white.withOpacity(0.8), size: 20),
              onPressed: () => Navigator.pop(context),
            ),
          ),
          SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: TextStyle(color: Colors.white, fontSize: 18.sp, fontWeight: FontWeight.w600)),
                if (subtitle != null)
                  Text(subtitle, style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 12.sp)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        backgroundColor: AppColors.night,
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
            child: Column(
              children: [
                _buildAppBar(context, 'Пересчет товаров'),
                Expanded(
                  child: Center(child: CircularProgressIndicator(color: AppColors.gold)),
                ),
              ],
            ),
          ),
        ),
      );
    }

    if (_selectedQuestions == null || _selectedQuestions!.isEmpty) {
      return Scaffold(
        backgroundColor: AppColors.night,
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
            child: Column(
              children: [
                _buildAppBar(context, 'Пересчет товаров'),
                Expanded(
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.inventory_2_outlined, size: 64, color: Colors.white.withOpacity(0.3)),
                        SizedBox(height: 16),
                        Text(
                          'Вопросы не найдены',
                          style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 18.sp),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final question = _selectedQuestions![_currentQuestionIndex];
    final isPhotoRequired = _photoRequiredIndices.contains(_currentQuestionIndex);
    final progress = (_currentQuestionIndex + 1) / _selectedQuestions!.length;

    // Цвета грейда
    final gradeColor = question.grade == 1
        ? Color(0xFFEF5350)
        : question.grade == 2
            ? Colors.orange
            : AppColors.blue;

    return Scaffold(
      backgroundColor: AppColors.night,
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [AppColors.emerald, AppColors.emeraldDark, AppColors.night],
            stops: [0.0, 0.25, 1.0],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              // AppBar
              _buildAppBar(
                context,
                'Вопрос ${_currentQuestionIndex + 1} из ${_selectedQuestions!.length}',
                subtitle: widget.shopAddress,
              ),
              // Прогресс-бар
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 6.h),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4.r),
                  child: LinearProgressIndicator(
                    value: progress,
                    backgroundColor: Colors.white.withOpacity(0.1),
                    valueColor: AlwaysStoppedAnimation<Color>(AppColors.gold.withOpacity(0.8)),
                    minHeight: 4,
                  ),
                ),
              ),
              SizedBox(height: 4),
              // Контент
              Expanded(
                child: SingleChildScrollView(
                  padding: EdgeInsets.fromLTRB(16.w, 4.h, 16.w, 16.h),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Карточка вопроса
                      Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              AppColors.gold.withOpacity(0.12),
                              AppColors.gold.withOpacity(0.04),
                            ],
                          ),
                          borderRadius: BorderRadius.circular(18.r),
                          border: Border.all(color: AppColors.gold.withOpacity(0.25)),
                        ),
                        child: Padding(
                          padding: EdgeInsets.all(18.w),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Бейдж грейда
                              Row(
                                children: [
                                  Container(
                                    padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 5.h),
                                    decoration: BoxDecoration(
                                      color: gradeColor.withOpacity(0.15),
                                      borderRadius: BorderRadius.circular(10.r),
                                      border: Border.all(color: gradeColor.withOpacity(0.3)),
                                    ),
                                    child: Text(
                                      'Грейд ${question.grade}',
                                      style: TextStyle(
                                        color: gradeColor,
                                        fontWeight: FontWeight.w600,
                                        fontSize: 12.sp,
                                        letterSpacing: 0.5,
                                      ),
                                    ),
                                  ),
                                  if (question.isAiActive) ...[
                                    SizedBox(width: 8),
                                    Container(
                                      padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 5.h),
                                      decoration: BoxDecoration(
                                        color: _isModelTrained
                                            ? Colors.green.withOpacity(0.12)
                                            : Colors.orange.withOpacity(0.12),
                                        borderRadius: BorderRadius.circular(10.r),
                                        border: Border.all(
                                          color: _isModelTrained
                                              ? Colors.green.withOpacity(0.25)
                                              : Colors.orange.withOpacity(0.25),
                                        ),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            _isModelTrained ? Icons.smart_toy : Icons.smart_toy_outlined,
                                            size: 12,
                                            color: _isModelTrained ? Colors.green[300] : Colors.orange[300],
                                          ),
                                          SizedBox(width: 4),
                                          Text(
                                            _isModelTrained ? 'AI проверит' : 'AI не обучен',
                                            style: TextStyle(
                                              color: _isModelTrained ? Colors.green[300] : Colors.orange[300],
                                              fontSize: 11.sp,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                              SizedBox(height: 16),
                              // Остаток из DBF
                              Container(
                                width: double.infinity,
                                padding: EdgeInsets.symmetric(vertical: 14.h, horizontal: 16.w),
                                decoration: BoxDecoration(
                                  color: AppColors.gold.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(14.r),
                                  border: Border.all(color: AppColors.gold.withOpacity(0.25)),
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.inventory_2_rounded, color: AppColors.gold, size: 22),
                                    SizedBox(width: 10),
                                    Text(
                                      'По программе: ${question.stock} шт',
                                      style: TextStyle(
                                        fontSize: 20.sp,
                                        fontWeight: FontWeight.w700,
                                        color: _goldLight,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              SizedBox(height: 16),
                              // Название товара + фото / заглушка
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(10.r),
                                    child: question.productPhotoUrl != null
                                        ? AppCachedImage(
                                            imageUrl: question.productPhotoUrl!,
                                            width: 60,
                                            height: 60,
                                            fit: BoxFit.cover,
                                          )
                                        : Container(
                                            width: 60,
                                            height: 60,
                                            decoration: BoxDecoration(
                                              color: AppColors.gold.withOpacity(0.1),
                                              borderRadius: BorderRadius.circular(10.r),
                                              border: Border.all(color: AppColors.gold.withOpacity(0.2)),
                                            ),
                                            child: Icon(
                                              Icons.inventory_2_outlined,
                                              color: AppColors.gold.withOpacity(0.5),
                                              size: 28,
                                            ),
                                          ),
                                  ),
                                  SizedBox(width: 14),
                                  Expanded(
                                    child: Text(
                                      question.question,
                                      style: TextStyle(
                                        fontSize: 18.sp,
                                        fontWeight: FontWeight.w600,
                                        height: 1.4,
                                        color: Colors.white.withOpacity(0.95),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                      SizedBox(height: 16),
                      // Выбор ответа
                      Container(
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.06),
                          borderRadius: BorderRadius.circular(16.r),
                          border: Border.all(color: Colors.white.withOpacity(0.1)),
                        ),
                        child: Padding(
                          padding: EdgeInsets.all(16.w),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(
                                'Ответ:',
                                style: TextStyle(
                                  fontSize: 15.sp,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.white.withOpacity(0.6),
                                  letterSpacing: 0.5,
                                ),
                              ),
                              SizedBox(height: 12),
                              Row(
                                children: [
                                  Expanded(
                                    child: _buildAnswerButton(
                                      label: 'Сходится',
                                      icon: Icons.check_circle_rounded,
                                      isSelected: _selectedAnswer == 'сходится',
                                      color: AppColors.success,
                                      onPressed: _answerSaved ? null : () {
                                        if (mounted) setState(() {
                                          _selectedAnswer = 'сходится';
                                        });
                                      },
                                    ),
                                  ),
                                  SizedBox(width: 12),
                                  Expanded(
                                    child: _buildAnswerButton(
                                      label: 'Не сходится',
                                      icon: Icons.cancel_rounded,
                                      isSelected: _selectedAnswer == 'не сходится',
                                      color: Color(0xFFEF5350),
                                      onPressed: _answerSaved ? null : () {
                                        if (mounted) setState(() {
                                          _selectedAnswer = 'не сходится';
                                        });
                                      },
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                      SizedBox(height: 12),
                      // При "Сходится" - подтверждение
                      if (_selectedAnswer == 'сходится')
                        Container(
                          padding: EdgeInsets.all(16.w),
                          decoration: BoxDecoration(
                            color: AppColors.success.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(14.r),
                            border: Border.all(color: AppColors.success.withOpacity(0.25)),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.check_circle_rounded, color: AppColors.success, size: 28),
                              SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  'Количество ${question.stock} шт подтверждено',
                                  style: TextStyle(
                                    fontSize: 15.sp,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.success,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      // При "Не сходится" - поля расхождений
                      if (_selectedAnswer == 'не сходится')
                        Container(
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.06),
                            borderRadius: BorderRadius.circular(16.r),
                            border: Border.all(color: Colors.white.withOpacity(0.1)),
                          ),
                          child: Padding(
                            padding: EdgeInsets.all(16.w),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Text(
                                  'Укажите расхождение (заполните ОДНО поле):',
                                  style: TextStyle(
                                    fontSize: 13.sp,
                                    color: Colors.white.withOpacity(0.5),
                                  ),
                                ),
                                SizedBox(height: 16),
                                // Поле "Больше на"
                                _buildDiscrepancyField(
                                  icon: Icons.add_circle_rounded,
                                  iconColor: AppColors.blue,
                                  label: 'Больше на:',
                                  controller: _moreByController,
                                  enabled: !_answerSaved,
                                  fillColor: AppColors.blue,
                                  onChanged: (value) {
                                    if (value.isNotEmpty && int.tryParse(value) != null && int.parse(value) > 0) {
                                      _lessByController.clear();
                                    }
                                    if (mounted) setState(() {});
                                  },
                                ),
                                SizedBox(height: 14),
                                // Поле "Меньше на"
                                _buildDiscrepancyField(
                                  icon: Icons.remove_circle_rounded,
                                  iconColor: Color(0xFFEF5350),
                                  label: 'Меньше на:',
                                  controller: _lessByController,
                                  enabled: !_answerSaved,
                                  fillColor: Color(0xFFEF5350),
                                  onChanged: (value) {
                                    if (value.isNotEmpty && int.tryParse(value) != null && int.parse(value) > 0) {
                                      _moreByController.clear();
                                    }
                                    if (mounted) setState(() {});
                                  },
                                ),
                                // Предпросмотр результата
                                if (_moreByController.text.isNotEmpty || _lessByController.text.isNotEmpty) ...[
                                  SizedBox(height: 14),
                                  Container(
                                    padding: EdgeInsets.symmetric(vertical: 12.h, horizontal: 16.w),
                                    decoration: BoxDecoration(
                                      color: AppColors.gold.withOpacity(0.1),
                                      borderRadius: BorderRadius.circular(12.r),
                                      border: Border.all(color: AppColors.gold.withOpacity(0.25)),
                                    ),
                                    child: Builder(
                                      builder: (context) {
                                        final moreBy = int.tryParse(_moreByController.text) ?? 0;
                                        final lessBy = int.tryParse(_lessByController.text) ?? 0;
                                        final actualBalance = question.stock + moreBy - lessBy;
                                        return Row(
                                          mainAxisAlignment: MainAxisAlignment.center,
                                          children: [
                                            Icon(Icons.summarize_rounded, size: 18, color: AppColors.gold),
                                            SizedBox(width: 8),
                                            Text(
                                              'По факту: $actualBalance шт',
                                              style: TextStyle(
                                                fontSize: 16.sp,
                                                fontWeight: FontWeight.w700,
                                                color: _goldLight,
                                              ),
                                            ),
                                          ],
                                        );
                                      },
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      // Фото (показываем только после сохранения ответа, если требуется)
                      if (_answerSaved && isPhotoRequired) ...[
                        SizedBox(height: 12),
                        Container(
                          decoration: BoxDecoration(
                            color: Colors.orange.withOpacity(0.08),
                            borderRadius: BorderRadius.circular(16.r),
                            border: Border.all(color: Colors.orange.withOpacity(0.25)),
                          ),
                          child: Padding(
                            padding: EdgeInsets.all(16.w),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Row(
                                  children: [
                                    Icon(Icons.camera_alt_rounded, color: Colors.orange[300], size: 22),
                                    SizedBox(width: 8),
                                    Flexible(
                                      child: Text(
                                        'Требуется фото для подтверждения',
                                        style: TextStyle(
                                          fontSize: 15.sp,
                                          fontWeight: FontWeight.w600,
                                          color: Colors.orange[300],
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                SizedBox(height: 12),
                                if (_photoPath != null)
                                  Container(
                                    height: 200,
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(12.r),
                                      border: Border.all(color: Colors.white.withOpacity(0.15), width: 2),
                                    ),
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(12.r),
                                      child: kIsWeb
                                          ? AppCachedImage(imageUrl: _photoPath!, fit: BoxFit.cover)
                                          : Image.file(File(_photoPath!), fit: BoxFit.cover),
                                    ),
                                  )
                                else
                                  ElevatedButton.icon(
                                    onPressed: _takePhoto,
                                    icon: Icon(Icons.camera_alt_rounded, size: 20),
                                    label: Text('Сделать фото', style: TextStyle(fontWeight: FontWeight.w600)),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.orange.withOpacity(0.2),
                                      foregroundColor: Colors.orange[300],
                                      padding: EdgeInsets.symmetric(vertical: 14.h),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12.r),
                                        side: BorderSide(color: Colors.orange.withOpacity(0.3)),
                                      ),
                                      elevation: 0,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              // Кнопки навигации
              Container(
                padding: EdgeInsets.fromLTRB(16.w, 12.h, 16.w, 16.h),
                decoration: BoxDecoration(
                  color: AppColors.night.withOpacity(0.9),
                  border: Border(top: BorderSide(color: Colors.white.withOpacity(0.06))),
                ),
                child: Row(
                  children: [
                    if (_currentQuestionIndex > 0)
                      Container(
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.06),
                          borderRadius: BorderRadius.circular(12.r),
                          border: Border.all(color: Colors.white.withOpacity(0.1)),
                        ),
                        child: IconButton(
                          onPressed: () {
                            if (mounted) setState(() {
                              _currentQuestionIndex--;
                              _selectedAnswer = null;
                              _moreByController.clear();
                              _lessByController.clear();
                              _photoPath = null;
                              _answerSaved = false;

                              if (_currentQuestionIndex < _answers.length) {
                                final savedAnswer = _answers[_currentQuestionIndex];
                                if (savedAnswer.answer.isNotEmpty) {
                                  _selectedAnswer = savedAnswer.answer;
                                  _answerSaved = true;
                                  if (savedAnswer.answer == 'не сходится') {
                                    _moreByController.text = savedAnswer.moreBy?.toString() ?? '';
                                    _lessByController.text = savedAnswer.lessBy?.toString() ?? '';
                                  }
                                  _photoPath = savedAnswer.photoPath;
                                }
                              }
                            });
                          },
                          icon: Icon(Icons.arrow_back_rounded, color: Colors.white.withOpacity(0.7)),
                        ),
                      ),
                    if (_currentQuestionIndex > 0) SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: (_isSubmitting || _isVerifyingAI) ? null : _nextQuestion,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _answerSaved && _photoRequiredIndices.contains(_currentQuestionIndex) && _photoPath == null
                              ? Colors.orange.withOpacity(0.2)
                              : AppColors.gold.withOpacity(0.2),
                          foregroundColor: _answerSaved && _photoRequiredIndices.contains(_currentQuestionIndex) && _photoPath == null
                              ? Colors.orange[300]
                              : AppColors.gold,
                          disabledBackgroundColor: Colors.white.withOpacity(0.05),
                          disabledForegroundColor: Colors.white.withOpacity(0.3),
                          padding: EdgeInsets.symmetric(vertical: 16.h),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14.r),
                            side: BorderSide(
                              color: _answerSaved && _photoRequiredIndices.contains(_currentQuestionIndex) && _photoPath == null
                                  ? Colors.orange.withOpacity(0.4)
                                  : AppColors.gold.withOpacity(0.4),
                            ),
                          ),
                          elevation: 0,
                        ),
                        child: (_isSubmitting || _isVerifyingAI)
                            ? Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  SizedBox(
                                    height: 20,
                                    width: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      valueColor: AlwaysStoppedAnimation<Color>(AppColors.gold),
                                    ),
                                  ),
                                  if (_isVerifyingAI) ...[
                                    SizedBox(width: 10),
                                    Text('ИИ проверяет...', style: TextStyle(color: _goldLight, fontSize: 14.sp)),
                                  ],
                                ],
                              )
                            : Text(
                                !_answerSaved
                                    ? 'Сохранить ответ'
                                    : _photoRequiredIndices.contains(_currentQuestionIndex) && _photoPath == null
                                        ? 'Сделать фото'
                                        : _currentQuestionIndex < _selectedQuestions!.length - 1
                                            ? 'Следующий вопрос'
                                            : 'Завершить пересчет',
                                style: TextStyle(
                                  fontSize: 16.sp,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Кнопка ответа "Сходится" / "Не сходится"
  Widget _buildAnswerButton({
    required String label,
    required IconData icon,
    required bool isSelected,
    required Color color,
    required VoidCallback? onPressed,
  }) {
    return GestureDetector(
      onTap: onPressed,
      child: AnimatedContainer(
        duration: Duration(milliseconds: 200),
        padding: EdgeInsets.symmetric(vertical: 16.h, horizontal: 8.w),
        decoration: BoxDecoration(
          color: isSelected ? color.withOpacity(0.15) : Colors.white.withOpacity(0.04),
          borderRadius: BorderRadius.circular(14.r),
          border: Border.all(
            color: isSelected ? color.withOpacity(0.5) : Colors.white.withOpacity(0.1),
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Column(
          children: [
            Icon(icon, color: isSelected ? color : Colors.white.withOpacity(0.4), size: 28),
            SizedBox(height: 6),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 15.sp,
                  fontWeight: FontWeight.w600,
                  color: isSelected ? color : Colors.white.withOpacity(0.5),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Поле расхождения
  Widget _buildDiscrepancyField({
    required IconData icon,
    required Color iconColor,
    required String label,
    required TextEditingController controller,
    required bool enabled,
    required Color fillColor,
    required ValueChanged<String> onChanged,
  }) {
    return Row(
      children: [
        Icon(icon, color: iconColor, size: 24),
        SizedBox(width: 10),
        Expanded(
          flex: 2,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 15.sp,
              fontWeight: FontWeight.w600,
              color: Colors.white.withOpacity(0.8),
            ),
          ),
        ),
        Expanded(
          flex: 3,
          child: TextField(
            controller: controller,
            keyboardType: TextInputType.number,
            enabled: enabled,
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white, fontSize: 16.sp, fontWeight: FontWeight.w600),
            decoration: InputDecoration(
              hintText: '0',
              hintStyle: TextStyle(color: Colors.white.withOpacity(0.25)),
              suffixText: 'шт',
              suffixStyle: TextStyle(color: Colors.white.withOpacity(0.4)),
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
                borderSide: BorderSide(color: fillColor, width: 2),
              ),
              filled: true,
              fillColor: controller.text.isNotEmpty
                  ? fillColor.withOpacity(0.08)
                  : Colors.white.withOpacity(0.04),
              contentPadding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 12.h),
            ),
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }
}
