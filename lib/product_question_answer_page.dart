import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:io';
import 'package:image_picker/image_picker.dart';
import 'product_question_model.dart';
import 'product_question_service.dart';
import 'shop_model.dart';

class ProductQuestionAnswerPage extends StatefulWidget {
  final String questionId;

  const ProductQuestionAnswerPage({
    super.key,
    required this.questionId,
  });

  @override
  State<ProductQuestionAnswerPage> createState() => _ProductQuestionAnswerPageState();
}

class _ProductQuestionAnswerPageState extends State<ProductQuestionAnswerPage> {
  ProductQuestion? _question;
  List<Shop> _shops = [];
  String? _selectedShopAddress;
  final TextEditingController _answerController = TextEditingController();
  final ImagePicker _imagePicker = ImagePicker();
  File? _selectedImage;
  bool _isLoading = true;
  bool _isSending = false;
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _answerController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final shops = await Shop.loadShopsFromServer();
      final question = await ProductQuestionService.getQuestion(widget.questionId);
      
      setState(() {
        _shops = shops;
        _question = question;
        _isLoading = false;
      });
      
      // Прокручиваем вниз после загрузки
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          0,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
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

  Future<void> _sendAnswer() async {
    if (_selectedShopAddress == null || _selectedShopAddress!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Выберите магазин, от имени которого отвечаете'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    if (_answerController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Введите ответ'),
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
      final senderPhone = prefs.getString('user_phone') ?? '';

      // Загружаем фото, если есть
      String? photoUrl;
      if (_selectedImage != null) {
        photoUrl = await ProductQuestionService.uploadPhoto(_selectedImage!.path);
        if (photoUrl == null) {
          throw Exception('Ошибка загрузки фото');
        }
      }

      // Отправляем ответ
      final message = await ProductQuestionService.answerQuestion(
        questionId: widget.questionId,
        shopAddress: _selectedShopAddress!,
        text: _answerController.text.trim(),
        senderPhone: senderPhone.isNotEmpty ? senderPhone : null,
        imageUrl: photoUrl,
      );

      if (message != null && mounted) {
        Navigator.pop(context, true); // Возвращаемся назад с результатом
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Ответ отправлен!'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 2),
          ),
        );
      } else {
        throw Exception('Не удалось отправить ответ');
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

  String _formatTimestamp(String timestamp) {
    try {
      final date = DateTime.parse(timestamp);
      final now = DateTime.now();
      final difference = now.difference(date);

      if (difference.inDays == 0) {
        return '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
      } else if (difference.inDays == 1) {
        return 'Вчера ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
      } else {
        return '${date.day}.${date.month}.${date.year} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
      }
    } catch (e) {
      return timestamp;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Ответ на вопрос'),
        backgroundColor: const Color(0xFF004D40),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadData,
            tooltip: 'Обновить',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _question == null
              ? const Center(
                  child: Text(
                    'Вопрос не найден',
                    style: TextStyle(color: Colors.grey),
                  ),
                )
              : Column(
                  children: [
                    // Выбор магазина (обязательное поле)
                    Container(
                      padding: const EdgeInsets.all(16),
                      color: Colors.orange[50],
                      child: DropdownButtonFormField<String>(
                        value: _selectedShopAddress,
                        decoration: InputDecoration(
                          labelText: 'Магазин *',
                          hintText: 'Выберите магазин',
                          border: const OutlineInputBorder(),
                          errorText: _selectedShopAddress == null ? 'Обязательное поле' : null,
                        ),
                        items: _shops.map((shop) => DropdownMenuItem<String>(
                          value: shop.address,
                          child: Text(shop.address),
                        )).toList(),
                        onChanged: (value) {
                          setState(() {
                            _selectedShopAddress = value;
                          });
                        },
                      ),
                    ),
                    // История диалога
                    Expanded(
                      child: ListView.builder(
                        controller: _scrollController,
                        reverse: true,
                        padding: const EdgeInsets.all(16),
                        itemCount: _question!.messages.length,
                        itemBuilder: (context, index) {
                          final message = _question!.messages[_question!.messages.length - 1 - index];
                          final isFromClient = message.senderType == 'client';
                          
                          return Align(
                            alignment: isFromClient 
                                ? Alignment.centerLeft 
                                : Alignment.centerRight,
                            child: Container(
                              margin: const EdgeInsets.only(bottom: 8),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 8,
                              ),
                              decoration: BoxDecoration(
                                color: isFromClient 
                                    ? Colors.grey[300]
                                    : const Color(0xFF004D40),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              constraints: BoxConstraints(
                                maxWidth: MediaQuery.of(context).size.width * 0.7,
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if (!isFromClient) ...[
                                    Text(
                                      'Ответ от магазина ${message.shopAddress}',
                                      style: const TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.white70,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                  ],
                                  Text(
                                    message.text,
                                    style: TextStyle(
                                      color: isFromClient ? Colors.black87 : Colors.white,
                                    ),
                                  ),
                                  if (message.imageUrl != null) ...[
                                    const SizedBox(height: 8),
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(8),
                                      child: Image.network(
                                        message.imageUrl!,
                                        width: double.infinity,
                                        fit: BoxFit.cover,
                                      ),
                                    ),
                                  ],
                                  const SizedBox(height: 4),
                                  Text(
                                    _formatTimestamp(message.timestamp),
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: isFromClient 
                                          ? Colors.black54 
                                          : Colors.white70,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    // Поле ввода ответа
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.grey[100],
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.1),
                            blurRadius: 4,
                            offset: const Offset(0, -2),
                          ),
                        ],
                      ),
                      child: Column(
                        children: [
                          // Превью фото
                          if (_selectedImage != null) ...[
                            Stack(
                              children: [
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child: Image.file(
                                    _selectedImage!,
                                    width: double.infinity,
                                    height: 150,
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
                            const SizedBox(height: 8),
                          ],
                          Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: _answerController,
                                  decoration: const InputDecoration(
                                    hintText: 'Введите ответ...',
                                    border: OutlineInputBorder(),
                                    contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                  ),
                                  maxLines: null,
                                  textInputAction: TextInputAction.send,
                                  onSubmitted: (_) => _sendAnswer(),
                                ),
                              ),
                              const SizedBox(width: 8),
                              IconButton(
                                icon: const Icon(Icons.photo),
                                onPressed: _isSending ? null : _showImageSourceDialog,
                                tooltip: 'Прикрепить фото',
                              ),
                              IconButton(
                                icon: _isSending
                                    ? const SizedBox(
                                        width: 20,
                                        height: 20,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF004D40)),
                                        ),
                                      )
                                    : const Icon(Icons.send, color: Color(0xFF004D40)),
                                onPressed: _isSending ? null : _sendAnswer,
                                tooltip: 'Отправить',
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
    );
  }
}



