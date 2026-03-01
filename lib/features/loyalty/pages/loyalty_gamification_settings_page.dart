import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/theme/app_colors.dart';
import '../models/loyalty_gamification_model.dart';
import '../services/loyalty_gamification_service.dart';
import '../../../core/constants/api_constants.dart';
import '../../../shared/widgets/app_cached_image.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

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
  WheelSettings _wheelSettings = WheelSettings(
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
  static final _primaryColor = AppColors.primaryGreen;
  static final _goldColor = Color(0xFFFFD700);

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
    if (mounted) setState(() => _isLoading = true);

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
        _levelMinDrinksControllers.add(TextEditingController(
            text: (level.minTotalPoints > 0
                ? level.minTotalPoints
                : level.minFreeDrinks * 10).toString()));
      }

      // Инициализируем колесо
      _freeDrinksPerSpinController.text =
          settings.wheel.effectivePointsPerSpin.toString();
      for (final sector in settings.wheel.sectors) {
        _sectorTextControllers.add(TextEditingController(text: sector.text));
        _sectorProbControllers.add(TextEditingController(
            text: (sector.probability * 100).toStringAsFixed(0)));
        _sectorValueControllers
            .add(TextEditingController(text: sector.prizeValue.toString()));
      }

      if (mounted) setState(() {
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

  /// Формирует полный URL для изображения значка
  String _getBadgeImageUrl(String value) {
    if (value.startsWith('http://') || value.startsWith('https://')) {
      return value;
    }
    // Относительный путь - добавляем базовый URL
    return '${ApiConstants.serverUrl}$value';
  }

  Future<void> _saveSettings() async {
    if (!_canSave()) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Сумма вероятностей не должна превышать 100%'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    if (mounted) setState(() => _isSaving = true);

    // Получаем телефон админа из SharedPreferences
    final prefs = await SharedPreferences.getInstance();
    final adminPhone = prefs.getString('user_phone') ?? '';

    // Собираем уровни
    final updatedLevels = <LoyaltyLevel>[];
    for (int i = 0; i < _levels.length; i++) {
      updatedLevels.add(_levels[i].copyWith(
        name: _levelNameControllers[i].text,
        minTotalPoints:
            int.tryParse(_levelMinDrinksControllers[i].text) ?? 0,
        minFreeDrinks: 0,
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
        pointsPerSpin:
            int.tryParse(_freeDrinksPerSpinController.text) ?? 50,
        freeDrinksPerSpin: 0,
        sectors: updatedSectors,
      ),
    );

    final success = await LoyaltyGamificationService.saveSettings(
      settings: updatedSettings,
      employeePhone: adminPhone,
    );

    if (mounted) setState(() => _isSaving = false);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(
                success ? Icons.check_circle : Icons.error,
                color: Colors.white,
              ),
              SizedBox(width: 12),
              Text(success ? 'Настройки сохранены' : 'Ошибка сохранения'),
            ],
          ),
          backgroundColor: success ? Colors.green : Colors.red,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.r)),
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
      backgroundColor: AppColors.night,
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              AppColors.emeraldDark,
              AppColors.night,
              AppColors.night,
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
                    ? Center(
                        child: CircularProgressIndicator(color: Colors.white),
                      )
                    : Container(
                        margin: EdgeInsets.only(top: 8.h),
                        decoration: BoxDecoration(
                          color: AppColors.night,
                          borderRadius: BorderRadius.vertical(
                            top: Radius.circular(24.r),
                          ),
                        ),
                        child: Column(
                          children: [
                            // Табы
                            Container(
                              margin: EdgeInsets.fromLTRB(16.w, 16.h, 16.w, 8.h),
                              decoration: BoxDecoration(
                                color: AppColors.emeraldDark,
                                borderRadius: BorderRadius.circular(12.r),
                              ),
                              child: TabBar(
                                controller: _tabController,
                                indicator: BoxDecoration(
                                  color: AppColors.emerald,
                                  borderRadius: BorderRadius.circular(12.r),
                                ),
                                labelColor: Colors.white,
                                unselectedLabelColor: Colors.white.withOpacity(0.5),
                                labelStyle: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14.sp,
                                ),
                                tabs: [
                                  Tab(
                                    child: Row(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Icon(Icons.workspace_premium, size: 20),
                                        SizedBox(width: 8),
                                        Flexible(child: Text('Уровни', overflow: TextOverflow.ellipsis)),
                                      ],
                                    ),
                                  ),
                                  Tab(
                                    child: Row(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Icon(Icons.casino, size: 20),
                                        SizedBox(width: 8),
                                        Flexible(child: Text('Колесо', overflow: TextOverflow.ellipsis)),
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
      padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 8.h),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.pop(context),
            icon: Container(
              padding: EdgeInsets.all(8.w),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.2),
                borderRadius: BorderRadius.circular(12.r),
              ),
              child: Icon(
                Icons.arrow_back_ios_new,
                color: Colors.white,
                size: 20,
              ),
            ),
          ),
          Expanded(
            child: Text(
              'Программа лояльности',
              style: TextStyle(
                color: Colors.white,
                fontSize: 20.sp,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
          ),
          _isSaving
              ? Container(
                  padding: EdgeInsets.all(16.w),
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
                  onPressed: _canSave() ? _saveSettings : null,
                  icon: Container(
                    padding: EdgeInsets.all(8.w),
                    decoration: BoxDecoration(
                      color: _canSave()
                          ? _goldColor
                          : Colors.white.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(12.r),
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
      padding: EdgeInsets.all(16.w),
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
      margin: EdgeInsets.only(bottom: 16.h),
      padding: EdgeInsets.all(16.w),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppColors.emeraldDark,
            AppColors.emerald.withOpacity(0.3),
          ],
        ),
        borderRadius: BorderRadius.circular(16.r),
        border: Border.all(color: AppColors.emerald.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: EdgeInsets.all(8.w),
                decoration: BoxDecoration(
                  color: _primaryColor.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(8.r),
                ),
                child: Icon(Icons.info_outline, color: _primaryColor, size: 20),
              ),
              SizedBox(width: 12),
              Text(
                'Настройка уровней',
                style: TextStyle(
                  fontSize: 16.sp,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ],
          ),
          SizedBox(height: 12),
          Text(
            'Клиенты получают уровни за бесплатные напитки. '
            'Значки появляются вокруг QR-кода.',
            style: TextStyle(
              fontSize: 13.sp,
              color: Colors.white.withOpacity(0.6),
              height: 1.4,
            ),
          ),
          SizedBox(height: 8),
          Container(
            padding: EdgeInsets.all(8.w),
            decoration: BoxDecoration(
              color: Colors.amber.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8.r),
            ),
            child: Row(
              children: [
                Icon(Icons.image, color: Colors.amber, size: 16),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Рекомендуемый размер значка: 100x100 px, PNG с прозрачностью',
                    style: TextStyle(
                      fontSize: 12.sp,
                      color: Colors.amber[300],
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
      margin: EdgeInsets.only(bottom: 12.h),
      decoration: BoxDecoration(
        color: AppColors.emeraldDark,
        borderRadius: BorderRadius.circular(16.r),
        border: Border.all(color: AppColors.emerald.withOpacity(0.3)),
      ),
      child: Padding(
        padding: EdgeInsets.all(16.w),
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
                    borderRadius: BorderRadius.circular(12.r),
                    boxShadow: [
                      BoxShadow(
                        color: level.color.withOpacity(0.4),
                        blurRadius: 8,
                        offset: Offset(0, 2),
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
                        : ClipRRect(
                            borderRadius: BorderRadius.circular(8.r),
                            child: AppCachedImage(
                              imageUrl: _getBadgeImageUrl(level.badge.value),
                              width: 40,
                              height: 40,
                              fit: BoxFit.cover,
                              errorWidget: (_, __, ___) => Icon(
                                Icons.image,
                                color: Colors.white,
                                size: 28,
                              ),
                            ),
                          ),
                  ),
                ),
                SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Уровень ${index + 1}',
                        style: TextStyle(
                          fontSize: 16.sp,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        'от ${_levelMinDrinksControllers[index].text} баллов',
                        style: TextStyle(
                          fontSize: 12.sp,
                          color: Colors.white.withOpacity(0.5),
                        ),
                      ),
                    ],
                  ),
                ),
                // Кнопка выбора цвета
                InkWell(
                  onTap: () => _showColorPicker(index),
                  borderRadius: BorderRadius.circular(8.r),
                  child: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: level.color,
                      borderRadius: BorderRadius.circular(8.r),
                      border: Border.all(color: AppColors.emerald.withOpacity(0.5)),
                    ),
                    child: Icon(Icons.palette, color: Colors.white, size: 18),
                  ),
                ),
              ],
            ),
            SizedBox(height: 16),
            // Название уровня
            TextField(
              controller: _levelNameControllers[index],
              style: TextStyle(color: Colors.white),
              decoration: InputDecoration(
                labelText: 'Название уровня',
                labelStyle: TextStyle(color: Colors.white.withOpacity(0.5)),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12.r),
                  borderSide: BorderSide(color: AppColors.emerald.withOpacity(0.5)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12.r),
                  borderSide: BorderSide(color: AppColors.emerald.withOpacity(0.5)),
                ),
                isDense: true,
                prefixIcon: Icon(Icons.label_outline, color: Colors.white.withOpacity(0.5)),
              ),
            ),
            SizedBox(height: 12),
            // Порог напитков и кнопка значка
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _levelMinDrinksControllers[index],
                    keyboardType: TextInputType.number,
                    style: TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      labelText: 'Мин. баллов',
                      labelStyle: TextStyle(color: Colors.white.withOpacity(0.5)),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12.r),
                        borderSide: BorderSide(color: AppColors.emerald.withOpacity(0.5)),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12.r),
                        borderSide: BorderSide(color: AppColors.emerald.withOpacity(0.5)),
                      ),
                      isDense: true,
                      prefixIcon: Icon(Icons.star_outline, color: Colors.white.withOpacity(0.5)),
                    ),
                  ),
                ),
                SizedBox(width: 12),
                // Кнопка выбора значка
                ElevatedButton.icon(
                  onPressed: () => _showBadgeSelector(index),
                  icon: Icon(Icons.edit, size: 18),
                  label: Text('Значок'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _primaryColor,
                    foregroundColor: Colors.white,
                    padding: EdgeInsets.symmetric(
                        horizontal: 16.w, vertical: 14.h),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12.r),
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
      Color(0xFF78909C), AppColors.success,
      Color(0xFF2196F3), Color(0xFF9C27B0),
      Color(0xFFFF9800), Color(0xFFF44336),
      Color(0xFF00BCD4), Color(0xFFE91E63),
      Color(0xFFFF5722), Color(0xFFFFD700),
      Color(0xFF795548), Color(0xFF607D8B),
      Color(0xFF3F51B5), Color(0xFF009688),
      Color(0xFFCDDC39), Color(0xFF8BC34A),
    ];

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Выберите цвет'),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20.r)),
        content: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: colors.map((color) {
            final isSelected = _levels[index].color.value == color.value;
            return InkWell(
              onTap: () {
                if (mounted) setState(() {
                  _levels[index] = _levels[index].copyWith(
                    colorHex:
                        '#${color.value.toRadixString(16).substring(2).toUpperCase()}',
                  );
                });
                Navigator.of(context).pop();
              },
              borderRadius: BorderRadius.circular(12.r),
              child: Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(12.r),
                  border: isSelected
                      ? Border.all(color: Colors.black, width: 3)
                      : null,
                  boxShadow: [
                    BoxShadow(
                      color: color.withOpacity(0.4),
                      blurRadius: 4,
                      offset: Offset(0, 2),
                    ),
                  ],
                ),
                child: isSelected
                    ? Icon(Icons.check, color: Colors.white)
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
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24.r)),
      ),
      builder: (context) => Container(
        padding: EdgeInsets.all(20.w),
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
                  borderRadius: BorderRadius.circular(2.r),
                ),
              ),
            ),
            SizedBox(height: 20),
            Text(
              'Выберите значок',
              style: TextStyle(fontSize: 20.sp, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 20),
            // Кнопка загрузки картинки
            Container(
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey.shade300),
                borderRadius: BorderRadius.circular(12.r),
              ),
              child: ListTile(
                leading: Container(
                  padding: EdgeInsets.all(8.w),
                  decoration: BoxDecoration(
                    color: _primaryColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8.r),
                  ),
                  child: Icon(Icons.photo_library, color: _primaryColor),
                ),
                title: Text('Загрузить картинку'),
                subtitle: Text('PNG 100x100 px, прозрачный фон'),
                trailing: Icon(Icons.chevron_right),
                onTap: () {
                  Navigator.pop(context);
                  _pickBadgeImage(index);
                },
              ),
            ),
            SizedBox(height: 16),
            Text(
              'Или выберите иконку:',
              style: TextStyle(fontWeight: FontWeight.w500),
            ),
            SizedBox(height: 12),
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
                    if (mounted) setState(() {
                      _levels[index] = _levels[index].copyWith(
                        badge: LevelBadge(type: 'icon', value: iconName),
                      );
                    });
                    Navigator.pop(context);
                  },
                  borderRadius: BorderRadius.circular(12.r),
                  child: Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      color: isSelected
                          ? _levels[index].color
                          : Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(12.r),
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
            SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Future<void> _pickBadgeImage(int index) async {
    final picker = ImagePicker();
    final image = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 512,
      maxHeight: 512,
      imageQuality: 95,
    );

    if (image == null) return;
    if (!mounted) return;

    // Открываем редактор кадрирования (как в Telegram)
    final croppedFile = await ImageCropper().cropImage(
      sourcePath: image.path,
      aspectRatio: CropAspectRatio(ratioX: 1, ratioY: 1),
      compressQuality: 90,
      maxWidth: 200,
      maxHeight: 200,
      cropStyle: CropStyle.circle,
      uiSettings: [
        AndroidUiSettings(
          toolbarTitle: 'Обрезать значок',
          toolbarColor: Theme.of(context).primaryColor,
          toolbarWidgetColor: Colors.white,
          initAspectRatio: CropAspectRatioPreset.square,
          lockAspectRatio: true,
          hideBottomControls: false,
        ),
        IOSUiSettings(
          title: 'Обрезать значок',
          aspectRatioLockEnabled: true,
          resetAspectRatioEnabled: false,
        ),
      ],
    );

    if (croppedFile == null) return;

    // Показываем индикатор загрузки
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
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

    final file = File(croppedFile.path);
    final url = await LoyaltyGamificationService.uploadBadgeImage(
      file,
      _levels[index].id,
    );

    if (mounted) {
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
    }

    if (url != null && mounted) {
      if (mounted) setState(() {
        _levels[index] = _levels[index].copyWith(
          badge: LevelBadge(type: 'image', value: url),
        );
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
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
        SnackBar(
          content: Text('Ошибка загрузки значка'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Widget _buildWheelTab() {
    final totalProbability = _calculateTotalProbability();
    final isValid = totalProbability <= 100;

    return SingleChildScrollView(
      padding: EdgeInsets.all(16.w),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Индикатор общего процента
          _buildProbabilityIndicator(totalProbability, isValid),
          SizedBox(height: 16),
          // Основные настройки
          _buildWheelMainSettings(),
          SizedBox(height: 16),
          // Заголовок секторов
          Row(
            children: [
              Container(
                padding: EdgeInsets.all(8.w),
                decoration: BoxDecoration(
                  color: _goldColor.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(8.r),
                ),
                child: Icon(Icons.pie_chart, color: Color(0xFFB8860B), size: 20),
              ),
              SizedBox(width: 12),
              Text(
                'Секторы колеса',
                style: TextStyle(fontSize: 18.sp, fontWeight: FontWeight.bold, color: Colors.white),
              ),
              Spacer(),
              Text(
                '${_wheelSettings.sectors.length} шт',
                style: TextStyle(
                  fontSize: 14.sp,
                  color: Colors.white.withOpacity(0.5),
                ),
              ),
            ],
          ),
          SizedBox(height: 12),
          // Секторы
          ListView.builder(
            shrinkWrap: true,
            physics: NeverScrollableScrollPhysics(),
            itemCount: _wheelSettings.sectors.length,
            itemBuilder: (context, index) {
              return _buildSectorCard(index);
            },
          ),
          SizedBox(height: 16),
          // Кнопка добавления сектора
          Center(
            child: ElevatedButton.icon(
              onPressed: _addSector,
              icon: Icon(Icons.add),
              label: Text('Добавить сектор'),
              style: ElevatedButton.styleFrom(
                backgroundColor: _primaryColor,
                foregroundColor: Colors.white,
                padding:
                    EdgeInsets.symmetric(horizontal: 24.w, vertical: 14.h),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12.r),
                ),
              ),
            ),
          ),
          SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildProbabilityIndicator(double total, bool isValid) {
    return Container(
      padding: EdgeInsets.all(16.w),
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
        borderRadius: BorderRadius.circular(16.r),
        border: Border.all(
          color: isValid ? Colors.green.withOpacity(0.3) : Colors.red.withOpacity(0.3),
        ),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                padding: EdgeInsets.all(8.w),
                decoration: BoxDecoration(
                  color: isValid
                      ? Colors.green.withOpacity(0.15)
                      : Colors.red.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(8.r),
                ),
                child: Icon(
                  isValid ? Icons.check_circle : Icons.warning,
                  color: isValid ? Colors.green : Colors.red,
                  size: 20,
                ),
              ),
              SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Общая вероятность',
                      style: TextStyle(
                        fontSize: 14.sp,
                        fontWeight: FontWeight.w500,
                        color: Colors.white,
                      ),
                    ),
                    Text(
                      isValid
                          ? 'Сумма вероятностей должна быть ≤ 100%'
                          : 'Превышен лимит! Уменьшите вероятности.',
                      style: TextStyle(
                        fontSize: 12.sp,
                        color: isValid ? Colors.white.withOpacity(0.5) : Colors.red,
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                '${total.toStringAsFixed(0)}%',
                style: TextStyle(
                  fontSize: 24.sp,
                  fontWeight: FontWeight.bold,
                  color: isValid ? Colors.green : Colors.red,
                ),
              ),
            ],
          ),
          SizedBox(height: 12),
          // Прогресс бар
          ClipRRect(
            borderRadius: BorderRadius.circular(4.r),
            child: LinearProgressIndicator(
              value: (total / 100).clamp(0.0, 1.0),
              backgroundColor: AppColors.emerald.withOpacity(0.3),
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
        color: AppColors.emeraldDark,
        borderRadius: BorderRadius.circular(16.r),
        border: Border.all(color: AppColors.emerald.withOpacity(0.3)),
      ),
      child: Padding(
        padding: EdgeInsets.all(16.w),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: EdgeInsets.all(8.w),
                  decoration: BoxDecoration(
                    color: _primaryColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8.r),
                  ),
                  child: Icon(Icons.settings, color: _primaryColor, size: 20),
                ),
                SizedBox(width: 12),
                Text(
                  'Основные настройки',
                  style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.bold, color: Colors.white),
                ),
              ],
            ),
            SizedBox(height: 16),
            // Включено/выключено
            Container(
              padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 4.h),
              decoration: BoxDecoration(
                color: _wheelSettings.enabled
                    ? Colors.green.withOpacity(0.1)
                    : Colors.grey.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12.r),
              ),
              child: SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text('Колесо удачи', style: TextStyle(color: Colors.white)),
                subtitle: Text(
                  _wheelSettings.enabled
                      ? 'Клиенты могут крутить колесо'
                      : 'Колесо отключено',
                  style: TextStyle(color: Colors.white.withOpacity(0.5)),
                ),
                value: _wheelSettings.enabled,
                onChanged: (value) {
                  if (mounted) setState(() {
                    _wheelSettings = _wheelSettings.copyWith(enabled: value);
                  });
                },
                activeColor: Colors.green,
              ),
            ),
            SizedBox(height: 16),
            // Баллов для прокрутки
            TextField(
              controller: _freeDrinksPerSpinController,
              keyboardType: TextInputType.number,
              style: TextStyle(color: Colors.white),
              decoration: InputDecoration(
                labelText: 'Баллов для прокрутки',
                labelStyle: TextStyle(color: Colors.white.withOpacity(0.5)),
                helperText: 'Сколько баллов нужно накопить для 1 прокрутки колеса',
                helperStyle: TextStyle(color: Colors.white.withOpacity(0.4)),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12.r),
                  borderSide: BorderSide(color: AppColors.emerald.withOpacity(0.5)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12.r),
                  borderSide: BorderSide(color: AppColors.emerald.withOpacity(0.5)),
                ),
                prefixIcon: Icon(Icons.stars, color: Colors.white.withOpacity(0.5)),
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
      margin: EdgeInsets.only(bottom: 12.h),
      decoration: BoxDecoration(
        color: AppColors.emeraldDark,
        borderRadius: BorderRadius.circular(16.r),
        border: Border.all(color: AppColors.emerald.withOpacity(0.3)),
      ),
      child: Padding(
        padding: EdgeInsets.all(12.w),
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
                    borderRadius: BorderRadius.circular(10.r),
                    boxShadow: [
                      BoxShadow(
                        color: sector.color.withOpacity(0.4),
                        blurRadius: 4,
                        offset: Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Center(
                    child: Text(
                      '${index + 1}',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 16.sp,
                      ),
                    ),
                  ),
                ),
                SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _sectorTextControllers[index],
                    style: TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      labelText: 'Текст приза',
                      labelStyle: TextStyle(color: Colors.white.withOpacity(0.5)),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12.r),
                        borderSide: BorderSide(color: AppColors.emerald.withOpacity(0.5)),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12.r),
                        borderSide: BorderSide(color: AppColors.emerald.withOpacity(0.5)),
                      ),
                      isDense: true,
                    ),
                  ),
                ),
                SizedBox(width: 8),
                // Цвет сектора
                InkWell(
                  onTap: () => _showSectorColorPicker(index),
                  borderRadius: BorderRadius.circular(8.r),
                  child: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: sector.color,
                      borderRadius: BorderRadius.circular(8.r),
                      border: Border.all(color: AppColors.emerald.withOpacity(0.5)),
                    ),
                    child: Icon(Icons.palette, color: Colors.white, size: 18),
                  ),
                ),
                IconButton(
                  icon: Icon(Icons.delete_outline, color: Colors.red),
                  onPressed: () => _removeSector(index),
                ),
              ],
            ),
            SizedBox(height: 12),
            Row(
              children: [
                // Вероятность
                Expanded(
                  flex: 2,
                  child: TextField(
                    controller: _sectorProbControllers[index],
                    keyboardType: TextInputType.number,
                    style: TextStyle(color: Colors.white),
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      labelText: 'Вероятность %',
                      labelStyle: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 12.sp),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12.r),
                        borderSide: BorderSide(color: AppColors.emerald.withOpacity(0.5)),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12.r),
                        borderSide: BorderSide(color: AppColors.emerald.withOpacity(0.5)),
                      ),
                      isDense: true,
                      prefixIcon: Icon(Icons.percent, size: 20, color: Colors.white.withOpacity(0.5)),
                    ),
                  ),
                ),
                SizedBox(width: 8),
                // Тип приза
                Expanded(
                  flex: 2,
                  child: DropdownButtonFormField<String>(
                    value: sector.prizeType,
                    dropdownColor: AppColors.emeraldDark,
                    style: TextStyle(color: Colors.white, fontSize: 14.sp),
                    decoration: InputDecoration(
                      labelText: 'Тип приза',
                      labelStyle: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 12.sp),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12.r),
                        borderSide: BorderSide(color: AppColors.emerald.withOpacity(0.5)),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12.r),
                        borderSide: BorderSide(color: AppColors.emerald.withOpacity(0.5)),
                      ),
                      isDense: true,
                    ),
                    items: [
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
                        if (mounted) setState(() {
                          final sectors = List<WheelSector>.from(_wheelSettings.sectors);
                          sectors[index] = sectors[index].copyWith(prizeType: value);
                          _wheelSettings = _wheelSettings.copyWith(sectors: sectors);
                        });
                      }
                    },
                  ),
                ),
                SizedBox(width: 8),
                // Значение
                Expanded(
                  flex: 1,
                  child: TextField(
                    controller: _sectorValueControllers[index],
                    keyboardType: TextInputType.number,
                    style: TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      labelText: 'Кол-во',
                      labelStyle: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 12.sp),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12.r),
                        borderSide: BorderSide(color: AppColors.emerald.withOpacity(0.5)),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12.r),
                        borderSide: BorderSide(color: AppColors.emerald.withOpacity(0.5)),
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
      AppColors.success, Color(0xFF2196F3),
      Color(0xFFFF9800), Color(0xFF9C27B0),
      Color(0xFFF44336), Color(0xFF795548),
      Color(0xFF00BCD4), Color(0xFFE91E63),
      Color(0xFFFFEB3B), Color(0xFF8BC34A),
      Color(0xFF3F51B5), Color(0xFF009688),
    ];

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Выберите цвет'),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20.r)),
        content: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: colors.map((color) {
            final isSelected =
                _wheelSettings.sectors[index].color.value == color.value;
            return InkWell(
              onTap: () {
                if (mounted) setState(() {
                  final sectors = List<WheelSector>.from(_wheelSettings.sectors);
                  sectors[index] = sectors[index].copyWith(
                    colorHex:
                        '#${color.value.toRadixString(16).substring(2).toUpperCase()}',
                  );
                  _wheelSettings = _wheelSettings.copyWith(sectors: sectors);
                });
                Navigator.of(context).pop();
              },
              borderRadius: BorderRadius.circular(12.r),
              child: Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(12.r),
                  border: isSelected
                      ? Border.all(color: Colors.black, width: 3)
                      : null,
                  boxShadow: [
                    BoxShadow(
                      color: color.withOpacity(0.4),
                      blurRadius: 4,
                      offset: Offset(0, 2),
                    ),
                  ],
                ),
                child: isSelected
                    ? Icon(Icons.check, color: Colors.white)
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

    if (mounted) setState(() {
      final sectors = List<WheelSector>.from(_wheelSettings.sectors);
      sectors.add(newSector);
      _wheelSettings = _wheelSettings.copyWith(sectors: sectors);
    });
  }

  void _removeSector(int index) {
    if (_wheelSettings.sectors.length <= 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(Icons.warning, color: Colors.white),
              SizedBox(width: 12),
              Text('Минимум 2 сектора'),
            ],
          ),
          backgroundColor: Colors.orange,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.r)),
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

    if (mounted) setState(() {
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
