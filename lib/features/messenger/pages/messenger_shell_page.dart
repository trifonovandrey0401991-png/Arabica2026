import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/theme/app_colors.dart';
import 'messenger_list_page.dart';

/// Полноэкранная обёртка мессенджера.
/// Единственная точка входа из основного приложения.
/// Автоматически загружает phone/name из SharedPreferences (как EmployeeChatsListPage).
class MessengerShellPage extends StatefulWidget {
  const MessengerShellPage({super.key});

  @override
  State<MessengerShellPage> createState() => _MessengerShellPageState();
}

class _MessengerShellPageState extends State<MessengerShellPage> {
  String? _userPhone;
  String? _userName;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadUser();
  }

  Future<void> _loadUser() async {
    final prefs = await SharedPreferences.getInstance();
    final phone = prefs.getString('user_phone') ?? prefs.getString('userPhone') ?? '';
    final name = prefs.getString('user_name') ?? prefs.getString('userName') ?? '';

    if (mounted) {
      setState(() {
        _userPhone = phone;
        _userName = name.isNotEmpty ? name : phone;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator(color: AppColors.emerald)),
      );
    }

    if (_userPhone == null || _userPhone!.isEmpty) {
      return Scaffold(
        appBar: AppBar(
          backgroundColor: AppColors.emerald,
          foregroundColor: Colors.white,
          title: const Text('Мессенджер'),
        ),
        body: const Center(child: Text('Ошибка: не удалось определить пользователя')),
      );
    }

    return MessengerListPage(
      userPhone: _userPhone!,
      userName: _userName ?? _userPhone!,
    );
  }
}
