import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';
import 'dart:io';
import 'package:image_picker/image_picker.dart';
import '../models/product_question_model.dart';
import '../models/product_question_message_model.dart';
import '../services/product_question_service.dart';

/// Страница персонального чата для сотрудника с клиентом
class ProductQuestionEmployeeDialogPage extends StatefulWidget {
  final String dialogId;
  final String shopAddress;
  final String clientName;

  const ProductQuestionEmployeeDialogPage({
    super.key,
    required this.dialogId,
    required this.shopAddress,
    required this.clientName,
  });

  @override
  State<ProductQuestionEmployeeDialogPage> createState() => _ProductQuestionEmployeeDialogPageState();
}

class _ProductQuestionEmployeeDialogPageState extends State<ProductQuestionEmployeeDialogPage> {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final ImagePicker _imagePicker = ImagePicker();

  PersonalProductDialog? _dialog;
  bool _isLoading = true;
  bool _isSending = false;
  File? _selectedImage;
  String? _employeePhone;
  String? _employeeName;
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _loadData();
    // Автообновление каждые 5 секунд
    _refreshTimer = Timer.periodic(const Duration(seconds: 5), (_) => _refreshDialog());
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    final prefs = await SharedPreferences.getInstance();
    _employeePhone = prefs.getString('user_phone') ?? '';
    _employeeName = prefs.getString('user_name') ?? 'Сотрудник';

    await _loadDialog();

    // Отмечаем как прочитанный для сотрудника
    await ProductQuestionService.markPersonalDialogRead(
      dialogId: widget.dialogId,
      readerType: 'employee',
    );
  }

  Future<void> _loadDialog() async {
    try {
      final dialog = await ProductQuestionService.getPersonalDialog(widget.dialogId);

      if (dialog != null && mounted) {
        setState(() {
          _dialog = dialog;
          _isLoading = false;
        });

        // Прокрутка вниз при загрузке
        _scrollToBottom();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _refreshDialog() async {
    if (_isSending) return;

    try {
      final dialog = await ProductQuestionService.getPersonalDialog(widget.dialogId);

      if (dialog != null && mounted) {
        final hadNewMessages = _dialog != null && dialog.messages.length > _dialog!.messages.length;

        setState(() {
          _dialog = dialog;
        });

        if (hadNewMessages) {
          _scrollToBottom();
          // Отмечаем как прочитанный
          await ProductQuestionService.markPersonalDialogRead(
            dialogId: widget.dialogId,
            readerType: 'employee',
          );
        }
      }
    } catch (e) {
      // Игнорируем ошибки автообновления
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _pickImage() async {
    try {
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
        final XFile? image = await _imagePicker.pickImage(
          source: source,
          maxWidth: 1920,
          maxHeight: 1920,
          imageQuality: 85,
        );

        if (image != null) {
          setState(() {
            _selectedImage = File(image.path);
          });
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

  Future<void> _sendMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty && _selectedImage == null) return;
    if (_isSending || _employeePhone == null) return;

    setState(() {
      _isSending = true;
    });

    try {
      String? photoUrl;
      if (_selectedImage != null) {
        photoUrl = await ProductQuestionService.uploadPhoto(_selectedImage!.path);
      }

      final result = await ProductQuestionService.sendPersonalDialogMessage(
        dialogId: widget.dialogId,
        senderType: 'employee',
        text: text.isEmpty ? 'Фото' : text,
        senderPhone: _employeePhone,
        senderName: _employeeName,
        imageUrl: photoUrl,
      );

      if (result != null && mounted) {
        _messageController.clear();
        setState(() {
          _selectedImage = null;
        });
        await _loadDialog();
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Не удалось отправить сообщение'),
            backgroundColor: Colors.red,
          ),
        );
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

  Widget _buildMessage(ProductQuestionMessage message) {
    // Для сотрудника: сообщения клиента слева, сотрудника справа
    final isEmployeeMessage = message.senderType == 'employee';

    return Align(
      alignment: isEmployeeMessage ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
        padding: const EdgeInsets.all(12),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.75,
        ),
        decoration: BoxDecoration(
          color: isEmployeeMessage ? const Color(0xFF004D40) : Colors.grey[200],
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Для сообщений клиента показываем имя
            if (!isEmployeeMessage) ...[
              Text(
                widget.clientName,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey[700],
                ),
              ),
              const SizedBox(height: 4),
            ],
            // Фото
            if (message.imageUrl != null && message.imageUrl!.isNotEmpty) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.network(
                  message.imageUrl!,
                  width: double.infinity,
                  fit: BoxFit.cover,
                  loadingBuilder: (context, child, loadingProgress) {
                    if (loadingProgress == null) return child;
                    return Container(
                      height: 150,
                      color: Colors.grey[300],
                      child: const Center(child: CircularProgressIndicator()),
                    );
                  },
                  errorBuilder: (context, error, stackTrace) {
                    return Container(
                      height: 100,
                      color: Colors.grey[300],
                      child: const Icon(Icons.broken_image, color: Colors.grey),
                    );
                  },
                ),
              ),
              const SizedBox(height: 8),
            ],
            // Текст
            Text(
              message.text,
              style: TextStyle(
                color: isEmployeeMessage ? Colors.white : Colors.black87,
              ),
            ),
            const SizedBox(height: 4),
            // Время
            Text(
              _formatTimestamp(message.timestamp),
              style: TextStyle(
                fontSize: 10,
                color: isEmployeeMessage ? Colors.white70 : Colors.grey,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.clientName, style: const TextStyle(fontSize: 16)),
            Text(
              widget.shopAddress,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.normal),
            ),
          ],
        ),
        backgroundColor: const Color(0xFF004D40),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadDialog,
            tooltip: 'Обновить',
          ),
        ],
      ),
      body: Column(
        children: [
          // Список сообщений
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _dialog == null || _dialog!.messages.isEmpty
                    ? const Center(
                        child: Text(
                          'Нет сообщений',
                          style: TextStyle(color: Colors.grey),
                        ),
                      )
                    : ListView.builder(
                        controller: _scrollController,
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        itemCount: _dialog!.messages.length,
                        itemBuilder: (context, index) {
                          return _buildMessage(_dialog!.messages[index]);
                        },
                      ),
          ),
          // Превью выбранного фото
          if (_selectedImage != null)
            Container(
              height: 100,
              padding: const EdgeInsets.all(8),
              child: Stack(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.file(
                      _selectedImage!,
                      height: 84,
                      fit: BoxFit.cover,
                    ),
                  ),
                  Positioned(
                    top: 0,
                    right: 0,
                    child: IconButton(
                      icon: const Icon(Icons.close, color: Colors.red),
                      onPressed: () {
                        setState(() {
                          _selectedImage = null;
                        });
                      },
                    ),
                  ),
                ],
              ),
            ),
          // Поле ввода
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.grey.withOpacity(0.2),
                  blurRadius: 4,
                  offset: const Offset(0, -2),
                ),
              ],
            ),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.photo),
                  color: const Color(0xFF004D40),
                  onPressed: _isSending ? null : _pickImage,
                ),
                Expanded(
                  child: TextField(
                    controller: _messageController,
                    decoration: const InputDecoration(
                      hintText: 'Написать сообщение...',
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                    maxLines: null,
                    enabled: !_isSending,
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: _isSending
                      ? const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.send),
                  color: const Color(0xFF004D40),
                  onPressed: _isSending ? null : _sendMessage,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
