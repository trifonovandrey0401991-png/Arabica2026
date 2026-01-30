import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../models/employee_chat_model.dart';
import '../services/employee_chat_service.dart';
import '../../employees/pages/employees_page.dart' show Employee;
import '../../employees/services/employee_service.dart';

/// Страница информации о группе
class GroupInfoPage extends StatefulWidget {
  final EmployeeChat chat;
  final String currentUserPhone;

  const GroupInfoPage({
    super.key,
    required this.chat,
    required this.currentUserPhone,
  });

  @override
  State<GroupInfoPage> createState() => _GroupInfoPageState();
}

class _GroupInfoPageState extends State<GroupInfoPage> {
  late EmployeeChat _chat;
  final _nameController = TextEditingController();
  bool _isEditing = false;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _chat = widget.chat;
    _nameController.text = _chat.name;
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  bool get _isCreator => _chat.isCreator(widget.currentUserPhone);

  Future<void> _updateGroupName() async {
    final newName = _nameController.text.trim();
    if (newName.isEmpty || newName == _chat.name) {
      setState(() => _isEditing = false);
      return;
    }

    setState(() => _isLoading = true);
    try {
      final updated = await EmployeeChatService.updateGroup(
        groupId: _chat.id,
        requesterPhone: widget.currentUserPhone,
        name: newName,
      );
      if (updated != null && mounted) {
        setState(() {
          _chat = updated;
          _isEditing = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Название обновлено')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _changePhoto() async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 512,
      maxHeight: 512,
      imageQuality: 80,
    );

    if (pickedFile == null) return;

    setState(() => _isLoading = true);
    try {
      // Загружаем фото
      final imageUrl = await EmployeeChatService.uploadGroupPhoto(File(pickedFile.path));
      if (imageUrl == null) throw Exception('Ошибка загрузки фото');

      // Обновляем группу
      final updated = await EmployeeChatService.updateGroup(
        groupId: _chat.id,
        requesterPhone: widget.currentUserPhone,
        imageUrl: imageUrl,
      );

      if (updated != null && mounted) {
        setState(() => _chat = updated);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Фото обновлено')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _addMembers() async {
    // Открываем диалог выбора участников
    final result = await showModalBottomSheet<List<String>>(
      context: context,
      isScrollControlled: true,
      builder: (context) => _AddMembersSheet(
        existingParticipants: _chat.participants,
      ),
    );

    if (result == null || result.isEmpty) return;

    setState(() => _isLoading = true);
    try {
      final success = await EmployeeChatService.addGroupMembers(
        groupId: _chat.id,
        requesterPhone: widget.currentUserPhone,
        phones: result,
      );

      if (success && mounted) {
        // Обновляем информацию о группе
        final updated = await EmployeeChatService.getGroupInfo(_chat.id);
        if (updated != null) {
          setState(() => _chat = updated);
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Добавлено участников: ${result.length}')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _removeMember(String phone) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Удалить участника?'),
        content: Text('Удалить ${_chat.getParticipantName(phone)} из группы?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Отмена'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Удалить'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _isLoading = true);
    try {
      final success = await EmployeeChatService.removeGroupMember(
        groupId: _chat.id,
        requesterPhone: widget.currentUserPhone,
        phone: phone,
      );

      if (success && mounted) {
        final updated = await EmployeeChatService.getGroupInfo(_chat.id);
        if (updated != null) {
          setState(() => _chat = updated);
        }
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Участник удалён')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _leaveGroup() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Выйти из группы?'),
        content: const Text('Вы уверены, что хотите покинуть эту группу?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Отмена'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Выйти'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _isLoading = true);
    try {
      final success = await EmployeeChatService.leaveGroup(
        _chat.id,
        widget.currentUserPhone,
      );

      if (success && mounted) {
        Navigator.pop(context, 'left'); // Сигнал что вышли из группы
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _deleteGroup() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Удалить группу?'),
        content: const Text(
          'Группа будет удалена для всех участников. '
          'Это действие нельзя отменить.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Отмена'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Удалить'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _isLoading = true);
    try {
      final success = await EmployeeChatService.deleteGroup(
        _chat.id,
        widget.currentUserPhone,
      );

      if (success && mounted) {
        Navigator.pop(context, 'deleted'); // Сигнал что группа удалена
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('О группе'),
        backgroundColor: const Color(0xFF004D40),
        foregroundColor: Colors.white,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              children: [
                // Шапка с аватаром и названием
                _buildHeader(),

                const Divider(),

                // Участники
                _buildParticipantsSection(),

                const Divider(),

                // Действия
                _buildActionsSection(),
              ],
            ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          // Аватар
          GestureDetector(
            onTap: _isCreator ? _changePhoto : null,
            child: Stack(
              children: [
                CircleAvatar(
                  radius: 50,
                  backgroundColor: Colors.grey[200],
                  backgroundImage: _chat.imageUrl != null
                      ? NetworkImage(_chat.imageUrl!)
                      : null,
                  child: _chat.imageUrl == null
                      ? const Icon(Icons.group, size: 50, color: Colors.grey)
                      : null,
                ),
                if (_isCreator)
                  Positioned(
                    bottom: 0,
                    right: 0,
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: const BoxDecoration(
                        color: Color(0xFF004D40),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.camera_alt,
                        size: 16,
                        color: Colors.white,
                      ),
                    ),
                  ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // Название
          if (_isEditing)
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _nameController,
                    autofocus: true,
                    decoration: const InputDecoration(
                      hintText: 'Название группы',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.check, color: Color(0xFF004D40)),
                  onPressed: _updateGroupName,
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.grey),
                  onPressed: () {
                    _nameController.text = _chat.name;
                    setState(() => _isEditing = false);
                  },
                ),
              ],
            )
          else
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  _chat.name,
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (_isCreator)
                  IconButton(
                    icon: const Icon(Icons.edit, size: 20),
                    onPressed: () => setState(() => _isEditing = true),
                  ),
              ],
            ),

          const SizedBox(height: 8),

          Text(
            '${_chat.participantsCount} участников',
            style: TextStyle(color: Colors.grey[600]),
          ),

          if (_chat.creatorName != null)
            Text(
              'Создатель: ${_chat.creatorName}',
              style: TextStyle(color: Colors.grey[600], fontSize: 12),
            ),
        ],
      ),
    );
  }

  Widget _buildParticipantsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Участники (${_chat.participantsCount})',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              if (_isCreator)
                TextButton.icon(
                  onPressed: _addMembers,
                  icon: const Icon(Icons.person_add),
                  label: const Text('Добавить'),
                ),
            ],
          ),
        ),
        ..._chat.participants.map((phone) => _buildParticipantTile(phone)),
      ],
    );
  }

  Widget _buildParticipantTile(String phone) {
    final name = _chat.getParticipantName(phone);
    final isCreator = phone == _chat.creatorPhone;
    final isMe = phone.replaceAll(RegExp(r'[\s+]'), '') ==
        widget.currentUserPhone.replaceAll(RegExp(r'[\s+]'), '');

    return ListTile(
      leading: CircleAvatar(
        backgroundColor: isCreator ? const Color(0xFF004D40) : Colors.grey[300],
        child: Icon(
          isCreator ? Icons.star : Icons.person,
          color: isCreator ? Colors.white : Colors.grey[600],
        ),
      ),
      title: Row(
        children: [
          Text(name),
          if (isMe)
            const Text(
              ' (Вы)',
              style: TextStyle(color: Colors.grey, fontSize: 12),
            ),
        ],
      ),
      subtitle: isCreator ? const Text('Создатель') : null,
      trailing: _isCreator && !isCreator
          ? IconButton(
              icon: const Icon(Icons.remove_circle_outline, color: Colors.red),
              onPressed: () => _removeMember(phone),
            )
          : null,
    );
  }

  Widget _buildActionsSection() {
    return Column(
      children: [
        if (!_isCreator)
          ListTile(
            leading: const Icon(Icons.exit_to_app, color: Colors.orange),
            title: const Text('Выйти из группы'),
            onTap: _leaveGroup,
          ),
        if (_isCreator)
          ListTile(
            leading: const Icon(Icons.delete, color: Colors.red),
            title: const Text('Удалить группу', style: TextStyle(color: Colors.red)),
            onTap: _deleteGroup,
          ),
      ],
    );
  }
}

/// Шит для добавления участников
class _AddMembersSheet extends StatefulWidget {
  final List<String> existingParticipants;

  const _AddMembersSheet({required this.existingParticipants});

  @override
  State<_AddMembersSheet> createState() => _AddMembersSheetState();
}

class _AddMembersSheetState extends State<_AddMembersSheet> {
  final _searchController = TextEditingController();
  final List<String> _selected = [];
  List<Employee> _employees = [];
  List<ChatClient> _clients = [];
  bool _isLoading = true;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _loadParticipants();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadParticipants() async {
    try {
      final results = await Future.wait([
        EmployeeService.getEmployees(),
        EmployeeChatService.getClientsForGroupSelection(),
      ]);

      final normalizedExisting = widget.existingParticipants
          .map((p) => p.replaceAll(RegExp(r'[\s+]'), ''))
          .toSet();

      _employees = (results[0] as List<Employee>).where((e) {
        final phone = (e.phone ?? '').replaceAll(RegExp(r'[\s+]'), '');
        return !normalizedExisting.contains(phone);
      }).toList();

      _clients = (results[1] as List<ChatClient>).where((c) {
        final phone = c.phone.replaceAll(RegExp(r'[\s+]'), '');
        return !normalizedExisting.contains(phone);
      }).toList();
    } catch (e) {
      // Ignore
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.7,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: Column(
        children: [
          // Заголовок
          Container(
            padding: const EdgeInsets.all(16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Добавить участников',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                TextButton(
                  onPressed: _selected.isEmpty
                      ? null
                      : () => Navigator.pop(context, _selected),
                  child: Text('Добавить (${_selected.length})'),
                ),
              ],
            ),
          ),

          // Поиск
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              controller: _searchController,
              onChanged: (v) => setState(() => _searchQuery = v.toLowerCase()),
              decoration: const InputDecoration(
                hintText: 'Поиск...',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
              ),
            ),
          ),

          const SizedBox(height: 8),

          // Список
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _buildList(),
          ),
        ],
      ),
    );
  }

  Widget _buildList() {
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
      return const Center(child: Text('Нет доступных участников'));
    }

    return ListView(
      children: [
        if (filteredEmployees.isNotEmpty) ...[
          Container(
            color: Colors.grey[100],
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: const Text('Сотрудники', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
          ...filteredEmployees.map((e) {
            final phone = (e.phone ?? '').replaceAll(RegExp(r'[\s+]'), '');
            final isSelected = _selected.contains(phone);
            return CheckboxListTile(
              value: isSelected,
              onChanged: (v) {
                setState(() {
                  if (v == true) {
                    _selected.add(phone);
                  } else {
                    _selected.remove(phone);
                  }
                });
              },
              title: Text(e.name ?? e.phone ?? ''),
              subtitle: Text(e.position ?? ''),
              secondary: const CircleAvatar(child: Icon(Icons.badge)),
            );
          }),
        ],
        if (filteredClients.isNotEmpty) ...[
          Container(
            color: Colors.grey[100],
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: const Text('Клиенты', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
          ...filteredClients.map((c) {
            final phone = c.phone.replaceAll(RegExp(r'[\s+]'), '');
            final isSelected = _selected.contains(phone);
            return CheckboxListTile(
              value: isSelected,
              onChanged: (v) {
                setState(() {
                  if (v == true) {
                    _selected.add(phone);
                  } else {
                    _selected.remove(phone);
                  }
                });
              },
              title: Text(c.displayName),
              subtitle: Text('Баллы: ${c.points}'),
              secondary: const CircleAvatar(
                backgroundColor: Colors.green,
                child: Icon(Icons.person, color: Colors.white),
              ),
            );
          }),
        ],
      ],
    );
  }
}
