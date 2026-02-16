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
    setState(() {
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

      setState(() {
        _shops = validShops;
        _settings = settings;
        _isLoading = false;
      });
      _animationController.forward();
    } catch (e) {
      Logger.error('Ошибка загрузки магазинов', e);
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
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20.r)),
          title: Row(
            children: [
              Container(
                padding: EdgeInsets.all(10.w),
                decoration: BoxDecoration(
                  color: Color(0xFF004D40).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12.r),
                ),
                child: Icon(Icons.add_business_rounded, color: Color(0xFF004D40)),
              ),
              SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Новый магазин',
                  style: TextStyle(fontSize: 18.sp, fontWeight: FontWeight.bold),
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
                  style: TextStyle(fontSize: 12.sp, color: Colors.grey[600]),
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
                    setState(() {
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
                    setState(() {
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
                    setState(() {
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
                  style: TextStyle(fontSize: 12.sp, color: Colors.grey[600]),
                ),
                SizedBox(height: 12),
                // Показываем текущие координаты если они установлены
                if (latitude != null && longitude != null)
                  Container(
                    padding: EdgeInsets.all(12.w),
                    margin: EdgeInsets.only(bottom: 12.h),
                    decoration: BoxDecoration(
                      color: Colors.green.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12.r),
                      border: Border.all(color: Colors.green.withOpacity(0.3)),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.check_circle_rounded, color: Colors.green, size: 20),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'GPS: ${latitude!.toStringAsFixed(6)}, ${longitude!.toStringAsFixed(6)}',
                            style: TextStyle(fontSize: 13.sp, color: Colors.green, fontWeight: FontWeight.w500),
                          ),
                        ),
                      ],
                    ),
                  ),
                // Кнопка установки геолокации
                Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Colors.blue, Color(0xFF1E88E5)],
                    ),
                    borderRadius: BorderRadius.circular(14.r),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.blue.withOpacity(0.3),
                        blurRadius: 8,
                        offset: Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: isGettingLocation ? null : () async {
                        setState(() => isGettingLocation = true);
                        try {
                          final position = await AttendanceService.getCurrentLocation()
                              .timeout(Duration(seconds: 15), onTimeout: () {
                            throw Exception('Таймаут получения геолокации');
                          });
                          setState(() {
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
                                backgroundColor: Colors.green,
                                behavior: SnackBarBehavior.floating,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.r)),
                              ),
                            );
                          }
                        } catch (e) {
                          setState(() => isGettingLocation = false);
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
                                backgroundColor: Colors.red,
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
                              Icon(Icons.my_location_rounded, color: Colors.white),
                            SizedBox(width: 10),
                            Text(
                              isGettingLocation ? 'Получение...' : 'Установить текущую геолокацию',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w600,
                                fontSize: 15.sp,
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
              child: Text('Отмена', style: TextStyle(color: Colors.grey[600])),
            ),
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFF004D40), Color(0xFF00695C)],
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
                          backgroundColor: Colors.orange,
                        ),
                      );
                      return;
                    }
                    if (addressController.text.trim().isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Введите адрес магазина'),
                          backgroundColor: Colors.orange,
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
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
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
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20.r)),
          title: Row(
            children: [
              Container(
                padding: EdgeInsets.all(10.w),
                decoration: BoxDecoration(
                  color: Color(0xFF004D40).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12.r),
                ),
                child: Icon(Icons.settings_rounded, color: Color(0xFF004D40)),
              ),
              SizedBox(width: 12),
              Expanded(
                child: Text(
                  shop.name,
                  style: TextStyle(fontSize: 18.sp, fontWeight: FontWeight.bold),
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
                // ID магазина (для синхронизации DBF)
                Container(
                  padding: EdgeInsets.all(12.w),
                  decoration: BoxDecoration(
                    color: Colors.grey[100],
                    borderRadius: BorderRadius.circular(8.r),
                    border: Border.all(color: Colors.grey[300]!),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.tag, size: 16, color: Colors.grey[600]),
                      SizedBox(width: 8),
                      Text(
                        'ID: ',
                        style: TextStyle(
                          fontSize: 12.sp,
                          color: Colors.grey[600],
                        ),
                      ),
                      Expanded(
                        child: SelectableText(
                          shop.id,
                          style: TextStyle(
                            fontSize: 12.sp,
                            fontFamily: 'monospace',
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      IconButton(
                        icon: Icon(Icons.copy, size: 16),
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
                  style: TextStyle(fontSize: 12.sp, color: Colors.grey[600]),
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
                    setState(() {
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
                    setState(() {
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
                    setState(() {
                      nightStart = start;
                      nightEnd = end;
                    });
                  },
                  nightAbbreviationController,
                ),
                SizedBox(height: 24),
                Divider(),
                SizedBox(height: 16),
                // Кнопка обновления геолокации
                Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Colors.blue, Color(0xFF1E88E5)],
                    ),
                    borderRadius: BorderRadius.circular(14.r),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.blue.withOpacity(0.3),
                        blurRadius: 8,
                        offset: Offset(0, 4),
                      ),
                    ],
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
                            Icon(Icons.my_location_rounded, color: Colors.white),
                            SizedBox(width: 10),
                            Text(
                              'Обновить геолокацию',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w600,
                                fontSize: 15.sp,
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
              child: Text('Отмена', style: TextStyle(color: Colors.grey[600])),
            ),
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFF004D40), Color(0xFF00695C)],
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
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
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
            color: Color(0xFF004D40).withOpacity(0.1),
            borderRadius: BorderRadius.circular(10.r),
          ),
          child: Icon(icon, color: Color(0xFF004D40), size: 20),
        ),
        SizedBox(width: 10),
        Text(
          title,
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16.sp),
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
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: Icon(icon, color: Color(0xFF004D40)),
        filled: true,
        fillColor: Colors.grey[50],
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14.r),
          borderSide: BorderSide(color: Colors.grey[300]!),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14.r),
          borderSide: BorderSide(color: Colors.grey[300]!),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14.r),
          borderSide: BorderSide(color: Color(0xFF004D40), width: 2),
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
        color: color.withOpacity(0.05),
        borderRadius: BorderRadius.circular(14.r),
        border: Border.all(color: color.withOpacity(0.2)),
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
            decoration: InputDecoration(
              labelText: 'Аббревиатура',
              hintText: 'Например: Ост(У)',
              labelStyle: TextStyle(color: color),
              filled: true,
              fillColor: Colors.white,
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
          color: Colors.white,
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
                  color: time != null ? Colors.black87 : Colors.grey,
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
      backgroundColor: Color(0xFF004D40),
      appBar: AppBar(
        title: Text(
          'Управление магазинами',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
        backgroundColor: Color(0xFF004D40),
        elevation: 0,
        actions: [
          // Кнопка добавления магазина
          Container(
            margin: EdgeInsets.only(right: 4.w),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.15),
              borderRadius: BorderRadius.circular(12.r),
            ),
            child: IconButton(
              icon: Icon(Icons.add_business_rounded),
              onPressed: _showAddShopDialog,
              tooltip: 'Добавить магазин',
            ),
          ),
          Container(
            margin: EdgeInsets.only(right: 8.w),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.15),
              borderRadius: BorderRadius.circular(12.r),
            ),
            child: IconButton(
              icon: Icon(Icons.refresh_rounded),
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
              Color(0xFF004D40),
              Color(0xFF00695C),
              Color(0xFF00796B),
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
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16.r),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.15),
                      blurRadius: 10,
                      offset: Offset(0, 4),
                    ),
                  ],
                ),
                child: TextField(
                  decoration: InputDecoration(
                    hintText: 'Поиск магазина...',
                    hintStyle: TextStyle(color: Colors.grey[400]),
                    prefixIcon: Icon(Icons.search_rounded, color: Colors.grey[500]),
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16.r),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: EdgeInsets.symmetric(horizontal: 20.w, vertical: 16.h),
                  ),
                  onChanged: (value) {
                    setState(() {
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
              color: Colors.white.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: CircularProgressIndicator(
              color: Colors.white,
              strokeWidth: 3,
            ),
          ),
          SizedBox(height: 24),
          Text(
            'Загрузка магазинов...',
            style: TextStyle(
              color: Colors.white.withOpacity(0.9),
              fontSize: 16.sp,
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
            padding: EdgeInsets.all(32.w),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.store_outlined,
              size: 80,
              color: Colors.white.withOpacity(0.7),
            ),
          ),
          SizedBox(height: 24),
          Text(
            'Магазины не найдены',
            style: TextStyle(
              fontSize: 22.sp,
              color: Colors.white,
              fontWeight: FontWeight.w600,
            ),
          ),
          SizedBox(height: 12),
          Text(
            'Попробуйте изменить поисковый запрос',
            style: TextStyle(
              fontSize: 16.sp,
              color: Colors.white.withOpacity(0.7),
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
      color: Color(0xFF004D40),
      backgroundColor: Colors.white,
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
        borderRadius: BorderRadius.circular(20.r),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.15),
            blurRadius: 12,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20.r),
        child: InkWell(
          onTap: () => _editShopSettings(shop),
          borderRadius: BorderRadius.circular(20.r),
          child: Padding(
            padding: EdgeInsets.all(16.w),
            child: Row(
              children: [
                // Иконка магазина
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16.r),
                    boxShadow: [
                      BoxShadow(
                        color: Color(0xFF004D40).withOpacity(0.3),
                        blurRadius: 8,
                        offset: Offset(0, 4),
                      ),
                    ],
                  ),
                  child: ShopIcon(size: 64),
                ),
                SizedBox(width: 16),
                // Информация о магазине
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        shop.name,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16.sp,
                          color: Color(0xFF1A1A1A),
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        shop.address,
                        style: TextStyle(
                          fontSize: 13.sp,
                          color: Colors.grey[600],
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      SizedBox(height: 10),
                      // Статусы
                      Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        children: [
                          _buildStatusBadge(
                            hasSettings ? 'Настроен' : 'Не настроен',
                            hasSettings ? Colors.green : Colors.orange,
                            hasSettings ? Icons.check_circle_rounded : Icons.warning_rounded,
                          ),
                          _buildStatusBadge(
                            hasLocation ? 'GPS' : 'Нет GPS',
                            hasLocation ? Colors.blue : Colors.grey,
                            hasLocation ? Icons.location_on_rounded : Icons.location_off_rounded,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                // Кнопки редактирования и удаления
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: EdgeInsets.all(12.w),
                      decoration: BoxDecoration(
                        color: Color(0xFF004D40).withOpacity(0.1),
                        borderRadius: BorderRadius.circular(14.r),
                      ),
                      child: Icon(
                        Icons.edit_rounded,
                        color: Color(0xFF004D40),
                        size: 22,
                      ),
                    ),
                    // Показываем кнопку удаления только если у магазина есть ID
                    if (shop.id.isNotEmpty) ...[
                      SizedBox(width: 8),
                      GestureDetector(
                        onTap: () => _confirmDeleteShop(shop),
                        child: Container(
                          padding: EdgeInsets.all(12.w),
                          decoration: BoxDecoration(
                            color: Colors.red.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(14.r),
                          ),
                          child: Icon(
                            Icons.delete_outline_rounded,
                            color: Colors.red,
                            size: 22,
                          ),
                        ),
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
                      Icon(Icons.store, color: Color(0xFF004D40), size: 20),
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
      padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 5.h),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20.r),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 14),
          SizedBox(width: 4),
          Text(
            text,
            style: TextStyle(
              color: color,
              fontSize: 11.sp,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
