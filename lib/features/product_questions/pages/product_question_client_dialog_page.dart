import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';
import 'dart:io';
import 'package:image_picker/image_picker.dart';
import '../models/product_question_message_model.dart';
import '../services/product_question_service.dart';
import 'product_question_personal_dialog_page.dart';
import 'product_question_dialog_page.dart';

/// Страница чата клиента по поиску товара (единый чат со всеми магазинами)
class ProductQuestionClientDialogPage extends StatefulWidget {
  const ProductQuestionClientDialogPage({super.key});

  @override
  State<ProductQuestionClientDialogPage> createState() => _ProductQuestionClientDialogPageState();
}

class _ProductQuestionClientDialogPageState extends State<ProductQuestionClientDialogPage> {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final ImagePicker _imagePicker = ImagePicker();

  List<ProductQuestionMessage> _messages = [];
  Set<String> _existingDialogShops = {}; // Магазины, с которыми уже есть персональные диалоги
  bool _isLoading = true;
  bool _isSending = false;
  bool _isCreatingDialog = false;
  File? _selectedImage;
  String? _clientPhone;
  String? _clientName;
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _loadData();
    // Автообновление каждые 5 секунд
    _refreshTimer = Timer.periodic(const Duration(seconds: 5), (_) => _loadMessages());
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
    _clientPhone = prefs.getString('user_phone') ?? '';
    _clientName = prefs.getString('user_name') ?? 'Клиент';

    if (_clientPhone!.isEmpty) {
      setState(() {
        _isLoading = false;
      });
      return;
    }

    // Загружаем существующие персональные диалоги
    await _loadExistingDialogs();
    await _loadMessages();

    // Помечаем все сообщения как прочитанные
    _markAllAsRead();
  }

  Future<void> _loadExistingDialogs() async {
    if (_clientPhone == null || _clientPhone!.isEmpty) return;

    try {
      final dialogs = await ProductQuestionService.getClientPersonalDialogs(_clientPhone!);
      setState(() {
        _existingDialogShops = dialogs.map((d) => d.shopAddress).toSet();
      });
    } catch (e) {
      // Игнорируем ошибки
    }
  }

  Future<void> _loadMessages() async {
    if (_clientPhone == null || _clientPhone!.isEmpty) return;

    try {
      final data = await ProductQuestionService.getClientDialog(_clientPhone!);

      if (data != null && mounted) {
        setState(() {
          _messages = data.messages;
          _isLoading = false;
        });

        // Прокрутка вниз при загрузке
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
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _markAllAsRead() async {
    if (_clientPhone == null || _clientPhone!.isEmpty) return;

    try {
      await ProductQuestionService.markAllClientQuestionsAsRead(_clientPhone!);
    } catch (e) {
      // Игнорируем ошибки
    }
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
    if (_isSending || _clientPhone == null) return;

    setState(() {
      _isSending = true;
    });

    try {
      String? photoUrl;
      if (_selectedImage != null) {
        photoUrl = await ProductQuestionService.uploadPhoto(_selectedImage!.path);
      }

      final result = await ProductQuestionService.sendClientReply(
        clientPhone: _clientPhone!,
        text: text.isEmpty ? 'Фото' : text,
        imageUrl: photoUrl,
      );

      if (result != null && mounted) {
        _messageController.clear();
        setState(() {
          _selectedImage = null;
        });
        await _loadMessages();
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

  /// Открыть диалог с магазином
  Future<void> _openShopDialog(String shopAddress, String? questionId) async {
    if (questionId == null) {
      // Если questionId нет - создаем персональный диалог
      await _startPersonalDialog(shopAddress);
      return;
    }

    // Открываем существующий диалог с магазином
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ProductQuestionDialogPage(
          questionId: questionId,
        ),
      ),
    );

    // Обновить данные после возврата
    _loadMessages();
  }

  /// Создать персональный диалог с магазином
  Future<void> _startPersonalDialog(String shopAddress) async {
    if (_isCreatingDialog || _clientPhone == null) return;

    setState(() {
      _isCreatingDialog = true;
    });

    try {
      final dialog = await ProductQuestionService.createPersonalDialog(
        clientPhone: _clientPhone!,
        clientName: _clientName ?? 'Клиент',
        shopAddress: shopAddress,
      );

      if (dialog != null && mounted) {
        // Обновляем список существующих диалогов
        setState(() {
          _existingDialogShops.add(shopAddress);
        });

        // Переходим на страницу персонального диалога
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => ProductQuestionPersonalDialogPage(
              dialogId: dialog.id,
              shopAddress: shopAddress,
            ),
          ),
        );
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Не удалось создать диалог'),
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
          _isCreatingDialog = false;
        });
      }
    }
  }

  Widget _buildMessage(ProductQuestionMessage message) {
    final isClientMessage = message.senderType == 'client';
    final shopAddress = message.shopAddress;
    final hasExistingDialog = shopAddress != null && _existingDialogShops.contains(shopAddress);

    return Column(
      crossAxisAlignment: isClientMessage ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        Align(
          alignment: isClientMessage ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
            padding: const EdgeInsets.all(12),
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.75,
            ),
            decoration: BoxDecoration(
              color: isClientMessage ? const Color(0xFF004D40) : Colors.grey[200],
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Для сообщений сотрудников показываем магазин и имя
                if (!isClientMessage) ...[
                  Text(
                    '${message.shopAddress ?? "Магазин"} - ${message.senderName ?? "Сотрудник"}',
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
                      message.imageUrl!.startsWith('http')
                          ? message.imageUrl!
                          : 'https://arabica26.ru${message.imageUrl}',
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
                    color: isClientMessage ? Colors.white : Colors.black87,
                  ),
                ),
                const SizedBox(height: 4),
                // Время
                Text(
                  _formatTimestamp(message.timestamp),
                  style: TextStyle(
                    fontSize: 10,
                    color: isClientMessage ? Colors.white70 : Colors.grey,
                  ),
                ),
              ],
            ),
          ),
        ),
        // Кнопка "Написать в магазин" под ответами сотрудников
        if (!isClientMessage && shopAddress != null) ...[
          Padding(
            padding: const EdgeInsets.only(left: 8, right: 8, bottom: 8),
            child: ElevatedButton.icon(
              onPressed: () => _openShopDialog(shopAddress, message.questionId),
              icon: const Icon(Icons.store, size: 16),
              label: const Text('Написать в магазин'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF004D40),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                textStyle: const TextStyle(fontSize: 12),
              ),
            ),
          ),
        ],
        // Показываем "Диалог создан" если уже есть
        if (!isClientMessage && shopAddress != null && hasExistingDialog) ...[
          Padding(
            padding: const EdgeInsets.only(left: 8, right: 8, bottom: 8),
            child: Text(
              'Диалог создан',
              style: TextStyle(
                fontSize: 11,
                color: Colors.grey[600],
                fontStyle: FontStyle.italic,
              ),
            ),
          ),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Поиск Товара'),
        backgroundColor: const Color(0xFF004D40),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadMessages,
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
                : _messages.isEmpty
                    ? const Center(
                        child: Text(
                          'Нет сообщений',
                          style: TextStyle(color: Colors.grey),
                        ),
                      )
                    : ListView.builder(
                        controller: _scrollController,
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        itemCount: _messages.length,
                        itemBuilder: (context, index) {
                          return _buildMessage(_messages[index]);
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
