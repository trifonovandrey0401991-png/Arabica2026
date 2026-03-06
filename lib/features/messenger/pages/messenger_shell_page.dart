import 'package:flutter/material.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/services/firebase_service.dart';
import '../../../core/theme/app_colors.dart';
import '../models/contact_model.dart';
import '../services/messenger_service.dart';
import '../../employees/models/user_role_model.dart';
import '../../employees/services/user_role_service.dart';
import '../../../core/utils/logger.dart';
import '../services/messenger_ws_service.dart';
import 'messenger_list_page.dart';
import 'contact_search_page.dart';
import 'messenger_global_search_page.dart';
import 'messenger_profile_page.dart';

/// Полноэкранная обёртка мессенджера.
/// Единственная точка входа из основного приложения.
/// Загружает phone/name из SharedPreferences, запрашивает доступ к контактам.
class MessengerShellPage extends StatefulWidget {
  const MessengerShellPage({super.key});

  /// Determines display name using priority:
  /// 1. Phone book name (if user is in device contacts)
  /// 2. Profile/server name (if set in messenger profile)
  /// 3. Phone number (fallback)
  static String resolveDisplayName(
    String phone, String? serverName,
    Map<String, String> phoneBookNames,
    {bool isGroupContext = false}
  ) {
    final bookName = phoneBookNames[phone];
    if (bookName != null) return bookName;
    if (serverName != null && serverName.isNotEmpty && serverName != phone) return serverName;
    return phone;
  }

  @override
  State<MessengerShellPage> createState() => _MessengerShellPageState();
}

class _MessengerShellPageState extends State<MessengerShellPage> with WidgetsBindingObserver {
  String? _userPhone;
  String? _userName;
  bool _isLoading = true;

  // Bottom navigation
  int _currentTabIndex = 0;

