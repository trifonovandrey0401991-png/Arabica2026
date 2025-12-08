import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'rko_service.dart';
import 'shop_model.dart';
import 'shop_settings_model.dart';
import 'rko_pdf_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
      // Получаем имя сотрудника
      final name = await RKOService.getEmployeeName();
      
      // Получаем магазин из последней пересменки
      if (name != null) {
        final shop = await RKOService.getShopFromLastShift(name);
        if (shop != null) {
          _selectedShop = shop;
        }
      }

      // Загружаем список всех магазинов для выбора
      final shops = await Shop.loadShopsFromGoogleSheets();
      
      setState(() {
        _employeeName = name;
        _shops = shops;
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

      // Генерируем PDF
      final pdfFile = await RKOPDFService.generateRKO(
        shopAddress: _selectedShop!.address,
        shopSettings: shopSettings,
        documentNumber: documentNumber,
        employeeData: employeeData,
        amount: amount,
        rkoType: widget.rkoType,
      );

      // Обновляем номер документа на сервере
      await RKOService.updateDocumentNumber(_selectedShop!.address, documentNumber);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('РКО успешно создан: ${pdfFile.path}'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 3),
          ),
        );
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
                            value: _selectedShop,
                            decoration: const InputDecoration(
                              border: OutlineInputBorder(),
                              labelText: 'Выберите магазин',
                            ),
                            items: _shops.map((shop) {
                              return DropdownMenuItem<Shop>(
                                value: shop,
                                child: Text(shop.name),
                              );
                            }).toList(),
                            onChanged: (shop) {
                              setState(() {
                                _selectedShop = shop;
                              });
                            },
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

