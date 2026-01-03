import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb;
import '../models/shift_question_model.dart';
import '../services/shift_question_service.dart';
import '../../shops/models/shop_model.dart';

/// Страница управления вопросами пересменки
class ShiftQuestionsManagementPage extends StatefulWidget {
  const ShiftQuestionsManagementPage({super.key});

  @override
  State<ShiftQuestionsManagementPage> createState() => _ShiftQuestionsManagementPageState();
}

class _ShiftQuestionsManagementPageState extends State<ShiftQuestionsManagementPage> {
  List<ShiftQuestion> _questions = [];
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
      final questions = await ShiftQuestionService.getQuestions();
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
    final result = await showDialog<ShiftQuestion>(
      context: context,
      builder: (context) => const ShiftQuestionFormDialog(),
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

  Future<void> _showEditQuestionDialog(ShiftQuestion question) async {
    final result = await showDialog<ShiftQuestion>(
      context: context,
      builder: (context) => ShiftQuestionFormDialog(question: question),
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

  Future<void> _deleteQuestion(ShiftQuestion question) async {
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
      final success = await ShiftQuestionService.deleteQuestion(question.id);
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

  String _getAnswerTypeLabel(ShiftQuestion question) {
    if (question.isPhotoOnly) return 'Фото';
    if (question.isYesNo) return 'Да/Нет';
    if (question.isNumberOnly) return 'Число';
    return 'Текст';
  }

  IconData _getAnswerTypeIcon(ShiftQuestion question) {
    if (question.isPhotoOnly) return Icons.camera_alt;
    if (question.isYesNo) return Icons.check_circle;
    if (question.isNumberOnly) return Icons.numbers;
    return Icons.text_fields;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Вопросы пересменки'),
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
class ShiftQuestionFormDialog extends StatefulWidget {
  final ShiftQuestion? question;

  const ShiftQuestionFormDialog({super.key, this.question});

  @override
  State<ShiftQuestionFormDialog> createState() => _ShiftQuestionFormDialogState();
}

class _ShiftQuestionFormDialogState extends State<ShiftQuestionFormDialog> {
  final _formKey = GlobalKey<FormState>();
  final _questionController = TextEditingController();
  String? _selectedAnswerType; // 'photo', 'yesno', 'number', 'text'
  bool _isSaving = false;
  bool _isForAllShops = false; // Задавать всем магазинам
  List<Shop> _allShops = [];
  Set<String> _selectedShopAddresses = {}; // Выбранные адреса магазинов
  Map<String, String> _referencePhotoUrls = {}; // URL эталонных фото для каждого магазина
  Map<String, File?> _referencePhotoFiles = {}; // Локальные файлы эталонных фото
  bool _isLoadingShops = true;
  bool _isUploadingPhotos = false;

  @override
  void initState() {
    super.initState();
    if (widget.question != null) {
      _questionController.text = widget.question!.question;
      // Определяем тип ответа из существующего вопроса
      if (widget.question!.isPhotoOnly) {
        _selectedAnswerType = 'photo';
      } else if (widget.question!.isYesNo) {
        _selectedAnswerType = 'yesno';
      } else if (widget.question!.isNumberOnly) {
        _selectedAnswerType = 'number';
      } else {
        _selectedAnswerType = 'text';
      }
      
      // Загружаем выбранные магазины и эталонные фото
      if (widget.question!.shops == null) {
        _isForAllShops = true;
      } else {
        _selectedShopAddresses = widget.question!.shops!.toSet();
      }
      
      if (widget.question!.referencePhotos != null) {
        _referencePhotoUrls = Map<String, String>.from(widget.question!.referencePhotos!);
      }
    } else {
      _selectedAnswerType = 'text'; // По умолчанию текст
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
        // Создаем веб-совместимый файл
        final File photoFile;
        if (kIsWeb) {
          // На веб создаем файл из байтов
          final bytes = await image.readAsBytes();
          photoFile = _XFileWrapper(image.path, bytes);
        } else {
          // На мобильных используем обычный File
          photoFile = File(image.path);
        }

        setState(() {
          _referencePhotoFiles[shopAddress] = photoFile;
        });

        // Загружаем фото на сервер, если вопрос уже создан
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

      final photoUrl = await ShiftQuestionService.uploadReferencePhoto(
        questionId: questionId,
        shopAddress: shopAddress,
        photoFile: photoFile,
      );

      if (photoUrl != null) {
        setState(() {
          _referencePhotoUrls[shopAddress] = photoUrl;
        });

        // КРИТИЧЕСКИ ВАЖНО: Обновляем вопрос с новым URL эталонного фото
        print('📝 Обновление вопроса с новым эталонным фото: $questionId');
        print('   Магазин: $shopAddress');
        print('   URL фото: $photoUrl');

        final updatedQuestion = await ShiftQuestionService.updateQuestion(
          id: questionId,
          referencePhotos: _referencePhotoUrls,
        );

        if (updatedQuestion != null) {
          print('✅ Вопрос успешно обновлен с эталонным фото');
          setState(() => _isUploadingPhotos = false);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Эталонное фото успешно загружено'),
                backgroundColor: Colors.green,
                duration: Duration(seconds: 2),
              ),
            );
          }
        } else {
          print('❌ Не удалось обновить вопрос с эталонным фото');
          setState(() => _isUploadingPhotos = false);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Фото загружено, но не удалось обновить вопрос'),
                backgroundColor: Colors.orange,
              ),
            );
          }
        }
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
      print('❌ Исключение при загрузке эталонного фото: $e');
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

      // Устанавливаем формат ответа в зависимости от выбранного типа
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
          // Для текста устанавливаем 'text', чтобы не конфликтовать с isYesNo
          // isTextOnly вернет true, так как не соответствует другим типам
          answerFormatB = 'text';
          answerFormatC = null;
          break;
      }

      // Определяем shops: null если для всех, иначе список выбранных адресов
      List<String>? shops = _isForAllShops ? null : _selectedShopAddresses.toList();
      
      // Для нового вопроса сначала создаем вопрос, затем загружаем фото
      ShiftQuestion? result;
      if (widget.question != null) {
        // Обновление существующего вопроса
        result = await ShiftQuestionService.updateQuestion(
          id: widget.question!.id,
          question: _questionController.text.trim(),
          answerFormatB: answerFormatB,
          answerFormatC: answerFormatC,
          shops: shops,
          referencePhotos: _referencePhotoUrls.isNotEmpty ? _referencePhotoUrls : null,
        );
        
        // Загружаем новые эталонные фото, если есть
        if (result != null && _selectedAnswerType == 'photo') {
          for (final entry in _referencePhotoFiles.entries) {
            if (entry.value != null && !_referencePhotoUrls.containsKey(entry.key)) {
              await _uploadReferencePhoto(result.id, entry.key, entry.value!);
            }
          }
          // Перезагружаем вопрос с обновленными фото
          final updatedResult = await ShiftQuestionService.getQuestion(result.id);
          if (updatedResult != null) {
            result = updatedResult;
          }
        }
      } else {
        // Создание нового вопроса
        result = await ShiftQuestionService.createQuestion(
          question: _questionController.text.trim(),
          answerFormatB: answerFormatB,
          answerFormatC: answerFormatC,
          shops: shops,
          referencePhotos: null, // Фото загрузим отдельно
        );
        
        // Загружаем эталонные фото для нового вопроса
        if (result != null && _selectedAnswerType == 'photo') {
          final Map<String, String> uploadedPhotos = {};
          for (final entry in _referencePhotoFiles.entries) {
            if (entry.value != null) {
              final photoUrl = await ShiftQuestionService.uploadReferencePhoto(
                questionId: result.id,
                shopAddress: entry.key,
                photoFile: entry.value!,
              );
              if (photoUrl != null) {
                uploadedPhotos[entry.key] = photoUrl;
              }
            }
          }
          
          // Обновляем вопрос с загруженными фото
          if (uploadedPhotos.isNotEmpty) {
            final updatedResult = await ShiftQuestionService.updateQuestion(
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
    return AlertDialog(
      title: Text(widget.question == null ? 'Добавить вопрос' : 'Редактировать вопрос'),
      content: SizedBox(
        width: MediaQuery.of(context).size.width * 0.9,
        child: SingleChildScrollView(
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
              // Выбор магазинов
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
                // Кнопка "Задавать всем магазинам"
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
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: _allShops.length,
                      itemBuilder: (context, index) {
                        final shop = _allShops[index];
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
                                _referencePhotoUrls.remove(shop.address);
                              }
                            });
                          },
                          controlAffinity: ListTileControlAffinity.leading,
                        );
                      },
                    ),
                  ),
                ],
                // Эталонные фото (только для вопросов с фото)
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
                  if (_isForAllShops)
                    // Если для всех магазинов, показываем возможность добавить фото для каждого
                    ..._allShops.map((shop) => _buildReferencePhotoSection(shop.address, shop.name))
                  else
                    // Если выбраны конкретные магазины, показываем только для них
                    ..._selectedShopAddresses.map((address) {
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
                    }),
                ],
              ],
              ],
            ),
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
                     _referencePhotoFiles.containsKey(shopAddress);
    final photoFile = _referencePhotoFiles[shopAddress];
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
              // Превью фото
              Container(
                height: 100,
                width: double.infinity,
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: photoFile != null
                      ? kIsWeb
                          ? Image.network(
                              photoFile.path,
                              fit: BoxFit.cover,
                              errorBuilder: (context, error, stackTrace) {
                                return const Center(child: Icon(Icons.error));
                              },
                            )
                          : Image.file(
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

