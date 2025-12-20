import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import 'shift_question_model.dart';
import 'shift_report_model.dart';
import 'shift_report_service.dart';
import 'google_drive_service.dart';

/// Страница с вопросами пересменки
class ShiftQuestionsPage extends StatefulWidget {
  final String employeeName;
  final String shopAddress;

  const ShiftQuestionsPage({
    super.key,
    required this.employeeName,
    required this.shopAddress,
  });

  @override
  State<ShiftQuestionsPage> createState() => _ShiftQuestionsPageState();
}

class _ShiftQuestionsPageState extends State<ShiftQuestionsPage> {
  List<ShiftQuestion>? _questions;
  bool _isLoading = true;
  List<ShiftAnswer> _answers = [];
  int _currentQuestionIndex = 0;
  final TextEditingController _textController = TextEditingController();
  final TextEditingController _numberController = TextEditingController();
  String? _photoPath;
  String? _selectedYesNo; // 'Да' или 'Нет'
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _loadQuestions();
  }

  Future<void> _loadQuestions() async {
    try {
      // Фильтруем вопросы по магазину сотрудника
      final questions = await ShiftQuestion.loadQuestions(shopAddress: widget.shopAddress);
      print('📋 Загружено вопросов: ${questions.length}');
      print('📋 Магазин сотрудника: "${widget.shopAddress}"');
      print('📋 Длина адреса магазина: ${widget.shopAddress.length}');
      for (var q in questions) {
        if (q.isPhotoOnly) {
          print('📋 Вопрос с фото: "${q.question}"');
          print('   ID вопроса: ${q.id}');
          if (q.referencePhotos != null) {
            print('   Эталонные фото (ключи): ${q.referencePhotos!.keys.toList()}');
            print('   Эталонные фото (количество): ${q.referencePhotos!.length}');
            // Проверяем точное совпадение
            if (q.referencePhotos!.containsKey(widget.shopAddress)) {
              print('   ✅ Есть эталонное фото для магазина: ${q.referencePhotos![widget.shopAddress]}');
            } else {
              print('   ❌ Нет эталонного фото для магазина "${widget.shopAddress}"');
              // Проверяем частичное совпадение
              for (var key in q.referencePhotos!.keys) {
                print('      Сравниваем: "${widget.shopAddress}" vs "$key"');
                if (key.contains(widget.shopAddress) || widget.shopAddress.contains(key)) {
                  print('      ⚠️ Найдено частичное совпадение!');
                }
              }
            }
          } else {
            print('   ❌ Нет эталонных фото в вопросе');
          }
        }
      }
      setState(() {
        _questions = questions;
        _isLoading = false;
      });
    } catch (e) {
      print('❌ Ошибка загрузки вопросов: $e');
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
              title: const Text('Выберите источник'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ListTile(
                    leading: const Icon(Icons.camera_alt),
                    title: const Text('Камера'),
                    onTap: () => Navigator.pop(context, ImageSource.camera),
                  ),
                  ListTile(
                    leading: const Icon(Icons.photo_library),
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
      print('❌ Ошибка при выборе фото: $e');
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
        _photoPath = null;
        _selectedYesNo = null;
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
      // Эталонное фото должно быть из question.referencePhotos[shopAddress]
      String? referencePhotoUrl;
      print('💾 Сохранение ответа на вопрос с фото: "${question.question}"');
      print('   Магазин: ${widget.shopAddress}');
      print('   Фото сотрудника: $_photoPath');
      print('   referencePhotos в вопросе: ${question.referencePhotos}');
      if (question.referencePhotos != null && 
          question.referencePhotos!.containsKey(widget.shopAddress)) {
        referencePhotoUrl = question.referencePhotos![widget.shopAddress];
        print('✅ Сохраняем эталонное фото ИЗ ВОПРОСА: $referencePhotoUrl');
        print('   Фото сотрудника (НЕ эталонное!): $_photoPath');
        // Дополнительная проверка: убеждаемся, что эталонное фото НЕ равно фото сотрудника
        if (referencePhotoUrl == _photoPath) {
          print('❌❌❌ ОШИБКА: Эталонное фото совпадает с фото сотрудника! Это неправильно!');
        }
      } else {
        print('⚠️ Нет эталонного фото в вопросе для магазина: ${widget.shopAddress}');
        print('   Доступные магазины: ${question.referencePhotos?.keys.toList()}');
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

  Future<void> _submitReport() async {
    if (_questions == null) return;
    
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

      final List<ShiftAnswer> syncedAnswers = [];
      for (var answer in _answers) {
        if (answer.photoPath != null && answer.photoDriveId == null) {
          try {
            final fileName = '${reportId}_${_answers.indexOf(answer)}.jpg';
            final driveId = await GoogleDriveService.uploadPhoto(
              answer.photoPath!,
              fileName,
            );
            if (driveId != null) {
              syncedAnswers.add(ShiftAnswer(
                question: answer.question,
                textAnswer: answer.textAnswer,
                numberAnswer: answer.numberAnswer,
                photoPath: answer.photoPath,
                photoDriveId: driveId,
              ));
            } else {
              // Если не удалось загрузить, сохраняем без photoDriveId
              print('⚠️ Фото не загружено в Google Drive, сохраняем локально');
              syncedAnswers.add(answer);
            }
          } catch (e) {
            print('⚠️ Исключение при загрузке фото: $e');
            syncedAnswers.add(answer);
          }
        } else {
          syncedAnswers.add(answer);
        }
      }

      final report = ShiftReport(
        id: reportId,
        employeeName: widget.employeeName,
        shopAddress: widget.shopAddress,
        createdAt: now,
        answers: syncedAnswers,
        isSynced: true,
      );

      // Сохраняем на сервере
      final saved = await ShiftReportService.saveReport(report);
      
      if (!saved) {
        // Если не удалось сохранить на сервере, сохраняем локально как резерв
        await ShiftReport.saveReport(report);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Отчет успешно сохранен'),
            backgroundColor: Colors.green,
          ),
        );
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
        appBar: AppBar(
          title: const Text('Загрузка вопросов'),
          backgroundColor: const Color(0xFF004D40),
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_questions == null || _questions!.isEmpty) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Ошибка'),
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
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.error_outline, size: 64, color: Colors.red),
                const SizedBox(height: 16),
                const Text(
                  'Что-то пошло не так, попробуйте позже',
                  style: TextStyle(color: Colors.white, fontSize: 18),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Назад'),
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

    return Scaffold(
      appBar: AppBar(
        title: Text('Вопрос ${_currentQuestionIndex + 1}'),
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
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    question.question,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 24),

              if (question.isNumberOnly) ...[
                TextField(
                  controller: _numberController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: 'Введите число',
                    border: OutlineInputBorder(),
                    filled: true,
                    fillColor: Colors.white,
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
                  // Получаем эталонное фото из вопроса для этого магазина
                  if (question.referencePhotos != null && 
                      question.referencePhotos!.containsKey(widget.shopAddress)) ...[
                    print('🖼️ Показываем эталонное фото для магазина: ${widget.shopAddress}');
                    print('   URL эталонного фото: ${question.referencePhotos![widget.shopAddress]}');
                    Card(
                      margin: const EdgeInsets.only(bottom: 16),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Эталонное фото (как должно быть):',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF004D40),
                              ),
                            ),
                            const SizedBox(height: 8),
                            Container(
                              height: 200,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: Colors.grey),
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(12),
                                child: Image.network(
                                  question.referencePhotos![widget.shopAddress]!,
                                  fit: BoxFit.cover,
                                  loadingBuilder: (context, child, loadingProgress) {
                                    if (loadingProgress == null) return child;
                                    return const Center(
                                      child: CircularProgressIndicator(),
                                    );
                                  },
                                  errorBuilder: (context, error, stackTrace) {
                                    print('❌ Ошибка загрузки эталонного фото: $error');
                                    return const Center(
                                      child: Column(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          Icon(Icons.error, size: 64, color: Colors.red),
                                          SizedBox(height: 8),
                                          Text('Ошибка загрузки эталонного фото'),
                                        ],
                                      ),
                                    );
                                  },
                                ),
                              ),
                            ),
                            const SizedBox(height: 12),
                            const Text(
                              'Посмотрите на эталонное фото, затем нажмите кнопку ниже для фотографирования',
                              style: TextStyle(
                                fontSize: 14,
                                fontStyle: FontStyle.italic,
                                color: Colors.grey,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ] else ...[
                    print('⚠️ Нет эталонного фото в вопросе для магазина: ${widget.shopAddress}');
                    print('   Доступные магазины в referencePhotos: ${question.referencePhotos?.keys.toList()}');
                  ],
                ],
                if (_photoPath != null)
                  Container(
                    height: 300,
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.grey),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: kIsWeb
                          ? Image.network(
                              _photoPath!,
                              fit: BoxFit.cover,
                              errorBuilder: (context, error, stackTrace) {
                                return const Center(
                                  child: Icon(Icons.error, size: 64),
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
                    print('📷 Нажата кнопка фотографирования');
                    print('   Текущий вопрос: "${question.question}"');
                    print('   Есть эталонное фото: ${question.referencePhotos != null && question.referencePhotos!.containsKey(widget.shopAddress)}');
                    await _takePhoto();
                    if (_photoPath != null) {
                      print('✅ Фото сделано: $_photoPath');
                      // Если фото сделано, автоматически переходим к следующему вопросу
                      if (_canProceed()) {
                        _saveAndNext();
                      }
                    } else {
                      print('⚠️ Фото не было сделано');
                    }
                  },
                  icon: const Icon(Icons.camera_alt),
                  label: Text(_photoPath == null ? 'Сфотографировать' : 'Изменить фото'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF004D40),
                    padding: const EdgeInsets.symmetric(vertical: 16),
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
                              : Colors.grey[300],
                          foregroundColor: _selectedYesNo == 'Да' 
                              ? Colors.white 
                              : Colors.black,
                          padding: const EdgeInsets.symmetric(vertical: 20),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text(
                          'Да',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
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
                              : Colors.grey[300],
                          foregroundColor: _selectedYesNo == 'Нет' 
                              ? Colors.white 
                              : Colors.black,
                          padding: const EdgeInsets.symmetric(vertical: 20),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text(
                          'Нет',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                  ],
                ),
              ] else ...[
                TextField(
                  controller: _textController,
                  maxLines: 5,
                  decoration: const InputDecoration(
                    labelText: 'Введите ответ',
                    border: OutlineInputBorder(),
                    filled: true,
                    fillColor: Colors.white,
                  ),
                  onChanged: (_) => setState(() {}),
                  onSubmitted: (_) {
                    if (_canProceed()) {
                      _saveAndNext();
                    }
                  },
                ),
              ],

              const SizedBox(height: 32),

              Row(
                children: [
                  if (_currentQuestionIndex > 0)
                    Expanded(
                      child: ElevatedButton(
                        onPressed: _isSubmitting ? null : _previousQuestion,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.grey[600],
                          padding: const EdgeInsets.symmetric(vertical: 16),
                        ),
                        child: const Text('Назад'),
                      ),
                    ),
                  if (_currentQuestionIndex > 0) const SizedBox(width: 16),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: (_isSubmitting || !_canProceed())
                          ? null
                          : (_currentQuestionIndex < _questions!.length - 1
                              ? () {
                                  _saveAnswer();
                                  _nextQuestion();
                                }
                              : _submitReport),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF004D40),
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                      child: _isSubmitting
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                              ),
                            )
                          : Text(
                              _currentQuestionIndex < _questions!.length - 1
                                  ? 'Далее'
                                  : 'Отправить',
                            ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 16),
              LinearProgressIndicator(
                value: (_currentQuestionIndex + 1) / _questions!.length,
                backgroundColor: Colors.grey[300],
                valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF004D40)),
              ),
              const SizedBox(height: 8),
              Text(
                '${_currentQuestionIndex + 1} из ${_questions!.length}',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

