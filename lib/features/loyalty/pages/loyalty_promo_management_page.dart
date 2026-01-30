import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/utils/logger.dart';
import '../services/loyalty_service.dart';

/// Страница управления условиями акций для админа
class LoyaltyPromoManagementPage extends StatefulWidget {
  const LoyaltyPromoManagementPage({super.key});

  @override
  State<LoyaltyPromoManagementPage> createState() => _LoyaltyPromoManagementPageState();
}

class _LoyaltyPromoManagementPageState extends State<LoyaltyPromoManagementPage> {
  final TextEditingController _promoTextController = TextEditingController();
  final TextEditingController _pointsRequiredController = TextEditingController(text: '10');
  final TextEditingController _drinksToGiveController = TextEditingController(text: '1');
  bool _isLoading = false;
  bool _isSaving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadPromoSettings();
  }

  @override
  void dispose() {
    _promoTextController.dispose();
    _pointsRequiredController.dispose();
    _drinksToGiveController.dispose();
    super.dispose();
  }

  Future<void> _loadPromoSettings() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final settings = await LoyaltyService.fetchPromoSettings();
      _promoTextController.text = settings.promoText;
      _pointsRequiredController.text = settings.pointsRequired > 0
          ? settings.pointsRequired.toString()
          : '10';
      _drinksToGiveController.text = settings.drinksToGive > 0
          ? settings.drinksToGive.toString()
          : '1';
      Logger.debug('✅ Настройки акции загружены: ${_pointsRequiredController.text}+${_drinksToGiveController.text}');
    } catch (e) {
      Logger.error('Ошибка загрузки настроек акции', e);
      _error = 'Ошибка загрузки: ${e.toString()}';
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _savePromoSettings() async {
    final pointsRequired = int.tryParse(_pointsRequiredController.text) ?? 0;
    final drinksToGive = int.tryParse(_drinksToGiveController.text) ?? 0;

    if (pointsRequired < 1 || pointsRequired > 100) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Количество баллов должно быть от 1 до 100'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    if (drinksToGive < 1 || drinksToGive > 10) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Количество напитков должно быть от 1 до 10'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() {
      _isSaving = true;
      _error = null;
    });

    try {
      // Получаем phone текущего пользователя для проверки роли
      // Проверяем оба ключа - для клиентов (user_phone) и сотрудников (userPhone)
      final prefs = await SharedPreferences.getInstance();
      final employeePhone = prefs.getString('userPhone') ?? prefs.getString('user_phone') ?? '';

      final success = await LoyaltyService.savePromoSettings(
        promoText: _promoTextController.text.trim(),
        pointsRequired: pointsRequired,
        drinksToGive: drinksToGive,
        employeePhone: employeePhone,
      );

      if (success) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Настройки акции успешно сохранены'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } else {
        _error = 'Не удалось сохранить настройки акции';
      }
    } catch (e) {
      Logger.error('Ошибка сохранения настроек акции', e);
      _error = 'Ошибка сохранения: ${e.toString()}';
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Управление акцией'),
        backgroundColor: const Color(0xFF004D40),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Карточка с настройками формулы акции
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Формула акции',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'Укажите сколько напитков нужно купить и сколько получить бесплатно',
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey,
                            ),
                          ),
                          const SizedBox(height: 16),
                          Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: _pointsRequiredController,
                                  keyboardType: TextInputType.number,
                                  inputFormatters: [
                                    FilteringTextInputFormatter.digitsOnly,
                                    LengthLimitingTextInputFormatter(3),
                                  ],
                                  decoration: const InputDecoration(
                                    labelText: 'Сколько купить',
                                    hintText: '10',
                                    border: OutlineInputBorder(),
                                    filled: true,
                                    fillColor: Colors.white,
                                    prefixIcon: Icon(Icons.shopping_cart),
                                  ),
                                ),
                              ),
                              const Padding(
                                padding: EdgeInsets.symmetric(horizontal: 16),
                                child: Text(
                                  '+',
                                  style: TextStyle(
                                    fontSize: 24,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF004D40),
                                  ),
                                ),
                              ),
                              Expanded(
                                child: TextField(
                                  controller: _drinksToGiveController,
                                  keyboardType: TextInputType.number,
                                  inputFormatters: [
                                    FilteringTextInputFormatter.digitsOnly,
                                    LengthLimitingTextInputFormatter(2),
                                  ],
                                  decoration: const InputDecoration(
                                    labelText: 'Сколько выдать',
                                    hintText: '1',
                                    border: OutlineInputBorder(),
                                    filled: true,
                                    fillColor: Colors.white,
                                    prefixIcon: Icon(Icons.card_giftcard),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.teal.shade50,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.teal.shade200),
                            ),
                            child: Row(
                              children: [
                                Icon(Icons.info_outline, color: Colors.teal.shade700),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    'Пример: ${_pointsRequiredController.text.isEmpty ? "10" : _pointsRequiredController.text} + ${_drinksToGiveController.text.isEmpty ? "1" : _drinksToGiveController.text} означает "купи ${_pointsRequiredController.text.isEmpty ? "10" : _pointsRequiredController.text} напитков, получи ${_drinksToGiveController.text.isEmpty ? "1" : _drinksToGiveController.text} бесплатно"',
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: Colors.teal.shade700,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  // Карточка с текстом условий
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Текст условий акции',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'Этот текст будет отображаться в карте лояльности клиента',
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey,
                            ),
                          ),
                          const SizedBox(height: 16),
                          TextField(
                            controller: _promoTextController,
                            maxLines: 6,
                            decoration: const InputDecoration(
                              labelText: 'Текст условий',
                              hintText: 'Например: При покупке 10 напитков получите 1 бесплатный...',
                              border: OutlineInputBorder(),
                              filled: true,
                              fillColor: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.red[50],
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.red),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.error, color: Colors.red),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _error!,
                              style: const TextStyle(color: Colors.red),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _isSaving ? null : _savePromoSettings,
                      icon: _isSaving
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                              ),
                            )
                          : const Icon(Icons.save),
                      label: Text(_isSaving ? 'Сохранение...' : 'Сохранить настройки'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF004D40),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
