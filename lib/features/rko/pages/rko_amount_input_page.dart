import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/rko_service.dart';
import '../../shops/models/shop_model.dart';
import '../services/rko_pdf_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../employees/pages/employees_page.dart';
import '../../kpi/services/kpi_service.dart';
import '../../../core/utils/logger.dart';
import '../../../core/services/report_notification_service.dart';

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
  static const _primaryColor = Color(0xFF004D40);
  static const _primaryColorLight = Color(0xFF00695C);

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
      Logger.error('Ошибка инициализации', e);
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
      // ВАЖНО: Приводим к нижнему регистру для совместимости с поиском в отчетах
      final systemEmployeeName = await EmployeesPage.getCurrentEmployeeName();
      if (systemEmployeeName != null && systemEmployeeName.isNotEmpty) {
        // Используем имя из меню "Сотрудники" (то же, что используется везде в системе)
        employeeNameForRKO = systemEmployeeName.toLowerCase().trim().replaceAll(RegExp(r'\s+'), ' ');
        Logger.debug('📤 Используем имя из меню "Сотрудники": "$employeeNameForRKO"');
      } else if (_employeeName != null && _employeeName!.isNotEmpty) {
        // Fallback: используем имя из сервер, только убираем лишние пробелы
        employeeNameForRKO = _employeeName!.toLowerCase().trim().replaceAll(RegExp(r'\s+'), ' ');
        Logger.debug('📤 Fallback: используем имя из сервер: "$employeeNameForRKO"');
      } else {
        // Последний fallback: используем имя из регистрации
        employeeNameForRKO = employeeData.fullName.toLowerCase().trim().replaceAll(RegExp(r'\s+'), ' ');
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

          // Отправляем уведомление администратору
          await ReportNotificationService.createNotification(
            reportType: ReportType.rko,
            reportId: 'rko_${now.millisecondsSinceEpoch}',
            employeeName: employeeNameForRKO,
            shopName: _selectedShop!.address,
            description: '${widget.rkoType}: ${amount.toStringAsFixed(0)} ₽',
          );

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
      Logger.error('Ошибка создания РКО', e);
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

  /// Иконка и цвет в зависимости от типа РКО
  IconData get _rkoTypeIcon {
    if (widget.rkoType.contains('месяц')) {
      return Icons.calendar_month_rounded;
    }
    return Icons.access_time_rounded;
  }

  Color get _rkoTypeColor {
    if (widget.rkoType.contains('месяц')) {
      return Colors.blue;
    }
    return Colors.orange;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('РКО: ${widget.rkoType}'),
        backgroundColor: _primaryColor,
        elevation: 0,
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              _primaryColor,
              _primaryColor.withOpacity(0.85),
            ],
          ),
        ),
        child: _isLoading
            ? Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircularProgressIndicator(
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Загрузка данных...',
                      style: TextStyle(color: Colors.white70, fontSize: 16),
                    ),
                  ],
                ),
              )
            : SafeArea(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Заголовок с типом РКО
                      _buildTypeHeader(),
                      const SizedBox(height: 24),

                      // Информация о сотруднике
                      if (_employeeName != null) ...[
                        _buildEmployeeCard(),
                        const SizedBox(height: 16),
                      ],

                      // Выбор магазина
                      _buildShopCard(),
                      const SizedBox(height: 16),

                      // Ввод суммы
                      _buildAmountCard(),
                      const SizedBox(height: 28),

                      // Кнопка создания
                      _buildCreateButton(),
                      const SizedBox(height: 16),

                      // Подсказка
                      _buildInfoTip(),
                    ],
                  ),
                ),
              ),
      ),
    );
  }

  /// Заголовок с типом РКО
  Widget _buildTypeHeader() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.15),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: _rkoTypeColor.withOpacity(0.2),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(
              _rkoTypeIcon,
              size: 32,
              color: Colors.white,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.rkoType,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  widget.rkoType.contains('месяц')
                      ? 'Месячная выплата заработной платы'
                      : 'Выплата за отработанную смену',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.white.withOpacity(0.8),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Карточка сотрудника
  Widget _buildEmployeeCard() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.15),
            blurRadius: 12,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: _primaryColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(
                Icons.person_rounded,
                color: _primaryColor,
                size: 26,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Сотрудник',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey[600],
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _employeeName!,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF2D2D2D),
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.check_circle_rounded,
              color: Colors.green[600],
              size: 24,
            ),
          ],
        ),
      ),
    );
  }

  /// Карточка выбора магазина
  Widget _buildShopCard() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.15),
            blurRadius: 12,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: _primaryColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    Icons.store_rounded,
                    color: _primaryColor,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                const Text(
                  'Магазин',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF2D2D2D),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Container(
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey[300]!),
                borderRadius: BorderRadius.circular(14),
              ),
              child: DropdownButtonFormField<Shop>(
                value: _selectedShop != null && _shops.any((s) => s.address == _selectedShop!.address)
                    ? _shops.firstWhere((s) => s.address == _selectedShop!.address)
                    : null,
                decoration: InputDecoration(
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  hintText: 'Выберите магазин',
                  hintStyle: TextStyle(color: Colors.grey[400]),
                ),
                dropdownColor: Colors.white,
                items: _shops.map((shop) {
                  return DropdownMenuItem<Shop>(
                    value: shop,
                    child: Text(
                      shop.name,
                      overflow: TextOverflow.ellipsis,
                      maxLines: 2,
                      style: const TextStyle(fontSize: 15),
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
            ),
            if (_selectedShop != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _primaryColor.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.location_on_rounded,
                      color: _primaryColor,
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _selectedShop!.address,
                        style: TextStyle(
                          fontSize: 13,
                          color: _primaryColor,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// Карточка ввода суммы
  Widget _buildAmountCard() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.15),
            blurRadius: 12,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: _rkoTypeColor.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    Icons.payments_rounded,
                    color: _rkoTypeColor,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                const Text(
                  'Сумма выплаты',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF2D2D2D),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _amountController,
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Color(0xFF2D2D2D),
              ),
              decoration: InputDecoration(
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(color: Colors.grey[300]!),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(color: _primaryColor, width: 2),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(color: Colors.grey[300]!),
                ),
                hintText: '0',
                hintStyle: TextStyle(
                  color: Colors.grey[400],
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
                suffixText: 'руб.',
                suffixStyle: TextStyle(
                  color: _primaryColor,
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
              ),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}')),
              ],
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            // Подсказка с быстрым вводом
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _buildQuickAmountButton(500),
                _buildQuickAmountButton(1000),
                _buildQuickAmountButton(1500),
                _buildQuickAmountButton(2000),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// Кнопка быстрого ввода суммы
  Widget _buildQuickAmountButton(int amount) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          _amountController.text = amount.toString();
        },
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            border: Border.all(color: _primaryColor.withOpacity(0.3)),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            '$amount',
            style: TextStyle(
              color: _primaryColor,
              fontWeight: FontWeight.w600,
              fontSize: 14,
            ),
          ),
        ),
      ),
    );
  }

  /// Кнопка создания РКО
  Widget _buildCreateButton() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 12,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: _isCreating ? null : _createRKO,
          borderRadius: BorderRadius.circular(18),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 18),
            child: _isCreating
                ? Center(
                    child: SizedBox(
                      height: 24,
                      width: 24,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        valueColor: AlwaysStoppedAnimation<Color>(_primaryColor),
                      ),
                    ),
                  )
                : Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.description_rounded,
                        color: _primaryColor,
                        size: 24,
                      ),
                      const SizedBox(width: 12),
                      Text(
                        'Создать РКО',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: _primaryColor,
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }

  /// Подсказка внизу
  Widget _buildInfoTip() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.1),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Icon(
            Icons.info_outline_rounded,
            color: Colors.white.withOpacity(0.7),
            size: 22,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'После оформления РКО будет сформирован PDF документ и загружен на сервер',
              style: TextStyle(
                fontSize: 13,
                color: Colors.white.withOpacity(0.7),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

