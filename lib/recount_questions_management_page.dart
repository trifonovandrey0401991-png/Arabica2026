import 'package:flutter/material.dart';
import 'recount_question_model.dart';
import 'recount_question_service.dart';

/// Страница управления вопросами пересчета
class RecountQuestionsManagementPage extends StatefulWidget {
  const RecountQuestionsManagementPage({super.key});

  @override
  State<RecountQuestionsManagementPage> createState() => _RecountQuestionsManagementPageState();
}

class _RecountQuestionsManagementPageState extends State<RecountQuestionsManagementPage> {
  List<RecountQuestion> _questions = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadQuestions();
  }

  Future<void> _loadQuestions() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final questions = await RecountQuestionService.getQuestions();
      setState(() {
        _questions = questions;
        _isLoading = false;
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
      }
    }
  }

  Future<void> _showAddQuestionDialog() async {
    final result = await showDialog<RecountQuestion>(
      context: context,
      builder: (context) => const RecountQuestionFormDialog(),
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

  Future<void> _showEditQuestionDialog(RecountQuestion question) async {
    final result = await showDialog<RecountQuestion>(
      context: context,
      builder: (context) => RecountQuestionFormDialog(question: question),
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

  Future<void> _deleteQuestion(RecountQuestion question) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Удалить вопрос?'),
        content: Text('Вы уверены, что хотите удалить вопрос:\n"${question.question}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Отмена'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Удалить'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final success = await RecountQuestionService.deleteQuestion(question.id);
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

  Color _getGradeColor(int grade) {
    switch (grade) {
      case 1:
        return Colors.red; // Очень важный
      case 2:
        return Colors.orange; // Средней важности
      case 3:
        return Colors.green; // Не очень важный
      default:
        return Colors.grey;
    }
  }

  String _getGradeLabel(int grade) {
    switch (grade) {
      case 1:
        return 'Очень важный';
      case 2:
        return 'Средней важности';
      case 3:
        return 'Не очень важный';
      default:
        return 'Неизвестно';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Вопросы пересчета'),
        backgroundColor: const Color(0xFF004D40),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadQuestions,
            tooltip: 'Обновить',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _questions.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.help_outline, size: 64, color: Colors.grey),
                      const SizedBox(height: 16),
                      const Text(
                        'Нет вопросов',
                        style: TextStyle(fontSize: 18, color: Colors.grey),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Нажмите + чтобы добавить первый вопрос',
                        style: TextStyle(fontSize: 14, color: Colors.grey),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _questions.length,
                  itemBuilder: (context, index) {
                    final question = _questions[index];
                    return Card(
                      elevation: 2,
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        leading: Icon(
                          Icons.help_outline,
                          color: _getGradeColor(question.grade),
                        ),
                        title: Text(question.question),
                        subtitle: Text(
                          'Грейд ${question.grade}: ${_getGradeLabel(question.grade)}',
                          style: TextStyle(
                            color: _getGradeColor(question.grade),
                            fontSize: 12,
                          ),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.edit, color: Color(0xFF004D40)),
                              onPressed: () => _showEditQuestionDialog(question),
                              tooltip: 'Редактировать',
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete, color: Colors.red),
                              onPressed: () => _deleteQuestion(question),
                              tooltip: 'Удалить',
                            ),
                          ],
                        ),
                        onTap: () => _showEditQuestionDialog(question),
                      ),
                    );
                  },
                ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showAddQuestionDialog,
        backgroundColor: const Color(0xFF004D40),
        child: const Icon(Icons.add, color: Colors.white),
      ),
    );
  }
}

/// Диалог для добавления/редактирования вопроса пересчета
class RecountQuestionFormDialog extends StatefulWidget {
  final RecountQuestion? question;

  const RecountQuestionFormDialog({super.key, this.question});

  @override
  State<RecountQuestionFormDialog> createState() => _RecountQuestionFormDialogState();
}

class _RecountQuestionFormDialogState extends State<RecountQuestionFormDialog> {
  final _formKey = GlobalKey<FormState>();
  final _questionController = TextEditingController();
  int? _selectedGrade;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    if (widget.question != null) {
      _questionController.text = widget.question!.question;
      _selectedGrade = widget.question!.grade;
    } else {
      _selectedGrade = 1; // По умолчанию грейд 1
    }
  }

  @override
  void dispose() {
    _questionController.dispose();
    super.dispose();
  }

  Future<void> _saveQuestion() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    if (_selectedGrade == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Пожалуйста, выберите грейд'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() {
      _isSaving = true;
    });

    try {
      RecountQuestion? result;
      if (widget.question != null) {
        // Обновление существующего вопроса
        result = await RecountQuestionService.updateQuestion(
          id: widget.question!.id,
          question: _questionController.text.trim(),
          grade: _selectedGrade,
        );
      } else {
        // Создание нового вопроса
        result = await RecountQuestionService.createQuestion(
          question: _questionController.text.trim(),
          grade: _selectedGrade!,
        );
      }

      if (result != null && mounted) {
        Navigator.pop(context, result);
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Ошибка сохранения вопроса'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.question == null ? 'Добавить вопрос' : 'Редактировать вопрос'),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextFormField(
                controller: _questionController,
                decoration: const InputDecoration(
                  labelText: 'Текст вопроса',
                  border: OutlineInputBorder(),
                  hintText: 'Введите текст вопроса',
                ),
                maxLines: 3,
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Пожалуйста, введите текст вопроса';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 24),
              const Text(
                'Грейд важности:',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              RadioListTile<int>(
                title: Row(
                  children: [
                    Container(
                      width: 20,
                      height: 20,
                      decoration: BoxDecoration(
                        color: Colors.red,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Text('Грейд 1: Очень важный'),
                  ],
                ),
                value: 1,
                groupValue: _selectedGrade,
                onChanged: (value) {
                  setState(() {
                    _selectedGrade = value;
                  });
                },
              ),
              RadioListTile<int>(
                title: Row(
                  children: [
                    Container(
                      width: 20,
                      height: 20,
                      decoration: BoxDecoration(
                        color: Colors.orange,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Text('Грейд 2: Средней важности'),
                  ],
                ),
                value: 2,
                groupValue: _selectedGrade,
                onChanged: (value) {
                  setState(() {
                    _selectedGrade = value;
                  });
                },
              ),
              RadioListTile<int>(
                title: Row(
                  children: [
                    Container(
                      width: 20,
                      height: 20,
                      decoration: BoxDecoration(
                        color: Colors.green,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Text('Грейд 3: Не очень важный'),
                  ],
                ),
                value: 3,
                groupValue: _selectedGrade,
                onChanged: (value) {
                  setState(() {
                    _selectedGrade = value;
                  });
                },
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSaving ? null : () => Navigator.pop(context),
          child: const Text('Отмена'),
        ),
        ElevatedButton(
          onPressed: _isSaving ? null : _saveQuestion,
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF004D40),
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
              : const Text('Сохранить'),
        ),
      ],
    );
  }
}

