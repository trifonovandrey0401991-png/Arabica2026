import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../../features/work_schedule/models/work_schedule_model.dart';
import '../../features/shops/models/shop_model.dart';
import '../../features/shops/models/shop_settings_model.dart';

class AbbreviationSelectionDialog extends StatefulWidget {
  final String employeeId;
  final String employeeName;
  final DateTime date;
  final WorkScheduleEntry? existingEntry;
  final List<Shop> shops;

  const AbbreviationSelectionDialog({
    super.key,
    required this.employeeId,
    required this.employeeName,
    required this.date,
    this.existingEntry,
    required this.shops,
  });

  @override
  State<AbbreviationSelectionDialog> createState() => _AbbreviationSelectionDialogState();
}

class _AbbreviationSelectionDialogState extends State<AbbreviationSelectionDialog> {
  List<ShopAbbreviation> _abbreviations = [];
  bool _isLoading = true;
  String? _selectedAbbreviation;

  @override
  void initState() {
    super.initState();
    print('🔵 AbbreviationSelectionDialog инициализирован');
    print('   Сотрудник: ${widget.employeeName}');
    print('   Дата: ${widget.date.day}.${widget.date.month}.${widget.date.year}');
    print('   Магазинов: ${widget.shops.length}');
    _loadAbbreviations();
    if (widget.existingEntry != null) {
      // Пытаемся найти аббревиатуру для существующей записи
      _selectedAbbreviation = _findAbbreviationForEntry(widget.existingEntry!);
    }
  }

