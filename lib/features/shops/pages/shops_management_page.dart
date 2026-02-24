import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/utils/logger.dart';
import '../../../core/widgets/shop_icon.dart';
import '../models/shop_model.dart';
import '../models/shop_settings_model.dart';
import '../services/shop_service.dart';
import '../../attendance/services/attendance_service.dart';
import '../../../core/utils/cache_manager.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../../core/theme/app_colors.dart';

/// Страница управления магазинами для РКО с улучшенным дизайном
class ShopsManagementPage extends StatefulWidget {
  const ShopsManagementPage({super.key});

  @override
  State<ShopsManagementPage> createState() => _ShopsManagementPageState();
}

class _ShopsManagementPageState extends State<ShopsManagementPage> with SingleTickerProviderStateMixin {
  List<Shop> _shops = [];
  Map<String, ShopSettings?> _settings = {};
  bool _isLoading = true;
  String _searchQuery = '';
  late AnimationController _animationController;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: 800),
    );
    _loadShops();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  Future<void> _loadShops() async {
    if (mounted) setState(() {
      _isLoading = true;
    });
    _animationController.reset();

    try {
      // Используем фильтрацию по роли пользователя
      final shops = await ShopService.getShopsForCurrentUser();

      // Фильтруем магазины с пустым ID (битые записи)
      final validShops = shops.where((shop) => shop.id.isNotEmpty).toList();

      Logger.debug('📋 Загружено магазинов: ${validShops.length}');
      for (var shop in validShops) {
        Logger.debug('   - ${shop.name} (ID: ${shop.id})');
      }

      // Загружаем настройки для всех магазинов ПАРАЛЛЕЛЬНО
      final entries = await Future.wait(
        validShops.map((shop) async {
          final settingsData = await _loadShopSettings(shop.address);
          return MapEntry(shop.address, settingsData);
        }),
      );
      final Map<String, ShopSettings?> settings = Map.fromEntries(entries);

      if (!mounted) return;
      setState(() {
        _shops = validShops;
        _settings = settings;
        _isLoading = false;
      });
      _animationController.forward();
    } catch (e) {
      Logger.error('Ошибка загрузки магазинов', e);
      if (!mounted) return;
      setState(() {
        _isLoading = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Icon(Icons.error_rounded, color: Colors.white),
                SizedBox(width: 12),
                Expanded(child: Text('Ошибка загрузки магазинов: $e')),
              ],
            ),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.r)),
            margin: EdgeInsets.all(16.w),
          ),
        );
      }
    }
  }

  Future<ShopSettings?> _loadShopSettings(String shopAddress) async {
    try {
      return await ShopService.getShopSettings(shopAddress);
    } catch (e) {
      Logger.error('Ошибка загрузки настроек магазина', e);
      return null;
    }
  }

  /// Диалог добавления нового магазина (полная форма как при редактировании)
  Future<void> _showAddShopDialog() async {
    final nameController = TextEditingController();
    final addressController = TextEditingController();
    final innController = TextEditingController();
    final directorController = TextEditingController();

    // Инициализация времени для смен
    TimeOfDay? morningStart;
    TimeOfDay? morningEnd;
    TimeOfDay? dayStart;
    TimeOfDay? dayEnd;
    TimeOfDay? nightStart;
    TimeOfDay? nightEnd;

    // Контроллеры для аббревиатур
    final morningAbbreviationController = TextEditingController();
    final dayAbbreviationController = TextEditingController();
    final nightAbbreviationController = TextEditingController();

    // Геолокация
    double? latitude;
    double? longitude;
    bool isGettingLocation = false;

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          backgroundColor: AppColors.emeraldDark,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20.r)),
          title: Row(
            children: [
              Container(
                padding: EdgeInsets.all(10.w),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [AppColors.emerald, AppColors.emeraldLight.withOpacity(0.7)],
                  ),
                  borderRadius: BorderRadius.circular(12.r),
                  border: Border.all(color: AppColors.gold.withOpacity(0.4)),
                ),
                child: Icon(Icons.add_business_rounded, color: AppColors.gold),
              ),
              SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Новый магазин',
                  style: TextStyle(fontSize: 18.sp, fontWeight: FontWeight.bold, color: Colors.white),
                ),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Основные данные магазина
                _buildSectionHeader('Основные данные', Icons.business_rounded),
                SizedBox(height: 12),
                _buildStyledTextField(
                  controller: nameController,
                  label: 'Название магазина *',
                  hint: 'Например: Арабика Лермонтов',
                  icon: Icons.store_rounded,
                ),
                SizedBox(height: 16),
                _buildStyledTextField(
                  controller: addressController,
                  label: 'Адрес магазина *',
                  hint: 'Лермонтов, ул. Ленина 10',
                  icon: Icons.location_on_rounded,
                ),
                SizedBox(height: 16),
                _buildStyledTextField(
                  controller: innController,
                  label: 'ИНН',
                  icon: Icons.numbers_rounded,
                  keyboardType: TextInputType.number,
                ),
                SizedBox(height: 16),
                _buildStyledTextField(
                  controller: directorController,
                  label: 'Руководитель организации',
                  hint: 'Например: ИП Горовой Р. В.',
                  icon: Icons.person_rounded,
                ),
                SizedBox(height: 24),
                // Интервалы времени для смен
                _buildSectionHeader('Интервалы для отметки', Icons.schedule_rounded),
                SizedBox(height: 8),
                Text(
                  'Если интервал не заполнен, смена не учитывается',
                  style: TextStyle(fontSize: 12.sp, color: Colors.white54),
                ),
                SizedBox(height: 16),
                // Утренняя смена
                _buildShiftTimeSection(
                  context,
                  'Утренняя смена',
                  Icons.wb_sunny_rounded,
                  Colors.orange,
                  morningStart,
                  morningEnd,
                  (start, end) {
                    if (mounted) setState(() {
                      morningStart = start;
                      morningEnd = end;
                    });
                  },
                  morningAbbreviationController,
                ),
                SizedBox(height: 16),
                // Дневная смена
                _buildShiftTimeSection(
                  context,
                  'Дневная смена',
                  Icons.light_mode_rounded,
                  Colors.amber,
                  dayStart,
                  dayEnd,
                  (start, end) {
                    if (mounted) setState(() {
                      dayStart = start;
                      dayEnd = end;
                    });
                  },
                  dayAbbreviationController,
                ),
                SizedBox(height: 16),
                // Ночная смена
                _buildShiftTimeSection(
                  context,
                  'Ночная смена',
                  Icons.nightlight_round,
                  Colors.indigo,
                  nightStart,
                  nightEnd,
                  (start, end) {
                    if (mounted) setState(() {
                      nightStart = start;
                      nightEnd = end;
                    });
                  },
                  nightAbbreviationController,
                ),
                SizedBox(height: 24),
                // Геолокация
                _buildSectionHeader('Геолокация', Icons.my_location_rounded),
                SizedBox(height: 8),
                Text(
                  'Координаты нужны для отметки прихода сотрудников',
                  style: TextStyle(fontSize: 12.sp, color: Colors.white54),
                ),
                SizedBox(height: 12),
                // Показываем текущие координаты если они установлены
                if (latitude != null && longitude != null)
                  Container(
                    padding: EdgeInsets.all(12.w),
                    margin: EdgeInsets.only(bottom: 12.h),
                    decoration: BoxDecoration(
                      color: AppColors.success.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(12.r),
                      border: Border.all(color: AppColors.success.withOpacity(0.4)),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.check_circle_rounded, color: AppColors.success, size: 20),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'GPS: ${latitude!.toStringAsFixed(6)}, ${longitude!.toStringAsFixed(6)}',
                            style: TextStyle(fontSize: 13.sp, color: AppColors.success, fontWeight: FontWeight.w500),
                          ),
                        ),
                      ],
                    ),
                  ),
                // Кнопка установки геолокации
                Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [AppColors.emerald, AppColors.emeraldLight],
                    ),
                    borderRadius: BorderRadius.circular(14.r),
                    border: Border.all(color: AppColors.info.withOpacity(0.4)),
                  ),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: isGettingLocation ? null : () async {
                        if (mounted) setState(() => isGettingLocation = true);
                        try {
                          final position = await AttendanceService.getCurrentLocation()
                              .timeout(Duration(seconds: 15), onTimeout: () {
                            throw Exception('Таймаут получения геолокации');
                          });
                          if (mounted) setState(() {
                            latitude = position.latitude;
                            longitude = position.longitude;
                            isGettingLocation = false;
                          });
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Row(
                                  children: [
                                    Icon(Icons.check_circle_rounded, color: Colors.white),
                                    SizedBox(width: 12),
                                    Text('Геолокация установлена'),
                                  ],
                                ),
                                backgroundColor: AppColors.success,
                                behavior: SnackBarBehavior.floating,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.r)),
                              ),
                            );
                          }
                        } catch (e) {
                          if (mounted) setState(() => isGettingLocation = false);
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Row(
                                  children: [
                                    Icon(Icons.error_rounded, color: Colors.white),
                                    SizedBox(width: 12),
                                    Expanded(child: Text('Ошибка: $e')),
                                  ],
                                ),
                                backgroundColor: AppColors.error,
                                behavior: SnackBarBehavior.floating,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.r)),
                              ),
                            );
                          }
                        }
                      },
                      borderRadius: BorderRadius.circular(14.r),
                      child: Padding(
                        padding: EdgeInsets.symmetric(vertical: 14.h),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            if (isGettingLocation)
                              SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                              )
                            else
                              Icon(Icons.my_location_rounded, color: AppColors.info),
                            SizedBox(width: 10),
                            Flexible(
                              child: Text(
                                isGettingLocation ? 'Получение...' : 'Установить текущую геолокацию',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 14.sp,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('Отмена', style: TextStyle(color: Colors.white54)),
            ),
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [AppColors.gold, AppColors.darkGold],
                ),
                borderRadius: BorderRadius.circular(12.r),
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () {
                    // Валидация
                    if (nameController.text.trim().isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Введите название магазина'),
                          backgroundColor: AppColors.warning,
                        ),
                      );
                      return;
                    }
                    if (addressController.text.trim().isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Введите адрес магазина'),
                          backgroundColor: AppColors.warning,
                        ),
                      );
                      return;
                    }
                    Navigator.pop(context, {
                      'name': nameController.text.trim(),
                      'address': addressController.text.trim(),
                      'inn': innController.text.trim(),
                      'directorName': directorController.text.trim(),
                      'latitude': latitude,
                      'longitude': longitude,
                      'morningShiftStart': morningStart,
                      'morningShiftEnd': morningEnd,
                      'dayShiftStart': dayStart,
                      'dayShiftEnd': dayEnd,
                      'nightShiftStart': nightStart,
                      'nightShiftEnd': nightEnd,
                      'morningAbbreviation': morningAbbreviationController.text.trim(),
                      'dayAbbreviation': dayAbbreviationController.text.trim(),
                      'nightAbbreviation': nightAbbreviationController.text.trim(),
                    });
                  },
                  borderRadius: BorderRadius.circular(12.r),
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: 20.w, vertical: 12.h),
                    child: Text(
                      'Создать',
                      style: TextStyle(color: AppColors.night, fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );

    if (result != null) {
      try {
        // 1. Создаём магазин
        final newShop = await ShopService.createShop(
          name: result['name'] as String,
          address: result['address'] as String,
          latitude: result['latitude'] as double?,
          longitude: result['longitude'] as double?,
        );

        if (newShop == null) {
          throw Exception('Не удалось создать магазин');
        }

        // 2. Сохраняем настройки магазина
        final settings = ShopSettings(
          shopAddress: newShop.address,
          address: result['address'] as String,
          inn: result['inn'] as String? ?? '',
          directorName: result['directorName'] as String? ?? '',
          lastDocumentNumber: 0,
          morningShiftStart: result['morningShiftStart'] as TimeOfDay?,
          morningShiftEnd: result['morningShiftEnd'] as TimeOfDay?,
          dayShiftStart: result['dayShiftStart'] as TimeOfDay?,
          dayShiftEnd: result['dayShiftEnd'] as TimeOfDay?,
          nightShiftStart: result['nightShiftStart'] as TimeOfDay?,
          nightShiftEnd: result['nightShiftEnd'] as TimeOfDay?,
          morningAbbreviation: result['morningAbbreviation']?.toString().isEmpty == true
              ? null
              : result['morningAbbreviation']?.toString(),
          dayAbbreviation: result['dayAbbreviation']?.toString().isEmpty == true
              ? null
              : result['dayAbbreviation']?.toString(),
          nightAbbreviation: result['nightAbbreviation']?.toString().isEmpty == true
              ? null
              : result['nightAbbreviation']?.toString(),
        );

        await _saveShopSettings(settings);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  Icon(Icons.check_circle_rounded, color: Colors.white),
                  SizedBox(width: 12),
                  Expanded(child: Text('Магазин "${newShop.name}" создан')),
                ],
              ),
              backgroundColor: Colors.green,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.r)),
            ),
          );
          await _loadShops();
        }
      } catch (e) {
        Logger.error('Ошибка создания магазина', e);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  Icon(Icons.error_rounded, color: Colors.white),
                  SizedBox(width: 12),
                  Expanded(child: Text('Ошибка: $e')),
                ],
              ),
              backgroundColor: Colors.red,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.r)),
            ),
          );
        }
      }
    }
  }

  Future<bool> _saveShopSettings(ShopSettings settings) async {
    try {
      Logger.debug('Сохранение настроек магазина: ${settings.shopAddress}');
      final success = await ShopService.saveShopSettings(settings);
      if (success) {
        Logger.success('Настройки магазина успешно сохранены');
      } else {
        Logger.error('Ошибка сохранения настроек магазина', null);
      }
      return success;
    } catch (e, stackTrace) {
      Logger.error('Ошибка сохранения настроек магазина: $stackTrace', e);
      return false;
    }
  }

  Future<void> _editShopSettings(Shop shop) async {
    final currentSettings = _settings[shop.address];

    final addressController = TextEditingController(
      text: currentSettings?.address ?? shop.address,
    );
    final innController = TextEditingController(
      text: currentSettings?.inn ?? '',
    );
    final directorController = TextEditingController(
      text: currentSettings?.directorName ?? '',
    );

    // Инициализация времени для смен
    TimeOfDay? morningStart = currentSettings?.morningShiftStart;
    TimeOfDay? morningEnd = currentSettings?.morningShiftEnd;
    TimeOfDay? dayStart = currentSettings?.dayShiftStart;
    TimeOfDay? dayEnd = currentSettings?.dayShiftEnd;
    TimeOfDay? nightStart = currentSettings?.nightShiftStart;
    TimeOfDay? nightEnd = currentSettings?.nightShiftEnd;

    // Контроллеры для аббревиатур
    final morningAbbreviationController = TextEditingController(
      text: currentSettings?.morningAbbreviation ?? '',
    );
    final dayAbbreviationController = TextEditingController(
      text: currentSettings?.dayAbbreviation ?? '',
    );
    final nightAbbreviationController = TextEditingController(
      text: currentSettings?.nightAbbreviation ?? '',
    );

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          backgroundColor: AppColors.emeraldDark,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20.r)),
          title: Row(
            children: [
              Container(
                padding: EdgeInsets.all(10.w),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [AppColors.emerald, AppColors.emeraldLight.withOpacity(0.7)],
                  ),
                  borderRadius: BorderRadius.circular(12.r),
                  border: Border.all(color: AppColors.gold.withOpacity(0.4)),
                ),
                child: Icon(Icons.settings_rounded, color: AppColors.gold),
              ),
              SizedBox(width: 12),
              Expanded(
                child: Text(
                  shop.name,
                  style: TextStyle(fontSize: 18.sp, fontWeight: FontWeight.bold, color: Colors.white),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ID магазина
                Container(
                  padding: EdgeInsets.all(12.w),
                  decoration: BoxDecoration(
                    color: AppColors.night.withOpacity(0.5),
                    borderRadius: BorderRadius.circular(8.r),
                    border: Border.all(color: Colors.white.withOpacity(0.1)),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.tag, size: 16, color: Colors.white54),
                      SizedBox(width: 8),
                      Text(
                        'ID: ',
                        style: TextStyle(
                          fontSize: 12.sp,
                          color: Colors.white54,
                        ),
                      ),
                      Expanded(
                        child: SelectableText(
                          shop.id,
                          style: TextStyle(
                            fontSize: 12.sp,
                            fontFamily: 'monospace',
                            fontWeight: FontWeight.w500,
                            color: Colors.white70,
                          ),
                        ),
                      ),
                      IconButton(
                        icon: Icon(Icons.copy, size: 16, color: Colors.white54),
                        padding: EdgeInsets.zero,
                        constraints: BoxConstraints(),
                        onPressed: () {
                          Clipboard.setData(ClipboardData(text: shop.id));
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('ID скопирован'),
                              duration: Duration(seconds: 1),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),
                SizedBox(height: 16),
                // Основные настройки
                _buildSectionHeader('Основные данные', Icons.business_rounded),
                SizedBox(height: 12),
                _buildStyledTextField(
                  controller: addressController,
                  label: 'Фактический адрес для РКО',
                  icon: Icons.location_on_rounded,
                ),
                SizedBox(height: 16),
                _buildStyledTextField(
                  controller: innController,
                  label: 'ИНН',
                  icon: Icons.numbers_rounded,
                  keyboardType: TextInputType.number,
                ),
                SizedBox(height: 16),
                _buildStyledTextField(
                  controller: directorController,
                  label: 'Руководитель организации',
                  hint: 'Например: ИП Горовой Р. В.',
                  icon: Icons.person_rounded,
                ),
                SizedBox(height: 24),
                // Интервалы времени для смен
                _buildSectionHeader('Интервалы для отметки', Icons.schedule_rounded),
                SizedBox(height: 8),
                Text(
                  'Если интервал не заполнен, смена не учитывается',
                  style: TextStyle(fontSize: 12.sp, color: Colors.white54),
                ),
                SizedBox(height: 16),
                // Утренняя смена
                _buildShiftTimeSection(
                  context,
                  'Утренняя смена',
                  Icons.wb_sunny_rounded,
                  Colors.orange,
                  morningStart,
                  morningEnd,
                  (start, end) {
                    if (mounted) setState(() {
                      morningStart = start;
                      morningEnd = end;
                    });
                  },
                  morningAbbreviationController,
                ),
                SizedBox(height: 16),
                // Дневная смена
                _buildShiftTimeSection(
                  context,
                  'Дневная смена',
                  Icons.light_mode_rounded,
                  Colors.amber,
                  dayStart,
                  dayEnd,
                  (start, end) {
                    if (mounted) setState(() {
                      dayStart = start;
                      dayEnd = end;
                    });
                  },
                  dayAbbreviationController,
                ),
                SizedBox(height: 16),
                // Ночная смена
                _buildShiftTimeSection(
                  context,
                  'Ночная смена',
                  Icons.nightlight_round,
                  Colors.indigo,
                  nightStart,
                  nightEnd,
                  (start, end) {
                    if (mounted) setState(() {
                      nightStart = start;
                      nightEnd = end;
                    });
                  },
                  nightAbbreviationController,
                ),
                SizedBox(height: 24),
                Divider(color: Colors.white.withOpacity(0.15)),
                SizedBox(height: 16),
                // Кнопка обновления геолокации
                Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [AppColors.emerald, AppColors.emeraldLight],
                    ),
                    borderRadius: BorderRadius.circular(14.r),
                    border: Border.all(color: AppColors.info.withOpacity(0.4)),
                  ),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () => _updateShopLocation(context, shop),
                      borderRadius: BorderRadius.circular(14.r),
                      child: Padding(
                        padding: EdgeInsets.symmetric(vertical: 14.h),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.my_location_rounded, color: AppColors.info),
                            SizedBox(width: 10),
                            Text(
                              'Обновить геолокацию',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w600,
                                fontSize: 14.sp,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('Отмена', style: TextStyle(color: Colors.white54)),
            ),
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [AppColors.gold, AppColors.darkGold],
                ),
                borderRadius: BorderRadius.circular(12.r),
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () {
                    Navigator.pop(context, {
                      'address': addressController.text.trim(),
                      'inn': innController.text.trim(),
                      'directorName': directorController.text.trim(),
                      'morningShiftStart': morningStart,
                      'morningShiftEnd': morningEnd,
                      'dayShiftStart': dayStart,
                      'dayShiftEnd': dayEnd,
                      'nightShiftStart': nightStart,
                      'nightShiftEnd': nightEnd,
                      'morningAbbreviation': morningAbbreviationController.text.trim(),
                      'dayAbbreviation': dayAbbreviationController.text.trim(),
                      'nightAbbreviation': nightAbbreviationController.text.trim(),
                    });
                  },
                  borderRadius: BorderRadius.circular(12.r),
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: 20.w, vertical: 12.h),
                    child: Text(
                      'Сохранить',
                      style: TextStyle(color: AppColors.night, fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );

    if (result != null) {
      try {
        final settings = ShopSettings(
          shopAddress: shop.address,
          address: result['address'] ?? shop.address,
          inn: result['inn'] ?? '',
          directorName: result['directorName'] ?? '',
          lastDocumentNumber: currentSettings?.lastDocumentNumber ?? 0,
          morningShiftStart: result['morningShiftStart'] as TimeOfDay?,
          morningShiftEnd: result['morningShiftEnd'] as TimeOfDay?,
          dayShiftStart: result['dayShiftStart'] as TimeOfDay?,
          dayShiftEnd: result['dayShiftEnd'] as TimeOfDay?,
          nightShiftStart: result['nightShiftStart'] as TimeOfDay?,
          nightShiftEnd: result['nightShiftEnd'] as TimeOfDay?,
          morningAbbreviation: result['morningAbbreviation']?.toString().isEmpty == true
              ? null
              : result['morningAbbreviation']?.toString(),
          dayAbbreviation: result['dayAbbreviation']?.toString().isEmpty == true
              ? null
              : result['dayAbbreviation']?.toString(),
          nightAbbreviation: result['nightAbbreviation']?.toString().isEmpty == true
              ? null
              : result['nightAbbreviation']?.toString(),
        );

        final success = await _saveShopSettings(settings);

        if (mounted) {
          if (success) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Row(
                  children: [
                    Icon(Icons.check_circle_rounded, color: Colors.white),
                    SizedBox(width: 12),
                    Text('Настройки успешно сохранены'),
                  ],
                ),
                backgroundColor: Colors.green,
                behavior: SnackBarBehavior.floating,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.r)),
                margin: EdgeInsets.all(16.w),
                duration: Duration(seconds: 2),
              ),
            );
            await _loadShops();
          } else {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Row(
                  children: [
                    Icon(Icons.error_rounded, color: Colors.white),
                    SizedBox(width: 12),
                    Expanded(child: Text('Ошибка сохранения настроек')),
                  ],
                ),
                backgroundColor: Colors.red,
                behavior: SnackBarBehavior.floating,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.r)),
                margin: EdgeInsets.all(16.w),
                duration: Duration(seconds: 4),
              ),
            );
          }
        }
      } catch (e, stackTrace) {
        Logger.error('Критическая ошибка при сохранении настроек: $stackTrace', e);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Ошибка: $e'),
              backgroundColor: Colors.red,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.r)),
              margin: EdgeInsets.all(16.w),
              duration: Duration(seconds: 4),
            ),
          );
        }
      }
    }
  }

  Widget _buildSectionHeader(String title, IconData icon) {
    return Row(
      children: [
        Container(
          padding: EdgeInsets.all(8.w),
          decoration: BoxDecoration(
            color: AppColors.emerald.withOpacity(0.4),
            borderRadius: BorderRadius.circular(10.r),
            border: Border.all(color: AppColors.gold.withOpacity(0.3)),
          ),
          child: Icon(icon, color: AppColors.gold, size: 18),
        ),
        SizedBox(width: 10),
        Text(
          title,
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15.sp, color: Colors.white.withOpacity(0.9)),
        ),
      ],
    );
  }

  Widget _buildStyledTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    String? hint,
    TextInputType keyboardType = TextInputType.text,
  }) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      style: TextStyle(color: Colors.white),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: Colors.white60),
        hintText: hint,
        hintStyle: TextStyle(color: Colors.white30),
        prefixIcon: Icon(icon, color: AppColors.gold.withOpacity(0.7)),
        filled: true,
        fillColor: AppColors.night.withOpacity(0.4),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14.r),
          borderSide: BorderSide(color: Colors.white.withOpacity(0.15)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14.r),
          borderSide: BorderSide(color: Colors.white.withOpacity(0.15)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14.r),
          borderSide: BorderSide(color: AppColors.gold, width: 2),
        ),
      ),
    );
  }

  Future<void> _updateShopLocation(BuildContext dialogContext, Shop shop) async {
    Logger.debug('🗺️ Начало обновления геолокации для магазина: ${shop.name}');

    final navigator = Navigator.of(context, rootNavigator: true);

    showDialog(
      context: context,
      barrierDismissible: false,
      useRootNavigator: true,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20.r)),
        content: Row(
          children: [
            Container(
              padding: EdgeInsets.all(12.w),
              decoration: BoxDecoration(
                color: Colors.blue.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: CircularProgressIndicator(
                color: Colors.blue,
                strokeWidth: 3,
              ),
            ),
            SizedBox(width: 20),
            Text('Получение геолокации...'),
          ],
        ),
      ),
    );

    try {
      Logger.debug('🗺️ Запрос геолокации...');
      final position = await AttendanceService.getCurrentLocation()
          .timeout(Duration(seconds: 15), onTimeout: () {
        throw Exception('Таймаут получения геолокации. Убедитесь что GPS включен.');
      });
      Logger.debug('🗺️ Геолокация получена: ${position.latitude}, ${position.longitude}');

      if (mounted) {
        navigator.pop();
      }

      if (!mounted) return;
      final confirm = await showDialog<bool>(
        context: context,
        useRootNavigator: true,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20.r)),
          title: Row(
            children: [
              Container(
                padding: EdgeInsets.all(10.w),
                decoration: BoxDecoration(
                  color: Colors.blue.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12.r),
                ),
                child: Icon(Icons.location_on_rounded, color: Colors.blue),
              ),
              SizedBox(width: 12),
              Text('Обновить геолокацию?'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: EdgeInsets.all(12.w),
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: BorderRadius.circular(12.r),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Магазин: ${shop.name}',
                      style: TextStyle(fontWeight: FontWeight.w500),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    SizedBox(height: 8),
                    Divider(height: 1),
                    SizedBox(height: 8),
                    Text('Новые координаты:', style: TextStyle(color: Colors.blue, fontWeight: FontWeight.w500)),
                    Text('Широта: ${position.latitude.toStringAsFixed(6)}'),
                    Text('Долгота: ${position.longitude.toStringAsFixed(6)}'),
                  ],
                ),
              ),
              if (shop.latitude != null && shop.longitude != null) ...[
                SizedBox(height: 12),
                Container(
                  padding: EdgeInsets.all(12.w),
                  decoration: BoxDecoration(
                    color: Colors.orange.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12.r),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Текущие координаты:', style: TextStyle(color: Colors.orange[700], fontWeight: FontWeight.w500)),
                      Text('Широта: ${shop.latitude!.toStringAsFixed(6)}', style: TextStyle(color: Colors.grey[700])),
                      Text('Долгота: ${shop.longitude!.toStringAsFixed(6)}', style: TextStyle(color: Colors.grey[700])),
                    ],
                  ),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text('Отмена', style: TextStyle(color: Colors.grey[600])),
            ),
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: [Colors.blue, Color(0xFF1E88E5)]),
                borderRadius: BorderRadius.circular(12.r),
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () => Navigator.pop(ctx, true),
                  borderRadius: BorderRadius.circular(12.r),
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: 20.w, vertical: 12.h),
                    child: Text('Обновить', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                  ),
                ),
              ),
            ),
          ],
        ),
      );

      if (confirm == true) {
        Logger.debug('🗺️ Отправляем обновление геолокации: id=${shop.id}, lat=${position.latitude}, lon=${position.longitude}');
        final updatedShop = await ShopService.updateShop(
          id: shop.id,
          latitude: position.latitude,
          longitude: position.longitude,
        );
        Logger.debug('🗺️ Результат обновления: ${updatedShop != null ? "успешно" : "ошибка"}');

        if (mounted) {
          if (updatedShop != null) {
            CacheManager.remove('shops_list');

            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Row(
                  children: [
                    Icon(Icons.check_circle_rounded, color: Colors.white),
                    SizedBox(width: 12),
                    Text('Геолокация магазина обновлена'),
                  ],
                ),
                backgroundColor: Colors.green,
                behavior: SnackBarBehavior.floating,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.r)),
                margin: EdgeInsets.all(16.w),
              ),
            );
            await _loadShops();
          } else {
            Logger.error('🗺️ ShopService.updateShop вернул null');
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Row(
                  children: [
                    Icon(Icons.error_rounded, color: Colors.white),
                    SizedBox(width: 12),
                    Text('Ошибка обновления геолокации'),
                  ],
                ),
                backgroundColor: Colors.red,
                behavior: SnackBarBehavior.floating,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.r)),
                margin: EdgeInsets.all(16.w),
              ),
            );
          }
        }
      }
    } catch (e, stackTrace) {
      Logger.error('🗺️ Ошибка обновления геолокации: $e\n$stackTrace');
      if (mounted) {
        navigator.pop();
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка: $e'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.r)),
            margin: EdgeInsets.all(16.w),
          ),
        );
      }
    }
  }

  Widget _buildShiftTimeSection(
    BuildContext context,
    String title,
    IconData icon,
    Color color,
    TimeOfDay? startTime,
    TimeOfDay? endTime,
    Function(TimeOfDay?, TimeOfDay?) onChanged,
    TextEditingController abbreviationController,
  ) {
    return Container(
      padding: EdgeInsets.all(14.w),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(14.r),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 20),
              SizedBox(width: 8),
              Text(
                title,
                style: TextStyle(fontWeight: FontWeight.w600, color: color),
              ),
            ],
          ),
          SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _buildTimePickerButton(
                  context,
                  startTime,
                  color,
                  () async {
                    final time = await showTimePicker(
                      context: context,
                      initialTime: startTime ?? TimeOfDay(hour: 8, minute: 0),
                      builder: (context, child) {
                        return MediaQuery(
                          data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
                          child: child!,
                        );
                      },
                    );
                    if (time != null) {
                      onChanged(time, endTime);
                    }
                  },
                ),
              ),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 10.w),
                child: Text('—', style: TextStyle(color: color, fontWeight: FontWeight.bold)),
              ),
              Expanded(
                child: _buildTimePickerButton(
                  context,
                  endTime,
                  color,
                  () async {
                    final time = await showTimePicker(
                      context: context,
                      initialTime: endTime ?? TimeOfDay(hour: 18, minute: 0),
                      builder: (context, child) {
                        return MediaQuery(
                          data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
                          child: child!,
                        );
                      },
                    );
                    if (time != null) {
                      onChanged(startTime, time);
                    }
                  },
                ),
              ),
            ],
          ),
          SizedBox(height: 12),
          TextField(
            controller: abbreviationController,
            style: TextStyle(color: Colors.white),
            decoration: InputDecoration(
              labelText: 'Аббревиатура',
              hintText: 'Например: Ост(У)',
              labelStyle: TextStyle(color: color),
              hintStyle: TextStyle(color: Colors.white30),
              filled: true,
              fillColor: AppColors.night.withOpacity(0.4),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12.r),
                borderSide: BorderSide(color: color.withOpacity(0.3)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12.r),
                borderSide: BorderSide(color: color.withOpacity(0.3)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12.r),
                borderSide: BorderSide(color: color, width: 2),
              ),
              contentPadding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 12.h),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTimePickerButton(BuildContext context, TimeOfDay? time, Color color, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12.r),
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 14.h),
        decoration: BoxDecoration(
          color: AppColors.night.withOpacity(0.4),
          borderRadius: BorderRadius.circular(12.r),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Flexible(
              child: Text(
                time != null
                    ? '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}'
                    : '—',
                style: TextStyle(
                  color: time != null ? Colors.white : Colors.white38,
                  fontWeight: time != null ? FontWeight.w500 : FontWeight.normal,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            SizedBox(width: 4),
            Icon(Icons.access_time_rounded, size: 18, color: color),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.night,
      appBar: AppBar(
        title: Text(
          'Управление магазинами',
          style: TextStyle(fontWeight: FontWeight.w600, color: Colors.white),
        ),
        backgroundColor: AppColors.night,
        iconTheme: IconThemeData(color: Colors.white),
        elevation: 0,
        actions: [
          // Кнопка добавления магазина
          Container(
            margin: EdgeInsets.only(right: 4.w),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [AppColors.emerald.withOpacity(0.5), AppColors.emeraldDark.withOpacity(0.5)],
              ),
              borderRadius: BorderRadius.circular(14.r),
              border: Border.all(color: AppColors.gold.withOpacity(0.3)),
            ),
            child: IconButton(
              icon: Icon(Icons.add_business_rounded, color: AppColors.gold),
              onPressed: _showAddShopDialog,
              tooltip: 'Добавить магазин',
            ),
          ),
          Container(
            margin: EdgeInsets.only(right: 8.w),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.1),
              borderRadius: BorderRadius.circular(14.r),
            ),
            child: IconButton(
              icon: Icon(Icons.refresh_rounded, color: Colors.white70),
              onPressed: _loadShops,
              tooltip: 'Обновить',
            ),
          ),
        ],
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              AppColors.night,
              AppColors.emeraldDark,
              AppColors.emerald.withOpacity(0.8),
            ],
          ),
        ),
        child: Column(
          children: [
            // Поиск
            Padding(
              padding: EdgeInsets.fromLTRB(16.w, 8.h, 16.w, 16.h),
              child: Container(
                decoration: BoxDecoration(
                  color: AppColors.emeraldDark.withOpacity(0.6),
                  borderRadius: BorderRadius.circular(16.r),
                  border: Border.all(color: Colors.white.withOpacity(0.12)),
                ),
                child: TextField(
                  style: TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    hintText: 'Поиск магазина...',
                    hintStyle: TextStyle(color: Colors.white38),
                    prefixIcon: Icon(Icons.search_rounded, color: Colors.white38),
                    filled: true,
                    fillColor: Colors.transparent,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16.r),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: EdgeInsets.symmetric(horizontal: 20.w, vertical: 16.h),
                  ),
                  onChanged: (value) {
                    if (mounted) setState(() {
                      _searchQuery = value.trim().toLowerCase();
                    });
                  },
                ),
              ),
            ),
            // Список магазинов
            Expanded(
              child: _isLoading
                  ? _buildLoadingState()
                  : _shops.isEmpty
                      ? _buildEmptyState()
                      : _buildShopsList(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLoadingState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: EdgeInsets.all(20.w),
            decoration: BoxDecoration(
              color: AppColors.emerald.withOpacity(0.3),
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.gold.withOpacity(0.3)),
            ),
            child: CircularProgressIndicator(
              color: AppColors.gold,
              strokeWidth: 3,
            ),
          ),
          SizedBox(height: 24),
          Text(
            'Загрузка магазинов...',
            style: TextStyle(
              color: Colors.white.withOpacity(0.8),
              fontSize: 15.sp,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: EdgeInsets.all(28.w),
            decoration: BoxDecoration(
              color: AppColors.emerald.withOpacity(0.2),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white.withOpacity(0.1)),
            ),
            child: Icon(
              Icons.store_outlined,
              size: 60,
              color: Colors.white.withOpacity(0.5),
            ),
          ),
          SizedBox(height: 20),
          Text(
            'Магазины не найдены',
            style: TextStyle(
              fontSize: 18.sp,
              color: Colors.white.withOpacity(0.9),
              fontWeight: FontWeight.w600,
            ),
          ),
          SizedBox(height: 8),
          Text(
            'Попробуйте изменить поисковый запрос',
            style: TextStyle(
              fontSize: 14.sp,
              color: Colors.white54,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildShopsList() {
    final filteredShops = _shops.where((shop) {
      if (_searchQuery.isEmpty) return true;
      final name = shop.name.toLowerCase();
      final address = shop.address.toLowerCase();
      return name.contains(_searchQuery) || address.contains(_searchQuery);
    }).toList();

    if (filteredShops.isEmpty) {
      return _buildEmptyState();
    }

    return RefreshIndicator(
      onRefresh: _loadShops,
      color: AppColors.gold,
      backgroundColor: AppColors.emeraldDark,
      child: ListView.builder(
        padding: EdgeInsets.fromLTRB(16.w, 0.h, 16.w, 16.h),
        itemCount: filteredShops.length,
        itemBuilder: (context, index) {
          final shop = filteredShops[index];
          return AnimatedBuilder(
            animation: _animationController,
            builder: (context, child) {
              final delay = (index * 0.1).clamp(0.0, 0.8);
              final animationValue = Curves.easeOutCubic.transform(
                (_animationController.value - delay).clamp(0.0, 1.0),
              );
              return Transform.translate(
                offset: Offset(0, 30 * (1 - animationValue)),
                child: Opacity(
                  opacity: animationValue,
                  child: _buildShopCard(shop),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildShopCard(Shop shop) {
    final settings = _settings[shop.address];
    final hasSettings = settings != null &&
        (settings.address.isNotEmpty ||
         settings.inn.isNotEmpty ||
         settings.directorName.isNotEmpty);
    final hasLocation = shop.latitude != null && shop.longitude != null;

    return Container(
      margin: EdgeInsets.only(bottom: 12.h),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16.r),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppColors.emeraldDark,
            AppColors.emerald.withOpacity(0.85),
          ],
        ),
        border: Border.all(color: Colors.white.withOpacity(0.12)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.3),
            blurRadius: 10,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16.r),
        child: InkWell(
          onTap: () => _editShopSettings(shop),
          borderRadius: BorderRadius.circular(16.r),
          splashColor: AppColors.gold.withOpacity(0.15),
          child: Padding(
            padding: EdgeInsets.all(14.w),
            child: Row(
              children: [
                // Иконка магазина
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14.r),
                    color: AppColors.night.withOpacity(0.4),
                    border: Border.all(color: AppColors.gold.withOpacity(0.3)),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(14.r),
                    child: ShopIcon(size: 56),
                  ),
                ),
                SizedBox(width: 14),
                // Информация о магазине
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        shop.name,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15.sp,
                          color: Colors.white,
                        ),
                      ),
                      SizedBox(height: 3),
                      Text(
                        shop.address,
                        style: TextStyle(
                          fontSize: 12.sp,
                          color: Colors.white60,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      SizedBox(height: 8),
                      // Статусы
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: [
                          _buildStatusBadge(
                            hasSettings ? 'Настроен' : 'Не настроен',
                            hasSettings ? AppColors.success : AppColors.warning,
                            hasSettings ? Icons.check_circle_rounded : Icons.warning_rounded,
                          ),
                          _buildStatusBadge(
                            hasLocation ? 'GPS' : 'Нет GPS',
                            hasLocation ? AppColors.info : Colors.grey,
                            hasLocation ? Icons.location_on_rounded : Icons.location_off_rounded,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                // Кнопки
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildCardActionButton(
                      icon: Icons.edit_rounded,
                      color: AppColors.gold,
                      onTap: () => _editShopSettings(shop),
                    ),
                    if (shop.id.isNotEmpty) ...[
                      SizedBox(height: 8),
                      _buildCardActionButton(
                        icon: Icons.delete_outline_rounded,
                        color: AppColors.error,
                        onTap: () => _confirmDeleteShop(shop),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCardActionButton({
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10.r),
        child: Container(
          padding: EdgeInsets.all(9.w),
          decoration: BoxDecoration(
            color: color.withOpacity(0.15),
            borderRadius: BorderRadius.circular(10.r),
            border: Border.all(color: color.withOpacity(0.3)),
          ),
          child: Icon(icon, color: color, size: 18),
        ),
      ),
    );
  }

  /// Показать диалог подтверждения удаления магазина
  Future<void> _confirmDeleteShop(Shop shop) async {
    // Защита от удаления магазинов с пустым ID
    if (shop.id.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Невозможно удалить магазин с пустым ID'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Удалить магазин?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Вы действительно хотите удалить магазин?',
              style: TextStyle(
                fontSize: 14.sp,
                color: Colors.grey[700],
              ),
            ),
            SizedBox(height: 16),
            Container(
              padding: EdgeInsets.all(12.w),
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.05),
                borderRadius: BorderRadius.circular(8.r),
                border: Border.all(color: Colors.red.withOpacity(0.2)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.store, color: AppColors.primaryGreen, size: 20),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          shop.name,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14.sp,
                          ),
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 4),
                  Text(
                    shop.address,
                    style: TextStyle(
                      fontSize: 12.sp,
                      color: Colors.grey[600],
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(height: 12),
            Container(
              padding: EdgeInsets.all(10.w),
              decoration: BoxDecoration(
                color: Colors.amber.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8.r),
              ),
              child: Row(
                children: [
                  Icon(Icons.warning_amber_rounded, color: Colors.amber[800], size: 20),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Это действие нельзя отменить',
                      style: TextStyle(
                        fontSize: 12.sp,
                        color: Colors.amber[900],
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Отмена'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: Text('Удалить'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _deleteShop(shop);
    }
  }

  /// Удалить магазин
  Future<void> _deleteShop(Shop shop) async {
    // Показываем индикатор загрузки
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => Center(
        child: CircularProgressIndicator(),
      ),
    );

    try {
      final success = await ShopService.deleteShop(shop.id);

      if (!mounted) return;

      // Закрываем индикатор загрузки
      Navigator.pop(context);

      if (success) {
        // Показываем успешное сообщение
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Icon(Icons.check_circle, color: Colors.white),
                SizedBox(width: 12),
                Expanded(
                  child: Text('Магазин "${shop.name}" успешно удален'),
                ),
              ],
            ),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10.r),
            ),
          ),
        );

        // Обновляем список магазинов
        await _loadShops();
      } else {
        // Показываем ошибку
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Icon(Icons.error_outline, color: Colors.white),
                SizedBox(width: 12),
                Expanded(
                  child: Text('Не удалось удалить магазин'),
                ),
              ],
            ),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10.r),
            ),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;

      // Закрываем индикатор загрузки
      Navigator.pop(context);

      // Показываем ошибку
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(Icons.error_outline, color: Colors.white),
              SizedBox(width: 12),
              Expanded(
                child: Text('Ошибка: $e'),
              ),
            ],
          ),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10.r),
          ),
        ),
      );
    }
  }

  Widget _buildStatusBadge(String text, Color color, IconData icon) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 4.h),
      decoration: BoxDecoration(
        color: color.withOpacity(0.2),
        borderRadius: BorderRadius.circular(8.r),
        border: Border.all(color: color.withOpacity(0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 12),
          SizedBox(width: 4),
          Text(
            text,
            style: TextStyle(
              color: color,
              fontSize: 10.sp,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
