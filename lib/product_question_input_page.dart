import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:io';
import 'package:image_picker/image_picker.dart';
import 'product_question_service.dart';

class ProductQuestionInputPage extends StatefulWidget {
  final String shopAddress;

  const ProductQuestionInputPage({
    super.key,
    required this.shopAddress,
  });

  @override
  State<ProductQuestionInputPage> createState() => _ProductQuestionInputPageState();
}

class _ProductQuestionInputPageState extends State<ProductQuestionInputPage> {
  final TextEditingController _questionController = TextEditingController();
  final ImagePicker _imagePicker = ImagePicker();
  File? _selectedImage;
  bool _isSending = false;

  Future<void> _pickImage() async {
    try {
      final XFile? image = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1920,
        maxHeight: 1920,
        imageQuality: 85,
      );
      
      if (image != null) {
        setState(() {
          _selectedImage = File(image.path);
        });
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

  Future<void> _takePhoto() async {
    try {
      final XFile? image = await _imagePicker.pickImage(
        source: ImageSource.camera,
        maxWidth: 1920,
        maxHeight: 1920,
        imageQuality: 85,
      );
      
      if (image != null) {
        setState(() {
          _selectedImage = File(image.path);
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка съемки фото: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _showImageSourceDialog() async {
    final source = await showDialog<ImageSource>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Выберите источник'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('Галерея'),
              onTap: () => Navigator.pop(context, ImageSource.gallery),
            ),
            ListTile(
              leading: const Icon(Icons.camera_alt),
              title: const Text('Камера'),
              onTap: () => Navigator.pop(context, ImageSource.camera),
            ),
          ],
        ),
      ),
    );

    if (source != null) {
      if (source == ImageSource.gallery) {
        await _pickImage();
      } else {
        await _takePhoto();
      }
    }
  }

  Future<void> _sendQuestion() async {
    if (_questionController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Введите вопрос'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    if (_isSending) return;

    setState(() {
      _isSending = true;
    });

    try {
      final prefs = await SharedPreferences.getInstance();
      final clientPhone = prefs.getString('user_phone') ?? '';
      final clientName = prefs.getString('user_name') ?? 'Клиент';

      if (clientPhone.isEmpty) {
        throw Exception('Не удалось определить телефон клиента');
      }

      // Загружаем фото, если есть
      String? photoUrl;
      if (_selectedImage != null) {
        photoUrl = await ProductQuestionService.uploadPhoto(_selectedImage!.path);
        if (photoUrl == null) {
          throw Exception('Ошибка загрузки фото');
        }
      }

      // Создаем вопрос
      final questionId = await ProductQuestionService.createQuestion(
        clientPhone: clientPhone,
        clientName: clientName,
        shopAddress: widget.shopAddress,
        questionText: _questionController.text.trim(),
        questionImageUrl: photoUrl,
      );

      if (questionId != null && mounted) {
        Navigator.pop(context, true); // Возвращаемся назад с результатом
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Вопрос отправлен! Вы получите ответ в разделе "Мои диалоги"'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 3),
          ),
        );
      } else {
        throw Exception('Не удалось отправить вопрос');
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
          _isSending = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _questionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Вопрос о товаре'),
        backgroundColor: const Color(0xFF004D40),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Card(
              color: const Color(0xFF004D40),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  'Магазин: ${widget.shopAddress}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _questionController,
              decoration: const InputDecoration(
                labelText: 'Ваш вопрос о товаре',
                hintText: 'Опишите товар, который вы ищете...',
                border: OutlineInputBorder(),
              ),
              maxLines: 6,
            ),
            const SizedBox(height: 16),
            // Превью фото
            if (_selectedImage != null) ...[
              Stack(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.file(
                      _selectedImage!,
                      width: double.infinity,
                      height: 200,
                      fit: BoxFit.cover,
                    ),
                  ),
                  Positioned(
                    top: 8,
                    right: 8,
                    child: IconButton(
                      icon: const Icon(Icons.close, color: Colors.white),
                      style: IconButton.styleFrom(
                        backgroundColor: Colors.black54,
                      ),
                      onPressed: () {
                        setState(() {
                          _selectedImage = null;
                        });
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
            ],
            // Кнопки действий
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _isSending ? null : _showImageSourceDialog,
                    icon: const Icon(Icons.photo),
                    label: const Text('Прикрепить фото'),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  flex: 2,
                  child: ElevatedButton(
                    onPressed: _isSending ? null : _sendQuestion,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF004D40),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                    child: _isSending
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                            ),
                          )
                        : const Text('Отправить'),
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


