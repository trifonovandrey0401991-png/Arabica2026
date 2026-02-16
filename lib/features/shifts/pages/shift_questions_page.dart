import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import '../models/shift_question_model.dart';
import '../models/shift_report_model.dart';
import 'package:arabica_app/shared/widgets/app_cached_image.dart';
import '../models/shift_shortage_model.dart';
import '../services/shift_report_service.dart';
import '../../../core/services/photo_upload_service.dart';
import '../../../core/services/report_notification_service.dart';
import '../../../core/utils/logger.dart';
import '../../ai_training/pages/shift_ai_verification_page.dart';
import '../../ai_training/services/shift_ai_verification_service.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

/// Страница с вопросами пересменки
class ShiftQuestionsPage extends StatefulWidget {
  final String employeeName;
  final String shopAddress;
  final String? shiftType; // 'morning' | 'evening' - тип смены для валидации времени

  const ShiftQuestionsPage({
    super.key,
    required this.employeeName,
    required this.shopAddress,
    this.shiftType,
  });

  @override
  State<ShiftQuestionsPage> createState() => _ShiftQuestionsPageState();
}

class _ShiftQuestionsPageState extends State<ShiftQuestionsPage> {
  // Dark emerald palette
  static final Color _emerald = Color(0xFF1A4D4D);
  static final Color _emeraldDark = Color(0xFF0D2E2E);
  static final Color _night = Color(0xFF051515);
  static final Color _gold = Color(0xFFD4AF37);

  List<ShiftQuestion>? _questions;
  bool _isLoading = true;
  final List<ShiftAnswer> _answers = [];
  int _currentQuestionIndex = 0;
  final TextEditingController _textController = TextEditingController();
  final TextEditingController _numberController = TextEditingController();
  String? _photoPath;
  String? _selectedYesNo; // 'Да' или 'Нет'
  bool _isSubmitting = false;

  // AI верификация товаров
  bool? _aiVerificationPassed;
  List<ShiftShortage> _aiShortages = [];

  /// Нормализовать адрес магазина для сравнения
  String _normalizeShopAddress(String address) {
    return address.toLowerCase().trim().replaceAll(RegExp(r'\s+'), ' ');
  }

  /// Найти эталонное фото для магазина (с учетом нормализации адресов)
  String? _findReferencePhoto(ShiftQuestion question) {
    Logger.debug('_findReferencePhoto вызвана для вопроса: "${question.question}"');
    Logger.debug('   Магазин сотрудника: "${widget.shopAddress}"');

    if (question.referencePhotos == null || question.referencePhotos!.isEmpty) {
      Logger.debug('   referencePhotos пуст или null');
      return null;
    }

    Logger.debug('   referencePhotos содержит ${question.referencePhotos!.length} записей:');
    question.referencePhotos!.forEach((key, value) {
      Logger.debug('     - "$key" -> "$value"');
    });

    final normalizedShopAddress = _normalizeShopAddress(widget.shopAddress);
    Logger.debug('   Нормализованный адрес магазина: "$normalizedShopAddress"');

    // Сначала пробуем точное совпадение
    if (question.referencePhotos!.containsKey(widget.shopAddress)) {
      Logger.success('   Найдено точное совпадение: "${question.referencePhotos![widget.shopAddress]}"');
      return question.referencePhotos![widget.shopAddress];
    }

    // Затем пробуем найти по нормализованному адресу
    for (var key in question.referencePhotos!.keys) {
      final normalizedKey = _normalizeShopAddress(key);
      Logger.debug('   Сравниваем: "$normalizedKey" == "$normalizedShopAddress" ? ${normalizedKey == normalizedShopAddress}');
      if (normalizedKey == normalizedShopAddress) {
        Logger.success('   Найдено эталонное фото по нормализованному адресу: "$key" -> "${question.referencePhotos![key]}"');
        return question.referencePhotos![key];
      }
    }

    Logger.debug('   Эталонное фото не найдено');
    return null;
  }

  @override
  void initState() {
    super.initState();
    _loadQuestions();
  }

