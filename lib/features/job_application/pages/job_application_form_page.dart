import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';
import 'dart:convert';
import '../../../core/utils/logger.dart';
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

  static const Color _emerald = Color(0xFF1A4D4D);
  static const Color _emeraldDark = Color(0xFF0D2E2E);
  static const Color _night = Color(0xFF051515);
  static const Color _gold = Color(0xFFD4AF37);

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
              content: Row(
                children: [
                  Icon(Icons.restore, color: _gold, size: 20),
                  const SizedBox(width: 8),
                  Text('Черновик восстановлен', style: TextStyle(color: Colors.white.withOpacity(0.9))),
                ],
              ),
              backgroundColor: _emeraldDark,
              duration: const Duration(seconds: 2),
            ),
          );
        }
      }
    } catch (e) {
      Logger.warning('Ошибка загрузки черновика: $e');
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
      Logger.warning('Ошибка сохранения черновика: $e');
    }
  }

  /// Очистка черновика
  Future<void> _clearDraft() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_draftKey);
    } catch (e) {
      Logger.warning('Ошибка очистки черновика: $e');
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
        SnackBar(
          content: const Text('Выберите хотя бы один магазин'),
          backgroundColor: Colors.red.shade700,
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
        SnackBar(
          content: const Row(
            children: [
              Icon(Icons.check_circle, color: Colors.white, size: 20),
              SizedBox(width: 8),
              Text('Анкета успешно отправлена!'),
            ],
          ),
          backgroundColor: _emerald,
        ),
      );

      // Возвращаемся к главному меню
      Navigator.of(context).popUntil((route) => route.isFirst);
    } else {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Ошибка при отправке анкеты'),
          backgroundColor: Colors.red.shade700,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _night,
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [_emerald, _emeraldDark, _night],
            stops: [0.0, 0.3, 1.0],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              // AppBar
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(
                  children: [
                    GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.white.withOpacity(0.1)),
                        ),
                        child: const Icon(Icons.arrow_back, color: Colors.white, size: 20),
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Text(
                        'Анкета соискателя',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // Body
              Expanded(
                child: _isLoading
                    ? Center(child: CircularProgressIndicator(color: _gold))
                    : Form(
                        key: _formKey,
                        child: ListView(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                          children: [
                            // Секция 1: Личные данные
                            _buildSectionCard(
                              title: 'Личные данные',
                              icon: Icons.person_outline,
                              accentColor: _gold,
                              children: [
                                _buildInputLabel('ФИО', required: true),
                                const SizedBox(height: 8),
                                TextFormField(
                                  controller: _fullNameController,
                                  decoration: _buildInputDecoration(
                                    hintText: 'Иванов Иван Иванович',
                                    prefixIcon: Icons.badge_outlined,
                                  ),
                                  style: TextStyle(color: Colors.white.withOpacity(0.9)),
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
                                  style: TextStyle(color: Colors.white.withOpacity(0.9)),
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
                            const SizedBox(height: 14),

                            // Секция 2: Желаемое время работы
                            _buildSectionCard(
                              title: 'Желаемое время работы',
                              icon: Icons.schedule_outlined,
                              accentColor: Colors.orange,
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
                                        color: Colors.indigo[300]!,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                            const SizedBox(height: 14),

                            // Секция 3: Выбор магазинов
                            _buildSectionCard(
                              title: 'Где хотите работать',
                              icon: Icons.store_outlined,
                              accentColor: _gold,
                              subtitle: 'Можно выбрать несколько магазинов',
                              children: [
                                // Счётчик выбранных
                                if (_selectedShopAddresses.isNotEmpty)
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                    margin: const EdgeInsets.only(bottom: 12),
                                    decoration: BoxDecoration(
                                      color: _gold.withOpacity(0.1),
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(color: _gold.withOpacity(0.2)),
                                    ),
                                    child: Row(
                                      children: [
                                        Icon(Icons.check_circle, color: _gold, size: 18),
                                        const SizedBox(width: 8),
                                        Text(
                                          'Выбрано магазинов: ${_selectedShopAddresses.length}',
                                          style: TextStyle(
                                            color: _gold,
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
                            SizedBox(
                              width: double.infinity,
                              child: OutlinedButton(
                                onPressed: _isSubmitting ? null : _submitApplication,
                                style: OutlinedButton.styleFrom(
                                  side: BorderSide(color: _gold.withOpacity(0.5)),
                                  padding: const EdgeInsets.symmetric(vertical: 18),
                                  backgroundColor: _gold.withOpacity(0.12),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                ),
                                child: _isSubmitting
                                    ? SizedBox(
                                        width: 24,
                                        height: 24,
                                        child: CircularProgressIndicator(
                                          color: _gold,
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : Row(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          Icon(Icons.send_rounded, size: 22, color: _gold),
                                          const SizedBox(width: 10),
                                          Text(
                                            'Отправить анкету',
                                            style: TextStyle(
                                              fontSize: 18,
                                              fontWeight: FontWeight.w600,
                                              color: _gold,
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
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionCard({
    required String title,
    required IconData icon,
    required Color accentColor,
    String? subtitle,
    required List<Widget> children,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.06),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Заголовок секции
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: accentColor.withOpacity(0.08),
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
                    color: accentColor.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, color: accentColor, size: 22),
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
                          color: Colors.white.withOpacity(0.9),
                        ),
                      ),
                      if (subtitle != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          subtitle,
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.white.withOpacity(0.4),
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
            color: Colors.white.withOpacity(0.6),
          ),
        ),
        if (required) ...[
          const SizedBox(width: 4),
          Text(
            '*',
            style: TextStyle(
              color: _gold,
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
      hintStyle: TextStyle(color: Colors.white.withOpacity(0.25)),
      prefixIcon: Icon(prefixIcon, color: Colors.white.withOpacity(0.3)),
      filled: true,
      fillColor: Colors.white.withOpacity(0.06),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.white.withOpacity(0.1)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.white.withOpacity(0.1)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: _gold.withOpacity(0.5), width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.red.shade300),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.red.shade300, width: 2),
      ),
      errorStyle: TextStyle(color: Colors.red.shade300),
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
        _saveDraft();
      },
      borderRadius: BorderRadius.circular(14),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isSelected ? color.withOpacity(0.12) : Colors.white.withOpacity(0.04),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSelected ? color.withOpacity(0.5) : Colors.white.withOpacity(0.1),
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isSelected ? color.withOpacity(0.2) : Colors.white.withOpacity(0.06),
                shape: BoxShape.circle,
              ),
              child: Icon(
                icon,
                color: isSelected ? color : Colors.white.withOpacity(0.4),
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
                color: isSelected ? color : Colors.white.withOpacity(0.6),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: TextStyle(
                fontSize: 12,
                color: isSelected ? color.withOpacity(0.8) : Colors.white.withOpacity(0.35),
              ),
            ),
            if (isSelected) ...[
              const SizedBox(height: 8),
              Icon(Icons.check_circle, color: color, size: 20),
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
          _saveDraft();
        },
        borderRadius: BorderRadius.circular(12),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: isSelected
                ? _gold.withOpacity(0.1)
                : Colors.white.withOpacity(0.04),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected ? _gold.withOpacity(0.4) : Colors.white.withOpacity(0.1),
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
                  color: isSelected ? _gold : Colors.transparent,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: isSelected ? _gold : Colors.white.withOpacity(0.3),
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
                      ? _gold.withOpacity(0.15)
                      : Colors.white.withOpacity(0.06),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  shop.icon,
                  color: isSelected ? _gold : Colors.white.withOpacity(0.4),
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
                            ? Colors.white.withOpacity(0.95)
                            : Colors.white.withOpacity(0.7),
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      shop.address,
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.white.withOpacity(0.4),
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
