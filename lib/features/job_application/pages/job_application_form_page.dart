import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';
import 'dart:convert';
import '../../shops/models/shop_model.dart';
import '../services/job_application_service.dart';

class JobApplicationFormPage extends StatefulWidget {
  const JobApplicationFormPage({super.key});

  @override
  State<JobApplicationFormPage> createState() => _JobApplicationFormPageState();
}

class _JobApplicationFormPageState extends State<JobApplicationFormPage> {
  final _formKey = GlobalKey<FormState>();
  final _fullNameController = TextEditingController();
  final _phoneController = TextEditingController();

  String _selectedShift = 'day'; // 'day' или 'night'
  List<Shop> _shops = [];
  List<String> _selectedShopAddresses = [];
  bool _isLoading = true;
  bool _isSubmitting = false;
  Timer? _autosaveTimer;

  static const String _draftKey = 'job_application_draft';

  @override
  void initState() {
    super.initState();
    _loadShops();
    _loadDraft();
    _startAutosave();

    // Слушаем изменения в полях для автосохранения
    _fullNameController.addListener(_onFormChanged);
    _phoneController.addListener(_onFormChanged);
  }

  @override
  void dispose() {
    _autosaveTimer?.cancel();
    _fullNameController.removeListener(_onFormChanged);
    _phoneController.removeListener(_onFormChanged);
    _fullNameController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  /// Загрузка черновика из SharedPreferences
  Future<void> _loadDraft() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final draftJson = prefs.getString(_draftKey);

      if (draftJson != null) {
        final draft = json.decode(draftJson);

        setState(() {
          _fullNameController.text = draft['fullName'] ?? '';
          _phoneController.text = draft['phone'] ?? '';
          _selectedShift = draft['selectedShift'] ?? 'day';
          _selectedShopAddresses = List<String>.from(draft['selectedShopAddresses'] ?? []);
        });

        // Показываем уведомление о восстановлении черновика
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Row(
                children: [
                  Icon(Icons.restore, color: Colors.white, size: 20),
                  SizedBox(width: 8),
                  Text('Черновик восстановлен'),
                ],
              ),
              backgroundColor: const Color(0xFF004D40),
              duration: const Duration(seconds: 2),
            ),
          );
        }
      }
    } catch (e) {
      print('Ошибка загрузки черновика: $e');
    }
  }

  /// Сохранение черновика в SharedPreferences
  Future<void> _saveDraft() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final draft = {
        'fullName': _fullNameController.text.trim(),
        'phone': _phoneController.text.trim(),
        'selectedShift': _selectedShift,
        'selectedShopAddresses': _selectedShopAddresses,
        'savedAt': DateTime.now().toIso8601String(),
      };

      await prefs.setString(_draftKey, json.encode(draft));
    } catch (e) {
      print('Ошибка сохранения черновика: $e');
    }
  }

  /// Очистка черновика
  Future<void> _clearDraft() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_draftKey);
    } catch (e) {
      print('Ошибка очистки черновика: $e');
    }
  }

  /// Обработчик изменения формы
  void _onFormChanged() {
    // Сохраняем черновик при каждом изменении (с дебаунсингом через таймер)
  }

  /// Запуск автосохранения (каждые 30 секунд)
  void _startAutosave() {
    _autosaveTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
      _saveDraft();
    });
  }

  Future<void> _loadShops() async {
    final shops = await Shop.loadShopsFromServer();
    setState(() {
      _shops = shops;
      _isLoading = false;
    });
  }

  Future<void> _submitApplication() async {
    if (!_formKey.currentState!.validate()) return;

    if (_selectedShopAddresses.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Выберите хотя бы один магазин'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() => _isSubmitting = true);

    final result = await JobApplicationService.create(
      fullName: _fullNameController.text.trim(),
      phone: _phoneController.text.trim(),
      preferredShift: _selectedShift,
      shopAddresses: _selectedShopAddresses,
    );

    setState(() => _isSubmitting = false);

    if (result != null) {
      // Очищаем черновик после успешной отправки
      await _clearDraft();

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Анкета успешно отправлена!'),
          backgroundColor: Colors.green,
        ),
      );

      // Возвращаемся к главному меню
      Navigator.of(context).popUntil((route) => route.isFirst);
    } else {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Ошибка при отправке анкеты'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: const Text('Анкета соискателя'),
        backgroundColor: const Color(0xFF004D40),
        elevation: 0,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  // Секция 1: Личные данные
                  _buildSectionCard(
                    title: 'Личные данные',
                    icon: Icons.person_outline,
                    iconColor: const Color(0xFF004D40),
                    children: [
                      // ФИО
                      _buildInputLabel('ФИО', required: true),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: _fullNameController,
                        decoration: _buildInputDecoration(
                          hintText: 'Иванов Иван Иванович',
                          prefixIcon: Icons.badge_outlined,
                        ),
                        textCapitalization: TextCapitalization.words,
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Введите ФИО';
                          }
                          if (value.trim().split(' ').length < 2) {
                            return 'Введите полное ФИО';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 20),

                      // Номер телефона
                      _buildInputLabel('Номер телефона', required: true),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: _phoneController,
                        decoration: _buildInputDecoration(
                          hintText: '+7 900 123 45 67',
                          prefixIcon: Icons.phone_outlined,
                        ),
                        keyboardType: TextInputType.phone,
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Введите номер телефона';
                          }
                          final digits = value.replaceAll(RegExp(r'[^\d]'), '');
                          if (digits.length < 10) {
                            return 'Введите корректный номер телефона';
                          }
                          return null;
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Секция 2: Желаемое время работы
                  _buildSectionCard(
                    title: 'Желаемое время работы',
                    icon: Icons.schedule_outlined,
                    iconColor: Colors.orange,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: _buildShiftOption(
                              value: 'day',
                              label: 'Дневная смена',
                              subtitle: '08:00 - 20:00',
                              icon: Icons.wb_sunny_outlined,
                              color: Colors.orange,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _buildShiftOption(
                              value: 'night',
                              label: 'Ночная смена',
                              subtitle: '20:00 - 08:00',
                              icon: Icons.nightlight_outlined,
                              color: Colors.indigo,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Секция 3: Выбор магазинов
                  _buildSectionCard(
                    title: 'Где хотите работать',
                    icon: Icons.store_outlined,
                    iconColor: Colors.teal,
                    subtitle: 'Можно выбрать несколько магазинов',
                    children: [
                      // Счётчик выбранных
                      if (_selectedShopAddresses.isNotEmpty)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          margin: const EdgeInsets.only(bottom: 12),
                          decoration: BoxDecoration(
                            color: const Color(0xFF004D40).withOpacity(0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.check_circle,
                                color: Color(0xFF004D40),
                                size: 18,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'Выбрано магазинов: ${_selectedShopAddresses.length}',
                                style: const TextStyle(
                                  color: Color(0xFF004D40),
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                      // Список магазинов
                      ..._shops.map((shop) => _buildShopCheckbox(shop)),
                    ],
                  ),
                  const SizedBox(height: 24),

                  // Кнопка отправки
                  Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      gradient: const LinearGradient(
                        colors: [Color(0xFF004D40), Color(0xFF00796B)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF004D40).withOpacity(0.3),
                          blurRadius: 8,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: ElevatedButton(
                      onPressed: _isSubmitting ? null : _submitApplication,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.transparent,
                        shadowColor: Colors.transparent,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 18),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      child: _isSubmitting
                          ? const SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 2,
                              ),
                            )
                          : const Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.send_rounded, size: 22),
                                SizedBox(width: 10),
                                Text(
                                  'Отправить анкету',
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                    ),
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
    );
  }

  Widget _buildSectionCard({
    required String title,
    required IconData icon,
    required Color iconColor,
    String? subtitle,
    required List<Widget> children,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Заголовок секции
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: iconColor.withOpacity(0.08),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(16),
                topRight: Radius.circular(16),
              ),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: iconColor.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, color: iconColor, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                          color: Colors.grey[800],
                        ),
                      ),
                      if (subtitle != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          subtitle,
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
          // Содержимое
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: children,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInputLabel(String label, {bool required = false}) {
    return Row(
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: Colors.grey[700],
          ),
        ),
        if (required) ...[
          const SizedBox(width: 4),
          const Text(
            '*',
            style: TextStyle(
              color: Colors.red,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ],
    );
  }

  InputDecoration _buildInputDecoration({
    required String hintText,
    required IconData prefixIcon,
  }) {
    return InputDecoration(
      hintText: hintText,
      hintStyle: TextStyle(color: Colors.grey[400]),
      prefixIcon: Icon(prefixIcon, color: Colors.grey[500]),
      filled: true,
      fillColor: Colors.grey[50],
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.grey[300]!),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.grey[300]!),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFF004D40), width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Colors.red),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Colors.red, width: 2),
      ),
    );
  }

  Widget _buildShiftOption({
    required String value,
    required String label,
    required String subtitle,
    required IconData icon,
    required Color color,
  }) {
    final isSelected = _selectedShift == value;

    return InkWell(
      onTap: () {
        setState(() => _selectedShift = value);
        _saveDraft(); // Сохраняем черновик при изменении смены
      },
      borderRadius: BorderRadius.circular(14),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isSelected ? color.withOpacity(0.12) : Colors.grey[50],
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSelected ? color : Colors.grey[300]!,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isSelected ? color.withOpacity(0.15) : Colors.grey[200],
                shape: BoxShape.circle,
              ),
              child: Icon(
                icon,
                color: isSelected ? color : Colors.grey[500],
                size: 28,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: isSelected ? color : Colors.grey[700],
              ),
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: TextStyle(
                fontSize: 12,
                color: isSelected ? color.withOpacity(0.8) : Colors.grey[500],
              ),
            ),
            if (isSelected) ...[
              const SizedBox(height: 8),
              Icon(
                Icons.check_circle,
                color: color,
                size: 20,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildShopCheckbox(Shop shop) {
    final isSelected = _selectedShopAddresses.contains(shop.address);

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        onTap: () {
          setState(() {
            if (isSelected) {
              _selectedShopAddresses.remove(shop.address);
            } else {
              _selectedShopAddresses.add(shop.address);
            }
          });
          _saveDraft(); // Сохраняем черновик при изменении магазинов
        },
        borderRadius: BorderRadius.circular(12),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: isSelected
                ? const Color(0xFF004D40).withOpacity(0.08)
                : Colors.grey[50],
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected ? const Color(0xFF004D40) : Colors.grey[300]!,
              width: isSelected ? 2 : 1,
            ),
          ),
          child: Row(
            children: [
              // Чекбокс
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  color: isSelected ? const Color(0xFF004D40) : Colors.white,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: isSelected ? const Color(0xFF004D40) : Colors.grey[400]!,
                    width: 2,
                  ),
                ),
                child: isSelected
                    ? const Icon(
                        Icons.check,
                        color: Colors.white,
                        size: 16,
                      )
                    : null,
              ),
              const SizedBox(width: 14),
              // Иконка магазина
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: isSelected
                      ? const Color(0xFF004D40).withOpacity(0.15)
                      : Colors.grey[200],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  shop.icon,
                  color: isSelected ? const Color(0xFF004D40) : Colors.grey[500],
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              // Текст
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      shop.name,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: isSelected
                            ? const Color(0xFF004D40)
                            : Colors.grey[800],
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      shop.address,
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey[600],
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
