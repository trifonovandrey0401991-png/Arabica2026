import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';
import 'dart:io';
import 'package:image_picker/image_picker.dart';
import '../models/product_question_model.dart';
import '../models/product_question_message_model.dart';
import '../services/product_question_service.dart';
import '../../../core/constants/api_constants.dart';
import '../../../shared/widgets/app_cached_image.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../../core/theme/app_colors.dart';

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
  String? _lastMessageTimestamp; // Для инкрементальной загрузки
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _loadData();
    _refreshTimer = Timer.periodic(Duration(seconds: 5), (_) => _refreshDialog());
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

    await ProductQuestionService.markPersonalDialogRead(
      dialogId: widget.dialogId,
      readerType: 'employee',
    );
  }

  Future<void> _loadDialog() async {
    try {
      final dialog = await ProductQuestionService.getPersonalDialog(widget.dialogId);

      if (dialog != null && mounted) {
        _updateLastTimestamp(dialog.messages);
        if (mounted) setState(() {
          _dialog = dialog;
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

  Future<void> _refreshDialog() async {
    if (_isSending || _dialog == null) return;

    try {
      // Инкрементальная загрузка — только новые сообщения
      final updated = await ProductQuestionService.getPersonalDialog(
        widget.dialogId,
        since: _lastMessageTimestamp,
      );

      if (updated != null && updated.messages.isNotEmpty && mounted) {
        _updateLastTimestamp(updated.messages);
        if (mounted) setState(() {
          _dialog = PersonalProductDialog(
            id: _dialog!.id,
            clientPhone: _dialog!.clientPhone,
            clientName: _dialog!.clientName,
            shopAddress: _dialog!.shopAddress,
            originalQuestionId: _dialog!.originalQuestionId,
            createdAt: _dialog!.createdAt,
            hasUnreadFromClient: updated.hasUnreadFromClient,
            hasUnreadFromEmployee: updated.hasUnreadFromEmployee,
            lastMessageTime: updated.lastMessageTime ?? _dialog!.lastMessageTime,
            messages: [..._dialog!.messages, ...updated.messages],
          );
        });
        _scrollToBottom();
        await ProductQuestionService.markPersonalDialogRead(
          dialogId: widget.dialogId,
          readerType: 'employee',
        );
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

  void _scrollToBottom() {
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
    if (_isSending || _employeePhone == null) return;

    if (mounted) setState(() {
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
        // Оптимистичное добавление
        _updateLastTimestamp([result]);
        if (mounted) setState(() {
          _selectedImage = null;
          if (_dialog != null) {
            _dialog = PersonalProductDialog(
              id: _dialog!.id,
              clientPhone: _dialog!.clientPhone,
              clientName: _dialog!.clientName,
              shopAddress: _dialog!.shopAddress,
              originalQuestionId: _dialog!.originalQuestionId,
              createdAt: _dialog!.createdAt,
              hasUnreadFromClient: _dialog!.hasUnreadFromClient,
              hasUnreadFromEmployee: _dialog!.hasUnreadFromEmployee,
              lastMessageTime: result.timestamp,
              messages: [..._dialog!.messages, result],
            );
          }
        });
        _scrollToBottom();
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Не удалось отправить сообщение'), backgroundColor: Colors.red),
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

  Widget _buildMessage(ProductQuestionMessage message) {
    final isEmployeeMessage = message.senderType == 'employee';

    return Padding(
      padding: EdgeInsets.symmetric(vertical: 4.h),
      child: Row(
        mainAxisAlignment: isEmployeeMessage ? MainAxisAlignment.end : MainAxisAlignment.start,
        children: [
          if (isEmployeeMessage) Spacer(flex: 1),
          Flexible(
            flex: 4,
            child: Container(
              padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 10.h),
              decoration: BoxDecoration(
                gradient: isEmployeeMessage
                    ? LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [AppColors.emerald, AppColors.emeraldDark],
                      )
                    : null,
                color: isEmployeeMessage ? null : Colors.white.withOpacity(0.08),
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(18.r),
                  topRight: Radius.circular(18.r),
                  bottomLeft: isEmployeeMessage ? Radius.circular(18.r) : Radius.circular(4.r),
                  bottomRight: isEmployeeMessage ? Radius.circular(4.r) : Radius.circular(18.r),
                ),
                border: Border.all(
                  color: AppColors.gold.withOpacity(0.5),
                  width: 1.0,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (!isEmployeeMessage) ...[
                    Text(
                      _dialog?.clientName ?? widget.clientName,
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
                      color: Colors.white.withOpacity(isEmployeeMessage ? 0.95 : 0.85),
                      fontSize: 15.sp,
                      height: 1.4,
                    ),
                  ),
                  SizedBox(height: 6),
                  Text(
                    _formatTimestamp(message.timestamp),
                    style: TextStyle(
                      fontSize: 11.sp,
                      color: Colors.white.withOpacity(isEmployeeMessage ? 0.5 : 0.35),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (!isEmployeeMessage) Spacer(flex: 1),
        ],
      ),
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
                            _dialog?.clientName ?? widget.clientName,
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 17.sp,
                              fontWeight: FontWeight.w500,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            widget.shopAddress,
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
                      onPressed: _loadDialog,
                    ),
                  ],
                ),
              ),
              // Messages
              Expanded(
                child: _isLoading
                    ? Center(child: CircularProgressIndicator(color: AppColors.gold))
                    : _dialog == null || _dialog!.messages.isEmpty
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
                            itemCount: _dialog!.messages.length,
                            itemBuilder: (context, index) {
                              return _buildMessage(_dialog!.messages[index]);
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
