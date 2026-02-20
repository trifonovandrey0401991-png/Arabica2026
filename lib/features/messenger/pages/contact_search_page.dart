import 'dart:async';
import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../models/contact_model.dart';
import '../services/messenger_service.dart';
import 'messenger_chat_page.dart';
import 'group_create_page.dart';

class ContactSearchPage extends StatefulWidget {
  final String userPhone;
  final String userName;

  const ContactSearchPage({
    super.key,
    required this.userPhone,
    required this.userName,
  });

  @override
  State<ContactSearchPage> createState() => _ContactSearchPageState();
}

class _ContactSearchPageState extends State<ContactSearchPage> {
  final _searchController = TextEditingController();
  List<MessengerContact> _contacts = [];
  bool _isSearching = false;
  Timer? _debounce;

  // Мультивыбор для создания группы
  bool _isMultiSelect = false;
  final Set<String> _selectedPhones = {};

  @override
  void dispose() {
    _searchController.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onSearchChanged(String query) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () {
      if (query.length >= 2) {
        _search(query);
      } else if (mounted) {
        setState(() => _contacts = []);
      }
    });
  }

  Future<void> _search(String query) async {
    if (mounted) setState(() => _isSearching = true);

    try {
      final contacts = await MessengerService.searchContacts(query);
      if (mounted) {
        setState(() {
          // Фильтруем себя
          _contacts = contacts.where((c) => c.phone != widget.userPhone).toList();
          _isSearching = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isSearching = false);
    }
  }

  void _startPrivateChat(MessengerContact contact) async {
    final conversation = await MessengerService.getOrCreatePrivateChat(
      phone1: widget.userPhone,
      phone2: contact.phone,
      name1: widget.userName,
      name2: contact.name,
    );

    if (conversation != null && mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => MessengerChatPage(
            conversation: conversation,
            userPhone: widget.userPhone,
            userName: widget.userName,
          ),
        ),
      );
    }
  }

  void _toggleSelection(String phone) {
    setState(() {
      if (_selectedPhones.contains(phone)) {
        _selectedPhones.remove(phone);
      } else {
        _selectedPhones.add(phone);
      }
    });
  }

  void _createGroup() {
    if (_selectedPhones.isEmpty) return;

    final selectedContacts = _contacts.where((c) => _selectedPhones.contains(c.phone)).toList();

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => GroupCreatePage(
          userPhone: widget.userPhone,
          userName: widget.userName,
          selectedContacts: selectedContacts,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.emerald,
        foregroundColor: Colors.white,
        title: Text(_isMultiSelect ? 'Создать группу' : 'Новый чат'),
        actions: [
          IconButton(
            icon: Icon(_isMultiSelect ? Icons.person : Icons.group_add),
            tooltip: _isMultiSelect ? 'Личный чат' : 'Создать группу',
            onPressed: () {
              setState(() {
                _isMultiSelect = !_isMultiSelect;
                _selectedPhones.clear();
              });
            },
          ),
          if (_isMultiSelect && _selectedPhones.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.check),
              onPressed: _createGroup,
            ),
        ],
      ),
      body: Column(
        children: [
          // Search field
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              controller: _searchController,
              onChanged: _onSearchChanged,
              autofocus: true,
              decoration: InputDecoration(
                hintText: 'Поиск по имени или телефону...',
                prefixIcon: const Icon(Icons.search, color: AppColors.emerald),
                filled: true,
                fillColor: Colors.grey[100],
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),

          if (_isMultiSelect && _selectedPhones.isNotEmpty)
            Container(
              height: 50,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: _selectedPhones.map((phone) {
                  final contact = _contacts.firstWhere(
                    (c) => c.phone == phone,
                    orElse: () => MessengerContact(phone: phone),
                  );
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Chip(
                      label: Text(contact.displayName, style: const TextStyle(fontSize: 12)),
                      deleteIcon: const Icon(Icons.close, size: 16),
                      onDeleted: () => _toggleSelection(phone),
                      backgroundColor: AppColors.teal50,
                    ),
                  );
                }).toList(),
              ),
            ),

          // Results
          Expanded(
            child: _isSearching
                ? const Center(child: CircularProgressIndicator(color: AppColors.emerald))
                : _contacts.isEmpty
                    ? Center(
                        child: Text(
                          _searchController.text.length < 2
                              ? 'Введите имя или телефон'
                              : 'Ничего не найдено',
                          style: TextStyle(color: Colors.grey[500]),
                        ),
                      )
                    : ListView.builder(
                        itemCount: _contacts.length,
                        itemBuilder: (context, index) {
                          final contact = _contacts[index];
                          final isSelected = _selectedPhones.contains(contact.phone);

                          return ListTile(
                            leading: CircleAvatar(
                              backgroundColor: contact.userType == 'employee'
                                  ? AppColors.emeraldLight
                                  : AppColors.turquoise,
                              child: Text(
                                contact.displayName[0].toUpperCase(),
                                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                              ),
                            ),
                            title: Text(contact.displayName),
                            subtitle: Text(
                              '${contact.phone} • ${contact.userType == 'employee' ? 'Сотрудник' : 'Клиент'}',
                              style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                            ),
                            trailing: _isMultiSelect
                                ? Checkbox(
                                    value: isSelected,
                                    activeColor: AppColors.emerald,
                                    onChanged: (_) => _toggleSelection(contact.phone),
                                  )
                                : const Icon(Icons.chevron_right, color: Colors.grey),
                            onTap: _isMultiSelect
                                ? () => _toggleSelection(contact.phone)
                                : () => _startPrivateChat(contact),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}
