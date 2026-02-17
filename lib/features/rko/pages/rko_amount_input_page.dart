import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/rko_service.dart';
import '../../shops/models/shop_model.dart';
import '../../shops/services/shop_service.dart';
import '../services/rko_pdf_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../employees/pages/employees_page.dart';
import '../../kpi/services/kpi_service.dart';
import '../../../core/utils/logger.dart';
import '../../../core/services/report_notification_service.dart';
// Сервисы для проверки активности сотрудника
import '../../attendance/services/attendance_service.dart';
import '../../shift_handover/services/shift_handover_report_service.dart';
import '../../recount/services/recount_service.dart';
// Сервис настроек баллов для проверки временного окна
import '../../efficiency/services/points_settings_service.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../../core/theme/app_colors.dart';

/// Страница ввода суммы и создания РКО
class RKOAmountInputPage extends StatefulWidget {
  final String rkoType;
  final Shop? preselectedShop; // Магазин, выбранный на предыдущем экране

  const RKOAmountInputPage({
    super.key,
    required this.rkoType,
    this.preselectedShop,
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

  // Проверка временного окна
  bool _isCheckingTime = true;
  bool _isTimeWindowOpen = false;
  String? _nextWindowTime;

  @override
  void initState() {
    super.initState();
    _checkTimeWindow();
    _initialize();
  }

  /// Парсинг времени из строки "HH:MM"
  TimeOfDay _parseTime(String timeStr) {
    final parts = timeStr.split(':');
    return TimeOfDay(
      hour: int.parse(parts[0]),
      minute: int.parse(parts[1]),
    );
  }

  /// Проверка находится ли время в диапазоне
  bool _isTimeInRange(TimeOfDay current, TimeOfDay start, TimeOfDay end) {
    final currentMinutes = current.hour * 60 + current.minute;
    final startMinutes = start.hour * 60 + start.minute;
    final endMinutes = end.hour * 60 + end.minute;
    return currentMinutes >= startMinutes && currentMinutes < endMinutes;
  }

  /// Проверка временного окна для сдачи РКО
  Future<void> _checkTimeWindow() async {
    try {
      final settings = await PointsSettingsService.getRkoPointsSettings();
      final now = TimeOfDay.now();

      final morningStart = _parseTime(settings.morningStartTime);
      final morningEnd = _parseTime(settings.morningEndTime);
      final eveningStart = _parseTime(settings.eveningStartTime);
      final eveningEnd = _parseTime(settings.eveningEndTime);

      bool isOpen = false;
      String? nextWindow;

      if (_isTimeInRange(now, morningStart, morningEnd)) {
        isOpen = true;
      } else if (_isTimeInRange(now, eveningStart, eveningEnd)) {
        isOpen = true;
      } else {
        // Определяем следующее окно
        final currentMinutes = now.hour * 60 + now.minute;
        final morningStartMinutes = morningStart.hour * 60 + morningStart.minute;
        final eveningStartMinutes = eveningStart.hour * 60 + eveningStart.minute;

        if (currentMinutes < morningStartMinutes) {
          nextWindow = '${settings.morningStartTime} - ${settings.morningEndTime}';
        } else if (currentMinutes < eveningStartMinutes) {
          nextWindow = '${settings.eveningStartTime} - ${settings.eveningEndTime}';
        } else {
          nextWindow = '${settings.morningStartTime} - ${settings.morningEndTime} (завтра)';
        }
      }

      if (mounted) {
        setState(() {
          _isCheckingTime = false;
          _isTimeWindowOpen = isOpen;
          _nextWindowTime = nextWindow;
        });
      }
    } catch (e) {
      Logger.error('Ошибка проверки временного окна РКО', e);
      if (mounted) {
        setState(() {
          _isCheckingTime = false;
          _isTimeWindowOpen = true; // В случае ошибки разрешаем доступ
        });
      }
    }
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

        // Если магазин уже выбран на предыдущем экране, используем его
        if (widget.preselectedShop != null) {
          _selectedShop = widget.preselectedShop;
        } else {
          // Получаем магазин из последней пересменки
          final shop = await RKOService.getShopFromLastShift(_employeeName!);
          if (shop != null) {
            _selectedShop = shop;
          }
        }
      } else {
        // Fallback: получаем имя из меню "Сотрудники" (единый источник истины)
        final name = await EmployeesPage.getCurrentEmployeeName();
        _employeeName = name;

        // Если магазин уже выбран на предыдущем экране, используем его
        if (widget.preselectedShop != null) {
          _selectedShop = widget.preselectedShop;
        } else if (name != null) {
          final shop = await RKOService.getShopFromLastShift(name);
          if (shop != null) {
            _selectedShop = shop;
          }
        }
      }

      // Загружаем список всех магазинов для выбора
      final shops = await ShopService.getShopsForCurrentUser();

      // Если был выбран магазин, находим его в списке по адресу
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
        SnackBar(
          content: Text('Введите сумму'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    final amount = double.tryParse(_amountController.text.replaceAll(',', '.'));
    if (amount == null || amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Введите корректную сумму'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    if (_selectedShop == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
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
            SnackBar(
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
            SnackBar(
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
            description: '${widget.rkoType}: ${amount.toStringAsFixed(0)} руб',
          );

          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
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
              duration: Duration(seconds: 5),
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

  /// Получить список магазинов где была активность сотрудника за последние 24 часа
  Future<List<_ActivityRecord>> _getRecentActivityShops() async {
    if (_employeeName == null) return [];

    final now = DateTime.now();
    final yesterday = now.subtract(Duration(hours: 24));
    final activities = <_ActivityRecord>[];

    try {
      // 1. Проверяем отметки "Я на работе"
      final attendanceRecords = await AttendanceService.getAttendanceRecords(
        employeeName: _employeeName,
      );
      for (final record in attendanceRecords) {
        if (record.timestamp.isAfter(yesterday)) {
          activities.add(_ActivityRecord(
            shopAddress: record.shopAddress,
            type: 'Отметка "Я на работе"',
            timestamp: record.timestamp,
          ));
        }
      }

      // 2. Проверяем пересменки
      final shiftReports = await ShiftHandoverReportService.getReports(
        employeeName: _employeeName,
      );
      for (final report in shiftReports) {
        if (report.createdAt.isAfter(yesterday)) {
          activities.add(_ActivityRecord(
            shopAddress: report.shopAddress,
            type: 'Пересменка',
            timestamp: report.createdAt,
          ));
        }
      }

      // 3. Проверяем пересчёты
      final recountReports = await RecountService.getReports(
        employeeName: _employeeName,
      );
      for (final report in recountReports) {
        if (report.completedAt.isAfter(yesterday)) {
          activities.add(_ActivityRecord(
            shopAddress: report.shopAddress,
            type: 'Пересчёт',
            timestamp: report.completedAt,
          ));
        }
      }
    } catch (e) {
      Logger.error('Ошибка получения активности', e);
    }

    return activities;
  }

  /// Проверить выбор магазина и показать предупреждение если нужно
  Future<bool> _validateShopSelection(Shop selectedShop) async {
    final activities = await _getRecentActivityShops();

    if (activities.isEmpty) return true; // Нет активности — разрешаем

    // Находим активности НЕ на выбранном магазине
    final otherShopActivities = activities.where(
      (a) => a.shopAddress.toLowerCase().trim() != selectedShop.address.toLowerCase().trim()
    ).toList();

    if (otherShopActivities.isEmpty) return true; // Вся активность на выбранном магазине

    // Группируем по магазинам
    final shopActivities = <String, List<_ActivityRecord>>{};
    for (final activity in otherShopActivities) {
      shopActivities.putIfAbsent(activity.shopAddress, () => []).add(activity);
    }

    // Показываем диалог
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 28),
            SizedBox(width: 12),
            Text('Внимание'),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Вы уверены что ваш выбор правильный?',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16.sp),
              ),
              SizedBox(height: 16),
              Text('За последние 24 часа у вас была активность на другом магазине:'),
              SizedBox(height: 12),
              ...shopActivities.entries.map((entry) => Container(
                margin: EdgeInsets.only(bottom: 8.h),
                padding: EdgeInsets.all(12.w),
                decoration: BoxDecoration(
                  color: Colors.orange.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8.r),
                  border: Border.all(color: Colors.orange.withOpacity(0.3)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.store, size: 18, color: Colors.orange[700]),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            entry.key,
                            style: TextStyle(fontWeight: FontWeight.bold, color: Colors.orange[800]),
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: 4),
                    ...entry.value.map((a) => Padding(
                      padding: EdgeInsets.only(left: 26.w),
                      child: Text(
                        '• ${a.type}',
                        style: TextStyle(fontSize: 13.sp, color: Colors.grey[700]),
                      ),
                    )),
                  ],
                ),
              )),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Отмена'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.primaryGreen),
            child: Text('Да, продолжить', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    return confirmed ?? false;
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
    // Проверка загрузки временного окна
    if (_isCheckingTime) {
      return Scaffold(
        appBar: AppBar(
          title: Text('РКО: ${widget.rkoType}'),
          backgroundColor: AppColors.primaryGreen,
        ),
        body: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    // Если временное окно закрыто - показываем сообщение
    if (!_isTimeWindowOpen) {
      return Scaffold(
        appBar: AppBar(
          title: Text('РКО: ${widget.rkoType}'),
          backgroundColor: AppColors.primaryGreen,
        ),
        body: Center(
          child: Padding(
            padding: EdgeInsets.all(24.w),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: EdgeInsets.all(24.w),
                  decoration: BoxDecoration(
                    color: Colors.orange.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(20.r),
                    border: Border.all(color: Colors.orange, width: 2),
                  ),
                  child: Column(
                    children: [
                      Icon(
                        Icons.access_time_rounded,
                        size: 64,
                        color: Colors.orange,
                      ),
                      SizedBox(height: 16),
                      Text(
                        'Окно сдачи РКО закрыто',
                        style: TextStyle(
                          fontSize: 20.sp,
                          fontWeight: FontWeight.bold,
                          color: Colors.orange,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      SizedBox(height: 8),
                      Text(
                        'РКО можно сдать только в определённое время',
                        style: TextStyle(
                          fontSize: 14.sp,
                          color: Colors.grey,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
                SizedBox(height: 24),
                Text(
                  'Следующее окно:',
                  style: TextStyle(
                    fontSize: 16.sp,
                    color: Colors.grey,
                  ),
                ),
                SizedBox(height: 8),
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 20.w, vertical: 12.h),
                  decoration: BoxDecoration(
                    color: AppColors.primaryGreen.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12.r),
                  ),
                  child: Text(
                    _nextWindowTime ?? 'Следующее окно',
                    style: TextStyle(
                      fontSize: 20.sp,
                      fontWeight: FontWeight.bold,
                      color: AppColors.primaryGreen,
                    ),
                  ),
                ),
                SizedBox(height: 32),
                ElevatedButton.icon(
                  onPressed: () => Navigator.pop(context),
                  icon: Icon(Icons.arrow_back),
                  label: Text('Назад'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primaryGreen,
                    foregroundColor: Colors.white,
                    padding: EdgeInsets.symmetric(horizontal: 32.w, vertical: 12.h),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text('РКО: ${widget.rkoType}'),
        backgroundColor: AppColors.primaryGreen,
        elevation: 0,
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              AppColors.primaryGreen,
              AppColors.primaryGreen.withOpacity(0.85),
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
                    SizedBox(height: 16),
                    Text(
                      'Загрузка данных...',
                      style: TextStyle(color: Colors.white70, fontSize: 16.sp),
                    ),
                  ],
                ),
              )
            : SafeArea(
                child: SingleChildScrollView(
                  padding: EdgeInsets.all(20.w),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Заголовок с типом РКО
                      _buildTypeHeader(),
                      SizedBox(height: 24),

                      // Информация о сотруднике
                      if (_employeeName != null) ...[
                        _buildEmployeeCard(),
                        SizedBox(height: 16),
                      ],

                      // Выбор магазина
                      _buildShopCard(),
                      SizedBox(height: 16),

                      // Ввод суммы
                      _buildAmountCard(),
                      SizedBox(height: 28),

                      // Кнопка создания
                      _buildCreateButton(),
                      SizedBox(height: 16),

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
      padding: EdgeInsets.all(20.w),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.15),
        borderRadius: BorderRadius.circular(20.r),
      ),
      child: Row(
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: _rkoTypeColor.withOpacity(0.2),
              borderRadius: BorderRadius.circular(16.r),
            ),
            child: Icon(
              _rkoTypeIcon,
              size: 32,
              color: Colors.white,
            ),
          ),
          SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.rkoType,
                  style: TextStyle(
                    fontSize: 20.sp,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  widget.rkoType.contains('месяц')
                      ? 'Месячная выплата заработной платы'
                      : 'Выплата за отработанную смену',
                  style: TextStyle(
                    fontSize: 14.sp,
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
        borderRadius: BorderRadius.circular(18.r),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.15),
            blurRadius: 12,
            offset: Offset(0, 5),
          ),
        ],
      ),
      child: Padding(
        padding: EdgeInsets.all(16.w),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: AppColors.primaryGreen.withOpacity(0.1),
                borderRadius: BorderRadius.circular(14.r),
              ),
              child: Icon(
                Icons.person_rounded,
                color: AppColors.primaryGreen,
                size: 26,
              ),
            ),
            SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Сотрудник',
                    style: TextStyle(
                      fontSize: 12.sp,
                      color: Colors.grey[600],
                    ),
                  ),
                  SizedBox(height: 2),
                  Text(
                    _employeeName!,
                    style: TextStyle(
                      fontSize: 16.sp,
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
        borderRadius: BorderRadius.circular(18.r),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.15),
            blurRadius: 12,
            offset: Offset(0, 5),
          ),
        ],
      ),
      child: Padding(
        padding: EdgeInsets.all(18.w),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: AppColors.primaryGreen.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12.r),
                  ),
                  child: Icon(
                    Icons.store_rounded,
                    color: AppColors.primaryGreen,
                    size: 24,
                  ),
                ),
                SizedBox(width: 12),
                Text(
                  'Магазин',
                  style: TextStyle(
                    fontSize: 17.sp,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF2D2D2D),
                  ),
                ),
              ],
            ),
            SizedBox(height: 16),
            Container(
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey[300]!),
                borderRadius: BorderRadius.circular(14.r),
              ),
              child: DropdownButtonFormField<Shop>(
                value: _selectedShop != null && _shops.any((s) => s.address == _selectedShop!.address)
                    ? _shops.firstWhere((s) => s.address == _selectedShop!.address)
                    : null,
                decoration: InputDecoration(
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 14.h),
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
                      style: TextStyle(fontSize: 15.sp),
                    ),
                  );
                }).toList(),
                onChanged: (shop) async {
                  if (shop == null) return;

                  // Сохраняем предыдущий выбор
                  final previousShop = _selectedShop;

                  // Временно устанавливаем новый магазин
                  setState(() {
                    _selectedShop = shop;
                  });

                  // Проверяем активность (только для "ЗП после смены")
                  if (widget.rkoType.contains('смены')) {
                    final confirmed = await _validateShopSelection(shop);
                    if (!confirmed && previousShop != null) {
                      // Отменяем выбор
                      setState(() {
                        _selectedShop = previousShop;
                      });
                    }
                  }
                },
                isExpanded: true,
              ),
            ),
            if (_selectedShop != null) ...[
              SizedBox(height: 12),
              Container(
                padding: EdgeInsets.all(12.w),
                decoration: BoxDecoration(
                  color: AppColors.primaryGreen.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(10.r),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.location_on_rounded,
                      color: AppColors.primaryGreen,
                      size: 18,
                    ),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _selectedShop!.address,
                        style: TextStyle(
                          fontSize: 13.sp,
                          color: AppColors.primaryGreen,
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
        borderRadius: BorderRadius.circular(18.r),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.15),
            blurRadius: 12,
            offset: Offset(0, 5),
          ),
        ],
      ),
      child: Padding(
        padding: EdgeInsets.all(18.w),
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
                    borderRadius: BorderRadius.circular(12.r),
                  ),
                  child: Icon(
                    Icons.payments_rounded,
                    color: _rkoTypeColor,
                    size: 24,
                  ),
                ),
                SizedBox(width: 12),
                Text(
                  'Сумма выплаты',
                  style: TextStyle(
                    fontSize: 17.sp,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF2D2D2D),
                  ),
                ),
              ],
            ),
            SizedBox(height: 16),
            TextField(
              controller: _amountController,
              style: TextStyle(
                fontSize: 24.sp,
                fontWeight: FontWeight.bold,
                color: Color(0xFF2D2D2D),
              ),
              decoration: InputDecoration(
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14.r),
                  borderSide: BorderSide(color: Colors.grey[300]!),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14.r),
                  borderSide: BorderSide(color: AppColors.primaryGreen, width: 2),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14.r),
                  borderSide: BorderSide(color: Colors.grey[300]!),
                ),
                hintText: '0',
                hintStyle: TextStyle(
                  color: Colors.grey[400],
                  fontSize: 24.sp,
                  fontWeight: FontWeight.bold,
                ),
                suffixText: 'руб.',
                suffixStyle: TextStyle(
                  color: AppColors.primaryGreen,
                  fontWeight: FontWeight.bold,
                  fontSize: 18.sp,
                ),
                contentPadding: EdgeInsets.symmetric(horizontal: 20.w, vertical: 18.h),
              ),
              keyboardType: TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}')),
              ],
              textAlign: TextAlign.center,
            ),
            SizedBox(height: 12),
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
        borderRadius: BorderRadius.circular(10.r),
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 8.h),
          decoration: BoxDecoration(
            border: Border.all(color: AppColors.primaryGreen.withOpacity(0.3)),
            borderRadius: BorderRadius.circular(10.r),
          ),
          child: Text(
            '$amount',
            style: TextStyle(
              color: AppColors.primaryGreen,
              fontWeight: FontWeight.w600,
              fontSize: 14.sp,
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
        borderRadius: BorderRadius.circular(18.r),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 12,
            offset: Offset(0, 5),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: _isCreating ? null : _createRKO,
          borderRadius: BorderRadius.circular(18.r),
          child: Padding(
            padding: EdgeInsets.symmetric(vertical: 18.h),
            child: _isCreating
                ? Center(
                    child: SizedBox(
                      height: 24,
                      width: 24,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        valueColor: AlwaysStoppedAnimation<Color>(AppColors.primaryGreen),
                      ),
                    ),
                  )
                : Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.description_rounded,
                        color: AppColors.primaryGreen,
                        size: 24,
                      ),
                      SizedBox(width: 12),
                      Text(
                        'Создать РКО',
                        style: TextStyle(
                          fontSize: 18.sp,
                          fontWeight: FontWeight.bold,
                          color: AppColors.primaryGreen,
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
      padding: EdgeInsets.all(16.w),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.1),
        borderRadius: BorderRadius.circular(14.r),
      ),
      child: Row(
        children: [
          Icon(
            Icons.info_outline_rounded,
            color: Colors.white.withOpacity(0.7),
            size: 22,
          ),
          SizedBox(width: 12),
          Expanded(
            child: Text(
              'После оформления РКО будет сформирован PDF документ и загружен на сервер',
              style: TextStyle(
                fontSize: 13.sp,
                color: Colors.white.withOpacity(0.7),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Запись об активности сотрудника
class _ActivityRecord {
  final String shopAddress;
  final String type;
  final DateTime timestamp;

  _ActivityRecord({
    required this.shopAddress,
    required this.type,
    required this.timestamp,
  });
}
