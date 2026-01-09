import 'dart:io';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import '../models/recount_question_model.dart';
import '../models/recount_answer_model.dart';
import '../models/recount_report_model.dart';
import '../services/recount_service.dart';
import '../services/recount_points_service.dart';
import '../models/recount_settings_model.dart';

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
  final TextEditingController _quantityController = TextEditingController();
  final TextEditingController _programBalanceController = TextEditingController();
  final TextEditingController _actualBalanceController = TextEditingController();
  String? _selectedAnswer; // "сходится" или "не сходится"
  String? _photoPath;
  bool _isSubmitting = false;
  DateTime? _startedAt;
  DateTime? _completedAt;
  bool _answerSaved = false; // Флаг, что ответ сохранен и заблокирован для изменения

  @override
  void initState() {
    super.initState();
    _startedAt = DateTime.now();
    _loadQuestions();
  }

  Future<void> _loadQuestions() async {
    try {
      final allQuestions = await RecountQuestion.loadQuestions();

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
            print('📊 Баллы сотрудника: ${points.points}, требуется фото: $requiredPhotos, вопросов: $questionsCount');
          }
        } catch (e) {
          print('⚠️ Ошибка загрузки настроек, используем значения по умолчанию: $e');
        }
      } else {
        // Если нет телефона, всё равно загружаем настройки для кол-ва вопросов
        try {
          final settings = await RecountPointsService.getSettings();
          questionsCount = settings.questionsCount;
        } catch (e) {
          print('⚠️ Ошибка загрузки настроек: $e');
        }
      }

      // Выбираем вопросы по алгоритму с учетом настройки
      final selectedQuestions = RecountQuestion.selectQuestions(allQuestions, totalCount: questionsCount);

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
    _quantityController.dispose();
    _programBalanceController.dispose();
    _actualBalanceController.dispose();
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
        if (kIsWeb) {
          final bytes = await photo.readAsBytes();
          final base64String = base64Encode(bytes);
          final dataUrl = 'data:image/jpeg;base64,$base64String';
          setState(() {
            _photoPath = dataUrl;
          });
        } else {
          final appDir = await getApplicationDocumentsDirectory();
          final fileName = 'recount_photo_${DateTime.now().millisecondsSinceEpoch}.jpg';
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

    if (_selectedAnswer == 'сходится') {
      final quantity = int.tryParse(_quantityController.text.trim());
      answer = RecountAnswer(
        question: question.question,
        grade: question.grade,
        answer: 'сходится',
        quantity: quantity,
        photoPath: _photoPath,
        photoRequired: isPhotoRequired,
      );
    } else if (_selectedAnswer == 'не сходится') {
      final programBalance = int.tryParse(_programBalanceController.text.trim());
      final actualBalance = int.tryParse(_actualBalanceController.text.trim());
      final difference = (programBalance ?? 0) - (actualBalance ?? 0);
      
      answer = RecountAnswer(
        question: question.question,
        grade: question.grade,
        answer: 'не сходится',
        programBalance: programBalance,
        actualBalance: actualBalance,
        difference: difference,
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
        final quantity = int.tryParse(_quantityController.text.trim());
        if (quantity == null || quantity < 0 || quantity > 1000) {
          return false;
        }
      } else if (_selectedAnswer == 'не сходится') {
        final programBalance = int.tryParse(_programBalanceController.text.trim());
        final actualBalance = int.tryParse(_actualBalanceController.text.trim());
        if (programBalance == null || actualBalance == null) {
          return false;
        }
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
      _answers[_currentQuestionIndex] = RecountAnswer(
        question: answer.question,
        grade: answer.grade,
        answer: answer.answer,
        quantity: answer.quantity,
        programBalance: answer.programBalance,
        actualBalance: answer.actualBalance,
        difference: answer.difference,
        photoPath: _photoPath,
        photoRequired: answer.photoRequired,
      );
    }

    if (_currentQuestionIndex < _selectedQuestions!.length - 1) {
      setState(() {
        _currentQuestionIndex++;
        _selectedAnswer = null;
        _quantityController.clear();
        _programBalanceController.clear();
        _actualBalanceController.clear();
        _photoPath = null;
        _answerSaved = false; // Сбрасываем флаг для нового вопроса
        
        // Загружаем сохраненный ответ, если есть
        if (_currentQuestionIndex < _answers.length) {
          final savedAnswer = _answers[_currentQuestionIndex];
          if (savedAnswer.answer.isNotEmpty) {
            // Если ответ уже сохранен, показываем его как заблокированный
            _selectedAnswer = savedAnswer.answer;
            _answerSaved = true; // Помечаем как сохраненный
            if (savedAnswer.answer == 'сходится') {
              _quantityController.text = savedAnswer.quantity?.toString() ?? '';
            } else if (savedAnswer.answer == 'не сходится') {
              _programBalanceController.text = savedAnswer.programBalance?.toString() ?? '';
              _actualBalanceController.text = savedAnswer.actualBalance?.toString() ?? '';
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
      print('❌ Ошибка отправки отчета: $e');
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
                    // Поля ввода в зависимости от ответа
                    if (_selectedAnswer == 'сходится')
                      Card(
                        color: Colors.white.withOpacity(0.95),
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              const Text(
                                'Количество:',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF004D40),
                                ),
                              ),
                              const SizedBox(height: 8),
                              TextField(
                                controller: _quantityController,
                                keyboardType: TextInputType.number,
                                enabled: !_answerSaved, // Блокируем после сохранения
                                decoration: const InputDecoration(
                                  hintText: 'Введите количество (0-1000)',
                                  border: OutlineInputBorder(),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    if (_selectedAnswer == 'не сходится')
                      Card(
                        color: Colors.white.withOpacity(0.95),
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              const Text(
                                'Остаток по программе:',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF004D40),
                                ),
                              ),
                              const SizedBox(height: 8),
                              TextField(
                                controller: _programBalanceController,
                                keyboardType: TextInputType.number,
                                enabled: !_answerSaved, // Блокируем после сохранения
                                decoration: const InputDecoration(
                                  hintText: 'Введите число',
                                  border: OutlineInputBorder(),
                                ),
                              ),
                              const SizedBox(height: 16),
                              const Text(
                                'Фактический остаток:',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF004D40),
                                ),
                              ),
                              const SizedBox(height: 8),
                              TextField(
                                controller: _actualBalanceController,
                                keyboardType: TextInputType.number,
                                enabled: !_answerSaved, // Блокируем после сохранения
                                decoration: const InputDecoration(
                                  hintText: 'Введите число',
                                  border: OutlineInputBorder(),
                                ),
                              ),
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
                            _quantityController.clear();
                            _programBalanceController.clear();
                            _actualBalanceController.clear();
                            _photoPath = null;
                            _answerSaved = false; // Сбрасываем флаг
                            
                            if (_currentQuestionIndex < _answers.length) {
                              final savedAnswer = _answers[_currentQuestionIndex];
                              if (savedAnswer.answer.isNotEmpty) {
                                _selectedAnswer = savedAnswer.answer;
                                _answerSaved = true; // Помечаем как сохраненный
                                if (savedAnswer.answer == 'сходится') {
                                  _quantityController.text = savedAnswer.quantity?.toString() ?? '';
                                } else if (savedAnswer.answer == 'не сходится') {
                                  _programBalanceController.text = savedAnswer.programBalance?.toString() ?? '';
                                  _actualBalanceController.text = savedAnswer.actualBalance?.toString() ?? '';
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
                      onPressed: _isSubmitting ? null : _nextQuestion,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _answerSaved && _photoRequiredIndices.contains(_currentQuestionIndex) && _photoPath == null
                            ? Colors.orange
                            : const Color(0xFF004D40),
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

