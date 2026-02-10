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
  static const Color _emerald = Color(0xFF1A4D4D);
  static const Color _emeraldDark = Color(0xFF0D2E2E);
  static const Color _night = Color(0xFF051515);
  static const Color _gold = Color(0xFFD4AF37);

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
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          constraints: const BoxConstraints(maxWidth: 400),
          decoration: BoxDecoration(
            color: _emeraldDark,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white.withOpacity(0.08)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Шапка
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [_emerald, _emeraldDark],
                  ),
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(20),
                    topRight: Radius.circular(20),
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: _gold.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: _gold.withOpacity(0.3)),
                      ),
                      child: const Icon(Icons.person, color: _gold, size: 24),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Text(
                        client.name.isNotEmpty ? client.name : client.phone,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close_rounded),
                      color: Colors.white70,
                      style: IconButton.styleFrom(
                        backgroundColor: Colors.white.withOpacity(0.1),
                      ),
                    ),
                  ],
                ),
              ),
              // Пункты меню
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Column(
                  children: [
                    _buildActionTile(
                      icon: Icons.message,
                      color: _gold,
                      title: 'Отправить сообщение',
                      onTap: () => Navigator.pop(context, 'send'),
                    ),
                    _buildActionTile(
                      icon: Icons.chat,
                      color: const Color(0xFF4FC3F7),
                      title: 'Начать диалог',
                      onTap: () => Navigator.pop(context, 'chat'),
                    ),
                    _buildActionTile(
                      icon: Icons.business,
                      color: client.hasUnreadManagement ? Colors.orange : const Color(0xFF81C784),
                      title: 'Связь с руководством',
                      badge: client.hasUnreadManagement ? 'NEW' : null,
                      onTap: () => Navigator.pop(context, 'management'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
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

  Widget _buildActionTile({
    required IconData icon,
    required Color color,
    required String title,
    String? badge,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: color.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: color.withOpacity(0.3)),
                ),
                child: Icon(icon, color: color, size: 20),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 15,
                    color: Colors.white.withOpacity(0.9),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              if (badge != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.orange.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.orange.withOpacity(0.4)),
                  ),
                  child: Text(
                    badge,
                    style: const TextStyle(
                      color: Colors.orange,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              const SizedBox(width: 8),
              Icon(Icons.chevron_right, color: Colors.white.withOpacity(0.3), size: 20),
            ],
          ),
        ),
      ),
    );
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
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text('Клиенты', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(
            icon: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: _gold.withOpacity(0.15),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: _gold.withOpacity(0.3)),
              ),
              child: const Icon(Icons.send, size: 18, color: _gold),
            ),
            onPressed: () => _showSendMessageDialog(null),
            tooltip: 'Отправить всем',
          ),
          IconButton(
            icon: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.08),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.white.withOpacity(0.1)),
              ),
              child: Icon(Icons.refresh, size: 18, color: Colors.white.withOpacity(0.7)),
            ),
            onPressed: _loadClients,
            tooltip: 'Обновить',
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [_emerald, _emeraldDark, _night],
            stops: [0.0, 0.3, 1.0],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              // Поиск
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: Colors.white.withOpacity(0.1)),
                  ),
                  child: TextField(
                    controller: _searchController,
                    style: TextStyle(color: Colors.white.withOpacity(0.9)),
                    cursorColor: _gold,
                    decoration: InputDecoration(
                      hintText: 'Поиск по имени или телефону',
                      hintStyle: TextStyle(color: Colors.white.withOpacity(0.3)),
                      prefixIcon: Icon(Icons.search, color: Colors.white.withOpacity(0.4)),
                      suffixIcon: _searchController.text.isNotEmpty
                          ? IconButton(
                              icon: Icon(Icons.clear, color: Colors.white.withOpacity(0.4)),
                              onPressed: () {
                                _searchController.clear();
                              },
                            )
                          : null,
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    ),
                  ),
                ),
              ),
              // Счётчик
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: _gold.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: _gold.withOpacity(0.3)),
                      ),
                      child: Text(
                        '${_filteredClients.length}',
                        style: const TextStyle(
                          color: _gold,
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'клиентов',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.5),
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              // Список
              Expanded(
                child: _isLoading
                    ? Center(
                        child: CircularProgressIndicator(
                          color: _gold.withOpacity(0.7),
                          strokeWidth: 2,
                        ),
                      )
                    : _filteredClients.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(20),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withOpacity(0.06),
                                    borderRadius: BorderRadius.circular(20),
                                    border: Border.all(color: Colors.white.withOpacity(0.08)),
                                  ),
                                  child: Icon(
                                    Icons.people_outline,
                                    size: 48,
                                    color: _gold.withOpacity(0.5),
                                  ),
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  _clients.isEmpty
                                      ? 'Нет клиентов'
                                      : 'Клиенты не найдены',
                                  style: TextStyle(
                                    fontSize: 18,
                                    color: Colors.white.withOpacity(0.7),
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                if (_clients.isEmpty) ...[
                                  const SizedBox(height: 8),
                                  Text(
                                    'Клиенты появятся после регистрации',
                                    style: TextStyle(
                                      fontSize: 14,
                                      color: Colors.white.withOpacity(0.4),
                                    ),
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
                                margin: const EdgeInsets.only(bottom: 10),
                                decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(0.06),
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(
                                    color: hasUnread
                                        ? Colors.red.withOpacity(0.4)
                                        : Colors.white.withOpacity(0.08),
                                    width: hasUnread ? 1.5 : 1,
                                  ),
                                ),
                                child: Material(
                                  color: Colors.transparent,
                                  borderRadius: BorderRadius.circular(14),
                                  child: InkWell(
                                    borderRadius: BorderRadius.circular(14),
                                    onTap: () => _showClientActions(client),
                                    child: Padding(
                                      padding: const EdgeInsets.all(14),
                                      child: Row(
                                        children: [
                                          // Аватар
                                          Stack(
                                            clipBehavior: Clip.none,
                                            children: [
                                              Container(
                                                width: 50,
                                                height: 50,
                                                decoration: BoxDecoration(
                                                  shape: BoxShape.circle,
                                                  gradient: LinearGradient(
                                                    begin: Alignment.topLeft,
                                                    end: Alignment.bottomRight,
                                                    colors: hasUnread
                                                        ? [Colors.red.withOpacity(0.6), Colors.red.withOpacity(0.3)]
                                                        : [_gold.withOpacity(0.3), _emerald],
                                                  ),
                                                  border: Border.all(
                                                    color: hasUnread
                                                        ? Colors.red.withOpacity(0.5)
                                                        : _gold.withOpacity(0.3),
                                                    width: 1.5,
                                                  ),
                                                ),
                                                child: Center(
                                                  child: Text(
                                                    client.name.isNotEmpty
                                                        ? client.name[0].toUpperCase()
                                                        : client.phone.isNotEmpty ? client.phone[0] : '?',
                                                    style: TextStyle(
                                                      color: hasUnread ? Colors.white : _gold,
                                                      fontSize: 20,
                                                      fontWeight: FontWeight.bold,
                                                    ),
                                                  ),
                                                ),
                                              ),
                                              // Индикатор непрочитанных
                                              if (client.hasUnreadFromClient)
                                                Positioned(
                                                  right: -2,
                                                  top: -2,
                                                  child: Container(
                                                    width: 20,
                                                    height: 20,
                                                    decoration: BoxDecoration(
                                                      color: Colors.red,
                                                      shape: BoxShape.circle,
                                                      border: Border.all(color: _emeraldDark, width: 2),
                                                    ),
                                                    child: const Center(
                                                      child: Icon(
                                                        Icons.mail,
                                                        color: Colors.white,
                                                        size: 10,
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                            ],
                                          ),
                                          const SizedBox(width: 14),
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
                                                          fontSize: 15,
                                                          fontWeight: FontWeight.bold,
                                                          color: hasUnread ? Colors.red[300] : Colors.white.withOpacity(0.9),
                                                        ),
                                                        maxLines: 1,
                                                        overflow: TextOverflow.ellipsis,
                                                      ),
                                                    ),
                                                    if (client.hasUnreadManagement)
                                                      Container(
                                                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                                                        margin: const EdgeInsets.only(left: 8),
                                                        decoration: BoxDecoration(
                                                          color: Colors.blue.withOpacity(0.2),
                                                          borderRadius: BorderRadius.circular(8),
                                                          border: Border.all(color: Colors.blue.withOpacity(0.4)),
                                                        ),
                                                        child: const Row(
                                                          mainAxisSize: MainAxisSize.min,
                                                          children: [
                                                            Icon(Icons.business, size: 11, color: Color(0xFF64B5F6)),
                                                            SizedBox(width: 3),
                                                            Text(
                                                              'Рук.',
                                                              style: TextStyle(
                                                                color: Color(0xFF64B5F6),
                                                                fontSize: 10,
                                                                fontWeight: FontWeight.bold,
                                                              ),
                                                            ),
                                                          ],
                                                        ),
                                                      ),
                                                  ],
                                                ),
                                                const SizedBox(height: 5),
                                                Row(
                                                  children: [
                                                    Icon(
                                                      Icons.phone_rounded,
                                                      size: 14,
                                                      color: Colors.white.withOpacity(0.35),
                                                    ),
                                                    const SizedBox(width: 5),
                                                    Text(
                                                      client.phone,
                                                      style: TextStyle(
                                                        fontSize: 13,
                                                        color: Colors.white.withOpacity(0.5),
                                                      ),
                                                    ),
                                                    const SizedBox(width: 10),
                                                    Container(
                                                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                                                      decoration: BoxDecoration(
                                                        color: client.freeDrinksGiven > 0
                                                            ? _gold.withOpacity(0.15)
                                                            : Colors.white.withOpacity(0.06),
                                                        borderRadius: BorderRadius.circular(8),
                                                        border: Border.all(
                                                          color: client.freeDrinksGiven > 0
                                                              ? _gold.withOpacity(0.3)
                                                              : Colors.white.withOpacity(0.1),
                                                        ),
                                                      ),
                                                      child: Row(
                                                        mainAxisSize: MainAxisSize.min,
                                                        children: [
                                                          Icon(
                                                            Icons.local_cafe,
                                                            size: 11,
                                                            color: client.freeDrinksGiven > 0
                                                                ? _gold
                                                                : Colors.white.withOpacity(0.4),
                                                          ),
                                                          const SizedBox(width: 3),
                                                          Text(
                                                            '${client.freeDrinksGiven}',
                                                            style: TextStyle(
                                                              color: client.freeDrinksGiven > 0
                                                                  ? _gold
                                                                  : Colors.white.withOpacity(0.4),
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
                                                  const SizedBox(height: 6),
                                                  Container(
                                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                                    decoration: BoxDecoration(
                                                      color: Colors.red.withOpacity(0.15),
                                                      borderRadius: BorderRadius.circular(6),
                                                      border: Border.all(color: Colors.red.withOpacity(0.3)),
                                                    ),
                                                    child: Row(
                                                      mainAxisSize: MainAxisSize.min,
                                                      children: [
                                                        Icon(Icons.mark_email_unread, size: 12, color: Colors.red[300]),
                                                        const SizedBox(width: 4),
                                                        Text(
                                                          'Новое сообщение',
                                                          style: TextStyle(
                                                            fontSize: 11,
                                                            color: Colors.red[300],
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
                                            width: 32,
                                            height: 32,
                                            decoration: BoxDecoration(
                                              color: Colors.white.withOpacity(0.06),
                                              borderRadius: BorderRadius.circular(8),
                                              border: Border.all(color: Colors.white.withOpacity(0.08)),
                                            ),
                                            child: Icon(
                                              Icons.chevron_right_rounded,
                                              color: Colors.white.withOpacity(0.3),
                                              size: 20,
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
        ),
      ),
    );
  }
}
