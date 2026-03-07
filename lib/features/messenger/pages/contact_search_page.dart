import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:permission_handler/permission_handler.dart';
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

  /// Select mode: multi-select contacts and return List<MessengerContact> via Navigator.pop
  final bool selectMode;

  /// Exclude these phones from the list (e.g. already in group)
  final Set<String> excludePhones;

  /// Single-select mode: tap returns one MessengerContact via Navigator.pop
  final bool singleSelectMode;

  /// Embedded mode: used as a tab in bottom navigation (no back button, push instead of pushReplacement)
  final bool embeddedMode;

  const ContactSearchPage({
    super.key,
    required this.userPhone,
    required this.userName,
    this.matchedContacts,
    this.selectMode = false,
    this.excludePhones = const {},
    this.singleSelectMode = false,
    this.embeddedMode = false,
  });

  @override
  State<ContactSearchPage> createState() => _ContactSearchPageState();
}

class _ContactSearchPageState extends State<ContactSearchPage> {
  final _searchController = TextEditingController();
  List<MessengerContact> _allContacts = [];
  List<MessengerContact> _contacts = [];
  bool _isLoading = true;
  String? _error;
  // Tracks whether contacts permission is actually granted (checked at load time)
  bool _permissionGranted = false;

  bool _isMultiSelect = false;
  final Set<String> _selectedPhones = {};

  @override
  void initState() {
    super.initState();
    if (widget.selectMode) _isMultiSelect = true;
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
      bool granted = false;

      if (widget.matchedContacts != null) {
        // Shell page already loaded contacts — use them directly
        contacts = widget.matchedContacts!;
        granted = true;
      } else {
        // matchedContacts == null may mean: (a) no permission, OR (b) permission granted
        // but shell page hasn't finished loading yet. Check actual status.
        final status = await Permission.contacts.status;
        if (status.isGranted) {
          granted = true;
          // Load contacts ourselves — shell page is still loading
          contacts = await _loadContactsFromDevice();
        } else {
          granted = false;
          contacts = [];
        }
      }

      if (mounted) {
        setState(() {
          _permissionGranted = granted;
          _allContacts = contacts.where((c) =>
              c.phone != widget.userPhone && !widget.excludePhones.contains(c.phone)).toList();
          _contacts = _allContacts;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() { _isLoading = false; _error = 'Не удалось загрузить контакты'; });
    }
  }

  /// Reads device contacts and checks which are registered in the system.
  Future<List<MessengerContact>> _loadContactsFromDevice() async {
    try {
      final deviceContacts = await FlutterContacts.getContacts(withProperties: true);
      final phones = <String>[];
      for (final c in deviceContacts) {
        for (final p in c.phones) {
          final normalized = _normalizePhone(p.number);
          if (normalized != null) phones.add(normalized);
        }
      }
      if (phones.isEmpty) return [];
      return await MessengerService.matchPhones(phones);
    } catch (_) {
      return [];
    }
  }

  String? _normalizePhone(String raw) {
    final digits = raw.replaceAll(RegExp(r'\D'), '');
    if (digits.length == 10) return '7$digits';
    if (digits.length == 11) {
      if (digits.startsWith('8')) return '7${digits.substring(1)}';
      if (digits.startsWith('7')) return digits;
    }
    return null;
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
      if (widget.embeddedMode) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => MessengerChatPage(
              conversation: conversation,
              userPhone: widget.userPhone,
              userName: widget.userName,
            ),
          ),
        );
      } else {
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

    // In select mode, return selected contacts to the caller
    if (widget.selectMode) {
      Navigator.pop(context, selectedContacts);
      return;
    }

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
          _isMultiSelect
              ? (widget.selectMode ? 'Добавить участников' : 'Создать группу')
              : widget.singleSelectMode
                  ? 'Выберите контакт'
                  : widget.embeddedMode
                      ? 'Контакты'
                      : 'Новый чат',
          style: TextStyle(color: Colors.white.withOpacity(0.95)),
        ),
        leading: _isMultiSelect
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () {
                  if (widget.selectMode) {
                    Navigator.pop(context);
                  } else if (mounted) {
                    setState(() {
                      _isMultiSelect = false;
                      _selectedPhones.clear();
                    });
                  }
                },
              )
            : widget.embeddedMode
                ? const SizedBox.shrink()
                : null,
        automaticallyImplyLeading: !widget.embeddedMode,
        actions: [
          if (_isMultiSelect && _selectedPhones.isNotEmpty)
            TextButton.icon(
              icon: const Icon(Icons.check, color: AppColors.turquoise, size: 20),
              label: Text(
                widget.selectMode
                    ? 'Добавить (${_selectedPhones.length})'
                    : 'Далее (${_selectedPhones.length})',
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
          if (!_isMultiSelect && _permissionGranted && _allContacts.isNotEmpty)
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
                : _error != null
                    ? Center(child: Text(_error!, style: TextStyle(color: Colors.white.withOpacity(0.5))))
                : _contacts.isEmpty
                    ? _buildEmptyState()
                    : ListView.builder(
                        itemCount: _contacts.length + (_isMultiSelect || widget.singleSelectMode ? 0 : 1),
                        itemBuilder: (context, index) {
                          if (!_isMultiSelect && !widget.singleSelectMode && index == 0) {
                            return _buildNewGroupRow();
                          }
                          final contactIndex = (_isMultiSelect || widget.singleSelectMode) ? index : index - 1;
                          final contact = _contacts[contactIndex];
                          final isSelected = _selectedPhones.contains(contact.phone);

                          return Material(
                            color: Colors.transparent,
                            child: InkWell(
                              splashColor: Colors.white.withOpacity(0.05),
                              highlightColor: Colors.white.withOpacity(0.03),
                              onTap: widget.singleSelectMode
                                  ? () => Navigator.pop(context, contact)
                                  : _isMultiSelect
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

    if (_permissionGranted) {
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

    // Нет разрешения на контакты
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.contacts_outlined, size: 64, color: Colors.white.withOpacity(0.12)),
            const SizedBox(height: 20),
            Text(
              'Нет доступа к контактам',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w600,
                color: Colors.white.withOpacity(0.7),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'Чтобы находить коллег в мессенджере, разрешите приложению доступ к контактам телефона',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: Colors.white.withOpacity(0.35)),
            ),
            const SizedBox(height: 28),
            TextButton.icon(
              onPressed: () => openAppSettings(),
              icon: Icon(Icons.settings_outlined, color: AppColors.turquoise, size: 18),
              label: const Text(
                'Открыть настройки',
                style: TextStyle(color: AppColors.turquoise, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