  // Контакты из телефонной книги, которые зарегистрированы в системе
  List<MessengerContact> _matchedContacts = [];
  bool _contactsGranted = false;
  bool _isClient = false;
  // Карта: нормализованный телефон → имя из телефонной книги устройства
  Map<String, String> _phoneBookNames = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _init();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Re-check contacts permission when app returns from background (e.g. user just granted in Settings)
    if (state == AppLifecycleState.resumed && !_contactsGranted && _userPhone != null && _userPhone!.isNotEmpty) {
      Permission.contacts.status.then((status) {
        if (status.isGranted) {
          _initContacts(_userPhone!);
        }
      });
    }
  }

  Future<void> _init() async {
    // 1. Загружаем пользователя
    final prefs = await SharedPreferences.getInstance();
    final phone = prefs.getString('user_phone') ?? prefs.getString('userPhone') ?? '';
    final name = prefs.getString('user_name') ?? prefs.getString('userName') ?? '';
    String displayName = name.isNotEmpty ? name : phone;

    if (phone.isNotEmpty) {
      try {
        final profile = await MessengerService.getProfile(phone);
        if (profile != null) {
          final profileName = profile['display_name'] as String?;
          if (profileName != null && profileName.isNotEmpty) {
            displayName = profileName;
          }
        }
      } catch (e) { Logger.error('MessengerShell', 'Failed to load profile', e); }
    }

    // 2. Проверяем роль пользователя (из кэша — мгновенно)
    bool isDeveloper = false;
    bool isClient = false;
    if (phone.isNotEmpty) {
      try {
        final roleData = await UserRoleService.loadUserRole();
        isDeveloper = roleData?.role == UserRole.developer;
        isClient = roleData?.role == UserRole.client;
      } catch (e) { Logger.error('Messenger: role load error', e); }
    }

    if (!mounted) return;
    setState(() {
      _userPhone = phone;
      _userName = displayName;
      _isClient = isClient;
      _isLoading = false;
    });

    // Сообщаем WS-сервису роль для фильтрации уведомлений
    MessengerWsService.isClientUser = isClient;

    // 3. Разработчик видит всех — пропускаем фильтрацию по контактам
    if (isDeveloper) return;

    // 4. Запрашиваем контакты после показа основного UI
    if (phone.isNotEmpty) {
      await _initContacts(phone);
    }
  }

  Future<void> _initContacts(String myPhone) async {
    var status = await Permission.contacts.status;

    // Если ещё не спрашивали — показываем объяснение
    if (status.isDenied && mounted) {
      final wantsToShare = await _showContactsExplanationDialog();
      if (wantsToShare == true) {
        status = await Permission.contacts.request();
      }
    }

    if (!status.isGranted) {
      if (mounted) setState(() => _contactsGranted = false);
      return;
    }

    if (mounted) setState(() => _contactsGranted = true);

    // Читаем контакты телефона
    final deviceContacts = await FlutterContacts.getContacts(withProperties: true);
    final phones = <String>[];
    final bookNames = <String, String>{};
    for (final c in deviceContacts) {
      for (final p in c.phones) {
        final normalized = _normalizePhone(p.number);
        if (normalized != null) {
          phones.add(normalized);
          if (c.displayName.isNotEmpty && !bookNames.containsKey(normalized)) {
            bookNames[normalized] = c.displayName;
          }
        }
      }
    }

    // Сохраняем телефонную книгу для фильтрации имён
    if (mounted) setState(() => _phoneBookNames = bookNames);
    MessengerWsService.phoneBookNames = bookNames;
    MessengerWsService.phoneBookPhones = bookNames.keys.toSet();

    // Push notifications: resolve sender name from phone book
    FirebaseService.resolveMessengerName = (phone) => bookNames[phone];

    if (phones.isEmpty) return;

    // Сверяем с сервером: кто из них зарегистрирован в системе?
    try {
      final matched = await MessengerService.matchPhones(phones);
      if (mounted) {
        setState(() {
          // Подставляем имя из телефонной книги вместо системного имени
          _matchedContacts = matched
              .where((c) => c.phone != myPhone)
              .map((c) {
                final bookName = bookNames[c.phone];
                if (bookName != null && bookName.isNotEmpty) {
                  return MessengerContact(phone: c.phone, name: bookName, userType: c.userType);
                }
                return c;
              })
              .toList();
        });
      }
    } catch (e) { Logger.error('MessengerShell', 'Failed to match contacts', e); }
  }

  /// Нормализует номер в формат 7XXXXXXXXXX (11 цифр без +)
  String? _normalizePhone(String raw) {
    final digits = raw.replaceAll(RegExp(r'\D'), '');
    if (digits.length == 10) return '7$digits';
    if (digits.length == 11) {
      if (digits.startsWith('8')) return '7${digits.substring(1)}';
      if (digits.startsWith('7')) return digits;
    }
    return null;
  }

  Future<bool?> _showContactsExplanationDialog() {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF0A2A2A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: [AppColors.turquoise, AppColors.emerald],
                ),
              ),
              child: const Icon(Icons.contacts, color: Colors.white, size: 36),
            ),
            const SizedBox(height: 20),
            Text(
              'Доступ к контактам',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.white.withOpacity(0.95),
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Text(
              'Мессенджер использует вашу телефонную книгу, чтобы показывать только тех людей, которых вы знаете и кто зарегистрирован в системе.',
              style: TextStyle(
                fontSize: 14,
                color: Colors.white.withOpacity(0.6),
                height: 1.5,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            Text(
              'Контакты не хранятся на сервере.',
              style: TextStyle(
                fontSize: 12,
                color: AppColors.turquoise.withOpacity(0.8),
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
        actionsAlignment: MainAxisAlignment.center,
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        actions: [
          Row(
            children: [
              Expanded(
                child: TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: Text(
                    'Не сейчас',
                    style: TextStyle(color: Colors.white.withOpacity(0.4)),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [AppColors.turquoise, AppColors.emerald],
                    ),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: TextButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    child: const Text(
                      'Поделиться',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        backgroundColor: AppColors.night,
        body: const Center(child: CircularProgressIndicator(color: AppColors.turquoise, strokeWidth: 2.5)),
      );
    }

    if (_userPhone == null || _userPhone!.isEmpty) {
      return Scaffold(
        backgroundColor: AppColors.night,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          foregroundColor: Colors.white,
          title: const Text('Мессенджер'),
        ),
        body: Center(
          child: Text(
            'Ошибка: не удалось определить пользователя',
            style: TextStyle(color: Colors.white.withOpacity(0.5)),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.night,
      body: IndexedStack(
        index: _currentTabIndex,
        children: [
          MessengerListPage(
            userPhone: _userPhone!,
            userName: _userName ?? _userPhone!,
            matchedContacts: _matchedContacts,
            contactsGranted: _contactsGranted,
            isClient: _isClient,
            phoneBookNames: _phoneBookNames,
          ),
          ContactSearchPage(
            userPhone: _userPhone!,
            userName: _userName ?? _userPhone!,
            matchedContacts: _contactsGranted ? _matchedContacts : null,
            embeddedMode: true,
          ),
          MessengerGlobalSearchPage(
            userPhone: _userPhone!,
            userName: _userName ?? _userPhone!,
            isClient: _isClient,
            phoneBookNames: _phoneBookNames,
          ),
          MessengerProfilePage(
            userPhone: _userPhone!,
            userName: _userName ?? _userPhone!,
            embeddedMode: true,
            onProfileChanged: (result) {
              if (result.displayName != null && mounted) {
                setState(() => _userName = result.displayName);
              }
            },
          ),
        ],
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: AppColors.night.withOpacity(0.95),
          border: Border(
            top: BorderSide(color: Colors.white.withOpacity(0.06)),
          ),
        ),
        child: BottomNavigationBar(
          currentIndex: _currentTabIndex,
          onTap: (index) {
            if (mounted) setState(() => _currentTabIndex = index);
          },
          backgroundColor: Colors.transparent,
          elevation: 0,
          selectedItemColor: AppColors.turquoise,
          unselectedItemColor: Colors.white.withOpacity(0.4),
          selectedFontSize: 12,
          unselectedFontSize: 12,
          type: BottomNavigationBarType.fixed,
          items: const [
            BottomNavigationBarItem(
              icon: Icon(Icons.chat_bubble),
              label: 'Чаты',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.contacts),
              label: 'Контакты',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.search),
              label: 'Поиск',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.person),
              label: 'Профиль',
            ),
          ],
        ),
      ),
    );
  }
}
