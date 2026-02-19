import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/test_model.dart';
import '../services/test_question_service.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../../core/theme/app_colors.dart';

/// Страница управления вопросами тестирования
class TestQuestionsManagementPage extends StatefulWidget {
  const TestQuestionsManagementPage({super.key});

  @override
  State<TestQuestionsManagementPage> createState() => _TestQuestionsManagementPageState();
}

class _TestQuestionsManagementPageState extends State<TestQuestionsManagementPage> {
  List<TestQuestion> _questions = [];
  List<TestQuestion> _filteredQuestions = [];
  bool _isLoading = true;
  String _searchQuery = '';
  final _searchController = TextEditingController();
  int _testDurationMinutes = 7;
  int _minimumScore = 0;

  @override
  void initState() {
    super.initState();
    _loadQuestions();
    _loadSettings();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _applyFilter() {
    if (_searchQuery.isEmpty) {
      _filteredQuestions = List.from(_questions);
    } else {
      final query = _searchQuery.toLowerCase();
      _filteredQuestions = _questions.where((q) =>
        q.question.toLowerCase().contains(query) ||
        q.options.any((opt) => opt.toLowerCase().contains(query))
      ).toList();
    }
  }

  Future<void> _loadQuestions() async {
    if (mounted) setState(() => _isLoading = true);

    try {
      final questions = await TestQuestionService.getQuestions();
      if (!mounted) return;
      setState(() {
        _questions = questions;
        _applyFilter();
        _isLoading = false;
      });
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка загрузки вопросов: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _loadSettings() async {
    final settings = await TestQuestionService.getTestSettings();
    if (mounted) {
      setState(() {
        _testDurationMinutes = settings.durationMinutes;
        _minimumScore = settings.minimumScore;
      });
    }
  }

  Future<void> _showSettingsDialog() async {
    final result = await showDialog<({int durationMinutes, int minimumScore})>(
      context: context,
      builder: (ctx) => _TestSettingsDialog(
        currentMinutes: _testDurationMinutes,
        currentMinimumScore: _minimumScore,
      ),
    );

    if (result == null) return;

    final changed = result.durationMinutes != _testDurationMinutes ||
        result.minimumScore != _minimumScore;
    if (!changed) return;

    final success = await TestQuestionService.saveTestSettings(
      durationMinutes: result.durationMinutes,
      minimumScore: result.minimumScore,
    );
    if (success) {
      if (!mounted) return;
      setState(() {
        _testDurationMinutes = result.durationMinutes;
        _minimumScore = result.minimumScore;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Настройки сохранены'),
            backgroundColor: Color(0xFF2E7D32),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.r)),
            margin: EdgeInsets.all(16.w),
          ),
        );
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка сохранения настроек'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.r)),
            margin: EdgeInsets.all(16.w),
          ),
        );
      }
    }
  }

  Future<void> _showAddQuestionDialog() async {
    final result = await showModalBottomSheet<TestQuestion>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => TestQuestionFormBottomSheet(),
    );

    if (result != null) {
      await _loadQuestions();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Вопрос успешно добавлен'),
            backgroundColor: Color(0xFF2E7D32),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.r)),
            margin: EdgeInsets.all(16.w),
          ),
        );
      }
    }
  }

  Future<void> _showEditQuestionDialog(TestQuestion question) async {
    final result = await showModalBottomSheet<TestQuestion>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => TestQuestionFormBottomSheet(question: question),
    );

    if (result != null) {
      await _loadQuestions();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Вопрос успешно обновлен'),
            backgroundColor: Color(0xFF2E7D32),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.r)),
            margin: EdgeInsets.all(16.w),
          ),
        );
      }
    }
  }

  Future<void> _deleteQuestion(TestQuestion question) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => _ModernDeleteDialog(question: question),
    );

    if (confirmed == true) {
      final success = await TestQuestionService.deleteQuestion(question.id);
      if (success) {
        await _loadQuestions();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Вопрос удален'),
              backgroundColor: Color(0xFF2E7D32),
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.r)),
              margin: EdgeInsets.all(16.w),
            ),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Ошибка удаления вопроса'),
              backgroundColor: Colors.red,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.r)),
              margin: EdgeInsets.all(16.w),
            ),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
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
              _buildCustomAppBar(),
              _buildStatsBar(),
              Expanded(child: _buildContent()),
            ],
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showAddQuestionDialog,
        backgroundColor: AppColors.gold.withOpacity(0.2),
        icon: Icon(Icons.add_rounded, color: AppColors.gold),
        label: Text(
          'Добавить',
          style: TextStyle(color: AppColors.gold, fontWeight: FontWeight.w600),
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16.r),
          side: BorderSide(color: AppColors.gold.withOpacity(0.4)),
        ),
        elevation: 0,
      ),
    );
  }

  Widget _buildCustomAppBar() {
    return Padding(
      padding: EdgeInsets.fromLTRB(8.w, 8.h, 8.w, 0.h),
      child: Row(
        children: [
          // Кнопка назад
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
          // Заголовок
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Вопросы тестирования',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20.sp,
                    fontWeight: FontWeight.w400,
                    letterSpacing: 0.5,
                  ),
                ),
                Text(
                  '${_questions.length} вопросов',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.5),
                    fontSize: 13.sp,
                  ),
                ),
              ],
            ),
          ),
          // Кнопка настроек
          Container(
            decoration: BoxDecoration(
              color: AppColors.gold.withOpacity(0.12),
              borderRadius: BorderRadius.circular(12.r),
              border: Border.all(color: AppColors.gold.withOpacity(0.25)),
            ),
            child: IconButton(
              icon: Icon(Icons.settings_rounded, color: AppColors.gold, size: 20),
              onPressed: _showSettingsDialog,
              tooltip: 'Настройки теста',
            ),
          ),
          SizedBox(width: 8),
          // Кнопка обновления
          Container(
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.08),
              borderRadius: BorderRadius.circular(12.r),
              border: Border.all(color: Colors.white.withOpacity(0.1)),
            ),
            child: IconButton(
              icon: Icon(Icons.refresh_rounded, color: Colors.white.withOpacity(0.8), size: 20),
              onPressed: _loadQuestions,
              tooltip: 'Обновить',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatsBar() {
    return Padding(
      padding: EdgeInsets.fromLTRB(16.w, 12.h, 16.w, 12.h),
      child: Row(
        children: [
          _buildStatChip(
            Icons.quiz_rounded,
            '${_questions.length}',
            'вопросов',
          ),
          SizedBox(width: 10),
          _buildStatChip(
            Icons.timer_outlined,
            '$_testDurationMinutes',
            'минут',
          ),
          SizedBox(width: 10),
          _buildStatChip(
            Icons.help_outline_rounded,
            '20',
            'в тесте',
          ),
        ],
      ),
    );
  }

  Widget _buildStatChip(IconData icon, String value, String label) {
    return Expanded(
      child: Container(
        padding: EdgeInsets.symmetric(vertical: 10.h, horizontal: 8.w),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.06),
          borderRadius: BorderRadius.circular(12.r),
          border: Border.all(color: Colors.white.withOpacity(0.08)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: AppColors.gold.withOpacity(0.7), size: 16),
            SizedBox(width: 6),
            Text(
              value,
              style: TextStyle(
                color: Colors.white,
                fontSize: 16.sp,
                fontWeight: FontWeight.w700,
              ),
            ),
            SizedBox(width: 4),
            Flexible(
              child: Text(
                label,
                style: TextStyle(
                  color: Colors.white.withOpacity(0.4),
                  fontSize: 11.sp,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent() {
    if (_isLoading) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(AppColors.gold),
              strokeWidth: 3,
            ),
            SizedBox(height: 16),
            Text(
              'Загрузка вопросов...',
              style: TextStyle(
                color: Colors.white.withOpacity(0.5),
                fontSize: 14.sp,
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        // Поиск
        Padding(
          padding: EdgeInsets.fromLTRB(16.w, 0.h, 16.w, 8.h),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.06),
              borderRadius: BorderRadius.circular(14.r),
              border: Border.all(color: Colors.white.withOpacity(0.1)),
            ),
            child: TextField(
              controller: _searchController,
              style: TextStyle(color: Colors.white, fontSize: 14.sp),
              decoration: InputDecoration(
                hintText: 'Поиск по вопросам...',
                hintStyle: TextStyle(color: Colors.white.withOpacity(0.3)),
                prefixIcon: Icon(Icons.search, color: Colors.white.withOpacity(0.3)),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: Icon(Icons.close, size: 18, color: Colors.white.withOpacity(0.4)),
                        onPressed: () {
                          _searchController.clear();
                          if (mounted) setState(() {
                            _searchQuery = '';
                            _applyFilter();
                          });
                        },
                      )
                    : null,
                border: InputBorder.none,
                contentPadding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 14.h),
              ),
              onChanged: (value) {
                if (mounted) setState(() {
                  _searchQuery = value;
                  _applyFilter();
                });
              },
            ),
          ),
        ),
        // Фильтр результат
        if (_searchQuery.isNotEmpty)
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 4.h),
            child: Row(
              children: [
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 5.h),
                  decoration: BoxDecoration(
                    color: AppColors.gold.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10.r),
                  ),
                  child: Text(
                    'Найдено: ${_filteredQuestions.length} из ${_questions.length}',
                    style: TextStyle(
                      color: AppColors.gold,
                      fontSize: 12.sp,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
        // Список
        Expanded(
          child: _filteredQuestions.isEmpty
              ? _buildEmptyState()
              : RefreshIndicator(
                  onRefresh: _loadQuestions,
                  color: AppColors.gold,
                  backgroundColor: AppColors.emeraldDark,
                  child: ListView.builder(
                    padding: EdgeInsets.fromLTRB(16.w, 8.h, 16.w, 100.h),
                    itemCount: _filteredQuestions.length,
                    itemBuilder: (context, index) {
                      final question = _filteredQuestions[index];
                      return _buildQuestionCard(question, index);
                    },
                  ),
                ),
        ),
      ],
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: EdgeInsets.all(24.w),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.05),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white.withOpacity(0.1)),
            ),
            child: Icon(
              _searchQuery.isNotEmpty ? Icons.search_off_rounded : Icons.quiz_outlined,
              size: 48,
              color: Colors.white.withOpacity(0.3),
            ),
          ),
          SizedBox(height: 20),
          Text(
            _searchQuery.isNotEmpty ? 'Вопросы не найдены' : 'Нет вопросов',
            style: TextStyle(
              fontSize: 18.sp,
              fontWeight: FontWeight.w600,
              color: Colors.white.withOpacity(0.7),
            ),
          ),
          SizedBox(height: 8),
          Text(
            _searchQuery.isNotEmpty
                ? 'Попробуйте изменить запрос'
                : 'Нажмите "Добавить" чтобы создать первый вопрос',
            style: TextStyle(
              fontSize: 14.sp,
              color: Colors.white.withOpacity(0.4),
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildQuestionCard(TestQuestion question, int index) {
    return Container(
      margin: EdgeInsets.only(bottom: 10.h),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.06),
        borderRadius: BorderRadius.circular(16.r),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16.r),
        child: InkWell(
          onTap: () => _showEditQuestionDialog(question),
          borderRadius: BorderRadius.circular(16.r),
          child: Padding(
            padding: EdgeInsets.all(14.w),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Заголовок с номером и действиями
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Номер вопроса
                    Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: AppColors.gold.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(10.r),
                      ),
                      child: Center(
                        child: Text(
                          '${index + 1}',
                          style: TextStyle(
                            color: AppColors.gold,
                            fontWeight: FontWeight.bold,
                            fontSize: 13.sp,
                          ),
                        ),
                      ),
                    ),
                    SizedBox(width: 10),
                    // Текст вопроса
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            question.question,
                            style: TextStyle(
                              fontSize: 14.sp,
                              fontWeight: FontWeight.w500,
                              color: Colors.white.withOpacity(0.9),
                              height: 1.4,
                            ),
                          ),
                          SizedBox(height: 4),
                          Row(
                            children: [
                              Icon(Icons.list_alt_rounded, size: 12, color: Colors.white.withOpacity(0.3)),
                              SizedBox(width: 4),
                              Text(
                                '${question.options.length} вариантов ответа',
                                style: TextStyle(
                                  fontSize: 11.sp,
                                  color: Colors.white.withOpacity(0.35),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    // Кнопки действий
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _buildActionIconButton(
                          icon: Icons.edit_outlined,
                          color: AppColors.gold,
                          onPressed: () => _showEditQuestionDialog(question),
                        ),
                        SizedBox(width: 4),
                        _buildActionIconButton(
                          icon: Icons.delete_outline_rounded,
                          color: Colors.red[300]!,
                          onPressed: () => _deleteQuestion(question),
                        ),
                      ],
                    ),
                  ],
                ),
                SizedBox(height: 10),
                // Варианты ответов
                ...question.options.asMap().entries.map((entry) {
                  final isCorrect = entry.value == question.correctAnswer;
                  return Padding(
                    padding: EdgeInsets.only(top: 5.h),
                    child: Container(
                      padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 8.h),
                      decoration: BoxDecoration(
                        color: isCorrect
                            ? AppColors.success.withOpacity(0.1)
                            : Colors.white.withOpacity(0.03),
                        borderRadius: BorderRadius.circular(10.r),
                        border: Border.all(
                          color: isCorrect
                              ? AppColors.success.withOpacity(0.3)
                              : Colors.white.withOpacity(0.06),
                        ),
                      ),
                      child: Row(
                        children: [
                          // Буква варианта
                          Container(
                            width: 22,
                            height: 22,
                            decoration: BoxDecoration(
                              color: isCorrect
                                  ? AppColors.success.withOpacity(0.2)
                                  : Colors.white.withOpacity(0.06),
                              borderRadius: BorderRadius.circular(6.r),
                            ),
                            child: Center(
                              child: Text(
                                String.fromCharCode(65 + entry.key),
                                style: TextStyle(
                                  color: isCorrect
                                      ? AppColors.successLight
                                      : Colors.white.withOpacity(0.4),
                                  fontWeight: FontWeight.w600,
                                  fontSize: 11.sp,
                                ),
                              ),
                            ),
                          ),
                          SizedBox(width: 8),
                          // Текст варианта
                          Expanded(
                            child: Text(
                              entry.value,
                              style: TextStyle(
                                fontSize: 12.sp,
                                color: isCorrect
                                    ? AppColors.successLight
                                    : Colors.white.withOpacity(0.6),
                                fontWeight: isCorrect ? FontWeight.w500 : FontWeight.normal,
                              ),
                            ),
                          ),
                          if (isCorrect)
                            Icon(
                              Icons.check_circle_rounded,
                              color: AppColors.success,
                              size: 16,
                            ),
                        ],
                      ),
                    ),
                  );
                }),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildActionIconButton({
    required IconData icon,
    required Color color,
    required VoidCallback onPressed,
  }) {
    return InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(8.r),
      child: Container(
        padding: EdgeInsets.all(7.w),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(8.r),
        ),
        child: Icon(icon, color: color, size: 16),
      ),
    );
  }
}

