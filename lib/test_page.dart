import 'package:flutter/material.dart';
import 'dart:async';
import 'test_model.dart';

/// Страница тестирования
class TestPage extends StatefulWidget {
  const TestPage({super.key});

  @override
  State<TestPage> createState() => _TestPageState();
}

class _TestPageState extends State<TestPage> {
  List<TestQuestion> _questions = [];
  int _currentQuestionIndex = 0;
  int _score = 0;
  String? _selectedAnswer;
  Map<int, String> _userAnswers = {};
  Timer? _timer;
  int _timeRemaining = 420; // 7 минут в секундах
  bool _testStarted = false;
  bool _testFinished = false;

  @override
  void initState() {
    super.initState();
    _loadQuestions();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _loadQuestions() async {
    final allQuestions = await TestQuestion.loadQuestions();
    if (mounted) {
      setState(() {
        _questions = TestQuestion.getRandomQuestions(allQuestions, 20);
      });
    }
  }

  void _startTest() {
    setState(() {
      _testStarted = true;
      _currentQuestionIndex = 0;
      _selectedAnswer = null;
      _timeRemaining = 420; // Сбрасываем таймер
    });
    _startTimer();
  }

  void _startTimer() {
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        setState(() {
          _timeRemaining--;
          if (_timeRemaining <= 0) {
            _timer?.cancel();
            _finishTest(timeExpired: true);
          }
        });
      }
    });
  }

  String _formatTime(int seconds) {
    final minutes = seconds ~/ 60;
    final secs = seconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
  }

  void _selectAnswer(String answer) {
    if (_testFinished) return;
    
    final question = _questions[_currentQuestionIndex];
    final isCorrect = answer == question.correctAnswer;
    
    setState(() {
      _selectedAnswer = answer;
      _userAnswers[_currentQuestionIndex] = answer;
    });

    // Если ответ правильный, автоматически переходим к следующему вопросу через 1.5 секунды
    if (isCorrect) {
      Future.delayed(const Duration(milliseconds: 1500), () {
        if (mounted && !_testFinished) {
          _nextQuestion();
        }
      });
    }
  }

  void _nextQuestion() {
    if (_currentQuestionIndex < _questions.length - 1) {
      setState(() {
        _currentQuestionIndex++;
        _selectedAnswer = _userAnswers[_currentQuestionIndex];
      });
    } else {
      _finishTest();
    }
  }

  void _finishTest({bool timeExpired = false}) {
    _timer?.cancel();
    
    if (timeExpired) {
      setState(() {
        _testFinished = true;
      });
      _showTimeExpiredDialog();
    } else {
      // Подсчитываем баллы
      int score = 0;
      for (int i = 0; i < _questions.length; i++) {
        final userAnswer = _userAnswers[i];
        if (userAnswer != null && userAnswer == _questions[i].correctAnswer) {
          score++;
        }
      }
      
      setState(() {
        _score = score;
        _testFinished = true;
      });
      _showResultsDialog();
    }
  }

  void _showTimeExpiredDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Время закончено'),
        content: const Text('К сожалению, время закончено.'),
        actions: [
          ElevatedButton(
            onPressed: () {
              Navigator.of(context).pop();
              Navigator.of(context).pop();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF004D40),
            ),
            child: const Text('Вернуться назад'),
          ),
        ],
      ),
    );
  }

  void _showResultsDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Результаты теста'),
        content: Text('Вы набрали: $_score баллов'),
        actions: [
          ElevatedButton(
            onPressed: () {
              Navigator.of(context).pop();
              Navigator.of(context).pop();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF004D40),
            ),
            child: const Text('Вернуться назад'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_testStarted) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Тестирование'),
          backgroundColor: const Color(0xFF004D40),
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  Icons.quiz,
                  size: 80,
                  color: Color(0xFF004D40),
                ),
                const SizedBox(height: 24),
                const Text(
                  'Вы готовы приступить к тесту?',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 48),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () {
                      if (_questions.isNotEmpty) {
                        _startTest();
                      } else {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Вопросы не загружены'),
                            backgroundColor: Colors.red,
                          ),
                        );
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF004D40),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                    child: const Text(
                      'Поехали',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.grey[600],
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                    child: const Text(
                      'Назад',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    if (_testFinished) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (_questions.isEmpty) {
      return const Scaffold(
        body: Center(child: Text('Вопросы не загружены')),
      );
    }

    final question = _questions[_currentQuestionIndex];
    final isCorrect = _selectedAnswer == question.correctAnswer;
    final hasSelected = _selectedAnswer != null;
    final isWrongAnswer = hasSelected && !isCorrect;

    return Scaffold(
      appBar: AppBar(
        title: Text('Вопрос ${_currentQuestionIndex + 1} из ${_questions.length}'),
        backgroundColor: const Color(0xFF004D40),
        actions: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Center(
              child: Text(
                _formatTime(_timeRemaining),
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    question.question,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 24),
                  ...question.options.map((option) {
                    final isSelected = _selectedAnswer == option;
                    final isCorrectOption = option == question.correctAnswer;
                    Color? backgroundColor;
                    Color? textColor;

                    if (hasSelected) {
                      if (isSelected) {
                        backgroundColor = isCorrect ? Colors.green : Colors.red;
                        textColor = Colors.white;
                      } else if (isCorrectOption) {
                        backgroundColor = Colors.green.withOpacity(0.3);
                        textColor = Colors.green[900];
                      }
                    }

                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: ElevatedButton(
                        onPressed: () => _selectAnswer(option),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: backgroundColor ?? Colors.grey[200],
                          foregroundColor: textColor ?? Colors.black,
                          padding: const EdgeInsets.symmetric(
                            vertical: 16,
                            horizontal: 16,
                          ),
                          alignment: Alignment.centerLeft,
                        ),
                        child: Text(
                          option,
                          style: const TextStyle(fontSize: 16),
                        ),
                      ),
                    );
                  }),
                ],
              ),
            ),
          ),
          if (isWrongAnswer)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 4,
                    offset: const Offset(0, -2),
                  ),
                ],
              ),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _nextQuestion,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF004D40),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  child: Text(
                    _currentQuestionIndex < _questions.length - 1
                        ? 'Следующий вопрос'
                        : 'Завершить тест',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

