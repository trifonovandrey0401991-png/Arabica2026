import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';
import '../models/product_question_model.dart';
import '../models/product_question_message_model.dart';
import '../services/product_question_service.dart';
import '../../../shared/widgets/app_cached_image.dart';
import 'product_question_personal_dialog_page.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

class ProductQuestionDialogPage extends StatefulWidget {
  final String questionId;
  const ProductQuestionDialogPage({
    super.key,
    required this.questionId,
  });

  @override
  State<ProductQuestionDialogPage> createState() => _ProductQuestionDialogPageState();
}

class _ProductQuestionDialogPageState extends State<ProductQuestionDialogPage> {
  // Dark emerald + gold palette
  static const Color _emerald = Color(0xFF1A4D4D);
  static const Color _emeraldDark = Color(0xFF0D2E2E);
  static const Color _night = Color(0xFF051515);
  static const Color _gold = Color(0xFFD4AF37);

  ProductQuestion? _question;
  bool _isLoading = true;
  bool _isSending = false;
  bool _isCreatingDialog = false;
  String? _clientPhone;
  String? _clientName;
  String? _lastMessageTimestamp; // Для инкрементальной загрузки
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _messageController = TextEditingController();
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _loadClientInfo();
    _loadQuestion();
    _markAsRead();
    _refreshTimer = Timer.periodic(Duration(seconds: 5), (_) => _refreshMessages());
  }

  Future<void> _loadClientInfo() async {
    final prefs = await SharedPreferences.getInstance();
    _clientPhone = prefs.getString('user_phone') ?? '';
    _clientName = prefs.getString('user_name') ?? 'Клиент';
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadQuestion() async {
    try {
      final question = await ProductQuestionService.getQuestion(widget.questionId);
      if (mounted && question != null) {
        _updateLastTimestamp(question.messages);
        setState(() {
          _question = question;
          _isLoading = false;
        });
        _scrollToBottom();
      } else if (mounted) {
        setState(() => _isLoading = false);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  /// Инкрементальный refresh — загружает только новые сообщения
  Future<void> _refreshMessages() async {
    if (_question == null || _lastMessageTimestamp == null) {
      return _loadQuestion();
    }
    try {
      final updated = await ProductQuestionService.getQuestion(
        widget.questionId,
        since: _lastMessageTimestamp,
      );
      if (mounted && updated != null && updated.messages.isNotEmpty) {
        _updateLastTimestamp(updated.messages);
        setState(() {
          _question = ProductQuestion(
            id: _question!.id,
            clientPhone: _question!.clientPhone,
            clientName: _question!.clientName,
            shopAddress: updated.shopAddress.isNotEmpty ? updated.shopAddress : _question!.shopAddress,
            shopName: updated.shopName ?? _question!.shopName,
            questionText: _question!.questionText,
            questionImageUrl: _question!.questionImageUrl,
            timestamp: _question!.timestamp,
            isAnswered: updated.isAnswered,
            answeredBy: updated.answeredBy ?? _question!.answeredBy,
            answeredByName: updated.answeredByName ?? _question!.answeredByName,
            lastAnswerTime: updated.lastAnswerTime ?? _question!.lastAnswerTime,
            isNetworkWide: _question!.isNetworkWide,
            hasUnreadFromClient: updated.hasUnreadFromClient,
            messages: [..._question!.messages, ...updated.messages],
            rawShops: updated.rawShops.isNotEmpty ? updated.rawShops : _question!.rawShops,
          );
        });
        _markAsRead();
        _scrollToBottom();
      }
    } catch (e) {
      // Тихо игнорируем ошибки инкрементального refresh
    }
  }

  void _updateLastTimestamp(List<ProductQuestionMessage> messages) {
    if (messages.isNotEmpty) {
      _lastMessageTimestamp = messages.last.timestamp;
    }
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        0,
        duration: Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
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

  Future<void> _markAsRead() async {
    try {
      await ProductQuestionService.markQuestionAsRead(
        questionId: widget.questionId,
        readerType: 'client',
      );
    } catch (e) {
      // Игнорируем ошибки
    }
  }

  Future<void> _sendMessage() async {
    if (_messageController.text.trim().isEmpty || _isSending) return;

    setState(() {
      _isSending = true;
    });

    try {
      final prefs = await SharedPreferences.getInstance();
      final clientPhone = prefs.getString('user_phone') ?? '';

      if (clientPhone.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Ошибка: телефон не найден'), backgroundColor: Colors.red),
          );
        }
        return;
      }

      final text = _messageController.text.trim();
      final result = await ProductQuestionService.sendClientReply(
        clientPhone: clientPhone,
        text: text,
        questionId: widget.questionId,
      );

      if (result != null && mounted) {
        _messageController.clear();
        // Оптимистичное добавление — сразу показываем сообщение
        _updateLastTimestamp([result]);
        setState(() {
          _question = ProductQuestion(
            id: _question!.id,
            clientPhone: _question!.clientPhone,
            clientName: _question!.clientName,
            shopAddress: _question!.shopAddress,
            shopName: _question!.shopName,
            questionText: _question!.questionText,
            questionImageUrl: _question!.questionImageUrl,
            timestamp: _question!.timestamp,
            isAnswered: _question!.isAnswered,
            answeredBy: _question!.answeredBy,
            answeredByName: _question!.answeredByName,
            lastAnswerTime: _question!.lastAnswerTime,
            isNetworkWide: _question!.isNetworkWide,
            hasUnreadFromClient: _question!.hasUnreadFromClient,
            messages: [..._question!.messages, result],
            rawShops: _question!.rawShops,
          );
        });
        _scrollToBottom();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка отправки: $e'), backgroundColor: Colors.red),
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

  Future<void> _openShopDialog(String shopAddress) async {
    if (_clientPhone == null || _clientPhone!.isEmpty || _isCreatingDialog) return;

    try {
      final dialogs = await ProductQuestionService.getClientPersonalDialogs(_clientPhone!);
      final existingDialog = dialogs.where((d) => d.shopAddress == shopAddress).firstOrNull;

      if (existingDialog != null) {
        if (mounted) {
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => ProductQuestionPersonalDialogPage(
                dialogId: existingDialog.id,
                shopAddress: shopAddress,
              ),
            ),
          );
          _loadQuestion();
        }
      } else {
        setState(() => _isCreatingDialog = true);
        try {
          final dialog = await ProductQuestionService.createPersonalDialog(
            clientPhone: _clientPhone!,
            clientName: _clientName ?? _question?.clientName ?? 'Клиент',
            shopAddress: shopAddress,
          );
          if (dialog != null && mounted) {
            await Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => ProductQuestionPersonalDialogPage(
                  dialogId: dialog.id,
                  shopAddress: shopAddress,
                ),
              ),
            );
            _loadQuestion();
          }
        } finally {
          if (mounted) setState(() => _isCreatingDialog = false);
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Widget _buildMessageBubble(ProductQuestionMessage message) {
    final isFromClient = message.senderType == 'client';
    final shopAddress = message.shopAddress;

    return Column(
      crossAxisAlignment: isFromClient ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.symmetric(vertical: 4.h),
          child: Row(
            mainAxisAlignment: isFromClient ? MainAxisAlignment.end : MainAxisAlignment.start,
            children: [
              if (isFromClient) Spacer(flex: 1),
              Flexible(
                flex: 4,
                child: Container(
                  padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 10.h),
                  decoration: BoxDecoration(
                    gradient: isFromClient
                        ? LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [_emerald, _emeraldDark],
                          )
                        : null,
                    color: isFromClient ? null : Colors.white.withOpacity(0.08),
                    borderRadius: BorderRadius.only(
                      topLeft: Radius.circular(18.r),
                      topRight: Radius.circular(18.r),
                      bottomLeft: isFromClient ? Radius.circular(18.r) : Radius.circular(4.r),
                      bottomRight: isFromClient ? Radius.circular(4.r) : Radius.circular(18.r),
                    ),
                    border: Border.all(
                      color: _gold.withOpacity(0.5),
                      width: 1.0,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (!isFromClient) ...[
                        Text(
                          'Ответ от магазина ${shopAddress ?? ""}',
                          style: TextStyle(
                            fontSize: 11.sp,
                            fontWeight: FontWeight.w600,
                            color: _gold.withOpacity(0.8),
                          ),
                        ),
                        SizedBox(height: 4),
                      ],
                      Text(
                        message.text,
                        style: TextStyle(
                          color: Colors.white.withOpacity(isFromClient ? 0.95 : 0.85),
                          fontSize: 15.sp,
                          height: 1.4,
                        ),
                      ),
                      if (message.imageUrl != null) ...[
                        SizedBox(height: 8),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(12.r),
                          child: AppCachedImage(
                            imageUrl: message.imageUrl!.startsWith('http')
                                ? message.imageUrl!
                                : 'https://arabica26.ru${message.imageUrl}',
                            width: double.infinity,
                            fit: BoxFit.cover,
                            errorWidget: (context, error, stackTrace) {
                              return Container(
                                height: 200,
                                decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(0.06),
                                  borderRadius: BorderRadius.circular(12.r),
                                ),
                                child: Center(
                                  child: Icon(Icons.broken_image_rounded, size: 50, color: Colors.white.withOpacity(0.3)),
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                      SizedBox(height: 6),
                      Text(
                        _formatTimestamp(message.timestamp),
                        style: TextStyle(
                          fontSize: 11.sp,
                          color: Colors.white.withOpacity(isFromClient ? 0.5 : 0.35),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (!isFromClient) Spacer(flex: 1),
            ],
          ),
        ),
        // Кнопка "Перейти в диалог с магазином" под сообщениями сотрудника
        if (!isFromClient && shopAddress != null && shopAddress.isNotEmpty)
          Padding(
            padding: EdgeInsets.only(left: 8.w, bottom: 8.h),
            child: GestureDetector(
              onTap: _isCreatingDialog ? null : () => _openShopDialog(shopAddress),
              child: Container(
                padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 6.h),
                decoration: BoxDecoration(
                  color: _emerald.withOpacity(0.5),
                  borderRadius: BorderRadius.circular(12.r),
                  border: Border.all(color: _gold.withOpacity(0.3)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.store_rounded, size: 14, color: _gold),
                    SizedBox(width: 6),
                    Text(
                      _isCreatingDialog ? 'Создание...' : 'Диалог с магазином',
                      style: TextStyle(
                        fontSize: 11.sp,
                        color: _gold,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _night,
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [_emerald, _emeraldDark, _night],
            stops: [0.0, 0.15, 0.4],
          ),
        ),
        child: SafeArea(
          bottom: false,
          child: Column(
            children: [
              // AppBar
              Padding(
                padding: EdgeInsets.fromLTRB(4.w, 8.h, 4.w, 8.h),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: Icon(
                        Icons.arrow_back_ios_new_rounded,
                        color: Colors.white.withOpacity(0.8),
                        size: 22,
                      ),
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _question?.shopAddress ?? 'Диалог',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 17.sp,
                              fontWeight: FontWeight.w500,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            'Поиск товара',
                            style: TextStyle(
                              fontSize: 12.sp,
                              color: _gold.withOpacity(0.7),
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: Icon(Icons.refresh_rounded, color: Colors.white.withOpacity(0.7), size: 22),
                      onPressed: _loadQuestion,
                    ),
                  ],
                ),
              ),
              // Messages
              Expanded(
                child: _isLoading
                    ? Center(child: CircularProgressIndicator(color: _gold))
                    : _question == null
                        ? Center(
                            child: Text(
                              'Диалог не найден',
                              style: TextStyle(color: Colors.white.withOpacity(0.5)),
                            ),
                          )
                        : _question!.messages.isEmpty
                            ? Center(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Container(
                                      width: 64,
                                      height: 64,
                                      decoration: BoxDecoration(
                                        color: Colors.white.withOpacity(0.06),
                                        borderRadius: BorderRadius.circular(18.r),
                                        border: Border.all(color: _gold.withOpacity(0.3)),
                                      ),
                                      child: Icon(
                                        Icons.chat_bubble_outline,
                                        size: 32,
                                        color: _gold.withOpacity(0.5),
                                      ),
                                    ),
                                    SizedBox(height: 20),
                                    Text(
                                      'Нет сообщений',
                                      style: TextStyle(
                                        fontSize: 18.sp,
                                        fontWeight: FontWeight.w500,
                                        color: Colors.white.withOpacity(0.8),
                                      ),
                                    ),
                                    SizedBox(height: 8),
                                    Padding(
                                      padding: EdgeInsets.symmetric(horizontal: 32.w),
                                      child: Text(
                                        'Вопрос: ${_question!.questionText}',
                                        style: TextStyle(color: Colors.white.withOpacity(0.4)),
                                        textAlign: TextAlign.center,
                                      ),
                                    ),
                                  ],
                                ),
                              )
                            : ListView.builder(
                                controller: _scrollController,
                                reverse: true,
                                padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 8.h),
                                itemCount: _question!.messages.length,
                                itemBuilder: (context, index) {
                                  final message = _question!.messages[_question!.messages.length - 1 - index];
                                  return _buildMessageBubble(message);
                                },
                              ),
              ),
              // Input field
              Container(
                padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 10.h),
                decoration: BoxDecoration(
                  color: _night.withOpacity(0.95),
                  border: Border(top: BorderSide(color: _gold.withOpacity(0.15))),
                ),
                child: SafeArea(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(
                        child: Container(
                          constraints: BoxConstraints(maxHeight: 120),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.06),
                            borderRadius: BorderRadius.circular(22.r),
                            border: Border.all(color: _gold.withOpacity(0.2)),
                          ),
                          child: TextField(
                            controller: _messageController,
                            maxLines: 4,
                            minLines: 1,
                            textCapitalization: TextCapitalization.sentences,
                            style: TextStyle(
                              fontSize: 15.sp,
                              height: 1.4,
                              color: Colors.white.withOpacity(0.9),
                            ),
                            decoration: InputDecoration(
                              hintText: 'Введите сообщение...',
                              hintStyle: TextStyle(
                                color: Colors.white.withOpacity(0.3),
                                fontSize: 15.sp,
                              ),
                              border: InputBorder.none,
                              contentPadding: EdgeInsets.symmetric(horizontal: 18.w, vertical: 12.h),
                            ),
                            onSubmitted: (_) => _sendMessage(),
                          ),
                        ),
                      ),
                      SizedBox(width: 10),
                      Container(
                        margin: EdgeInsets.only(bottom: 4.h),
                        child: GestureDetector(
                          onTap: _isSending ? null : _sendMessage,
                          child: Container(
                            width: 46,
                            height: 46,
                            decoration: BoxDecoration(
                              color: _emerald,
                              borderRadius: BorderRadius.circular(23.r),
                              border: Border.all(color: _gold.withOpacity(0.3)),
                            ),
                            child: Center(
                              child: _isSending
                                  ? SizedBox(
                                      width: 22,
                                      height: 22,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2.5,
                                        color: _gold,
                                      ),
                                    )
                                  : Icon(
                                      Icons.send_rounded,
                                      color: _gold,
                                      size: 22,
                                    ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