  Future<void> _loadQuestions() async {
    try {
      // Фильтруем вопросы по магазину сотрудника
      final questions = await ShiftQuestion.loadQuestions(shopAddress: widget.shopAddress);
      Logger.info('Загружено вопросов: ${questions.length}');
      Logger.debug('Магазин сотрудника: "${widget.shopAddress}"');
      Logger.debug('Длина адреса магазина: ${widget.shopAddress.length}');
      for (var i = 0; i < questions.length; i++) {
        final q = questions[i];
        if (q.isPhotoOnly) {
          Logger.debug('Вопрос ${i + 1} с фото: "${q.question}"');
          Logger.debug('   ID вопроса: ${q.id}');
          if (q.referencePhotos != null && q.referencePhotos!.isNotEmpty) {
            Logger.success('   Есть эталонные фото (${q.referencePhotos!.length}):');
            q.referencePhotos!.forEach((key, value) {
              Logger.debug('     - "$key" -> "$value"');
            });
            // Проверяем точное совпадение
            if (q.referencePhotos!.containsKey(widget.shopAddress)) {
              Logger.success('   Есть эталонное фото для магазина "${widget.shopAddress}": ${q.referencePhotos![widget.shopAddress]}');
            } else {
              Logger.debug('   Нет эталонного фото для магазина "${widget.shopAddress}"');
              // Проверяем нормализованное совпадение
              final normalizedShopAddress = _normalizeShopAddress(widget.shopAddress);
              for (var key in q.referencePhotos!.keys) {
                final normalizedKey = _normalizeShopAddress(key);
                Logger.debug('      Сравниваем нормализованные: "$normalizedKey" == "$normalizedShopAddress" ? ${normalizedKey == normalizedShopAddress}');
                if (normalizedKey == normalizedShopAddress) {
                  Logger.success('      Найдено совпадение по нормализованному адресу!');
                }
              }
            }
          } else {
            Logger.debug('   Нет эталонных фото в вопросе (referencePhotos: ${q.referencePhotos})');
          }
        }
      }
      setState(() {
        _questions = questions;
        _isLoading = false;
      });
    } catch (e) {
      Logger.error('Ошибка загрузки вопросов', e);
      setState(() {
        _isLoading = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Что-то пошло не так, попробуйте позже'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  void dispose() {
    _textController.dispose();
    _numberController.dispose();
    super.dispose();
  }

  Future<void> _takePhoto() async {
    try {
      ImageSource? source;

      // Проверяем, является ли текущий вопрос типом "только фото"
      final isPhotoOnlyQuestion = _questions != null &&
          _currentQuestionIndex < _questions!.length &&
          _questions![_currentQuestionIndex].isPhotoOnly;

      // Если вопрос требует только фото, используем только камеру (даже на веб)
      if (isPhotoOnlyQuestion) {
        source = ImageSource.camera;
      } else {
        // Для других случаев (если фото опционально) показываем выбор
        // На веб используем галерею
        if (kIsWeb) {
          source = ImageSource.gallery;
        } else {
          // На мобильных показываем диалог выбора
          source = await showDialog<ImageSource>(
            context: context,
            builder: (context) => AlertDialog(
              backgroundColor: _emeraldDark,
              title: Text('Выберите источник', style: TextStyle(color: Colors.white)),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ListTile(
                    leading: Icon(Icons.camera_alt, color: Colors.white.withOpacity(0.8)),
                    title: Text('Камера', style: TextStyle(color: Colors.white.withOpacity(0.9))),
                    onTap: () => Navigator.pop(context, ImageSource.camera),
                  ),
                  ListTile(
                    leading: Icon(Icons.photo_library, color: Colors.white.withOpacity(0.8)),
                    title: Text('Галерея', style: TextStyle(color: Colors.white.withOpacity(0.9))),
                    onTap: () => Navigator.pop(context, ImageSource.gallery),
                  ),
                ],
              ),
            ),
          );
        }
      }

      if (source == null) return;

      final ImagePicker picker = ImagePicker();
      final XFile? photo = await picker.pickImage(
        source: source,
        imageQuality: kIsWeb ? 60 : 85, // Меньшее качество для веб для уменьшения размера
        maxWidth: kIsWeb ? 1920 : null, // Ограничение размера для веб
        maxHeight: kIsWeb ? 1080 : null,
      );

      if (photo != null) {
        if (kIsWeb) {
          // Для веб конвертируем в base64 data URL
          final bytes = await photo.readAsBytes();
          final base64String = base64Encode(bytes);
          final dataUrl = 'data:image/jpeg;base64,$base64String';
          setState(() {
            _photoPath = dataUrl;
          });
        } else {
          // Для мобильных сохраняем в файл
          final appDir = await getApplicationDocumentsDirectory();
          final fileName = 'shift_photo_${DateTime.now().millisecondsSinceEpoch}.jpg';
          final savedFile = File(path.join(appDir.path, fileName));
          final bytes = await photo.readAsBytes();
          await savedFile.writeAsBytes(bytes);
          setState(() {
            _photoPath = savedFile.path;
          });
        }
      }
    } catch (e) {
      Logger.error('Ошибка при выборе фото', e);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка: ${e.toString()}'),
            backgroundColor: Colors.red,
            duration: Duration(seconds: 5),
          ),
        );
      }
    }
  }

  void _nextQuestion() {
    if (_questions == null) return;
    if (_currentQuestionIndex < _questions!.length - 1) {
      setState(() {
        _currentQuestionIndex++;
        _textController.clear();
        _numberController.clear();
        _photoPath = null; // Сбрасываем фото при переходе к следующему вопросу
        _selectedYesNo = null;
        Logger.debug('Переход к следующему вопросу: индекс $_currentQuestionIndex');
        if (_currentQuestionIndex < _questions!.length) {
          final nextQuestion = _questions![_currentQuestionIndex];
          Logger.debug('   Следующий вопрос: "${nextQuestion.question}"');
          if (nextQuestion.isPhotoOnly) {
            Logger.debug('   Это вопрос с фото');
            final refPhoto = _findReferencePhoto(nextQuestion);
            if (refPhoto != null) {
              Logger.success('   У следующего вопроса есть эталонное фото: $refPhoto');
            } else {
              Logger.debug('   У следующего вопроса нет эталонного фото');
            }
          }
        }
      });
    } else {
      _submitReport();
    }
  }

  /// Сохранить ответ и автоматически перейти к следующему вопросу
  Future<void> _saveAndNext() async {
    _saveAnswer();
    // Небольшая задержка для визуального отклика
    await Future.delayed(Duration(milliseconds: 500));
    if (mounted) {
      _nextQuestion();
    }
  }

  void _previousQuestion() {
    if (_currentQuestionIndex > 0) {
      setState(() {
        _currentQuestionIndex--;
        if (_questions != null && _currentQuestionIndex < _questions!.length) {
          final question = _questions![_currentQuestionIndex];
          if (_currentQuestionIndex < _answers.length) {
            final answer = _answers[_currentQuestionIndex];
            if (question.isNumberOnly) {
              _numberController.text = answer.numberAnswer?.toString() ?? '';
            } else if (question.isTextOnly) {
              _textController.text = answer.textAnswer ?? '';
            } else if (question.isPhotoOnly) {
              _photoPath = answer.photoPath;
            } else if (question.isYesNo) {
              _selectedYesNo = answer.textAnswer; // 'Да' или 'Нет'
            }
          }
        }
      });
    }
  }

  bool _canProceed() {
    if (_questions == null || _currentQuestionIndex >= _questions!.length) {
      return false;
    }
    final question = _questions![_currentQuestionIndex];

    if (question.isNumberOnly) {
      return _numberController.text.trim().isNotEmpty;
    } else if (question.isPhotoOnly) {
      return _photoPath != null;
    } else if (question.isYesNo) {
      return _selectedYesNo != null;
    } else {
      return _textController.text.trim().isNotEmpty;
    }
  }

  void _saveAnswer() {
    if (_questions == null || _currentQuestionIndex >= _questions!.length) return;

    final question = _questions![_currentQuestionIndex];
    ShiftAnswer answer;

    if (question.isNumberOnly) {
      final numberValue = double.tryParse(_numberController.text.trim());
      if (numberValue == null) return;
      answer = ShiftAnswer(
        question: question.question,
        numberAnswer: numberValue,
      );
    } else if (question.isPhotoOnly) {
      if (_photoPath == null) return;
      // КРИТИЧЕСКИ ВАЖНО: Получаем URL эталонного фото ИЗ ВОПРОСА (которое админ прикрепил)
      // НИ В КОЕМ СЛУЧАЕ не используем фото сотрудника как эталонное!
      // Эталонное фото должно быть из question.referencePhotos[shopAddress] (с нормализацией адресов)
      String? referencePhotoUrl;
      Logger.debug('Сохранение ответа на вопрос с фото: "${question.question}"');
      Logger.debug('   Магазин: ${widget.shopAddress}');
      Logger.debug('   Фото сотрудника: $_photoPath');
      Logger.debug('   referencePhotos в вопросе: ${question.referencePhotos}');

      // Используем функцию поиска с нормализацией адресов
      referencePhotoUrl = _findReferencePhoto(question);

      if (referencePhotoUrl != null) {
        Logger.success('Сохраняем эталонное фото ИЗ ВОПРОСА: $referencePhotoUrl');
        Logger.debug('   Фото сотрудника (НЕ эталонное!): $_photoPath');
        // Дополнительная проверка: убеждаемся, что эталонное фото НЕ равно фото сотрудника
        if (referencePhotoUrl == _photoPath) {
          Logger.error('ОШИБКА: Эталонное фото совпадает с фото сотрудника! Это неправильно!');
        }
      } else {
        Logger.warning('Нет эталонного фото в вопросе для магазина: ${widget.shopAddress}');
        if (question.referencePhotos != null) {
          Logger.debug('   Доступные магазины: ${question.referencePhotos!.keys.toList()}');
        }
      }
      answer = ShiftAnswer(
        question: question.question,
        photoPath: _photoPath, // Фото сотрудника (НЕ эталонное!)
        referencePhotoUrl: referencePhotoUrl, // Эталонное фото ИЗ ВОПРОСА (НЕ из фото сотрудника!)
      );
    } else if (question.isYesNo) {
      if (_selectedYesNo == null) return;
      answer = ShiftAnswer(
        question: question.question,
        textAnswer: _selectedYesNo, // Сохраняем 'Да' или 'Нет'
      );
    } else {
      answer = ShiftAnswer(
        question: question.question,
        textAnswer: _textController.text.trim(),
      );
    }

    if (_currentQuestionIndex < _answers.length) {
      _answers[_currentQuestionIndex] = answer;
    } else {
      _answers.add(answer);
    }
  }

  /// Проверить есть ли активные AI товары для магазина
  Future<bool> _hasActiveAiProducts() async {
    try {
      final products = await ShiftAiVerificationService.getActiveAiProducts(widget.shopAddress);
      Logger.debug('Активных AI товаров для ${widget.shopAddress}: ${products.length}');
      return products.isNotEmpty;
    } catch (e) {
      Logger.error('Ошибка проверки активных AI товаров', e);
      return false;
    }
  }

  /// Собрать фото из ответов для AI верификации
  Future<List<Uint8List>> _collectPhotosForAiVerification() async {
    final List<Uint8List> photos = [];

    for (var answer in _answers) {
      if (answer.photoPath != null) {
        try {
          if (answer.photoPath!.startsWith('data:image')) {
            // base64 формат (веб)
            final base64Data = answer.photoPath!.split(',').last;
            final bytes = base64Decode(base64Data);
            photos.add(Uint8List.fromList(bytes));
          } else {
            // файловый путь (мобильные)
            final file = File(answer.photoPath!);
            if (await file.exists()) {
              final bytes = await file.readAsBytes();
              photos.add(bytes);
            }
          }
        } catch (e) {
          Logger.error('Ошибка чтения фото для AI: ${answer.photoPath}', e);
        }
      }
    }

    Logger.debug('Собрано ${photos.length} фото для AI верификации');
    return photos;
  }

  /// Запустить AI верификацию товаров
  Future<bool> _runAiVerification() async {
    // Проверяем есть ли активные AI товары
    final hasAiProducts = await _hasActiveAiProducts();
    if (!hasAiProducts) {
      Logger.debug('Нет активных AI товаров - пропускаем AI верификацию');
      return true; // Нет AI товаров - пропускаем
    }

    // Собираем фото
    final photos = await _collectPhotosForAiVerification();
    if (photos.isEmpty) {
      Logger.debug('Нет фото для AI верификации');
      return true; // Нет фото - пропускаем
    }

    // Открываем страницу AI верификации
    if (!mounted) return true;

    final result = await Navigator.push<Map<String, dynamic>?>(
      context,
      MaterialPageRoute(
        builder: (context) => ShiftAiVerificationPage(
          photos: photos,
          shopAddress: widget.shopAddress,
          employeeName: widget.employeeName,
        ),
      ),
    );

    if (result == null) {
      // Пользователь пропустил AI верификацию
      Logger.debug('AI верификация пропущена пользователем');
      return true;
    }

    // Сохраняем результаты
    _aiVerificationPassed = result['aiVerificationPassed'] as bool?;
    final shortages = result['shortages'] as List<ShiftShortage>?;
    if (shortages != null) {
      _aiShortages = shortages;
    }

    Logger.info('AI верификация завершена: passed=$_aiVerificationPassed, недостач=${_aiShortages.length}');
    return true;
  }

  Future<void> _submitReport() async {
    if (_questions == null) return;
    if (_isSubmitting) return; // Защита от повторной отправки

    setState(() => _isSubmitting = true);

    try {
      _saveAnswer();

      if (_answers.length != _questions!.length) {
        throw Exception('Не все вопросы отвечены');
      }

      final now = DateTime.now();
      final reportId = ShiftReport.generateId(
        widget.employeeName,
        widget.shopAddress,
        now,
      );

      // Загрузка фото пакетами (по 3 одновременно, не перегружая сеть)
      final photoTasks = <int, List<String>>{};
      for (var i = 0; i < _answers.length; i++) {
        final answer = _answers[i];
        if (answer.photoPath != null && answer.photoDriveId == null) {
          photoTasks[i] = [answer.photoPath!, '${reportId}_$i.jpg'];
        }
      }
      final uploadResults = await PhotoUploadService.uploadInBatches(photoTasks);

      // Собираем ответы с результатами загрузок
      final List<ShiftAnswer> syncedAnswers = [];
      for (var i = 0; i < _answers.length; i++) {
        final answer = _answers[i];
        if (uploadResults.containsKey(i)) {
          final driveId = uploadResults[i];
          if (driveId != null) {
            Logger.success('Фото ${i + 1} загружено: $driveId');
            syncedAnswers.add(ShiftAnswer(
              question: answer.question,
              textAnswer: answer.textAnswer,
              numberAnswer: answer.numberAnswer,
              photoPath: answer.photoPath,
              photoDriveId: driveId,
              referencePhotoUrl: answer.referencePhotoUrl,
            ));
          } else {
            Logger.warning('Фото ${i + 1} не загружено, сохраняем локально');
            syncedAnswers.add(answer);
          }
        } else {
          syncedAnswers.add(answer);
        }
      }

      Logger.info('Итого обработано ответов: ${syncedAnswers.length}');
      for (var i = 0; i < syncedAnswers.length; i++) {
        final ans = syncedAnswers[i];
        Logger.debug('   Ответ ${i + 1}: photoPath=${ans.photoPath}, photoDriveId=${ans.photoDriveId}, referencePhotoUrl=${ans.referencePhotoUrl}');
      }

      // Запускаем AI верификацию товаров
      await _runAiVerification();

      final report = ShiftReport(
        id: reportId,
        employeeName: widget.employeeName,
        shopAddress: widget.shopAddress,
        createdAt: now,
        answers: syncedAnswers,
        isSynced: true,
        shiftType: widget.shiftType, // Передаём тип смены для валидации на сервере
        shortages: _aiShortages.isNotEmpty ? _aiShortages : null,
        aiVerificationPassed: _aiVerificationPassed,
      );

      // Сохраняем на сервере с обработкой TIME_EXPIRED
      final result = await ShiftReportService.submitReport(report);

      if (!result.success) {
        if (result.isTimeExpired) {
          // Время истекло - показываем диалог и закрываем
          if (mounted) {
            await showDialog(
              context: context,
              barrierDismissible: false,
              builder: (context) => AlertDialog(
                backgroundColor: _emeraldDark,
                title: Row(
                  children: [
                    Icon(Icons.timer_off, color: Colors.red, size: 28),
                    SizedBox(width: 8),
                    Text('Время истекло', style: TextStyle(color: Colors.white)),
                  ],
                ),
                content: Text(
                  result.message ?? 'К сожалению вы не успели пройти пересменку вовремя',
                  style: TextStyle(fontSize: 16.sp, color: Colors.white.withOpacity(0.9)),
                ),
                actions: [
                  TextButton(
                    onPressed: () {
                      Navigator.of(context).pop(); // Закрыть диалог
                      Navigator.of(context).popUntil((route) => route.isFirst); // Вернуться на главную
                    },
                    child: Text('Понятно', style: TextStyle(color: _gold)),
                  ),
                ],
              ),
            );
          }
          return; // Выходим из метода
        }

        // Другая ошибка - сохраняем локально как резерв
        Logger.warning('Ошибка сохранения на сервере: ${result.errorType}');
        await ShiftReport.saveReport(report);
      }

      // Отправляем уведомление админу о новом отчёте (пересменка)
      await ReportNotificationService.createNotification(
        reportType: ReportType.shiftHandover,
        reportId: reportId,
        employeeName: widget.employeeName,
        shopName: widget.shopAddress,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Отчет успешно сохранен'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Что-то пошло не так, попробуйте позже'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  Widget _buildAppBar(BuildContext context, String title) {
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
            child: Text(title, style: TextStyle(color: Colors.white, fontSize: 18.sp, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        backgroundColor: _night,
        body: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [_emerald, _emeraldDark, _night],
              stops: [0.0, 0.3, 1.0],
            ),
          ),
          child: SafeArea(
            child: Column(
              children: [
                _buildAppBar(context, 'Загрузка вопросов'),
                Expanded(
                  child: Center(child: CircularProgressIndicator(color: _gold)),
                ),
              ],
            ),
          ),
        ),
      );
    }

    if (_questions == null || _questions!.isEmpty) {
      return Scaffold(
        backgroundColor: _night,
        body: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [_emerald, _emeraldDark, _night],
              stops: [0.0, 0.3, 1.0],
            ),
          ),
          child: SafeArea(
            child: Column(
              children: [
                _buildAppBar(context, 'Ошибка'),
                Expanded(
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.error_outline, size: 64, color: Colors.red),
                        SizedBox(height: 16),
                        Text(
                          'Что-то пошло не так, попробуйте позже',
                          style: TextStyle(color: Colors.white.withOpacity(0.9), fontSize: 18.sp),
                          textAlign: TextAlign.center,
                        ),
                        SizedBox(height: 16),
                        ElevatedButton(
                          onPressed: () => Navigator.pop(context),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _gold,
                            foregroundColor: _night,
                          ),
                          child: Text('Назад'),
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

    if (_currentQuestionIndex >= _questions!.length) {
      return Scaffold(
        backgroundColor: _night,
        body: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [_emerald, _emeraldDark, _night],
              stops: [0.0, 0.3, 1.0],
            ),
          ),
          child: Center(
            child: Text(
              'Все вопросы отвечены',
              style: TextStyle(color: Colors.white.withOpacity(0.9), fontSize: 16.sp),
            ),
          ),
        ),
      );
    }

    final question = _questions![_currentQuestionIndex];

    // Логирование для отладки эталонного фото
    if (question.isPhotoOnly && _photoPath == null) {
      Logger.debug('build: Текущий вопрос с фото: "${question.question}"');
      Logger.debug('   Индекс вопроса: $_currentQuestionIndex');
      Logger.debug('   Магазин: ${widget.shopAddress}');
      final referencePhotoUrl = _findReferencePhoto(question);
      if (referencePhotoUrl != null) {
        Logger.success('build: Найдено эталонное фото: $referencePhotoUrl');
      } else {
        Logger.debug('build: Эталонное фото не найдено');
      }
    }

    return Scaffold(
      backgroundColor: _night,
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [_emerald, _emeraldDark, _night],
            stops: [0.0, 0.3, 1.0],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              _buildAppBar(context, 'Вопрос ${_currentQuestionIndex + 1}'),
              Expanded(
                child: SingleChildScrollView(
                  padding: EdgeInsets.all(16.w),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Question card
                      Container(
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.06),
                          borderRadius: BorderRadius.circular(14.r),
                          border: Border.all(color: Colors.white.withOpacity(0.1)),
                        ),
                        child: Padding(
                          padding: EdgeInsets.all(16.w),
                          child: Text(
                            question.question,
                            style: TextStyle(
                              fontSize: 20.sp,
                              fontWeight: FontWeight.bold,
                              color: Colors.white.withOpacity(0.9),
                            ),
                          ),
                        ),
                      ),
                      SizedBox(height: 24),

                      if (question.isNumberOnly) ...[
                        TextField(
                          controller: _numberController,
                          keyboardType: TextInputType.numberWithOptions(decimal: true),
                          style: TextStyle(color: Colors.white),
                          decoration: InputDecoration(
                            labelText: 'Введите число',
                            labelStyle: TextStyle(color: Colors.white.withOpacity(0.5)),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12.r),
                              borderSide: BorderSide(color: Colors.white.withOpacity(0.2)),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12.r),
                              borderSide: BorderSide(color: Colors.white.withOpacity(0.2)),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12.r),
                              borderSide: BorderSide(color: _gold, width: 2),
                            ),
                            filled: true,
                            fillColor: Colors.white.withOpacity(0.06),
                          ),
                          onChanged: (_) => setState(() {}),
                          onSubmitted: (_) {
                            if (_canProceed()) {
                              _saveAndNext();
                            }
                          },
                        ),
                      ] else if (question.isPhotoOnly) ...[
                        // ВАЖНО: Эталонное фото из вопроса пересменки (которое админ прикрепил)
                        // Эталонное фото ВСЕГДА показывается ДО того, как сотрудник сделал свое фото
                        // После того как фото сделано, эталонное фото скрывается (сравнение только в отчетах)
                        if (_photoPath == null) ...[
                          // Получаем эталонное фото из вопроса для этого магазина (с нормализацией адресов)
                          Builder(
                            builder: (context) {
                              final referencePhotoUrl = _findReferencePhoto(question);
                              if (referencePhotoUrl != null) {
                                Logger.debug('Builder: Показываем эталонное фото для магазина: ${widget.shopAddress}');
                                Logger.debug('   URL эталонного фото: $referencePhotoUrl');
                                return Container(
                              margin: EdgeInsets.only(bottom: 16.h),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.06),
                                borderRadius: BorderRadius.circular(14.r),
                                border: Border.all(color: Colors.white.withOpacity(0.1)),
                              ),
                              child: Padding(
                                padding: EdgeInsets.all(12.w),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Эталонное фото (как должно быть):',
                                      style: TextStyle(
                                        fontSize: 16.sp,
                                        fontWeight: FontWeight.bold,
                                        color: _gold,
                                      ),
                                    ),
                                    SizedBox(height: 8),
                                    Container(
                                      height: 400,
                                      width: double.infinity,
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(12.r),
                                        border: Border.all(color: Colors.white.withOpacity(0.2), width: 2),
                                      ),
                                      child: ClipRRect(
                                        borderRadius: BorderRadius.circular(12.r),
                                        child: AppCachedImage(
                                          imageUrl: referencePhotoUrl,
                                          fit: BoxFit.contain,
                                          errorWidget: (context, error, stackTrace) {
                                            Logger.error('Ошибка загрузки эталонного фото', error);
                                            return Center(
                                              child: Column(
                                                mainAxisAlignment: MainAxisAlignment.center,
                                                children: [
                                                  Icon(Icons.error, size: 64, color: Colors.red),
                                                  SizedBox(height: 8),
                                                  Text(
                                                    'Ошибка загрузки эталонного фото',
                                                    style: TextStyle(color: Colors.white.withOpacity(0.5)),
                                                  ),
                                                ],
                                              ),
                                            );
                                          },
                                        ),
                                      ),
                                    ),
                                    SizedBox(height: 16),
                                    Text(
                                      'Посмотрите на эталонное фото, затем нажмите кнопку ниже для фотографирования',
                                      style: TextStyle(
                                        fontSize: 16.sp,
                                        fontWeight: FontWeight.w500,
                                        color: Colors.white.withOpacity(0.7),
                                      ),
                                      textAlign: TextAlign.center,
                                    ),
                                  ],
                                ),
                              ),
                                );
                              } else {
                                Logger.warning('Нет эталонного фото в вопросе для магазина: ${widget.shopAddress}');
                                if (question.referencePhotos != null) {
                                  Logger.debug('   Доступные магазины в referencePhotos: ${question.referencePhotos!.keys.toList()}');
                                }
                                return SizedBox.shrink();
                              }
                            },
                          ),
                        ],
                        if (_photoPath != null)
                          Container(
                            height: 300,
                            margin: EdgeInsets.only(bottom: 16.h),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(12.r),
                              border: Border.all(color: Colors.white.withOpacity(0.2)),
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(12.r),
                              child: kIsWeb
                                  ? AppCachedImage(
                                      imageUrl: _photoPath!,
                                      fit: BoxFit.cover,
                                      errorWidget: (context, error, stackTrace) {
                                        return Center(
                                          child: Icon(Icons.error, size: 64, color: Colors.white.withOpacity(0.5)),
                                        );
                                      },
                                    )
                                  : Image.file(
                                      File(_photoPath!),
                                      fit: BoxFit.cover,
                                    ),
                            ),
                          ),
                        ElevatedButton.icon(
                          onPressed: () async {
                            Logger.debug('Нажата кнопка фотографирования');
                            Logger.debug('   Текущий вопрос: "${question.question}"');
                            Logger.debug('   Есть эталонное фото: ${question.referencePhotos != null && question.referencePhotos!.containsKey(widget.shopAddress)}');
                            await _takePhoto();
                            if (_photoPath != null) {
                              Logger.success('Фото сделано: $_photoPath');
                              // Если фото сделано, автоматически переходим к следующему вопросу
                              if (_canProceed()) {
                                _saveAndNext();
                              }
                            } else {
                              Logger.warning('Фото не было сделано');
                            }
                          },
                          icon: Icon(Icons.camera_alt),
                          label: Text(_photoPath == null ? 'Сфотографировать' : 'Изменить фото'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _gold,
                            foregroundColor: _night,
                            padding: EdgeInsets.symmetric(vertical: 16.h),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12.r),
                            ),
                          ),
                        ),
                      ] else if (question.isYesNo) ...[
                        // Кнопки Да/Нет
                        Row(
                          children: [
                            Expanded(
                              child: ElevatedButton(
                                onPressed: () {
                                  setState(() {
                                    _selectedYesNo = 'Да';
                                  });
                                  // Автоматически переходим к следующему вопросу
                                  if (_canProceed()) {
                                    _saveAndNext();
                                  }
                                },
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: _selectedYesNo == 'Да'
                                      ? Colors.green
                                      : Colors.white.withOpacity(0.06),
                                  foregroundColor: _selectedYesNo == 'Да'
                                      ? Colors.white
                                      : Colors.white.withOpacity(0.9),
                                  padding: EdgeInsets.symmetric(vertical: 20.h),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12.r),
                                    side: BorderSide(
                                      color: _selectedYesNo == 'Да'
                                          ? Colors.green
                                          : Colors.white.withOpacity(0.1),
                                    ),
                                  ),
                                ),
                                child: Text(
                                  'Да',
                                  style: TextStyle(fontSize: 18.sp, fontWeight: FontWeight.bold),
                                ),
                              ),
                            ),
                            SizedBox(width: 16),
                            Expanded(
                              child: ElevatedButton(
                                onPressed: () {
                                  setState(() {
                                    _selectedYesNo = 'Нет';
                                  });
                                  // Автоматически переходим к следующему вопросу
                                  if (_canProceed()) {
                                    _saveAndNext();
                                  }
                                },
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: _selectedYesNo == 'Нет'
                                      ? Colors.red
                                      : Colors.white.withOpacity(0.06),
                                  foregroundColor: _selectedYesNo == 'Нет'
                                      ? Colors.white
                                      : Colors.white.withOpacity(0.9),
                                  padding: EdgeInsets.symmetric(vertical: 20.h),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12.r),
                                    side: BorderSide(
                                      color: _selectedYesNo == 'Нет'
                                          ? Colors.red
                                          : Colors.white.withOpacity(0.1),
                                    ),
                                  ),
                                ),
                                child: Text(
                                  'Нет',
                                  style: TextStyle(fontSize: 18.sp, fontWeight: FontWeight.bold),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ] else ...[
                        TextField(
                          controller: _textController,
                          maxLines: 5,
                          style: TextStyle(color: Colors.white),
                          decoration: InputDecoration(
                            labelText: 'Введите ответ',
                            labelStyle: TextStyle(color: Colors.white.withOpacity(0.5)),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12.r),
                              borderSide: BorderSide(color: Colors.white.withOpacity(0.2)),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12.r),
                              borderSide: BorderSide(color: Colors.white.withOpacity(0.2)),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12.r),
                              borderSide: BorderSide(color: _gold, width: 2),
                            ),
                            filled: true,
                            fillColor: Colors.white.withOpacity(0.06),
                          ),
                          onChanged: (_) => setState(() {}),
                          onSubmitted: (_) {
                            if (_canProceed()) {
                              _saveAndNext();
                            }
                          },
                        ),
                      ],

                      SizedBox(height: 32),

                      // Скрываем кнопки Назад/Далее для вопросов Да/Нет (автопереход по нажатию)
                      if (!question.isYesNo)
                      Row(
                        children: [
                          // Кнопка "Назад"
                          if (_currentQuestionIndex > 0) ...[
                            Expanded(
                              child: Container(
                                decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(0.06),
                                  borderRadius: BorderRadius.circular(14.r),
                                  border: Border.all(color: Colors.white.withOpacity(0.1)),
                                ),
                                child: Material(
                                  color: Colors.transparent,
                                  child: InkWell(
                                    onTap: _isSubmitting ? null : _previousQuestion,
                                    borderRadius: BorderRadius.circular(14.r),
                                    child: Padding(
                                      padding: EdgeInsets.symmetric(vertical: 18.h),
                                      child: Row(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          Icon(
                                            Icons.arrow_back_ios_rounded,
                                            size: 18,
                                            color: Colors.white.withOpacity(0.7),
                                          ),
                                          SizedBox(width: 8),
                                          Text(
                                            'Назад',
                                            style: TextStyle(
                                              fontSize: 16.sp,
                                              fontWeight: FontWeight.bold,
                                              color: Colors.white.withOpacity(0.7),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            SizedBox(width: 12),
                          ],
                          // Кнопка "Далее" / "Отправить"
                          Expanded(
                            child: Container(
                              decoration: BoxDecoration(
                                color: (_isSubmitting || !_canProceed())
                                    ? Colors.white.withOpacity(0.06)
                                    : _gold,
                                borderRadius: BorderRadius.circular(14.r),
                                border: Border.all(
                                  color: (_isSubmitting || !_canProceed())
                                      ? Colors.white.withOpacity(0.1)
                                      : _gold,
                                ),
                              ),
                              child: Material(
                                color: Colors.transparent,
                                child: InkWell(
                                  onTap: (_isSubmitting || !_canProceed())
                                      ? null
                                      : (_currentQuestionIndex < _questions!.length - 1
                                          ? () {
                                              _saveAnswer();
                                              _nextQuestion();
                                            }
                                          : _submitReport),
                                  borderRadius: BorderRadius.circular(14.r),
                                  child: Padding(
                                    padding: EdgeInsets.symmetric(vertical: 18.h),
                                    child: _isSubmitting
                                        ? Center(
                                            child: SizedBox(
                                              height: 22,
                                              width: 22,
                                              child: CircularProgressIndicator(
                                                strokeWidth: 2.5,
                                                color: _gold,
                                              ),
                                            ),
                                          )
                                        : Row(
                                            mainAxisAlignment: MainAxisAlignment.center,
                                            children: [
                                              if (_currentQuestionIndex >= _questions!.length - 1) ...[
                                                Icon(
                                                  Icons.send_rounded,
                                                  size: 20,
                                                  color: (_isSubmitting || !_canProceed())
                                                      ? Colors.white.withOpacity(0.3)
                                                      : _night,
                                                ),
                                                SizedBox(width: 10),
                                              ],
                                              Text(
                                                _currentQuestionIndex < _questions!.length - 1
                                                    ? 'Далее'
                                                    : 'Отправить',
                                                style: TextStyle(
                                                  fontSize: 16.sp,
                                                  fontWeight: FontWeight.bold,
                                                  color: (_isSubmitting || !_canProceed())
                                                      ? Colors.white.withOpacity(0.3)
                                                      : _night,
                                                ),
                                              ),
                                              if (_currentQuestionIndex < _questions!.length - 1) ...[
                                                SizedBox(width: 8),
                                                Icon(
                                                  Icons.arrow_forward_ios_rounded,
                                                  size: 18,
                                                  color: (_isSubmitting || !_canProceed())
                                                      ? Colors.white.withOpacity(0.3)
                                                      : _night,
                                                ),
                                              ],
                                            ],
                                          ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),

                      SizedBox(height: 16),
                      LinearProgressIndicator(
                        value: (_currentQuestionIndex + 1) / _questions!.length,
                        backgroundColor: Colors.white.withOpacity(0.1),
                        valueColor: AlwaysStoppedAnimation<Color>(_gold),
                      ),
                      SizedBox(height: 8),
                      Text(
                        '${_currentQuestionIndex + 1} из ${_questions!.length}',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.white.withOpacity(0.5)),
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
}
