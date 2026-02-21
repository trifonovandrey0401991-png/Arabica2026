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
  List<MessengerContact> _allContacts = [];
  List<MessengerContact> _contacts = [];
  bool _isSearching = false;
  Timer? _debounce;

  bool _isMultiSelect = false;
  final Set<String> _selectedPhones = {};

  @override
  void initState() {
    super.initState();
    _loadAllContacts();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _loadAllContacts() async {
    if (mounted) setState(() => _isSearching = true);
    try {
      final contacts = await MessengerService.searchContacts('');
      if (mounted) {
        setState(() {
          _allContacts = contacts.where((c) => c.phone != widget.userPhone).toList();
          _contacts = _allContacts;
          _isSearching = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isSearching = false);
    }
  }

  void _onSearchChanged(String query) {
    _debounce?.cancel();
    if (query.isEmpty) {
      setState(() => _contacts = _allContacts);
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 400), () {
      if (query.length >= 2) {
        _search(query);
      } else if (mounted) {
        setState(() => _contacts = _allContacts);
      }
    });
  }

  Future<void> _search(String query) async {
    if (mounted) setState(() => _isSearching = true);

    try {
      final contacts = await MessengerService.searchContacts(query);
      if (mounted) {
        setState(() {
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
      backgroundColor: AppColors.night,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: Colors.white,
        title: Text(
          _isMultiSelect ? 'Создать группу' : 'Новый чат',
          style: TextStyle(color: Colors.white.withOpacity(0.95)),
        ),
        actions: [
          IconButton(
            icon: Icon(
              _isMultiSelect ? Icons.person : Icons.group_add,
              color: Colors.white.withOpacity(0.6),
            ),
            tooltip: _isMultiSelect ? 'Личный чат' : 'Создать группу',
            onPressed: () {
              if (mounted) {
                setState(() {
                  _isMultiSelect = !_isMultiSelect;
                  _selectedPhones.clear();
                });
              }
            },
          ),
          if (_isMultiSelect && _selectedPhones.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.check, color: AppColors.turquoise),
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
          // Search field
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
                autofocus: true,
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

          // Results
          Expanded(
            child: _isSearching
                ? const Center(child: CircularProgressIndicator(color: AppColors.turquoise, strokeWidth: 2.5))
                : _contacts.isEmpty
                    ? Center(
                        child: Text(
                          _searchController.text.isEmpty
                              ? 'Нет контактов'
                              : 'Ничего не найдено',
                          style: TextStyle(color: Colors.white.withOpacity(0.35)),
                        ),
                      )
                    : ListView.builder(
                        itemCount: _contacts.length,
                        itemBuilder: (context, index) {
                          final contact = _contacts[index];
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
}
