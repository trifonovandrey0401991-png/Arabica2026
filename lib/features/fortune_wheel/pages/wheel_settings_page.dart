import 'package:flutter/material.dart';
import '../models/fortune_wheel_model.dart';
import '../services/fortune_wheel_service.dart';

/// Страница настроек секторов Колеса Удачи (для админа)
class WheelSettingsPage extends StatefulWidget {
  const WheelSettingsPage({super.key});

  @override
  State<WheelSettingsPage> createState() => _WheelSettingsPageState();
}

class _WheelSettingsPageState extends State<WheelSettingsPage> {
  List<FortuneWheelSector> _sectors = [];
  int _topEmployeesCount = 3; // Количество топ-сотрудников (1-10)
  bool _isLoading = true;
  bool _isSaving = false;

  final List<TextEditingController> _textControllers = [];
  final List<TextEditingController> _probControllers = [];

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  @override
  void dispose() {
    for (final c in _textControllers) {
      c.dispose();
    }
    for (final c in _probControllers) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _loadSettings() async {
    setState(() => _isLoading = true);

    final settings = await FortuneWheelService.getSettings();

    if (mounted) {
      _textControllers.clear();
      _probControllers.clear();

      final sectors = settings?.sectors ?? [];

      for (final sector in sectors) {
        _textControllers.add(TextEditingController(text: sector.text));
        _probControllers.add(
          TextEditingController(text: (sector.probability * 100).toStringAsFixed(1)),
        );
      }

      setState(() {
        _sectors = sectors;
        _topEmployeesCount = settings?.topEmployeesCount ?? 3; // Читаем topEmployeesCount
        _isLoading = false;
      });
    }
  }

  Future<void> _saveSettings() async {
    setState(() => _isSaving = true);

    // Валидация topEmployeesCount
    if (_topEmployeesCount < 1 || _topEmployeesCount > 10) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Количество должно быть от 1 до 10'),
          backgroundColor: Colors.red,
        ),
      );
      setState(() => _isSaving = false);
      return;
    }

    // Собираем обновлённые секторы
    final updatedSectors = <FortuneWheelSector>[];
    for (int i = 0; i < _sectors.length; i++) {
      final prob = double.tryParse(_probControllers[i].text) ?? 6.67;
      updatedSectors.add(_sectors[i].copyWith(
        text: _textControllers[i].text,
        probability: prob / 100,
      ));
    }

    // Создаём настройки с topEmployeesCount
    final updatedSettings = FortuneWheelSettings(
      topEmployeesCount: _topEmployeesCount,
      sectors: updatedSectors,
    );

    final success = await FortuneWheelService.updateSettings(updatedSettings);

    setState(() => _isSaving = false);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(success ? 'Настройки сохранены' : 'Ошибка сохранения'),
          backgroundColor: success ? Colors.green : Colors.red,
        ),
      );

      if (success) {
        Navigator.pop(context);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Настройка Колеса Удачи'),
        backgroundColor: const Color(0xFF004D40),
        actions: [
          IconButton(
            icon: const Icon(Icons.save),
            onPressed: _isSaving ? null : _saveSettings,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // Настройка количества топ-сотрудников
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF004D40).withOpacity(0.1),
                    border: Border(
                      bottom: BorderSide(color: Colors.grey.shade300),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Заголовок
                      Row(
                        children: [
                          const Icon(Icons.emoji_events, color: Color(0xFF004D40), size: 24),
                          const SizedBox(width: 12),
                          const Text(
                            'Количество призовых мест',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF004D40),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),

                      // Слайдер
                      Row(
                        children: [
                          Expanded(
                            child: Slider(
                              value: _topEmployeesCount.toDouble(),
                              min: 1,
                              max: 10,
                              divisions: 9,
                              activeColor: const Color(0xFF004D40),
                              inactiveColor: const Color(0xFF004D40).withOpacity(0.3),
                              label: _topEmployeesCount.toString(),
                              onChanged: (value) {
                                setState(() {
                                  _topEmployeesCount = value.toInt();
                                });
                              },
                            ),
                          ),
                          const SizedBox(width: 16),
                          // Текущее значение
                          Container(
                            width: 60,
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            decoration: BoxDecoration(
                              color: const Color(0xFF004D40),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Center(
                              child: Text(
                                '$_topEmployeesCount',
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 12),

                      // Предпросмотр распределения
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.grey.shade300),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Распределение прокруток:',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                                color: Colors.grey[700],
                              ),
                            ),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                for (int i = 0; i < _topEmployeesCount; i++)
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                    decoration: BoxDecoration(
                                      color: i == 0 ? Colors.amber[100] : Colors.grey[100],
                                      borderRadius: BorderRadius.circular(16),
                                      border: Border.all(
                                        color: i == 0 ? Colors.amber : Colors.grey,
                                        width: 1.5,
                                      ),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                          i == 0 ? '🥇' : i == 1 ? '🥈' : i == 2 ? '🥉' : '${i + 1}',
                                          style: const TextStyle(fontSize: 14),
                                        ),
                                        const SizedBox(width: 4),
                                        Text(
                                          '${i == 0 ? 2 : 1} спин${i == 0 ? 'а' : ''}',
                                          style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: i == 0 ? FontWeight.bold : FontWeight.normal,
                                            color: i == 0 ? Colors.amber[900] : Colors.grey[700],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                // Инфо
                Container(
                  padding: const EdgeInsets.all(16),
                  color: Colors.amber[50],
                  child: Row(
                    children: [
                      Icon(Icons.info_outline, color: Colors.amber[800]),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Сумма вероятностей должна быть 100%.\n'
                          'Текущая сумма: ${_calculateTotalProbability().toStringAsFixed(1)}%',
                          style: TextStyle(color: Colors.amber[900]),
                        ),
                      ),
                    ],
                  ),
                ),

                // Список секторов
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _sectors.length,
                    itemBuilder: (context, index) {
                      return _buildSectorCard(index);
                    },
                  ),
                ),

                // Кнопка сохранения
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton(
                      onPressed: _isSaving ? null : _saveSettings,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF004D40),
                      ),
                      child: _isSaving
                          ? const SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 2,
                              ),
                            )
                          : const Text(
                              'Сохранить',
                              style: TextStyle(fontSize: 16),
                            ),
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildSectorCard(int index) {
    final sector = _sectors[index];

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Заголовок с цветом
            Row(
              children: [
                Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    color: sector.color,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2),
                    boxShadow: [
                      BoxShadow(
                        color: sector.color.withOpacity(0.3),
                        blurRadius: 4,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  'Сектор ${index + 1}',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Текст приза
            TextField(
              controller: _textControllers[index],
              decoration: const InputDecoration(
                labelText: 'Текст приза',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 12),

            // Вероятность
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _probControllers[index],
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Вероятность (%)',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                const SizedBox(width: 12),
                // Быстрые кнопки
                IconButton(
                  icon: const Icon(Icons.remove_circle_outline),
                  color: Colors.red,
                  onPressed: () {
                    final current = double.tryParse(_probControllers[index].text) ?? 0;
                    if (current > 0) {
                      _probControllers[index].text = (current - 1).toStringAsFixed(1);
                      setState(() {});
                    }
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.add_circle_outline),
                  color: Colors.green,
                  onPressed: () {
                    final current = double.tryParse(_probControllers[index].text) ?? 0;
                    _probControllers[index].text = (current + 1).toStringAsFixed(1);
                    setState(() {});
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  double _calculateTotalProbability() {
    double total = 0;
    for (final c in _probControllers) {
      total += double.tryParse(c.text) ?? 0;
    }
    return total;
  }
}
