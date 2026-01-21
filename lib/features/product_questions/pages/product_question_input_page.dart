import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:io';
import 'package:image_picker/image_picker.dart';
import '../services/product_question_service.dart';

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
  final FocusNode _focusNode = FocusNode();
  File? _selectedImage;
  bool _isSending = false;

  // Цвета
  static const _primaryColor = Color(0xFF004D40);

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
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        margin: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Добавить фото',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            ListTile(
              leading: Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: _primaryColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.photo_library, color: _primaryColor),
              ),
              title: const Text('Выбрать из галереи'),
              subtitle: Text(
                'Выберите готовое фото',
                style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
              ),
              onTap: () => Navigator.pop(context, ImageSource.gallery),
            ),
            ListTile(
              leading: Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: _primaryColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.camera_alt, color: _primaryColor),
              ),
              title: const Text('Сделать фото'),
              subtitle: Text(
                'Сфотографируйте товар',
                style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
              ),
              onTap: () => Navigator.pop(context, ImageSource.camera),
            ),
            const SizedBox(height: 16),
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
            content: Text('Вопрос отправлен! Ответ придёт в "Мои диалоги"'),
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
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('Вопрос о товаре'),
        backgroundColor: _primaryColor,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Карточка магазина
            _buildShopCard(),
            const SizedBox(height: 20),

            // Поле ввода вопроса
            _buildQuestionInput(),
            const SizedBox(height: 16),

            // Превью фото
            if (_selectedImage != null) ...[
              _buildImagePreview(),
              const SizedBox(height: 16),
            ],

            // Кнопки действий
            _buildActionButtons(),

            const SizedBox(height: 24),

            // Подсказка
            _buildHint(),
          ],
        ),
      ),
    );
  }

  Widget _buildShopCard() {
    final isAllNetwork = widget.shopAddress == 'Вся сеть';

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isAllNetwork
              ? [const Color(0xFF004D40), const Color(0xFF00796B)]
              : [Colors.grey.shade100, Colors.grey.shade50],
        ),
        borderRadius: BorderRadius.circular(16),
        border: isAllNetwork
            ? null
            : Border.all(color: Colors.grey.shade300),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: isAllNetwork
                    ? Colors.white.withOpacity(0.2)
                    : _primaryColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                isAllNetwork ? Icons.store_mall_directory : Icons.store,
                color: isAllNetwork ? Colors.white : _primaryColor,
                size: 24,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    isAllNetwork ? 'Вся сеть магазинов' : 'Магазин',
                    style: TextStyle(
                      color: isAllNetwork ? Colors.white70 : Colors.grey.shade600,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    isAllNetwork ? 'Вопрос получат все' : widget.shopAddress,
                    style: TextStyle(
                      color: isAllNetwork ? Colors.white : const Color(0xFF1A1A1A),
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuestionInput() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: TextField(
        controller: _questionController,
        focusNode: _focusNode,
        decoration: InputDecoration(
          hintText: 'Опишите товар, который вы ищете...',
          hintStyle: TextStyle(color: Colors.grey.shade400),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.all(16),
          prefixIcon: Padding(
            padding: const EdgeInsets.only(left: 12, right: 8),
            child: Icon(
              Icons.edit_note,
              color: _primaryColor.withOpacity(0.5),
              size: 24,
            ),
          ),
        ),
        maxLines: 5,
        minLines: 3,
        textCapitalization: TextCapitalization.sentences,
      ),
    );
  }

  Widget _buildImagePreview() {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Stack(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Image.file(
              _selectedImage!,
              width: double.infinity,
              height: 200,
              fit: BoxFit.cover,
            ),
          ),
          // Затемнение сверху
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Container(
              height: 60,
              decoration: BoxDecoration(
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(16),
                  topRight: Radius.circular(16),
                ),
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withOpacity(0.4),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
          // Кнопка удаления
          Positioned(
            top: 8,
            right: 8,
            child: GestureDetector(
              onTap: () {
                setState(() {
                  _selectedImage = null;
                });
              },
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.5),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.close,
                  color: Colors.white,
                  size: 20,
                ),
              ),
            ),
          ),
          // Метка "Фото товара"
          Positioned(
            top: 12,
            left: 12,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.5),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.photo, color: Colors.white, size: 14),
                  SizedBox(width: 4),
                  Text(
                    'Фото товара',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButtons() {
    return Row(
      children: [
        // Кнопка прикрепить фото
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border.all(color: _primaryColor, width: 2),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: _isSending ? null : _showImageSourceDialog,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        _selectedImage != null ? Icons.photo : Icons.add_photo_alternate,
                        color: _primaryColor,
                        size: 20,
                      ),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          _selectedImage != null ? 'Изменить' : 'Фото',
                          style: TextStyle(
                            color: _primaryColor,
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        // Кнопка отправить
        Expanded(
          flex: 2,
          child: Container(
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF004D40), Color(0xFF00796B)],
              ),
              borderRadius: BorderRadius.circular(14),
              boxShadow: [
                BoxShadow(
                  color: _primaryColor.withOpacity(0.3),
                  blurRadius: 8,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: _isSending ? null : _sendQuestion,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (_isSending)
                        const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        )
                      else ...[
                        const Icon(Icons.send, color: Colors.white, size: 18),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            'Отправить',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildHint() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.blue.shade50,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.blue.shade100),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.lightbulb_outline,
            color: Colors.blue.shade600,
            size: 22,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Совет',
                  style: TextStyle(
                    color: Colors.blue.shade800,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Добавьте фото товара для более точного ответа. Ответ придёт в раздел "Мои диалоги".',
                  style: TextStyle(
                    color: Colors.blue.shade700,
                    fontSize: 13,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
