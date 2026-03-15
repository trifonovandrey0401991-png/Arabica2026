import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';
import 'dart:io';
import 'package:image_picker/image_picker.dart';
import '../models/product_question_model.dart';
import '../models/product_question_message_model.dart';
import '../services/product_question_service.dart';
import '../../shops/models/shop_model.dart';
import '../../../core/constants/api_constants.dart';
import '../../../shared/widgets/app_cached_image.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../../core/theme/app_colors.dart';

class ProductQuestionAnswerPage extends StatefulWidget {
  final String questionId;
  final String? shopAddress;
  final bool canAnswer;

  const ProductQuestionAnswerPage({
    super.key,
    required this.questionId,
    this.shopAddress,
    this.canAnswer = true,
  });

  @override
  State<ProductQuestionAnswerPage> createState() => _ProductQuestionAnswerPageState();
}

class _ProductQuestionAnswerPageState extends State<ProductQuestionAnswerPage> with WidgetsBindingObserver {
  ProductQuestion? _question;
  String? _selectedShopAddress;
  String? _lastMessageTimestamp; // Для инкрементальной загрузки
  final TextEditingController _answerController = TextEditingController();
  final ImagePicker _imagePicker = ImagePicker();
  File? _selectedImage;
  bool _isLoading = true;
  bool _isSending = false;
  bool _hasAnswered = false;
  final ScrollController _scrollController = ScrollController();
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadData();
    _markAsRead();
    _refreshTimer = Timer.periodic(Duration(seconds: 5), (_) => _refreshMessages());
  }

  Future<void> _markAsRead() async {
    try {
      await ProductQuestionService.markQuestionAsRead(
        questionId: widget.questionId,
        readerType: 'employee',
      );
    } catch (e) {
      // Игнорируем ошибки
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _refreshTimer?.cancel();
    _answerController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _refreshTimer?.cancel();
      _refreshTimer = null;
    } else if (state == AppLifecycleState.resumed) {
      _refreshTimer ??= Timer.periodic(Duration(seconds: 5), (_) => _refreshMessages());
    }
  }

  Future<void> _refreshMessages() async {
    if (_isSending || _question == null) return;
    try {
      // Инкрементальная загрузка — только новые сообщения
      final updated = await ProductQuestionService.getQuestion(
        widget.questionId,
        since: _lastMessageTimestamp,
      );
      if (updated != null && updated.messages.isNotEmpty && mounted) {
        _updateLastTimestamp(updated.messages);
        if (mounted) setState(() {
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
      }
    } catch (e) {
      // Игнорируем ошибки автообновления
    }
  }

  void _updateLastTimestamp(List<ProductQuestionMessage> messages) {
    if (messages.isNotEmpty) {
      _lastMessageTimestamp = messages.last.timestamp;
    }
  }

  Future<void> _loadData() async {
    if (mounted) setState(() {
      _isLoading = true;
    });

    try {
      await Shop.loadShopsFromServer();
      final question = await ProductQuestionService.getQuestion(widget.questionId);
      if (question != null) _updateLastTimestamp(question.messages);

      if (!mounted) return;
      setState(() {
        _question = question;
        if (widget.shopAddress != null && widget.shopAddress!.isNotEmpty) {
          _selectedShopAddress = widget.shopAddress;
        } else if (question != null && question.shopAddress.isNotEmpty) {
          _selectedShopAddress = question.shopAddress;
        }
        _isLoading = false;
      });

      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          0,
          duration: Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка загрузки: $e'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10.r)),
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

      if (image != null && mounted) {
        if (mounted) setState(() {
          _selectedImage = File(image.path);
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка выбора фото: $e'), backgroundColor: Colors.red),
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

      if (image != null && mounted) {
        if (mounted) setState(() {
          _selectedImage = File(image.path);
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка съемки фото: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _showImageSourceDialog() async {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: BoxDecoration(
          color: AppColors.night.withOpacity(0.98),
          borderRadius: BorderRadius.vertical(top: Radius.circular(20.r)),
          border: Border(
            top: BorderSide(color: AppColors.gold.withOpacity(0.2)),
          ),
        ),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                margin: EdgeInsets.symmetric(vertical: 12.h),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(2.r),
                ),
              ),
              Padding(
                padding: EdgeInsets.all(16.w),
                child: Text(
                  'Прикрепить фото',
                  style: TextStyle(
                    fontSize: 18.sp,
                    fontWeight: FontWeight.w600,
                    color: Colors.white.withOpacity(0.9),
                  ),
                ),
              ),
              ListTile(
                leading: Container(
                  padding: EdgeInsets.all(10.w),
                  decoration: BoxDecoration(
                    color: AppColors.emerald.withOpacity(0.3),
                    borderRadius: BorderRadius.circular(12.r),
                  ),
                  child: Icon(Icons.photo_library, color: Colors.white.withOpacity(0.8)),
                ),
                title: Text('Галерея', style: TextStyle(color: Colors.white.withOpacity(0.9))),
                onTap: () {
                  Navigator.pop(context);
                  _pickImage();
                },
              ),
              ListTile(
                leading: Container(
                  padding: EdgeInsets.all(10.w),
                  decoration: BoxDecoration(
                    color: AppColors.emerald.withOpacity(0.3),
                    borderRadius: BorderRadius.circular(12.r),
                  ),
                  child: Icon(Icons.camera_alt, color: Colors.white.withOpacity(0.8)),
                ),
                title: Text('Камера', style: TextStyle(color: Colors.white.withOpacity(0.9))),
                onTap: () {
                  Navigator.pop(context);
                  _takePhoto();
                },
              ),
              SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _sendAnswer() async {
    if (_selectedShopAddress == null || _selectedShopAddress!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Выберите магазин, от имени которого отвечаете'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    if (_answerController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Введите ответ'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    if (_isSending) return;

    if (mounted) setState(() {
      _isSending = true;
    });

    try {
      final prefs = await SharedPreferences.getInstance();
      final senderPhone = prefs.getString('user_phone') ?? '';
      final senderName = prefs.getString('user_name') ?? 'Сотрудник';

      String? photoUrl;
      if (_selectedImage != null) {
        photoUrl = await ProductQuestionService.uploadPhoto(_selectedImage!.path);
        if (photoUrl == null) {
          throw Exception('Ошибка загрузки фото');
        }
      }

      final message = await ProductQuestionService.answerQuestion(
        questionId: widget.questionId,
        shopAddress: _selectedShopAddress!,
        text: _answerController.text.trim(),
        senderPhone: senderPhone.isNotEmpty ? senderPhone : null,
        senderName: senderName,
        imageUrl: photoUrl,
      );

      if (message != null && mounted) {
        _answerController.clear();
        // Оптимистичное добавление — сразу показываем ответ
        _updateLastTimestamp([message]);
        if (mounted) setState(() {
          _selectedImage = null;
          _hasAnswered = true;
          if (_question != null) {
            _question = ProductQuestion(
              id: _question!.id,
              clientPhone: _question!.clientPhone,
              clientName: _question!.clientName,
              shopAddress: _question!.shopAddress,
              shopName: _question!.shopName,
              questionText: _question!.questionText,
              questionImageUrl: _question!.questionImageUrl,
              timestamp: _question!.timestamp,
              isAnswered: true,
              answeredBy: _question!.answeredBy,
              answeredByName: _question!.answeredByName,
              lastAnswerTime: message.timestamp,
              isNetworkWide: _question!.isNetworkWide,
              hasUnreadFromClient: _question!.hasUnreadFromClient,
              messages: [..._question!.messages, message],
              rawShops: _question!.rawShops,
            );
          }
        });
        if (_scrollController.hasClients) {
          _scrollController.animateTo(
            0,
            duration: Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ответ отправлен!'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10.r)),
          ),
        );
      } else {
        throw Exception('Не удалось отправить ответ');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка: $e'), backgroundColor: Colors.red),
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
      final date = DateTime.parse(timestamp).toLocal();
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

  Widget _buildMessageBubble(ProductQuestionMessage message) {
    final isFromClient = message.senderType == 'client';
    // Для сотрудника: клиент слева, сотрудник справа
    final isMyMessage = !isFromClient;

    return Padding(
      padding: EdgeInsets.symmetric(vertical: 4.h),
      child: Row(
        mainAxisAlignment: isMyMessage ? MainAxisAlignment.end : MainAxisAlignment.start,
        children: [
          if (isMyMessage) Spacer(flex: 1),
          Flexible(
            flex: 4,
            child: Container(
              padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 10.h),
              decoration: BoxDecoration(
                gradient: isMyMessage
                    ? LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [AppColors.emerald, AppColors.emeraldDark],
                      )
                    : null,
                color: isMyMessage ? null : Colors.white.withOpacity(0.08),
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(18.r),
                  topRight: Radius.circular(18.r),
                  bottomLeft: isMyMessage ? Radius.circular(18.r) : Radius.circular(4.r),
                  bottomRight: isMyMessage ? Radius.circular(4.r) : Radius.circular(18.r),
                ),
                border: Border.all(
                  color: AppColors.gold.withOpacity(0.5),
                  width: 1.0,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (isMyMessage && (message.shopAddress?.isNotEmpty ?? false)) ...[
                    Text(
                      'От: ${message.shopAddress}',
                      style: TextStyle(
                        fontSize: 11.sp,
                        fontWeight: FontWeight.w600,
                        color: AppColors.gold.withOpacity(0.8),
                      ),
                    ),
                    SizedBox(height: 4),
                  ],
                  if (isFromClient) ...[
                    Text(
                      'Клиент',
                      style: TextStyle(
                        fontSize: 11.sp,
                        fontWeight: FontWeight.w600,
                        color: AppColors.gold.withOpacity(0.8),
                      ),
                    ),
                    SizedBox(height: 4),
                  ],
                  Text(
                    message.text,
                    style: TextStyle(
                      color: Colors.white.withOpacity(isMyMessage ? 0.95 : 0.85),
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
                            : '${ApiConstants.serverUrl}${message.imageUrl}',
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
                      color: Colors.white.withOpacity(isMyMessage ? 0.5 : 0.35),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (!isMyMessage) Spacer(flex: 1),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) {
          Navigator.of(context).pop(_hasAnswered);
        }
      },
      child: Scaffold(
        backgroundColor: AppColors.night,
        body: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [AppColors.emerald, AppColors.emeraldDark, AppColors.night],
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
                        onPressed: () => Navigator.of(context).pop(_hasAnswered),
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
                              'Ответ на вопрос',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 17.sp,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            if (_selectedShopAddress != null)
                              Text(
                                _selectedShopAddress!,
                                style: TextStyle(
                                  fontSize: 12.sp,
                                  color: AppColors.gold.withOpacity(0.7),
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: Icon(Icons.refresh_rounded, color: Colors.white.withOpacity(0.7), size: 22),
                        onPressed: _loadData,
                      ),
                    ],
                  ),
                ),
                // Warning if can't answer
                if (!widget.canAnswer)
                  Container(
                    margin: EdgeInsets.symmetric(horizontal: 12.w),
                    padding: EdgeInsets.all(12.w),
                    decoration: BoxDecoration(
                      color: Colors.red.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(12.r),
                      border: Border.all(color: Colors.red.withOpacity(0.3)),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.lock_rounded, color: Colors.red[300], size: 20),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Время ответа истекло. Просмотр без возможности ответа.',
                            style: TextStyle(
                              fontSize: 12.sp,
                              color: Colors.red[300],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                // Messages
                Expanded(
                  child: _isLoading
                      ? Center(child: CircularProgressIndicator(color: AppColors.gold))
                      : _question == null
                          ? Center(
                              child: Text(
                                'Вопрос не найден',
                                style: TextStyle(color: Colors.white.withOpacity(0.5)),
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
                // Input field (only if can answer)
                if (widget.canAnswer)
                  Column(
                    children: [
                      // Photo preview
                      if (_selectedImage != null)
                        Container(
                          padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 8.h),
                          color: AppColors.night.withOpacity(0.95),
                          child: Stack(
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(12.r),
                                child: Image.file(
                                  _selectedImage!,
                                  width: double.infinity,
                                  height: 150,
                                  fit: BoxFit.cover,
                                ),
                              ),
                              Positioned(
                                top: 8.h,
                                right: 8.w,
                                child: GestureDetector(
                                  onTap: () => setState(() => _selectedImage = null),
                                  child: Container(
                                    padding: EdgeInsets.all(6.w),
                                    decoration: BoxDecoration(
                                      color: Colors.black54,
                                      shape: BoxShape.circle,
                                    ),
                                    child: Icon(Icons.close_rounded, color: Colors.white, size: 18),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      // Input
                      Container(
                        padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 10.h),
                        decoration: BoxDecoration(
                          color: AppColors.night.withOpacity(0.95),
                          border: Border(top: BorderSide(color: AppColors.gold.withOpacity(0.15))),
                        ),
                        child: SafeArea(
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              // Attach button
                              Container(
                                margin: EdgeInsets.only(bottom: 4.h),
                                width: 44,
                                height: 44,
                                decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(0.08),
                                  borderRadius: BorderRadius.circular(12.r),
                                  border: Border.all(color: AppColors.gold.withOpacity(0.2)),
                                ),
                                child: IconButton(
                                  icon: Icon(Icons.attach_file_rounded, color: AppColors.gold.withOpacity(0.7)),
                                  onPressed: _isSending ? null : _showImageSourceDialog,
                                  iconSize: 22,
                                  constraints: BoxConstraints(minWidth: 44, minHeight: 44),
                                ),
                              ),
                              SizedBox(width: 10),
                              // Text field
                              Expanded(
                                child: Container(
                                  constraints: BoxConstraints(maxHeight: 120),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withOpacity(0.06),
                                    borderRadius: BorderRadius.circular(22.r),
                                    border: Border.all(color: AppColors.gold.withOpacity(0.2)),
                                  ),
                                  child: TextField(
                                    controller: _answerController,
                                    maxLines: 4,
                                    minLines: 1,
                                    textCapitalization: TextCapitalization.sentences,
                                    style: TextStyle(
                                      fontSize: 15.sp,
                                      height: 1.4,
                                      color: Colors.white.withOpacity(0.9),
                                    ),
                                    decoration: InputDecoration(
                                      hintText: 'Введите ответ...',
                                      hintStyle: TextStyle(
                                        color: Colors.white.withOpacity(0.3),
                                        fontSize: 15.sp,
                                      ),
                                      border: InputBorder.none,
                                      contentPadding: EdgeInsets.symmetric(horizontal: 18.w, vertical: 12.h),
                                    ),
                                    onSubmitted: (_) => _sendAnswer(),
                                  ),
                                ),
                              ),
                              SizedBox(width: 10),
                              // Send button
                              Container(
                                margin: EdgeInsets.only(bottom: 4.h),
                                child: GestureDetector(
                                  onTap: _isSending ? null : _sendAnswer,
                                  child: Container(
                                    width: 46,
                                    height: 46,
                                    decoration: BoxDecoration(
                                      color: AppColors.emerald,
                                      borderRadius: BorderRadius.circular(23.r),
                                      border: Border.all(color: AppColors.gold.withOpacity(0.3)),
                                    ),
                                    child: Center(
                                      child: _isSending
                                          ? SizedBox(
                                              width: 22,
                                              height: 22,
                                              child: CircularProgressIndicator(
                                                strokeWidth: 2.5,
                                                color: AppColors.gold,
                                              ),
                                            )
                                          : Icon(
                                              Icons.send_rounded,
                                              color: AppColors.gold,
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
              ],
            ),
          ),
        ),
      ),
    );
  }
}
