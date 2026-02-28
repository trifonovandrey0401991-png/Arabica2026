import 'package:flutter/material.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/theme/app_colors.dart';
import '../models/contact_model.dart';
import '../services/messenger_service.dart';
import '../../employees/models/user_role_model.dart';
import '../../employees/services/user_role_service.dart';
import '../../../core/utils/logger.dart';
import 'messenger_list_page.dart';

/// Полноэкранная обёртка мессенджера.
/// Единственная точка входа из основного приложения.
/// Загружает phone/name из SharedPreferences, запрашивает доступ к контактам.
class MessengerShellPage extends StatefulWidget {
  const MessengerShellPage({super.key});

  @override
  State<MessengerShellPage> createState() => _MessengerShellPageState();
}

class _MessengerShellPageState extends State<MessengerShellPage> {
  String? _userPhone;
  String? _userName;
  bool _isLoading = true;

  // Контакты из телефонной книги, которые зарегистрированы в системе
  List<MessengerContact> _matchedContacts = [];
  bool _contactsGranted = false;

  @override
  void initState() {
    super.initState();
    _init();
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
    if (phone.isNotEmpty) {
      try {
        final roleData = await UserRoleService.loadUserRole();
        isDeveloper = roleData?.role == UserRole.developer;
      } catch (_) {}
    }

    if (!mounted) return;
    setState(() {
      _userPhone = phone;
      _userName = displayName;
      _isLoading = false;
    });

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
    // Карта: нормализованный номер → имя из телефонной книги
    final phoneBookNames = <String, String>{};
    for (final c in deviceContacts) {
      for (final p in c.phones) {
        final normalized = _normalizePhone(p.number);
        if (normalized != null) {
          phones.add(normalized);
          if (c.displayName.isNotEmpty && !phoneBookNames.containsKey(normalized)) {
            phoneBookNames[normalized] = c.displayName;
          }
        }
      }
    }

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
                final bookName = phoneBookNames[c.phone];
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

    return MessengerListPage(
      userPhone: _userPhone!,
      userName: _userName ?? _userPhone!,
      matchedContacts: _matchedContacts,
      contactsGranted: _contactsGranted,
    );
  }
}
