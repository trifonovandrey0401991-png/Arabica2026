import 'package:flutter/material.dart';
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

  static const _primaryColor = Color(0xFF004D40);
  static const _gradientStart = Color(0xFF00695C);
  static const _gradientEnd = Color(0xFF004D40);

  @override
  void initState() {
    super.initState();
    _loadQuestions();
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
          const SnackBar(
            content: Text('Вопрос успешно добавлен'),
            backgroundColor: Colors.green,
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
          const SnackBar(
            content: Text('Вопрос успешно обновлен'),
            backgroundColor: Colors.green,
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
            const SnackBar(
              content: Text('Вопрос успешно удален'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Ошибка удаления вопроса'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [_gradientStart, _gradientEnd],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              // Кастомный AppBar
              _buildCustomAppBar(),
              // Контент
              Expanded(
                child: Container(
                  decoration: const BoxDecoration(
                    color: Color(0xFFF5F5F5),
                    borderRadius: BorderRadius.only(
                      topLeft: Radius.circular(24),
                      topRight: Radius.circular(24),
                    ),
                  ),
                  child: ClipRRect(
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(24),
                      topRight: Radius.circular(24),
                    ),
                    child: _buildContent(),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showAddQuestionDialog,
        backgroundColor: _primaryColor,
        icon: const Icon(Icons.add_rounded, color: Colors.white),
        label: const Text(
          'Добавить',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }

  Widget _buildCustomAppBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 16),
      child: Row(
        children: [
          // Кнопка назад
          Container(
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: IconButton(
              icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 20),
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
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  '${_questions.length} вопросов',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.8),
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
          // Кнопка обновления
          Container(
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: IconButton(
              icon: const Icon(Icons.refresh, color: Colors.white, size: 20),
              onPressed: _loadQuestions,
              tooltip: 'Обновить',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContent() {
    if (_isLoading) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: _primaryColor.withOpacity(0.1),
                    blurRadius: 20,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: const CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(_primaryColor),
                strokeWidth: 3,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Загрузка вопросов...',
              style: TextStyle(
                color: Colors.grey[600],
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
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 10,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Поиск по вопросам...',
                hintStyle: TextStyle(color: Colors.grey[400]),
                prefixIcon: Icon(Icons.search, color: Colors.grey[400]),
                suffixIcon: _searchQuery.isNotEmpty
                    ? Container(
                        margin: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.grey[200],
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(8),
                          onTap: () {
                            _searchController.clear();
                            setState(() {
                              _searchQuery = '';
                              _applyFilter();
                            });
                          },
                          child: const Icon(Icons.close, size: 18, color: Colors.grey),
                        ),
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
        // Статистика
        if (_searchQuery.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: _primaryColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    'Найдено: ${_filteredQuestions.length} из ${_questions.length}',
                    style: const TextStyle(
                      color: _primaryColor,
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
                  color: _primaryColor,
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
              color: Colors.white,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Colors.grey.withOpacity(0.1),
                  blurRadius: 20,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Icon(
              _searchQuery.isNotEmpty ? Icons.search_off_rounded : Icons.quiz_outlined,
              size: 48,
              color: Colors.grey[400],
            ),
          ),
          const SizedBox(height: 20),
          Text(
            _searchQuery.isNotEmpty ? 'Вопросы не найдены' : 'Нет вопросов',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: Colors.grey[700],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _searchQuery.isNotEmpty
                ? 'Попробуйте изменить запрос'
                : 'Нажмите "Добавить" чтобы создать первый вопрос',
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[500],
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildQuestionCard(TestQuestion question, int index) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: _primaryColor.withOpacity(0.06),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: () => _showEditQuestionDialog(question),
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Заголовок с номером и действиями
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Номер вопроса
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [_gradientStart, _gradientEnd],
                        ),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Center(
                        child: Text(
                          '${index + 1}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    // Текст вопроса
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            question.question,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: Colors.black87,
                              height: 1.4,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Icon(Icons.list_alt_rounded, size: 14, color: Colors.grey[400]),
                              const SizedBox(width: 4),
                              Text(
                                '${question.options.length} вариантов ответа',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey[500],
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
                          color: _primaryColor,
                          onPressed: () => _showEditQuestionDialog(question),
                        ),
                        const SizedBox(width: 4),
                        _buildActionIconButton(
                          icon: Icons.delete_outline_rounded,
                          color: Colors.red,
                          onPressed: () => _deleteQuestion(question),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                // Варианты ответов
                ...question.options.asMap().entries.map((entry) {
                  final isCorrect = entry.value == question.correctAnswer;
                  return Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        color: isCorrect
                            ? Colors.green.withOpacity(0.1)
                            : Colors.grey[50],
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: isCorrect
                              ? Colors.green.withOpacity(0.3)
                              : Colors.grey.withOpacity(0.15),
                        ),
                      ),
                      child: Row(
                        children: [
                          // Буква варианта
                          Container(
                            width: 24,
                            height: 24,
                            decoration: BoxDecoration(
                              color: isCorrect
                                  ? Colors.green
                                  : Colors.grey[300],
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Center(
                              child: Text(
                                String.fromCharCode(65 + entry.key), // A, B, C, D
                                style: TextStyle(
                                  color: isCorrect ? Colors.white : Colors.grey[600],
                                  fontWeight: FontWeight.w600,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          // Текст варианта
                          Expanded(
                            child: Text(
                              entry.value,
                              style: TextStyle(
                                fontSize: 13,
                                color: isCorrect ? Colors.green[700] : Colors.black87,
                                fontWeight: isCorrect ? FontWeight.w500 : FontWeight.normal,
                              ),
                            ),
                          ),
                          // Иконка правильного ответа
                          if (isCorrect)
                            Icon(
                              Icons.check_circle_rounded,
                              color: Colors.green,
                              size: 18,
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
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: color.withOpacity(0.08),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, color: color, size: 18),
      ),
    );
  }
}

/// Современный диалог удаления
class _ModernDeleteDialog extends StatelessWidget {
  final TestQuestion question;

  const _ModernDeleteDialog({required this.question});

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.delete_outline_rounded,
                color: Colors.red,
                size: 32,
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'Удалить вопрос?',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              question.question,
              style: TextStyle(
                color: Colors.grey[600],
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
                      backgroundColor: Colors.red,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
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

  static const _primaryColor = Color(0xFF004D40);

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
        const SnackBar(
          content: Text('Выберите правильный ответ'),
          backgroundColor: Colors.orange,
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
          const SnackBar(
            content: Text('Заполните хотя бы 2 варианта ответа'),
            backgroundColor: Colors.orange,
          ),
        );
        setState(() => _isSaving = false);
        return;
      }

      if (_selectedCorrectAnswer! >= options.length) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Правильный ответ должен быть заполнен'),
            backgroundColor: Colors.orange,
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
          const SnackBar(
            content: Text('Ошибка сохранения вопроса'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка: $e'), backgroundColor: Colors.red),
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
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          // Ручка
          Container(
            margin: const EdgeInsets.only(top: 12),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey[300],
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
                    color: _primaryColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(
                    isEditing ? Icons.edit_note_rounded : Icons.add_circle_outline,
                    color: _primaryColor,
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
                        ),
                      ),
                      Text(
                        isEditing ? 'Измените данные и сохраните' : 'Заполните все поля',
                        style: TextStyle(
                          color: Colors.grey[500],
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: Icon(Icons.close, color: Colors.grey[400]),
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
                    // Секция: Текст вопроса
                    _buildSectionTitle('Текст вопроса', Icons.quiz_outlined),
                    const SizedBox(height: 12),
                    Container(
                      decoration: BoxDecoration(
                        color: _primaryColor.withOpacity(0.05),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: _primaryColor.withOpacity(0.1)),
                      ),
                      child: TextFormField(
                        controller: _questionController,
                        decoration: InputDecoration(
                          hintText: 'Введите текст вопроса...',
                          hintStyle: TextStyle(color: Colors.grey[400]),
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.all(16),
                        ),
                        maxLines: 3,
                        style: const TextStyle(fontSize: 15, height: 1.4),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Введите текст вопроса';
                          }
                          return null;
                        },
                      ),
                    ),
                    const SizedBox(height: 24),
                    // Секция: Варианты ответов
                    _buildSectionTitle('Варианты ответов', Icons.list_alt_rounded),
                    const SizedBox(height: 8),
                    Text(
                      'Нажмите на кружок справа, чтобы выбрать правильный ответ',
                      style: TextStyle(
                        color: Colors.grey[500],
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 12),
                    // Варианты ответов
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
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 10,
                  offset: const Offset(0, -2),
                ),
              ],
            ),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _isSaving ? null : () => Navigator.pop(context),
                    style: OutlinedButton.styleFrom(
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
                      backgroundColor: _primaryColor,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      elevation: 0,
                    ),
                    child: _isSaving
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
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
        Icon(icon, size: 18, color: _primaryColor),
        const SizedBox(width: 8),
        Text(
          title,
          style: const TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 15,
            color: _primaryColor,
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
              ? Colors.green.withOpacity(0.08)
              : Colors.grey[50],
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSelected
                ? Colors.green.withOpacity(0.4)
                : Colors.grey.withOpacity(0.2),
            width: isSelected ? 2 : 1,
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
                    ? Colors.green
                    : Colors.grey[200],
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(12),
                  bottomLeft: Radius.circular(12),
                ),
              ),
              child: Center(
                child: Text(
                  letter,
                  style: TextStyle(
                    color: isSelected ? Colors.white : Colors.grey[600],
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
                  hintText: index < 2 ? 'Вариант ответа (обязательно)' : 'Вариант ответа (опционально)',
                  hintStyle: TextStyle(color: Colors.grey[400], fontSize: 14),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14),
                ),
                style: TextStyle(
                  fontSize: 14,
                  color: isSelected ? Colors.green[700] : Colors.black87,
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
                        ? Colors.green
                        : hasText
                            ? Colors.grey[300]
                            : Colors.grey[200],
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    isSelected ? Icons.check_rounded : Icons.circle_outlined,
                    color: isSelected ? Colors.white : Colors.grey[500],
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
