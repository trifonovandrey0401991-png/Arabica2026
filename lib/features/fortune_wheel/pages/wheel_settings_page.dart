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
        _isLoading = false;
      });
    }
  }

  Future<void> _saveSettings() async {
    setState(() => _isSaving = true);

    // Собираем обновлённые секторы
    final updatedSectors = <FortuneWheelSector>[];
    for (int i = 0; i < _sectors.length; i++) {
      final prob = double.tryParse(_probControllers[i].text) ?? 6.67;
      updatedSectors.add(_sectors[i].copyWith(
        text: _textControllers[i].text,
        probability: prob / 100,
      ));
    }

    final success = await FortuneWheelService.updateSettings(updatedSectors);

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
