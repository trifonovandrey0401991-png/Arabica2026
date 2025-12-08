import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'shop_model.dart';
import 'shop_settings_model.dart';

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
      final shops = await Shop.loadShopsFromGoogleSheets();
      
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
      final response = await http.post(
        Uri.parse(url),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(settings.toJson()),
      ).timeout(
        const Duration(seconds: 10),
      );

      if (response.statusCode == 200) {
        final result = jsonDecode(response.body);
        return result['success'] == true;
      }
      return false;
    } catch (e) {
      print('Ошибка сохранения настроек магазина: $e');
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

    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Настройки магазина: ${shop.name}'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
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
              });
            },
            child: const Text('Сохранить'),
          ),
        ],
      ),
    );

    if (result != null) {
      final settings = ShopSettings(
        shopAddress: shop.address,
        address: result['address'] ?? shop.address,
        inn: result['inn'] ?? '',
        directorName: result['directorName'] ?? '',
        lastDocumentNumber: currentSettings?.lastDocumentNumber ?? 0,
      );

      final success = await _saveShopSettings(settings);
      
      if (mounted) {
        if (success) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Настройки успешно сохранены'),
              backgroundColor: Colors.green,
            ),
          );
          await _loadShops();
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Ошибка сохранения настроек'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
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

