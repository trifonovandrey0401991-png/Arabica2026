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
import 'package:arabica_app/shared/widgets/app_cached_image.dart';
import '../../envelope/pages/envelope_form_page.dart';
import '../../employees/services/employee_service.dart';
import '../../employees/pages/employees_page.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../../core/theme/app_colors.dart';

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
  final List<ShiftHandoverAnswer> _answers = [];
  int _currentQuestionIndex = 0;
  final TextEditingController _textController = TextEditingController();
  final TextEditingController _numberController = TextEditingController();
  String? _photoPath;
  String? _selectedYesNo; // 'Да' или 'Нет'
  bool _isSubmitting = false;

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
          SnackBar(
            content: Text('Что-то пошло не так, попробуйте позже'),
            backgroundColor: Colors.red[700],
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.r)),
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
            builder: (context) => Dialog(
              backgroundColor: AppColors.emeraldDark,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20.r)),
              child: Padding(
                padding: EdgeInsets.all(20.w),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Выберите источник',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 17.sp,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    SizedBox(height: 20),
                    _buildSourceOption(
                      icon: Icons.camera_alt_rounded,
                      label: 'Камера',
                      onTap: () => Navigator.pop(context, ImageSource.camera),
                    ),
                    SizedBox(height: 10),
                    _buildSourceOption(
                      icon: Icons.photo_library_rounded,
                      label: 'Галерея',
                      onTap: () => Navigator.pop(context, ImageSource.gallery),
                    ),
                  ],
                ),
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
            backgroundColor: Colors.red[700],
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.r)),
            duration: Duration(seconds: 5),
          ),
        );
      }
    }
  }

  Widget _buildSourceOption({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 14.h),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.06),
          borderRadius: BorderRadius.circular(12.r),
          border: Border.all(color: Colors.white.withOpacity(0.1)),
        ),
        child: Row(
          children: [
            Icon(icon, color: AppColors.gold, size: 22),
            SizedBox(width: 14),
            Text(
              label,
              style: TextStyle(
                color: Colors.white.withOpacity(0.85),
                fontSize: 15.sp,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
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
            } else if (question.isPhotoOnly || question.isScreenshotOnly) {
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
    } else if (question.isPhotoOnly || question.isScreenshotOnly) {
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
    } else if (question.isPhotoOnly || question.isScreenshotOnly) {
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
      final List<ShiftHandoverAnswer> syncedAnswers = [];
      for (var i = 0; i < _answers.length; i++) {
        final answer = _answers[i];
        if (uploadResults.containsKey(i)) {
          final driveId = uploadResults[i];
          if (driveId != null) {
            Logger.success('Фото ${i + 1} загружено: $driveId');
            syncedAnswers.add(ShiftHandoverAnswer(
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
          Logger.debug('Телефон сотрудника для push: ${Logger.maskPhone(employeePhone)}');
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
          SnackBar(
            content: Text('Отчет успешно сохранен'),
            backgroundColor: Color(0xFF43A047),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.r)),
          ),
        );

        // Для заведующей предлагаем сформировать конверт
        if (widget.targetRole == 'manager') {
          final shouldCreateEnvelope = await showDialog<bool>(
            context: context,
            barrierDismissible: false,
            builder: (context) => Dialog(
              backgroundColor: AppColors.emeraldDark,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20.r)),
              child: Padding(
                padding: EdgeInsets.all(24.w),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: EdgeInsets.all(14.w),
                      decoration: BoxDecoration(
                        color: AppColors.gold.withOpacity(0.15),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(Icons.mail_rounded, color: AppColors.gold, size: 36),
                    ),
                    SizedBox(height: 20),
                    Text(
                      'Сформировать конверт?',
                      style: TextStyle(
                        fontSize: 18.sp,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    SizedBox(height: 10),
                    Text(
                      'Вы закончили сдачу смены.\nХотите сформировать конверт с выручкой?',
                      style: TextStyle(
                        fontSize: 14.sp,
                        color: Colors.white.withOpacity(0.5),
                        height: 1.5,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    SizedBox(height: 24),
                    Row(
                      children: [
                        Expanded(
                          child: GestureDetector(
                            onTap: () => Navigator.of(context).pop(false),
                            child: Container(
                              padding: EdgeInsets.symmetric(vertical: 14.h),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.06),
                                borderRadius: BorderRadius.circular(12.r),
                                border: Border.all(color: Colors.white.withOpacity(0.1)),
                              ),
                              child: Text(
                                'На главную',
                                style: TextStyle(
                                  fontSize: 14.sp,
                                  fontWeight: FontWeight.w500,
                                  color: Colors.white.withOpacity(0.7),
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ),
                          ),
                        ),
                        SizedBox(width: 12),
                        Expanded(
                          child: GestureDetector(
                            onTap: () => Navigator.of(context).pop(true),
                            child: Container(
                              padding: EdgeInsets.symmetric(vertical: 14.h),
                              decoration: BoxDecoration(
                                color: AppColors.gold.withOpacity(0.2),
                                borderRadius: BorderRadius.circular(12.r),
                                border: Border.all(color: AppColors.gold.withOpacity(0.4)),
                              ),
                              child: Text(
                                'Да',
                                style: TextStyle(
                                  fontSize: 14.sp,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.white,
                                ),
                                textAlign: TextAlign.center,
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
        // НЕ вызываем setState после popUntil — страница уходит из дерева
        return;
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Что-то пошло не так, попробуйте позже'),
            backgroundColor: Colors.red[700],
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.r)),
          ),
        );
      }
    }
    // Сбрасываем _isSubmitting только если остались на странице
    if (mounted) setState(() => _isSubmitting = false);
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
                _buildAppBar('Сдача смены'),
                Expanded(
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        SizedBox(
                          width: 48,
                          height: 48,
                          child: CircularProgressIndicator(
                            color: AppColors.gold.withOpacity(0.7),
                            strokeWidth: 3,
                          ),
                        ),
                        SizedBox(height: 20),
                        Text(
                          'Загрузка вопросов...',
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.5),
                            fontSize: 15.sp,
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
      );
    }

    if (_questions == null || _questions!.isEmpty) {
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
                _buildAppBar('Сдача смены'),
                Expanded(
                  child: Center(
                    child: Padding(
                      padding: EdgeInsets.all(32.w),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            width: 80,
                            height: 80,
                            decoration: BoxDecoration(
                              color: Colors.orange.withOpacity(0.12),
                              borderRadius: BorderRadius.circular(20.r),
                            ),
                            child: Icon(
                              Icons.quiz_outlined,
                              size: 40,
                              color: Colors.orange.withOpacity(0.7),
                            ),
                          ),
                          SizedBox(height: 24),
                          Text(
                            'Вопросы не найдены',
                            style: TextStyle(
                              fontSize: 19.sp,
                              fontWeight: FontWeight.w600,
                              color: Colors.white.withOpacity(0.85),
                            ),
                          ),
                          SizedBox(height: 8),
                          Text(
                            'Администратор еще не настроил\nвопросы для сдачи смены',
                            style: TextStyle(
                              fontSize: 14.sp,
                              color: Colors.white.withOpacity(0.4),
                              height: 1.5,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          SizedBox(height: 28),
                          GestureDetector(
                            onTap: () => Navigator.pop(context),
                            child: Container(
                              width: double.infinity,
                              padding: EdgeInsets.symmetric(vertical: 16.h),
                              decoration: BoxDecoration(
                                color: AppColors.gold.withOpacity(0.2),
                                borderRadius: BorderRadius.circular(14.r),
                                border: Border.all(color: AppColors.gold.withOpacity(0.4)),
                              ),
                              child: Text(
                                'Вернуться назад',
                                style: TextStyle(
                                  fontSize: 15.sp,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.white,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ),
                          ),
                        ],
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
      return Scaffold(
        backgroundColor: AppColors.night,
        body: Center(
          child: Text(
            'Все вопросы отвечены',
            style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 16.sp),
          ),
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
              _buildAppBar('Вопрос ${_currentQuestionIndex + 1}'),
              // Прогресс-бар
              _buildProgressBar(progress),
              // Основной контент
              Expanded(
                child: SingleChildScrollView(
                  physics: BouncingScrollPhysics(),
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(16.w, 16.h, 16.w, 24.h),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        // Карточка с вопросом
                        _buildQuestionCard(question),
                        SizedBox(height: 24),
                        // Ввод ответа
                        if (question.isNumberOnly)
                          _buildNumberInput()
                        else if (question.isPhotoOnly || question.isScreenshotOnly)
                          _buildPhotoInput(question)
                        else if (question.isYesNo)
                          _buildYesNoButtons()
                        else
                          _buildTextInput(),
                        SizedBox(height: 24),
                      ],
                    ),
                  ),
                ),
              ),
              // Нижняя панель
              _buildBottomPanel(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAppBar(String title) {
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
            child: Text(
              title,
              style: TextStyle(
                color: Colors.white,
                fontSize: 18.sp,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.3,
              ),
            ),
          ),
          if (_questions != null)
            Container(
              padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 6.h),
              decoration: BoxDecoration(
                color: AppColors.gold.withOpacity(0.15),
                borderRadius: BorderRadius.circular(10.r),
                border: Border.all(color: AppColors.gold.withOpacity(0.3)),
              ),
              child: Text(
                '${_currentQuestionIndex + 1}/${_questions!.length}',
                style: TextStyle(
                  color: AppColors.gold,
                  fontSize: 13.sp,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildProgressBar(double progress) {
    return Container(
      margin: EdgeInsets.fromLTRB(16.w, 8.h, 16.w, 0.h),
      height: 4,
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.08),
        borderRadius: BorderRadius.circular(2.r),
      ),
      child: Stack(
        children: [
          AnimatedContainer(
            duration: Duration(milliseconds: 300),
            curve: Curves.easeInOut,
            width: MediaQuery.of(context).size.width * progress - 32,
            height: 4,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [AppColors.gold.withOpacity(0.8), AppColors.gold],
              ),
              borderRadius: BorderRadius.circular(2.r),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuestionCard(ShiftHandoverQuestion question) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(20.w),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.06),
        borderRadius: BorderRadius.circular(16.r),
        border: Border.all(color: AppColors.gold.withOpacity(0.2)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Иконка типа вопроса
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: AppColors.gold.withOpacity(0.12),
              borderRadius: BorderRadius.circular(14.r),
              border: Border.all(color: AppColors.gold.withOpacity(0.25)),
            ),
            child: Icon(
              _getQuestionIcon(question),
              color: AppColors.gold,
              size: 28,
            ),
          ),
          SizedBox(height: 18),
          // Текст вопроса
          Text(
            question.question,
            style: TextStyle(
              fontSize: 17.sp,
              fontWeight: FontWeight.w600,
              color: Colors.white.withOpacity(0.9),
              height: 1.4,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  IconData _getQuestionIcon(ShiftHandoverQuestion question) {
    if (question.isNumberOnly) return Icons.numbers;
    if (question.isPhotoOnly) return Icons.camera_alt_rounded;
    if (question.isScreenshotOnly) return Icons.screenshot;
    if (question.isYesNo) return Icons.help_outline_rounded;
    return Icons.edit_note_rounded;
  }

  Widget _buildNumberInput() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.06),
        borderRadius: BorderRadius.circular(16.r),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
      ),
      child: TextField(
        controller: _numberController,
        keyboardType: TextInputType.numberWithOptions(decimal: true),
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 32.sp,
          fontWeight: FontWeight.bold,
          color: AppColors.gold,
        ),
        decoration: InputDecoration(
          hintText: '0',
          hintStyle: TextStyle(
            color: Colors.white.withOpacity(0.15),
            fontSize: 32.sp,
            fontWeight: FontWeight.bold,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16.r),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16.r),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16.r),
            borderSide: BorderSide(color: AppColors.gold.withOpacity(0.5), width: 1.5),
          ),
          contentPadding: EdgeInsets.symmetric(horizontal: 24.w, vertical: 24.h),
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
        color: Colors.white.withOpacity(0.06),
        borderRadius: BorderRadius.circular(16.r),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
      ),
      child: TextField(
        controller: _textController,
        maxLines: 4,
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 15.sp,
          height: 1.5,
          color: Colors.white.withOpacity(0.9),
        ),
        decoration: InputDecoration(
          hintText: 'Введите ваш ответ здесь...',
          hintStyle: TextStyle(color: Colors.white.withOpacity(0.2)),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16.r),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16.r),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16.r),
            borderSide: BorderSide(color: AppColors.gold.withOpacity(0.5), width: 1.5),
          ),
          contentPadding: EdgeInsets.all(20.w),
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
            color: Color(0xFF43A047),
            icon: Icons.check_rounded,
            onTap: () {
              setState(() => _selectedYesNo = 'Да');
              if (_canProceed()) {
                _saveAndNext();
              }
            },
          ),
        ),
        SizedBox(width: 14),
        Expanded(
          child: _buildYesNoButton(
            label: 'Нет',
            isSelected: _selectedYesNo == 'Нет',
            color: Color(0xFFE53935),
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
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: Duration(milliseconds: 200),
        padding: EdgeInsets.symmetric(vertical: 24.h),
        decoration: BoxDecoration(
          color: isSelected ? color.withOpacity(0.2) : Colors.white.withOpacity(0.06),
          borderRadius: BorderRadius.circular(16.r),
          border: Border.all(
            color: isSelected ? color.withOpacity(0.5) : Colors.white.withOpacity(0.1),
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: isSelected ? color.withOpacity(0.25) : Colors.white.withOpacity(0.06),
                borderRadius: BorderRadius.circular(14.r),
              ),
              child: Icon(
                icon,
                size: 28,
                color: isSelected ? color : Colors.white.withOpacity(0.4),
              ),
            ),
            SizedBox(height: 12),
            Text(
              label,
              style: TextStyle(
                fontSize: 17.sp,
                fontWeight: FontWeight.w700,
                color: isSelected ? color : Colors.white.withOpacity(0.5),
                letterSpacing: 0.5,
              ),
            ),
          ],
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
            padding: EdgeInsets.all(16.w),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.06),
              borderRadius: BorderRadius.circular(16.r),
              border: Border.all(color: AppColors.emerald.withOpacity(0.3)),
            ),
            child: Column(
              children: [
                // Заголовок
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 6.h),
                  decoration: BoxDecoration(
                    color: AppColors.gold.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(10.r),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.photo_library_rounded, color: AppColors.gold, size: 16),
                      SizedBox(width: 8),
                      Text(
                        'Образец',
                        style: TextStyle(
                          fontSize: 13.sp,
                          fontWeight: FontWeight.w600,
                          color: AppColors.gold,
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(height: 14),
                // Изображение
                Container(
                  height: 280,
                  width: double.infinity,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12.r),
                    color: AppColors.emeraldDark.withOpacity(0.5),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12.r),
                    child: AppCachedImage(
                      imageUrl: referencePhotoUrl,
                      fit: BoxFit.contain,
                      errorWidget: (context, error, stackTrace) {
                        return Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.broken_image_rounded, size: 40, color: Colors.white.withOpacity(0.2)),
                              SizedBox(height: 8),
                              Text(
                                'Не удалось загрузить',
                                style: TextStyle(color: Colors.white.withOpacity(0.3), fontSize: 12.sp),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ),
                SizedBox(height: 12),
                Text(
                  'Сделайте фото как на образце',
                  style: TextStyle(
                    fontSize: 12.sp,
                    color: Colors.white.withOpacity(0.4),
                    fontWeight: FontWeight.w500,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
          SizedBox(height: 16),
        ],

        // Фото сотрудника (если сделано)
        if (_photoPath != null) ...[
          Container(
            width: double.infinity,
            padding: EdgeInsets.all(16.w),
            decoration: BoxDecoration(
              color: Color(0xFF43A047).withOpacity(0.08),
              borderRadius: BorderRadius.circular(16.r),
              border: Border.all(color: Color(0xFF43A047).withOpacity(0.3), width: 1.5),
            ),
            child: Column(
              children: [
                // Заголовок
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 6.h),
                  decoration: BoxDecoration(
                    color: Color(0xFF43A047).withOpacity(0.15),
                    borderRadius: BorderRadius.circular(10.r),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.check_circle_rounded, color: Color(0xFF43A047), size: 16),
                      SizedBox(width: 8),
                      Text(
                        'Ваше фото',
                        style: TextStyle(
                          fontSize: 13.sp,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF43A047),
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(height: 14),
                // Изображение
                Container(
                  height: 240,
                  width: double.infinity,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12.r),
                    color: AppColors.emeraldDark.withOpacity(0.5),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12.r),
                    child: kIsWeb
                        ? AppCachedImage(
                            imageUrl: _photoPath!,
                            fit: BoxFit.cover,
                            errorWidget: (context, error, stackTrace) {
                              return Center(
                                child: Icon(Icons.error_outline, size: 40, color: Colors.white.withOpacity(0.3)),
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
          SizedBox(height: 16),
        ],

        // Кнопка фотографирования
        GestureDetector(
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
          child: Container(
            width: double.infinity,
            padding: EdgeInsets.symmetric(vertical: 16.h),
            decoration: BoxDecoration(
              color: _photoPath == null
                  ? AppColors.gold.withOpacity(0.2)
                  : Colors.white.withOpacity(0.06),
              borderRadius: BorderRadius.circular(14.r),
              border: Border.all(
                color: _photoPath == null
                    ? AppColors.gold.withOpacity(0.4)
                    : Colors.white.withOpacity(0.15),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  _photoPath == null ? Icons.camera_alt_rounded : Icons.refresh_rounded,
                  color: _photoPath == null ? AppColors.gold : Colors.white.withOpacity(0.5),
                  size: 22,
                ),
                SizedBox(width: 10),
                Text(
                  _photoPath == null ? 'Сфотографировать' : 'Переснять',
                  style: TextStyle(
                    fontSize: 15.sp,
                    fontWeight: FontWeight.w600,
                    color: _photoPath == null ? AppColors.gold : Colors.white.withOpacity(0.5),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildBottomPanel() {
    return Container(
      padding: EdgeInsets.fromLTRB(16.w, 14.h, 16.w, 16.h),
      decoration: BoxDecoration(
        color: AppColors.emeraldDark.withOpacity(0.7),
        border: Border(
          top: BorderSide(color: Colors.white.withOpacity(0.06)),
        ),
      ),
      child: _buildNavigationButtons(),
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
            child: GestureDetector(
              onTap: _isSubmitting ? null : _previousQuestion,
              child: Container(
                padding: EdgeInsets.symmetric(vertical: 16.h),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.06),
                  borderRadius: BorderRadius.circular(14.r),
                  border: Border.all(color: Colors.white.withOpacity(0.1)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.arrow_back_ios_rounded,
                      size: 16,
                      color: Colors.white.withOpacity(0.6),
                    ),
                    SizedBox(width: 6),
                    Text(
                      'Назад',
                      style: TextStyle(
                        fontSize: 14.sp,
                        fontWeight: FontWeight.w500,
                        color: Colors.white.withOpacity(0.6),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          SizedBox(width: 12),
        ],

        // Кнопка "Далее" / "Завершить"
        Expanded(
          flex: _currentQuestionIndex > 0 ? 2 : 1,
          child: GestureDetector(
            onTap: (_isSubmitting || !canProceed)
                ? null
                : (isLastQuestion
                    ? _submitReport
                    : () {
                        _saveAnswer();
                        _nextQuestion();
                      }),
            child: AnimatedContainer(
              duration: Duration(milliseconds: 200),
              padding: EdgeInsets.symmetric(vertical: 16.h),
              decoration: BoxDecoration(
                color: (_isSubmitting || !canProceed)
                    ? Colors.white.withOpacity(0.04)
                    : AppColors.gold.withOpacity(0.2),
                borderRadius: BorderRadius.circular(14.r),
                border: Border.all(
                  color: (_isSubmitting || !canProceed)
                      ? Colors.white.withOpacity(0.06)
                      : AppColors.gold.withOpacity(0.4),
                ),
              ),
              child: _isSubmitting
                  ? Center(
                      child: SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          color: AppColors.gold.withOpacity(0.7),
                        ),
                      ),
                    )
                  : Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        if (isLastQuestion) ...[
                          Icon(
                            Icons.check_circle_outline_rounded,
                            size: 20,
                            color: (_isSubmitting || !canProceed)
                                ? Colors.white.withOpacity(0.2)
                                : AppColors.gold,
                          ),
                          SizedBox(width: 8),
                        ],
                        Text(
                          isLastQuestion ? 'Завершить' : 'Далее',
                          style: TextStyle(
                            fontSize: 15.sp,
                            fontWeight: FontWeight.w600,
                            color: (_isSubmitting || !canProceed)
                                ? Colors.white.withOpacity(0.2)
                                : Colors.white,
                          ),
                        ),
                        if (!isLastQuestion) ...[
                          SizedBox(width: 6),
                          Icon(
                            Icons.arrow_forward_ios_rounded,
                            size: 16,
                            color: (_isSubmitting || !canProceed)
                                ? Colors.white.withOpacity(0.2)
                                : AppColors.gold,
                          ),
                        ],
                      ],
                    ),
            ),
          ),
        ),
      ],
    );
  }
}
