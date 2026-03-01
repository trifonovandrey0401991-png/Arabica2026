import 'dart:async' show TimeoutException;
import 'dart:io';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:shared_preferences/shared_preferences.dart';
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
import '../../ai_training/pages/cigarette_annotation_page.dart';
import '../../ai_training/models/cigarette_training_model.dart';
import '../../coffee_machine/widgets/counter_region_selector.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../../core/theme/app_colors.dart';
import '../../ai_training/services/ai_toggle_service.dart';

/// Страница с вопросами пересчета
class RecountQuestionsPage extends StatefulWidget {
  final String employeeName;
  final String shopAddress;
  final String? employeePhone;
  final bool dbfStale;

  const RecountQuestionsPage({
    super.key,
    required this.employeeName,
    required this.shopAddress,
    this.employeePhone,
    this.dbfStale = false,
  });

  @override
  State<RecountQuestionsPage> createState() => _RecountQuestionsPageState();
}

class _RecountQuestionsPageState extends State<RecountQuestionsPage> {
  static final Color _goldLight = Color(0xFFE8C860);

  List<RecountQuestion>? _selectedQuestions; // 30 выбранных вопросов
  Set<int> _photoRequiredIndices = {}; // Индексы вопросов, для которых требуется фото
  bool _isLoading = true;
  String? _loadError;
  List<RecountAnswer> _answers = [];
  int _currentQuestionIndex = 0;
  // Контроллеры для полей "Больше на" и "Меньше на"
  final TextEditingController _moreByController = TextEditingController();
  final TextEditingController _lessByController = TextEditingController();
  final TextEditingController _manualQuantityController = TextEditingController();
  String? _selectedAnswer; // "сходится" или "не сходится"
  String? _photoPath;
  bool _isSubmitting = false;
  bool _submitFailed = false; // Флаг: последняя отправка провалилась
  bool _isVerifyingAI = false; // Флаг проверки ИИ
  DateTime? _startedAt;
  DateTime? _completedAt;
  bool _answerSaved = false; // Флаг, что ответ сохранен и заблокирован для изменения
  bool _isModelTrained = false; // Обучена ли модель ИИ
  int _aiActiveCount = 0; // Кол-во вопросов с AI (для баннера)
  bool _aiBannerDismissed = false; // Баннер закрыт пользователем
  Map<String, double>? _selectedRegion; // Выделенная область для текущего вопроса
  double _uploadProgress = 0.0; // Прогресс отправки отчёта (0.0–1.0)

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
      final questionsWithAi = aiActiveQuestions; // захватываем до async
      AiToggleService.isEnabled('cigaretteVision').then((enabled) async {
        if (!enabled) {
          Logger.info('[Recount AI] Cigarette Vision disabled via toggle');
          return;
        }
        final trained = await CigaretteVisionService.isModelTrained();
        if (!mounted) return;
        setState(() => _isModelTrained = trained);
        if (trained && questionsWithAi == 0) {
          // Фаза 2.2: модель обучена, но в этом магазине нет AI-товаров
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  Icon(Icons.info_outline, color: Colors.white, size: 20),
                  SizedBox(width: 8),
                  Flexible(child: Text('Для этого магазина нет товаров с ИИ — пересчёт без автоматической проверки')),
                ],
              ),
              backgroundColor: Colors.blueGrey[700],
              duration: Duration(seconds: 5),
            ),
          );
        } else if (!trained && questionsWithAi > 0) {
          // Фаза 4.1: есть AI-товары, но модель ещё не обучена
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  Icon(Icons.smart_toy_outlined, color: Colors.white, size: 20),
                  SizedBox(width: 8),
                  Flexible(child: Text('ИИ ещё обучается — для $questionsWithAi тов. потребуется ввод вручную')),
                ],
              ),
              backgroundColor: Colors.orange[700],
              duration: Duration(seconds: 5),
            ),
          );
        }
      });

      if (!mounted) return;
      setState(() {
        _selectedQuestions = selectedQuestions;
        _photoRequiredIndices = photoIndices;
        _aiActiveCount = aiActiveQuestions;
        // _isLoading остаётся true — страница не показывается до конца восстановления
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

      // Предлагаем восстановить черновик (B1) — пока спиннер ещё виден
      await _offerDraftRestore();

      // Только после ответа на диалог показываем страницу
      if (mounted) setState(() => _isLoading = false);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _loadError = e.toString();
      });
    }
  }

  @override
  void dispose() {
    _moreByController.dispose();
    _lessByController.dispose();
    _manualQuantityController.dispose();
    super.dispose();
  }

  // ─── Черновик пересчёта (B1) ───────────────────────────────────────────────

  String get _draftKey =>
      'recount_draft_${widget.shopAddress}_${widget.employeeName}';

  Future<void> _saveDraft() async {
    if (_answers.isEmpty) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final json = jsonEncode(_answers.map((a) => a.toJson()).toList());
      await prefs.setString(_draftKey, json);
    } catch (e) {
      Logger.warning('Не удалось сохранить черновик: $e');
    }
  }

  Future<void> _deleteDraft() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_draftKey);
    } catch (_) {}
  }

  Future<void> _offerDraftRestore() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(_draftKey);
      if (saved == null || !mounted) return;

      final restored = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          backgroundColor: AppColors.emerald,
          title: Text('Восстановить прогресс?',
              style: TextStyle(color: Colors.white)),
          content: Text(
            'Найден незавершённый пересчёт. Продолжить с того места?',
            style: TextStyle(color: Colors.white70),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text('Начать заново', style: TextStyle(color: Colors.white54)),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text('Продолжить'),
            ),
          ],
        ),
      );

      if (restored == true && mounted) {
        final decoded = jsonDecode(saved) as List<dynamic>;
        final restoredAnswers =
            decoded.map((j) => RecountAnswer.fromJson(j as Map<String, dynamic>)).toList();

        // Применяем только ответы, индексы которых совпадают
        final count = restoredAnswers.length < _answers.length
            ? restoredAnswers.length
            : _answers.length;

        setState(() {
          for (int i = 0; i < count; i++) {
            if (restoredAnswers[i].answer.isNotEmpty) {
              _answers[i] = restoredAnswers[i];
            }
          }
          // Переходим к первому неотвеченному вопросу
          final firstUnanswered =
              _answers.indexWhere((a) => a.answer.isEmpty);
          if (firstUnanswered != -1) {
            _currentQuestionIndex = firstUnanswered;
          }
        });
      } else if (restored == false) {
        await _deleteDraft();
      }
    } catch (e) {
      Logger.warning('Не удалось восстановить черновик: $e');
    }
  }

  // ─── Проверка подключения (B2) ─────────────────────────────────────────────

  Future<bool> _checkConnectivity() async {
    if (kIsWeb) return true; // на вебе не можем проверить через dart:io
    try {
      final result = await InternetAddress.lookup('arabica26.ru')
          .timeout(const Duration(seconds: 4));
      return result.isNotEmpty && result.first.rawAddress.isNotEmpty;
    } on SocketException catch (_) {
      return false;
    } on TimeoutException catch (_) {
      return false;
    }
  }

  // ──────────────────────────────────────────────────────────────────────────

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

    RecountAnswer answer;

    // Режим без DBF — ответ + ручной ввод количества
    if (widget.dbfStale) {
      final qty = int.tryParse(_manualQuantityController.text.trim());
      if (qty == null || qty < 0 || _selectedAnswer == null) return;
      answer = RecountAnswer(
        question: question.question,
        grade: question.grade,
        answer: _selectedAnswer!,
        quantity: qty,
        programBalance: null,
        actualBalance: qty,
        difference: null,
        moreBy: null,
        lessBy: null,
        photoPath: _photoPath,
        photoRequired: isPhotoRequired,
      );
    } else {
      // Нормальный режим с остатками из DBF
      final stockFromDbf = question.stock;

      if (_selectedAnswer == 'сходится') {
        answer = RecountAnswer.matching(
          question: question.question,
          grade: question.grade,
          stockFromDbf: stockFromDbf,
          photoPath: _photoPath,
          photoRequired: isPhotoRequired,
        );
      } else if (_selectedAnswer == 'не сходится') {
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
        return; // Ответ не выбран
      }
    }

    _answers[_currentQuestionIndex] = answer;
    // Помечаем, что ответ сохранен
    if (mounted) setState(() {
      _answerSaved = true;
    });
    // Сохраняем черновик (B1) — асинхронно, не блокируем UI
    _saveDraft();
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

    // Проверяем глобальный переключатель ИИ
    final aiToggleEnabled = await AiToggleService.isEnabled('cigaretteVision');
    if (!aiToggleEnabled) {
      Logger.info('[Recount AI] Cigarette Vision disabled via toggle - skipping');
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
          confidence: result.confidence,
        );
      } else {
        // ИИ не смог — "Перефотографировать" / "Обвести товар"
        Logger.warning('ИИ не смог определить количество: ${result.error}');
        _answers[questionIndex] = answer.copyWith(aiVerified: false);
        await _showAiFailedDialog(
          questionIndex: questionIndex,
          question: question,
          imageBytes: imageBytes,
          aiError: result.error,
          pendingSampleId: result.pendingSampleId,
        );
      }
    } catch (e) {
      Logger.error('Ошибка ИИ проверки', e);
      if (!mounted) return;
      // При таймауте или другой ошибке сети — авто-расчёт или ручной ввод
      if (e is TimeoutException) {
        _answers[questionIndex] = answer.copyWith(aiVerified: false);
        await _resolveQuantity(questionIndex: questionIndex, question: question);
      }
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
    double confidence = 0,
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
                  SizedBox(height: 6),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.bar_chart,
                        size: 12,
                        color: confidence >= 0.7
                            ? Colors.green[300]
                            : confidence >= 0.5
                                ? Colors.orange[300]
                                : Colors.red[300],
                      ),
                      SizedBox(width: 4),
                      Text(
                        confidence >= 0.7
                            ? 'Уверенность: высокая'
                            : confidence >= 0.5
                                ? 'Уверенность: средняя'
                                : 'Уверенность: низкая',
                        style: TextStyle(
                          fontSize: 11.sp,
                          color: confidence >= 0.7
                              ? Colors.green[300]
                              : confidence >= 0.5
                                  ? Colors.orange[300]
                                  : Colors.red[300],
                        ),
                      ),
                    ],
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
      // Фото уже сохранено в pending при первом вызове detectAndCountWithTraining —
      // повторная отправка не нужна (избегаем дублей в counting-pending)
      if (mounted) {
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
      }
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
    String? aiError,
    String? pendingSampleId,
  }) async {
    // Определяем причину и подбираем понятное сообщение
    final isModelNotTrained = aiError != null &&
        (aiError.contains('не обучена') || aiError.contains('MODEL_NOT_TRAINED') || aiError.contains('modelMissing'));
    final isLowConfidence = aiError == 'LOW_CONFIDENCE';
    final isNothingDetected = aiError == 'NOTHING_DETECTED';
    final dialogMessage = isModelNotTrained
        ? 'ИИ ещё обучается — образцов пока недостаточно.\nВведите количество вручную.'
        : isNothingDetected
            ? 'ИИ не нашёл товар на фото.\nУбедитесь что упаковка хорошо видна и заполняет кадр.'
            : isLowConfidence
                ? 'Фото нечёткое или товар плохо виден.\nСделайте более чёткое фото или введите вручную.'
                : 'Попробуйте обвести товар на фото или сделать новое фото.';

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
          dialogMessage,
          style: TextStyle(fontSize: 14.sp, color: Colors.white.withOpacity(0.8)),
        ),
        actionsAlignment: MainAxisAlignment.spaceEvenly,
        actions: [
          if (!isModelNotTrained && !isLowConfidence && !isNothingDetected) ...[
            TextButton.icon(
              onPressed: () => Navigator.pop(ctx, 'retake'),
              icon: Icon(Icons.camera_alt, color: Colors.white70, size: 18),
              label: Text('Перефото', style: TextStyle(color: Colors.white70)),
            ),
            ElevatedButton.icon(
              onPressed: () => Navigator.pop(ctx, 'region'),
              icon: Icon(Icons.crop, size: 18),
              label: Text('Обвести'),
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.gold),
            ),
          ],
          if (isLowConfidence || isNothingDetected)
            TextButton.icon(
              onPressed: () => Navigator.pop(ctx, 'retake'),
              icon: Icon(Icons.camera_alt, color: Colors.white70, size: 18),
              label: Text('Переснять', style: TextStyle(color: Colors.white70)),
            ),
          ElevatedButton.icon(
            onPressed: () => Navigator.pop(ctx, 'annotate'),
            icon: Icon(Icons.draw, size: 18),
            label: Text('Обучить ИИ'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green.shade700,
              foregroundColor: Colors.white,
            ),
          ),
          TextButton.icon(
            onPressed: () => Navigator.pop(ctx, 'manual'),
            icon: Icon(Icons.edit, color: Colors.blue[300], size: 18),
            label: Text('Ввести вручную', style: TextStyle(color: Colors.blue[300])),
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
    } else if (result == 'annotate') {
      await _openAnnotationFromRecount(
        questionIndex: questionIndex,
        question: question,
        imageBytes: imageBytes,
        pendingSampleId: pendingSampleId,
      );
    } else if (result == 'manual') {
      await _resolveQuantity(questionIndex: questionIndex, question: question);
    }
  }

  /// Открыть аннотацию — сотрудник обводит пачки → рамки идут к pending образцу
  Future<void> _openAnnotationFromRecount({
    required int questionIndex,
    required RecountQuestion question,
    required Uint8List imageBytes,
    String? pendingSampleId,
  }) async {
    final fakeProduct = CigaretteProduct(
      id: question.barcode,
      barcode: question.barcode,
      productGroup: '',
      productName: question.productName,
      grade: 0,
    );

    final annotated = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => CigaretteAnnotationPage(
          imageBytes: imageBytes,
          product: fakeProduct,
          type: TrainingSampleType.counting,
          shopAddress: widget.shopAddress,
          fromRecount: true,
          pendingSampleId: pendingSampleId,
        ),
      ),
    );

    if (!mounted) return;

    if (annotated == true) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Спасибо! ИИ получил данные для обучения 🎯'),
          backgroundColor: Colors.green,
        ),
      );
    }

    // После аннотации — авто-расчёт или ручной ввод
    await _resolveQuantity(questionIndex: questionIndex, question: question);
  }

  /// Открыть CounterRegionSelector → повторный ИИ с регионом → подтвердить/ввести вручную
  Future<void> _openRegionAndRetry({
    required int questionIndex,
    required RecountQuestion question,
    required Uint8List imageBytes,
  }) async {
    final answer = _answers[questionIndex];
    if (answer.photoPath == null) return;

    // На web photoPath может быть data URL — File() не работает
    if (kIsWeb) return;

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
        // ИИ снова не смог — авто-расчёт или ручной ввод
        Logger.warning('Повторный ИИ не смог определить');
        await _resolveQuantity(questionIndex: questionIndex, question: question);
      }
    } catch (e) {
      Logger.error('Ошибка повторной ИИ проверки', e);
      await _resolveQuantity(questionIndex: questionIndex, question: question);
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
      await _resolveQuantity(questionIndex: questionIndex, question: question);
    }
  }

  /// Авто-расчёт количества из DBF остатка или ручной ввод если остатка нет
  Future<void> _resolveQuantity({
    required int questionIndex,
    required RecountQuestion question,
  }) async {
    // Режим без DBF — количество уже введено вручную
    if (widget.dbfStale) {
      final qty = int.tryParse(_manualQuantityController.text.trim()) ?? 0;
      _answers[questionIndex] = _answers[questionIndex].copyWith(
        employeeConfirmedQuantity: qty,
      );
      return;
    }

    final hasDbfStock = question.stock > 0;

    if (hasDbfStock && _selectedAnswer == 'сходится') {
      // "Сходится" + DBF остаток → количество = остаток
      _answers[questionIndex] = _answers[questionIndex].copyWith(
        employeeConfirmedQuantity: question.stock,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Остаток подтверждён: ${question.stock} шт.'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 2),
          ),
        );
      }
      return;
    }

    if (hasDbfStock && _selectedAnswer == 'не сходится') {
      // "Не сходится" + DBF остаток → авто-расчёт
      final moreBy = int.tryParse(_moreByController.text.trim()) ?? 0;
      final lessBy = int.tryParse(_lessByController.text.trim()) ?? 0;
      final actualBalance = question.stock + moreBy - lessBy;
      _answers[questionIndex] = _answers[questionIndex].copyWith(
        employeeConfirmedQuantity: actualBalance,
      );
      if (mounted) {
        final diffStr = moreBy > 0 ? '+$moreBy' : '-$lessBy';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('По факту: $actualBalance шт. (${question.stock} $diffStr)'),
            backgroundColor: Colors.blue,
            duration: Duration(seconds: 2),
          ),
        );
      }
      return;
    }

    // Нет DBF остатка — ручной ввод как раньше
    await _promptManualQuantity(questionIndex: questionIndex, question: question);
  }

  /// Диалог ручного ввода количества
  Future<void> _promptManualQuantity({
    required int questionIndex,
    required RecountQuestion question,
  }) async {
    final controller = TextEditingController();
    int? result;
    try {
      result = await showDialog<int?>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          backgroundColor: AppColors.emeraldDark,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16.r)),
          title: Text('Введите количество', style: TextStyle(color: Colors.white)),
          content: SingleChildScrollView(
            child: Column(
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
          ),
          actions: [
            TextButton(
              onPressed: () {
                // Снимаем фокус до закрытия — иначе Android клавиатура
                // пытается обновить уже disposed контроллер → красный экран
                FocusManager.instance.primaryFocus?.unfocus();
                Navigator.pop(ctx, null);
              },
              child: Text('Пропустить', style: TextStyle(color: Colors.white54)),
            ),
            ElevatedButton(
              onPressed: () {
                FocusManager.instance.primaryFocus?.unfocus();
                final value = int.tryParse(controller.text.trim());
                Navigator.pop(ctx, value);
              },
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.gold),
              child: Text('Подтвердить'),
            ),
          ],
        ),
      );
    } finally {
      // showDialog возвращает управление сразу при Navigator.pop,
      // но диалог ещё ~300мс анимируется закрытием и TextField остаётся в дереве.
      // Немедленный dispose вызывает _AnimatedState.didUpdateWidget на мёртвый controller.
      // Откладываем на 500мс — к этому моменту анимация точно завершена.
      Future.delayed(const Duration(milliseconds: 500), controller.dispose);
    }

    if (!mounted) return;

    if (result != null) {
      _answers[questionIndex] = _answers[questionIndex].copyWith(
        employeeConfirmedQuantity: result,
        aiMismatch: true,
      );
      // Отправляем employeeAnswer на сервер для pending sample
      try {
        final photoBytes = kIsWeb
            ? base64Decode(_answers[questionIndex].photoPath!.split(',').last)
            : await File(_answers[questionIndex].photoPath!).readAsBytes();
        await CigaretteVisionService.detectAndCountWithTraining(
          imageBytes: photoBytes,
          productId: question.barcode,
          productName: question.productName,
          shopAddress: widget.shopAddress,
          isAiActive: question.isAiActive,
          employeeAnswer: result,
          selectedRegion: _selectedRegion,
        );
      } catch (e) {
        debugPrint('[Recount AI] Ошибка отправки ответа сотрудника в ИИ: $e');
      }

      if (!mounted) return;
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
      // DBF отключена — проверяем выбор ответа + ввод количества
      if (widget.dbfStale) {
        if (_selectedAnswer == null) return false;
        final qty = int.tryParse(_manualQuantityController.text.trim());
        return qty != null && qty >= 0;
      }

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
        _manualQuantityController.clear();
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
            if (savedAnswer.answer == 'ввод количества') {
              _manualQuantityController.text = savedAnswer.quantity?.toString() ?? '';
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
    if (_isSubmitting) return; // защита от двойной отправки
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

    // Проверка интернета (B2)
    if (mounted) setState(() => _uploadProgress = 0.05);
    final hasInternet = await _checkConnectivity();
    if (!hasInternet) {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
          _uploadProgress = 0.0;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Нет интернета. Ответы сохранены, попробуйте позже.'),
            backgroundColor: Colors.orange,
            duration: Duration(seconds: 4),
          ),
        );
      }
      return;
    }

    if (mounted) setState(() {
      _isSubmitting = true;
      _completedAt = DateTime.now();
      _uploadProgress = 0.2;
    });

    try {
      final duration = _completedAt!.difference(_startedAt!);

      if (mounted) setState(() => _uploadProgress = 0.4);

      // Утренняя смена 07:00–19:00, вечерняя 19:05–06:58
      final shiftType = _startedAt!.hour < 19 ? 'morning' : 'evening';

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
        shiftType: shiftType,
      );

      if (mounted) setState(() => _uploadProgress = 0.6);
      final success = await RecountService.createReport(report);
      if (mounted) setState(() => _uploadProgress = 0.9);

      if (mounted) {
        if (success) {
          // Удаляем черновик после успешной отправки (B1)
          await _deleteDraft();
          if (mounted) setState(() => _uploadProgress = 1.0);

          // Отправляем уведомление админу о новом отчёте
          await ReportNotificationService.createNotification(
            reportType: ReportType.recount,
            reportId: report.id,
            employeeName: widget.employeeName,
            shopName: widget.shopAddress,
          );

          if (!mounted) return;
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
            _uploadProgress = 0.0;
            _submitFailed = true;
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
          _uploadProgress = 0.0;
          _submitFailed = true;
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
    if (_loadError != null) {
      return Scaffold(
        backgroundColor: AppColors.night,
        body: SafeArea(
          child: Column(
            children: [
              _buildAppBar(context, 'Пересчет товаров'),
              Expanded(
                child: Center(
                  child: Padding(
                    padding: EdgeInsets.all(24.w),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.error_outline, color: Colors.red, size: 48.sp),
                        SizedBox(height: 16.h),
                        Text(
                          'Не удалось загрузить вопросы',
                          style: TextStyle(color: Colors.white, fontSize: 16.sp, fontWeight: FontWeight.bold),
                          textAlign: TextAlign.center,
                        ),
                        SizedBox(height: 8.h),
                        Text(
                          _loadError!,
                          style: TextStyle(color: Colors.white54, fontSize: 12.sp),
                          textAlign: TextAlign.center,
                        ),
                        SizedBox(height: 24.h),
                        ElevatedButton.icon(
                          onPressed: () {
                            setState(() { _isLoading = true; _loadError = null; });
                            _loadQuestions();
                          },
                          icon: Icon(Icons.refresh),
                          label: Text('Повторить'),
                          style: ElevatedButton.styleFrom(backgroundColor: AppColors.emerald),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

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
              // Прогресс-бар загрузки отчёта (B3) — виден только при отправке
              if (_isSubmitting)
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 2.h),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4.r),
                    child: LinearProgressIndicator(
                      value: _uploadProgress,
                      backgroundColor: Colors.white.withOpacity(0.1),
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.greenAccent.withOpacity(0.8)),
                      minHeight: 4,
                    ),
                  ),
                ),
              // Баннер: отчёт не отправлен (#7)
              if (_submitFailed)
                Container(
                  margin: EdgeInsets.symmetric(horizontal: 16.w, vertical: 4.h),
                  padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 8.h),
                  decoration: BoxDecoration(
                    color: Colors.red.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(8.r),
                    border: Border.all(color: Colors.red.withOpacity(0.4)),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.warning_amber_rounded, color: Colors.red, size: 18.sp),
                      SizedBox(width: 8.w),
                      Expanded(
                        child: Text(
                          'Отчёт не отправлен — попробуйте снова',
                          style: TextStyle(color: Colors.red.shade300, fontSize: 12.sp),
                        ),
                      ),
                    ],
                  ),
                ),
              SizedBox(height: 4),
              // Баннер статуса ИИ (показывается на первом вопросе, пока не закрыт)
              if (!_aiBannerDismissed && !_isLoading && _currentQuestionIndex == 0)
                AnimatedContainer(
                  duration: Duration(milliseconds: 300),
                  margin: EdgeInsets.symmetric(horizontal: 16.w, vertical: 4.h),
                  padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 8.h),
                  decoration: BoxDecoration(
                    color: (_aiActiveCount > 0 && _isModelTrained)
                        ? AppColors.emerald.withOpacity(0.12)
                        : Colors.orange.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(10.r),
                    border: Border.all(
                      color: (_aiActiveCount > 0 && _isModelTrained)
                          ? AppColors.emerald.withOpacity(0.4)
                          : Colors.orange.withOpacity(0.4),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        (_aiActiveCount > 0 && _isModelTrained)
                            ? Icons.smart_toy
                            : Icons.smart_toy_outlined,
                        color: (_aiActiveCount > 0 && _isModelTrained)
                            ? AppColors.emerald
                            : Colors.orange,
                        size: 18.sp,
                      ),
                      SizedBox(width: 8.w),
                      Expanded(
                        child: Text(
                          (_aiActiveCount > 0 && _isModelTrained)
                              ? '🤖 ИИ активен для $_aiActiveCount тов. — фото обработаются автоматически'
                              : (_aiActiveCount > 0)
                                  ? '⚠️ ИИ обучается — для $_aiActiveCount тов. введите вручную'
                                  : '⚠️ ИИ не настроен для этого магазина — ввод вручную',
                          style: TextStyle(
                            fontSize: 12.sp,
                            color: Colors.white.withOpacity(0.85),
                          ),
                        ),
                      ),
                      GestureDetector(
                        onTap: () => setState(() => _aiBannerDismissed = true),
                        child: Icon(Icons.close, size: 16.sp, color: Colors.white.withOpacity(0.4)),
                      ),
                    ],
                  ),
                ),
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
                              // Остаток из DBF или предупреждение о недоступности
                              if (widget.dbfStale)
                                Container(
                                  width: double.infinity,
                                  padding: EdgeInsets.symmetric(vertical: 12.h, horizontal: 16.w),
                                  decoration: BoxDecoration(
                                    color: Colors.orange.withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(14.r),
                                    border: Border.all(color: Colors.orange.withOpacity(0.3)),
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 22),
                                      SizedBox(width: 10),
                                      Expanded(
                                        child: Text(
                                          'DBF не обновлялась более 20 мин.\nВведите фактическое количество.',
                                          style: TextStyle(
                                            fontSize: 13.sp,
                                            fontWeight: FontWeight.w500,
                                            color: Colors.orange,
                                            height: 1.4,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                )
                              else
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
                      // Кнопки «Сходится» / «Не сходится» — в обоих режимах
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
                      // Режим без DBF — поле ввода количества (после выбора ответа)
                      if (widget.dbfStale && _selectedAnswer != null)
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
                                  'Количество на полке:',
                                  style: TextStyle(
                                    fontSize: 15.sp,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.white.withOpacity(0.6),
                                    letterSpacing: 0.5,
                                  ),
                                ),
                                SizedBox(height: 12),
                                TextField(
                                  controller: _manualQuantityController,
                                  keyboardType: TextInputType.number,
                                  enabled: !_answerSaved,
                                  style: TextStyle(
                                    fontSize: 24.sp,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                  ),
                                  textAlign: TextAlign.center,
                                  decoration: InputDecoration(
                                    hintText: '0',
                                    hintStyle: TextStyle(color: Colors.white.withOpacity(0.2), fontSize: 24.sp),
                                    filled: true,
                                    fillColor: Colors.white.withOpacity(0.06),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12.r),
                                      borderSide: BorderSide(color: AppColors.gold.withOpacity(0.3)),
                                    ),
                                    enabledBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12.r),
                                      borderSide: BorderSide(color: AppColors.gold.withOpacity(0.3)),
                                    ),
                                    focusedBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12.r),
                                      borderSide: BorderSide(color: AppColors.gold, width: 2),
                                    ),
                                    suffixText: 'шт',
                                    suffixStyle: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 16.sp),
                                    contentPadding: EdgeInsets.symmetric(vertical: 16.h, horizontal: 16.w),
                                  ),
                                  onChanged: (_) {
                                    if (mounted) setState(() {});
                                  },
                                ),
                              ],
                            ),
                          ),
                        ),
                      // При "Сходится" - подтверждение (только в нормальном режиме)
                      if (!widget.dbfStale && _selectedAnswer == 'сходится')
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
                      // При "Не сходится" - поля расхождений (только в нормальном режиме)
                      if (!widget.dbfStale && _selectedAnswer == 'не сходится')
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
                              _manualQuantityController.clear();
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
                                  if (savedAnswer.answer == 'ввод количества') {
                                    _manualQuantityController.text = savedAnswer.quantity?.toString() ?? '';
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
