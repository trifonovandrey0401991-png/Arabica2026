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
import '../services/recount_points_service.dart';
import '../services/recount_question_service.dart';
import '../../shops/services/shop_service.dart';
import '../../ai_training/services/cigarette_vision_service.dart';

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
  List<RecountQuestion>? _allQuestions;
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
  int _photoAttempts = 0; // Счётчик попыток фото для текущего вопроса (для кнопки "ИИ ошибся")

  @override
  void initState() {
    super.initState();
    _startedAt = DateTime.now();
    _loadQuestions();
  }

  Future<void> _loadQuestions() async {
    try {
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
          // Используем товары напрямую из DBF (реальные баркоды, названия, остатки)
          // onlyWithStock: true - показываем только товары с остатком > 0
          allQuestions = await RecountQuestionService.getQuestionsFromShopProducts(
            shopId: shopId,
            onlyWithStock: true,
          );

          // Статистика по остаткам
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

      // Получаем настройки для определения кол-ва вопросов и фото
      int requiredPhotos = 3; // По умолчанию
      int questionsCount = 30; // По умолчанию

      if (widget.employeePhone != null && widget.employeePhone!.isNotEmpty) {
        try {
          final settings = await RecountPointsService.getSettings();
          questionsCount = settings.questionsCount;
          final points = await RecountPointsService.getPointsByPhone(widget.employeePhone!);

          if (points != null) {
            requiredPhotos = settings.calculateRequiredPhotos(points.points);
            Logger.debug('Баллы сотрудника: ${points.points}, требуется фото: $requiredPhotos, вопросов: $questionsCount');
          }
        } catch (e) {
          Logger.warning('Ошибка загрузки настроек, используем значения по умолчанию: $e');
        }
      } else {
        // Если нет телефона, всё равно загружаем настройки для кол-ва вопросов
        try {
          final settings = await RecountPointsService.getSettings();
          questionsCount = settings.questionsCount;
        } catch (e) {
          Logger.warning('Ошибка загрузки настроек: $e');
        }
      }

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

      setState(() {
        _allQuestions = allQuestions;
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
          ),
        );
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка загрузки вопросов: $e'),
            backgroundColor: Colors.red,
          ),
        );
        Navigator.pop(context);
      }
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
            final needRetake = await _verifyWithAI(_currentQuestionIndex);
            if (needRetake && mounted) {
              // Пользователь выбрал "Повторное фото" - очищаем и открываем камеру снова
              setState(() {
                _photoPath = null;
              });
              _answers[_currentQuestionIndex] = answer.copyWith(photoPath: null);
              // Рекурсивно вызываем для повторного фото
              await _takePhoto();
            }
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
    setState(() {
      _answerSaved = true;
    });
  }

  /// Проверка ответа с помощью ИИ
  /// Возвращает true если нужно сделать повторное фото
  Future<bool> _verifyWithAI(int questionIndex) async {
    if (_selectedQuestions == null || questionIndex >= _selectedQuestions!.length) return false;

    final question = _selectedQuestions![questionIndex];
    final answer = _answers[questionIndex];

    // Проверяем что товар активен для ИИ и есть фото
    if (!question.isAiActive || answer.photoPath == null) {
      Logger.debug('ИИ проверка пропущена: isAiActive=${question.isAiActive}, hasPhoto=${answer.photoPath != null}');
      return false;
    }

    // Проверяем не отключен ли ИИ для этого товара (после многих ошибок)
    final isAiDisabled = await CigaretteVisionService.isProductAiDisabled(question.barcode);
    if (isAiDisabled) {
      Logger.warning('ИИ отключен для товара ${question.barcode} (слишком много ошибок)');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.warning_amber, color: Colors.white, size: 20),
                const SizedBox(width: 8),
                Flexible(child: Text('ИИ отключен для "${question.productName}" (требуется переобучение)')),
              ],
            ),
            backgroundColor: Colors.orange,
            duration: const Duration(seconds: 3),
          ),
        );
      }
      return false;
    }

    setState(() {
      _isVerifyingAI = true;
    });

    try {
      // Загружаем фото
      Uint8List imageBytes;
      if (kIsWeb) {
        // Для веба - декодируем base64
        final base64Data = answer.photoPath!.split(',').last;
        imageBytes = base64Decode(base64Data);
      } else {
        // Для мобильных - читаем файл
        imageBytes = await File(answer.photoPath!).readAsBytes();
      }

      // Отправляем на ИИ (с сохранением в counting датасет для дообучения)
      // isAiActive=true сохраняет фото для обучения независимо от результата детекции
      Logger.info('🤖 Отправка фото на ИИ проверку для товара: ${question.productName}');
      final result = await CigaretteVisionService.detectAndCountWithTraining(
        imageBytes: imageBytes,
        productId: question.barcode,
        productName: question.productName,
        shopAddress: widget.shopAddress,
        isAiActive: question.isAiActive,
      );

      if (!mounted) return false;

      if (result.success) {
        // Сравниваем с остатком из DBF (или введённым вручную)
        final expectedCount = question.stock; // Остаток по программе (DBF)
        final aiCount = result.count;
        final mismatchThreshold = 2; // Порог расхождения
        final mismatch = (expectedCount - aiCount).abs() > mismatchThreshold;

        Logger.info('🤖 ИИ насчитал: $aiCount, по программе (DBF): $expectedCount, расхождение: $mismatch');

        // Обновляем ответ с данными ИИ
        _answers[questionIndex] = answer.copyWith(
          aiVerified: true,
          aiQuantity: aiCount,
          aiConfidence: result.confidence,
          aiMismatch: mismatch,
          aiAnnotatedImageUrl: result.annotatedImageUrl,
        );

        // Показываем результат
        if (mismatch) {
          // Увеличиваем счётчик попыток фото
          _photoAttempts++;

          // Показываем диалог с выбором: повторное фото, далее или "ИИ ошибся" (после 3 попыток)
          final dialogResult = await _showAIMismatchDialog(
            expectedCount: expectedCount,
            aiCount: aiCount,
            question: question,
            imageBytes: imageBytes,
            showReportButton: _photoAttempts >= 3, // Кнопка появляется после 3 попыток
          );
          return dialogResult == 'retake';
        } else {
          // Если расхождения нет - показываем короткое сообщение
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  const Icon(Icons.smart_toy, color: Colors.white, size: 20),
                  const SizedBox(width: 8),
                  Text('✓ ИИ подтвердил: $aiCount шт (совпадает с программой)'),
                ],
              ),
              backgroundColor: Colors.green,
              duration: const Duration(seconds: 2),
            ),
          );
        }
      } else {
        Logger.warning('Ошибка ИИ проверки: ${result.error}');
        // Помечаем что ИИ не смог проверить
        _answers[questionIndex] = answer.copyWith(
          aiVerified: false,
        );
      }
    } catch (e) {
      Logger.error('Ошибка ИИ проверки', e);
    } finally {
      if (mounted) {
        setState(() {
          _isVerifyingAI = false;
        });
      }
    }
    return false;
  }

  /// Показать диалог о расхождении с ИИ
  /// Возвращает: 'retake' - повторное фото, 'continue' - продолжить, 'error_reported' - ИИ ошибся
  /// [showReportButton] - показывать кнопку "ИИ ошибся" (появляется после 3 попыток)
  Future<String> _showAIMismatchDialog({
    required int expectedCount,
    required int aiCount,
    required RecountQuestion question,
    required Uint8List imageBytes,
    bool showReportButton = false,
  }) async {
    final result = await showDialog<String>(
      context: context,
      barrierDismissible: false, // Нельзя закрыть тапом вне диалога
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.warning_amber, color: Colors.orange, size: 28),
            const SizedBox(width: 8),
            const Flexible(child: Text('Расхождение')),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Что показывает программа (DBF)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF004D40).withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(Icons.inventory_2, size: 20, color: Color(0xFF004D40)),
                  const SizedBox(width: 8),
                  Text(
                    'По программе: $expectedCount шт',
                    style: const TextStyle(fontSize: 16),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            // Что насчитал ИИ
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(Icons.smart_toy, size: 20, color: Colors.blue),
                  const SizedBox(width: 8),
                  Text(
                    'ИИ насчитал: $aiCount шт',
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            // Подсказка в зависимости от количества попыток
            Text(
              showReportButton
                  ? 'Попытка $_photoAttempts. Если ИИ постоянно ошибается - нажмите "ИИ ошибся".'
                  : 'Попытка $_photoAttempts из 3. Попробуйте сделать более чёткое фото.',
              style: TextStyle(color: Colors.grey[600], fontSize: 14),
            ),
          ],
        ),
        actionsAlignment: MainAxisAlignment.spaceBetween,
        actionsPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        actions: [
          // Кнопка "ИИ ошибся" - появляется только после 3 попыток
          if (showReportButton)
            TextButton.icon(
              onPressed: () async {
                // Закрываем диалог и отправляем отчёт об ошибке
                Navigator.pop(ctx, 'error_reported');
              },
              icon: const Icon(Icons.report_problem, size: 18, color: Colors.red),
              label: const Text('ИИ ошибся', style: TextStyle(color: Colors.red)),
            )
          else
            const SizedBox.shrink(), // Пустой виджет если кнопка не показывается
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Кнопка "Далее" - продолжить без повторного фото
              TextButton(
                onPressed: () => Navigator.pop(ctx, 'continue'),
                child: const Text('Далее'),
              ),
              const SizedBox(width: 8),
              // Кнопка "Повторное фото"
              ElevatedButton.icon(
                onPressed: () => Navigator.pop(ctx, 'retake'),
                icon: const Icon(Icons.camera_alt, size: 18),
                label: const Text('Повторить'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange,
                ),
              ),
            ],
          ),
        ],
      ),
    );

    // Обработка "ИИ ошибся"
    if (result == 'error_reported') {
      await _reportAiError(
        question: question,
        expectedCount: expectedCount,
        aiCount: aiCount,
        imageBytes: imageBytes,
      );
      return 'continue'; // После отчёта продолжаем
    }

    return result ?? 'continue';
  }

  /// Отправить отчёт об ошибке ИИ
  Future<void> _reportAiError({
    required RecountQuestion question,
    required int expectedCount,
    required int aiCount,
    required Uint8List imageBytes,
  }) async {
    // Показываем индикатор загрузки
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const AlertDialog(
        content: Row(
          children: [
            CircularProgressIndicator(),
            SizedBox(width: 16),
            Text('Отправка отчёта...'),
          ],
        ),
      ),
    );

    try {
      final report = await CigaretteVisionService.reportAiError(
        productId: question.barcode,
        productName: question.productName,
        expectedCount: expectedCount,
        aiCount: aiCount,
        imageBytes: imageBytes,
        shopAddress: widget.shopAddress,
        employeeName: widget.employeeName,
      );

      // Закрываем индикатор
      if (mounted) Navigator.pop(context);

      if (!mounted) return;

      if (report.success) {
        // Показываем результат
        String message;
        Color backgroundColor;

        if (report.isDisabled) {
          message = 'ИИ отключен для "${question.productName}" (${report.consecutiveErrors}/${report.threshold} ошибок)';
          backgroundColor = Colors.red;
        } else {
          message = 'Отчёт отправлен (${report.consecutiveErrors}/${report.threshold})';
          backgroundColor = Colors.green;
        }

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Icon(
                  report.isDisabled ? Icons.warning : Icons.check_circle,
                  color: Colors.white,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Flexible(child: Text(message)),
              ],
            ),
            backgroundColor: backgroundColor,
            duration: const Duration(seconds: 3),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка отправки: ${report.error}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      // Закрываем индикатор
      if (mounted) Navigator.pop(context);

      Logger.error('Ошибка отправки отчёта об ошибке ИИ', e);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
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
          const SnackBar(
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
          const SnackBar(
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
          const SnackBar(
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
      setState(() {
        _currentQuestionIndex++;
        _selectedAnswer = null;
        _moreByController.clear();
        _lessByController.clear();
        _photoPath = null;
        _answerSaved = false; // Сбрасываем флаг для нового вопроса
        _photoAttempts = 0; // Сбрасываем счётчик попыток для нового вопроса

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
        const SnackBar(
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
        setState(() {
          _currentQuestionIndex = i;
        });
        return;
      }
    }

    setState(() {
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
            const SnackBar(
              content: Text('Отчет успешно отправлен'),
              backgroundColor: Colors.green,
            ),
          );
          Navigator.of(context).popUntil((route) => route.isFirst);
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Ошибка отправки отчета. Попробуйте позже'),
              backgroundColor: Colors.red,
            ),
          );
          setState(() {
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
        setState(() {
          _isSubmitting = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Пересчет товаров'),
          backgroundColor: const Color(0xFF004D40),
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_selectedQuestions == null || _selectedQuestions!.isEmpty) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Пересчет товаров'),
          backgroundColor: const Color(0xFF004D40),
        ),
        body: const Center(
          child: Text('Вопросы не найдены'),
        ),
      );
    }

    final question = _selectedQuestions![_currentQuestionIndex];
    final isPhotoRequired = _photoRequiredIndices.contains(_currentQuestionIndex);
    final progress = (_currentQuestionIndex + 1) / _selectedQuestions!.length;

    return Scaffold(
      appBar: AppBar(
        title: Text('Вопрос ${_currentQuestionIndex + 1} из ${_selectedQuestions!.length}'),
        backgroundColor: const Color(0xFF004D40),
      ),
      body: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF004D40),
          image: DecorationImage(
            image: AssetImage('assets/images/arabica_background.png'),
            fit: BoxFit.cover,
            opacity: 0.6,
          ),
        ),
        child: Column(
          children: [
            // Прогресс-бар
            LinearProgressIndicator(
              value: progress,
              backgroundColor: Colors.white.withOpacity(0.3),
              valueColor: const AlwaysStoppedAnimation<Color>(Colors.green),
              minHeight: 4,
            ),
            // Контент
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Вопрос
                    Card(
                      color: Colors.white.withOpacity(0.95),
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 6,
                                  ),
                                  decoration: BoxDecoration(
                                    color: question.grade == 1
                                        ? Colors.red
                                        : question.grade == 2
                                            ? Colors.orange
                                            : Colors.blue,
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Text(
                                    'Грейд ${question.grade}',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            // Остаток из DBF - крупно показываем
                            const SizedBox(height: 16),
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: const Color(0xFF004D40).withOpacity(0.1),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: const Color(0xFF004D40).withOpacity(0.3),
                                ),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const Icon(
                                    Icons.inventory_2,
                                    color: Color(0xFF004D40),
                                    size: 24,
                                  ),
                                  const SizedBox(width: 12),
                                  Text(
                                    'По программе: ${question.stock} шт',
                                    style: const TextStyle(
                                      fontSize: 20,
                                      fontWeight: FontWeight.bold,
                                      color: Color(0xFF004D40),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 16),
                            Text(
                              question.question,
                              style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF004D40),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    // Выбор ответа
                    Card(
                      color: Colors.white.withOpacity(0.95),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const Text(
                              'Ответ:',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF004D40),
                              ),
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Expanded(
                                  child: ElevatedButton(
                                    onPressed: _answerSaved ? null : () {
                                      setState(() {
                                        _selectedAnswer = 'сходится';
                                      });
                                    },
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: _selectedAnswer == 'сходится'
                                          ? Colors.green
                                          : Colors.grey[300],
                                      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
                                    ),
                                    child: const FittedBox(
                                      fit: BoxFit.scaleDown,
                                      child: Text(
                                        'Сходится',
                                        style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: ElevatedButton(
                                    onPressed: _answerSaved ? null : () {
                                      setState(() {
                                        _selectedAnswer = 'не сходится';
                                      });
                                    },
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: _selectedAnswer == 'не сходится'
                                          ? Colors.red
                                          : Colors.grey[300],
                                      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
                                    ),
                                    child: const FittedBox(
                                      fit: BoxFit.scaleDown,
                                      child: Text(
                                        'Не сходится',
                                        style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    // При "Сходится" - ничего вводить не нужно, количество берётся автоматически
                    if (_selectedAnswer == 'сходится')
                      Card(
                        color: Colors.green.withOpacity(0.1),
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Row(
                            children: [
                              const Icon(Icons.check_circle, color: Colors.green, size: 32),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  'Количество ${question.stock} шт подтверждено',
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.green,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    // При "Не сходится" - показываем поля "Больше на" и "Меньше на"
                    if (_selectedAnswer == 'не сходится')
                      Card(
                        color: Colors.white.withOpacity(0.95),
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              const Text(
                                'Укажите расхождение (заполните ОДНО поле):',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Colors.grey,
                                ),
                              ),
                              const SizedBox(height: 16),
                              // Поле "Больше на"
                              Row(
                                children: [
                                  const Icon(Icons.add_circle, color: Colors.blue, size: 24),
                                  const SizedBox(width: 8),
                                  const Expanded(
                                    flex: 2,
                                    child: Text(
                                      'Больше на:',
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                        color: Color(0xFF004D40),
                                      ),
                                    ),
                                  ),
                                  Expanded(
                                    flex: 3,
                                    child: TextField(
                                      controller: _moreByController,
                                      keyboardType: TextInputType.number,
                                      enabled: !_answerSaved,
                                      textAlign: TextAlign.center,
                                      decoration: InputDecoration(
                                        hintText: '0',
                                        border: const OutlineInputBorder(),
                                        suffixText: 'шт',
                                        filled: _moreByController.text.isNotEmpty,
                                        fillColor: Colors.blue.withOpacity(0.1),
                                      ),
                                      onChanged: (value) {
                                        // Очищаем поле "Меньше на" если вводим сюда
                                        if (value.isNotEmpty && int.tryParse(value) != null && int.parse(value) > 0) {
                                          _lessByController.clear();
                                        }
                                        setState(() {});
                                      },
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 16),
                              // Поле "Меньше на"
                              Row(
                                children: [
                                  const Icon(Icons.remove_circle, color: Colors.red, size: 24),
                                  const SizedBox(width: 8),
                                  const Expanded(
                                    flex: 2,
                                    child: Text(
                                      'Меньше на:',
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                        color: Color(0xFF004D40),
                                      ),
                                    ),
                                  ),
                                  Expanded(
                                    flex: 3,
                                    child: TextField(
                                      controller: _lessByController,
                                      keyboardType: TextInputType.number,
                                      enabled: !_answerSaved,
                                      textAlign: TextAlign.center,
                                      decoration: InputDecoration(
                                        hintText: '0',
                                        border: const OutlineInputBorder(),
                                        suffixText: 'шт',
                                        filled: _lessByController.text.isNotEmpty,
                                        fillColor: Colors.red.withOpacity(0.1),
                                      ),
                                      onChanged: (value) {
                                        // Очищаем поле "Больше на" если вводим сюда
                                        if (value.isNotEmpty && int.tryParse(value) != null && int.parse(value) > 0) {
                                          _moreByController.clear();
                                        }
                                        setState(() {});
                                      },
                                    ),
                                  ),
                                ],
                              ),
                              // Предпросмотр результата
                              if (_moreByController.text.isNotEmpty || _lessByController.text.isNotEmpty) ...[
                                const SizedBox(height: 16),
                                Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: Colors.grey.withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Builder(
                                    builder: (context) {
                                      final moreBy = int.tryParse(_moreByController.text) ?? 0;
                                      final lessBy = int.tryParse(_lessByController.text) ?? 0;
                                      final actualBalance = question.stock + moreBy - lessBy;
                                      return Text(
                                        'По факту: $actualBalance шт',
                                        style: const TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold,
                                        ),
                                        textAlign: TextAlign.center,
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
                    if (_answerSaved && isPhotoRequired)
                      Card(
                        color: Colors.white.withOpacity(0.95),
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Row(
                                children: [
                                  const Icon(Icons.camera_alt, color: Colors.orange),
                                  const SizedBox(width: 8),
                                  const Flexible(
                                    child: Text(
                                      'Требуется фото для подтверждения',
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.orange,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              if (_photoPath != null)
                                Container(
                                  height: 200,
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(color: Colors.grey),
                                  ),
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(8),
                                    child: kIsWeb
                                        ? Image.network(
                                            _photoPath!,
                                            fit: BoxFit.cover,
                                          )
                                        : Image.file(
                                            File(_photoPath!),
                                            fit: BoxFit.cover,
                                          ),
                                  ),
                                )
                              else
                                ElevatedButton.icon(
                                  onPressed: _takePhoto,
                                  icon: const Icon(Icons.camera_alt),
                                  label: const Text('Сделать фото'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.orange,
                                    padding: const EdgeInsets.symmetric(vertical: 16),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            // Кнопки навигации
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.95),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 4,
                    offset: const Offset(0, -2),
                  ),
                ],
              ),
              child: Row(
                children: [
                  if (_currentQuestionIndex > 0)
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () {
                          setState(() {
                            _currentQuestionIndex--;
                            _selectedAnswer = null;
                            _moreByController.clear();
                            _lessByController.clear();
                            _photoPath = null;
                            _answerSaved = false; // Сбрасываем флаг

                            if (_currentQuestionIndex < _answers.length) {
                              final savedAnswer = _answers[_currentQuestionIndex];
                              if (savedAnswer.answer.isNotEmpty) {
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
                        },
                        child: const Text('Назад'),
                      ),
                    ),
                  if (_currentQuestionIndex > 0) const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: ElevatedButton(
                      onPressed: (_isSubmitting || _isVerifyingAI) ? null : _nextQuestion,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _answerSaved && _photoRequiredIndices.contains(_currentQuestionIndex) && _photoPath == null
                            ? Colors.orange
                            : const Color(0xFF004D40),
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                      child: (_isSubmitting || _isVerifyingAI)
                          ? Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const SizedBox(
                                  height: 20,
                                  width: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                  ),
                                ),
                                if (_isVerifyingAI) ...[
                                  const SizedBox(width: 8),
                                  const Text('ИИ проверяет...'),
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
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
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
    );
  }
}

