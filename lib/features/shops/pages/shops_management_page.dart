import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/utils/logger.dart';
import '../../../core/widgets/shop_icon.dart';
import '../models/shop_model.dart';
import '../models/shop_settings_model.dart';
import '../services/shop_service.dart';
import '../../attendance/services/attendance_service.dart';
import '../../../core/utils/cache_manager.dart';

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
      duration: const Duration(milliseconds: 800),
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
      // Очищаем кэш магазинов перед загрузкой
      CacheManager.remove('shops_list');

      final shops = await ShopService.getShops();
      Logger.debug('📋 Загружено магазинов: ${shops.length}');
      for (var shop in shops) {
        Logger.debug('   - ${shop.name} (ID: ${shop.id})');
      }

      // Загружаем настройки для каждого магазина
      final Map<String, ShopSettings?> settings = {};
      for (var shop in shops) {
        final settingsData = await _loadShopSettings(shop.address);
        settings[shop.address] = settingsData;
      }

      setState(() {
        _shops = shops;
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
                const Icon(Icons.error_rounded, color: Colors.white),
                const SizedBox(width: 12),
                Expanded(child: Text('Ошибка загрузки магазинов: $e')),
              ],
            ),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            margin: const EdgeInsets.all(16),
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
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFF004D40).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.settings_rounded, color: Color(0xFF004D40)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  shop.name,
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Основные настройки
                _buildSectionHeader('Основные данные', Icons.business_rounded),
                const SizedBox(height: 12),
                _buildStyledTextField(
                  controller: addressController,
                  label: 'Фактический адрес для РКО',
                  icon: Icons.location_on_rounded,
                ),
                const SizedBox(height: 16),
                _buildStyledTextField(
                  controller: innController,
                  label: 'ИНН',
                  icon: Icons.numbers_rounded,
                  keyboardType: TextInputType.number,
                ),
                const SizedBox(height: 16),
                _buildStyledTextField(
                  controller: directorController,
                  label: 'Руководитель организации',
                  hint: 'Например: ИП Горовой Р. В.',
                  icon: Icons.person_rounded,
                ),
                const SizedBox(height: 24),
                // Интервалы времени для смен
                _buildSectionHeader('Интервалы для отметки', Icons.schedule_rounded),
                const SizedBox(height: 8),
                Text(
                  'Если интервал не заполнен, смена не учитывается',
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                ),
                const SizedBox(height: 16),
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
                const SizedBox(height: 16),
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
                const SizedBox(height: 16),
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
                const SizedBox(height: 24),
                const Divider(),
                const SizedBox(height: 16),
                // Кнопка обновления геолокации
                Container(
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Colors.blue, Color(0xFF1E88E5)],
                    ),
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.blue.withOpacity(0.3),
                        blurRadius: 8,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () => _updateShopLocation(context, shop),
                      borderRadius: BorderRadius.circular(14),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.my_location_rounded, color: Colors.white),
                            const SizedBox(width: 10),
                            const Text(
                              'Обновить геолокацию',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w600,
                                fontSize: 15,
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
                gradient: const LinearGradient(
                  colors: [Color(0xFF004D40), Color(0xFF00695C)],
                ),
                borderRadius: BorderRadius.circular(12),
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
                  borderRadius: BorderRadius.circular(12),
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 20, vertical: 12),
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
                    const Icon(Icons.check_circle_rounded, color: Colors.white),
                    const SizedBox(width: 12),
                    const Text('Настройки успешно сохранены'),
                  ],
                ),
                backgroundColor: Colors.green,
                behavior: SnackBarBehavior.floating,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                margin: const EdgeInsets.all(16),
                duration: const Duration(seconds: 2),
              ),
            );
            await _loadShops();
          } else {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Row(
                  children: [
                    const Icon(Icons.error_rounded, color: Colors.white),
                    const SizedBox(width: 12),
                    const Expanded(child: Text('Ошибка сохранения настроек')),
                  ],
                ),
                backgroundColor: Colors.red,
                behavior: SnackBarBehavior.floating,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                margin: const EdgeInsets.all(16),
                duration: const Duration(seconds: 4),
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
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              margin: const EdgeInsets.all(16),
              duration: const Duration(seconds: 4),
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
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: const Color(0xFF004D40).withOpacity(0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: const Color(0xFF004D40), size: 20),
        ),
        const SizedBox(width: 10),
        Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
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
        prefixIcon: Icon(icon, color: const Color(0xFF004D40)),
        filled: true,
        fillColor: Colors.grey[50],
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: Colors.grey[300]!),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: Colors.grey[300]!),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFF004D40), width: 2),
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        content: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: const CircularProgressIndicator(
                color: Colors.blue,
                strokeWidth: 3,
              ),
            ),
            const SizedBox(width: 20),
            const Text('Получение геолокации...'),
          ],
        ),
      ),
    );

    try {
      Logger.debug('🗺️ Запрос геолокации...');
      final position = await AttendanceService.getCurrentLocation()
          .timeout(const Duration(seconds: 15), onTimeout: () {
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
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.blue.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.location_on_rounded, color: Colors.blue),
              ),
              const SizedBox(width: 12),
              const Text('Обновить геолокацию?'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Магазин: ${shop.name}', style: const TextStyle(fontWeight: FontWeight.w500)),
                    const SizedBox(height: 8),
                    const Divider(height: 1),
                    const SizedBox(height: 8),
                    const Text('Новые координаты:', style: TextStyle(color: Colors.blue, fontWeight: FontWeight.w500)),
                    Text('Широта: ${position.latitude.toStringAsFixed(6)}'),
                    Text('Долгота: ${position.longitude.toStringAsFixed(6)}'),
                  ],
                ),
              ),
              if (shop.latitude != null && shop.longitude != null) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.orange.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
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
                gradient: const LinearGradient(colors: [Colors.blue, Color(0xFF1E88E5)]),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () => Navigator.pop(ctx, true),
                  borderRadius: BorderRadius.circular(12),
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 20, vertical: 12),
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
                    const Icon(Icons.check_circle_rounded, color: Colors.white),
                    const SizedBox(width: 12),
                    const Text('Геолокация магазина обновлена'),
                  ],
                ),
                backgroundColor: Colors.green,
                behavior: SnackBarBehavior.floating,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                margin: const EdgeInsets.all(16),
              ),
            );
            await _loadShops();
          } else {
            Logger.error('🗺️ ShopService.updateShop вернул null');
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Row(
                  children: [
                    const Icon(Icons.error_rounded, color: Colors.white),
                    const SizedBox(width: 12),
                    const Text('Ошибка обновления геолокации'),
                  ],
                ),
                backgroundColor: Colors.red,
                behavior: SnackBarBehavior.floating,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                margin: const EdgeInsets.all(16),
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
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            margin: const EdgeInsets.all(16),
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
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withOpacity(0.05),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 20),
              const SizedBox(width: 8),
              Text(
                title,
                style: TextStyle(fontWeight: FontWeight.w600, color: color),
              ),
            ],
          ),
          const SizedBox(height: 12),
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
                      initialTime: startTime ?? const TimeOfDay(hour: 8, minute: 0),
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
                padding: const EdgeInsets.symmetric(horizontal: 10),
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
                      initialTime: endTime ?? const TimeOfDay(hour: 18, minute: 0),
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
          const SizedBox(height: 12),
          TextField(
            controller: abbreviationController,
            decoration: InputDecoration(
              labelText: 'Аббревиатура',
              hintText: 'Например: Ост(У)',
              labelStyle: TextStyle(color: color),
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: color.withOpacity(0.3)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: color.withOpacity(0.3)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: color, width: 2),
              ),
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTimePickerButton(BuildContext context, TimeOfDay? time, Color color, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              time != null
                  ? '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}'
                  : 'Не задано',
              style: TextStyle(
                color: time != null ? Colors.black87 : Colors.grey,
                fontWeight: time != null ? FontWeight.w500 : FontWeight.normal,
              ),
            ),
            Icon(Icons.access_time_rounded, size: 20, color: color),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF004D40),
      appBar: AppBar(
        title: const Text(
          'Управление магазинами',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
        backgroundColor: const Color(0xFF004D40),
        elevation: 0,
        actions: [
          Container(
            margin: const EdgeInsets.only(right: 8),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: IconButton(
              icon: const Icon(Icons.refresh_rounded),
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
              const Color(0xFF004D40),
              const Color(0xFF00695C),
              const Color(0xFF00796B),
            ],
          ),
        ),
        child: Column(
          children: [
            // Поиск
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.15),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
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
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
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
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: const CircularProgressIndicator(
              color: Colors.white,
              strokeWidth: 3,
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'Загрузка магазинов...',
            style: TextStyle(
              color: Colors.white.withOpacity(0.9),
              fontSize: 16,
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
            padding: const EdgeInsets.all(32),
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
          const SizedBox(height: 24),
          const Text(
            'Магазины не найдены',
            style: TextStyle(
              fontSize: 22,
              color: Colors.white,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Попробуйте изменить поисковый запрос',
            style: TextStyle(
              fontSize: 16,
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
      color: const Color(0xFF004D40),
      backgroundColor: Colors.white,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        itemCount: filteredShops.length,
        itemBuilder: (context, index) {
          final shop = filteredShops[index];
          return AnimatedBuilder(
            animation: _animationController,
            builder: (context, child) {
              final delay = index * 0.1;
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
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.15),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          onTap: () => _editShopSettings(shop),
          borderRadius: BorderRadius.circular(20),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                // Иконка магазина
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF004D40).withOpacity(0.3),
                        blurRadius: 8,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: const ShopIcon(size: 64),
                ),
                const SizedBox(width: 16),
                // Информация о магазине
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        shop.name,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                          color: Color(0xFF1A1A1A),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        shop.address,
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey[600],
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 10),
                      // Статусы
                      Row(
                        children: [
                          _buildStatusBadge(
                            hasSettings ? 'Настроен' : 'Не настроен',
                            hasSettings ? Colors.green : Colors.orange,
                            hasSettings ? Icons.check_circle_rounded : Icons.warning_rounded,
                          ),
                          const SizedBox(width: 8),
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
                // Кнопка редактирования
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF004D40).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(
                    Icons.edit_rounded,
                    color: Color(0xFF004D40),
                    size: 22,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStatusBadge(String text, Color color, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 14),
          const SizedBox(width: 4),
          Text(
            text,
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
