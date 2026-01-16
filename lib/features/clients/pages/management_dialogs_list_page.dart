import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/management_message_model.dart';
import '../models/client_model.dart';
import '../../../core/services/base_http_service.dart';
import '../../../core/constants/api_constants.dart';
import 'admin_management_dialog_page.dart';

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

  Future<void> _loadDialogs() async {
    setState(() => _isLoading = true);

    try {
      final result = await BaseHttpService.getRaw(
        endpoint: '/api/management-dialogs',
        timeout: ApiConstants.longTimeout,
      );

      if (result != null && result['success'] == true) {
        final dialogsData = result['dialogs'] as List<dynamic>? ?? [];
        final dialogs = dialogsData
            .map((json) => ManagementDialogSummary.fromJson(json as Map<String, dynamic>))
            .where((dialog) => dialog.phone.isNotEmpty) // Фильтруем диалоги с пустым телефоном
            .toList();

        print('🔍 DEBUG ManagementDialogsList: Loaded ${dialogs.length} dialogs');
        for (var i = 0; i < dialogs.length && i < 3; i++) {
          print('🔍 Dialog $i: ${dialogs[i].clientName} (${dialogs[i].phone}), unread: ${dialogs[i].unreadCount}');
        }

        if (mounted) {
          setState(() {
            _dialogs = dialogs;
            _totalUnread = result['totalUnread'] ?? 0;
            _isLoading = false;
          });
        }
      } else {
        if (mounted) {
          setState(() {
            _dialogs = [];
            _totalUnread = 0;
            _isLoading = false;
          });
        }
      }
    } catch (e) {
      if (mounted) {
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
      final date = DateTime.parse(timestamp);
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
            const Icon(Icons.business, size: 24),
            const SizedBox(width: 8),
            const Flexible(
              child: Text(
                'Связь с руководством',
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (_totalUnread > 0) ...[
              const SizedBox(width: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.red,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  _totalUnread > 99 ? '99+' : '$_totalUnread',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ],
        ),
        backgroundColor: const Color(0xFF004D40),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadDialogs,
            tooltip: 'Обновить',
          ),
        ],
      ),
      body: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF004D40),
          image: DecorationImage(
            image: AssetImage('assets/images/arabica_background.png'),
            fit: BoxFit.cover,
            opacity: 0.6,
          ),
        ),
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _dialogs.isEmpty
                ? const Center(
                    child: Text(
                      'Нет сообщений',
                      style: TextStyle(color: Colors.white, fontSize: 18),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _dialogs.length,
                    itemBuilder: (context, index) {
                      final dialog = _dialogs[index];
                      final hasUnread = dialog.unreadCount > 0;

                      return Card(
                        margin: const EdgeInsets.only(bottom: 12),
                        child: ListTile(
                          leading: Stack(
                            children: [
                              CircleAvatar(
                                backgroundColor: const Color(0xFF004D40),
                                child: Text(
                                  dialog.clientName[0].toUpperCase(),
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              if (hasUnread)
                                Positioned(
                                  right: 0,
                                  top: 0,
                                  child: Container(
                                    padding: const EdgeInsets.all(4),
                                    decoration: const BoxDecoration(
                                      color: Colors.red,
                                      shape: BoxShape.circle,
                                    ),
                                    child: Text(
                                      dialog.unreadCount > 9 ? '9+' : '${dialog.unreadCount}',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 10,
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
                              const SizedBox(height: 4),
                              Text(
                                '${dialog.messagesCount} сообщ. • ${_formatTimestamp(dialog.lastMessage.timestamp)}',
                                style: TextStyle(
                                  color: Colors.grey[600],
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () async {
                            print('🔍 DEBUG: Tapped on dialog: ${dialog.clientName} (${dialog.phone})');
                            // Создаем простой объект Client
                            final client = Client(
                              phone: dialog.phone,
                              name: dialog.clientName,
                            );

                            print('🔍 DEBUG: Navigating to AdminManagementDialogPage with client: ${client.name}, ${client.phone}');
                            await Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => AdminManagementDialogPage(
                                  client: client,
                                ),
                              ),
                            );
                            print('🔍 DEBUG: Returned from AdminManagementDialogPage, reloading dialogs');
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
