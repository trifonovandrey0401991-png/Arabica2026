import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb;
import '../models/shift_handover_question_model.dart';
import '../services/shift_handover_question_service.dart';
import '../../shops/models/shop_model.dart';
import '../../envelope/models/envelope_question_model.dart';
import '../../envelope/services/envelope_question_service.dart';

/// Страница управления вопросами сдачи смены
class ShiftHandoverQuestionsManagementPage extends StatefulWidget {
  const ShiftHandoverQuestionsManagementPage({super.key});

  @override
  State<ShiftHandoverQuestionsManagementPage> createState() => _ShiftHandoverQuestionsManagementPageState();
}

class _ShiftHandoverQuestionsManagementPageState extends State<ShiftHandoverQuestionsManagementPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  // Вопросы сдачи смены
  List<ShiftHandoverQuestion> _questions = [];
  bool _isLoading = true;

  // Вопросы формирования конверта
  List<EnvelopeQuestion> _envelopeQuestions = [];
  bool _isLoadingEnvelope = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      // Перестроить UI когда вкладка меняется
      if (!_tabController.indexIsChanging) {
        setState(() {});
      }
    });
    _loadQuestions();
    _loadEnvelopeQuestions();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadEnvelopeQuestions() async {
    setState(() {
      _isLoadingEnvelope = true;
    });

    try {
      final questions = await EnvelopeQuestionService.getQuestions();
      setState(() {
        _envelopeQuestions = questions;
        _isLoadingEnvelope = false;
      });
    } catch (e) {
      setState(() {
        _isLoadingEnvelope = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка загрузки вопросов конверта: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _loadQuestions() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final questions = await ShiftHandoverQuestionService.getQuestions();
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
    final result = await showDialog<ShiftHandoverQuestion>(
      context: context,
      builder: (context) => const ShiftHandoverQuestionFormDialog(),
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

  Future<void> _showEditQuestionDialog(ShiftHandoverQuestion question) async {
    final result = await showDialog<ShiftHandoverQuestion>(
      context: context,
      builder: (context) => ShiftHandoverQuestionFormDialog(question: question),
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

  Future<void> _deleteQuestion(ShiftHandoverQuestion question) async {
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
      final success = await ShiftHandoverQuestionService.deleteQuestion(question.id);
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

  String _getAnswerTypeLabel(ShiftHandoverQuestion question) {
    if (question.isPhotoOnly) return 'Фото';
    if (question.isYesNo) return 'Да/Нет';
    if (question.isNumberOnly) return 'Число';
    return 'Текст';
  }

  IconData _getAnswerTypeIcon(ShiftHandoverQuestion question) {
    if (question.isPhotoOnly) return Icons.camera_alt;
    if (question.isYesNo) return Icons.check_circle;
    if (question.isNumberOnly) return Icons.numbers;
    return Icons.text_fields;
  }

  Future<void> _showEditEnvelopeQuestionDialog(EnvelopeQuestion question) async {
    final result = await showDialog<EnvelopeQuestion>(
      context: context,
      builder: (context) => EnvelopeQuestionFormDialog(question: question),
    );

    if (result != null) {
      await _loadEnvelopeQuestions();
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

  Future<void> _toggleEnvelopeQuestionActive(EnvelopeQuestion question) async {
    final updated = question.copyWith(isActive: !question.isActive);
    final result = await EnvelopeQuestionService.updateQuestion(updated);

    if (result != null) {
      await _loadEnvelopeQuestions();
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Ошибка обновления вопроса'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Управление вопросами'),
        backgroundColor: const Color(0xFF004D40),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          tabs: const [
            Tab(text: 'Сдача смены'),
            Tab(text: 'Форм. конверта'),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              _loadQuestions();
              _loadEnvelopeQuestions();
            },
            tooltip: 'Обновить',
          ),
        ],
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          // Вкладка 1: Сдача смены
          _buildShiftHandoverQuestionsTab(),
          // Вкладка 2: Формирование конверта
          _buildEnvelopeQuestionsTab(),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          if (_tabController.index == 0) {
            _showAddQuestionDialog();
          }
        },
        backgroundColor: _tabController.index == 0 ? const Color(0xFF004D40) : Colors.grey,
        child: const Icon(Icons.add, color: Colors.white),
      ),
    );
  }

  Widget _buildShiftHandoverQuestionsTab() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_questions.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.question_answer, size: 64, color: Colors.grey),
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
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _questions.length,
      itemBuilder: (context, index) {
        final question = _questions[index];
        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: const Color(0xFF004D40),
              child: Text(
                '${index + 1}',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            title: Text(
              question.question,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
            subtitle: Row(
              children: [
                Icon(
                  _getAnswerTypeIcon(question),
                  size: 16,
                  color: Colors.grey[600],
                ),
                const SizedBox(width: 4),
                Text(
                  _getAnswerTypeLabel(question),
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey[600],
                  ),
                ),
              ],
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
            isThreeLine: false,
          ),
        );
      },
    );
  }

  Widget _buildEnvelopeQuestionsTab() {
    if (_isLoadingEnvelope) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_envelopeQuestions.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.mail, size: 64, color: Colors.grey),
            const SizedBox(height: 16),
            const Text(
              'Нет вопросов',
              style: TextStyle(fontSize: 18, color: Colors.grey),
            ),
            const SizedBox(height: 8),
            const Text(
              'Вопросы конверта не загружены',
              style: TextStyle(fontSize: 14, color: Colors.grey),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _envelopeQuestions.length,
      itemBuilder: (context, index) {
        final question = _envelopeQuestions[index];
        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: question.isActive ? const Color(0xFF004D40) : Colors.grey,
              child: Text(
                '${question.order}',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            title: Row(
              children: [
                Expanded(
                  child: Text(
                    question.title,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: question.isActive ? Colors.black : Colors.grey,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: _getSectionColor(question.section).withOpacity(0.2),
                    borderRadius: BorderRadius.circular(12),
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
              ],
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (question.description.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      question.description,
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey[600],
                      ),
                    ),
                  ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Icon(
                      _getEnvelopeTypeIcon(question.type),
                      size: 16,
                      color: Colors.grey[600],
                    ),
                    const SizedBox(width: 4),
                    Text(
                      question.typeText,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[600],
                      ),
                    ),
                  ],
                ),
              ],
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Switch(
                  value: question.isActive,
                  onChanged: (value) => _toggleEnvelopeQuestionActive(question),
                  activeColor: const Color(0xFF004D40),
                ),
                IconButton(
                  icon: const Icon(Icons.edit, color: Color(0xFF004D40)),
                  onPressed: () => _showEditEnvelopeQuestionDialog(question),
                  tooltip: 'Редактировать',
                ),
              ],
            ),
            isThreeLine: true,
          ),
        );
      },
    );
  }

  Color _getSectionColor(String section) {
    switch (section) {
      case 'ooo':
        return Colors.blue;
      case 'ip':
        return Colors.orange;
      case 'general':
        return Colors.green;
      default:
        return Colors.grey;
    }
  }

  IconData _getEnvelopeTypeIcon(String type) {
    switch (type) {
      case 'photo':
        return Icons.camera_alt;
      case 'numbers':
        return Icons.dialpad;
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
}

/// Диалог для добавления/редактирования вопроса
class ShiftHandoverQuestionFormDialog extends StatefulWidget {
  final ShiftHandoverQuestion? question;

  const ShiftHandoverQuestionFormDialog({super.key, this.question});

  @override
  State<ShiftHandoverQuestionFormDialog> createState() => _ShiftHandoverQuestionFormDialogState();
}

class _ShiftHandoverQuestionFormDialogState extends State<ShiftHandoverQuestionFormDialog> {
  final _formKey = GlobalKey<FormState>();
  final _questionController = TextEditingController();
  String? _selectedAnswerType;
  String? _selectedTargetRole; // 'manager' или 'employee'
  bool _isSaving = false;
  bool _isForAllShops = false;
  List<Shop> _allShops = [];
  Set<String> _selectedShopAddresses = {};
  Map<String, String> _referencePhotoUrls = {};
  Map<String, File?> _referencePhotoFiles = {};
  Map<String, Uint8List?> _referencePhotoBytes = {}; // Для веб-платформы
  bool _isLoadingShops = true;
  bool _isUploadingPhotos = false;

  @override
  void initState() {
    super.initState();
    if (widget.question != null) {
      _questionController.text = widget.question!.question;
      if (widget.question!.isPhotoOnly) {
        _selectedAnswerType = 'photo';
      } else if (widget.question!.isYesNo) {
        _selectedAnswerType = 'yesno';
      } else if (widget.question!.isNumberOnly) {
        _selectedAnswerType = 'number';
      } else {
        _selectedAnswerType = 'text';
      }

      if (widget.question!.shops == null) {
        _isForAllShops = true;
      } else {
        _selectedShopAddresses = widget.question!.shops!.toSet();
      }

      if (widget.question!.referencePhotos != null) {
        _referencePhotoUrls = Map<String, String>.from(widget.question!.referencePhotos!);
      }

      _selectedTargetRole = widget.question!.targetRole ?? 'all';
    } else {
      _selectedAnswerType = 'text';
      _selectedTargetRole = 'all'; // По умолчанию "Всем"
    }
    _loadShops();
  }

  Future<void> _loadShops() async {
    try {
      setState(() => _isLoadingShops = true);
      final shops = await Shop.loadShopsFromServer();
      setState(() {
        _allShops = shops;
        _isLoadingShops = false;
      });
    } catch (e) {
      setState(() => _isLoadingShops = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка загрузки магазинов: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _pickReferencePhoto(String shopAddress) async {
    try {
      final ImagePicker picker = ImagePicker();
      final XFile? image = await picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 85,
      );

      if (image != null) {
        // Читаем bytes для веб-платформы
        final bytes = await image.readAsBytes();

        // Создаем веб-совместимый файл
        final File photoFile;
        if (kIsWeb) {
          // На веб создаем файл из байтов
          photoFile = _XFileWrapper(image.path, bytes);
        } else {
          // На мобильных используем обычный File
          photoFile = File(image.path);
        }

        setState(() {
          _referencePhotoFiles[shopAddress] = photoFile;
          _referencePhotoBytes[shopAddress] = bytes;
        });

        if (widget.question != null) {
          await _uploadReferencePhoto(widget.question!.id, shopAddress, photoFile);
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка выбора фото: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _uploadReferencePhoto(String questionId, String shopAddress, File photoFile) async {
    try {
      setState(() => _isUploadingPhotos = true);

      final photoUrl = await ShiftHandoverQuestionService.uploadReferencePhoto(
        questionId: questionId,
        shopAddress: shopAddress,
        photoFile: photoFile,
      );

      if (photoUrl != null) {
        setState(() {
          _referencePhotoUrls[shopAddress] = photoUrl;
          _isUploadingPhotos = false;
        });
      } else {
        setState(() => _isUploadingPhotos = false);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Ошибка загрузки эталонного фото'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      setState(() => _isUploadingPhotos = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
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

    setState(() {
      _isSaving = true;
    });

    try {
      String? answerFormatB;
      String? answerFormatC;

      switch (_selectedAnswerType) {
        case 'photo':
          answerFormatB = 'photo';
          answerFormatC = null;
          break;
        case 'yesno':
          answerFormatB = null;
          answerFormatC = null;
          break;
        case 'number':
          answerFormatB = null;
          answerFormatC = 'число';
          break;
        case 'text':
        default:
          answerFormatB = 'text';
          answerFormatC = null;
          break;
      }

      List<String>? shops = _isForAllShops ? null : _selectedShopAddresses.toList();

      ShiftHandoverQuestion? result;
      if (widget.question != null) {
        result = await ShiftHandoverQuestionService.updateQuestion(
          id: widget.question!.id,
          question: _questionController.text.trim(),
          answerFormatB: answerFormatB,
          answerFormatC: answerFormatC,
          shops: shops,
          referencePhotos: _referencePhotoUrls.isNotEmpty ? _referencePhotoUrls : null,
          targetRole: _selectedTargetRole,
        );

        if (result != null && _selectedAnswerType == 'photo') {
          for (final entry in _referencePhotoFiles.entries) {
            if (entry.value != null && !_referencePhotoUrls.containsKey(entry.key)) {
              await _uploadReferencePhoto(result.id, entry.key, entry.value!);
            }
          }
          final updatedResult = await ShiftHandoverQuestionService.getQuestion(result.id);
          if (updatedResult != null) {
            result = updatedResult;
          }
        }
      } else {
        result = await ShiftHandoverQuestionService.createQuestion(
          question: _questionController.text.trim(),
          answerFormatB: answerFormatB,
          answerFormatC: answerFormatC,
          shops: shops,
          referencePhotos: null,
          targetRole: _selectedTargetRole,
        );

        if (result != null && _selectedAnswerType == 'photo') {
          final Map<String, String> uploadedPhotos = {};
          for (final entry in _referencePhotoFiles.entries) {
            if (entry.value != null) {
              final photoUrl = await ShiftHandoverQuestionService.uploadReferencePhoto(
                questionId: result.id,
                shopAddress: entry.key,
                photoFile: entry.value!,
              );
              if (photoUrl != null) {
                uploadedPhotos[entry.key] = photoUrl;
              }
            }
          }

          if (uploadedPhotos.isNotEmpty) {
            final updatedResult = await ShiftHandoverQuestionService.updateQuestion(
              id: result.id,
              referencePhotos: uploadedPhotos,
            );
            if (updatedResult != null) {
              result = updatedResult;
            }
          }
        }
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
    return Dialog(
      child: Container(
        constraints: BoxConstraints(
          maxWidth: 600,
          maxHeight: MediaQuery.of(context).size.height * 0.9,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                widget.question == null ? 'Добавить вопрос' : 'Редактировать вопрос',
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
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
                'Кому задавать вопрос:',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _buildTargetRoleOption(
                      icon: Icons.business_center,
                      label: 'Заведующая',
                      value: 'manager',
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _buildTargetRoleOption(
                      icon: Icons.person,
                      label: 'Сотрудник',
                      value: 'employee',
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _buildTargetRoleOption(
                      icon: Icons.groups,
                      label: 'Всем',
                      value: 'all',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              const Text(
                'Тип ответа:',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _buildAnswerTypeOption(
                      icon: Icons.camera_alt,
                      label: 'Фото',
                      value: 'photo',
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _buildAnswerTypeOption(
                      icon: Icons.check_circle,
                      label: 'Да/Нет',
                      value: 'yesno',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: _buildAnswerTypeOption(
                      icon: Icons.numbers,
                      label: 'Число',
                      value: 'number',
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _buildAnswerTypeOption(
                      icon: Icons.text_fields,
                      label: 'Текст',
                      value: 'text',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              const Text(
                'Магазины:',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              if (_isLoadingShops)
                const Center(child: CircularProgressIndicator())
              else ...[
                CheckboxListTile(
                  title: const Text('Задавать всем магазинам'),
                  value: _isForAllShops,
                  onChanged: (value) {
                    setState(() {
                      _isForAllShops = value ?? false;
                      if (_isForAllShops) {
                        _selectedShopAddresses.clear();
                      }
                    });
                  },
                  controlAffinity: ListTileControlAffinity.leading,
                ),
                if (!_isForAllShops) ...[
                  const SizedBox(height: 8),
                  Container(
                    constraints: const BoxConstraints(maxHeight: 200),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: SingleChildScrollView(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: _allShops.map((shop) {
                          final isSelected = _selectedShopAddresses.contains(shop.address);
                          return CheckboxListTile(
                            title: Text(shop.name),
                            subtitle: Text(
                              shop.address,
                              style: const TextStyle(fontSize: 12),
                            ),
                            value: isSelected,
                            onChanged: (value) {
                              setState(() {
                                if (value ?? false) {
                                  _selectedShopAddresses.add(shop.address);
                                } else {
                                  _selectedShopAddresses.remove(shop.address);
                                  _referencePhotoFiles.remove(shop.address);
                                  _referencePhotoBytes.remove(shop.address);
                                  _referencePhotoUrls.remove(shop.address);
                                }
                              });
                            },
                            controlAffinity: ListTileControlAffinity.leading,
                          );
                        }).toList(),
                      ),
                    ),
                  ),
                ],
                if (_selectedAnswerType == 'photo') ...[
                  const SizedBox(height: 24),
                  const Text(
                    'Эталонные фото:',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    constraints: const BoxConstraints(maxHeight: 300),
                    child: SingleChildScrollView(
                      child: Column(
                        children: _isForAllShops
                            ? _allShops.map((shop) => _buildReferencePhotoSection(shop.address, shop.name)).toList()
                            : _selectedShopAddresses.map((address) {
                                final shop = _allShops.firstWhere(
                                  (s) => s.address == address,
                                  orElse: () => Shop(
                                    id: '',
                                    name: address,
                                    address: address,
                                    icon: Icons.store,
                                  ),
                                );
                                return _buildReferencePhotoSection(address, shop.name);
                              }).toList(),
                      ),
                    ),
                  ),
                ],
              ],
                    ],
                  ),
                ),
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: _isSaving ? null : () => Navigator.pop(context),
                    child: const Text('Отмена'),
                  ),
                  const SizedBox(width: 8),
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
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAnswerTypeOption({
    required IconData icon,
    required String label,
    required String value,
  }) {
    final isSelected = _selectedAnswerType == value;
    return InkWell(
      onTap: () {
        setState(() {
          _selectedAnswerType = value;
        });
      },
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isSelected
              ? const Color(0xFF004D40).withOpacity(0.1)
              : Colors.grey[100],
          border: Border.all(
            color: isSelected ? const Color(0xFF004D40) : Colors.grey[300]!,
            width: isSelected ? 2 : 1,
          ),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          children: [
            Icon(
              icon,
              color: isSelected ? const Color(0xFF004D40) : Colors.grey[600],
              size: 32,
            ),
            const SizedBox(height: 8),
            Text(
              label,
              style: TextStyle(
                color: isSelected ? const Color(0xFF004D40) : Colors.grey[700],
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildReferencePhotoSection(String shopAddress, String shopName) {
    final hasPhoto = _referencePhotoUrls.containsKey(shopAddress) ||
                     _referencePhotoFiles.containsKey(shopAddress) ||
                     _referencePhotoBytes.containsKey(shopAddress);
    final photoFile = _referencePhotoFiles[shopAddress];
    final photoBytes = _referencePhotoBytes[shopAddress];
    final photoUrl = _referencePhotoUrls[shopAddress];

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              shopName,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 8),
            if (hasPhoto) ...[
              Container(
                height: 100,
                width: double.infinity,
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: photoBytes != null
                      ? Image.memory(
                          photoBytes,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) {
                            return const Center(child: Icon(Icons.error));
                          },
                        )
                      : photoFile != null && !kIsWeb
                          ? Image.file(
                              photoFile,
                              fit: BoxFit.cover,
                            )
                          : photoUrl != null
                              ? Image.network(
                                  photoUrl,
                                  fit: BoxFit.cover,
                                  errorBuilder: (context, error, stackTrace) {
                                    return const Center(child: Icon(Icons.error));
                                  },
                                )
                              : const Center(child: Icon(Icons.image)),
                ),
              ),
              const SizedBox(height: 8),
            ],
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _isUploadingPhotos ? null : () => _pickReferencePhoto(shopAddress),
                    icon: const Icon(Icons.add_photo_alternate, size: 18),
                    label: Text(hasPhoto ? 'Изменить фото' : 'Добавить эталонное фото'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF004D40),
                      foregroundColor: Colors.white,
                    ),
                  ),
                ),
                if (hasPhoto) ...[
                  const SizedBox(width: 8),
                  IconButton(
                    icon: const Icon(Icons.delete, color: Colors.red),
                    onPressed: () {
                      setState(() {
                        _referencePhotoFiles.remove(shopAddress);
                        _referencePhotoBytes.remove(shopAddress);
                        _referencePhotoUrls.remove(shopAddress);
                      });
                    },
                    tooltip: 'Удалить фото',
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTargetRoleOption({
    required IconData icon,
    required String label,
    required String value,
  }) {
    final isSelected = _selectedTargetRole == value;
    return InkWell(
      onTap: () {
        setState(() {
          _selectedTargetRole = value;
        });
      },
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isSelected
              ? const Color(0xFF004D40).withOpacity(0.1)
              : Colors.grey[100],
          border: Border.all(
            color: isSelected ? const Color(0xFF004D40) : Colors.grey[300]!,
            width: isSelected ? 2 : 1,
          ),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          children: [
            Icon(
              icon,
              color: isSelected ? const Color(0xFF004D40) : Colors.grey[600],
              size: 32,
            ),
            const SizedBox(height: 8),
            Text(
              label,
              style: TextStyle(
                color: isSelected ? const Color(0xFF004D40) : Colors.grey[700],
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Класс-обертка для работы с XFile на веб-платформе
/// Имитирует интерфейс File, но хранит данные в памяти
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

/// Диалог для редактирования вопроса формирования конверта
class EnvelopeQuestionFormDialog extends StatefulWidget {
  final EnvelopeQuestion question;

  const EnvelopeQuestionFormDialog({super.key, required this.question});

  @override
  State<EnvelopeQuestionFormDialog> createState() => _EnvelopeQuestionFormDialogState();
}

class _EnvelopeQuestionFormDialogState extends State<EnvelopeQuestionFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _titleController;
  late TextEditingController _descriptionController;
  bool _isSaving = false;
  bool _isUploadingPhoto = false;
  String? _referencePhotoUrl;
  File? _selectedPhotoFile;
  Uint8List? _selectedPhotoBytes;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.question.title);
    _descriptionController = TextEditingController(text: widget.question.description);
    _referencePhotoUrl = widget.question.referencePhotoUrl;
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _pickReferencePhoto() async {
    try {
      final ImagePicker picker = ImagePicker();
      final XFile? image = await picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 85,
      );

      if (image != null) {
        final bytes = await image.readAsBytes();

        setState(() {
          _selectedPhotoBytes = bytes;
          if (!kIsWeb) {
            _selectedPhotoFile = File(image.path);
          }
        });

        // Загружаем фото сразу
        await _uploadPhoto();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка выбора фото: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _uploadPhoto() async {
    if (_selectedPhotoFile == null && _selectedPhotoBytes == null) return;

    setState(() {
      _isUploadingPhoto = true;
    });

    try {
      File photoFile;
      if (_selectedPhotoFile != null) {
        photoFile = _selectedPhotoFile!;
      } else {
        // Создаем временный файл для веб
        photoFile = _XFileWrapper('temp.jpg', _selectedPhotoBytes!);
      }

      final url = await EnvelopeQuestionService.uploadReferencePhoto(
        questionId: widget.question.id,
        photoFile: photoFile,
      );

      if (url != null) {
        setState(() {
          _referencePhotoUrl = url;
        });
      } else {
        if (mounted) {
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
          _isUploadingPhoto = false;
        });
      }
    }
  }

  void _removePhoto() {
    setState(() {
      _referencePhotoUrl = null;
      _selectedPhotoFile = null;
      _selectedPhotoBytes = null;
    });
  }

  Future<void> _saveQuestion() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _isSaving = true;
    });

    try {
      final updated = widget.question.copyWith(
        title: _titleController.text.trim(),
        description: _descriptionController.text.trim(),
        referencePhotoUrl: _referencePhotoUrl,
      );

      final result = await EnvelopeQuestionService.updateQuestion(updated);

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
    final isPhotoType = widget.question.type == 'photo';
    final hasPhoto = _referencePhotoUrl != null || _selectedPhotoBytes != null;

    return Dialog(
      child: Container(
        constraints: BoxConstraints(
          maxWidth: 500,
          maxHeight: MediaQuery.of(context).size.height * 0.85,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Icon(
                    _getTypeIcon(widget.question.type),
                    color: const Color(0xFF004D40),
                    size: 28,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Редактирование шага',
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            // Content
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Form(
                  key: _formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: _getSectionColor(widget.question.section).withOpacity(0.2),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              widget.question.sectionText,
                              style: TextStyle(
                                fontSize: 12,
                                color: _getSectionColor(widget.question.section),
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.grey.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              widget.question.typeText,
                              style: const TextStyle(
                                fontSize: 12,
                                color: Colors.grey,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      TextFormField(
                        controller: _titleController,
                        decoration: const InputDecoration(
                          labelText: 'Название шага',
                          border: OutlineInputBorder(),
                          hintText: 'Введите название',
                        ),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Пожалуйста, введите название';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _descriptionController,
                        decoration: const InputDecoration(
                          labelText: 'Описание',
                          border: OutlineInputBorder(),
                          hintText: 'Введите описание для сотрудника',
                        ),
                        maxLines: 3,
                      ),
                      // Эталонное фото (только для типа photo)
                      if (isPhotoType) ...[
                        const SizedBox(height: 20),
                        const Text(
                          'Эталонное фото:',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Сотрудник увидит это фото как образец',
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.grey[600],
                          ),
                        ),
                        const SizedBox(height: 12),
                        if (hasPhoto)
                          Container(
                            height: 150,
                            width: double.infinity,
                            decoration: BoxDecoration(
                              border: Border.all(color: Colors.grey[300]!),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Stack(
                              children: [
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(12),
                                  child: _selectedPhotoBytes != null
                                      ? Image.memory(
                                          _selectedPhotoBytes!,
                                          fit: BoxFit.cover,
                                          width: double.infinity,
                                          height: double.infinity,
                                        )
                                      : _referencePhotoUrl != null
                                          ? Image.network(
                                              _referencePhotoUrl!,
                                              fit: BoxFit.cover,
                                              width: double.infinity,
                                              height: double.infinity,
                                              errorBuilder: (_, __, ___) => const Center(
                                                child: Icon(Icons.error, size: 48),
                                              ),
                                            )
                                          : const SizedBox(),
                                ),
                                if (_isUploadingPhoto)
                                  Container(
                                    color: Colors.black.withOpacity(0.5),
                                    child: const Center(
                                      child: CircularProgressIndicator(color: Colors.white),
                                    ),
                                  ),
                                Positioned(
                                  top: 8,
                                  right: 8,
                                  child: IconButton(
                                    icon: const Icon(Icons.delete, color: Colors.red),
                                    onPressed: _isUploadingPhoto ? null : _removePhoto,
                                    style: IconButton.styleFrom(
                                      backgroundColor: Colors.white,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          )
                        else
                          Container(
                            height: 100,
                            width: double.infinity,
                            decoration: BoxDecoration(
                              border: Border.all(color: Colors.grey[300]!, style: BorderStyle.solid),
                              borderRadius: BorderRadius.circular(12),
                              color: Colors.grey[50],
                            ),
                            child: InkWell(
                              onTap: _isUploadingPhoto ? null : _pickReferencePhoto,
                              borderRadius: BorderRadius.circular(12),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.add_photo_alternate, size: 40, color: Colors.grey[400]),
                                  const SizedBox(height: 8),
                                  Text(
                                    'Добавить эталонное фото',
                                    style: TextStyle(color: Colors.grey[600]),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        if (hasPhoto)
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: ElevatedButton.icon(
                              onPressed: _isUploadingPhoto ? null : _pickReferencePhoto,
                              icon: const Icon(Icons.photo_camera, size: 18),
                              label: const Text('Изменить фото'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF004D40),
                              ),
                            ),
                          ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
            const Divider(height: 1),
            // Actions
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: _isSaving ? null : () => Navigator.pop(context),
                    child: const Text('Отмена'),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: (_isSaving || _isUploadingPhoto) ? null : _saveQuestion,
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
        return Icons.dialpad;
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
        return Colors.green;
      default:
        return Colors.grey;
    }
  }
}
