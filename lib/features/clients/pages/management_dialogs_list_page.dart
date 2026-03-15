import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../core/utils/logger.dart';
import '../models/client_model.dart';
import '../../../core/services/base_http_service.dart';
import '../../../core/constants/api_constants.dart';
import 'admin_management_dialog_page.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/cache_manager.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

/// Страница списка диалогов "Связь с руководством" для админа
class ManagementDialogsListPage extends StatefulWidget {
  const ManagementDialogsListPage({super.key});

  @override
  State<ManagementDialogsListPage> createState() => _ManagementDialogsListPageState();
}

class _ManagementDialogsListPageState extends State<ManagementDialogsListPage> {
  List<ManagementDialogSummary> _dialogs = [];
  bool _isLoading = true;
  int _totalUnread = 0;

  @override
  void initState() {
    super.initState();
    _loadDialogs();
  }

  static const _cacheKey = 'management_dialogs';

  Future<void> _loadDialogs() async {
    // Step 1: Show cached data instantly
    final cached = CacheManager.get<Map<String, dynamic>>(_cacheKey);
    if (cached != null && mounted) {
      setState(() {
        _dialogs = cached['dialogs'] as List<ManagementDialogSummary>;
        _totalUnread = cached['totalUnread'] as int;
        _isLoading = false;
      });
    }

    if (_dialogs.isEmpty && mounted) setState(() => _isLoading = true);

    try {
      final result = await BaseHttpService.getRaw(
        endpoint: '/api/management-dialogs',
        timeout: ApiConstants.longTimeout,
      );

      if (result != null && result['success'] == true) {
        final dialogsData = result['dialogs'] as List<dynamic>? ?? [];
        final dialogs = dialogsData
            .map((json) => ManagementDialogSummary.fromJson(json as Map<String, dynamic>))
            .where((dialog) => dialog.phone.isNotEmpty)
            .toList();

        if (mounted) {
          setState(() {
            _dialogs = dialogs;
            _totalUnread = result['totalUnread'] ?? 0;
            _isLoading = false;
          });
          // Step 3: Save to cache
          CacheManager.set(_cacheKey, {
            'dialogs': dialogs,
            'totalUnread': result['totalUnread'] ?? 0,
          });
        }
      } else {
        if (mounted && _dialogs.isEmpty) {
          setState(() {
            _dialogs = [];
            _totalUnread = 0;
            _isLoading = false;
          });
        }
      }
    } catch (e) {
      if (mounted && _dialogs.isEmpty) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка загрузки: $e'),
            backgroundColor: Colors.red,
          ),
        );
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
        return 'Вчера';
      } else if (difference.inDays < 7) {
        return '${difference.inDays} дн. назад';
      } else {
        return DateFormat('dd.MM.yyyy').format(date);
      }
    } catch (e) {
      return timestamp;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Icon(Icons.business, size: 24),
            SizedBox(width: 8),
            Flexible(
              child: Text(
                'Связь с руководством',
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (_totalUnread > 0) ...[
              SizedBox(width: 12),
              Container(
                padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 4.h),
                decoration: BoxDecoration(
                  color: Colors.red,
                  borderRadius: BorderRadius.circular(12.r),
                ),
                child: Text(
                  _totalUnread > 99 ? '99+' : '$_totalUnread',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 12.sp,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ],
        ),
        backgroundColor: AppColors.primaryGreen,
        actions: [
          IconButton(
            icon: Icon(Icons.refresh),
            onPressed: _loadDialogs,
            tooltip: 'Обновить',
          ),
        ],
      ),
      body: Container(
        decoration: BoxDecoration(
          color: AppColors.primaryGreen,
          image: DecorationImage(
            image: AssetImage('assets/images/arabica_background.png'),
            fit: BoxFit.cover,
            opacity: 0.6,
          ),
        ),
        child: _isLoading
            ? Center(child: CircularProgressIndicator())
            : _dialogs.isEmpty
                ? Center(
                    child: Text(
                      'Нет сообщений',
                      style: TextStyle(color: Colors.white, fontSize: 18.sp),
                    ),
                  )
                : ListView.builder(
                    padding: EdgeInsets.all(16.w),
                    itemCount: _dialogs.length,
                    itemBuilder: (context, index) {
                      final dialog = _dialogs[index];
                      final hasUnread = dialog.unreadCount > 0;

                      return Card(
                        margin: EdgeInsets.only(bottom: 12.h),
                        child: ListTile(
                          leading: Stack(
                            children: [
                              CircleAvatar(
                                backgroundColor: AppColors.primaryGreen,
                                child: Text(
                                  dialog.clientName[0].toUpperCase(),
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              if (hasUnread)
                                Positioned(
                                  right: 0.w,
                                  top: 0.h,
                                  child: Container(
                                    padding: EdgeInsets.all(4.w),
                                    decoration: BoxDecoration(
                                      color: Colors.red,
                                      shape: BoxShape.circle,
                                    ),
                                    child: Text(
                                      dialog.unreadCount > 9 ? '9+' : '${dialog.unreadCount}',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 10.sp,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          title: Text(
                            dialog.clientName,
                            style: TextStyle(
                              fontWeight: hasUnread ? FontWeight.bold : FontWeight.normal,
                            ),
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                dialog.lastMessage.text.isNotEmpty
                                    ? dialog.lastMessage.text
                                    : 'Медиа',
                                style: TextStyle(
                                  color: Colors.grey[700],
                                  fontWeight: hasUnread ? FontWeight.w500 : FontWeight.normal,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              SizedBox(height: 4),
                              Text(
                                '${dialog.messagesCount} сообщ. • ${_formatTimestamp(dialog.lastMessage.timestamp)}',
                                style: TextStyle(
                                  color: Colors.grey[600],
                                  fontSize: 12.sp,
                                ),
                              ),
                            ],
                          ),
                          trailing: Icon(Icons.chevron_right),
                          onTap: () async {
                            Logger.debug('Tapped on dialog: ${dialog.clientName} (${Logger.maskPhone(dialog.phone)})');
                            // Создаем простой объект Client
                            final client = Client(
                              phone: dialog.phone,
                              name: dialog.clientName,
                            );

                            Logger.debug('Navigating to AdminManagementDialogPage with client: ${client.name}, ${Logger.maskPhone(client.phone)}');
                            await Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => AdminManagementDialogPage(
                                  client: client,
                                ),
                              ),
                            );
                            Logger.debug('Returned from AdminManagementDialogPage, reloading dialogs');
                            // Перезагрузить список после возврата
                            _loadDialogs();
                          },
                        ),
                      );
                    },
                  ),
      ),
    );
  }
}

/// Модель для краткой информации о диалоге
class ManagementDialogSummary {
  final String phone;
  final String clientName;
  final int messagesCount;
  final int unreadCount;
  final ManagementLastMessage lastMessage;

  ManagementDialogSummary({
    required this.phone,
    required this.clientName,
    required this.messagesCount,
    required this.unreadCount,
    required this.lastMessage,
  });

  factory ManagementDialogSummary.fromJson(Map<String, dynamic> json) {
    return ManagementDialogSummary(
      phone: json['phone'] ?? '',
      clientName: json['clientName'] ?? 'Клиент',
      messagesCount: json['messagesCount'] ?? 0,
      unreadCount: json['unreadCount'] ?? 0,
      lastMessage: ManagementLastMessage.fromJson(json['lastMessage'] ?? {}),
    );
  }
}

/// Модель для последнего сообщения в диалоге
class ManagementLastMessage {
  final String text;
  final String timestamp;
  final String senderType;

  ManagementLastMessage({
    required this.text,
    required this.timestamp,
    required this.senderType,
  });

  factory ManagementLastMessage.fromJson(Map<String, dynamic> json) {
    return ManagementLastMessage(
      text: json['text'] ?? '',
      timestamp: json['timestamp'] ?? DateTime.now().toIso8601String(),
      senderType: json['senderType'] ?? 'client',
    );
  }
}
