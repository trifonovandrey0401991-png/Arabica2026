import 'package:flutter/material.dart';
import '../models/client_model.dart';
import '../services/client_service.dart';
import '../../../shared/dialogs/send_message_dialog.dart';
import 'client_chat_page.dart';
import 'admin_management_dialog_page.dart';

/// Страница управления клиентами
class ClientsManagementPage extends StatefulWidget {
  const ClientsManagementPage({super.key});

  @override
  State<ClientsManagementPage> createState() => _ClientsManagementPageState();
}

class _ClientsManagementPageState extends State<ClientsManagementPage> {
  List<Client> _clients = [];
  List<Client> _filteredClients = [];
  bool _isLoading = true;
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadClients();
    _searchController.addListener(_filterClients);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadClients() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final clients = await ClientService.getClients();
      // Сортируем: клиенты с непрочитанными сообщениями сверху
      clients.sort((a, b) {
        // Сначала по наличию непрочитанных (management имеет приоритет)
        final aHasUnread = a.hasUnreadFromClient || a.hasUnreadManagement;
        final bHasUnread = b.hasUnreadFromClient || b.hasUnreadManagement;
        if (aHasUnread && !bHasUnread) return -1;
        if (!aHasUnread && bHasUnread) return 1;
        // Management сообщения имеют приоритет
        if (a.hasUnreadManagement && !b.hasUnreadManagement) return -1;
        if (!a.hasUnreadManagement && b.hasUnreadManagement) return 1;
        // Затем по времени последнего сообщения (новые сверху)
        if (a.lastClientMessageTime != null && b.lastClientMessageTime != null) {
          return b.lastClientMessageTime!.compareTo(a.lastClientMessageTime!);
        }
        if (a.lastClientMessageTime != null) return -1;
        if (b.lastClientMessageTime != null) return 1;
        // По имени
        return a.name.compareTo(b.name);
      });
      setState(() {
        _clients = clients;
        _filteredClients = clients;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка загрузки клиентов: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _filterClients() {
    final query = _searchController.text.toLowerCase().trim();
    if (query.isEmpty) {
      setState(() {
        _filteredClients = _clients;
      });
      return;
    }

    setState(() {
      _filteredClients = _clients.where((client) {
        final nameMatch = client.name.toLowerCase().contains(query);
        final phoneMatch = client.phone.toLowerCase().contains(query);
        return nameMatch || phoneMatch;
      }).toList();
    });
  }

  Future<void> _showClientActions(Client client) async {
    final action = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(client.name.isNotEmpty ? client.name : client.phone),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.message, color: Color(0xFF004D40)),
              title: const Text('Отправить сообщение'),
              onTap: () => Navigator.pop(context, 'send'),
            ),
            ListTile(
              leading: const Icon(Icons.chat, color: Color(0xFF004D40)),
              title: const Text('Начать диалог'),
              onTap: () => Navigator.pop(context, 'chat'),
            ),
            ListTile(
              leading: Icon(
                Icons.business,
                color: client.hasUnreadManagement ? Colors.orange : const Color(0xFF004D40),
              ),
              title: Row(
                children: [
                  const Text('Связь с руководством'),
                  if (client.hasUnreadManagement) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.orange,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Text(
                        'NEW',
                        style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ],
              ),
              onTap: () => Navigator.pop(context, 'management'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Отмена'),
          ),
        ],
      ),
    );

