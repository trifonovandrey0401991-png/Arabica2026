import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../services/employee_chat_service.dart';
import '../../employees/pages/employees_page.dart' show Employee;
import '../../employees/services/employee_service.dart';

/// Страница создания группы — dark emerald стиль
class CreateGroupPage extends StatefulWidget {
  final String creatorPhone;
  final String creatorName;

  const CreateGroupPage({
    super.key,
    required this.creatorPhone,
    required this.creatorName,
  });

  @override
  State<CreateGroupPage> createState() => _CreateGroupPageState();
}

class _CreateGroupPageState extends State<CreateGroupPage> {
  // Dark emerald palette
  static const Color _emerald = Color(0xFF1A4D4D);
  static const Color _emeraldDark = Color(0xFF0D2E2E);
  static const Color _night = Color(0xFF051515);

  final _nameController = TextEditingController();
  final _searchController = TextEditingController();
  File? _selectedImage;
  final List<String> _selectedParticipants = [];
  bool _isCreating = false;
  bool _isLoading = true;

  List<Employee> _employees = [];
  List<ChatClient> _clients = [];
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _loadParticipants();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadParticipants() async {
    setState(() => _isLoading = true);
    try {
      final results = await Future.wait([
        EmployeeService.getEmployees(),
        EmployeeChatService.getClientsForGroupSelection(),
      ]);

      final employees = results[0] as List<Employee>;
      final clients = results[1] as List<ChatClient>;

      final normalizedCreator = widget.creatorPhone.replaceAll(RegExp(r'[\s+]'), '');
      _employees = employees.where((e) {
        final empPhone = (e.phone ?? '').replaceAll(RegExp(r'[\s+]'), '');
        return empPhone != normalizedCreator;
      }).toList();

      _clients = clients.where((c) {
        final clientPhone = c.phone.replaceAll(RegExp(r'[\s+]'), '');
        return clientPhone != normalizedCreator;
      }).toList();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка загрузки: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 512,
      maxHeight: 512,
      imageQuality: 80,
    );

    if (pickedFile != null) {
      setState(() {
        _selectedImage = File(pickedFile.path);
      });
    }
  }

