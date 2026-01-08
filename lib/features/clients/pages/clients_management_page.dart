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
                          return Card(
                            elevation: 2,
                            margin: const EdgeInsets.only(bottom: 8),
                            child: ListTile(
                              leading: Stack(
                                clipBehavior: Clip.none,
                                children: [
                                  CircleAvatar(
                                    backgroundColor: const Color(0xFF004D40),
                                    child: Text(
                                      client.name.isNotEmpty
                                          ? client.name[0].toUpperCase()
                                          : client.phone[0],
                                      style: const TextStyle(color: Colors.white),
                                    ),
                                  ),
                                  if (client.hasUnreadFromClient)
                                    Positioned(
                                      right: -4,
                                      top: -4,
                                      child: Container(
                                        width: 20,
                                        height: 20,
                                        decoration: const BoxDecoration(
                                          color: Colors.red,
                                          shape: BoxShape.circle,
                                        ),
                                        child: const Center(
                                          child: Text(
                                            '!',
                                            style: TextStyle(
                                              color: Colors.white,
                                              fontWeight: FontWeight.bold,
                                              fontSize: 14,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                              title: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      client.name.isNotEmpty ? client.name : 'Без имени',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: client.hasUnreadFromClient || client.hasUnreadManagement
                                            ? Colors.red
                                            : null,
                                      ),
                                    ),
                                  ),
                                  if (client.hasUnreadManagement)
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      margin: const EdgeInsets.only(left: 4),
                                      decoration: BoxDecoration(
                                        color: Colors.blue,
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: const [
                                          Icon(Icons.business, size: 12, color: Colors.white),
                                          SizedBox(width: 2),
                                          Text(
                                            'Рук.',
                                            style: TextStyle(
                                              color: Colors.white,
                                              fontSize: 10,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                ],
                              ),
                              subtitle: Text(client.phone),
                              trailing: const Icon(Icons.chevron_right),
                              onTap: () => _showClientActions(client),
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


