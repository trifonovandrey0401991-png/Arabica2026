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
  final Map<int, String> _userAnswers = {};
  Timer? _timer;
  int _timeRemaining = 420; // 7 минут в секундах
  bool _testStarted = false;
  bool _testFinished = false;
  TestResult? _testResult;

  late AnimationController _progressController;
  late AnimationController _questionAnimController;
  late Animation<double> _questionFadeAnimation;
  late AnimationController _pointsAnimController;
  late Animation<double> _pointsScaleAnimation;

  // Единая палитра приложения
  static const Color _emerald = Color(0xFF1A4D4D);
  static const Color _emeraldDark = Color(0xFF0D2E2E);
  static const Color _night = Color(0xFF051515);
  static const Color _gold = Color(0xFFD4AF37);
  static const Color _goldLight = Color(0xFFE8C860);

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

      String? shopAddress = prefs.getString('user_shop_address') ??
                           prefs.getString('selected_shop_address');

      final timeSpent = 420 - _timeRemaining;

      final result = await TestResultService.saveResult(
        employeeName: employeeName,
        employeePhone: employeePhone.replaceAll(RegExp(r'[\s\+]'), ''),
        score: score,
        totalQuestions: _questions.length,
        timeSpent: timeSpent,
        shopAddress: shopAddress,
      );

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
      builder: (ctx) => Dialog(
        backgroundColor: _emeraldDark,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: Colors.orange.withOpacity(0.15),
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.orange.withOpacity(0.3)),
                ),
                child: const Icon(
                  Icons.timer_off_rounded,
                  size: 44,
                  color: Colors.orange,
                ),
              ),
              const SizedBox(height: 22),
              const Text(
                'Время закончено',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'К сожалению, время для теста истекло',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.white.withOpacity(0.6),
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 28),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.of(ctx).pop();
                    Navigator.of(context).pop();
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _gold.withOpacity(0.2),
                    foregroundColor: _gold,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                      side: BorderSide(color: _gold.withOpacity(0.4)),
                    ),
                    elevation: 0,
                  ),
                  child: const Text(
                    'Понятно',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
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
      resultColor = const Color(0xFF4CAF50);
      resultMessage = 'Отличный результат!';
      resultIcon = Icons.emoji_events_rounded;
    } else if (percentage >= 60) {
      resultColor = Colors.orange;
      resultMessage = 'Хороший результат!';
      resultIcon = Icons.thumb_up_rounded;
    } else {
      resultColor = const Color(0xFFEF5350);
      resultMessage = 'Нужно подучить материал';
      resultIcon = Icons.school_rounded;
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Dialog(
        backgroundColor: _emeraldDark,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Иконка результата
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: resultColor.withOpacity(0.15),
                  shape: BoxShape.circle,
                  border: Border.all(color: resultColor.withOpacity(0.3)),
                ),
                child: Icon(
                  resultIcon,
                  size: 44,
                  color: resultColor,
                ),
              ),
              const SizedBox(height: 22),
              const Text(
                'Тест завершён',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 20),
              // Счёт
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 18),
                decoration: BoxDecoration(
                  color: resultColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: resultColor.withOpacity(0.3)),
                ),
                child: Column(
                  children: [
                    Text(
                      '$_score / ${_questions.length}',
                      style: TextStyle(
                        fontSize: 40,
                        fontWeight: FontWeight.w800,
                        color: resultColor,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '$percentage%',
                      style: TextStyle(
                        fontSize: 16,
                        color: resultColor.withOpacity(0.8),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              Text(
                resultMessage,
                style: TextStyle(
                  fontSize: 15,
                  color: Colors.white.withOpacity(0.7),
                  fontWeight: FontWeight.w500,
                ),
              ),
              // Начисленные баллы
              if (_testResult?.points != null) ...[
                const SizedBox(height: 18),
                ScaleTransition(
                  scale: _pointsScaleAnimation,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    decoration: BoxDecoration(
                      color: (_testResult!.points! >= 0 ? _gold : Colors.red).withOpacity(0.12),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: (_testResult!.points! >= 0 ? _gold : Colors.red).withOpacity(0.4),
                        width: 1.5,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _testResult!.points! >= 0 ? Icons.add_circle_rounded : Icons.remove_circle_rounded,
                          color: _testResult!.points! >= 0 ? _gold : Colors.red,
                          size: 22,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '${_testResult!.points! >= 0 ? "+" : ""}${_testResult!.points!.toStringAsFixed(1)} ${_getBallsWordForm(_testResult!.points!)}',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                            color: _testResult!.points! >= 0 ? _goldLight : Colors.red[300],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 26),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.of(ctx).pop();
                    Navigator.of(context).pop();
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _gold.withOpacity(0.2),
                    foregroundColor: _gold,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                      side: BorderSide(color: _gold.withOpacity(0.4)),
                    ),
                    elevation: 0,
                  ),
                  child: const Text(
                    'Готово',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
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
      return Scaffold(
        backgroundColor: _night,
        body: const Center(child: CircularProgressIndicator(color: _gold)),
      );
    }

    if (_questions.isEmpty) {
      return Scaffold(
        backgroundColor: _night,
        body: Center(
          child: Text(
            'Вопросы не загружены',
            style: TextStyle(color: Colors.white.withOpacity(0.6)),
          ),
        ),
      );
    }

    return _buildQuestionScreen();
  }

  // ─────────── СТАРТОВЫЙ ЭКРАН ───────────

  Widget _buildStartScreen() {
    return Scaffold(
      backgroundColor: _night,
      body: Container(
        decoration: const BoxDecoration(
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
              // AppBar
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: Icon(
                        Icons.arrow_back_ios_new_rounded,
                        color: Colors.white.withOpacity(0.8),
                        size: 22,
                      ),
                    ),
                    const Expanded(
                      child: Text(
                        'Тестирование',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.w400,
                          letterSpacing: 1,
                        ),
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
                        // Иконка
                        Container(
                          width: 110,
                          height: 110,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.white.withOpacity(0.05),
                            border: Border.all(color: _gold.withOpacity(0.2), width: 2),
                          ),
                          child: Container(
                            margin: const EdgeInsets.all(15),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: _gold.withOpacity(0.12),
                              border: Border.all(color: _gold.withOpacity(0.3)),
                            ),
                            child: Icon(
                              Icons.quiz_rounded,
                              size: 40,
                              color: _gold,
                            ),
                          ),
                        ),
                        const SizedBox(height: 36),
                        // Заголовок
                        const Text(
                          'Готовы к тесту?',
                          style: TextStyle(
                            fontSize: 26,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                            letterSpacing: 0.5,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          '20 вопросов • 7 минут',
                          style: TextStyle(
                            fontSize: 15,
                            color: Colors.white.withOpacity(0.5),
                            letterSpacing: 0.3,
                          ),
                        ),
                        const SizedBox(height: 36),
                        // Информационные карточки
                        Row(
                          children: [
                            Expanded(
                              child: _buildInfoCard(
                                icon: Icons.help_outline_rounded,
                                title: '20',
                                subtitle: 'вопросов',
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: _buildInfoCard(
                                icon: Icons.timer_outlined,
                                title: '7',
                                subtitle: 'минут',
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 44),
                        // Кнопка старта
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: _questions.isNotEmpty ? _startTest : null,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _gold.withOpacity(0.2),
                              foregroundColor: _gold,
                              disabledBackgroundColor: Colors.white.withOpacity(0.05),
                              disabledForegroundColor: Colors.white.withOpacity(0.3),
                              padding: const EdgeInsets.symmetric(vertical: 18),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                                side: BorderSide(
                                  color: _questions.isNotEmpty
                                      ? _gold.withOpacity(0.5)
                                      : Colors.white.withOpacity(0.1),
                                ),
                              ),
                              elevation: 0,
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.play_arrow_rounded,
                                  size: 26,
                                  color: _questions.isNotEmpty ? _gold : Colors.white.withOpacity(0.3),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  _questions.isNotEmpty ? 'Начать тест' : 'Загрузка...',
                                  style: const TextStyle(
                                    fontSize: 17,
                                    fontWeight: FontWeight.w600,
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
        color: Colors.white.withOpacity(0.06),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
      ),
      child: Column(
        children: [
          Icon(icon, color: _gold.withOpacity(0.7), size: 26),
          const SizedBox(height: 10),
          Text(
            title,
            style: const TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w800,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            style: TextStyle(
              fontSize: 13,
              color: Colors.white.withOpacity(0.5),
            ),
          ),
        ],
      ),
    );
  }

  // ─────────── ЭКРАН ВОПРОСОВ ───────────

  Widget _buildQuestionScreen() {
    final question = _questions[_currentQuestionIndex];
    final isCorrect = _selectedAnswer == question.correctAnswer;
    final hasSelected = _selectedAnswer != null;
    final progress = (_currentQuestionIndex + 1) / _questions.length;
    final isTimeWarning = _timeRemaining <= 60;

    return Scaffold(
      backgroundColor: _night,
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [_emerald, _emeraldDark, _night],
            stops: [0.0, 0.25, 1.0],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              // Хедер с таймером
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 12, 6),
                child: Row(
                  children: [
                    // Кнопка выхода
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.white.withOpacity(0.1)),
                      ),
                      child: IconButton(
                        onPressed: () => _showExitConfirmation(),
                        icon: Icon(
                          Icons.close_rounded,
                          color: Colors.white.withOpacity(0.7),
                          size: 22,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    // Номер вопроса
                    Expanded(
                      child: Text(
                        'Вопрос ${_currentQuestionIndex + 1} / ${_questions.length}',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: Colors.white.withOpacity(0.6),
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    // Таймер
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: isTimeWarning
                            ? Colors.red.withOpacity(0.15)
                            : _gold.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isTimeWarning
                              ? Colors.red.withOpacity(0.3)
                              : _gold.withOpacity(0.3),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.timer_rounded,
                            size: 16,
                            color: isTimeWarning ? Colors.red[300] : _gold,
                          ),
                          const SizedBox(width: 5),
                          Text(
                            _formatTime(_timeRemaining),
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              fontFamily: 'monospace',
                              color: isTimeWarning ? Colors.red[300] : _goldLight,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              // Прогресс-бар
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: progress,
                    backgroundColor: Colors.white.withOpacity(0.1),
                    valueColor: AlwaysStoppedAnimation<Color>(_gold.withOpacity(0.8)),
                    minHeight: 4,
                  ),
                ),
              ),
              const SizedBox(height: 8),

              // Карточка вопроса
              Expanded(
                child: FadeTransition(
                  opacity: _questionFadeAnimation,
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Текст вопроса
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [
                                _gold.withOpacity(0.12),
                                _gold.withOpacity(0.04),
                              ],
                            ),
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(color: _gold.withOpacity(0.25)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Бейдж номера вопроса
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                                decoration: BoxDecoration(
                                  color: _gold.withOpacity(0.15),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Text(
                                  'Вопрос ${_currentQuestionIndex + 1}',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: _gold,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 14),
                              Text(
                                question.question,
                                style: TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.w600,
                                  height: 1.5,
                                  color: Colors.white.withOpacity(0.95),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                        // Варианты ответов
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
    Color bgColor = Colors.white.withOpacity(0.06);
    Color borderColor = Colors.white.withOpacity(0.12);
    Color textColor = Colors.white.withOpacity(0.85);
    Color letterBgColor = _emerald.withOpacity(0.5);
    Color letterColor = Colors.white.withOpacity(0.7);
    IconData? trailingIcon;
    Color? iconColor;

    if (hasSelected) {
      if (isSelected) {
        if (isCorrect) {
          // Правильный ответ
          bgColor = const Color(0xFF4CAF50).withOpacity(0.12);
          borderColor = const Color(0xFF4CAF50).withOpacity(0.5);
          textColor = const Color(0xFF81C784);
          letterBgColor = const Color(0xFF4CAF50).withOpacity(0.2);
          letterColor = const Color(0xFF81C784);
          trailingIcon = Icons.check_circle_rounded;
          iconColor = const Color(0xFF4CAF50);
        } else {
          // Неправильный ответ
          bgColor = Colors.red.withOpacity(0.12);
          borderColor = Colors.red.withOpacity(0.5);
          textColor = Colors.red[300]!;
          letterBgColor = Colors.red.withOpacity(0.2);
          letterColor = Colors.red[300]!;
          trailingIcon = Icons.cancel_rounded;
          iconColor = Colors.red[400];
        }
      } else if (isCorrectOption) {
        // Подсветка правильного (когда выбран неправильный)
        bgColor = const Color(0xFF4CAF50).withOpacity(0.12);
        borderColor = const Color(0xFF4CAF50).withOpacity(0.5);
        textColor = const Color(0xFF81C784);
        letterBgColor = const Color(0xFF4CAF50).withOpacity(0.2);
        letterColor = const Color(0xFF81C784);
        trailingIcon = Icons.check_circle_rounded;
        iconColor = const Color(0xFF4CAF50);
      } else {
        // Неактивные варианты после выбора
        bgColor = Colors.white.withOpacity(0.03);
        borderColor = Colors.white.withOpacity(0.06);
        textColor = Colors.white.withOpacity(0.3);
        letterBgColor = Colors.white.withOpacity(0.05);
        letterColor = Colors.white.withOpacity(0.2);
      }
    }

    final letters = ['A', 'B', 'C', 'D', 'E', 'F'];
    final letter = index < letters.length ? letters[index] : '';

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        onTap: hasSelected ? null : () => _selectAnswer(option),
        borderRadius: BorderRadius.circular(14),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          padding: const EdgeInsets.all(15),
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: borderColor, width: 1.5),
          ),
          child: Row(
            children: [
              // Буква варианта
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: letterBgColor,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Center(
                  child: Text(
                    letter,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: letterColor,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              // Текст ответа
              Expanded(
                child: Text(
                  option,
                  style: TextStyle(
                    fontSize: 14,
                    color: textColor,
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                    height: 1.4,
                  ),
                ),
              ),
              if (trailingIcon != null) ...[
                const SizedBox(width: 8),
                Icon(trailingIcon, color: iconColor, size: 22),
              ],
            ],
          ),
        ),
      ),
    );
  }

  void _showExitConfirmation() {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: _emeraldDark,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(0.12),
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.red.withOpacity(0.25)),
                ),
                child: Icon(Icons.exit_to_app_rounded, size: 32, color: Colors.red[300]),
              ),
              const SizedBox(height: 18),
              const Text(
                'Выйти из теста?',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Прогресс не будет сохранён',
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.white.withOpacity(0.5),
                ),
              ),
              const SizedBox(height: 22),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(ctx),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white.withOpacity(0.7),
                        side: BorderSide(color: Colors.white.withOpacity(0.15)),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text('Отмена', style: TextStyle(fontSize: 14)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () {
                        Navigator.pop(ctx);
                        Navigator.pop(context);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red.withOpacity(0.2),
                        foregroundColor: Colors.red[300],
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(color: Colors.red.withOpacity(0.3)),
                        ),
                        elevation: 0,
                      ),
                      child: const Text(
                        'Выйти',
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
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
  }
}
