import 'dart:io';
import 'dart:convert';
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

  Future<void> _submitReport() async {
    if (_questions == null) return;

    setState(() => _isSubmitting = true);

    try {
      _saveAnswer();

      if (_answers.length != _questions!.length) {
        throw Exception('Не все вопросы отвечены');
      }

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

      final report = ShiftHandoverReport(
        id: reportId,
        employeeName: widget.employeeName,
        shopAddress: widget.shopAddress,
        createdAt: now,
        answers: syncedAnswers,
        isSynced: true,
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
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Отчет успешно сохранен'),
            backgroundColor: Colors.green,
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
          title: const Text('Загрузка...'),
          backgroundColor: _primaryColor,
          foregroundColor: Colors.white,
          elevation: 0,
        ),
        body: const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(color: _primaryColor),
              SizedBox(height: 16),
              Text('Загрузка вопросов...', style: TextStyle(color: Colors.grey)),
            ],
          ),
        ),
      );
    }

    if (_questions == null || _questions!.isEmpty) {
      return Scaffold(
        backgroundColor: _backgroundColor,
        appBar: AppBar(
          title: const Text('Ошибка'),
          backgroundColor: _primaryColor,
          foregroundColor: Colors.white,
          elevation: 0,
        ),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.error_outline, size: 64, color: Colors.grey[400]),
              const SizedBox(height: 16),
              Text(
                'Вопросы не найдены',
                style: TextStyle(fontSize: 18, color: Colors.grey[600]),
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: () => Navigator.pop(context),
                style: ElevatedButton.styleFrom(backgroundColor: _primaryColor),
                child: const Text('Назад', style: TextStyle(color: Colors.white)),
              ),
            ],
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
        title: Text('Вопрос ${_currentQuestionIndex + 1} из ${_questions!.length}'),
        backgroundColor: _primaryColor,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
      ),
      body: Column(
        children: [
          // Прогресс-бар
          Container(
            height: 4,
            child: LinearProgressIndicator(
              value: progress,
              backgroundColor: Colors.grey[300],
              valueColor: const AlwaysStoppedAnimation<Color>(_primaryColor),
            ),
          ),
          // Основной контент
          Expanded(
            child: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    // Карточка с вопросом
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.05),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Column(
                        children: [
                          // Иконка типа вопроса
                          Container(
                            width: 56,
                            height: 56,
                            decoration: BoxDecoration(
                              color: _primaryColor.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Icon(
                              _getQuestionIcon(question),
                              color: _primaryColor,
                              size: 28,
                            ),
                          ),
                          const SizedBox(height: 16),
                          // Текст вопроса
                          Text(
                            question.question,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF2D3748),
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Ввод ответа
                    if (question.isNumberOnly) ...[
                      _buildNumberInput(),
                    ] else if (question.isPhotoOnly) ...[
                      _buildPhotoInput(question),
                    ] else if (question.isYesNo) ...[
                      _buildYesNoButtons(),
                    ] else ...[
                      _buildTextInput(),
                    ],

                    const SizedBox(height: 32),

                    // Кнопки навигации
                    _buildNavigationButtons(),
                  ],
                ),
              ),
            ),
          ),
        ],
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
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _primaryColor.withOpacity(0.3)),
      ),
      child: TextField(
        controller: _numberController,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        textAlign: TextAlign.center,
        style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
        decoration: InputDecoration(
          hintText: 'Введите число',
          hintStyle: TextStyle(color: Colors.grey[400], fontSize: 18),
          border: InputBorder.none,
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

  Widget _buildTextInput() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _primaryColor.withOpacity(0.3)),
      ),
      child: TextField(
        controller: _textController,
        maxLines: 4,
        textAlign: TextAlign.center,
        style: const TextStyle(fontSize: 16),
        decoration: InputDecoration(
          hintText: 'Введите ответ',
          hintStyle: TextStyle(color: Colors.grey[400]),
          border: InputBorder.none,
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
      children: [
        Expanded(
          child: _buildYesNoButton(
            label: 'Да',
            isSelected: _selectedYesNo == 'Да',
            color: Colors.green,
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
            color: Colors.red,
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
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 24),
          decoration: BoxDecoration(
            color: isSelected ? color : Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isSelected ? color : Colors.grey.shade300,
              width: 2,
            ),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: color.withOpacity(0.3),
                      blurRadius: 8,
                      offset: const Offset(0, 4),
                    ),
                  ]
                : null,
          ),
          child: Column(
            children: [
              Icon(
                label == 'Да' ? Icons.check_circle_outline : Icons.cancel_outlined,
                size: 40,
                color: isSelected ? Colors.white : color,
              ),
              const SizedBox(height: 8),
              Text(
                label,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: isSelected ? Colors.white : color,
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
      children: [
        // Эталонное фото (если есть и фото сотрудника еще не сделано)
        if (referencePhotoUrl != null && _photoPath == null) ...[
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: _primaryColor.withOpacity(0.3)),
            ),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.photo_library, color: _primaryColor, size: 20),
                    const SizedBox(width: 8),
                    Text(
                      'Эталонное фото',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: _primaryColor,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Container(
                  height: 300,
                  width: double.infinity,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: _primaryColor.withOpacity(0.2)),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.network(
                      referencePhotoUrl,
                      fit: BoxFit.contain,
                      loadingBuilder: (context, child, loadingProgress) {
                        if (loadingProgress == null) return child;
                        return Center(
                          child: CircularProgressIndicator(
                            color: _primaryColor,
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
                              Icon(Icons.error, size: 48, color: Colors.grey[400]),
                              const SizedBox(height: 8),
                              Text(
                                'Ошибка загрузки',
                                style: TextStyle(color: Colors.grey[500]),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Сделайте фото как на образце выше',
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.grey[600],
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
        ],

        // Фото сотрудника (если сделано)
        if (_photoPath != null) ...[
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.green.withOpacity(0.3)),
            ),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.check_circle, color: Colors.green, size: 20),
                    const SizedBox(width: 8),
                    const Text(
                      'Ваше фото',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Colors.green,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Container(
                  height: 250,
                  width: double.infinity,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.green.withOpacity(0.2)),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: kIsWeb
                        ? Image.network(
                            _photoPath!,
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) {
                              return const Center(child: Icon(Icons.error, size: 64));
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
          const SizedBox(height: 16),
        ],

        // Кнопка фотографирования
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: () async {
              Logger.debug('Нажата кнопка фотографирования');
              await _takePhoto();
              if (_photoPath != null) {
                Logger.success('Фото сделано: $_photoPath');
                if (_canProceed()) {
                  _saveAndNext();
                }
              }
            },
            icon: Icon(_photoPath == null ? Icons.camera_alt : Icons.refresh),
            label: Text(
              _photoPath == null ? 'Сфотографировать' : 'Переснять',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: _primaryColor,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
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
                  padding: const EdgeInsets.symmetric(vertical: 18),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.15),
                        blurRadius: 8,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.arrow_back_ios_rounded,
                        size: 18,
                        color: _primaryColor,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Назад',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: _primaryColor,
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
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 18),
                decoration: BoxDecoration(
                  color: (_isSubmitting || !canProceed)
                      ? Colors.white.withOpacity(0.5)
                      : Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.15),
                      blurRadius: 8,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: _isSubmitting
                    ? Center(
                        child: SizedBox(
                          height: 22,
                          width: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            valueColor: AlwaysStoppedAnimation<Color>(_primaryColor),
                          ),
                        ),
                      )
                    : Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          if (isLastQuestion) ...[
                            Icon(
                              Icons.send_rounded,
                              size: 20,
                              color: (_isSubmitting || !canProceed)
                                  ? Colors.grey
                                  : _primaryColor,
                            ),
                            const SizedBox(width: 10),
                          ],
                          Text(
                            isLastQuestion ? 'Отправить' : 'Далее',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: (_isSubmitting || !canProceed)
                                  ? Colors.grey
                                  : _primaryColor,
                            ),
                          ),
                          if (!isLastQuestion) ...[
                            const SizedBox(width: 8),
                            Icon(
                              Icons.arrow_forward_ios_rounded,
                              size: 18,
                              color: (_isSubmitting || !canProceed)
                                  ? Colors.grey
                                  : _primaryColor,
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