  Future<void> _loadAbbreviations() async {
    print('📥 Начинаем загрузку аббревиатур...');
    setState(() {
      _isLoading = true;
    });

    try {
      final List<ShopAbbreviation> abbreviations = [];
      
      // Загружаем настройки для каждого магазина
      for (var shop in widget.shops) {
        try {
          final url = 'https://arabica26.ru/api/shop-settings/${Uri.encodeComponent(shop.address)}';
          print('   Загрузка настроек для: ${shop.name}');
          final response = await http.get(Uri.parse(url)).timeout(
            const Duration(seconds: 5),
          );

          if (response.statusCode == 200) {
            final result = jsonDecode(response.body);
            if (result['success'] == true && result['settings'] != null) {
              final settings = ShopSettings.fromJson(result['settings']);
              
              // Добавляем аббревиатуры для каждой смены
              if (settings.morningAbbreviation != null && settings.morningAbbreviation!.isNotEmpty) {
                abbreviations.add(ShopAbbreviation(
                  abbreviation: settings.morningAbbreviation!,
                  shopAddress: shop.address,
                  shopName: shop.name,
                  shiftType: ShiftType.morning,
                ));
                print('     ✅ Добавлена аббревиатура: ${settings.morningAbbreviation} (утро)');
              }
              if (settings.dayAbbreviation != null && settings.dayAbbreviation!.isNotEmpty) {
                abbreviations.add(ShopAbbreviation(
                  abbreviation: settings.dayAbbreviation!,
                  shopAddress: shop.address,
                  shopName: shop.name,
                  shiftType: ShiftType.day,
                ));
                print('     ✅ Добавлена аббревиатура: ${settings.dayAbbreviation} (день)');
              }
              if (settings.nightAbbreviation != null && settings.nightAbbreviation!.isNotEmpty) {
                abbreviations.add(ShopAbbreviation(
                  abbreviation: settings.nightAbbreviation!,
                  shopAddress: shop.address,
                  shopName: shop.name,
                  shiftType: ShiftType.evening, // night = evening
                ));
                print('     ✅ Добавлена аббревиатура: ${settings.nightAbbreviation} (ночь)');
              }
            }
          } else {
            print('     ⚠️ Статус ответа: ${response.statusCode}');
          }
        } catch (e) {
          print('     ❌ Ошибка загрузки настроек для магазина ${shop.address}: $e');
        }
      }

      // Сортируем по аббревиатуре
      abbreviations.sort((a, b) => a.abbreviation.compareTo(b.abbreviation));

      print('✅ Загружено аббревиатур: ${abbreviations.length}');
      if (mounted) {
        setState(() {
          _abbreviations = abbreviations;
          _isLoading = false;
        });
      }
    } catch (e) {
      print('❌ Ошибка загрузки аббревиатур: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  String? _findAbbreviationForEntry(WorkScheduleEntry entry) {
    // Пытаемся найти аббревиатуру для существующей записи
    for (var abbrev in _abbreviations) {
      if (abbrev.shopAddress == entry.shopAddress && abbrev.shiftType == entry.shiftType) {
        return abbrev.abbreviation;
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Выбор смены: ${widget.employeeName}'),
      content: SizedBox(
        width: MediaQuery.of(context).size.width * 0.8,
        height: MediaQuery.of(context).size.height * 0.6,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Дата: ${_formatDate(widget.date)}',
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            if (_isLoading)
              const Center(child: CircularProgressIndicator())
            else if (_abbreviations.isEmpty)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(16.0),
                  child: Text(
                    'Аббревиатуры не найдены. Убедитесь, что они заполнены в настройках магазинов.',
                    textAlign: TextAlign.center,
                  ),
                ),
              )
            else
              Expanded(
                child: ListView.builder(
                  itemCount: _abbreviations.length,
                  itemBuilder: (context, index) {
                    final abbrev = _abbreviations[index];
                    final isSelected = _selectedAbbreviation == abbrev.abbreviation;
                    
                    return RadioListTile<String>(
                      title: Text(abbrev.abbreviation),
                      subtitle: Text('${abbrev.shopName} - ${abbrev.shiftType.label}'),
                      value: abbrev.abbreviation,
                      groupValue: _selectedAbbreviation,
                      onChanged: (value) {
                        setState(() {
                          _selectedAbbreviation = value;
                        });
                      },
                      selected: isSelected,
                    );
                  },
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Отмена'),
        ),
        if (widget.existingEntry != null)
          TextButton(
            onPressed: () {
              Navigator.of(context).pop({
                'action': 'delete',
                'entry': widget.existingEntry,
              });
            },
            child: const Text('Удалить', style: TextStyle(color: Colors.red)),
          ),
        ElevatedButton(
          onPressed: _selectedAbbreviation == null ? null : _save,
          child: const Text('Сохранить'),
        ),
      ],
    );
  }

  String _formatDate(DateTime date) {
    return '${date.day.toString().padLeft(2, '0')}.${date.month.toString().padLeft(2, '0')}.${date.year}';
  }

  void _save() {
    if (_selectedAbbreviation == null) {
      print('❌ Аббревиатура не выбрана');
      return;
    }

    // Валидация employeeId
    if (widget.employeeId.isEmpty) {
      print('❌ Ошибка: employeeId пустой');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Ошибка: не указан сотрудник'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    // Валидация employeeName
    if (widget.employeeName.isEmpty) {
      print('❌ Ошибка: employeeName пустой');
    }

    print('💾 Сохранение смены:');
    print('   employeeId: ${widget.employeeId}');
    print('   employeeName: ${widget.employeeName}');
    print('   date: ${widget.date.day}.${widget.date.month}.${widget.date.year}');
    print('   selectedAbbreviation: $_selectedAbbreviation');

    // Находим выбранную аббревиатуру
    final selectedAbbrev = _abbreviations.firstWhere(
      (a) => a.abbreviation == _selectedAbbreviation,
    );

    print('   shopAddress: ${selectedAbbrev.shopAddress}');
    print('   shiftType: ${selectedAbbrev.shiftType.name}');

    // Создаем запись
    final entry = WorkScheduleEntry(
      id: widget.existingEntry?.id ?? '',
      employeeId: widget.employeeId,
      employeeName: widget.employeeName,
      shopAddress: selectedAbbrev.shopAddress,
      date: widget.date,
      shiftType: selectedAbbrev.shiftType,
    );

    // Дополнительная валидация созданной записи
    if (entry.employeeId.isEmpty) {
      print('❌ КРИТИЧЕСКАЯ ОШИБКА: employeeId пустой в созданной записи!');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Ошибка: не удалось создать запись'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    print('✅ Запись создана успешно:');
    print('   ID: ${entry.id}');
    print('   employeeId: ${entry.employeeId}');
    print('   employeeName: ${entry.employeeName}');
    print('   shopAddress: ${entry.shopAddress}');
    print('   date: ${entry.date}');
    print('   shiftType: ${entry.shiftType.name}');

    Navigator.of(context).pop({
      'action': 'save',
      'entry': entry,
    });
  }
}

// Вспомогательный класс для хранения информации об аббревиатуре
class ShopAbbreviation {
  final String abbreviation;
  final String shopAddress;
  final String shopName;
  final ShiftType shiftType;

  ShopAbbreviation({
    required this.abbreviation,
    required this.shopAddress,
    required this.shopName,
    required this.shiftType,
  });
}

