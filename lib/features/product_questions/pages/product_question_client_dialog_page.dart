import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';
import 'dart:io';
import 'package:image_picker/image_picker.dart';
import '../../../core/constants/api_constants.dart';
import '../../../core/utils/logger.dart';
import '../models/product_question_message_model.dart';
import '../services/product_question_service.dart';
import 'product_question_personal_dialog_page.dart';
import '../../../shared/widgets/app_cached_image.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../../core/theme/app_colors.dart';

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
  Set<String> _existingDialogShops = {};
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
    _refreshTimer = Timer.periodic(Duration(seconds: 5), (_) => _loadMessages());
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
      if (mounted) setState(() {
        _isLoading = false;
      });
      return;
    }

    await _loadExistingDialogs();
    await _loadMessages();
    _markAllAsRead();
  }

  Future<void> _loadExistingDialogs() async {
    if (_clientPhone == null || _clientPhone!.isEmpty) return;

    try {
      final dialogs = await ProductQuestionService.getClientPersonalDialogs(_clientPhone!);
      if (mounted) setState(() {
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
        if (mounted) setState(() {
          _messages = data.messages;
          _isLoading = false;
        });

        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_scrollController.hasClients) {
            _scrollController.animateTo(
              _scrollController.position.maxScrollExtent,
              duration: Duration(milliseconds: 300),
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
      final source = await showModalBottomSheet<ImageSource>(
        context: context,
        backgroundColor: Colors.transparent,
        builder: (context) => Container(
          decoration: BoxDecoration(
            color: AppColors.night.withOpacity(0.98),
            borderRadius: BorderRadius.vertical(top: Radius.circular(20.r)),
            border: Border(top: BorderSide(color: AppColors.gold.withOpacity(0.2))),
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
                  onTap: () => Navigator.pop(context, ImageSource.gallery),
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
                  onTap: () => Navigator.pop(context, ImageSource.camera),
                ),
                SizedBox(height: 16),
              ],
            ),
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

        if (image != null && mounted) {
          if (mounted) setState(() {
            _selectedImage = File(image.path);
          });
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка выбора фото: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _sendMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty && _selectedImage == null) return;
    if (_isSending || _clientPhone == null) return;

    if (mounted) setState(() {
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
        if (mounted) setState(() {
          _selectedImage = null;
        });
        await _loadMessages();
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Не удалось отправить сообщение'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10.r)),
          ),
        );
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

  Future<void> _openShopDialog(String shopAddress, String? questionId) async {
    try {
      if (_clientPhone == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка: не удалось получить телефон клиента'), backgroundColor: Colors.red),
        );
        return;
      }

      final dialogs = await ProductQuestionService.getClientPersonalDialogs(_clientPhone!);
      final existingDialog = dialogs.where((d) => d.shopAddress == shopAddress).firstOrNull;

      if (existingDialog != null) {
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => ProductQuestionPersonalDialogPage(
              dialogId: existingDialog.id,
              shopAddress: shopAddress,
            ),
          ),
        );
        _loadMessages();
      } else {
        await _startPersonalDialog(shopAddress);
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка при открытии диалога: $e'), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _startPersonalDialog(String shopAddress) async {
    if (_isCreatingDialog || _clientPhone == null) return;

    if (mounted) setState(() {
      _isCreatingDialog = true;
    });

    try {
      final dialog = await ProductQuestionService.createPersonalDialog(
        clientPhone: _clientPhone!,
        clientName: _clientName ?? 'Клиент',
        shopAddress: shopAddress,
      );

      if (dialog != null && mounted) {
        if (mounted) setState(() {
          _existingDialogShops.add(shopAddress);
        });

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
          SnackBar(content: Text('Не удалось создать диалог'), backgroundColor: Colors.red),
        );
        Logger.debug('createPersonalDialog returned null for shopAddress: $shopAddress');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка при создании диалога: $e'), backgroundColor: Colors.red),
        );
        Logger.warning('Exception in createPersonalDialog: $e');
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
        Padding(
          padding: EdgeInsets.symmetric(vertical: 4.h),
          child: Row(
            mainAxisAlignment: isClientMessage ? MainAxisAlignment.end : MainAxisAlignment.start,
            children: [
              if (isClientMessage) Spacer(flex: 1),
              Flexible(
                flex: 4,
                child: Container(
                  padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 10.h),
                  decoration: BoxDecoration(
                    gradient: isClientMessage
                        ? LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [AppColors.emerald, AppColors.emeraldDark],
                          )
                        : null,
                    color: isClientMessage ? null : Colors.white.withOpacity(0.08),
                    borderRadius: BorderRadius.only(
                      topLeft: Radius.circular(18.r),
                      topRight: Radius.circular(18.r),
                      bottomLeft: isClientMessage ? Radius.circular(18.r) : Radius.circular(4.r),
                      bottomRight: isClientMessage ? Radius.circular(4.r) : Radius.circular(18.r),
                    ),
                    border: Border.all(
                      color: AppColors.gold.withOpacity(0.5),
                      width: 1.0,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (!isClientMessage) ...[
                        Text(
                          '${message.shopAddress ?? "Магазин"} - ${message.senderName ?? "Сотрудник"}',
                          style: TextStyle(
                            fontSize: 11.sp,
                            fontWeight: FontWeight.w600,
                            color: AppColors.gold.withOpacity(0.8),
                          ),
                        ),
                        SizedBox(height: 4),
                      ],
                      if (message.imageUrl != null && message.imageUrl!.isNotEmpty) ...[
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
                                height: 100,
                                decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(0.06),
                                  borderRadius: BorderRadius.circular(12.r),
                                ),
                                child: Icon(Icons.broken_image_rounded, color: Colors.white.withOpacity(0.3)),
                              );
                            },
                          ),
                        ),
                        SizedBox(height: 8),
                      ],
                      Text(
                        message.text,
                        style: TextStyle(
                          color: Colors.white.withOpacity(isClientMessage ? 0.95 : 0.85),
                          fontSize: 15.sp,
                          height: 1.4,
                        ),
                      ),
                      SizedBox(height: 6),
                      Text(
                        _formatTimestamp(message.timestamp),
                        style: TextStyle(
                          fontSize: 11.sp,
                          color: Colors.white.withOpacity(isClientMessage ? 0.5 : 0.35),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (!isClientMessage) Spacer(flex: 1),
            ],
          ),
        ),
        // Button "Write to shop" under employee messages
        if (!isClientMessage && shopAddress != null) ...[
          Padding(
            padding: EdgeInsets.only(left: 8.w, right: 8.w, bottom: 8.h),
            child: ElevatedButton.icon(
              onPressed: () => _openShopDialog(shopAddress, message.questionId),
              icon: Icon(Icons.store_rounded, size: 16),
              label: Text('Написать в магазин'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.emerald,
                foregroundColor: AppColors.gold,
                padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 6.h),
                textStyle: TextStyle(fontSize: 12.sp),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12.r),
                  side: BorderSide(color: AppColors.gold.withOpacity(0.3)),
                ),
              ),
            ),
          ),
        ],
        if (!isClientMessage && shopAddress != null && hasExistingDialog) ...[
          Padding(
            padding: EdgeInsets.only(left: 8.w, right: 8.w, bottom: 8.h),
            child: Text(
              'Диалог создан',
              style: TextStyle(
                fontSize: 11.sp,
                color: AppColors.gold.withOpacity(0.5),
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
                            'Поиск Товара',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 17.sp,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          Text(
                            'Все диалоги',
                            style: TextStyle(
                              fontSize: 12.sp,
                              color: AppColors.gold.withOpacity(0.7),
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: Icon(Icons.refresh_rounded, color: Colors.white.withOpacity(0.7), size: 22),
                      onPressed: _loadMessages,
                    ),
                  ],
                ),
              ),
              // Messages
              Expanded(
                child: _isLoading
                    ? Center(child: CircularProgressIndicator(color: AppColors.gold))
                    : _messages.isEmpty
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
                                    border: Border.all(color: AppColors.gold.withOpacity(0.3)),
                                  ),
                                  child: Icon(
                                    Icons.chat_bubble_outline,
                                    size: 32,
                                    color: AppColors.gold.withOpacity(0.5),
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
                              ],
                            ),
                          )
                        : ListView.builder(
                            controller: _scrollController,
                            padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 8.h),
                            itemCount: _messages.length,
                            itemBuilder: (context, index) {
                              return _buildMessage(_messages[index]);
                            },
                          ),
              ),
              // Photo preview
              if (_selectedImage != null)
                Container(
                  height: 100,
                  padding: EdgeInsets.all(8.w),
                  color: AppColors.night.withOpacity(0.95),
                  child: Stack(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12.r),
                        child: Image.file(
                          _selectedImage!,
                          height: 84,
                          fit: BoxFit.cover,
                        ),
                      ),
                      Positioned(
                        top: 0.h,
                        right: 0.w,
                        child: GestureDetector(
                          onTap: () => setState(() => _selectedImage = null),
                          child: Container(
                            padding: EdgeInsets.all(4.w),
                            decoration: BoxDecoration(
                              color: Colors.black54,
                              shape: BoxShape.circle,
                            ),
                            child: Icon(Icons.close_rounded, color: Colors.white, size: 16),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              // Input field
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
                          onPressed: _isSending ? null : _pickImage,
                          iconSize: 22,
                          constraints: BoxConstraints(minWidth: 44, minHeight: 44),
                        ),
                      ),
                      SizedBox(width: 10),
                      Expanded(
                        child: Container(
                          constraints: BoxConstraints(maxHeight: 120),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.06),
                            borderRadius: BorderRadius.circular(22.r),
                            border: Border.all(color: AppColors.gold.withOpacity(0.2)),
                          ),
                          child: TextField(
                            controller: _messageController,
                            maxLines: 4,
                            minLines: 1,
                            textCapitalization: TextCapitalization.sentences,
                            enabled: !_isSending,
                            style: TextStyle(
                              fontSize: 15.sp,
                              height: 1.4,
                              color: Colors.white.withOpacity(0.9),
                            ),
                            decoration: InputDecoration(
                              hintText: 'Написать сообщение...',
                              hintStyle: TextStyle(
                                color: Colors.white.withOpacity(0.3),
                                fontSize: 15.sp,
                              ),
                              border: InputBorder.none,
                              contentPadding: EdgeInsets.symmetric(horizontal: 18.w, vertical: 12.h),
                            ),
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
        ),
      ),
    );
  }
}
