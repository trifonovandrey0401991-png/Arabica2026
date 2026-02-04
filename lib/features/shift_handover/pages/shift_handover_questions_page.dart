import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import '../models/shift_handover_question_model.dart';
import '../models/shift_handover_report_model.dart';
import '../services/shift_handover_report_service.dart';
import '../../../core/services/photo_upload_service.dart';
import '../../../core/services/report_notification_service.dart';
import '../../../core/utils/logger.dart';
import '../../envelope/pages/envelope_form_page.dart';
import '../../ai_training/pages/shift_ai_verification_page.dart';
import '../../ai_training/services/shift_ai_verification_service.dart';
import '../../shifts/models/shift_shortage_model.dart';
import '../../employees/services/employee_service.dart';
import '../../employees/pages/employees_page.dart';

/// Страница с вопросами сдачи смены
class ShiftHandoverQuestionsPage extends StatefulWidget {
  final String employeeName;
  final String shopAddress;
  final String targetRole; // НОВОЕ: 'employee' или 'manager'

  const ShiftHandoverQuestionsPage({
    super.key,
    required this.employeeName,
    required this.shopAddress,
    required this.targetRole, // НОВОЕ
  });

  @override
  State<ShiftHandoverQuestionsPage> createState() => _ShiftHandoverQuestionsPageState();
}

class _ShiftHandoverQuestionsPageState extends State<ShiftHandoverQuestionsPage> {
  List<ShiftHandoverQuestion>? _questions;
  bool _isLoading = true;
  List<ShiftHandoverAnswer> _answers = [];
  int _currentQuestionIndex = 0;
  final TextEditingController _textController = TextEditingController();
  final TextEditingController _numberController = TextEditingController();
  String? _photoPath;
  String? _selectedYesNo; // 'Да' или 'Нет'
  bool _isSubmitting = false;

  // AI Verification - результаты проверки ИИ
  bool? _aiVerificationPassed;
  bool _aiVerificationSkipped = false;
  List<ShiftShortage> _aiShortages = [];

  // Основные цвета
  static const _primaryColor = Color(0xFF004D40);
  static const _primaryColorLight = Color(0xFF00695C);
  static const _backgroundColor = Color(0xFFF5F5F5);

  /// Нормализовать адрес магазина для сравнения
  String _normalizeShopAddress(String address) {
    return address.toLowerCase().trim().replaceAll(RegExp(r'\s+'), ' ');
  }

  /// Найти эталонное фото для магазина (с учетом нормализации адресов)
  String? _findReferencePhoto(ShiftHandoverQuestion question) {
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
      Logger.debug('   Найдено точное совпадение: "${question.referencePhotos![widget.shopAddress]}"');
      return question.referencePhotos![widget.shopAddress];
    }

