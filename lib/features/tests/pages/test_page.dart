import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';
import '../../../core/utils/logger.dart';
import '../../../core/services/report_notification_service.dart';
import '../../employees/services/user_role_service.dart';
import '../models/test_model.dart';
import '../models/test_result_model.dart';
import '../services/test_question_service.dart';
import '../services/test_result_service.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../../core/theme/app_colors.dart';

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
  int _durationMinutes = 7;
  int _minimumScore = 0;
  int _timeRemaining = 420;
  bool _testStarted = false;
  bool _testFinished = false;
  TestResult? _testResult;

  late AnimationController _progressController;
  late AnimationController _questionAnimController;
  late Animation<double> _questionFadeAnimation;
  late AnimationController _pointsAnimController;
  late Animation<double> _pointsScaleAnimation;

  static final Color _goldLight = Color(0xFFE8C860);

  @override
  void initState() {
    super.initState();
    _loadQuestions();
    _loadDuration();
    _progressController = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: 300),
    );
    _questionAnimController = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: 400),
    );
    _questionFadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _questionAnimController, curve: Curves.easeInOut),
    );
    _pointsAnimController = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: 600),
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

  Future<void> _loadDuration() async {
    final settings = await TestQuestionService.getTestSettings();
    if (mounted) {
      setState(() {
        _durationMinutes = settings.durationMinutes;
        _minimumScore = settings.minimumScore;
        _timeRemaining = settings.durationMinutes * 60;
      });
    }
  }

  void _startTest() {
    setState(() {
      _testStarted = true;
      _currentQuestionIndex = 0;
      _selectedAnswer = null;
      _timeRemaining = _durationMinutes * 60;
    });
    _questionAnimController.forward();
    _startTimer();
  }

  void _startTimer() {
    _timer = Timer.periodic(Duration(seconds: 1), (timer) {
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

      // Проверяем минимальный проходной балл
      if (_minimumScore > 0 && score < _minimumScore) {
        _showFailedDialog();
      } else {
        _showResultsDialog();
      }
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

      final timeSpent = (_durationMinutes * 60) - _timeRemaining;

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
        backgroundColor: AppColors.emeraldDark,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24.r)),
        child: Padding(
          padding: EdgeInsets.all(28.w),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: EdgeInsets.all(18.w),
                decoration: BoxDecoration(
                  color: Colors.orange.withOpacity(0.15),
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.orange.withOpacity(0.3)),
                ),
                child: Icon(
                  Icons.timer_off_rounded,
                  size: 44,
                  color: Colors.orange,
                ),
              ),
              SizedBox(height: 22),
              Text(
                'Время закончено',
                style: TextStyle(
                  fontSize: 22.sp,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
              SizedBox(height: 10),
              Text(
                'К сожалению, время для теста истекло',
                style: TextStyle(
                  fontSize: 14.sp,
                  color: Colors.white.withOpacity(0.6),
                ),
                textAlign: TextAlign.center,
              ),
              SizedBox(height: 28),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.of(ctx).pop();
                    Navigator.of(context).pop();
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.gold.withOpacity(0.2),
                    foregroundColor: AppColors.gold,
                    padding: EdgeInsets.symmetric(vertical: 14.h),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14.r),
                      side: BorderSide(color: AppColors.gold.withOpacity(0.4)),
                    ),
                    elevation: 0,
                  ),
                  child: Text(
                    'Понятно',
                    style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.w600),
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

  void _retryTest() {
    setState(() {
      _score = 0;
      _selectedAnswer = null;
      _userAnswers.clear();
      _testFinished = false;
      _testStarted = false;
      _testResult = null;
      _currentQuestionIndex = 0;
      _timeRemaining = _durationMinutes * 60;
    });
    _loadQuestions();
  }

  void _showFailedDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Dialog(
        backgroundColor: AppColors.emeraldDark,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24.r)),
        child: Padding(
          padding: EdgeInsets.all(28.w),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Иконка
              Container(
                padding: EdgeInsets.all(18.w),
                decoration: BoxDecoration(
                  color: Color(0xFFEF5350).withOpacity(0.15),
                  shape: BoxShape.circle,
                  border: Border.all(color: Color(0xFFEF5350).withOpacity(0.3)),
                ),
                child: Icon(
                  Icons.close_rounded,
                  size: 44,
                  color: Color(0xFFEF5350),
                ),
              ),
              SizedBox(height: 22),
              Text(
                'Тест не пройден',
                style: TextStyle(
                  fontSize: 22.sp,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
              SizedBox(height: 14),
              // Счёт
              Container(
                padding: EdgeInsets.symmetric(horizontal: 32.w, vertical: 18.h),
                decoration: BoxDecoration(
                  color: Color(0xFFEF5350).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(18.r),
                  border: Border.all(color: Color(0xFFEF5350).withOpacity(0.3)),
                ),
                child: Column(
                  children: [
                    Text(
                      '$_score / ${_questions.length}',
                      style: TextStyle(
                        fontSize: 36.sp,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFFEF5350),
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(height: 14),
              Text(
                'Вы набрали меньше нужного',
                style: TextStyle(
                  fontSize: 15.sp,
                  color: Colors.white.withOpacity(0.7),
                  fontWeight: FontWeight.w500,
                ),
              ),
              SizedBox(height: 6),
              Text(
                'Необходимо: $_minimumScore правильных',
                style: TextStyle(
                  fontSize: 14.sp,
                  color: Colors.white.withOpacity(0.5),
                ),
              ),
              // Начисленные баллы
              if (_testResult?.points != null) ...[
                SizedBox(height: 14),
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 8.h),
                  decoration: BoxDecoration(
                    color: Colors.red.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(12.r),
                    border: Border.all(color: Colors.red.withOpacity(0.3)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _testResult!.points! >= 0 ? Icons.add_circle_rounded : Icons.remove_circle_rounded,
                        color: _testResult!.points! >= 0 ? AppColors.gold : Colors.red,
                        size: 18,
                      ),
                      SizedBox(width: 6),
                      Text(
                        '${_testResult!.points! >= 0 ? "+" : ""}${_testResult!.points!.toStringAsFixed(1)} ${_getBallsWordForm(_testResult!.points!)}',
                        style: TextStyle(
                          fontSize: 14.sp,
                          fontWeight: FontWeight.w600,
                          color: _testResult!.points! >= 0 ? _goldLight : Colors.red[300],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              SizedBox(height: 24),
              // Кнопка "Попробовать ещё раз"
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.of(ctx).pop();
                    _retryTest();
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.gold.withOpacity(0.2),
                    foregroundColor: AppColors.gold,
                    padding: EdgeInsets.symmetric(vertical: 14.h),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14.r),
                      side: BorderSide(color: AppColors.gold.withOpacity(0.4)),
                    ),
                    elevation: 0,
                  ),
                  child: Text(
                    'Попробовать ещё раз',
                    style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
              SizedBox(height: 10),
              // Кнопка "Выйти"
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: () {
                    Navigator.of(ctx).pop();
                    Navigator.of(context).pop();
                  },
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white.withOpacity(0.6),
                    side: BorderSide(color: Colors.white.withOpacity(0.15)),
                    padding: EdgeInsets.symmetric(vertical: 14.h),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14.r),
                    ),
                  ),
                  child: Text(
                    'Выйти',
                    style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.w500),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showResultsDialog() {
    _pointsAnimController.reset();
    Future.delayed(Duration(milliseconds: 300), () {
      if (mounted) {
        _pointsAnimController.forward();
      }
    });

    final percentage = (_score / _questions.length * 100).round();
    Color resultColor;
    String resultMessage;
    IconData resultIcon;

    if (percentage >= 80) {
      resultColor = AppColors.success;
      resultMessage = 'Отличный результат!';
      resultIcon = Icons.emoji_events_rounded;
    } else if (percentage >= 60) {
      resultColor = Colors.orange;
      resultMessage = 'Хороший результат!';
      resultIcon = Icons.thumb_up_rounded;
    } else {
      resultColor = Color(0xFFEF5350);
      resultMessage = 'Нужно подучить материал';
      resultIcon = Icons.school_rounded;
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Dialog(
        backgroundColor: AppColors.emeraldDark,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24.r)),
        child: Padding(
          padding: EdgeInsets.all(28.w),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Иконка результата
              Container(
                padding: EdgeInsets.all(18.w),
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
              SizedBox(height: 22),
              Text(
                'Тест завершён',
                style: TextStyle(
                  fontSize: 22.sp,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
              SizedBox(height: 20),
              // Счёт
              Container(
                padding: EdgeInsets.symmetric(horizontal: 32.w, vertical: 18.h),
                decoration: BoxDecoration(
                  color: resultColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(18.r),
                  border: Border.all(color: resultColor.withOpacity(0.3)),
                ),
                child: Column(
                  children: [
                    Text(
                      '$_score / ${_questions.length}',
                      style: TextStyle(
                        fontSize: 40.sp,
                        fontWeight: FontWeight.w800,
                        color: resultColor,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      '$percentage%',
                      style: TextStyle(
                        fontSize: 16.sp,
                        color: resultColor.withOpacity(0.8),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(height: 14),
              Text(
                resultMessage,
                style: TextStyle(
                  fontSize: 15.sp,
                  color: Colors.white.withOpacity(0.7),
                  fontWeight: FontWeight.w500,
                ),
              ),
              // Начисленные баллы
              if (_testResult?.points != null) ...[
                SizedBox(height: 18),
                ScaleTransition(
                  scale: _pointsScaleAnimation,
                  child: Container(
                    padding: EdgeInsets.symmetric(horizontal: 20.w, vertical: 12.h),
                    decoration: BoxDecoration(
                      color: (_testResult!.points! >= 0 ? AppColors.gold : Colors.red).withOpacity(0.12),
                      borderRadius: BorderRadius.circular(14.r),
                      border: Border.all(
                        color: (_testResult!.points! >= 0 ? AppColors.gold : Colors.red).withOpacity(0.4),
                        width: 1.5,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _testResult!.points! >= 0 ? Icons.add_circle_rounded : Icons.remove_circle_rounded,
                          color: _testResult!.points! >= 0 ? AppColors.gold : Colors.red,
                          size: 22,
                        ),
                        SizedBox(width: 8),
                        Text(
                          '${_testResult!.points! >= 0 ? "+" : ""}${_testResult!.points!.toStringAsFixed(1)} ${_getBallsWordForm(_testResult!.points!)}',
                          style: TextStyle(
                            fontSize: 17.sp,
                            fontWeight: FontWeight.w700,
                            color: _testResult!.points! >= 0 ? _goldLight : Colors.red[300],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
              SizedBox(height: 26),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.of(ctx).pop();
                    Navigator.of(context).pop();
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.gold.withOpacity(0.2),
                    foregroundColor: AppColors.gold,
                    padding: EdgeInsets.symmetric(vertical: 14.h),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14.r),
                      side: BorderSide(color: AppColors.gold.withOpacity(0.4)),
                    ),
                    elevation: 0,
                  ),
                  child: Text(
                    'Готово',
                    style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.w600),
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
        backgroundColor: AppColors.night,
        body: Center(child: CircularProgressIndicator(color: AppColors.gold)),
      );
    }

    if (_questions.isEmpty) {
      return Scaffold(
        backgroundColor: AppColors.night,
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
              // AppBar
              Padding(
                padding: EdgeInsets.fromLTRB(8.w, 8.h, 8.w, 8.h),
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
                    Expanded(
                      child: Text(
                        'Тестирование',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 20.sp,
                          fontWeight: FontWeight.w400,
                          letterSpacing: 1,
                        ),
                      ),
                    ),
                    SizedBox(width: 48),
                  ],
                ),
              ),
              // Content
              Expanded(
                child: Center(
                  child: SingleChildScrollView(
                    padding: EdgeInsets.all(32.w),
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
                            border: Border.all(color: AppColors.gold.withOpacity(0.2), width: 2),
                          ),
                          child: Container(
                            margin: EdgeInsets.all(15.w),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: AppColors.gold.withOpacity(0.12),
                              border: Border.all(color: AppColors.gold.withOpacity(0.3)),
                            ),
                            child: Icon(
                              Icons.quiz_rounded,
                              size: 40,
                              color: AppColors.gold,
                            ),
                          ),
                        ),
                        SizedBox(height: 36),
                        // Заголовок
                        Text(
                          'Готовы к тесту?',
                          style: TextStyle(
                            fontSize: 26.sp,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                            letterSpacing: 0.5,
                          ),
                        ),
                        SizedBox(height: 10),
                        Text(
                          '20 вопросов • $_durationMinutes минут',
                          style: TextStyle(
                            fontSize: 15.sp,
                            color: Colors.white.withOpacity(0.5),
                            letterSpacing: 0.3,
                          ),
                        ),
                        SizedBox(height: 36),
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
                            SizedBox(width: 14),
                            Expanded(
                              child: _buildInfoCard(
                                icon: Icons.timer_outlined,
                                title: '$_durationMinutes',
                                subtitle: 'минут',
                              ),
                            ),
                          ],
                        ),
                        SizedBox(height: 44),
                        // Кнопка старта
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: _questions.isNotEmpty ? _startTest : null,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.gold.withOpacity(0.2),
                              foregroundColor: AppColors.gold,
                              disabledBackgroundColor: Colors.white.withOpacity(0.05),
                              disabledForegroundColor: Colors.white.withOpacity(0.3),
                              padding: EdgeInsets.symmetric(vertical: 18.h),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16.r),
                                side: BorderSide(
                                  color: _questions.isNotEmpty
                                      ? AppColors.gold.withOpacity(0.5)
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
                                  color: _questions.isNotEmpty ? AppColors.gold : Colors.white.withOpacity(0.3),
                                ),
                                SizedBox(width: 8),
                                Text(
                                  _questions.isNotEmpty ? 'Начать тест' : 'Загрузка...',
                                  style: TextStyle(
                                    fontSize: 17.sp,
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
      padding: EdgeInsets.symmetric(vertical: 20.h, horizontal: 16.w),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.06),
        borderRadius: BorderRadius.circular(16.r),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
      ),
      child: Column(
        children: [
          Icon(icon, color: AppColors.gold.withOpacity(0.7), size: 26),
          SizedBox(height: 10),
          Text(
            title,
            style: TextStyle(
              fontSize: 28.sp,
              fontWeight: FontWeight.w800,
              color: Colors.white,
            ),
          ),
          SizedBox(height: 2),
          Text(
            subtitle,
            style: TextStyle(
              fontSize: 13.sp,
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
      backgroundColor: AppColors.night,
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [AppColors.emerald, AppColors.emeraldDark, AppColors.night],
            stops: [0.0, 0.25, 1.0],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              // Хедер с таймером
              Padding(
                padding: EdgeInsets.fromLTRB(8.w, 8.h, 12.w, 6.h),
                child: Row(
                  children: [
                    // Кнопка выхода
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(12.r),
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
                    SizedBox(width: 12),
                    // Номер вопроса
                    Expanded(
                      child: Text(
                        'Вопрос ${_currentQuestionIndex + 1} / ${_questions.length}',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 14.sp,
                          fontWeight: FontWeight.w500,
                          color: Colors.white.withOpacity(0.6),
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                    SizedBox(width: 12),
                    // Таймер
                    Container(
                      padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 8.h),
                      decoration: BoxDecoration(
                        color: isTimeWarning
                            ? Colors.red.withOpacity(0.15)
                            : AppColors.gold.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(12.r),
                        border: Border.all(
                          color: isTimeWarning
                              ? Colors.red.withOpacity(0.3)
                              : AppColors.gold.withOpacity(0.3),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.timer_rounded,
                            size: 16,
                            color: isTimeWarning ? Colors.red[300] : AppColors.gold,
                          ),
                          SizedBox(width: 5),
                          Text(
                            _formatTime(_timeRemaining),
                            style: TextStyle(
                              fontSize: 15.sp,
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
                padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 6.h),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4.r),
                  child: LinearProgressIndicator(
                    value: progress,
                    backgroundColor: Colors.white.withOpacity(0.1),
                    valueColor: AlwaysStoppedAnimation<Color>(AppColors.gold.withOpacity(0.8)),
                    minHeight: 4,
                  ),
                ),
              ),
              SizedBox(height: 8),

              // Карточка вопроса
              Expanded(
                child: FadeTransition(
                  opacity: _questionFadeAnimation,
                  child: SingleChildScrollView(
                    padding: EdgeInsets.fromLTRB(16.w, 4.h, 16.w, 20.h),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Текст вопроса
                        Container(
                          width: double.infinity,
                          padding: EdgeInsets.all(20.w),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [
                                AppColors.gold.withOpacity(0.12),
                                AppColors.gold.withOpacity(0.04),
                              ],
                            ),
                            borderRadius: BorderRadius.circular(18.r),
                            border: Border.all(color: AppColors.gold.withOpacity(0.25)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Бейдж номера вопроса
                              Container(
                                padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 5.h),
                                decoration: BoxDecoration(
                                  color: AppColors.gold.withOpacity(0.15),
                                  borderRadius: BorderRadius.circular(10.r),
                                ),
                                child: Text(
                                  'Вопрос ${_currentQuestionIndex + 1}',
                                  style: TextStyle(
                                    fontSize: 11.sp,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.gold,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                              ),
                              SizedBox(height: 14),
                              Text(
                                question.question,
                                style: TextStyle(
                                  fontSize: 17.sp,
                                  fontWeight: FontWeight.w600,
                                  height: 1.5,
                                  color: Colors.white.withOpacity(0.95),
                                ),
                              ),
                            ],
                          ),
                        ),
                        SizedBox(height: 16),
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
    Color letterBgColor = AppColors.emerald.withOpacity(0.5);
    Color letterColor = Colors.white.withOpacity(0.7);
    IconData? trailingIcon;
    Color? iconColor;

    if (hasSelected) {
      if (isSelected) {
        if (isCorrect) {
          // Правильный ответ
          bgColor = AppColors.success.withOpacity(0.12);
          borderColor = AppColors.success.withOpacity(0.5);
          textColor = AppColors.successLight;
          letterBgColor = AppColors.success.withOpacity(0.2);
          letterColor = AppColors.successLight;
          trailingIcon = Icons.check_circle_rounded;
          iconColor = AppColors.success;
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
        bgColor = AppColors.success.withOpacity(0.12);
        borderColor = AppColors.success.withOpacity(0.5);
        textColor = AppColors.successLight;
        letterBgColor = AppColors.success.withOpacity(0.2);
        letterColor = AppColors.successLight;
        trailingIcon = Icons.check_circle_rounded;
        iconColor = AppColors.success;
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
      padding: EdgeInsets.only(bottom: 10.h),
      child: InkWell(
        onTap: hasSelected ? null : () => _selectAnswer(option),
        borderRadius: BorderRadius.circular(14.r),
        child: AnimatedContainer(
          duration: Duration(milliseconds: 250),
          padding: EdgeInsets.all(15.w),
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(14.r),
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
                  borderRadius: BorderRadius.circular(10.r),
                ),
                child: Center(
                  child: Text(
                    letter,
                    style: TextStyle(
                      fontSize: 15.sp,
                      fontWeight: FontWeight.w700,
                      color: letterColor,
                    ),
                  ),
                ),
              ),
              SizedBox(width: 12),
              // Текст ответа
              Expanded(
                child: Text(
                  option,
                  style: TextStyle(
                    fontSize: 14.sp,
                    color: textColor,
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                    height: 1.4,
                  ),
                ),
              ),
              if (trailingIcon != null) ...[
                SizedBox(width: 8),
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
                  color: Colors.red.withOpacity(0.12),
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.red.withOpacity(0.25)),
                ),
                child: Icon(Icons.exit_to_app_rounded, size: 32, color: Colors.red[300]),
              ),
              SizedBox(height: 18),
              Text(
                'Выйти из теста?',
                style: TextStyle(
                  fontSize: 18.sp,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
              SizedBox(height: 8),
              Text(
                'Прогресс не будет сохранён',
                style: TextStyle(
                  fontSize: 13.sp,
                  color: Colors.white.withOpacity(0.5),
                ),
              ),
              SizedBox(height: 22),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(ctx),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white.withOpacity(0.7),
                        side: BorderSide(color: Colors.white.withOpacity(0.15)),
                        padding: EdgeInsets.symmetric(vertical: 12.h),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12.r),
                        ),
                      ),
                      child: Text('Отмена', style: TextStyle(fontSize: 14.sp)),
                    ),
                  ),
                  SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () {
                        Navigator.pop(ctx);
                        Navigator.pop(context);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red.withOpacity(0.2),
                        foregroundColor: Colors.red[300],
                        padding: EdgeInsets.symmetric(vertical: 12.h),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12.r),
                          side: BorderSide(color: Colors.red.withOpacity(0.3)),
                        ),
                        elevation: 0,
                      ),
                      child: Text(
                        'Выйти',
                        style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.w600),
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
