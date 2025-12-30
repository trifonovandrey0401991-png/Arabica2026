import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb;
import '../models/shift_handover_question_model.dart';
import '../services/shift_handover_question_service.dart';
import '../../shops/models/shop_model.dart';

/// Страница управления вопросами сдачи смены
class ShiftHandoverQuestionsManagementPage extends StatefulWidget {
  const ShiftHandoverQuestionsManagementPage({super.key});

  @override
  State<ShiftHandoverQuestionsManagementPage> createState() => _ShiftHandoverQuestionsManagementPageState();
}

class _ShiftHandoverQuestionsManagementPageState extends State<ShiftHandoverQuestionsManagementPage> {
  List<ShiftHandoverQuestion> _questions = [];
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Вопросы (Сдача Смены)'),
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
                )
              : ListView.builder(
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
                ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showAddQuestionDialog,
        backgroundColor: const Color(0xFF004D40),
        child: const Icon(Icons.add, color: Colors.white),
      ),
    );
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
