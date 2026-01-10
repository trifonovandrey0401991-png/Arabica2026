import 'package:flutter/material.dart';
import '../../features/work_schedule/models/work_schedule_model.dart';
import '../../features/shops/models/shop_model.dart';
import '../../features/shops/services/shop_service.dart';
import '../../core/utils/logger.dart';

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
    Logger.debug('AbbreviationSelectionDialog инициализирован');
    Logger.debug('   Сотрудник: ${widget.employeeName}');
    Logger.debug('   Дата: ${widget.date.day}.${widget.date.month}.${widget.date.year}');
    Logger.debug('   Магазинов: ${widget.shops.length}');
    _loadAbbreviations();
    if (widget.existingEntry != null) {
      // Пытаемся найти аббревиатуру для существующей записи
      _selectedAbbreviation = _findAbbreviationForEntry(widget.existingEntry!);
    }
  }

  Future<void> _loadAbbreviations() async {
    Logger.debug('Начинаем загрузку аббревиатур...');
    setState(() {
      _isLoading = true;
    });

    try {
      final List<ShopAbbreviation> abbreviations = [];
      
      // Загружаем настройки для каждого магазина через ShopService
      for (var shop in widget.shops) {
        try {
          Logger.debug('   Загрузка настроек для: ${shop.name}');
          final settings = await ShopService.getShopSettings(shop.address);

          if (settings != null) {
            // Добавляем аббревиатуры для каждой смены
            if (settings.morningAbbreviation != null && settings.morningAbbreviation!.isNotEmpty) {
              String? morningTimeRange;
              if (settings.morningShiftStart != null && settings.morningShiftEnd != null) {
                morningTimeRange = '${_formatTime(settings.morningShiftStart!)}-${_formatTime(settings.morningShiftEnd!)}';
              }
              abbreviations.add(ShopAbbreviation(
                abbreviation: settings.morningAbbreviation!,
                shopAddress: shop.address,
                shopName: shop.name,
                shiftType: ShiftType.morning,
                timeRange: morningTimeRange,
              ));
              Logger.debug('     Добавлена аббревиатура: ${settings.morningAbbreviation} (утро, ${morningTimeRange ?? 'дефолт'})');
            }
            if (settings.dayAbbreviation != null && settings.dayAbbreviation!.isNotEmpty) {
              String? dayTimeRange;
              if (settings.dayShiftStart != null && settings.dayShiftEnd != null) {
                dayTimeRange = '${_formatTime(settings.dayShiftStart!)}-${_formatTime(settings.dayShiftEnd!)}';
              }
              abbreviations.add(ShopAbbreviation(
                abbreviation: settings.dayAbbreviation!,
                shopAddress: shop.address,
                shopName: shop.name,
                shiftType: ShiftType.day,
                timeRange: dayTimeRange,
              ));
              Logger.debug('     Добавлена аббревиатура: ${settings.dayAbbreviation} (день, ${dayTimeRange ?? 'дефолт'})');
            }
            if (settings.nightAbbreviation != null && settings.nightAbbreviation!.isNotEmpty) {
              String? nightTimeRange;
              if (settings.nightShiftStart != null && settings.nightShiftEnd != null) {
                nightTimeRange = '${_formatTime(settings.nightShiftStart!)}-${_formatTime(settings.nightShiftEnd!)}';
              }
              abbreviations.add(ShopAbbreviation(
                abbreviation: settings.nightAbbreviation!,
                shopAddress: shop.address,
                shopName: shop.name,
                shiftType: ShiftType.evening, // night = evening
                timeRange: nightTimeRange,
              ));
              Logger.debug('     Добавлена аббревиатура: ${settings.nightAbbreviation} (ночь, ${nightTimeRange ?? 'дефолт'})');
            }
          }
        } catch (e) {
          Logger.error('Ошибка загрузки настроек для магазина ${shop.address}', e);
        }
      }

      // Сортируем по аббревиатуре
      abbreviations.sort((a, b) => a.abbreviation.compareTo(b.abbreviation));

      Logger.success('Загружено аббревиатур: ${abbreviations.length}');
      if (mounted) {
        setState(() {
          _abbreviations = abbreviations;
          _isLoading = false;
        });
      }
    } catch (e) {
      Logger.error('Ошибка загрузки аббревиатур', e);
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
                      subtitle: Text('${abbrev.shopName} - ${abbrev.shiftType.label} (${abbrev.displayTimeRange})'),
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

  String _formatTime(TimeOfDay time) {
    return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
  }

  void _save() {
    if (_selectedAbbreviation == null) {
      Logger.warning('Аббревиатура не выбрана');
      return;
    }

    // Валидация employeeId
    if (widget.employeeId.isEmpty) {
      Logger.error('Ошибка: employeeId пустой');
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
      Logger.warning('employeeName пустой');
    }

    Logger.debug('Сохранение смены:');
    Logger.debug('   employeeId: ${widget.employeeId}');
    Logger.debug('   employeeName: ${widget.employeeName}');
    Logger.debug('   date: ${widget.date.day}.${widget.date.month}.${widget.date.year}');
    Logger.debug('   selectedAbbreviation: $_selectedAbbreviation');

    // Находим выбранную аббревиатуру
    final selectedAbbrev = _abbreviations.firstWhere(
      (a) => a.abbreviation == _selectedAbbreviation,
    );

    Logger.debug('   shopAddress: ${selectedAbbrev.shopAddress}');
    Logger.debug('   shiftType: ${selectedAbbrev.shiftType.name}');

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
      Logger.error('КРИТИЧЕСКАЯ ОШИБКА: employeeId пустой в созданной записи!');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Ошибка: не удалось создать запись'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    Logger.success('Запись создана успешно:');
    Logger.debug('   ID: ${entry.id}');
    Logger.debug('   employeeId: ${entry.employeeId}');
    Logger.debug('   employeeName: ${entry.employeeName}');
    Logger.debug('   shopAddress: ${entry.shopAddress}');
    Logger.debug('   date: ${entry.date}');
    Logger.debug('   shiftType: ${entry.shiftType.name}');

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
  final String? timeRange; // Время смены из настроек магазина

  ShopAbbreviation({
    required this.abbreviation,
    required this.shopAddress,
    required this.shopName,
    required this.shiftType,
    this.timeRange,
  });

  /// Получить отображаемое время смены (из настроек или дефолт)
  String get displayTimeRange => timeRange ?? shiftType.timeRange;
}

