import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'shop_model.dart';
import 'shop_settings_model.dart';
import 'shop_service.dart';

/// Страница управления магазинами для РКО
class ShopsManagementPage extends StatefulWidget {
  const ShopsManagementPage({super.key});

  @override
  State<ShopsManagementPage> createState() => _ShopsManagementPageState();
}

class _ShopsManagementPageState extends State<ShopsManagementPage> {
  List<Shop> _shops = [];
  Map<String, ShopSettings?> _settings = {};
  bool _isLoading = true;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _loadShops();
  }

  Future<void> _loadShops() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final shops = await ShopService.getShops();
      
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
    } catch (e) {
      print('Ошибка загрузки магазинов: $e');
      setState(() {
        _isLoading = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка загрузки магазинов: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<ShopSettings?> _loadShopSettings(String shopAddress) async {
    try {
      final url = 'https://arabica26.ru/api/shop-settings/${Uri.encodeComponent(shopAddress)}';
      final response = await http.get(Uri.parse(url)).timeout(
        const Duration(seconds: 10),
      );

      if (response.statusCode == 200) {
        final result = jsonDecode(response.body);
        if (result['success'] == true && result['settings'] != null) {
          return ShopSettings.fromJson(result['settings']);
        }
      }
      return null;
    } catch (e) {
      print('Ошибка загрузки настроек магазина: $e');
      return null;
    }
  }

  Future<bool> _saveShopSettings(ShopSettings settings) async {
    try {
      final url = 'https://arabica26.ru/api/shop-settings';
      print('💾 Сохранение настроек магазина: ${settings.shopAddress}');
      print('   URL: $url');
      print('   Данные: ${jsonEncode(settings.toJson())}');
      
      final uri = Uri.parse(url);
      print('   Parsed URI: $uri');
      print('   Host: ${uri.host}, Path: ${uri.path}');
      
      final requestBody = jsonEncode(settings.toJson());
      print('   Request body length: ${requestBody.length}');
      
      final response = await http.post(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: requestBody,
      ).timeout(
        const Duration(seconds: 10),
      );

      print('   Статус ответа: ${response.statusCode}');
      print('   Headers: ${response.headers}');
      print('   Тело ответа (первые 500 символов): ${response.body.length > 500 ? response.body.substring(0, 500) : response.body}');

      if (response.statusCode == 200) {
        try {
          final result = jsonDecode(response.body);
          final success = result['success'] == true;
          if (success) {
            print('   ✅ Настройки успешно сохранены');
          } else {
            print('   ❌ Ошибка: ${result['error'] ?? 'Неизвестная ошибка'}');
          }
          return success;
        } catch (e) {
          print('   ❌ Ошибка парсинга JSON: $e');
          print('   Тело ответа: ${response.body}');
          return false;
        }
      } else {
        print('   ❌ HTTP ошибка: ${response.statusCode}');
        print('   Тело ответа: ${response.body}');
        return false;
      }
    } catch (e, stackTrace) {
      print('❌ Ошибка сохранения настроек магазина: $e');
      print('   Stack trace: $stackTrace');
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
          title: Text('Настройки магазина: ${shop.name}'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Основные настройки
                const Text(
                  'Основные данные',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: addressController,
                  decoration: const InputDecoration(
                    labelText: 'Фактический адрес для РКО',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: innController,
                  decoration: const InputDecoration(
                    labelText: 'ИНН',
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.number,
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: directorController,
                  decoration: const InputDecoration(
                    labelText: 'Руководитель организации',
                    hintText: 'Например: ИП Горовой Р. В.',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 24),
                // Интервалы времени для смен
                const Text(
                  'Интервалы времени для отметки',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Если интервал не заполнен, смена не учитывается',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
                const SizedBox(height: 16),
                // Утренняя смена
                _buildShiftTimeSection(
                  context,
                  'Утренняя смена',
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
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Отмена'),
            ),
            ElevatedButton(
              onPressed: () {
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
              child: const Text('Сохранить'),
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
              const SnackBar(
                content: Text('Настройки успешно сохранены'),
                backgroundColor: Colors.green,
                duration: Duration(seconds: 2),
              ),
            );
            await _loadShops();
          } else {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Ошибка сохранения настроек. Проверьте логи и убедитесь, что сервер работает.'),
                backgroundColor: Colors.red,
                duration: Duration(seconds: 4),
              ),
            );
          }
        }
      } catch (e, stackTrace) {
        print('❌ Критическая ошибка при сохранении настроек: $e');
        print('   Stack trace: $stackTrace');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Ошибка: $e'),
              backgroundColor: Colors.red,
              duration: const Duration(seconds: 4),
            ),
          );
        }
      }
    }
  }

  Widget _buildShiftTimeSection(
    BuildContext context,
    String title,
    TimeOfDay? startTime,
    TimeOfDay? endTime,
    Function(TimeOfDay?, TimeOfDay?) onChanged,
    TextEditingController abbreviationController,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.w500),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: InkWell(
                onTap: () async {
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
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        startTime != null
                            ? '${startTime.hour.toString().padLeft(2, '0')}:${startTime.minute.toString().padLeft(2, '0')}'
                            : 'Не задано',
                        style: TextStyle(
                          color: startTime != null ? Colors.black : Colors.grey,
                        ),
                      ),
                      const Icon(Icons.access_time, size: 20),
                    ],
                  ),
                ),
              ),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 8),
              child: Text('—'),
            ),
            Expanded(
              child: InkWell(
                onTap: () async {
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
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        endTime != null
                            ? '${endTime.hour.toString().padLeft(2, '0')}:${endTime.minute.toString().padLeft(2, '0')}'
                            : 'Не задано',
                        style: TextStyle(
                          color: endTime != null ? Colors.black : Colors.grey,
                        ),
                      ),
                      const Icon(Icons.access_time, size: 20),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        TextField(
          controller: abbreviationController,
          decoration: const InputDecoration(
            labelText: 'Аббревиатура для графика',
            hintText: 'Например: Ост(У)',
            border: OutlineInputBorder(),
            helperText: 'Используется в графике работы для быстрого выбора',
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Управление магазинами'),
        backgroundColor: const Color(0xFF004D40),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadShops,
            tooltip: 'Обновить',
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              decoration: InputDecoration(
                hintText: 'Поиск магазина...',
                prefixIcon: const Icon(Icons.search),
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
              onChanged: (value) {
                setState(() {
                  _searchQuery = value.trim().toLowerCase();
                });
              },
            ),
          ),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _shops.isEmpty
                    ? const Center(child: Text('Магазины не найдены'))
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        itemCount: _shops.length,
                        itemBuilder: (context, index) {
                          final shop = _shops[index];
                          
                          // Фильтрация по поисковому запросу
                          if (_searchQuery.isNotEmpty) {
                            final name = shop.name.toLowerCase();
                            final address = shop.address.toLowerCase();
                            if (!name.contains(_searchQuery) && 
                                !address.contains(_searchQuery)) {
                              return const SizedBox.shrink();
                            }
                          }

                          final settings = _settings[shop.address];
                          final hasSettings = settings != null && 
                              (settings.address.isNotEmpty || 
                               settings.inn.isNotEmpty || 
                               settings.directorName.isNotEmpty);

                          return Card(
                            margin: const EdgeInsets.symmetric(vertical: 4),
                            color: hasSettings 
                                ? Colors.green.shade50 
                                : Colors.orange.shade50,
                            child: ListTile(
                              leading: Icon(
                                shop.icon,
                                color: const Color(0xFF004D40),
                              ),
                              title: Text(
                                shop.name,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(shop.address),
                                  if (hasSettings) ...[
                                    const SizedBox(height: 4),
                                    if (settings!.address.isNotEmpty)
                                      Text(
                                        'Адрес РКО: ${settings.address}',
                                        style: const TextStyle(fontSize: 12),
                                      ),
                                    if (settings.inn.isNotEmpty)
                                      Text(
                                        'ИНН: ${settings.inn}',
                                        style: const TextStyle(fontSize: 12),
                                      ),
                                    if (settings.directorName.isNotEmpty)
                                      Text(
                                        'Руководитель: ${settings.directorName}',
                                        style: const TextStyle(fontSize: 12),
                                      ),
                                  ] else
                                    const Text(
                                      'Настройки не заполнены',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.orange,
                                      ),
                                    ),
                                ],
                              ),
                              trailing: IconButton(
                                icon: const Icon(Icons.edit),
                                onPressed: () => _editShopSettings(shop),
                                tooltip: 'Редактировать настройки',
                              ),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}