    if (action == 'send') {
      await _showSendMessageDialog(client);
    } else if (action == 'chat') {
      await _openChat(client);
    } else if (action == 'management') {
      await _openManagementChat(client);
    }
  }

  Future<void> _openManagementChat(Client client) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => AdminManagementDialogPage(client: client),
      ),
    );
    // После возврата обновляем список
    _loadClients();
  }

  Future<void> _showSendMessageDialog(Client? client) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => SendMessageDialog(client: client),
    );

    if (result == true) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(client != null 
              ? 'Сообщение отправлено клиенту'
              : 'Сообщение отправлено всем клиентам'),
            backgroundColor: Colors.green,
          ),
        );
      }
    }
  }

  Future<void> _openChat(Client client) async {
    // Отмечаем сетевые сообщения как прочитанные
    if (client.hasUnreadFromClient) {
      ClientService.markNetworkMessagesAsReadByAdmin(client.phone);
    }

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ClientChatPage(client: client),
      ),
    );

    // После возврата обновляем список
    _loadClients();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Клиенты'),
        backgroundColor: const Color(0xFF004D40),
        actions: [
          IconButton(
            icon: const Icon(Icons.send),
            onPressed: () => _showSendMessageDialog(null),
            tooltip: 'Отправить всем',
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadClients,
            tooltip: 'Обновить',
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Поиск по имени или номеру телефона',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchController.clear();
                        },
                      )
                    : null,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _filteredClients.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.people_outline, size: 64, color: Colors.grey),
                            const SizedBox(height: 16),
                            Text(
                              _clients.isEmpty
                                  ? 'Нет клиентов'
                                  : 'Клиенты не найдены',
                              style: const TextStyle(fontSize: 18, color: Colors.grey),
                            ),
                            if (_clients.isEmpty) ...[
                              const SizedBox(height: 8),
                              const Text(
                                'Клиенты появятся после регистрации',
                                style: TextStyle(fontSize: 14, color: Colors.grey),
                              ),
                            ],
                          ],
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        itemCount: _filteredClients.length,
                        itemBuilder: (context, index) {
                          final client = _filteredClients[index];
                          final hasUnread = client.hasUnreadFromClient || client.hasUnreadManagement;

                          return Container(
                            margin: const EdgeInsets.only(bottom: 12),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(16),
                              boxShadow: [
                                BoxShadow(
                                  color: hasUnread
                                      ? Colors.red.withOpacity(0.3)
                                      : Colors.black.withOpacity(0.1),
                                  blurRadius: hasUnread ? 12 : 8,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: Material(
                              borderRadius: BorderRadius.circular(16),
                              color: Colors.white,
                              child: InkWell(
                                borderRadius: BorderRadius.circular(16),
                                onTap: () => _showClientActions(client),
                                child: Container(
                                  padding: const EdgeInsets.all(16),
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(16),
                                    border: hasUnread
                                        ? Border.all(color: Colors.red.withOpacity(0.5), width: 2)
                                        : null,
                                  ),
                                  child: Row(
                                    children: [
                                      // Аватар с градиентом
                                      Stack(
                                        clipBehavior: Clip.none,
                                        children: [
                                          Container(
                                            width: 56,
                                            height: 56,
                                            decoration: BoxDecoration(
                                              shape: BoxShape.circle,
                                              gradient: LinearGradient(
                                                begin: Alignment.topLeft,
                                                end: Alignment.bottomRight,
                                                colors: hasUnread
                                                    ? [Colors.red[400]!, Colors.red[700]!]
                                                    : [const Color(0xFF00897B), const Color(0xFF004D40)],
                                              ),
                                              boxShadow: [
                                                BoxShadow(
                                                  color: (hasUnread ? Colors.red : const Color(0xFF004D40))
                                                      .withOpacity(0.4),
                                                  blurRadius: 8,
                                                  offset: const Offset(0, 4),
                                                ),
                                              ],
                                            ),
                                            child: Center(
                                              child: Text(
                                                client.name.isNotEmpty
                                                    ? client.name[0].toUpperCase()
                                                    : client.phone.isNotEmpty ? client.phone[0] : '?',
                                                style: const TextStyle(
                                                  color: Colors.white,
                                                  fontSize: 24,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                            ),
                                          ),
                                          // Индикатор непрочитанных сообщений
                                          if (client.hasUnreadFromClient)
                                            Positioned(
                                              right: -2,
                                              top: -2,
                                              child: Container(
                                                width: 22,
                                                height: 22,
                                                decoration: BoxDecoration(
                                                  color: Colors.red,
                                                  shape: BoxShape.circle,
                                                  border: Border.all(color: Colors.white, width: 2),
                                                  boxShadow: [
                                                    BoxShadow(
                                                      color: Colors.red.withOpacity(0.5),
                                                      blurRadius: 4,
                                                    ),
                                                  ],
                                                ),
                                                child: const Center(
                                                  child: Icon(
                                                    Icons.mail,
                                                    color: Colors.white,
                                                    size: 12,
                                                  ),
                                                ),
                                              ),
                                            ),
                                        ],
                                      ),
                                      const SizedBox(width: 16),
                                      // Информация о клиенте
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Row(
                                              children: [
                                                Expanded(
                                                  child: Text(
                                                    client.name.isNotEmpty ? client.name : 'Без имени',
                                                    style: TextStyle(
                                                      fontSize: 16,
                                                      fontWeight: FontWeight.bold,
                                                      color: hasUnread ? Colors.red[700] : Colors.grey[800],
                                                    ),
                                                    maxLines: 1,
                                                    overflow: TextOverflow.ellipsis,
                                                  ),
                                                ),
                                                if (client.hasUnreadManagement)
                                                  Container(
                                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                                    margin: const EdgeInsets.only(left: 8),
                                                    decoration: BoxDecoration(
                                                      gradient: LinearGradient(
                                                        colors: [Colors.blue[400]!, Colors.blue[700]!],
                                                      ),
                                                      borderRadius: BorderRadius.circular(12),
                                                      boxShadow: [
                                                        BoxShadow(
                                                          color: Colors.blue.withOpacity(0.3),
                                                          blurRadius: 4,
                                                          offset: const Offset(0, 2),
                                                        ),
                                                      ],
                                                    ),
                                                    child: const Row(
                                                      mainAxisSize: MainAxisSize.min,
                                                      children: [
                                                        Icon(Icons.business, size: 12, color: Colors.white),
                                                        SizedBox(width: 4),
                                                        Text(
                                                          'Рук.',
                                                          style: TextStyle(
                                                            color: Colors.white,
                                                            fontSize: 11,
                                                            fontWeight: FontWeight.bold,
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                              ],
                                            ),
                                            const SizedBox(height: 6),
                                            Row(
                                              children: [
                                                Icon(
                                                  Icons.phone_rounded,
                                                  size: 16,
                                                  color: Colors.grey[500],
                                                ),
                                                const SizedBox(width: 6),
                                                Text(
                                                  client.phone,
                                                  style: TextStyle(
                                                    fontSize: 14,
                                                    color: Colors.grey[600],
                                                  ),
                                                ),
                                                const SizedBox(width: 12),
                                                Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                                  decoration: BoxDecoration(
                                                    gradient: LinearGradient(
                                                      colors: client.freeDrinksGiven > 0
                                                          ? [Colors.teal[400]!, Colors.teal[600]!]
                                                          : [Colors.grey[400]!, Colors.grey[500]!],
                                                    ),
                                                    borderRadius: BorderRadius.circular(10),
                                                    boxShadow: [
                                                      BoxShadow(
                                                        color: (client.freeDrinksGiven > 0 ? Colors.teal : Colors.grey).withOpacity(0.3),
                                                        blurRadius: 4,
                                                        offset: const Offset(0, 2),
                                                      ),
                                                    ],
                                                  ),
                                                  child: Row(
                                                    mainAxisSize: MainAxisSize.min,
                                                    children: [
                                                      const Icon(Icons.local_cafe, size: 12, color: Colors.white),
                                                      const SizedBox(width: 4),
                                                      Text(
                                                        '${client.freeDrinksGiven}',
                                                        style: const TextStyle(
                                                          color: Colors.white,
                                                          fontSize: 11,
                                                          fontWeight: FontWeight.bold,
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              ],
                                            ),
                                            if (hasUnread) ...[
                                              const SizedBox(height: 8),
                                              Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                                decoration: BoxDecoration(
                                                  color: Colors.red[50],
                                                  borderRadius: BorderRadius.circular(8),
                                                  border: Border.all(color: Colors.red[200]!),
                                                ),
                                                child: Row(
                                                  mainAxisSize: MainAxisSize.min,
                                                  children: [
                                                    Icon(Icons.mark_email_unread, size: 14, color: Colors.red[600]),
                                                    const SizedBox(width: 4),
                                                    Text(
                                                      'Новое сообщение',
                                                      style: TextStyle(
                                                        fontSize: 12,
                                                        color: Colors.red[700],
                                                        fontWeight: FontWeight.w600,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ],
                                          ],
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      // Стрелка
                                      Container(
                                        width: 36,
                                        height: 36,
                                        decoration: BoxDecoration(
                                          color: Colors.grey[100],
                                          borderRadius: BorderRadius.circular(10),
                                        ),
                                        child: Icon(
                                          Icons.chevron_right_rounded,
                                          color: Colors.grey[500],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}


