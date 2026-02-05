import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../models/loyalty_gamification_model.dart';
import '../services/loyalty_gamification_service.dart';

/// Страница настроек геймификации программы лояльности
class LoyaltyGamificationSettingsPage extends StatefulWidget {
  const LoyaltyGamificationSettingsPage({super.key});

  @override
  State<LoyaltyGamificationSettingsPage> createState() =>
      _LoyaltyGamificationSettingsPageState();
}

class _LoyaltyGamificationSettingsPageState
    extends State<LoyaltyGamificationSettingsPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _isLoading = true;
  bool _isSaving = false;

  // Данные уровней
  List<LoyaltyLevel> _levels = [];
  final List<TextEditingController> _levelNameControllers = [];
  final List<TextEditingController> _levelMinDrinksControllers = [];

  // Данные колеса
  WheelSettings _wheelSettings = const WheelSettings(
    enabled: true,
    freeDrinksPerSpin: 5,
    sectors: [],
  );
  final TextEditingController _freeDrinksPerSpinController =
      TextEditingController();
  final List<TextEditingController> _sectorTextControllers = [];
  final List<TextEditingController> _sectorProbControllers = [];
  final List<TextEditingController> _sectorValueControllers = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadSettings();
  }

  @override
  void dispose() {
    _tabController.dispose();
    for (final c in _levelNameControllers) {
      c.dispose();
    }
    for (final c in _levelMinDrinksControllers) {
      c.dispose();
    }
    _freeDrinksPerSpinController.dispose();
    for (final c in _sectorTextControllers) {
      c.dispose();
    }
    for (final c in _sectorProbControllers) {
      c.dispose();
    }
    for (final c in _sectorValueControllers) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _loadSettings() async {
    setState(() => _isLoading = true);

    final settings = await LoyaltyGamificationService.fetchSettings();

    if (mounted) {
      // Очищаем контроллеры
      for (final c in _levelNameControllers) {
        c.dispose();
      }
      for (final c in _levelMinDrinksControllers) {
        c.dispose();
      }
      for (final c in _sectorTextControllers) {
        c.dispose();
      }
      for (final c in _sectorProbControllers) {
        c.dispose();
      }
      for (final c in _sectorValueControllers) {
        c.dispose();
      }

      _levelNameControllers.clear();
      _levelMinDrinksControllers.clear();
      _sectorTextControllers.clear();
      _sectorProbControllers.clear();
      _sectorValueControllers.clear();

      // Инициализируем уровни
      for (final level in settings.levels) {
        _levelNameControllers
            .add(TextEditingController(text: level.name));
        _levelMinDrinksControllers
            .add(TextEditingController(text: level.minFreeDrinks.toString()));
      }

      // Инициализируем колесо
      _freeDrinksPerSpinController.text =
          settings.wheel.freeDrinksPerSpin.toString();
      for (final sector in settings.wheel.sectors) {
        _sectorTextControllers.add(TextEditingController(text: sector.text));
        _sectorProbControllers.add(TextEditingController(
            text: (sector.probability * 100).toStringAsFixed(1)));
        _sectorValueControllers
            .add(TextEditingController(text: sector.prizeValue.toString()));
      }

      setState(() {
        _levels = settings.levels;
        _wheelSettings = settings.wheel;
        _isLoading = false;
      });
    }
  }

  Future<void> _saveSettings() async {
    setState(() => _isSaving = true);

    // Собираем уровни
    final updatedLevels = <LoyaltyLevel>[];
    for (int i = 0; i < _levels.length; i++) {
      updatedLevels.add(_levels[i].copyWith(
        name: _levelNameControllers[i].text,
        minFreeDrinks:
            int.tryParse(_levelMinDrinksControllers[i].text) ?? 0,
      ));
    }

    // Собираем секторы колеса
    final updatedSectors = <WheelSector>[];
    for (int i = 0; i < _wheelSettings.sectors.length; i++) {
      final prob = double.tryParse(_sectorProbControllers[i].text) ?? 10.0;
      updatedSectors.add(_wheelSettings.sectors[i].copyWith(
        text: _sectorTextControllers[i].text,
        probability: prob / 100,
        prizeValue: int.tryParse(_sectorValueControllers[i].text) ?? 1,
      ));
    }

    final updatedSettings = GamificationSettings(
      levels: updatedLevels,
      wheel: _wheelSettings.copyWith(
        freeDrinksPerSpin:
            int.tryParse(_freeDrinksPerSpinController.text) ?? 5,
        sectors: updatedSectors,
      ),
    );

    // TODO: Получить phone текущего пользователя
    final success = await LoyaltyGamificationService.saveSettings(
      settings: updatedSettings,
      employeePhone: '',
    );

    setState(() => _isSaving = false);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(success ? 'Настройки сохранены' : 'Ошибка сохранения'),
          backgroundColor: success ? Colors.green : Colors.red,
        ),
      );

      if (success) {
        _loadSettings();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        title: const Text('Программа лояльности'),
        backgroundColor: const Color(0xFF004D40),
        elevation: 0,
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          tabs: const [
            Tab(text: 'Уровни', icon: Icon(Icons.workspace_premium)),
            Tab(text: 'Колесо удачи', icon: Icon(Icons.casino)),
          ],
        ),
        actions: [
          if (!_isLoading)
            _isSaving
                ? const Padding(
                    padding: EdgeInsets.all(16),
                    child: SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    ),
                  )
                : IconButton(
                    icon: const Icon(Icons.save),
                    onPressed: _saveSettings,
                    tooltip: 'Сохранить',
                  ),
        ],
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFF004D40)))
          : TabBarView(
              controller: _tabController,
              children: [
                _buildLevelsTab(),
                _buildWheelTab(),
              ],
            ),
    );
  }

  Widget _buildLevelsTab() {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _levels.length,
      itemBuilder: (context, index) {
        return _buildLevelCard(index);
      },
    );
  }

  Widget _buildLevelCard(int index) {
    final level = _levels[index];

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Заголовок с номером и значком
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: level.color,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Center(
                    child: level.badge.type == 'icon'
                        ? Icon(
                            level.badge.getIcon() ?? Icons.emoji_events,
                            color: Colors.white,
                            size: 24,
                          )
                        : const Icon(Icons.image, color: Colors.white, size: 24),
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  'Уровень ${index + 1}',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                // Кнопка выбора цвета
                InkWell(
                  onTap: () => _showColorPicker(index),
                  child: Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: level.color,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.grey.shade300),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            // Название уровня
            TextField(
              controller: _levelNameControllers[index],
              decoration: const InputDecoration(
                labelText: 'Название',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 12),
            // Порог напитков
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _levelMinDrinksControllers[index],
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Мин. напитков',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                // Кнопка выбора значка
                ElevatedButton.icon(
                  onPressed: () => _showBadgeSelector(index),
                  icon: const Icon(Icons.edit, size: 18),
                  label: const Text('Значок'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF004D40),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _showColorPicker(int index) {
    final colors = [
      const Color(0xFF78909C), // Blue Grey
      const Color(0xFF4CAF50), // Green
      const Color(0xFF2196F3), // Blue
      const Color(0xFF9C27B0), // Purple
      const Color(0xFFFF9800), // Orange
      const Color(0xFFF44336), // Red
      const Color(0xFF00BCD4), // Cyan
      const Color(0xFFE91E63), // Pink
      const Color(0xFFFF5722), // Deep Orange
      const Color(0xFFFFD700), // Gold
      const Color(0xFF795548), // Brown
      const Color(0xFF607D8B), // Blue Grey Dark
      const Color(0xFF3F51B5), // Indigo
      const Color(0xFF009688), // Teal
      const Color(0xFFCDDC39), // Lime
      const Color(0xFF8BC34A), // Light Green
    ];

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Выберите цвет'),
        content: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: colors.map((color) {
            final isSelected = _levels[index].color.value == color.value;
            return InkWell(
              onTap: () {
                setState(() {
                  _levels[index] = _levels[index].copyWith(
                    colorHex:
                        '#${color.value.toRadixString(16).substring(2).toUpperCase()}',
                  );
                });
                Navigator.of(context).pop();
              },
              child: Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(8),
                  border: isSelected
                      ? Border.all(color: Colors.black, width: 3)
                      : null,
                ),
                child: isSelected
                    ? const Icon(Icons.check, color: Colors.white)
                    : null,
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  void _showBadgeSelector(int index) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Container(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Выберите значок',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            // Кнопка загрузки картинки
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('Загрузить картинку'),
              onTap: () {
                Navigator.pop(context);
                _pickBadgeImage(index);
              },
            ),
            const Divider(),
            const Text('Или выберите иконку:'),
            const SizedBox(height: 12),
            // Сетка иконок
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: LevelBadge.availableIcons.map((iconName) {
                final iconData = LevelBadge(type: 'icon', value: iconName).getIcon();
                final isSelected = _levels[index].badge.type == 'icon' &&
                    _levels[index].badge.value == iconName;

                return InkWell(
                  onTap: () {
                    setState(() {
                      _levels[index] = _levels[index].copyWith(
                        badge: LevelBadge(type: 'icon', value: iconName),
                      );
                    });
                    Navigator.pop(context);
                  },
                  child: Container(
                    width: 50,
                    height: 50,
                    decoration: BoxDecoration(
                      color: isSelected
                          ? _levels[index].color
                          : Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(10),
                      border: isSelected
                          ? Border.all(color: _levels[index].color, width: 2)
                          : null,
                    ),
                    child: Icon(
                      iconData ?? Icons.help,
                      color: isSelected ? Colors.white : Colors.grey.shade700,
                    ),
                  ),
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickBadgeImage(int index) async {
    final picker = ImagePicker();
    final image = await picker.pickImage(source: ImageSource.gallery);

    if (image != null) {
      final file = File(image.path);
      final url = await LoyaltyGamificationService.uploadBadgeImage(
        file,
        _levels[index].id,
      );

      if (url != null && mounted) {
        setState(() {
          _levels[index] = _levels[index].copyWith(
            badge: LevelBadge(type: 'image', value: url),
          );
        });
      }
    }
  }

  Widget _buildWheelTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Основные настройки
          Card(
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Основные настройки',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 16),
                  // Включено/выключено
                  SwitchListTile(
                    title: const Text('Колесо удачи включено'),
                    subtitle:
                        const Text('Клиенты смогут крутить колесо за напитки'),
                    value: _wheelSettings.enabled,
                    onChanged: (value) {
                      setState(() {
                        _wheelSettings = _wheelSettings.copyWith(enabled: value);
                      });
                    },
                    activeColor: const Color(0xFF004D40),
                  ),
                  const Divider(),
                  // Напитков для прокрутки
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _freeDrinksPerSpinController,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'Напитков для прокрутки',
                            helperText: 'Сколько напитков нужно для 1 спина',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          // Секторы колеса
          const Text(
            'Секторы колеса',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _wheelSettings.sectors.length,
            itemBuilder: (context, index) {
              return _buildSectorCard(index);
            },
          ),
          const SizedBox(height: 16),
          // Кнопка добавления сектора
          Center(
            child: ElevatedButton.icon(
              onPressed: _addSector,
              icon: const Icon(Icons.add),
              label: const Text('Добавить сектор'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF004D40),
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectorCard(int index) {
    final sector = _wheelSettings.sectors[index];

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: sector.color,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Center(
                    child: Text(
                      '${index + 1}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _sectorTextControllers[index],
                    decoration: const InputDecoration(
                      labelText: 'Текст приза',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                // Цвет сектора
                InkWell(
                  onTap: () => _showSectorColorPicker(index),
                  child: Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: sector.color,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.grey.shade300),
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.delete, color: Colors.red),
                  onPressed: () => _removeSector(index),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _sectorProbControllers[index],
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Вероятность %',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    value: sector.prizeType,
                    decoration: const InputDecoration(
                      labelText: 'Тип приза',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    items: const [
                      DropdownMenuItem(
                          value: 'bonus_points', child: Text('Баллы')),
                      DropdownMenuItem(
                          value: 'discount', child: Text('Скидка %')),
                      DropdownMenuItem(
                          value: 'free_drink', child: Text('Напиток')),
                      DropdownMenuItem(value: 'merch', child: Text('Мерч')),
                    ],
                    onChanged: (value) {
                      if (value != null) {
                        setState(() {
                          final sectors = List<WheelSector>.from(_wheelSettings.sectors);
                          sectors[index] = sectors[index].copyWith(prizeType: value);
                          _wheelSettings = _wheelSettings.copyWith(sectors: sectors);
                        });
                      }
                    },
                  ),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  width: 80,
                  child: TextField(
                    controller: _sectorValueControllers[index],
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Кол-во',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _showSectorColorPicker(int index) {
    final colors = [
      const Color(0xFF4CAF50), // Green
      const Color(0xFF2196F3), // Blue
      const Color(0xFFFF9800), // Orange
      const Color(0xFF9C27B0), // Purple
      const Color(0xFFF44336), // Red
      const Color(0xFF795548), // Brown
      const Color(0xFF00BCD4), // Cyan
      const Color(0xFFE91E63), // Pink
      const Color(0xFFFFEB3B), // Yellow
      const Color(0xFF8BC34A), // Light Green
      const Color(0xFF3F51B5), // Indigo
      const Color(0xFF009688), // Teal
    ];

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Выберите цвет'),
        content: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: colors.map((color) {
            final isSelected =
                _wheelSettings.sectors[index].color.value == color.value;
            return InkWell(
              onTap: () {
                setState(() {
                  final sectors = List<WheelSector>.from(_wheelSettings.sectors);
                  sectors[index] = sectors[index].copyWith(
                    colorHex:
                        '#${color.value.toRadixString(16).substring(2).toUpperCase()}',
                  );
                  _wheelSettings = _wheelSettings.copyWith(sectors: sectors);
                });
                Navigator.of(context).pop();
              },
              child: Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(8),
                  border: isSelected
                      ? Border.all(color: Colors.black, width: 3)
                      : null,
                ),
                child: isSelected
                    ? const Icon(Icons.check, color: Colors.white)
                    : null,
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  void _addSector() {
    final newIndex = _wheelSettings.sectors.length;
    final newSector = WheelSector(
      index: newIndex,
      text: 'Новый приз',
      probability: 0.1,
      colorHex: '#4CAF50',
      prizeType: 'bonus_points',
      prizeValue: 5,
    );

    _sectorTextControllers.add(TextEditingController(text: newSector.text));
    _sectorProbControllers
        .add(TextEditingController(text: (newSector.probability * 100).toString()));
    _sectorValueControllers
        .add(TextEditingController(text: newSector.prizeValue.toString()));

    setState(() {
      final sectors = List<WheelSector>.from(_wheelSettings.sectors);
      sectors.add(newSector);
      _wheelSettings = _wheelSettings.copyWith(sectors: sectors);
    });
  }

  void _removeSector(int index) {
    if (_wheelSettings.sectors.length <= 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Минимум 2 сектора'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    _sectorTextControllers[index].dispose();
    _sectorProbControllers[index].dispose();
    _sectorValueControllers[index].dispose();

    _sectorTextControllers.removeAt(index);
    _sectorProbControllers.removeAt(index);
    _sectorValueControllers.removeAt(index);

    setState(() {
      final sectors = List<WheelSector>.from(_wheelSettings.sectors);
      sectors.removeAt(index);
      // Обновляем индексы
      for (int i = 0; i < sectors.length; i++) {
        sectors[i] = sectors[i].copyWith(index: i);
      }
      _wheelSettings = _wheelSettings.copyWith(sectors: sectors);
    });
  }
}
