import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb;
import '../models/envelope_question_model.dart';
import '../services/envelope_question_service.dart';

/// Страница управления вопросами формирования конверта
class EnvelopeQuestionsManagementPage extends StatefulWidget {
  const EnvelopeQuestionsManagementPage({super.key});

  @override
  State<EnvelopeQuestionsManagementPage> createState() => _EnvelopeQuestionsManagementPageState();
}

class _EnvelopeQuestionsManagementPageState extends State<EnvelopeQuestionsManagementPage> {
  List<EnvelopeQuestion> _questions = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadQuestions();
  }

  Future<void> _loadQuestions() async {
    setState(() => _isLoading = true);

    try {
      final questions = await EnvelopeQuestionService.getQuestions();
      setState(() {
        _questions = questions;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка загрузки: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _toggleQuestion(EnvelopeQuestion question) async {
    final updated = question.copyWith(isActive: !question.isActive);
    final result = await EnvelopeQuestionService.updateQuestion(updated);

    if (result != null) {
      await _loadQuestions();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(updated.isActive ? 'Вопрос включен' : 'Вопрос выключен'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Ошибка обновления'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// Диалог добавления/редактирования вопроса
  Future<void> _showAddEditDialog({EnvelopeQuestion? question}) async {
    final isEdit = question != null;
    final titleController = TextEditingController(text: question?.title ?? '');
    final descriptionController = TextEditingController(text: question?.description ?? '');

    String selectedType = question?.type ?? 'photo';
    String selectedSection = question?.section ?? 'general';
    int order = question?.order ?? (_questions.isEmpty ? 1 : _questions.last.order + 1);
    bool isRequired = question?.isRequired ?? true;

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(isEdit ? 'Редактировать вопрос' : 'Новый вопрос'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: titleController,
                  decoration: const InputDecoration(
                    labelText: 'Название *',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: descriptionController,
                  decoration: const InputDecoration(
                    labelText: 'Описание',
                    border: OutlineInputBorder(),
                  ),
                  maxLines: 2,
                ),
                const SizedBox(height: 16),
                // Тип вопроса
                const Text('Тип:', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: [
                    ChoiceChip(
                      label: const Text('Фото'),
                      selected: selectedType == 'photo',
                      onSelected: (selected) {
                        if (selected) setDialogState(() => selectedType = 'photo');
                      },
                    ),
                    ChoiceChip(
                      label: const Text('Числа'),
                      selected: selectedType == 'numbers',
                      onSelected: (selected) {
                        if (selected) setDialogState(() => selectedType = 'numbers');
                      },
                    ),
                    ChoiceChip(
                      label: const Text('Расходы'),
                      selected: selectedType == 'expenses',
                      onSelected: (selected) {
                        if (selected) setDialogState(() => selectedType = 'expenses');
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                // Секция
                const Text('Секция:', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: [
                    ChoiceChip(
                      label: const Text('ООО'),
                      selected: selectedSection == 'ooo',
                      onSelected: (selected) {
                        if (selected) setDialogState(() => selectedSection = 'ooo');
                      },
                    ),
                    ChoiceChip(
                      label: const Text('ИП'),
                      selected: selectedSection == 'ip',
                      onSelected: (selected) {
                        if (selected) setDialogState(() => selectedSection = 'ip');
                      },
                    ),
                    ChoiceChip(
                      label: const Text('Общее'),
                      selected: selectedSection == 'general',
                      onSelected: (selected) {
                        if (selected) setDialogState(() => selectedSection = 'general');
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                // Порядок
                Row(
                  children: [
                    const Text('Порядок:', style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(width: 16),
                    IconButton(
                      icon: const Icon(Icons.remove_circle_outline),
                      onPressed: order > 1 ? () => setDialogState(() => order--) : null,
                    ),
                    Text('$order', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    IconButton(
                      icon: const Icon(Icons.add_circle_outline),
                      onPressed: () => setDialogState(() => order++),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                // Обязательный
                SwitchListTile(
                  title: const Text('Обязательный'),
                  value: isRequired,
                  onChanged: (value) => setDialogState(() => isRequired = value),
                  contentPadding: EdgeInsets.zero,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Отмена'),
            ),
            ElevatedButton(
              onPressed: () {
                if (titleController.text.trim().isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Введите название'),
                      backgroundColor: Colors.orange,
                    ),
                  );
                  return;
                }
                Navigator.pop(context, true);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF004D40),
                foregroundColor: Colors.white,
              ),
              child: Text(isEdit ? 'Сохранить' : 'Создать'),
            ),
          ],
        ),
      ),
    );

    if (result == true) {
      final newQuestion = EnvelopeQuestion(
        id: question?.id ?? 'envelope_q_${DateTime.now().millisecondsSinceEpoch}',
        title: titleController.text.trim(),
        description: descriptionController.text.trim(),
        type: selectedType,
        section: selectedSection,
        order: order,
        isRequired: isRequired,
        isActive: question?.isActive ?? true,
        referencePhotoUrl: question?.referencePhotoUrl,
      );

      EnvelopeQuestion? savedQuestion;
      if (isEdit) {
        savedQuestion = await EnvelopeQuestionService.updateQuestion(newQuestion);
      } else {
        savedQuestion = await EnvelopeQuestionService.createQuestion(newQuestion);
      }

      if (savedQuestion != null) {
        await _loadQuestions();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(isEdit ? 'Вопрос обновлен' : 'Вопрос создан'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(isEdit ? 'Ошибка обновления' : 'Ошибка создания'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  /// Удаление вопроса
  Future<void> _deleteQuestion(EnvelopeQuestion question) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Удалить вопрос?'),
        content: Text('Вопрос "${question.title}" будет удален безвозвратно.'),
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
      final success = await EnvelopeQuestionService.deleteQuestion(question.id);
      if (success) {
        await _loadQuestions();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Вопрос удален'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Ошибка удаления'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  Future<void> _uploadReferencePhoto(EnvelopeQuestion question) async {
    try {
      final ImagePicker picker = ImagePicker();
      final XFile? image = await picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 85,
      );

      if (image == null) return;

      // Показываем индикатор загрузки
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Row(
              children: [
                SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                ),
                SizedBox(width: 16),
                Text('Загрузка фото...'),
              ],
            ),
            duration: Duration(seconds: 10),
          ),
        );
      }

      // Создаем File из XFile
      File photoFile;
      if (kIsWeb) {
        final bytes = await image.readAsBytes();
        photoFile = _XFileWrapper(image.path, bytes);
      } else {
        photoFile = File(image.path);
      }

      // Загружаем фото
      final photoUrl = await EnvelopeQuestionService.uploadReferencePhoto(
        questionId: question.id,
        photoFile: photoFile,
      );

      if (photoUrl != null) {
        // Обновляем вопрос с новым URL фото
        final updated = question.copyWith(referencePhotoUrl: photoUrl);
        await EnvelopeQuestionService.updateQuestion(updated);
        await _loadQuestions();

        if (mounted) {
          ScaffoldMessenger.of(context).hideCurrentSnackBar();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Эталонное фото загружено'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).hideCurrentSnackBar();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Ошибка загрузки фото'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _removeReferencePhoto(EnvelopeQuestion question) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Удалить эталонное фото?'),
        content: const Text('Это действие нельзя отменить.'),
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
      final updated = EnvelopeQuestion(
        id: question.id,
        title: question.title,
        description: question.description,
        type: question.type,
        section: question.section,
        order: question.order,
        isRequired: question.isRequired,
        isActive: question.isActive,
        referencePhotoUrl: null,
      );

      final result = await EnvelopeQuestionService.updateQuestion(updated);
      if (result != null) {
        await _loadQuestions();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Эталонное фото удалено'),
              backgroundColor: Colors.green,
            ),
          );
        }
      }
    }
  }

  void _showReferencePhoto(EnvelopeQuestion question) {
    if (question.referencePhotoUrl == null) return;

    showDialog(
      context: context,
      builder: (context) => Dialog(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppBar(
              title: Text(question.title),
              automaticallyImplyLeading: false,
              actions: [
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            InteractiveViewer(
              child: Image.network(
                question.referencePhotoUrl!,
                fit: BoxFit.contain,
                loadingBuilder: (context, child, loadingProgress) {
                  if (loadingProgress == null) return child;
                  return const SizedBox(
                    height: 200,
                    child: Center(child: CircularProgressIndicator()),
                  );
                },
                errorBuilder: (context, error, stackTrace) {
                  return const SizedBox(
                    height: 200,
                    child: Center(
                      child: Icon(Icons.error, size: 64, color: Colors.red),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  IconData _getTypeIcon(String type) {
    switch (type) {
      case 'photo':
        return Icons.camera_alt;
      case 'numbers':
        return Icons.pin;
      case 'expenses':
        return Icons.receipt_long;
      case 'shift_select':
        return Icons.schedule;
      case 'summary':
        return Icons.summarize;
      default:
        return Icons.help_outline;
    }
  }

  Color _getSectionColor(String section) {
    switch (section) {
      case 'ooo':
        return Colors.blue;
      case 'ip':
        return Colors.orange;
      case 'general':
        return Colors.grey;
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Вопросы (Конверт)'),
        backgroundColor: const Color(0xFF004D40),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadQuestions,
            tooltip: 'Обновить',
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showAddEditDialog(),
        backgroundColor: const Color(0xFF004D40),
        child: const Icon(Icons.add, color: Colors.white),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _questions.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.mail_outline, size: 64, color: Colors.grey),
                      const SizedBox(height: 16),
                      const Text(
                        'Нет вопросов',
                        style: TextStyle(fontSize: 18, color: Colors.grey),
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton.icon(
                        onPressed: () => _showAddEditDialog(),
                        icon: const Icon(Icons.add),
                        label: const Text('Добавить вопрос'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF004D40),
                          foregroundColor: Colors.white,
                        ),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _questions.length,
                  itemBuilder: (context, index) {
                    final question = _questions[index];
                    final hasReferencePhoto = question.referencePhotoUrl != null &&
                                              question.referencePhotoUrl!.isNotEmpty;

                    return Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      elevation: question.isActive ? 2 : 0,
                      color: question.isActive ? null : Colors.grey[200],
                      child: Column(
                        children: [
                          ListTile(
                            leading: CircleAvatar(
                              backgroundColor: question.isActive
                                  ? _getSectionColor(question.section)
                                  : Colors.grey,
                              child: Icon(
                                _getTypeIcon(question.type),
                                color: Colors.white,
                                size: 20,
                              ),
                            ),
                            title: Text(
                              question.title,
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: question.isActive ? null : Colors.grey,
                                decoration: question.isActive
                                    ? null
                                    : TextDecoration.lineThrough,
                              ),
                            ),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  question.description,
                                  style: TextStyle(
                                    color: question.isActive
                                        ? Colors.grey[600]
                                        : Colors.grey,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 2,
                                      ),
                                      decoration: BoxDecoration(
                                        color: _getSectionColor(question.section)
                                            .withOpacity(0.2),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Text(
                                        question.sectionText,
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: _getSectionColor(question.section),
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 2,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Colors.grey.withOpacity(0.2),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Text(
                                        question.typeText,
                                        style: const TextStyle(
                                          fontSize: 12,
                                          color: Colors.grey,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.edit, size: 20),
                                  onPressed: () => _showAddEditDialog(question: question),
                                  tooltip: 'Редактировать',
                                  color: Colors.blue,
                                ),
                                IconButton(
                                  icon: const Icon(Icons.delete, size: 20),
                                  onPressed: () => _deleteQuestion(question),
                                  tooltip: 'Удалить',
                                  color: Colors.red,
                                ),
                                Switch(
                                  value: question.isActive,
                                  onChanged: (_) => _toggleQuestion(question),
                                  activeColor: const Color(0xFF004D40),
                                ),
                              ],
                            ),
                          ),
                          // Секция эталонного фото для типа photo
                          if (question.type == 'photo') ...[
                            const Divider(height: 1),
                            Padding(
                              padding: const EdgeInsets.all(12),
                              child: Row(
                                children: [
                                  if (hasReferencePhoto) ...[
                                    GestureDetector(
                                      onTap: () => _showReferencePhoto(question),
                                      child: Container(
                                        width: 60,
                                        height: 60,
                                        decoration: BoxDecoration(
                                          borderRadius: BorderRadius.circular(8),
                                          border: Border.all(color: Colors.grey[300]!),
                                        ),
                                        child: ClipRRect(
                                          borderRadius: BorderRadius.circular(8),
                                          child: Image.network(
                                            question.referencePhotoUrl!,
                                            fit: BoxFit.cover,
                                            errorBuilder: (_, __, ___) => const Icon(
                                              Icons.broken_image,
                                              color: Colors.grey,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          const Text(
                                            'Эталонное фото',
                                            style: TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 12,
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          Row(
                                            children: [
                                              TextButton.icon(
                                                onPressed: () => _uploadReferencePhoto(question),
                                                icon: const Icon(Icons.refresh, size: 16),
                                                label: const Text('Заменить'),
                                                style: TextButton.styleFrom(
                                                  padding: EdgeInsets.zero,
                                                  minimumSize: const Size(0, 30),
                                                ),
                                              ),
                                              const SizedBox(width: 8),
                                              TextButton.icon(
                                                onPressed: () => _removeReferencePhoto(question),
                                                icon: const Icon(Icons.delete, size: 16),
                                                label: const Text('Удалить'),
                                                style: TextButton.styleFrom(
                                                  padding: EdgeInsets.zero,
                                                  minimumSize: const Size(0, 30),
                                                  foregroundColor: Colors.red,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                  ] else ...[
                                    Container(
                                      width: 60,
                                      height: 60,
                                      decoration: BoxDecoration(
                                        color: Colors.grey[100],
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(
                                          color: Colors.grey[300]!,
                                          style: BorderStyle.solid,
                                        ),
                                      ),
                                      child: Icon(
                                        Icons.add_photo_alternate,
                                        color: Colors.grey[400],
                                        size: 30,
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            'Нет эталонного фото',
                                            style: TextStyle(
                                              color: Colors.grey[600],
                                              fontSize: 12,
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          ElevatedButton.icon(
                                            onPressed: () => _uploadReferencePhoto(question),
                                            icon: const Icon(Icons.add_photo_alternate, size: 16),
                                            label: const Text('Добавить эталон'),
                                            style: ElevatedButton.styleFrom(
                                              backgroundColor: const Color(0xFF004D40),
                                              foregroundColor: Colors.white,
                                              padding: const EdgeInsets.symmetric(
                                                horizontal: 12,
                                                vertical: 8,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                    );
                  },
                ),
    );
  }
}

/// Класс-обертка для работы с XFile на веб-платформе
class _XFileWrapper implements File {
  final String _path;
  final Uint8List _bytes;

  _XFileWrapper(String path, List<int> bytes)
      : _path = path,
        _bytes = bytes is Uint8List ? bytes : Uint8List.fromList(bytes);

  @override
  String get path => _path;

  @override
  Future<Uint8List> readAsBytes() async => _bytes;

  @override
  Uint8List readAsBytesSync() => _bytes;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
