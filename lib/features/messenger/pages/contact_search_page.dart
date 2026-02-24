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
  /// Если передан — показываем только этих людей (из телефонной книги).
  /// Если null — доступ к контактам не дан, показываем всех зарегистрированных.
  final List<MessengerContact>? matchedContacts;

  const ContactSearchPage({
    super.key,
    required this.userPhone,
    required this.userName,
    this.matchedContacts,
  });

  @override
  State<ContactSearchPage> createState() => _ContactSearchPageState();
}

class _ContactSearchPageState extends State<ContactSearchPage> {
  final _searchController = TextEditingController();
  List<MessengerContact> _allContacts = [];
  List<MessengerContact> _contacts = [];
  bool _isLoading = true;

  bool _isMultiSelect = false;
  final Set<String> _selectedPhones = {};

  @override
  void initState() {
    super.initState();
    _loadContacts();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadContacts() async {
    if (mounted) setState(() => _isLoading = true);

    try {
      List<MessengerContact> contacts;

      if (widget.matchedContacts != null) {
        // Используем список из телефонной книги (уже отфильтрованный на сервере)
        contacts = widget.matchedContacts!;
      } else {
        // Нет разрешения на контакты — загружаем всех зарегистрированных пользователей
        contacts = await MessengerService.searchContacts('');
      }

      if (mounted) {
        setState(() {
          _allContacts = contacts.where((c) => c.phone != widget.userPhone).toList();
          _contacts = _allContacts;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _onSearchChanged(String query) {
    if (query.isEmpty) {
      if (mounted) setState(() => _contacts = _allContacts);
      return;
    }
    final lower = query.toLowerCase();
    if (mounted) {
      setState(() {
        _contacts = _allContacts.where((c) {
          return c.displayName.toLowerCase().contains(lower) ||
              c.phone.contains(query);
        }).toList();
      });
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
    if (mounted) {
      setState(() {
        if (_selectedPhones.contains(phone)) {
          _selectedPhones.remove(phone);
        } else {
          _selectedPhones.add(phone);
        }
      });
    }
  }

  void _createGroup() {
    if (_selectedPhones.isEmpty) return;

    final selectedContacts = _allContacts.where((c) => _selectedPhones.contains(c.phone)).toList();

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

  Widget _buildNewGroupRow() {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        splashColor: Colors.white.withOpacity(0.05),
        highlightColor: Colors.white.withOpacity(0.03),
        onTap: () {
          if (mounted) {
            setState(() {
              _isMultiSelect = true;
              _selectedPhones.clear();
            });
          }
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(color: Colors.white.withOpacity(0.06)),
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: const LinearGradient(
                    colors: [AppColors.turquoise, AppColors.emerald],
                  ),
                  border: Border.all(color: Colors.white.withOpacity(0.15)),
                ),
                child: const Icon(Icons.group_add, color: Colors.white, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Новая группа',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.9),
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'До 256 участников',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.white.withOpacity(0.35),
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: Colors.white.withOpacity(0.2)),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.night,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: Colors.white,
        title: Text(
          _isMultiSelect ? 'Создать группу' : 'Новый чат',
          style: TextStyle(color: Colors.white.withOpacity(0.95)),
        ),
        leading: _isMultiSelect
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () {
                  if (mounted) {
                    setState(() {
                      _isMultiSelect = false;
                      _selectedPhones.clear();
                    });
                  }
                },
              )
            : null,
        actions: [
          if (_isMultiSelect && _selectedPhones.isNotEmpty)
            TextButton.icon(
              icon: const Icon(Icons.check, color: AppColors.turquoise, size: 20),
              label: Text(
                'Далее (${_selectedPhones.length})',
                style: const TextStyle(color: AppColors.turquoise, fontWeight: FontWeight.w600),
              ),
              onPressed: _createGroup,
            ),
        ],
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                AppColors.emerald.withOpacity(0.3),
                Colors.transparent,
              ],
            ),
          ),
        ),
      ),
      body: Column(
        children: [
          // Поиск (только локальная фильтрация по кэшу)
          Padding(
            padding: const EdgeInsets.all(12),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.06),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.white.withOpacity(0.1)),
              ),
              child: TextField(
                controller: _searchController,
                onChanged: _onSearchChanged,
                autofocus: false,
                style: TextStyle(color: Colors.white.withOpacity(0.9)),
                decoration: InputDecoration(
                  hintText: 'Поиск по имени или телефону...',
                  hintStyle: TextStyle(color: Colors.white.withOpacity(0.3)),
                  prefixIcon: Icon(Icons.search, color: AppColors.turquoise.withOpacity(0.7)),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ),
          ),

          // Горизонтальные чипы выбранных участников (в режиме группы)
          if (_isMultiSelect && _selectedPhones.isNotEmpty)
            Container(
              height: 50,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: _selectedPhones.map((phone) {
                  final contact = _allContacts.firstWhere(
                    (c) => c.phone == phone,
                    orElse: () => MessengerContact(phone: phone),
                  );
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Chip(
                      label: Text(
                        contact.displayName,
                        style: TextStyle(fontSize: 12, color: Colors.white.withOpacity(0.9)),
                      ),
                      deleteIcon: Icon(Icons.close, size: 16, color: Colors.white.withOpacity(0.5)),
                      onDeleted: () => _toggleSelection(phone),
                      backgroundColor: AppColors.emerald.withOpacity(0.3),
                      side: BorderSide(color: AppColors.emerald.withOpacity(0.5)),
                    ),
                  );
                }).toList(),
              ),
            ),

          // Пояснение откуда список (если из контактов)
          if (!_isMultiSelect && widget.matchedContacts != null && _allContacts.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Row(
                children: [
                  Icon(Icons.contacts, size: 14, color: AppColors.turquoise.withOpacity(0.5)),
                  const SizedBox(width: 6),
                  Text(
                    'Из ваших контактов · ${_allContacts.length}',
                    style: TextStyle(fontSize: 12, color: Colors.white.withOpacity(0.35)),
                  ),
                ],
              ),
            ),

          // Список
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator(color: AppColors.turquoise, strokeWidth: 2.5))
                : _contacts.isEmpty
                    ? _buildEmptyState()
                    : ListView.builder(
                        itemCount: _contacts.length + (_isMultiSelect ? 0 : 1),
                        itemBuilder: (context, index) {
                          if (!_isMultiSelect && index == 0) {
                            return _buildNewGroupRow();
                          }
                          final contactIndex = _isMultiSelect ? index : index - 1;
                          final contact = _contacts[contactIndex];
                          final isSelected = _selectedPhones.contains(contact.phone);

                          return Material(
                            color: Colors.transparent,
                            child: InkWell(
                              splashColor: Colors.white.withOpacity(0.05),
                              highlightColor: Colors.white.withOpacity(0.03),
                              onTap: _isMultiSelect
                                  ? () => _toggleSelection(contact.phone)
                                  : () => _startPrivateChat(contact),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                decoration: BoxDecoration(
                                  border: Border(
                                    bottom: BorderSide(color: Colors.white.withOpacity(0.06)),
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Container(
                                      width: 44,
                                      height: 44,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        gradient: LinearGradient(
                                          colors: contact.userType == 'employee'
                                              ? [AppColors.emeraldLight, AppColors.emerald]
                                              : [AppColors.turquoise, AppColors.emerald],
                                        ),
                                        border: Border.all(color: Colors.white.withOpacity(0.15)),
                                      ),
                                      child: Center(
                                        child: Text(
                                          contact.displayName[0].toUpperCase(),
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 16,
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            contact.displayName,
                                            style: TextStyle(
                                              color: Colors.white.withOpacity(0.9),
                                              fontWeight: FontWeight.w500,
                                              fontSize: 15,
                                            ),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            '${contact.phone} \u2022 ${contact.userType == 'employee' ? 'Сотрудник' : 'Клиент'}',
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: Colors.white.withOpacity(0.35),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    if (_isMultiSelect)
                                      Container(
                                        width: 24,
                                        height: 24,
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          color: isSelected
                                              ? AppColors.turquoise
                                              : Colors.white.withOpacity(0.08),
                                          border: Border.all(
                                            color: isSelected
                                                ? AppColors.turquoise
                                                : Colors.white.withOpacity(0.2),
                                          ),
                                        ),
                                        child: isSelected
                                            ? const Icon(Icons.check, size: 16, color: Colors.white)
                                            : null,
                                      )
                                    else
                                      Icon(Icons.chevron_right, color: Colors.white.withOpacity(0.2)),
                                  ],
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

  Widget _buildEmptyState() {
    if (_searchController.text.isNotEmpty) {
      return Center(
        child: Text(
          'Ничего не найдено',
          style: TextStyle(color: Colors.white.withOpacity(0.35)),
        ),
      );
    }

    if (widget.matchedContacts != null) {
      // Разрешение дано, но никого из контактов нет в системе
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.contacts, size: 56, color: Colors.white.withOpacity(0.1)),
            const SizedBox(height: 16),
            Text(
              'Никого из ваших контактов\nпока нет в системе',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 15, color: Colors.white.withOpacity(0.4)),
            ),
          ],
        ),
      );
    }

    // Нет разрешения — список пуст
    return Center(
      child: Text(
        'Нет контактов',
        style: TextStyle(color: Colors.white.withOpacity(0.35)),
      ),
    );
  }
}
