import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/test_model.dart';
import '../services/test_question_service.dart';

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

  // Единая палитра приложения (как в test_page)
  static const _emerald = Color(0xFF1A4D4D);
  static const _emeraldDark = Color(0xFF0D2E2E);
  static const _night = Color(0xFF051515);
  static const _gold = Color(0xFFD4AF37);

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
    setState(() => _isLoading = true);

    try {
      final questions = await TestQuestionService.getQuestions();
      setState(() {
        _questions = questions;
        _applyFilter();
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
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
    final minutes = await TestQuestionService.getTestDurationMinutes();
    if (mounted) {
      setState(() => _testDurationMinutes = minutes);
    }
  }

  Future<void> _showSettingsDialog() async {
    final controller = TextEditingController(text: '$_testDurationMinutes');

    final result = await showDialog<int>(
      context: context,
      builder: (ctx) => _TestSettingsDialog(
        controller: controller,
        currentMinutes: _testDurationMinutes,
      ),
    );

    controller.dispose();

    if (result != null && result != _testDurationMinutes) {
      final success = await TestQuestionService.saveTestDurationMinutes(result);
      if (success) {
        setState(() => _testDurationMinutes = result);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Время теста: $result мин.'),
              backgroundColor: const Color(0xFF2E7D32),
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              margin: const EdgeInsets.all(16),
            ),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Ошибка сохранения настроек'),
              backgroundColor: Colors.red,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              margin: const EdgeInsets.all(16),
            ),
          );
        }
      }
    }
  }

  Future<void> _showAddQuestionDialog() async {
    final result = await showModalBottomSheet<TestQuestion>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => const TestQuestionFormBottomSheet(),
    );

    if (result != null) {
      await _loadQuestions();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Вопрос успешно добавлен'),
            backgroundColor: const Color(0xFF2E7D32),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            margin: const EdgeInsets.all(16),
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
            content: const Text('Вопрос успешно обновлен'),
            backgroundColor: const Color(0xFF2E7D32),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            margin: const EdgeInsets.all(16),
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
              content: const Text('Вопрос удален'),
              backgroundColor: const Color(0xFF2E7D32),
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              margin: const EdgeInsets.all(16),
            ),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Ошибка удаления вопроса'),
              backgroundColor: Colors.red,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              margin: const EdgeInsets.all(16),
            ),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
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
              _buildCustomAppBar(),
              _buildStatsBar(),
              Expanded(child: _buildContent()),
            ],
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showAddQuestionDialog,
        backgroundColor: _gold.withOpacity(0.2),
        icon: Icon(Icons.add_rounded, color: _gold),
        label: Text(
          'Добавить',
          style: TextStyle(color: _gold, fontWeight: FontWeight.w600),
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: _gold.withOpacity(0.4)),
        ),
        elevation: 0,
      ),
    );
  }

  Widget _buildCustomAppBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
      child: Row(
        children: [
          // Кнопка назад
          Container(
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white.withOpacity(0.1)),
            ),
            child: IconButton(
              icon: Icon(Icons.arrow_back_ios_new, color: Colors.white.withOpacity(0.8), size: 20),
              onPressed: () => Navigator.pop(context),
            ),
          ),
          const SizedBox(width: 12),
          // Заголовок
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Вопросы тестирования',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w400,
                    letterSpacing: 0.5,
                  ),
                ),
                Text(
                  '${_questions.length} вопросов',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.5),
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
          // Кнопка настроек
          Container(
            decoration: BoxDecoration(
              color: _gold.withOpacity(0.12),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _gold.withOpacity(0.25)),
            ),
            child: IconButton(
              icon: Icon(Icons.settings_rounded, color: _gold, size: 20),
              onPressed: _showSettingsDialog,
              tooltip: 'Настройки теста',
            ),
          ),
          const SizedBox(width: 8),
          // Кнопка обновления
          Container(
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.08),
              borderRadius: BorderRadius.circular(12),
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
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Row(
        children: [
          _buildStatChip(
            Icons.quiz_rounded,
            '${_questions.length}',
            'вопросов',
          ),
          const SizedBox(width: 10),
          _buildStatChip(
            Icons.timer_outlined,
            '$_testDurationMinutes',
            'минут',
          ),
          const SizedBox(width: 10),
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
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.06),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white.withOpacity(0.08)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: _gold.withOpacity(0.7), size: 16),
            const SizedBox(width: 6),
            Text(
              value,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                label,
                style: TextStyle(
                  color: Colors.white.withOpacity(0.4),
                  fontSize: 11,
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
              valueColor: AlwaysStoppedAnimation<Color>(_gold),
              strokeWidth: 3,
            ),
            const SizedBox(height: 16),
            Text(
              'Загрузка вопросов...',
              style: TextStyle(
                color: Colors.white.withOpacity(0.5),
                fontSize: 14,
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
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.06),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.white.withOpacity(0.1)),
            ),
            child: TextField(
              controller: _searchController,
              style: const TextStyle(color: Colors.white, fontSize: 14),
              decoration: InputDecoration(
                hintText: 'Поиск по вопросам...',
                hintStyle: TextStyle(color: Colors.white.withOpacity(0.3)),
                prefixIcon: Icon(Icons.search, color: Colors.white.withOpacity(0.3)),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: Icon(Icons.close, size: 18, color: Colors.white.withOpacity(0.4)),
                        onPressed: () {
                          _searchController.clear();
                          setState(() {
                            _searchQuery = '';
                            _applyFilter();
                          });
                        },
                      )
                    : null,
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              ),
              onChanged: (value) {
                setState(() {
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
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                  decoration: BoxDecoration(
                    color: _gold.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    'Найдено: ${_filteredQuestions.length} из ${_questions.length}',
                    style: TextStyle(
                      color: _gold,
                      fontSize: 12,
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
                  color: _gold,
                  backgroundColor: _emeraldDark,
                  child: ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
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
            padding: const EdgeInsets.all(24),
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
          const SizedBox(height: 20),
          Text(
            _searchQuery.isNotEmpty ? 'Вопросы не найдены' : 'Нет вопросов',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: Colors.white.withOpacity(0.7),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _searchQuery.isNotEmpty
                ? 'Попробуйте изменить запрос'
                : 'Нажмите "Добавить" чтобы создать первый вопрос',
            style: TextStyle(
              fontSize: 14,
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
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.06),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: () => _showEditQuestionDialog(question),
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(14),
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
                        color: _gold.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Center(
                        child: Text(
                          '${index + 1}',
                          style: TextStyle(
                            color: _gold,
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    // Текст вопроса
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            question.question,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              color: Colors.white.withOpacity(0.9),
                              height: 1.4,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Icon(Icons.list_alt_rounded, size: 12, color: Colors.white.withOpacity(0.3)),
                              const SizedBox(width: 4),
                              Text(
                                '${question.options.length} вариантов ответа',
                                style: TextStyle(
                                  fontSize: 11,
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
                          color: _gold,
                          onPressed: () => _showEditQuestionDialog(question),
                        ),
                        const SizedBox(width: 4),
                        _buildActionIconButton(
                          icon: Icons.delete_outline_rounded,
                          color: Colors.red[300]!,
                          onPressed: () => _deleteQuestion(question),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                // Варианты ответов
                ...question.options.asMap().entries.map((entry) {
                  final isCorrect = entry.value == question.correctAnswer;
                  return Padding(
                    padding: const EdgeInsets.only(top: 5),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      decoration: BoxDecoration(
                        color: isCorrect
                            ? const Color(0xFF4CAF50).withOpacity(0.1)
                            : Colors.white.withOpacity(0.03),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: isCorrect
                              ? const Color(0xFF4CAF50).withOpacity(0.3)
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
                                  ? const Color(0xFF4CAF50).withOpacity(0.2)
                                  : Colors.white.withOpacity(0.06),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Center(
                              child: Text(
                                String.fromCharCode(65 + entry.key),
                                style: TextStyle(
                                  color: isCorrect
                                      ? const Color(0xFF81C784)
                                      : Colors.white.withOpacity(0.4),
                                  fontWeight: FontWeight.w600,
                                  fontSize: 11,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          // Текст варианта
                          Expanded(
                            child: Text(
                              entry.value,
                              style: TextStyle(
                                fontSize: 12,
                                color: isCorrect
                                    ? const Color(0xFF81C784)
                                    : Colors.white.withOpacity(0.6),
                                fontWeight: isCorrect ? FontWeight.w500 : FontWeight.normal,
                              ),
                            ),
                          ),
                          if (isCorrect)
                            const Icon(
                              Icons.check_circle_rounded,
                              color: Color(0xFF4CAF50),
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
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.all(7),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, color: color, size: 16),
      ),
    );
  }
}

/// Диалог настроек теста (время в минутах)
class _TestSettingsDialog extends StatefulWidget {
  final TextEditingController controller;
  final int currentMinutes;

  const _TestSettingsDialog({
    required this.controller,
    required this.currentMinutes,
  });

  @override
  State<_TestSettingsDialog> createState() => _TestSettingsDialogState();
}

class _TestSettingsDialogState extends State<_TestSettingsDialog> {
  static const _emeraldDark = Color(0xFF0D2E2E);
  static const _gold = Color(0xFFD4AF37);
  static const _goldLight = Color(0xFFE8C860);

  late int _selectedMinutes;
  final _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _selectedMinutes = widget.currentMinutes;
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: _emeraldDark,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Иконка
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: _gold.withOpacity(0.12),
                shape: BoxShape.circle,
                border: Border.all(color: _gold.withOpacity(0.25)),
              ),
              child: Icon(
                Icons.timer_rounded,
                size: 36,
                color: _gold,
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'Время тестирования',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Укажите сколько минут отводится\nна прохождение теста',
              style: TextStyle(
                fontSize: 13,
                color: Colors.white.withOpacity(0.5),
                height: 1.4,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            // Поле ввода минут
            Container(
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.06),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: _gold.withOpacity(0.3)),
              ),
              child: Row(
                children: [
                  // Кнопка минус
                  IconButton(
                    onPressed: _selectedMinutes > 1
                        ? () {
                            setState(() {
                              _selectedMinutes--;
                              widget.controller.text = '$_selectedMinutes';
                            });
                          }
                        : null,
                    icon: Icon(
                      Icons.remove_circle_outline,
                      color: _selectedMinutes > 1
                          ? _gold
                          : Colors.white.withOpacity(0.2),
                    ),
                  ),
                  // Поле ввода
                  Expanded(
                    child: TextField(
                      controller: widget.controller,
                      focusNode: _focusNode,
                      textAlign: TextAlign.center,
                      keyboardType: TextInputType.number,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(3),
                      ],
                      style: TextStyle(
                        color: _goldLight,
                        fontSize: 32,
                        fontWeight: FontWeight.w800,
                      ),
                      decoration: const InputDecoration(
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.zero,
                      ),
                      onChanged: (value) {
                        final parsed = int.tryParse(value);
                        if (parsed != null && parsed >= 1 && parsed <= 120) {
                          setState(() => _selectedMinutes = parsed);
                        }
                      },
                    ),
                  ),
                  // Кнопка плюс
                  IconButton(
                    onPressed: _selectedMinutes < 120
                        ? () {
                            setState(() {
                              _selectedMinutes++;
                              widget.controller.text = '$_selectedMinutes';
                            });
                          }
                        : null,
                    icon: Icon(
                      Icons.add_circle_outline,
                      color: _selectedMinutes < 120
                          ? _gold
                          : Colors.white.withOpacity(0.2),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'минут',
              style: TextStyle(
                fontSize: 14,
                color: Colors.white.withOpacity(0.4),
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 8),
            // Быстрые варианты
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [5, 7, 10, 15].map((m) {
                final isSelected = _selectedMinutes == m;
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: InkWell(
                    onTap: () {
                      setState(() {
                        _selectedMinutes = m;
                        widget.controller.text = '$m';
                      });
                    },
                    borderRadius: BorderRadius.circular(10),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? _gold.withOpacity(0.2)
                            : Colors.white.withOpacity(0.05),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: isSelected
                              ? _gold.withOpacity(0.5)
                              : Colors.white.withOpacity(0.08),
                        ),
                      ),
                      child: Text(
                        '$m',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: isSelected
                              ? _goldLight
                              : Colors.white.withOpacity(0.5),
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 26),
            // Кнопки
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white.withOpacity(0.7),
                      side: BorderSide(color: Colors.white.withOpacity(0.15)),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: const Text('Отмена'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () {
                      final value = int.tryParse(widget.controller.text);
                      if (value != null && value >= 1 && value <= 120) {
                        Navigator.pop(context, value);
                      }
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
    );
  }
}

/// Современный диалог удаления
class _ModernDeleteDialog extends StatelessWidget {
  final TestQuestion question;

  const _ModernDeleteDialog({required this.question});

  static const _emeraldDark = Color(0xFF0D2E2E);

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: _emeraldDark,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
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
            const SizedBox(height: 20),
            const Text(
              'Удалить вопрос?',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              question.question,
              style: TextStyle(
                color: Colors.white.withOpacity(0.5),
                fontSize: 14,
                height: 1.4,
              ),
              textAlign: TextAlign.center,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context, false),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white.withOpacity(0.7),
                      side: BorderSide(color: Colors.white.withOpacity(0.15)),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text('Отмена'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(context, true),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red.withOpacity(0.2),
                      foregroundColor: Colors.red[300],
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(color: Colors.red.withOpacity(0.3)),
                      ),
                      elevation: 0,
                    ),
                    child: const Text('Удалить'),
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

  static const _emeraldDark = Color(0xFF0D2E2E);
  static const _night = Color(0xFF051515);
  static const _gold = Color(0xFFD4AF37);

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
          content: const Text('Выберите правильный ответ'),
          backgroundColor: Colors.orange,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          margin: const EdgeInsets.all(16),
        ),
      );
      return;
    }

    setState(() => _isSaving = true);

    try {
      final options = _optionControllers
          .map((c) => c.text.trim())
          .where((t) => t.isNotEmpty)
          .toList();

      if (options.length < 2) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Заполните хотя бы 2 варианта ответа'),
            backgroundColor: Colors.orange,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            margin: const EdgeInsets.all(16),
          ),
        );
        setState(() => _isSaving = false);
        return;
      }

      if (_selectedCorrectAnswer! >= options.length) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Правильный ответ должен быть заполнен'),
            backgroundColor: Colors.orange,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            margin: const EdgeInsets.all(16),
          ),
        );
        setState(() => _isSaving = false);
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
            content: const Text('Ошибка сохранения вопроса'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            margin: const EdgeInsets.all(16),
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
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            margin: const EdgeInsets.all(16),
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
          colors: [_emeraldDark, _night],
        ),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          // Ручка
          Container(
            margin: const EdgeInsets.only(top: 12),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          // Заголовок
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: _gold.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: _gold.withOpacity(0.25)),
                  ),
                  child: Icon(
                    isEditing ? Icons.edit_note_rounded : Icons.add_circle_outline,
                    color: _gold,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        isEditing ? 'Редактировать вопрос' : 'Новый вопрос',
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      Text(
                        isEditing ? 'Измените данные и сохраните' : 'Заполните все поля',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.4),
                          fontSize: 13,
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
              padding: const EdgeInsets.all(20),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildSectionTitle('Текст вопроса', Icons.quiz_outlined),
                    const SizedBox(height: 12),
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.06),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: _gold.withOpacity(0.15)),
                      ),
                      child: TextFormField(
                        controller: _questionController,
                        decoration: InputDecoration(
                          hintText: 'Введите текст вопроса...',
                          hintStyle: TextStyle(color: Colors.white.withOpacity(0.25)),
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.all(16),
                        ),
                        maxLines: 3,
                        style: TextStyle(
                          fontSize: 15,
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
                    const SizedBox(height: 24),
                    _buildSectionTitle('Варианты ответов', Icons.list_alt_rounded),
                    const SizedBox(height: 8),
                    Text(
                      'Нажмите на кружок, чтобы выбрать правильный ответ',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.35),
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 12),
                    _buildOptionField(0, 'A'),
                    _buildOptionField(1, 'B'),
                    _buildOptionField(2, 'C'),
                    _buildOptionField(3, 'D'),
                    const SizedBox(height: 16),
                  ],
                ),
              ),
            ),
          ),
          // Кнопки
          Container(
            padding: EdgeInsets.fromLTRB(20, 12, 20, 12 + MediaQuery.of(context).padding.bottom),
            decoration: BoxDecoration(
              color: _night,
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
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: const Text('Отмена'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: ElevatedButton(
                    onPressed: _isSaving ? null : _saveQuestion,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _gold.withOpacity(0.2),
                      foregroundColor: _gold,
                      disabledBackgroundColor: Colors.white.withOpacity(0.05),
                      disabledForegroundColor: Colors.white.withOpacity(0.3),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                        side: BorderSide(color: _gold.withOpacity(0.4)),
                      ),
                      elevation: 0,
                    ),
                    child: _isSaving
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFD4AF37)),
                            ),
                          )
                        : Text(
                            isEditing ? 'Сохранить изменения' : 'Добавить вопрос',
                            style: const TextStyle(fontWeight: FontWeight.w600),
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
        Icon(icon, size: 18, color: _gold),
        const SizedBox(width: 8),
        Text(
          title,
          style: TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 15,
            color: _gold,
          ),
        ),
      ],
    );
  }

  Widget _buildOptionField(int index, String letter) {
    final isSelected = _selectedCorrectAnswer == index;
    final hasText = _optionControllers[index].text.trim().isNotEmpty;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        decoration: BoxDecoration(
          color: isSelected
              ? const Color(0xFF4CAF50).withOpacity(0.08)
              : Colors.white.withOpacity(0.04),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSelected
                ? const Color(0xFF4CAF50).withOpacity(0.4)
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
                    ? const Color(0xFF4CAF50).withOpacity(0.2)
                    : Colors.white.withOpacity(0.05),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(12),
                  bottomLeft: Radius.circular(12),
                ),
              ),
              child: Center(
                child: Text(
                  letter,
                  style: TextStyle(
                    color: isSelected
                        ? const Color(0xFF81C784)
                        : Colors.white.withOpacity(0.4),
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
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
                  hintStyle: TextStyle(color: Colors.white.withOpacity(0.2), fontSize: 14),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14),
                ),
                style: TextStyle(
                  fontSize: 14,
                  color: isSelected
                      ? const Color(0xFF81C784)
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
              padding: const EdgeInsets.only(right: 8),
              child: InkWell(
                onTap: () {
                  if (_optionControllers[index].text.trim().isNotEmpty) {
                    setState(() => _selectedCorrectAnswer = index);
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Сначала заполните вариант $letter'),
                        backgroundColor: Colors.orange,
                        behavior: SnackBarBehavior.floating,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        margin: const EdgeInsets.all(16),
                      ),
                    );
                  }
                },
                borderRadius: BorderRadius.circular(20),
                child: Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: isSelected
                        ? const Color(0xFF4CAF50).withOpacity(0.2)
                        : hasText
                            ? Colors.white.withOpacity(0.08)
                            : Colors.white.withOpacity(0.04),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: isSelected
                          ? const Color(0xFF4CAF50).withOpacity(0.5)
                          : Colors.white.withOpacity(0.1),
                    ),
                  ),
                  child: Icon(
                    isSelected ? Icons.check_rounded : Icons.circle_outlined,
                    color: isSelected
                        ? const Color(0xFF4CAF50)
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