  Future<void> _createGroup() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Введите название группы')),
      );
      return;
    }

    if (_selectedParticipants.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Выберите хотя бы одного участника')),
      );
      return;
    }

    setState(() => _isCreating = true);

    try {
      String? imageUrl;
      if (_selectedImage != null) {
        imageUrl = await EmployeeChatService.uploadGroupPhoto(_selectedImage!);
      }

      final chat = await EmployeeChatService.createGroup(
        creatorPhone: widget.creatorPhone,
        creatorName: widget.creatorName,
        name: name,
        imageUrl: imageUrl,
        participants: _selectedParticipants,
      );

      if (chat != null && mounted) {
        Navigator.pop(context, chat);
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Ошибка создания группы')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isCreating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _night,
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
              // AppBar
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: Icon(Icons.arrow_back_ios_new_rounded,
                          color: Colors.white.withOpacity(0.8), size: 22),
                    ),
                    Expanded(
                      child: Center(
                        child: Text(
                          'Создать группу',
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.95),
                            fontSize: 20,
                            fontWeight: FontWeight.w400,
                            letterSpacing: 1,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 48),
                  ],
                ),
              ),
              // Body
              Expanded(
                child: _isLoading
                    ? const Center(child: CircularProgressIndicator(color: Colors.white))
                    : Column(
                        children: [
                          // Аватар
                          _buildGroupAvatar(),
                          // Название
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            child: Container(
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.06),
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(color: Colors.white.withOpacity(0.12)),
                              ),
                              child: TextField(
                                controller: _nameController,
                                style: TextStyle(color: Colors.white.withOpacity(0.9)),
                                cursorColor: Colors.white,
                                decoration: InputDecoration(
                                  labelText: 'Название группы',
                                  labelStyle: TextStyle(color: Colors.white.withOpacity(0.4)),
                                  hintText: 'Например: VIP клиенты',
                                  hintStyle: TextStyle(color: Colors.white.withOpacity(0.2)),
                                  prefixIcon: Icon(Icons.group, color: Colors.white.withOpacity(0.4)),
                                  border: InputBorder.none,
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          // Поиск
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            child: Container(
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.06),
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(color: Colors.white.withOpacity(0.12)),
                              ),
                              child: TextField(
                                controller: _searchController,
                                onChanged: (v) => setState(() => _searchQuery = v.toLowerCase()),
                                style: TextStyle(color: Colors.white.withOpacity(0.9)),
                                cursorColor: Colors.white,
                                decoration: InputDecoration(
                                  hintText: 'Поиск по имени или телефону...',
                                  hintStyle: TextStyle(color: Colors.white.withOpacity(0.3)),
                                  prefixIcon: Icon(Icons.search, color: Colors.white.withOpacity(0.4)),
                                  border: InputBorder.none,
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                                ),
                              ),
                            ),
                          ),
                          // Чипсы
                          if (_selectedParticipants.isNotEmpty) _buildSelectedChips(),
                          const SizedBox(height: 8),
                          // Список
                          Expanded(child: _buildParticipantsList()),
                        ],
                      ),
              ),
            ],
          ),
        ),
      ),
      floatingActionButton: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        decoration: BoxDecoration(
          color: _selectedParticipants.isEmpty || _isCreating
              ? Colors.grey[700]
              : _emerald,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white.withOpacity(0.15)),
        ),
        child: GestureDetector(
          onTap: _selectedParticipants.isEmpty || _isCreating ? null : _createGroup,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _isCreating
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                    )
                  : Icon(Icons.check, color: Colors.white.withOpacity(0.9)),
              const SizedBox(width: 10),
              Text(
                _isCreating ? 'Создание...' : 'Создать (${_selectedParticipants.length})',
                style: TextStyle(color: Colors.white.withOpacity(0.9), fontWeight: FontWeight.w500),
              ),
            ],
          ),
        ),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
    );
  }

  Widget _buildGroupAvatar() {
    return GestureDetector(
      onTap: _pickImage,
      child: Container(
        margin: const EdgeInsets.all(16),
        width: 90,
        height: 90,
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.08),
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white.withOpacity(0.15)),
          image: _selectedImage != null
              ? DecorationImage(image: FileImage(_selectedImage!), fit: BoxFit.cover)
              : null,
        ),
        child: _selectedImage == null
            ? Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.camera_alt, size: 28, color: Colors.white.withOpacity(0.4)),
                  Text('Фото', style: TextStyle(color: Colors.white.withOpacity(0.3), fontSize: 11)),
                ],
              )
            : null,
      ),
    );
  }

  Widget _buildSelectedChips() {
    return Container(
      height: 50,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      margin: const EdgeInsets.only(top: 8),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: _selectedParticipants.length,
        itemBuilder: (context, index) {
          final phone = _selectedParticipants[index];
          final name = _getParticipantName(phone);
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: _emerald.withOpacity(0.4),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: _emerald.withOpacity(0.6)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(name, style: TextStyle(fontSize: 12, color: Colors.white.withOpacity(0.9))),
                  const SizedBox(width: 6),
                  GestureDetector(
                    onTap: () => setState(() => _selectedParticipants.remove(phone)),
                    child: Icon(Icons.close, size: 16, color: Colors.white.withOpacity(0.6)),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  String _getParticipantName(String phone) {
    final normalizedPhone = phone.replaceAll(RegExp(r'[\s+]'), '');

    for (final e in _employees) {
      final empPhone = (e.phone ?? '').replaceAll(RegExp(r'[\s+]'), '');
      if (empPhone == normalizedPhone) {
        return e.name ?? phone;
      }
    }

    for (final c in _clients) {
      final clientPhone = c.phone.replaceAll(RegExp(r'[\s+]'), '');
      if (clientPhone == normalizedPhone) {
        return c.displayName;
      }
    }

    return phone;
  }

  Widget _buildParticipantsList() {
    final filteredEmployees = _employees.where((e) {
      final name = (e.name ?? '').toLowerCase();
      final phone = (e.phone ?? '').toLowerCase();
      return name.contains(_searchQuery) || phone.contains(_searchQuery);
    }).toList();

    final filteredClients = _clients.where((c) {
      final name = (c.name ?? '').toLowerCase();
      final phone = c.phone.toLowerCase();
      return name.contains(_searchQuery) || phone.contains(_searchQuery);
    }).toList();

    if (filteredEmployees.isEmpty && filteredClients.isEmpty) {
      return Center(
        child: Text('Нет участников для отображения',
            style: TextStyle(color: Colors.white.withOpacity(0.4))),
      );
    }

    return ListView(
      padding: const EdgeInsets.only(bottom: 80),
      children: [
        if (filteredEmployees.isNotEmpty) ...[
          Container(
            color: Colors.white.withOpacity(0.04),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                Icon(Icons.badge, size: 20, color: Colors.white.withOpacity(0.6)),
                const SizedBox(width: 8),
                Text('Сотрудники',
                    style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white.withOpacity(0.7))),
              ],
            ),
          ),
          ...filteredEmployees.map((e) => _buildParticipantTile(
                phone: e.phone ?? '',
                name: e.name ?? e.phone ?? '',
                subtitle: e.position ?? '',
                isEmployee: true,
              )),
        ],
        if (filteredClients.isNotEmpty) ...[
          Container(
            color: Colors.white.withOpacity(0.04),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                Icon(Icons.person, size: 20, color: Colors.green[400]),
                const SizedBox(width: 8),
                Text('Клиенты',
                    style: TextStyle(fontWeight: FontWeight.bold, color: Colors.green[400])),
              ],
            ),
          ),
          ...filteredClients.map((c) => _buildParticipantTile(
                phone: c.phone,
                name: c.displayName,
                subtitle: 'Баллы: ${c.points}',
                isEmployee: false,
              )),
        ],
      ],
    );
  }

  Widget _buildParticipantTile({
    required String phone,
    required String name,
    String? subtitle,
    required bool isEmployee,
  }) {
    final normalizedPhone = phone.replaceAll(RegExp(r'[\s+]'), '');
    final isSelected = _selectedParticipants.contains(normalizedPhone);

    return Container(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: Colors.white.withOpacity(0.05))),
      ),
      child: CheckboxListTile(
        value: isSelected,
        onChanged: (v) {
          setState(() {
            if (v == true) {
              _selectedParticipants.add(normalizedPhone);
            } else {
              _selectedParticipants.remove(normalizedPhone);
            }
          });
        },
        title: Text(name, style: TextStyle(color: Colors.white.withOpacity(0.9))),
        subtitle: subtitle != null && subtitle.isNotEmpty
            ? Text(subtitle, style: TextStyle(color: Colors.white.withOpacity(0.4)))
            : null,
        secondary: CircleAvatar(
          backgroundColor: isEmployee ? _emerald : Colors.green.withOpacity(0.3),
          child: Icon(
            isEmployee ? Icons.badge : Icons.person,
            color: Colors.white.withOpacity(0.8),
            size: 20,
          ),
        ),
        activeColor: _emerald,
        checkColor: Colors.white,
      ),
    );
  }
}
