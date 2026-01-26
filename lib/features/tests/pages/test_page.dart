import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';
import '../../../core/utils/logger.dart';
import '../../../core/services/report_notification_service.dart';
import '../../employees/services/user_role_service.dart';
import '../models/test_model.dart';
import '../models/test_result_model.dart';
import '../services/test_result_service.dart';

/// Страница тестирования
class TestPage extends StatefulWidget {
  const TestPage({super.key});

  @override
  State<TestPage> createState() => _TestPageState();
}

class _TestPageState extends State<TestPage> with TickerProviderStateMixin {
  List<TestQuestion> _questions = [];
  int _currentQuestionIndex = 0;
  int _score = 0;
  String? _selectedAnswer;
  Map<int, String> _userAnswers = {};
  Timer? _timer;
  int _timeRemaining = 420; // 7 минут в секундах
  bool _testStarted = false;
  bool _testFinished = false;
  TestResult? _testResult; // Результат теста с начисленными баллами

  late AnimationController _progressController;
  late AnimationController _questionAnimController;
  late Animation<double> _questionFadeAnimation;
  late AnimationController _pointsAnimController;
  late Animation<double> _pointsScaleAnimation;

  @override
  void initState() {
    super.initState();
    _loadQuestions();
    _progressController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _questionAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _questionFadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _questionAnimController, curve: Curves.easeInOut),
    );
    _pointsAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _pointsScaleAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _pointsAnimController, curve: Curves.elasticOut),
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    _progressController.dispose();
    _questionAnimController.dispose();
    _pointsAnimController.dispose();
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
      _timeRemaining = 420;
    });
    _questionAnimController.forward();
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
    if (_selectedAnswer != null) return;

    final question = _questions[_currentQuestionIndex];
    final isCorrect = answer.trim() == question.correctAnswer.trim();

    setState(() {
      _selectedAnswer = answer;
      _userAnswers[_currentQuestionIndex] = answer;
    });

    final delay = isCorrect ? 1500 : 2000;

    Future.delayed(Duration(milliseconds: delay), () {
      if (mounted && !_testFinished && _selectedAnswer == answer) {
        _nextQuestion();
      }
    });
  }

  void _nextQuestion() async {
    if (_currentQuestionIndex < _questions.length - 1) {
      await _questionAnimController.reverse();
      setState(() {
        _currentQuestionIndex++;
        _selectedAnswer = _userAnswers.containsKey(_currentQuestionIndex)
            ? _userAnswers[_currentQuestionIndex]
            : null;
      });
      _questionAnimController.forward();
    } else {
      _finishTest();
    }
  }

  void _finishTest({bool timeExpired = false}) async {
    _timer?.cancel();

    if (timeExpired) {
      setState(() {
        _testFinished = true;
      });
      _showTimeExpiredDialog();
    } else {
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

      await _saveTestResult(score);
      _showResultsDialog();
    }
  }

  Future<void> _saveTestResult(int score) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final employeePhone = prefs.getString('user_phone') ?? '';

      String employeeName = prefs.getString('currentEmployeeName') ??
                            prefs.getString('user_employee_name') ??
                            prefs.getString('user_display_name') ??
                            prefs.getString('user_name') ??
                            '';

      if (employeeName.isEmpty && employeePhone.isNotEmpty) {
        try {
          final roleData = await UserRoleService.checkEmployeeViaAPI(employeePhone);
          if (roleData != null && roleData.employeeName != null && roleData.employeeName!.isNotEmpty) {
            employeeName = roleData.employeeName!;
          }
        } catch (e) {
          Logger.warning('Не удалось загрузить имя сотрудника: $e');
        }
      }

      if (employeeName.isEmpty) {
        employeeName = 'Неизвестный сотрудник';
      }

      // Получаем адрес магазина
      String? shopAddress = prefs.getString('user_shop_address') ??
                           prefs.getString('selected_shop_address');

      // Если адрес магазина не найден, пытаемся получить из UserRoleService
      if (shopAddress == null || shopAddress.isEmpty) {
        try {
          final roleData = await UserRoleService.checkEmployeeViaAPI(employeePhone);
          if (roleData != null && roleData.shopAddress != null && roleData.shopAddress!.isNotEmpty) {
            shopAddress = roleData.shopAddress!;
          }
        } catch (e) {
          Logger.warning('Не удалось загрузить адрес магазина: $e');
        }
      }

      final timeSpent = 420 - _timeRemaining;

      final result = await TestResultService.saveResult(
        employeeName: employeeName,
        employeePhone: employeePhone.replaceAll(RegExp(r'[\s\+]'), ''),
        score: score,
        totalQuestions: _questions.length,
        timeSpent: timeSpent,
        shopAddress: shopAddress,
      );

      // Сохраняем результат с начисленными баллами
      if (mounted) {
        setState(() {
          _testResult = result;
        });
      }

      await ReportNotificationService.createNotification(
        reportType: ReportType.test,
        reportId: 'test_${DateTime.now().millisecondsSinceEpoch}',
        employeeName: employeeName,
        description: '$score из ${_questions.length}',
      );

      Logger.success('Результат теста сохранен: $employeeName - $score/${_questions.length}');
    } catch (e) {
      Logger.error('Ошибка сохранения результата теста', e);
    }
  }

  void _showTimeExpiredDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.orange.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.timer_off,
                  size: 48,
                  color: Colors.orange,
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                'Время закончено',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'К сожалению, время для теста истекло',
                style: TextStyle(
                  fontSize: 16,
                  color: Colors.grey[600],
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.of(context).pop();
                    Navigator.of(context).pop();
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF004D40),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text(
                    'Понятно',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _getBallsWordForm(double points) {
    final absPoints = points.abs().round();
    if (absPoints % 10 == 1 && absPoints % 100 != 11) {
      return 'балл';
    } else if ([2, 3, 4].contains(absPoints % 10) && ![12, 13, 14].contains(absPoints % 100)) {
      return 'балла';
    } else {
      return 'баллов';
    }
  }

  void _showResultsDialog() {
    // Запускаем анимацию баллов
    _pointsAnimController.reset();
    Future.delayed(const Duration(milliseconds: 300), () {
      if (mounted) {
        _pointsAnimController.forward();
      }
    });

    final percentage = (_score / _questions.length * 100).round();
    Color resultColor;
    String resultMessage;
    IconData resultIcon;

    if (percentage >= 80) {
      resultColor = Colors.green;
      resultMessage = 'Отличный результат!';
      resultIcon = Icons.emoji_events;
    } else if (percentage >= 60) {
      resultColor = Colors.orange;
      resultMessage = 'Хороший результат!';
      resultIcon = Icons.thumb_up;
    } else {
      resultColor = Colors.red;
      resultMessage = 'Нужно подучить материал';
      resultIcon = Icons.school;
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: resultColor.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  resultIcon,
                  size: 48,
                  color: resultColor,
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                'Тест завершён',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                decoration: BoxDecoration(
                  color: resultColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  children: [
                    Text(
                      '$_score / ${_questions.length}',
                      style: TextStyle(
                        fontSize: 42,
                        fontWeight: FontWeight.bold,
                        color: resultColor,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '$percentage%',
                      style: TextStyle(
                        fontSize: 18,
                        color: resultColor,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Text(
                resultMessage,
                style: TextStyle(
                  fontSize: 16,
                  color: Colors.grey[700],
                  fontWeight: FontWeight.w500,
                ),
              ),
              // Отображаем начисленные баллы
              if (_testResult?.points != null) ...[
                const SizedBox(height: 20),
                ScaleTransition(
                  scale: _pointsScaleAnimation,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    decoration: BoxDecoration(
                      color: (_testResult!.points! >= 0 ? Colors.green : Colors.red).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: _testResult!.points! >= 0 ? Colors.green : Colors.red,
                        width: 2,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _testResult!.points! >= 0 ? Icons.add_circle : Icons.remove_circle,
                          color: _testResult!.points! >= 0 ? Colors.green : Colors.red,
                          size: 24,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '${_testResult!.points! >= 0 ? "+" : ""}${_testResult!.points!.toStringAsFixed(1)} ${_getBallsWordForm(_testResult!.points!)}',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: _testResult!.points! >= 0 ? Colors.green[700] : Colors.red[700],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.of(context).pop();
                    Navigator.of(context).pop();
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF004D40),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text(
                    'Готово',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_testStarted) {
      return _buildStartScreen();
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

    return _buildQuestionScreen();
  }

  Widget _buildStartScreen() {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFF004D40),
              Color(0xFF00695C),
            ],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              // AppBar
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.arrow_back, color: Colors.white),
                    ),
                    const Expanded(
                      child: Text(
                        'Тестирование',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    const SizedBox(width: 48),
                  ],
                ),
              ),
              // Content
              Expanded(
                child: Center(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        // Icon
                        Container(
                          padding: const EdgeInsets.all(24),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.15),
                            shape: BoxShape.circle,
                          ),
                          child: Container(
                            padding: const EdgeInsets.all(20),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.2),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.quiz_outlined,
                              size: 64,
                              color: Colors.white,
                            ),
                          ),
                        ),
                        const SizedBox(height: 40),
                        // Title
                        const Text(
                          'Готовы к тесту?',
                          style: TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          '20 вопросов • 7 минут',
                          style: TextStyle(
                            fontSize: 18,
                            color: Colors.white.withOpacity(0.8),
                          ),
                        ),
                        const SizedBox(height: 40),
                        // Info cards
                        Row(
                          children: [
                            Expanded(
                              child: _buildInfoCard(
                                icon: Icons.help_outline,
                                title: '20',
                                subtitle: 'вопросов',
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: _buildInfoCard(
                                icon: Icons.timer_outlined,
                                title: '7',
                                subtitle: 'минут',
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 48),
                        // Start button
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: _questions.isNotEmpty ? _startTest : null,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.white,
                              foregroundColor: const Color(0xFF004D40),
                              padding: const EdgeInsets.symmetric(vertical: 18),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                              elevation: 0,
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(Icons.play_arrow, size: 28),
                                const SizedBox(width: 8),
                                Text(
                                  _questions.isNotEmpty ? 'Начать тест' : 'Загрузка...',
                                  style: const TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
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
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInfoCard({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.15),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Icon(icon, color: Colors.white, size: 28),
          const SizedBox(height: 8),
          Text(
            title,
            style: const TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          Text(
            subtitle,
            style: TextStyle(
              fontSize: 14,
              color: Colors.white.withOpacity(0.8),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuestionScreen() {
    final question = _questions[_currentQuestionIndex];
    final isCorrect = _selectedAnswer == question.correctAnswer;
    final hasSelected = _selectedAnswer != null;
    final progress = (_currentQuestionIndex + 1) / _questions.length;
    final isTimeWarning = _timeRemaining <= 60;

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFF004D40),
              Color(0xFF00695C),
            ],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              // Header
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: () => _showExitConfirmation(),
                      icon: const Icon(Icons.close, color: Colors.white),
                    ),
                    Expanded(
                      child: Column(
                        children: [
                          Text(
                            'Вопрос ${_currentQuestionIndex + 1} из ${_questions.length}',
                            style: const TextStyle(
                              fontSize: 16,
                              color: Colors.white70,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: isTimeWarning
                            ? Colors.red.withOpacity(0.2)
                            : Colors.white.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.timer,
                            size: 18,
                            color: isTimeWarning ? Colors.red[300] : Colors.white,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            _formatTime(_timeRemaining),
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: isTimeWarning ? Colors.red[300] : Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              // Progress bar
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: progress,
                    backgroundColor: Colors.white.withOpacity(0.2),
                    valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
                    minHeight: 6,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              // Question card
              Expanded(
                child: FadeTransition(
                  opacity: _questionFadeAnimation,
                  child: Container(
                    margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.1),
                          blurRadius: 20,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                    child: Column(
                      children: [
                        // Question
                        Expanded(
                          child: SingleChildScrollView(
                            padding: const EdgeInsets.all(24),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 6,
                                  ),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF004D40).withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: Text(
                                    'Вопрос ${_currentQuestionIndex + 1}',
                                    style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      color: Color(0xFF004D40),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  question.question,
                                  style: const TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.w600,
                                    height: 1.4,
                                  ),
                                ),
                                const SizedBox(height: 24),
                                // Options
                                ...question.options.asMap().entries.map((entry) {
                                  final index = entry.key;
                                  final option = entry.value;
                                  return _buildOptionButton(
                                    option: option,
                                    index: index,
                                    isSelected: _selectedAnswer == option,
                                    isCorrectOption: option == question.correctAnswer,
                                    hasSelected: hasSelected,
                                    isCorrect: isCorrect,
                                  );
                                }),
                              ],
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

  Widget _buildOptionButton({
    required String option,
    required int index,
    required bool isSelected,
    required bool isCorrectOption,
    required bool hasSelected,
    required bool isCorrect,
  }) {
    Color backgroundColor = Colors.grey[100]!;
    Color borderColor = Colors.grey[300]!;
    Color textColor = Colors.black87;
    IconData? trailingIcon;
    Color? iconColor;

    if (hasSelected) {
      if (isSelected) {
        if (isCorrect) {
          backgroundColor = Colors.green.withOpacity(0.1);
          borderColor = Colors.green;
          textColor = Colors.green[800]!;
          trailingIcon = Icons.check_circle;
          iconColor = Colors.green;
        } else {
          backgroundColor = Colors.red.withOpacity(0.1);
          borderColor = Colors.red;
          textColor = Colors.red[800]!;
          trailingIcon = Icons.cancel;
          iconColor = Colors.red;
        }
      } else if (isCorrectOption) {
        backgroundColor = Colors.green.withOpacity(0.1);
        borderColor = Colors.green;
        textColor = Colors.green[800]!;
        trailingIcon = Icons.check_circle;
        iconColor = Colors.green;
      }
    }

    final letters = ['A', 'B', 'C', 'D', 'E', 'F'];
    final letter = index < letters.length ? letters[index] : '';

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: hasSelected ? null : () => _selectAnswer(option),
        borderRadius: BorderRadius.circular(16),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: backgroundColor,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: borderColor, width: 2),
          ),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: hasSelected && (isSelected || isCorrectOption)
                      ? borderColor.withOpacity(0.2)
                      : const Color(0xFF004D40).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Center(
                  child: Text(
                    letter,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: hasSelected && (isSelected || isCorrectOption)
                          ? borderColor
                          : const Color(0xFF004D40),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  option,
                  style: TextStyle(
                    fontSize: 16,
                    color: textColor,
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                  ),
                ),
              ),
              if (trailingIcon != null)
                Icon(trailingIcon, color: iconColor, size: 24),
            ],
          ),
        ),
      ),
    );
  }

  void _showExitConfirmation() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Выйти из теста?'),
        content: const Text('Прогресс не будет сохранён'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Отмена'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              Navigator.pop(context);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
            ),
            child: const Text('Выйти'),
          ),
        ],
      ),
    );
  }
}