/// Диалог настроек теста (время в минутах)
class _TestSettingsDialog extends StatefulWidget {
  final int currentMinutes;
  final int currentMinimumScore;

  _TestSettingsDialog({
    required this.currentMinutes,
    required this.currentMinimumScore,
  });

  @override
  State<_TestSettingsDialog> createState() => _TestSettingsDialogState();
}

class _TestSettingsDialogState extends State<_TestSettingsDialog> {
  static final _goldLight = Color(0xFFE8C860);

  late int _selectedMinutes;
  late int _selectedMinScore;
  late TextEditingController _minutesController;
  late TextEditingController _minScoreController;

  @override
  void initState() {
    super.initState();
    _selectedMinutes = widget.currentMinutes;
    _selectedMinScore = widget.currentMinimumScore;
    _minutesController = TextEditingController(text: '$_selectedMinutes');
    _minScoreController = TextEditingController(text: '$_selectedMinScore');
  }

  @override
  void dispose() {
    _minutesController.dispose();
    _minScoreController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppColors.emeraldDark,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24.r)),
      child: SingleChildScrollView(
        child: Padding(
          padding: EdgeInsets.all(28.w),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Иконка
              Container(
                padding: EdgeInsets.all(16.w),
                decoration: BoxDecoration(
                  color: AppColors.gold.withOpacity(0.12),
                  shape: BoxShape.circle,
                  border: Border.all(color: AppColors.gold.withOpacity(0.25)),
                ),
                child: Icon(
                  Icons.settings_rounded,
                  size: 36,
                  color: AppColors.gold,
                ),
              ),
              SizedBox(height: 20),
              Text(
                'Настройки теста',
                style: TextStyle(
                  fontSize: 20.sp,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),

              // ── Секция 1: Время ──
              SizedBox(height: 24),
              _buildSectionLabel('Время тестирования', Icons.timer_rounded),
              SizedBox(height: 12),
              _buildNumberInput(
                controller: _minutesController,
                value: _selectedMinutes,
                min: 1,
                max: 120,
                onChanged: (v) => setState(() => _selectedMinutes = v),
              ),
              SizedBox(height: 6),
              Text(
                'минут',
                style: TextStyle(
                  fontSize: 13.sp,
                  color: Colors.white.withOpacity(0.4),
                ),
              ),
              SizedBox(height: 8),
              _buildQuickOptions(
                values: [5, 7, 10, 15],
                selected: _selectedMinutes,
                controller: _minutesController,
                onSelect: (v) => setState(() => _selectedMinutes = v),
              ),

              // ── Секция 2: Минимальный балл ──
              SizedBox(height: 24),
              _buildSectionLabel('Проходной балл', Icons.star_rounded),
              SizedBox(height: 12),
              _buildNumberInput(
                controller: _minScoreController,
                value: _selectedMinScore,
                min: 0,
                max: 20,
                onChanged: (v) => setState(() => _selectedMinScore = v),
              ),
              SizedBox(height: 6),
              Text(
                _selectedMinScore == 0
                    ? 'отключено'
                    : 'из 20 правильных ответов',
                style: TextStyle(
                  fontSize: 13.sp,
                  color: _selectedMinScore == 0
                      ? Colors.white.withOpacity(0.3)
                      : Colors.white.withOpacity(0.4),
                ),
              ),
              SizedBox(height: 8),
              _buildQuickOptions(
                values: [0, 10, 15, 18],
                selected: _selectedMinScore,
                controller: _minScoreController,
                onSelect: (v) => setState(() => _selectedMinScore = v),
                labels: {0: 'Выкл'},
              ),

              // ── Кнопки ──
              SizedBox(height: 26),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white.withOpacity(0.7),
                        side: BorderSide(color: Colors.white.withOpacity(0.15)),
                        padding: EdgeInsets.symmetric(vertical: 14.h),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14.r),
                        ),
                      ),
                      child: Text('Отмена'),
                    ),
                  ),
                  SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () {
                        if (_selectedMinutes >= 1 && _selectedMinutes <= 120) {
                          Navigator.pop(context, (
                            durationMinutes: _selectedMinutes,
                            minimumScore: _selectedMinScore,
                          ));
                        }
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
                        'Сохранить',
                        style: TextStyle(fontWeight: FontWeight.w600),
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

  Widget _buildSectionLabel(String text, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 18, color: AppColors.gold.withOpacity(0.7)),
        SizedBox(width: 8),
        Text(
          text,
          style: TextStyle(
            fontSize: 14.sp,
            fontWeight: FontWeight.w600,
            color: Colors.white.withOpacity(0.7),
          ),
        ),
      ],
    );
  }

  Widget _buildNumberInput({
    required TextEditingController controller,
    required int value,
    required int min,
    required int max,
    required ValueChanged<int> onChanged,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.06),
        borderRadius: BorderRadius.circular(16.r),
        border: Border.all(color: AppColors.gold.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: value > min
                ? () {
                    final newVal = value - 1;
                    onChanged(newVal);
                    controller.text = '$newVal';
                  }
                : null,
            icon: Icon(
              Icons.remove_circle_outline,
              color: value > min ? AppColors.gold : Colors.white.withOpacity(0.2),
            ),
          ),
          Expanded(
            child: TextField(
              controller: controller,
              textAlign: TextAlign.center,
              keyboardType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(3),
              ],
              style: TextStyle(
                color: _goldLight,
                fontSize: 32.sp,
                fontWeight: FontWeight.w800,
              ),
              decoration: InputDecoration(
                border: InputBorder.none,
                contentPadding: EdgeInsets.zero,
              ),
              onChanged: (text) {
                final parsed = int.tryParse(text);
                if (parsed != null && parsed >= min && parsed <= max) {
                  onChanged(parsed);
                }
              },
            ),
          ),
          IconButton(
            onPressed: value < max
                ? () {
                    final newVal = value + 1;
                    onChanged(newVal);
                    controller.text = '$newVal';
                  }
                : null,
            icon: Icon(
              Icons.add_circle_outline,
              color: value < max ? AppColors.gold : Colors.white.withOpacity(0.2),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickOptions({
    required List<int> values,
    required int selected,
    required TextEditingController controller,
    required ValueChanged<int> onSelect,
    Map<int, String>? labels,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: values.map((v) {
        final isActive = selected == v;
        final label = labels?[v] ?? '$v';
        return Padding(
          padding: EdgeInsets.symmetric(horizontal: 4.w),
          child: InkWell(
            onTap: () {
              onSelect(v);
              controller.text = '$v';
            },
            borderRadius: BorderRadius.circular(10.r),
            child: Container(
              padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 8.h),
              decoration: BoxDecoration(
                color: isActive
                    ? AppColors.gold.withOpacity(0.2)
                    : Colors.white.withOpacity(0.05),
                borderRadius: BorderRadius.circular(10.r),
                border: Border.all(
                  color: isActive
                      ? AppColors.gold.withOpacity(0.5)
                      : Colors.white.withOpacity(0.08),
                ),
              ),
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 14.sp,
                  fontWeight: FontWeight.w600,
                  color: isActive ? _goldLight : Colors.white.withOpacity(0.5),
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}

/// Современный диалог удаления
class _ModernDeleteDialog extends StatelessWidget {
  final TestQuestion question;

  _ModernDeleteDialog({required this.question});
  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppColors.emeraldDark,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24.r)),
      child: Padding(
        padding: EdgeInsets.all(24.w),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: EdgeInsets.all(16.w),
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.12),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.red.withOpacity(0.25)),
              ),
              child: Icon(
                Icons.delete_outline_rounded,
                color: Colors.red[300],
                size: 32,
              ),
            ),
            SizedBox(height: 20),
            Text(
              'Удалить вопрос?',
              style: TextStyle(
                fontSize: 18.sp,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            SizedBox(height: 12),
            Text(
              question.question,
              style: TextStyle(
                color: Colors.white.withOpacity(0.5),
                fontSize: 14.sp,
                height: 1.4,
              ),
              textAlign: TextAlign.center,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
            SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context, false),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white.withOpacity(0.7),
                      side: BorderSide(color: Colors.white.withOpacity(0.15)),
                      padding: EdgeInsets.symmetric(vertical: 14.h),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12.r),
                      ),
                    ),
                    child: Text('Отмена'),
                  ),
                ),
                SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(context, true),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red.withOpacity(0.2),
                      foregroundColor: Colors.red[300],
                      padding: EdgeInsets.symmetric(vertical: 14.h),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12.r),
                        side: BorderSide(color: Colors.red.withOpacity(0.3)),
                      ),
                      elevation: 0,
                    ),
                    child: Text('Удалить'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Современный Bottom Sheet для добавления/редактирования вопроса
class TestQuestionFormBottomSheet extends StatefulWidget {
  final TestQuestion? question;

  const TestQuestionFormBottomSheet({super.key, this.question});

  @override
  State<TestQuestionFormBottomSheet> createState() => _TestQuestionFormBottomSheetState();
}

class _TestQuestionFormBottomSheetState extends State<TestQuestionFormBottomSheet> {
  final _formKey = GlobalKey<FormState>();
  final _questionController = TextEditingController();
  final List<TextEditingController> _optionControllers = [
    TextEditingController(),
    TextEditingController(),
    TextEditingController(),
    TextEditingController(),
  ];
  int? _selectedCorrectAnswer;
  bool _isSaving = false;
  @override
  void initState() {
    super.initState();
    if (widget.question != null) {
      _questionController.text = widget.question!.question;
      for (int i = 0; i < widget.question!.options.length && i < 4; i++) {
        _optionControllers[i].text = widget.question!.options[i];
      }
      final correctAnswer = widget.question!.correctAnswer;
      final correctIndex = widget.question!.options.indexOf(correctAnswer);
      if (correctIndex >= 0 && correctIndex < 4) {
        _selectedCorrectAnswer = correctIndex;
      }
    }
  }

  @override
  void dispose() {
    _questionController.dispose();
    for (var controller in _optionControllers) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _saveQuestion() async {
    if (!_formKey.currentState!.validate()) return;

    if (_selectedCorrectAnswer == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Выберите правильный ответ'),
          backgroundColor: Colors.orange,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.r)),
          margin: EdgeInsets.all(16.w),
        ),
      );
      return;
    }

    if (mounted) setState(() => _isSaving = true);

    try {
      final options = _optionControllers
          .map((c) => c.text.trim())
          .where((t) => t.isNotEmpty)
          .toList();

      if (options.length < 2) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Заполните хотя бы 2 варианта ответа'),
            backgroundColor: Colors.orange,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.r)),
            margin: EdgeInsets.all(16.w),
          ),
        );
        if (mounted) setState(() => _isSaving = false);
        return;
      }

      if (_selectedCorrectAnswer! >= options.length) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Правильный ответ должен быть заполнен'),
            backgroundColor: Colors.orange,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.r)),
            margin: EdgeInsets.all(16.w),
          ),
        );
        if (mounted) setState(() => _isSaving = false);
        return;
      }

      final correctAnswer = options[_selectedCorrectAnswer!];

      TestQuestion? result;
      if (widget.question != null) {
        result = await TestQuestionService.updateQuestion(
          id: widget.question!.id,
          question: _questionController.text.trim(),
          options: options,
          correctAnswer: correctAnswer,
        );
      } else {
        result = await TestQuestionService.createQuestion(
          question: _questionController.text.trim(),
          options: options,
          correctAnswer: correctAnswer,
        );
      }

      if (result != null && mounted) {
        Navigator.pop(context, result);
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка сохранения вопроса'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.r)),
            margin: EdgeInsets.all(16.w),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка: $e'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.r)),
            margin: EdgeInsets.all(16.w),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.question != null;

    return Container(
      height: MediaQuery.of(context).size.height * 0.9,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [AppColors.emeraldDark, AppColors.night],
        ),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24.r)),
      ),
      child: Column(
        children: [
          // Ручка
          Container(
            margin: EdgeInsets.only(top: 12.h),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              borderRadius: BorderRadius.circular(2.r),
            ),
          ),
          // Заголовок
          Padding(
            padding: EdgeInsets.fromLTRB(20.w, 20.h, 20.w, 0.h),
            child: Row(
              children: [
                Container(
                  padding: EdgeInsets.all(12.w),
                  decoration: BoxDecoration(
                    color: AppColors.gold.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(14.r),
                    border: Border.all(color: AppColors.gold.withOpacity(0.25)),
                  ),
                  child: Icon(
                    isEditing ? Icons.edit_note_rounded : Icons.add_circle_outline,
                    color: AppColors.gold,
                    size: 24,
                  ),
                ),
                SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        isEditing ? 'Редактировать вопрос' : 'Новый вопрос',
                        style: TextStyle(
                          fontSize: 20.sp,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      Text(
                        isEditing ? 'Измените данные и сохраните' : 'Заполните все поля',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.4),
                          fontSize: 13.sp,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: Icon(Icons.close, color: Colors.white.withOpacity(0.4)),
                ),
              ],
            ),
          ),
          // Форма
          Expanded(
            child: SingleChildScrollView(
              padding: EdgeInsets.all(20.w),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildSectionTitle('Текст вопроса', Icons.quiz_outlined),
                    SizedBox(height: 12),
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.06),
                        borderRadius: BorderRadius.circular(16.r),
                        border: Border.all(color: AppColors.gold.withOpacity(0.15)),
                      ),
                      child: TextFormField(
                        controller: _questionController,
                        decoration: InputDecoration(
                          hintText: 'Введите текст вопроса...',
                          hintStyle: TextStyle(color: Colors.white.withOpacity(0.25)),
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.all(16.w),
                        ),
                        maxLines: 3,
                        style: TextStyle(
                          fontSize: 15.sp,
                          height: 1.4,
                          color: Colors.white.withOpacity(0.9),
                        ),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Введите текст вопроса';
                          }
                          return null;
                        },
                      ),
                    ),
                    SizedBox(height: 24),
                    _buildSectionTitle('Варианты ответов', Icons.list_alt_rounded),
                    SizedBox(height: 8),
                    Text(
                      'Нажмите на кружок, чтобы выбрать правильный ответ',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.35),
                        fontSize: 12.sp,
                      ),
                    ),
                    SizedBox(height: 12),
                    _buildOptionField(0, 'A'),
                    _buildOptionField(1, 'B'),
                    _buildOptionField(2, 'C'),
                    _buildOptionField(3, 'D'),
                    SizedBox(height: 16),
                  ],
                ),
              ),
            ),
          ),
          // Кнопки
          Container(
            padding: EdgeInsets.fromLTRB(20.w, 12.h, 20.w, 12.h + MediaQuery.of(context).padding.bottom),
            decoration: BoxDecoration(
              color: AppColors.night,
              border: Border(
                top: BorderSide(color: Colors.white.withOpacity(0.06)),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _isSaving ? null : () => Navigator.pop(context),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white.withOpacity(0.7),
                      side: BorderSide(color: Colors.white.withOpacity(0.15)),
                      padding: EdgeInsets.symmetric(vertical: 16.h),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14.r),
                      ),
                    ),
                    child: Text('Отмена'),
                  ),
                ),
                SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: ElevatedButton(
                    onPressed: _isSaving ? null : _saveQuestion,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.gold.withOpacity(0.2),
                      foregroundColor: AppColors.gold,
                      disabledBackgroundColor: Colors.white.withOpacity(0.05),
                      disabledForegroundColor: Colors.white.withOpacity(0.3),
                      padding: EdgeInsets.symmetric(vertical: 16.h),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14.r),
                        side: BorderSide(color: AppColors.gold.withOpacity(0.4)),
                      ),
                      elevation: 0,
                    ),
                    child: _isSaving
                        ? SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(AppColors.gold),
                            ),
                          )
                        : Text(
                            isEditing ? 'Сохранить изменения' : 'Добавить вопрос',
                            style: TextStyle(fontWeight: FontWeight.w600),
                          ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 18, color: AppColors.gold),
        SizedBox(width: 8),
        Text(
          title,
          style: TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 15.sp,
            color: AppColors.gold,
          ),
        ),
      ],
    );
  }

  Widget _buildOptionField(int index, String letter) {
    final isSelected = _selectedCorrectAnswer == index;
    final hasText = _optionControllers[index].text.trim().isNotEmpty;

    return Padding(
      padding: EdgeInsets.only(bottom: 10.h),
      child: Container(
        decoration: BoxDecoration(
          color: isSelected
              ? AppColors.success.withOpacity(0.08)
              : Colors.white.withOpacity(0.04),
          borderRadius: BorderRadius.circular(14.r),
          border: Border.all(
            color: isSelected
                ? AppColors.success.withOpacity(0.4)
                : Colors.white.withOpacity(0.08),
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            // Буква
            Container(
              width: 48,
              height: 56,
              decoration: BoxDecoration(
                color: isSelected
                    ? AppColors.success.withOpacity(0.2)
                    : Colors.white.withOpacity(0.05),
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(12.r),
                  bottomLeft: Radius.circular(12.r),
                ),
              ),
              child: Center(
                child: Text(
                  letter,
                  style: TextStyle(
                    color: isSelected
                        ? AppColors.successLight
                        : Colors.white.withOpacity(0.4),
                    fontWeight: FontWeight.bold,
                    fontSize: 18.sp,
                  ),
                ),
              ),
            ),
            // Поле ввода
            Expanded(
              child: TextFormField(
                controller: _optionControllers[index],
                decoration: InputDecoration(
                  hintText: index < 2 ? 'Вариант (обязательно)' : 'Вариант (опционально)',
                  hintStyle: TextStyle(color: Colors.white.withOpacity(0.2), fontSize: 14.sp),
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.symmetric(horizontal: 14.w),
                ),
                style: TextStyle(
                  fontSize: 14.sp,
                  color: isSelected
                      ? AppColors.successLight
                      : Colors.white.withOpacity(0.8),
                  fontWeight: isSelected ? FontWeight.w500 : FontWeight.normal,
                ),
                onChanged: (_) => setState(() {}),
                validator: (value) {
                  if (index < 2 && (value == null || value.trim().isEmpty)) {
                    return '';
                  }
                  return null;
                },
              ),
            ),
            // Кнопка выбора
            Padding(
              padding: EdgeInsets.only(right: 8.w),
              child: InkWell(
                onTap: () {
                  if (_optionControllers[index].text.trim().isNotEmpty) {
                    if (mounted) setState(() => _selectedCorrectAnswer = index);
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Сначала заполните вариант $letter'),
                        backgroundColor: Colors.orange,
                        behavior: SnackBarBehavior.floating,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.r)),
                        margin: EdgeInsets.all(16.w),
                      ),
                    );
                  }
                },
                borderRadius: BorderRadius.circular(20.r),
                child: Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: isSelected
                        ? AppColors.success.withOpacity(0.2)
                        : hasText
                            ? Colors.white.withOpacity(0.08)
                            : Colors.white.withOpacity(0.04),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: isSelected
                          ? AppColors.success.withOpacity(0.5)
                          : Colors.white.withOpacity(0.1),
                    ),
                  ),
                  child: Icon(
                    isSelected ? Icons.check_rounded : Icons.circle_outlined,
                    color: isSelected
                        ? AppColors.success
                        : Colors.white.withOpacity(0.3),
                    size: 18,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
