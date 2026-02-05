import 'package:flutter/material.dart';

import 'pin_setup_page.dart';

/// Страница ввода номера телефона
///
/// Упрощённая регистрация:
/// 1. Пользователь вводит номер телефона и имя
/// 2. Нажимает "Продолжить"
/// 3. Сразу переходит к созданию PIN-кода (без Telegram)
class PhoneEntryPage extends StatefulWidget {
  /// Имя пользователя (если уже известно)
  final String? name;

  /// Callback при успешном завершении авторизации
  final VoidCallback? onSuccess;

  const PhoneEntryPage({
    super.key,
    this.name,
    this.onSuccess,
  });

  @override
  State<PhoneEntryPage> createState() => _PhoneEntryPageState();
}

class _PhoneEntryPageState extends State<PhoneEntryPage> {
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _nameController = TextEditingController();

  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    if (widget.name != null) {
      _nameController.text = widget.name!;
    }
  }

  @override
  void dispose() {
    _phoneController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  String get _fullPhone {
    final digits = _phoneController.text.replaceAll(RegExp(r'\D'), '');
    if (digits.startsWith('7') && digits.length == 11) {
      return digits;
    } else if (digits.length == 10) {
      return '7$digits';
    }
    return digits;
  }

  bool get _isPhoneValid {
    final phone = _fullPhone;
    return phone.length == 11 && phone.startsWith('7');
  }

  bool get _isNameValid {
    return _nameController.text.trim().length >= 2;
  }

  bool get _canSubmit {
    return _isPhoneValid && _isNameValid;
  }

  void _continue() {
    if (!_canSubmit) return;

    // Сразу переходим к созданию PIN (без Telegram)
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => PinSetupPage(
          phone: _fullPhone,
          name: _nameController.text.trim(),
          onSuccess: widget.onSuccess,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Регистрация'),
        centerTitle: true,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 32),

              // Иконка
              Icon(
                Icons.person_add_outlined,
                size: 80,
                color: Theme.of(context).primaryColor,
              ),
              const SizedBox(height: 24),

              // Заголовок
              Text(
                'Добро пожаловать!',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),

              // Описание
              Text(
                'Введите ваши данные для регистрации',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Colors.grey[600],
                    ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),

              // Поле имени
              TextField(
                controller: _nameController,
                decoration: InputDecoration(
                  labelText: 'Ваше имя',
                  hintText: 'Иван',
                  prefixIcon: const Icon(Icons.person_outline),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  filled: true,
                  fillColor: Colors.grey[50],
                ),
                textCapitalization: TextCapitalization.words,
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 16),

              // Поле телефона
              TextField(
                controller: _phoneController,
                decoration: InputDecoration(
                  labelText: 'Номер телефона',
                  hintText: '9001234567',
                  prefixIcon: const Icon(Icons.phone_outlined),
                  prefixText: '+7 ',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  filled: true,
                  fillColor: Colors.grey[50],
                  errorText: _errorMessage,
                ),
                keyboardType: TextInputType.phone,
                maxLength: 10,
                onChanged: (_) => setState(() {
                  _errorMessage = null;
                }),
              ),
              const SizedBox(height: 24),

              // Кнопка продолжения
              ElevatedButton(
                onPressed: _canSubmit ? _continue : null,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text(
                  'Продолжить',
                  style: TextStyle(fontSize: 16),
                ),
              ),
              const SizedBox(height: 24),

              // Информация о безопасности
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.green[50],
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.green[200]!),
                ),
                child: Row(
                  children: [
                    Icon(Icons.security, color: Colors.green[700], size: 32),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Безопасность',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.green[900],
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'На следующем шаге вы создадите PIN-код для защиты аккаунта',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.green[700],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