    // Затем пробуем найти по нормализованному адресу
    for (var key in question.referencePhotos!.keys) {
      final normalizedKey = _normalizeShopAddress(key);
      Logger.debug('   Сравниваем: "$normalizedKey" == "$normalizedShopAddress" ? ${normalizedKey == normalizedShopAddress}');
      if (normalizedKey == normalizedShopAddress) {
        Logger.debug('   Найдено эталонное фото по нормализованному адресу: "$key" -> "${question.referencePhotos![key]}"');
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
      // Загружаем все вопросы для магазина
      final allQuestions = await ShiftHandoverQuestion.loadQuestions(shopAddress: widget.shopAddress);

      // Фильтруем вопросы по targetRole
      final questions = allQuestions.where((q) {
        return q.targetRole == null ||
               q.targetRole == 'all' ||
               q.targetRole == widget.targetRole;
      }).toList();

      Logger.info('Загружено вопросов: ${questions.length}');
      Logger.debug('Магазин сотрудника: "${widget.shopAddress}"');
      Logger.debug('Целевая роль: "${widget.targetRole}"');
      Logger.debug('Длина адреса магазина: ${widget.shopAddress.length}');
      for (var i = 0; i < questions.length; i++) {
        final q = questions[i];
        if (q.isPhotoOnly) {
          Logger.debug('Вопрос ${i + 1} с фото: "${q.question}"');
          Logger.debug('   ID вопроса: ${q.id}');
          if (q.referencePhotos != null && q.referencePhotos!.isNotEmpty) {
            Logger.debug('   Есть эталонные фото (${q.referencePhotos!.length}):');
            q.referencePhotos!.forEach((key, value) {
              Logger.debug('     - "$key" -> "$value"');
            });
            // Проверяем точное совпадение
            if (q.referencePhotos!.containsKey(widget.shopAddress)) {
              Logger.debug('   Есть эталонное фото для магазина "${widget.shopAddress}": ${q.referencePhotos![widget.shopAddress]}');
            } else {
              Logger.debug('   Нет эталонного фото для магазина "${widget.shopAddress}"');
              // Проверяем нормализованное совпадение
              final normalizedShopAddress = _normalizeShopAddress(widget.shopAddress);
              for (var key in q.referencePhotos!.keys) {
                final normalizedKey = _normalizeShopAddress(key);
                Logger.debug('      Сравниваем нормализованные: "$normalizedKey" == "$normalizedShopAddress" ? ${normalizedKey == normalizedShopAddress}');
                if (normalizedKey == normalizedShopAddress) {
                  Logger.debug('      Найдено совпадение по нормализованному адресу!');
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
          const SnackBar(
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
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: const Text('Выберите источник'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ListTile(
                    leading: const Icon(Icons.camera_alt, color: _primaryColor),
                    title: const Text('Камера'),
                    onTap: () => Navigator.pop(context, ImageSource.camera),
                  ),
                  ListTile(
                    leading: const Icon(Icons.photo_library, color: _primaryColor),
                    title: const Text('Галерея'),
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
          final fileName = 'shift_handover_photo_${DateTime.now().millisecondsSinceEpoch}.jpg';
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
            duration: const Duration(seconds: 5),
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
              Logger.debug('   У следующего вопроса есть эталонное фото: $refPhoto');
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
    await Future.delayed(const Duration(milliseconds: 500));
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
    ShiftHandoverAnswer answer;

    if (question.isNumberOnly) {
      final numberValue = double.tryParse(_numberController.text.trim());
      if (numberValue == null) return;
      answer = ShiftHandoverAnswer(
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
      answer = ShiftHandoverAnswer(
        question: question.question,
        photoPath: _photoPath, // Фото сотрудника (НЕ эталонное!)
        referencePhotoUrl: referencePhotoUrl, // Эталонное фото ИЗ ВОПРОСА (НЕ из фото сотрудника!)
      );
    } else if (question.isYesNo) {
      if (_selectedYesNo == null) return;
      answer = ShiftHandoverAnswer(
        question: question.question,
        textAnswer: _selectedYesNo, // Сохраняем 'Да' или 'Нет'
      );
    } else {
      answer = ShiftHandoverAnswer(
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

  /// Собрать фото из ответов и конвертировать в Uint8List
  Future<List<Uint8List>> _collectPhotosForAiVerification() async {
    final photos = <Uint8List>[];

    for (final answer in _answers) {
      if (answer.photoPath != null) {
        try {
          if (kIsWeb) {
            // Для веб: декодируем base64 из data URL
            if (answer.photoPath!.startsWith('data:')) {
              final base64Data = answer.photoPath!.split(',').last;
              photos.add(base64Decode(base64Data));
            }
          } else {
            // Для мобильных: читаем файл
            final file = File(answer.photoPath!);
            if (await file.exists()) {
              photos.add(await file.readAsBytes());
            }
          }
        } catch (e) {
          Logger.error('Ошибка чтения фото для AI верификации', e);
        }
      }
    }

    return photos;
  }

  /// Проверить есть ли активные AI товары для магазина
  Future<bool> _hasActiveAiProducts() async {
    try {
      final activeProducts = await ShiftAiVerificationService.getActiveAiProducts(widget.shopAddress);
      return activeProducts.isNotEmpty;
    } catch (e) {
      Logger.error('Ошибка проверки активных AI товаров', e);
      return false;
    }
  }

  /// Запустить AI верификацию
  Future<void> _runAiVerification(List<Uint8List> photos) async {
    if (!mounted) return;

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
      // Пользователь пропустил проверку
      _aiVerificationSkipped = true;
      _aiVerificationPassed = null;
      Logger.info('AI верификация пропущена пользователем');
    } else {
      _aiVerificationPassed = result['aiVerificationPassed'] as bool?;
      final shortages = result['shortages'] as List<ShiftShortage>?;
      if (shortages != null) {
        _aiShortages = shortages;
      }
      Logger.info('AI верификация завершена: passed=$_aiVerificationPassed, shortages=${_aiShortages.length}');
    }
  }

  Future<void> _submitReport() async {
    if (_questions == null) return;

    setState(() => _isSubmitting = true);

    try {
      _saveAnswer();

      if (_answers.length != _questions!.length) {
        throw Exception('Не все вопросы отвечены');
      }

      // ========== AI VERIFICATION START ==========
      // Проверяем есть ли фото в ответах и активные AI товары
      final photos = await _collectPhotosForAiVerification();
      if (photos.isNotEmpty) {
        final hasActiveAi = await _hasActiveAiProducts();
        if (hasActiveAi) {
          Logger.info('Найдено ${photos.length} фото и активные AI товары - запускаем верификацию');
          await _runAiVerification(photos);
        } else {
          Logger.info('Нет активных AI товаров для магазина - пропускаем верификацию');
          _aiVerificationSkipped = true;
        }
      } else {
        Logger.info('Нет фото для AI верификации');
        _aiVerificationSkipped = true;
      }

      if (!mounted) return;
      // ========== AI VERIFICATION END ==========

      final now = DateTime.now();
      final reportId = ShiftHandoverReport.generateId(
        widget.employeeName,
        widget.shopAddress,
        now,
      );

      final List<ShiftHandoverAnswer> syncedAnswers = [];
      for (var i = 0; i < _answers.length; i++) {
        final answer = _answers[i];
        Logger.debug('Обработка ответа ${i + 1}/${_answers.length}: "${answer.question}"');
        Logger.debug('   photoPath: ${answer.photoPath}');
        Logger.debug('   photoDriveId: ${answer.photoDriveId}');
        Logger.debug('   referencePhotoUrl: ${answer.referencePhotoUrl}');

        if (answer.photoPath != null && answer.photoDriveId == null) {
          try {
            final fileName = '${reportId}_${i}.jpg';
            Logger.info('Загрузка фото сотрудника на сервер: $fileName');
            Logger.debug('   Путь к фото: ${answer.photoPath}');

            final driveId = await PhotoUploadService.uploadPhoto(
              answer.photoPath!,
              fileName,
            );

            if (driveId != null) {
              Logger.success('Фото сотрудника успешно загружено: $driveId');
              syncedAnswers.add(ShiftHandoverAnswer(
                question: answer.question,
                textAnswer: answer.textAnswer,
                numberAnswer: answer.numberAnswer,
                photoPath: answer.photoPath,
                photoDriveId: driveId,
                referencePhotoUrl: answer.referencePhotoUrl, // Сохраняем эталонное фото
              ));
            } else {
              // Если не удалось загрузить, сохраняем без photoDriveId
              Logger.warning('Фото не загружено на сервер, сохраняем локально');
              syncedAnswers.add(answer);
            }
          } catch (e) {
            Logger.error('Исключение при загрузке фото', e, StackTrace.current);
            syncedAnswers.add(answer);
          }
        } else {
          Logger.debug('Ответ уже имеет photoDriveId или не содержит фото');
          syncedAnswers.add(answer);
        }
      }

      Logger.info('Итого обработано ответов: ${syncedAnswers.length}');
      for (var i = 0; i < syncedAnswers.length; i++) {
        final ans = syncedAnswers[i];
        Logger.debug('   Ответ ${i + 1}: photoPath=${ans.photoPath}, photoDriveId=${ans.photoDriveId}, referencePhotoUrl=${ans.referencePhotoUrl}');
      }

      // Конвертируем AI shortages в Map для сохранения
      final aiShortagesJson = _aiShortages.map((s) => s.toJson()).toList();

      // Получаем телефон сотрудника для push-уведомлений
      String? employeePhone;
      try {
        final employeeId = await EmployeesPage.getCurrentEmployeeId();
        if (employeeId != null) {
          final employees = await EmployeeService.getEmployees();
          final employee = employees.firstWhere(
            (e) => e.id == employeeId,
            orElse: () => throw StateError('Employee not found'),
          );
          employeePhone = employee.phone;
          Logger.debug('Телефон сотрудника для push: $employeePhone');
        }
      } catch (e) {
        Logger.warning('Не удалось получить телефон сотрудника: $e');
      }

      final report = ShiftHandoverReport(
        id: reportId,
        employeeName: widget.employeeName,
        employeePhone: employeePhone,
        shopAddress: widget.shopAddress,
        createdAt: now,
        answers: syncedAnswers,
        isSynced: true,
        // AI Verification результаты
        aiVerificationPassed: _aiVerificationPassed,
        aiVerificationSkipped: _aiVerificationSkipped,
        aiShortages: aiShortagesJson.isNotEmpty ? aiShortagesJson : null,
      );

      // Сохраняем на сервере
      final saved = await ShiftHandoverReportService.saveReport(report);

      if (!saved) {
        // Если не удалось сохранить на сервере, сохраняем локально как резерв
        await ShiftHandoverReport.saveLocal(report);
      }

      // Отправляем уведомление админу о новом отчёте (сдача смены)
      await ReportNotificationService.createNotification(
        reportType: ReportType.shiftReport,
        reportId: reportId,
        employeeName: widget.employeeName,
        shopName: widget.shopAddress,
        description: widget.targetRole == 'manager' ? 'Заведующая' : 'Сотрудник',
      );

      if (mounted) {
        // Показываем результат с информацией об AI верификации
        String successMessage = 'Отчет успешно сохранен';
        if (_aiVerificationPassed == true) {
          successMessage = 'Отчет сохранен. ИИ проверка пройдена!';
        } else if (_aiVerificationPassed == false && _aiShortages.isNotEmpty) {
          successMessage = 'Отчет сохранен. Выявлено недостач: ${_aiShortages.length}';
        }

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(successMessage),
            backgroundColor: _aiVerificationPassed == false ? Colors.orange : Colors.green,
          ),
        );

        // Для заведующей предлагаем сформировать конверт
        if (widget.targetRole == 'manager') {
          final shouldCreateEnvelope = await showDialog<bool>(
            context: context,
            barrierDismissible: false,
            builder: (context) => AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: const Text('Сформировать конверт?'),
              content: const Text(
                'Вы закончили сдачу смены. Хотите сформировать конверт с выручкой?',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text('Нет, на главную'),
                ),
                ElevatedButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _primaryColor,
                  ),
                  child: const Text('Да, сформировать', style: TextStyle(color: Colors.white)),
                ),
              ],
            ),
          );

          if (shouldCreateEnvelope == true && mounted) {
            Navigator.of(context).pushReplacement(
              MaterialPageRoute(
                builder: (context) => EnvelopeFormPage(
                  employeeName: widget.employeeName,
                  shopAddress: widget.shopAddress,
                ),
              ),
            );
            return;
          }
        }

        if (!mounted) return;

        Navigator.of(context).popUntil((route) => route.isFirst);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
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

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        backgroundColor: _backgroundColor,
        appBar: AppBar(
          title: const Text(
            'Сдача смены',
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
          backgroundColor: _primaryColor,
          foregroundColor: Colors.white,
          elevation: 0,
          centerTitle: true,
        ),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  color: _primaryColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Center(
                  child: CircularProgressIndicator(
                    color: _primaryColor,
                    strokeWidth: 3,
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Text(
                'Загрузка вопросов...',
                style: TextStyle(
                  color: Colors.grey[600],
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (_questions == null || _questions!.isEmpty) {
      return Scaffold(
        backgroundColor: _backgroundColor,
        appBar: AppBar(
          title: const Text(
            'Сдача смены',
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
          backgroundColor: _primaryColor,
          foregroundColor: Colors.white,
          elevation: 0,
          centerTitle: true,
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 100,
                  height: 100,
                  decoration: BoxDecoration(
                    color: Colors.orange.shade50,
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: Icon(
                    Icons.quiz_outlined,
                    size: 48,
                    color: Colors.orange.shade400,
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  'Вопросы не найдены',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey[800],
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Администратор еще не настроил\nвопросы для сдачи смены',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey[500],
                    height: 1.5,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 32),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(context),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _primaryColor,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: const Text(
                      'Вернуться назад',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
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
      return const Scaffold(
        body: Center(
          child: Text('Все вопросы отвечены'),
        ),
      );
    }

    final question = _questions![_currentQuestionIndex];
    final progress = (_currentQuestionIndex + 1) / _questions!.length;

    // Логирование для отладки эталонного фото
    if (question.isPhotoOnly && _photoPath == null) {
      Logger.debug('build: Текущий вопрос с фото: "${question.question}"');
      Logger.debug('   Индекс вопроса: $_currentQuestionIndex');
      Logger.debug('   Магазин: ${widget.shopAddress}');
      final referencePhotoUrl = _findReferencePhoto(question);
      if (referencePhotoUrl != null) {
        Logger.debug('   build: Найдено эталонное фото: $referencePhotoUrl');
      } else {
        Logger.debug('   build: Эталонное фото не найдено');
      }
    }

    return Scaffold(
      backgroundColor: _backgroundColor,
      appBar: AppBar(
        title: Text(
          'Вопрос ${_currentQuestionIndex + 1}',
          style: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w600,
          ),
        ),
        backgroundColor: _primaryColor,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Прогресс-бар с анимацией
            Container(
              height: 6,
              decoration: BoxDecoration(
                color: Colors.grey[200],
              ),
              child: Stack(
                children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeInOut,
                    width: MediaQuery.of(context).size.width * progress,
                    height: 6,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [_primaryColor, _primaryColorLight],
                        begin: Alignment.centerLeft,
                        end: Alignment.centerRight,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // Основной контент
            Expanded(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      // Карточка с вопросом
                      Container(
                        width: double.infinity,
                        constraints: const BoxConstraints(maxWidth: 500),
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [
                            BoxShadow(
                              color: _primaryColor.withOpacity(0.08),
                              blurRadius: 20,
                              offset: const Offset(0, 8),
                            ),
                          ],
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // Иконка типа вопроса
                            Container(
                              width: 64,
                              height: 64,
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [
                                    _primaryColor.withOpacity(0.15),
                                    _primaryColorLight.withOpacity(0.1),
                                  ],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: Icon(
                                _getQuestionIcon(question),
                                color: _primaryColor,
                                size: 32,
                              ),
                            ),
                            const SizedBox(height: 20),
                            // Текст вопроса
                            Text(
                              question.question,
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF2D3748),
                                height: 1.4,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 28),

                      // Ввод ответа
                      Container(
                        constraints: const BoxConstraints(maxWidth: 500),
                        child: Column(
                          children: [
                            if (question.isNumberOnly) ...[
                              _buildNumberInput(),
                            ] else if (question.isPhotoOnly) ...[
                              _buildPhotoInput(question),
                            ] else if (question.isYesNo) ...[
                              _buildYesNoButtons(),
                            ] else ...[
                              _buildTextInput(),
                            ],
                          ],
                        ),
                      ),

                      const SizedBox(height: 32),
                    ],
                  ),
                ),
              ),
            ),
            // Нижняя панель с прогрессом и кнопками
            Container(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 20),
              decoration: BoxDecoration(
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.08),
                    blurRadius: 10,
                    offset: const Offset(0, -4),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Текст прогресса
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Text(
                      '${_currentQuestionIndex + 1} из ${_questions!.length}',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: Colors.grey[600],
                      ),
                    ),
                  ),
                  // Кнопки навигации
                  _buildNavigationButtons(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  IconData _getQuestionIcon(ShiftHandoverQuestion question) {
    if (question.isNumberOnly) return Icons.numbers;
    if (question.isPhotoOnly) return Icons.camera_alt_rounded;
    if (question.isYesNo) return Icons.help_outline_rounded;
    return Icons.edit_note_rounded;
  }

  Widget _buildNumberInput() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: _primaryColor.withOpacity(0.08),
            blurRadius: 15,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: TextField(
        controller: _numberController,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 32,
          fontWeight: FontWeight.bold,
          color: _primaryColor,
        ),
        decoration: InputDecoration(
          hintText: '0',
          hintStyle: TextStyle(
            color: Colors.grey[300],
            fontSize: 32,
            fontWeight: FontWeight.bold,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide(color: Colors.grey[200]!, width: 2),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide(color: Colors.grey[200]!, width: 2),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide(color: _primaryColor, width: 2),
          ),
          contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        ),
        onChanged: (_) => setState(() {}),
        onSubmitted: (_) {
          if (_canProceed()) {
            _saveAndNext();
          }
        },
      ),
    );
  }

  Widget _buildTextInput() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: _primaryColor.withOpacity(0.08),
            blurRadius: 15,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: TextField(
        controller: _textController,
        maxLines: 4,
        textAlign: TextAlign.center,
        style: const TextStyle(fontSize: 16, height: 1.5),
        decoration: InputDecoration(
          hintText: 'Введите ваш ответ здесь...',
          hintStyle: TextStyle(color: Colors.grey[400]),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide(color: Colors.grey[200]!, width: 2),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide(color: Colors.grey[200]!, width: 2),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide(color: _primaryColor, width: 2),
          ),
          contentPadding: const EdgeInsets.all(20),
        ),
        onChanged: (_) => setState(() {}),
        onSubmitted: (_) {
          if (_canProceed()) {
            _saveAndNext();
          }
        },
      ),
    );
  }

  Widget _buildYesNoButtons() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Expanded(
          child: _buildYesNoButton(
            label: 'Да',
            isSelected: _selectedYesNo == 'Да',
            color: const Color(0xFF43A047),
            icon: Icons.check_rounded,
            onTap: () {
              setState(() => _selectedYesNo = 'Да');
              if (_canProceed()) {
                _saveAndNext();
              }
            },
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: _buildYesNoButton(
            label: 'Нет',
            isSelected: _selectedYesNo == 'Нет',
            color: const Color(0xFFE53935),
            icon: Icons.close_rounded,
            onTap: () {
              setState(() => _selectedYesNo = 'Нет');
              if (_canProceed()) {
                _saveAndNext();
              }
            },
          ),
        ),
      ],
    );
  }

  Widget _buildYesNoButton({
    required String label,
    required bool isSelected,
    required Color color,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 28),
          decoration: BoxDecoration(
            gradient: isSelected
                ? LinearGradient(
                    colors: [color, color.withOpacity(0.85)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  )
                : null,
            color: isSelected ? null : Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isSelected ? color : Colors.grey.shade200,
              width: isSelected ? 0 : 2,
            ),
            boxShadow: [
              BoxShadow(
                color: isSelected ? color.withOpacity(0.35) : Colors.black.withOpacity(0.06),
                blurRadius: isSelected ? 16 : 10,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: isSelected ? Colors.white.withOpacity(0.2) : color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(
                  icon,
                  size: 32,
                  color: isSelected ? Colors.white : color,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                label,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: isSelected ? Colors.white : color,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPhotoInput(ShiftHandoverQuestion question) {
    final referencePhotoUrl = _findReferencePhoto(question);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // Эталонное фото (если есть и фото сотрудника еще не сделано)
        if (referencePhotoUrl != null && _photoPath == null) ...[
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: _primaryColor.withOpacity(0.1),
                  blurRadius: 15,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Column(
              children: [
                // Заголовок с иконкой
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: _primaryColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.photo_library_rounded, color: _primaryColor, size: 18),
                      const SizedBox(width: 8),
                      Text(
                        'Образец',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: _primaryColor,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                // Изображение
                Container(
                  height: 280,
                  width: double.infinity,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    color: Colors.grey[100],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: Image.network(
                      referencePhotoUrl,
                      fit: BoxFit.contain,
                      loadingBuilder: (context, child, loadingProgress) {
                        if (loadingProgress == null) return child;
                        return Center(
                          child: CircularProgressIndicator(
                            color: _primaryColor,
                            strokeWidth: 3,
                            value: loadingProgress.expectedTotalBytes != null
                                ? loadingProgress.cumulativeBytesLoaded /
                                    loadingProgress.expectedTotalBytes!
                                : null,
                          ),
                        );
                      },
                      errorBuilder: (context, error, stackTrace) {
                        return Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.broken_image_rounded, size: 48, color: Colors.grey[400]),
                              const SizedBox(height: 8),
                              Text(
                                'Не удалось загрузить',
                                style: TextStyle(color: Colors.grey[500], fontSize: 13),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  'Сделайте фото как на образце',
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.grey[600],
                    fontWeight: FontWeight.w500,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
        ],

        // Фото сотрудника (если сделано)
        if (_photoPath != null) ...[
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.green.shade300, width: 2),
              boxShadow: [
                BoxShadow(
                  color: Colors.green.withOpacity(0.15),
                  blurRadius: 15,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Column(
              children: [
                // Заголовок с галочкой
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.green.shade50,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.check_circle_rounded, color: Colors.green.shade600, size: 18),
                      const SizedBox(width: 8),
                      Text(
                        'Ваше фото',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Colors.green.shade700,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                // Изображение
                Container(
                  height: 240,
                  width: double.infinity,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    color: Colors.grey[100],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: kIsWeb
                        ? Image.network(
                            _photoPath!,
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) {
                              return Center(
                                child: Icon(Icons.error_outline, size: 48, color: Colors.grey[400]),
                              );
                            },
                          )
                        : Image.file(
                            File(_photoPath!),
                            fit: BoxFit.cover,
                          ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
        ],

        // Кнопка фотографирования
        SizedBox(
          width: double.infinity,
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () async {
                Logger.debug('Нажата кнопка фотографирования');
                await _takePhoto();
                if (_photoPath != null) {
                  Logger.success('Фото сделано: $_photoPath');
                  if (_canProceed()) {
                    _saveAndNext();
                  }
                }
              },
              borderRadius: BorderRadius.circular(16),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 18),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: _photoPath == null
                        ? [_primaryColor, _primaryColorLight]
                        : [Colors.grey.shade400, Colors.grey.shade500],
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                  ),
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: (_photoPath == null ? _primaryColor : Colors.grey).withOpacity(0.3),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      _photoPath == null ? Icons.camera_alt_rounded : Icons.refresh_rounded,
                      color: Colors.white,
                      size: 24,
                    ),
                    const SizedBox(width: 12),
                    Text(
                      _photoPath == null ? 'Сфотографировать' : 'Переснять',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildNavigationButtons() {
    final isLastQuestion = _currentQuestionIndex >= _questions!.length - 1;
    final canProceed = _canProceed();

    return Row(
      children: [
        // Кнопка "Назад"
        if (_currentQuestionIndex > 0) ...[
          Expanded(
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: _isSubmitting ? null : _previousQuestion,
                borderRadius: BorderRadius.circular(14),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  decoration: BoxDecoration(
                    color: Colors.grey[100],
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: Colors.grey[300]!,
                      width: 1.5,
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.arrow_back_ios_rounded,
                        size: 18,
                        color: Colors.grey[700],
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'Назад',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: Colors.grey[700],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
        ],

        // Кнопка "Далее" / "Отправить"
        Expanded(
          flex: _currentQuestionIndex > 0 ? 2 : 1,
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: (_isSubmitting || !canProceed)
                  ? null
                  : (isLastQuestion
                      ? _submitReport
                      : () {
                          _saveAnswer();
                          _nextQuestion();
                        }),
              borderRadius: BorderRadius.circular(14),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(vertical: 16),
                decoration: BoxDecoration(
                  gradient: (_isSubmitting || !canProceed)
                      ? null
                      : LinearGradient(
                          colors: [_primaryColor, _primaryColorLight],
                          begin: Alignment.centerLeft,
                          end: Alignment.centerRight,
                        ),
                  color: (_isSubmitting || !canProceed) ? Colors.grey[300] : null,
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: (_isSubmitting || !canProceed)
                      ? null
                      : [
                          BoxShadow(
                            color: _primaryColor.withOpacity(0.3),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          ),
                        ],
                ),
                child: _isSubmitting
                    ? const Center(
                        child: SizedBox(
                          height: 22,
                          width: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        ),
                      )
                    : Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          if (isLastQuestion) ...[
                            Icon(
                              Icons.check_circle_outline_rounded,
                              size: 22,
                              color: (_isSubmitting || !canProceed)
                                  ? Colors.grey[600]
                                  : Colors.white,
                            ),
                            const SizedBox(width: 10),
                          ],
                          Text(
                            isLastQuestion ? 'Завершить' : 'Далее',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: (_isSubmitting || !canProceed)
                                  ? Colors.grey[600]
                                  : Colors.white,
                            ),
                          ),
                          if (!isLastQuestion) ...[
                            const SizedBox(width: 8),
                            Icon(
                              Icons.arrow_forward_ios_rounded,
                              size: 18,
                              color: (_isSubmitting || !canProceed)
                                  ? Colors.grey[600]
                                  : Colors.white,
                            ),
                          ],
                        ],
                      ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
