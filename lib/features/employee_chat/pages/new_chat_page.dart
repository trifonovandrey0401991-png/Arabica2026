import 'package:flutter/material.dart';
import '../models/employee_chat_model.dart';
import '../services/employee_chat_service.dart';
import '../../employees/services/employee_service.dart';
import '../../employees/pages/employees_page.dart' show Employee;
import '../../shops/services/shop_service.dart';
import '../../shops/models/shop_model.dart';
import 'create_group_page.dart';

/// Страница создания нового чата
class NewChatPage extends StatefulWidget {
  final String userPhone;
  final String userName;
  final bool isAdmin;

  const NewChatPage({
    super.key,
    required this.userPhone,
    required this.userName,
    this.isAdmin = false,
  });

  @override
  State<NewChatPage> createState() => _NewChatPageState();
}

class _NewChatPageState extends State<NewChatPage> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  List<Employee> _employees = [];
  List<Shop> _shops = [];
  bool _isLoading = true;
  String _searchQuery = '';

  int get _tabCount => widget.isAdmin ? 4 : 3;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _tabCount, vsync: this);
    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);

    try {
      final employees = await EmployeeService.getEmployees();
      final shops = await ShopService.getShops();

      if (mounted) {
        setState(() {
          // Исключаем себя из списка сотрудников для личных чатов
          _employees = employees.where((e) => e.phone != widget.userPhone).toList();
          _shops = shops;
          _isLoading = false;
        });
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

  Future<void> _openGeneralChat() async {
    // Общий чат уже существует, просто возвращаем его
    final chat = EmployeeChat(
      id: 'general',
      type: EmployeeChatType.general,
      name: 'Общий чат',
    );
    if (mounted) {
      Navigator.pop(context, chat);
    }
  }

  Future<void> _openPrivateChat(Employee employee) async {
    setState(() => _isLoading = true);

    try {
      final chat = await EmployeeChatService.getOrCreatePrivateChat(
        widget.userPhone,
        employee.phone ?? '',
      );

      if (chat != null && mounted) {
        // Устанавливаем имя собеседника
        final chatWithName = EmployeeChat(
          id: chat.id,
          type: chat.type,
          name: employee.name,
          participants: chat.participants,
        );
        Navigator.pop(context, chatWithName);
      } else {
        if (mounted) {
          setState(() => _isLoading = false);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Ошибка создания чата'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _openShopChat(Shop shop) async {
    setState(() => _isLoading = true);

    try {
      final chat = await EmployeeChatService.getOrCreateShopChat(shop.address);

      if (chat != null && mounted) {
        Navigator.pop(context, chat);
      } else {
        if (mounted) {
          setState(() => _isLoading = false);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Ошибка создания чата'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _openCreateGroup() async {
    final result = await Navigator.push<EmployeeChat>(
      context,
      MaterialPageRoute(
        builder: (context) => CreateGroupPage(
          creatorPhone: widget.userPhone,
          creatorName: widget.userName,
        ),
      ),
    );

    if (result != null && mounted) {
      Navigator.pop(context, result);
    }
  }

  List<Employee> get _filteredEmployees {
    if (_searchQuery.isEmpty) return _employees;
    final query = _searchQuery.toLowerCase();
    return _employees.where((e) {
      return e.name.toLowerCase().contains(query) ||
             (e.phone?.contains(query) ?? false);
    }).toList();
  }

  List<Shop> get _filteredShops {
    if (_searchQuery.isEmpty) return _shops;
    final query = _searchQuery.toLowerCase();
    return _shops.where((s) {
      return s.address.toLowerCase().contains(query);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Новый чат'),
        backgroundColor: const Color(0xFF004D40),
        foregroundColor: Colors.white,
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          tabs: [
            const Tab(icon: Icon(Icons.public), text: 'Общий'),
            const Tab(icon: Icon(Icons.person), text: 'Личный'),
            const Tab(icon: Icon(Icons.store), text: 'Магазин'),
            if (widget.isAdmin)
              const Tab(icon: Icon(Icons.group_add), text: 'Группа'),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: TextField(
                    decoration: InputDecoration(
                      hintText: 'Поиск...',
                      prefixIcon: const Icon(Icons.search),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      filled: true,
                      fillColor: Colors.grey[100],
                    ),
                    onChanged: (value) {
                      setState(() => _searchQuery = value);
                    },
                  ),
                ),
                Expanded(
                  child: TabBarView(
                    controller: _tabController,
                    children: [
                      _buildGeneralTab(),
                      _buildPrivateTab(),
                      _buildShopTab(),
                      if (widget.isAdmin) _buildGroupTab(),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildGeneralTab() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 100,
            height: 100,
            decoration: BoxDecoration(
              color: Colors.blue[100],
              shape: BoxShape.circle,
            ),
            child: const Center(
              child: Text(
                '🌐',
                style: TextStyle(fontSize: 48),
              ),
            ),
          ),
          const SizedBox(height: 24),
          const Text(
            'Общий чат',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Чат для всех сотрудников',
            style: TextStyle(
              fontSize: 16,
              color: Colors.grey[600],
            ),
          ),
          const SizedBox(height: 32),
          ElevatedButton.icon(
            onPressed: _openGeneralChat,
            icon: const Icon(Icons.arrow_forward),
            label: const Text('Открыть чат'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF004D40),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPrivateTab() {
    final employees = _filteredEmployees;

    if (employees.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.person_off, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(
              _searchQuery.isEmpty ? 'Нет сотрудников' : 'Ничего не найдено',
              style: TextStyle(fontSize: 18, color: Colors.grey[600]),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      itemCount: employees.length,
      itemBuilder: (context, index) {
        final employee = employees[index];
        return ListTile(
          leading: CircleAvatar(
            backgroundColor: Colors.green[100],
            child: Text(
              employee.name.isNotEmpty ? employee.name[0].toUpperCase() : '?',
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                color: Color(0xFF004D40),
              ),
            ),
          ),
          title: Text(employee.name),
          subtitle: Text(employee.phone ?? ''),
          trailing: const Icon(Icons.chat_bubble_outline),
          onTap: () => _openPrivateChat(employee),
        );
      },
    );
  }

  Widget _buildShopTab() {
    final shops = _filteredShops;

    if (shops.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.store_mall_directory, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(
              _searchQuery.isEmpty ? 'Нет магазинов' : 'Ничего не найдено',
              style: TextStyle(fontSize: 18, color: Colors.grey[600]),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      itemCount: shops.length,
      itemBuilder: (context, index) {
        final shop = shops[index];
        return ListTile(
          leading: CircleAvatar(
            backgroundColor: Colors.orange[100],
            child: const Text(
              '🏪',
              style: TextStyle(fontSize: 20),
            ),
          ),
          title: Text(shop.address),
          trailing: const Icon(Icons.chat_bubble_outline),
          onTap: () => _openShopChat(shop),
        );
      },
    );
  }

  Widget _buildGroupTab() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 100,
            height: 100,
            decoration: BoxDecoration(
              color: Colors.purple[100],
              shape: BoxShape.circle,
            ),
            child: const Center(
              child: Text(
                '👥',
                style: TextStyle(fontSize: 48),
              ),
            ),
          ),
          const SizedBox(height: 24),
          const Text(
            'Создать группу',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Text(
              'Группа с любыми участниками: сотрудниками и клиентами',
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey[600],
              ),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 32),
          ElevatedButton.icon(
            onPressed: _openCreateGroup,
            icon: const Icon(Icons.add),
            label: const Text('Создать группу'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF004D40),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
            ),
          ),
        ],
      ),
    );
  }
}
