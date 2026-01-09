import 'package:flutter/material.dart';
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

  @override
  void initState() {
    super.initState();
    _loadShops();
  }

  @override
  void dispose() {
    _fullNameController.dispose();
    _phoneController.dispose();
    super.dispose();
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
      appBar: AppBar(
        title: const Text('Анкета'),
        backgroundColor: const Color(0xFF004D40),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  // 1. ФИО
                  TextFormField(
                    controller: _fullNameController,
                    decoration: const InputDecoration(
                      labelText: 'ФИО',
                      hintText: 'Иванов Иван Иванович',
                      prefixIcon: Icon(Icons.person),
                      border: OutlineInputBorder(),
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
                  const SizedBox(height: 16),

                  // 2. Номер телефона
                  TextFormField(
                    controller: _phoneController,
                    decoration: const InputDecoration(
                      labelText: 'Номер телефона',
                      hintText: '+7 900 123 45 67',
                      prefixIcon: Icon(Icons.phone),
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.phone,
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'Введите номер телефона';
                      }
                      // Убираем все нецифровые символы для проверки
                      final digits = value.replaceAll(RegExp(r'[^\d]'), '');
                      if (digits.length < 10) {
                        return 'Введите корректный номер телефона';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 24),

                  // 3. Желаемое время работы
                  const Text(
                    'Желаемое время работы',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: _buildShiftOption(
                          value: 'day',
                          label: 'День',
                          icon: Icons.wb_sunny,
                          color: Colors.orange,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _buildShiftOption(
                          value: 'night',
                          label: 'Ночь',
                          icon: Icons.nightlight_round,
                          color: Colors.indigo,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),

                  // 4. Где хотите работать
                  const Text(
                    'Где хотите работать',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Можно выбрать несколько магазинов',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey[600],
                    ),
                  ),
                  const SizedBox(height: 8),
                  ..._shops.map((shop) => _buildShopCheckbox(shop)),
                  const SizedBox(height: 32),

                  // Кнопка отправки
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _isSubmitting ? null : _submitApplication,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF004D40),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
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
                          : const Text(
                              'Отправить анкету',
                              style: TextStyle(fontSize: 18),
                            ),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            ),
    );
  }

  Widget _buildShiftOption({
    required String value,
    required String label,
    required IconData icon,
    required Color color,
  }) {
    final isSelected = _selectedShift == value;

    return InkWell(
      onTap: () => setState(() => _selectedShift = value),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
        decoration: BoxDecoration(
          color: isSelected ? color.withOpacity(0.1) : Colors.grey[100],
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? color : Colors.grey[300]!,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Column(
          children: [
            Icon(
              icon,
              color: isSelected ? color : Colors.grey[600],
              size: 32,
            ),
            const SizedBox(height: 8),
            Text(
              label,
              style: TextStyle(
                fontSize: 16,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                color: isSelected ? color : Colors.grey[700],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildShopCheckbox(Shop shop) {
    final isSelected = _selectedShopAddresses.contains(shop.address);

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: CheckboxListTile(
        value: isSelected,
        onChanged: (value) {
          setState(() {
            if (value == true) {
              _selectedShopAddresses.add(shop.address);
            } else {
              _selectedShopAddresses.remove(shop.address);
            }
          });
        },
        title: Text(
          shop.name,
          style: const TextStyle(fontWeight: FontWeight.w500),
        ),
        subtitle: Text(
          shop.address,
          style: TextStyle(
            fontSize: 13,
            color: Colors.grey[600],
          ),
        ),
        secondary: Icon(
          shop.icon,
          color: isSelected ? const Color(0xFF004D40) : Colors.grey,
        ),
        activeColor: const Color(0xFF004D40),
        checkColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
      ),
    );
  }
}
