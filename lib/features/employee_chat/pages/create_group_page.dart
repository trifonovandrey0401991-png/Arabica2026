import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../models/employee_chat_model.dart';
import '../services/employee_chat_service.dart';
import '../../employees/pages/employees_page.dart' show Employee;
import '../../employees/services/employee_service.dart';

/// Страница создания группы
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
      // Загружаем сотрудников и клиентов параллельно
      final results = await Future.wait([
        EmployeeService.getEmployees(),
        EmployeeChatService.getClientsForGroupSelection(),
      ]);

      final employees = results[0] as List<Employee>;
      final clients = results[1] as List<ChatClient>;

      // Исключаем создателя из списка
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
      // Загружаем фото если выбрано
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
      appBar: AppBar(
        title: const Text('Создать группу'),
        backgroundColor: const Color(0xFF004D40),
        foregroundColor: Colors.white,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // Аватар группы
                _buildGroupAvatar(),

                // Название группы
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: TextField(
                    controller: _nameController,
                    decoration: const InputDecoration(
                      labelText: 'Название группы',
                      hintText: 'Например: VIP клиенты',
                      prefixIcon: Icon(Icons.group),
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),

                // Поиск участников
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: TextField(
                    controller: _searchController,
                    onChanged: (v) => setState(() => _searchQuery = v.toLowerCase()),
                    decoration: const InputDecoration(
                      hintText: 'Поиск по имени или телефону...',
                      prefixIcon: Icon(Icons.search),
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),

                // Выбранные участники (chips)
                if (_selectedParticipants.isNotEmpty) _buildSelectedChips(),

                const SizedBox(height: 8),

                // Список для выбора
                Expanded(
                  child: _buildParticipantsList(),
                ),
              ],
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _selectedParticipants.isEmpty || _isCreating ? null : _createGroup,
        backgroundColor: _selectedParticipants.isEmpty || _isCreating
            ? Colors.grey
            : const Color(0xFF004D40),
        icon: _isCreating
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
              )
            : const Icon(Icons.check, color: Colors.white),
        label: Text(
          _isCreating ? 'Создание...' : 'Создать (${_selectedParticipants.length})',
          style: const TextStyle(color: Colors.white),
        ),
      ),
    );
  }

  Widget _buildGroupAvatar() {
    return GestureDetector(
      onTap: _pickImage,
      child: Container(
        margin: const EdgeInsets.all(16),
        width: 100,
        height: 100,
        decoration: BoxDecoration(
          color: Colors.grey[200],
          shape: BoxShape.circle,
          image: _selectedImage != null
              ? DecorationImage(
                  image: FileImage(_selectedImage!),
                  fit: BoxFit.cover,
                )
              : null,
        ),
        child: _selectedImage == null
            ? const Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.camera_alt, size: 32, color: Colors.grey),
                  Text('Фото', style: TextStyle(color: Colors.grey, fontSize: 12)),
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
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: _selectedParticipants.length,
        itemBuilder: (context, index) {
          final phone = _selectedParticipants[index];
          final name = _getParticipantName(phone);
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Chip(
              label: Text(name, style: const TextStyle(fontSize: 12)),
              deleteIcon: const Icon(Icons.close, size: 16),
              onDeleted: () {
                setState(() {
                  _selectedParticipants.remove(phone);
                });
              },
              backgroundColor: const Color(0xFF004D40).withOpacity(0.1),
            ),
          );
        },
      ),
    );
  }

  String _getParticipantName(String phone) {
    final normalizedPhone = phone.replaceAll(RegExp(r'[\s+]'), '');

    // Ищем в сотрудниках
    for (final e in _employees) {
      final empPhone = (e.phone ?? '').replaceAll(RegExp(r'[\s+]'), '');
      if (empPhone == normalizedPhone) {
        return e.name ?? phone;
      }
    }

    // Ищем в клиентах
    for (final c in _clients) {
      final clientPhone = c.phone.replaceAll(RegExp(r'[\s+]'), '');
      if (clientPhone == normalizedPhone) {
        return c.displayName;
      }
    }

    return phone;
  }

  Widget _buildParticipantsList() {
    // Фильтруем по поиску
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
      return const Center(
        child: Text('Нет участников для отображения'),
      );
    }

    return ListView(
      children: [
        // Секция сотрудников
        if (filteredEmployees.isNotEmpty) ...[
          Container(
            color: Colors.grey[100],
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: const Row(
              children: [
                Icon(Icons.badge, size: 20, color: Color(0xFF004D40)),
                SizedBox(width: 8),
                Text(
                  'Сотрудники',
                  style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF004D40)),
                ),
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

        // Секция клиентов
        if (filteredClients.isNotEmpty) ...[
          Container(
            color: Colors.grey[100],
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: const Row(
              children: [
                Icon(Icons.person, size: 20, color: Colors.green),
                SizedBox(width: 8),
                Text(
                  'Клиенты',
                  style: TextStyle(fontWeight: FontWeight.bold, color: Colors.green),
                ),
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

    return CheckboxListTile(
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
      title: Text(name),
      subtitle: subtitle != null && subtitle.isNotEmpty ? Text(subtitle) : null,
      secondary: CircleAvatar(
        backgroundColor: isEmployee ? const Color(0xFF004D40) : Colors.green,
        child: Icon(
          isEmployee ? Icons.badge : Icons.person,
          color: Colors.white,
          size: 20,
        ),
      ),
      activeColor: const Color(0xFF004D40),
    );
  }
}
