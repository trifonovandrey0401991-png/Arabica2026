import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/rko_service.dart';
import '../../shops/models/shop_model.dart';
import '../../shops/models/shop_settings_model.dart';
import '../services/rko_pdf_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../employees/pages/employees_page.dart';
import '../../kpi/services/kpi_service.dart';
import '../../../core/utils/logger.dart';

/// Страница ввода суммы и создания РКО
class RKOAmountInputPage extends StatefulWidget {
  final String rkoType;

  const RKOAmountInputPage({
    super.key,
    required this.rkoType,
  });

  @override
  State<RKOAmountInputPage> createState() => _RKOAmountInputPageState();
}

class _RKOAmountInputPageState extends State<RKOAmountInputPage> {
  final _amountController = TextEditingController();
  Shop? _selectedShop;
  List<Shop> _shops = [];
  bool _isLoading = true;
  bool _isCreating = false;
  String? _employeeName;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    setState(() {
      _isLoading = true;
    });

    try {
      // Получаем имя сотрудника из сервер (для совместимости с поиском)
      final employees = await EmployeesPage.loadEmployeesForNotifications();
      final prefs = await SharedPreferences.getInstance();
      final phone = prefs.getString('userPhone') ?? prefs.getString('user_phone');
      
      if (phone != null && employees.isNotEmpty) {
        // Нормализуем телефон для поиска
        final normalizedPhone = phone.replaceAll(RegExp(r'[\s\+]'), '');
        // Ищем сотрудника по телефону
        final currentEmployee = employees.firstWhere(
          (e) => e.phone != null && e.phone!.replaceAll(RegExp(r'[\s\+]'), '') == normalizedPhone,
          orElse: () => employees.first,
        );
        _employeeName = currentEmployee.name;
        
        // Получаем магазин из последней пересменки
        final shop = await RKOService.getShopFromLastShift(_employeeName!);
        if (shop != null) {
          _selectedShop = shop;
        }
      } else {
        // Fallback: получаем имя из меню "Сотрудники" (единый источник истины)
        final name = await EmployeesPage.getCurrentEmployeeName();
        _employeeName = name;
        if (name != null) {
          final shop = await RKOService.getShopFromLastShift(name);
          if (shop != null) {
            _selectedShop = shop;
          }
        }
      }

      // Загружаем список всех магазинов для выбора
      final shops = await Shop.loadShopsFromGoogleSheets();
      
      // Если был выбран магазин из последней пересменки, находим его в списке по адресу
      Shop? selectedShopFromList;
      if (_selectedShop != null) {
        selectedShopFromList = shops.firstWhere(
          (shop) => shop.address == _selectedShop!.address,
          orElse: () => shops.isNotEmpty ? shops.first : _selectedShop!,
        );
      }
      
      setState(() {
        _shops = shops;
        _selectedShop = selectedShopFromList ?? (shops.isNotEmpty ? shops.first : null);
        _isLoading = false;
      });
    } catch (e) {
      print('Ошибка инициализации: $e');
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _createRKO() async {
    if (_amountController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Введите сумму'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    final amount = double.tryParse(_amountController.text.replaceAll(',', '.'));
    if (amount == null || amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Введите корректную сумму'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    if (_selectedShop == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Выберите магазин'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() {
      _isCreating = true;
    });

    try {
      // Получаем настройки магазина
      final shopSettings = await RKOService.getShopSettings(_selectedShop!.address);
      if (shopSettings == null || 
          shopSettings.address.isEmpty || 
          shopSettings.inn.isEmpty || 
          shopSettings.directorName.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Настройки магазина не заполнены. Заполните их в меню "Сотрудники" -> "Магазины"'),
              backgroundColor: Colors.orange,
              duration: Duration(seconds: 5),
            ),
          );
        }
        setState(() {
          _isCreating = false;
        });
        return;
      }

      // Получаем данные сотрудника
      final employeeData = await RKOService.getEmployeeData();
      if (employeeData == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Данные сотрудника не найдены. Пройдите регистрацию'),
              backgroundColor: Colors.red,
            ),
          );
        }
        setState(() {
          _isCreating = false;
        });
        return;
      }

      // Получаем следующий номер документа
      final documentNumber = await RKOService.getNextDocumentNumber(_selectedShop!.address);

      // Генерируем PDF через reportlab
      final pdfFile = await RKOPDFService.generateRKOFromDocx(
        shopAddress: _selectedShop!.address,
        shopSettings: shopSettings,
        documentNumber: documentNumber,
        employeeData: employeeData,
        amount: amount,
        rkoType: widget.rkoType,
      );

      // Получаем имя файла
      final fileName = pdfFile.path.split('/').last;
      final now = DateTime.now();
      
      // Загружаем на сервер
      // ВАЖНО: Используем то же имя, которое используется в системе для отметок прихода и пересменок
      // Это имя из SharedPreferences или регистрации, а НЕ из сервер
      // сервер может содержать другое имя (например, "andrey tifonov vladimir"),
      // а в системе сотрудник называется "Андрей В"
      String employeeNameForRKO;
      
      // ВАЖНО: Используем единый источник истины - меню "Сотрудники"
      // Это гарантирует, что имя будет совпадать с отображением в системе
      final systemEmployeeName = await EmployeesPage.getCurrentEmployeeName();
      if (systemEmployeeName != null && systemEmployeeName.isNotEmpty) {
        // Используем имя из меню "Сотрудники" (то же, что используется везде в системе)
        employeeNameForRKO = systemEmployeeName.trim().replaceAll(RegExp(r'\s+'), ' ');
        Logger.debug('📤 Используем имя из меню "Сотрудники": "$employeeNameForRKO"');
      } else if (_employeeName != null && _employeeName!.isNotEmpty) {
        // Fallback: используем имя из сервер, только убираем лишние пробелы
        employeeNameForRKO = _employeeName!.trim().replaceAll(RegExp(r'\s+'), ' ');
        Logger.debug('📤 Fallback: используем имя из сервер: "$employeeNameForRKO"');
      } else {
        // Последний fallback: используем имя из регистрации
        employeeNameForRKO = employeeData.fullName.trim().replaceAll(RegExp(r'\s+'), ' ');
        Logger.debug('📤 Fallback: используем имя из регистрации: "$employeeNameForRKO"');
      }
      Logger.debug('📤 Оригинальное имя из регистрации: "${employeeData.fullName}"');
      Logger.debug('📤 Имя из сервер: "$_employeeName"');
      Logger.debug('📤 Итоговое имя для РКО: "$employeeNameForRKO"');
      final uploadSuccess = await RKOPDFService.uploadRKOToServer(
        pdfFile: pdfFile,
        fileName: fileName,
        employeeName: employeeNameForRKO,
        shopAddress: _selectedShop!.address,
        date: now,
        amount: amount,
        rkoType: widget.rkoType,
      );

      // Обновляем номер документа на сервере
      await RKOService.updateDocumentNumber(_selectedShop!.address, documentNumber);

      if (mounted) {
        if (uploadSuccess) {
          // Очищаем кэш KPI для этого магазина и даты, чтобы новые РКО отображались сразу
          KPIService.clearCacheForDate(_selectedShop!.address, now);
          // Также очищаем кэш для всего магазина на случай, если нужно обновить другие даты
          KPIService.clearCacheForShop(_selectedShop!.address);
          
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('РКО успешно создан и загружен на сервер'),
              backgroundColor: Colors.green,
              duration: Duration(seconds: 3),
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('РКО создан локально: ${pdfFile.path}, но не удалось загрузить на сервер'),
              backgroundColor: Colors.orange,
              duration: const Duration(seconds: 5),
            ),
          );
        }
        Navigator.pop(context);
      }
    } catch (e) {
      print('Ошибка создания РКО: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка создания РКО: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isCreating = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('РКО: ${widget.rkoType}'),
        backgroundColor: const Color(0xFF004D40),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Выбор магазина
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Магазин',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 8),
                          DropdownButtonFormField<Shop>(
                            value: _selectedShop != null && _shops.any((s) => s.address == _selectedShop!.address)
                                ? _shops.firstWhere((s) => s.address == _selectedShop!.address)
                                : null,
                            decoration: const InputDecoration(
                              border: OutlineInputBorder(),
                              labelText: 'Выберите магазин',
                            ),
                            items: _shops.map((shop) {
                              return DropdownMenuItem<Shop>(
                                value: shop,
                                child: Text(
                                  shop.name,
                                  overflow: TextOverflow.ellipsis,
                                  maxLines: 2,
                                ),
                              );
                            }).toList(),
                            onChanged: (shop) {
                              setState(() {
                                _selectedShop = shop;
                              });
                            },
                            isExpanded: true,
                          ),
                          if (_selectedShop != null) ...[
                            const SizedBox(height: 8),
                            Text(
                              'Адрес: ${_selectedShop!.address}',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey[600],
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  // Ввод суммы
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Сумма',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 8),
                          TextField(
                            controller: _amountController,
                            decoration: const InputDecoration(
                              border: OutlineInputBorder(),
                              labelText: 'Введите сумму',
                              hintText: 'Например: 1000',
                              prefixText: '₽ ',
                            ),
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            inputFormatters: [
                              FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}')),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  // Кнопка создания
                  ElevatedButton(
                    onPressed: _isCreating ? null : _createRKO,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF004D40),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                    child: _isCreating
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                            ),
                          )
                        : const Text(
                            'Создать РКО',
                            style: TextStyle(fontSize: 18),
                          ),
                  ),
                ],
              ),
            ),
    );
  }
}

