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

  // Премиум цвета
  static const _primaryColor = Color(0xFF004D40);
  static const _accentColor = Color(0xFF00897B);
  static const _goldColor = Color(0xFFFFD700);

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
            text: (sector.probability * 100).toStringAsFixed(0)));
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

  double _calculateTotalProbability() {
    double total = 0;
    for (final controller in _sectorProbControllers) {
      final value = double.tryParse(controller.text) ?? 0;
      total += value;
    }
    return total;
  }

  bool _canSave() {
    final total = _calculateTotalProbability();
    return total <= 100;
  }

  Future<void> _saveSettings() async {
    if (!_canSave()) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Сумма вероятностей не должна превышать 100%'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

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

    // Собираем секторы колеса с правильными индексами
    final updatedSectors = <WheelSector>[];
    for (int i = 0; i < _sectorTextControllers.length; i++) {
      final prob = double.tryParse(_sectorProbControllers[i].text) ?? 10.0;
      // Создаем новый сектор с правильным индексом
      updatedSectors.add(WheelSector(
        index: i,
        text: _sectorTextControllers[i].text,
        probability: prob / 100,
        colorHex: _wheelSettings.sectors.length > i
            ? _wheelSettings.sectors[i].colorHex
            : '#4CAF50',
        prizeType: _wheelSettings.sectors.length > i
            ? _wheelSettings.sectors[i].prizeType
            : 'bonus_points',
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

    final success = await LoyaltyGamificationService.saveSettings(
      settings: updatedSettings,
      employeePhone: '',
    );

    setState(() => _isSaving = false);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(
                success ? Icons.check_circle : Icons.error,
                color: Colors.white,
              ),
              const SizedBox(width: 12),
              Text(success ? 'Настройки сохранены' : 'Ошибка сохранения'),
            ],
          ),
          backgroundColor: success ? Colors.green : Colors.red,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFF004D40),
              Color(0xFF00695C),
              Color(0xFF00897B),
            ],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              // Кастомный AppBar
              _buildAppBar(),
              // Контент
              Expanded(
                child: _isLoading
                    ? const Center(
                        child: CircularProgressIndicator(color: Colors.white),
                      )
                    : Container(
                        margin: const EdgeInsets.only(top: 8),
                        decoration: const BoxDecoration(
                          color: Color(0xFFF5F7FA),
                          borderRadius: BorderRadius.vertical(
                            top: Radius.circular(24),
                          ),
                        ),
                        child: Column(
                          children: [
                            // Табы
                            Container(
                              margin: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                              decoration: BoxDecoration(
                                color: Colors.grey.shade200,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: TabBar(
                                controller: _tabController,
                                indicator: BoxDecoration(
                                  color: _primaryColor,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                labelColor: Colors.white,
                                unselectedLabelColor: Colors.grey.shade700,
                                labelStyle: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                ),
                                tabs: const [
                                  Tab(
                                    child: Row(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Icon(Icons.workspace_premium, size: 20),
                                        SizedBox(width: 8),
                                        Text('Уровни'),
                                      ],
                                    ),
                                  ),
                                  Tab(
                                    child: Row(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Icon(Icons.casino, size: 20),
                                        SizedBox(width: 8),
                                        Text('Колесо'),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            // Контент табов
                            Expanded(
                              child: TabBarView(
                                controller: _tabController,
                                children: [
                                  _buildLevelsTab(),
                                  _buildWheelTab(),
                                ],
                              ),
                            ),
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

  Widget _buildAppBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.pop(context),
            icon: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.2),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(
                Icons.arrow_back_ios_new,
                color: Colors.white,
                size: 20,
              ),
            ),
          ),
          const Expanded(
            child: Text(
              'Программа лояльности',
              style: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
          ),
          _isSaving
              ? Container(
                  padding: const EdgeInsets.all(16),
                  child: const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 2,
                    ),
                  ),
                )
              : IconButton(
                  onPressed: _canSave() ? _saveSettings : null,
                  icon: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: _canSave()
                          ? _goldColor
                          : Colors.white.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      Icons.save,
                      color: _canSave() ? Colors.black : Colors.white54,
                      size: 20,
                    ),
                  ),
                ),
        ],
      ),
    );
  }

  Widget _buildLevelsTab() {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _levels.length + 1, // +1 для информационной карточки
      itemBuilder: (context, index) {
        if (index == 0) {
          return _buildLevelsInfoCard();
        }
        return _buildLevelCard(index - 1);
      },
    );
  }

  Widget _buildLevelsInfoCard() {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            _primaryColor.withOpacity(0.1),
            _accentColor.withOpacity(0.05),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _primaryColor.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: _primaryColor.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(Icons.info_outline, color: _primaryColor, size: 20),
              ),
              const SizedBox(width: 12),
              const Text(
                'Настройка уровней',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'Клиенты получают уровни за бесплатные напитки. '
            'Значки появляются вокруг QR-кода.',
            style: TextStyle(
              fontSize: 13,
              color: Colors.grey.shade700,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.amber.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                const Icon(Icons.image, color: Colors.amber, size: 16),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Рекомендуемый размер значка: 100x100 px, PNG с прозрачностью',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.amber.shade800,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLevelCard(int index) {
    final level = _levels[index];

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
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
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Заголовок с номером и значком
            Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: level.color,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: level.color.withOpacity(0.4),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Center(
                    child: level.badge.type == 'icon'
                        ? Icon(
                            level.badge.getIcon() ?? Icons.emoji_events,
                            color: Colors.white,
                            size: 28,
                          )
                        : const Icon(Icons.image, color: Colors.white, size: 28),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Уровень ${index + 1}',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        'от ${_levelMinDrinksControllers[index].text} напитков',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                ),
                // Кнопка выбора цвета
                InkWell(
                  onTap: () => _showColorPicker(index),
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: level.color,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.grey.shade300),
                    ),
                    child: const Icon(Icons.palette, color: Colors.white, size: 18),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            // Название уровня
            TextField(
              controller: _levelNameControllers[index],
              decoration: InputDecoration(
                labelText: 'Название уровня',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                isDense: true,
                prefixIcon: const Icon(Icons.label_outline),
              ),
            ),
            const SizedBox(height: 12),
            // Порог напитков и кнопка значка
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _levelMinDrinksControllers[index],
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: 'Мин. напитков',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      isDense: true,
                      prefixIcon: const Icon(Icons.local_cafe_outlined),
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
                    backgroundColor: _primaryColor,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
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

  void _showColorPicker(int index) {
    final colors = [
      const Color(0xFF78909C), const Color(0xFF4CAF50),
      const Color(0xFF2196F3), const Color(0xFF9C27B0),
      const Color(0xFFFF9800), const Color(0xFFF44336),
      const Color(0xFF00BCD4), const Color(0xFFE91E63),
      const Color(0xFFFF5722), const Color(0xFFFFD700),
      const Color(0xFF795548), const Color(0xFF607D8B),
      const Color(0xFF3F51B5), const Color(0xFF009688),
      const Color(0xFFCDDC39), const Color(0xFF8BC34A),
    ];

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Выберите цвет'),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
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
              borderRadius: BorderRadius.circular(12),
              child: Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(12),
                  border: isSelected
                      ? Border.all(color: Colors.black, width: 3)
                      : null,
                  boxShadow: [
                    BoxShadow(
                      color: color.withOpacity(0.4),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ],
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
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => Container(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'Выберите значок',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 20),
            // Кнопка загрузки картинки
            Container(
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey.shade300),
                borderRadius: BorderRadius.circular(12),
              ),
              child: ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: _primaryColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(Icons.photo_library, color: _primaryColor),
                ),
                title: const Text('Загрузить картинку'),
                subtitle: const Text('PNG 100x100 px, прозрачный фон'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  Navigator.pop(context);
                  _pickBadgeImage(index);
                },
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Или выберите иконку:',
              style: TextStyle(fontWeight: FontWeight.w500),
            ),
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
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      color: isSelected
                          ? _levels[index].color
                          : Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(12),
                      border: isSelected
                          ? Border.all(color: _levels[index].color, width: 2)
                          : null,
                    ),
                    child: Icon(
                      iconData ?? Icons.help,
                      color: isSelected ? Colors.white : Colors.grey.shade700,
                      size: 28,
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Future<void> _pickBadgeImage(int index) async {
    final picker = ImagePicker();
    final image = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 200,
      maxHeight: 200,
      imageQuality: 90,
    );

    if (image != null) {
      // Показываем индикатор загрузки
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Row(
              children: [
                SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    color: Colors.white,
                    strokeWidth: 2,
                  ),
                ),
                SizedBox(width: 12),
                Text('Загрузка значка...'),
              ],
            ),
            duration: Duration(seconds: 10),
          ),
        );
      }

      final file = File(image.path);
      final url = await LoyaltyGamificationService.uploadBadgeImage(
        file,
        _levels[index].id,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
      }

      if (url != null && mounted) {
        setState(() {
          _levels[index] = _levels[index].copyWith(
            badge: LevelBadge(type: 'image', value: url),
          );
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Row(
              children: [
                Icon(Icons.check_circle, color: Colors.white),
                SizedBox(width: 12),
                Text('Значок загружен'),
              ],
            ),
            backgroundColor: Colors.green,
          ),
        );
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Ошибка загрузки значка'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Widget _buildWheelTab() {
    final totalProbability = _calculateTotalProbability();
    final isValid = totalProbability <= 100;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Индикатор общего процента
          _buildProbabilityIndicator(totalProbability, isValid),
          const SizedBox(height: 16),
          // Основные настройки
          _buildWheelMainSettings(),
          const SizedBox(height: 16),
          // Заголовок секторов
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: _goldColor.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.pie_chart, color: Color(0xFFB8860B), size: 20),
              ),
              const SizedBox(width: 12),
              const Text(
                'Секторы колеса',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const Spacer(),
              Text(
                '${_wheelSettings.sectors.length} шт',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey.shade600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Секторы
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
                backgroundColor: _primaryColor,
                foregroundColor: Colors.white,
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildProbabilityIndicator(double total, bool isValid) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isValid
              ? [
                  Colors.green.withOpacity(0.1),
                  Colors.green.withOpacity(0.05),
                ]
              : [
                  Colors.red.withOpacity(0.1),
                  Colors.red.withOpacity(0.05),
                ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isValid ? Colors.green.withOpacity(0.3) : Colors.red.withOpacity(0.3),
        ),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: isValid
                      ? Colors.green.withOpacity(0.15)
                      : Colors.red.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  isValid ? Icons.check_circle : Icons.warning,
                  color: isValid ? Colors.green : Colors.red,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Общая вероятность',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    Text(
                      isValid
                          ? 'Сумма вероятностей должна быть ≤ 100%'
                          : 'Превышен лимит! Уменьшите вероятности.',
                      style: TextStyle(
                        fontSize: 12,
                        color: isValid ? Colors.grey.shade600 : Colors.red,
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                '${total.toStringAsFixed(0)}%',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: isValid ? Colors.green : Colors.red,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Прогресс бар
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: (total / 100).clamp(0.0, 1.0),
              backgroundColor: Colors.grey.shade200,
              valueColor: AlwaysStoppedAnimation<Color>(
                isValid ? Colors.green : Colors.red,
              ),
              minHeight: 8,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWheelMainSettings() {
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
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: _primaryColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(Icons.settings, color: _primaryColor, size: 20),
                ),
                const SizedBox(width: 12),
                const Text(
                  'Основные настройки',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 16),
            // Включено/выключено
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: _wheelSettings.enabled
                    ? Colors.green.withOpacity(0.1)
                    : Colors.grey.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Колесо удачи'),
                subtitle: Text(
                  _wheelSettings.enabled
                      ? 'Клиенты могут крутить колесо'
                      : 'Колесо отключено',
                ),
                value: _wheelSettings.enabled,
                onChanged: (value) {
                  setState(() {
                    _wheelSettings = _wheelSettings.copyWith(enabled: value);
                  });
                },
                activeColor: Colors.green,
              ),
            ),
            const SizedBox(height: 16),
            // Напитков для прокрутки
            TextField(
              controller: _freeDrinksPerSpinController,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: 'Напитков для прокрутки',
                helperText: 'Сколько бесплатных напитков нужно для 1 спина',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                prefixIcon: const Icon(Icons.local_cafe),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectorCard(int index) {
    final sector = _wheelSettings.sectors[index];

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
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
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                // Номер сектора
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: sector.color,
                    borderRadius: BorderRadius.circular(10),
                    boxShadow: [
                      BoxShadow(
                        color: sector.color.withOpacity(0.4),
                        blurRadius: 4,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Center(
                    child: Text(
                      '${index + 1}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _sectorTextControllers[index],
                    decoration: InputDecoration(
                      labelText: 'Текст приза',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                // Цвет сектора
                InkWell(
                  onTap: () => _showSectorColorPicker(index),
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: sector.color,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.grey.shade300),
                    ),
                    child: const Icon(Icons.palette, color: Colors.white, size: 18),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline, color: Colors.red),
                  onPressed: () => _removeSector(index),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                // Вероятность
                Expanded(
                  flex: 2,
                  child: TextField(
                    controller: _sectorProbControllers[index],
                    keyboardType: TextInputType.number,
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      labelText: 'Вероятность %',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      isDense: true,
                      prefixIcon: const Icon(Icons.percent, size: 20),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                // Тип приза
                Expanded(
                  flex: 2,
                  child: DropdownButtonFormField<String>(
                    value: sector.prizeType,
                    decoration: InputDecoration(
                      labelText: 'Тип приза',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      isDense: true,
                    ),
                    items: const [
                      DropdownMenuItem(
                          value: 'bonus_points', child: Text('Баллы')),
                      DropdownMenuItem(
                          value: 'discount', child: Text('Скидка')),
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
                const SizedBox(width: 8),
                // Значение
                Expanded(
                  flex: 1,
                  child: TextField(
                    controller: _sectorValueControllers[index],
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: 'Кол-во',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
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
      const Color(0xFF4CAF50), const Color(0xFF2196F3),
      const Color(0xFFFF9800), const Color(0xFF9C27B0),
      const Color(0xFFF44336), const Color(0xFF795548),
      const Color(0xFF00BCD4), const Color(0xFFE91E63),
      const Color(0xFFFFEB3B), const Color(0xFF8BC34A),
      const Color(0xFF3F51B5), const Color(0xFF009688),
    ];

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Выберите цвет'),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
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
              borderRadius: BorderRadius.circular(12),
              child: Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(12),
                  border: isSelected
                      ? Border.all(color: Colors.black, width: 3)
                      : null,
                  boxShadow: [
                    BoxShadow(
                      color: color.withOpacity(0.4),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ],
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
    _sectorProbControllers.add(TextEditingController(text: '10'));
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
        SnackBar(
          content: const Row(
            children: [
              Icon(Icons.warning, color: Colors.white),
              SizedBox(width: 12),
              Text('Минимум 2 сектора'),
            ],
          ),
          backgroundColor: Colors.orange,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
