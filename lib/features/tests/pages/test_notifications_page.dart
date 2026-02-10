import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import '../../../shared/providers/order_provider.dart';
import '../../../core/services/notification_service.dart';
import '../../employees/pages/employees_page.dart';
import '../../../shared/providers/cart_provider.dart';
import '../../menu/pages/menu_page.dart';
import '../../attendance/services/attendance_service.dart';
import '../../shifts/models/shift_report_model.dart';
import '../../shifts/services/shift_report_service.dart';
import '../../shifts/models/shift_question_model.dart';
import '../../recount/services/recount_service.dart';
import '../../recount/models/recount_report_model.dart';
import '../../recount/models/recount_question_model.dart';
import '../../recount/models/recount_answer_model.dart';
import '../../shops/models/shop_model.dart';
import '../../rko/services/rko_reports_service.dart';
import '../../../core/utils/logger.dart';

/// Тестовая страница для проверки всех функций приложения
class TestNotificationsPage extends StatefulWidget {
  const TestNotificationsPage({super.key});

  @override
  State<TestNotificationsPage> createState() => _TestNotificationsPageState();
}

class _TestNotificationsPageState extends State<TestNotificationsPage> {
  // Состояние для тестирования заказов
  String? _selectedEmployee;
  List<Employee> _employees = [];
  bool _loadingEmployees = false;

  // Состояние для тестирования KPI
  String? _kpiSelectedEmployee;
  String? _kpiSelectedShop;
  DateTime _kpiSelectedDate = DateTime.now();
  final TextEditingController _timeController = TextEditingController();
  List<Employee> _allEmployees = []; // Используем Employee вместо EmployeeRegistration
  List<Shop> _allShops = [];
  bool _loadingKpiData = false;
  bool _creatingAttendance = false;
  bool _creatingShift = false;
  bool _creatingRecount = false;

  @override
  void initState() {
    super.initState();
    _timeController.text = '${DateTime.now().hour.toString().padLeft(2, '0')}:${DateTime.now().minute.toString().padLeft(2, '0')}';
    _loadEmployees();
    _loadKpiData();
  }

  @override
  void dispose() {
    _timeController.dispose();
    super.dispose();
  }

  // ========== Загрузка данных ==========

  Future<void> _loadEmployees() async {
    setState(() => _loadingEmployees = true);
    try {
      final employees = await EmployeesPage.loadEmployeesForNotifications();
      setState(() {
        _employees = employees;
        _loadingEmployees = false;
      });
    } catch (e) {
      setState(() => _loadingEmployees = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка загрузки сотрудников: $e')),
        );
      }
    }
  }

  Future<void> _loadKpiData() async {
    setState(() => _loadingKpiData = true);
    try {
      // Используем тот же метод, что и в меню "Сотрудники"
      // Это гарантирует, что имена будут совпадать с отображением в системе
      final employees = await EmployeesPage.loadEmployeesForNotifications();
      final shops = await Shop.loadShopsFromServer();
      setState(() {
        _allEmployees = employees;
        _allShops = shops;
        if (_allShops.isNotEmpty && _kpiSelectedShop == null) {
          _kpiSelectedShop = _allShops.first.address;
        }
        if (_allEmployees.isNotEmpty && _kpiSelectedEmployee == null) {
          _kpiSelectedEmployee = _allEmployees.first.name; // Используем name вместо fullName
        }
        _loadingKpiData = false;
      });
    } catch (e) {
      Logger.error('Ошибка загрузки данных для KPI', e);
      setState(() => _loadingKpiData = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка загрузки данных: $e')),
        );
      }
    }
  }

  // ========== Тестирование заказов ==========

  Future<void> _createTestOrder() async {
    if (!mounted) return;
    final orderProvider = OrderProvider.of(context);
    
    final testItems = [
      CartItem(
        menuItem: MenuItem(
          id: 'test_item_1',
          name: 'Тестовый напиток',
          price: '150',
          category: 'Тест',
          shop: 'Тестовый магазин',
          photoId: '',
        ),
        quantity: 2,
      ),
    ];

    orderProvider.createOrder(
      testItems,
      300.0,
      comment: 'Тестовый заказ для проверки уведомлений',
    );

    final newOrder = orderProvider.orders.first;

    try {
      await NotificationService.notifyNewOrder(
        context,
        newOrder,
        _employees,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Тестовый заказ создан! Уведомления отправлены.'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Ошибка отправки уведомления: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _testAcceptOrder() async {
    if (!mounted) return;
    final orderProvider = OrderProvider.of(context);
    
    if (orderProvider.orders.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('⚠️ Сначала создайте тестовый заказ'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    if (_selectedEmployee == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('⚠️ Выберите сотрудника'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    final order = orderProvider.orders.first;
    await NotificationService.showAcceptOrderDialog(
      context,
      order,
      _selectedEmployee!,
    );
  }

  Future<void> _testRejectOrder() async {
    if (!mounted) return;
    final orderProvider = OrderProvider.of(context);
    
    if (orderProvider.orders.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('⚠️ Сначала создайте тестовый заказ'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    if (_selectedEmployee == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('⚠️ Выберите сотрудника'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    final order = orderProvider.orders.first;
    await NotificationService.showRejectOrderDialog(
      context,
      order,
      _selectedEmployee!,
    );
  }

  // ========== Тестирование KPI ==========

  Future<void> _selectKpiDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _kpiSelectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
    );
    if (picked != null) {
      setState(() => _kpiSelectedDate = picked);
    }
  }

  TimeOfDay? _parseTime(String timeStr) {
    try {
      final parts = timeStr.split(':');
      if (parts.length != 2) return null;
      final hour = int.tryParse(parts[0]);
      final minute = int.tryParse(parts[1]);
      if (hour == null || minute == null) return null;
      if (hour < 0 || hour > 23 || minute < 0 || minute > 59) return null;
      return TimeOfDay(hour: hour, minute: minute);
    } catch (e) {
      return null;
    }
  }

  String? _validateTime(String? value) {
    if (value == null || value.isEmpty) {
      return 'Введите время';
    }
    final time = _parseTime(value);
    if (time == null) {
      return 'Неверный формат. Используйте HH:mm (например, 14:30)';
    }
    return null;
  }

  Future<bool> _createTestAttendance() async {
    if (_kpiSelectedEmployee == null || _kpiSelectedShop == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('⚠️ Выберите сотрудника и магазин'),
          backgroundColor: Colors.orange,
        ),
      );
      return false;
    }

    setState(() => _creatingAttendance = true);

    try {
      // Парсим время из текстового поля
      final time = _parseTime(_timeController.text);
      if (time == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('⚠️ Неверный формат времени. Используйте HH:mm (например, 14:30)'),
            backgroundColor: Colors.orange,
          ),
        );
        setState(() => _creatingAttendance = false);
        return false;
      }

      // Создаем DateTime из выбранных даты и времени в UTC
      // Важно: конвертируем в UTC, чтобы время было корректным на сервере
      final dateTime = DateTime.utc(
        _kpiSelectedDate.year,
        _kpiSelectedDate.month,
        _kpiSelectedDate.day,
        time.hour,
        time.minute,
      );

      // Находим магазин для получения координат
      final shop = _allShops.firstWhere(
        (s) => s.address == _kpiSelectedShop,
        orElse: () => _allShops.first,
      );

      // Используем координаты магазина или тестовые координаты
      final latitude = shop.latitude ?? 44.0433; // Координаты Пятигорска
      final longitude = shop.longitude ?? 43.0577;

      // Создаем отметку прихода с указанным временем
      Logger.debug('📝 Создание тестовой отметки прихода: $_kpiSelectedEmployee, дата/время (UTC): ${dateTime.toIso8601String()}');
      final result = await AttendanceService.markAttendance(
        employeeName: _kpiSelectedEmployee!,
        shopAddress: _kpiSelectedShop!,
        latitude: latitude,
        longitude: longitude,
        distance: 0.0,
        timestamp: dateTime, // Передаем созданное время в UTC
      );

      if (mounted) {
        setState(() => _creatingAttendance = false);
        if (result.success) {
          String message = '✅ Отметка прихода создана: ${_formatDateTime(dateTime)}';
          Color backgroundColor = Colors.green;
          
          if (result.isOnTime == true) {
            message += '\nВовремя';
          } else if (result.isOnTime == false && result.lateMinutes != null) {
            message += '\nОпоздал на ${result.lateMinutes} мин';
            backgroundColor = Colors.orange;
          } else if (result.isOnTime == null) {
            message += '\nВне смены';
            backgroundColor = Colors.amber;
          }
          
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(message),
              backgroundColor: backgroundColor,
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('❌ Ошибка создания отметки прихода: ${result.error ?? "Неизвестная ошибка"}'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }

      return result.success;
    } catch (e) {
      Logger.error('Ошибка создания тестовой отметки прихода', e);
      if (mounted) {
        setState(() => _creatingAttendance = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Ошибка: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return false;
    }
  }

  Future<bool> _createTestShiftReport() async {
    if (_kpiSelectedEmployee == null || _kpiSelectedShop == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('⚠️ Выберите сотрудника и магазин'),
          backgroundColor: Colors.orange,
        ),
      );
      return false;
    }

    setState(() => _creatingShift = true);

    try {
      // Загружаем вопросы пересменки
      final questions = await ShiftQuestion.loadQuestions();

      if (!mounted) return false;

      // Создаем ответы с дефолтными значениями
      final answers = questions.map((question) {
        if (question.isNumberOnly) {
          return ShiftAnswer(
            question: question.question,
            numberAnswer: 0,
          );
        } else if (question.isYesNo) {
          return ShiftAnswer(
            question: question.question,
            textAnswer: 'Да',
          );
        } else if (question.isPhotoOnly) {
          // Пропускаем фото
          return ShiftAnswer(
            question: question.question,
            textAnswer: 'Тестовый ответ (фото пропущено)',
          );
        } else {
          // Текстовый вопрос
          return ShiftAnswer(
            question: question.question,
            textAnswer: 'Тестовый ответ',
          );
        }
      }).toList();

      // Парсим время из текстового поля
      final time = _parseTime(_timeController.text);
      if (time == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('⚠️ Неверный формат времени. Используйте HH:mm (например, 14:30)'),
            backgroundColor: Colors.orange,
          ),
        );
        setState(() => _creatingShift = false);
        return false;
      }

      // Создаем DateTime из выбранных даты и времени в UTC
      // Важно: конвертируем в UTC, чтобы время было корректным на сервере
      final dateTime = DateTime.utc(
        _kpiSelectedDate.year,
        _kpiSelectedDate.month,
        _kpiSelectedDate.day,
        time.hour,
        time.minute,
      );

      // Создаем отчет
      final report = ShiftReport(
        id: ShiftReport.generateId(
          _kpiSelectedEmployee!,
          _kpiSelectedShop!,
          dateTime,
        ),
        employeeName: _kpiSelectedEmployee!,
        shopAddress: _kpiSelectedShop!,
        createdAt: dateTime, // Время в UTC
        answers: answers,
        isSynced: false,
      );

      // Сохраняем отчет на сервер
      final success = await ShiftReportService.saveReport(report);

      if (mounted) {
        setState(() => _creatingShift = false);
        if (success) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('✅ Пересменка создана: ${_formatDateTime(dateTime)}'),
              backgroundColor: Colors.green,
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('❌ Ошибка сохранения пересменки на сервер'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }

      return success;
    } catch (e) {
      Logger.error('Ошибка создания тестовой пересменки', e);
      if (mounted) {
        setState(() => _creatingShift = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Ошибка: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return false;
    }
  }

  Future<bool> _createTestRecountReport() async {
    if (_kpiSelectedEmployee == null || _kpiSelectedShop == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('⚠️ Выберите сотрудника и магазин'),
          backgroundColor: Colors.orange,
        ),
      );
      return false;
    }

    setState(() => _creatingRecount = true);

    try {
      // Загружаем вопросы пересчета
      final allQuestions = await RecountQuestion.loadQuestions();

      if (!mounted) return false;

      // Выбираем 30 вопросов по алгоритму
      final selectedQuestions = RecountQuestion.selectQuestions(allQuestions);

      // Парсим время из текстового поля
      final time = _parseTime(_timeController.text);
      if (time == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('⚠️ Неверный формат времени. Используйте HH:mm (например, 14:30)'),
            backgroundColor: Colors.orange,
          ),
        );
        setState(() => _creatingRecount = false);
        return false;
      }

      // Создаем DateTime из выбранных даты и времени в UTC
      // Важно: конвертируем в UTC, чтобы время было корректным на сервере
      final dateTime = DateTime.utc(
        _kpiSelectedDate.year,
        _kpiSelectedDate.month,
        _kpiSelectedDate.day,
        time.hour,
        time.minute,
      );

      final startedAt = dateTime; // Время в UTC
      final completedAt = dateTime.add(const Duration(minutes: 5)); // Тестовая длительность 5 минут
      final duration = completedAt.difference(startedAt);

      // Создаем ответы с дефолтными значениями
      final answers = selectedQuestions.map((question) {
        return RecountAnswer(
          question: question.question,
          grade: question.grade,
          answer: 'сходится',
          quantity: 0,
          programBalance: 0,
          actualBalance: 0,
          difference: 0,
          photoRequired: false, // Для теста не требуем фото
        );
      }).toList();

      // Создаем отчет
      final report = RecountReport(
        id: RecountReport.generateId(
          _kpiSelectedEmployee!,
          _kpiSelectedShop!,
          dateTime,
        ),
        employeeName: _kpiSelectedEmployee!,
        shopAddress: _kpiSelectedShop!,
        startedAt: startedAt,
        completedAt: completedAt,
        duration: duration,
        answers: answers,
      );

      // Сохраняем отчет через сервис
      final success = await RecountService.createReport(report);

      if (mounted) {
        setState(() => _creatingRecount = false);
        if (success) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('✅ Пересчет создан: ${_formatDateTime(dateTime)}'),
              backgroundColor: Colors.green,
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('❌ Ошибка создания пересчета'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }

      return success;
    } catch (e) {
      Logger.error('Ошибка создания тестового пересчета', e);
      if (mounted) {
        setState(() => _creatingRecount = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Ошибка: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return false;
    }
  }

  Future<void> _createTestRKO() async {
    if (_kpiSelectedEmployee == null || _kpiSelectedShop == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('⚠️ Выберите сотрудника и магазин'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    // Показываем диалог для ввода суммы
    final amountController = TextEditingController();
    final rkoTypeController = TextEditingController(text: 'income');
    
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Создать тестовое РКО'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: amountController,
              decoration: const InputDecoration(
                labelText: 'Сумма',
                hintText: 'Например: 10000',
              ),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: rkoTypeController,
              decoration: const InputDecoration(
                labelText: 'Тип РКО',
                hintText: 'income',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Отмена'),
          ),
          ElevatedButton(
            onPressed: () {
              if (amountController.text.isNotEmpty) {
                Navigator.pop(context, true);
              }
            },
            child: const Text('Создать'),
          ),
        ],
      ),
    );

    if (!mounted) return;

    if (result != true) return;

    final amount = double.tryParse(amountController.text.replaceAll(',', '.'));
    if (amount == null || amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('⚠️ Введите корректную сумму'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    // Создаем тестовое РКО напрямую через API
    // Используем выбранную дату из тестовой страницы
    final selectedDate = DateTime.utc(
      _kpiSelectedDate.year,
      _kpiSelectedDate.month,
      _kpiSelectedDate.day,
    );

    try {
      // Создаем минимальный PDF файл для теста
      final tempDir = await getTemporaryDirectory();
      final fileName = 'rko_test_${_kpiSelectedEmployee!.toLowerCase()}_${_kpiSelectedDate.day}_${DateTime.now().millisecondsSinceEpoch}.pdf';
      final pdfFile = File(path.join(tempDir.path, fileName));
      
      // Создаем пустой PDF файл (заглушка)
      await pdfFile.writeAsString('PDF placeholder for test RKO');
      
      // Загружаем на сервер с выбранной датой
      final success = await RKOReportsService.uploadRKO(
        pdfFile: pdfFile,
        fileName: fileName,
        employeeName: _kpiSelectedEmployee!,
        shopAddress: _kpiSelectedShop!,
        date: selectedDate, // Используем выбранную дату
        amount: amount,
        rkoType: rkoTypeController.text.isEmpty ? 'income' : rkoTypeController.text,
      );

      if (mounted) {
        if (success) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('✅ Тестовое РКО создано для ${_formatDate(_kpiSelectedDate)}'),
              backgroundColor: Colors.green,
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('❌ Ошибка создания РКО'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      Logger.error('Ошибка создания тестового РКО', e);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Ошибка: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // ========== Вспомогательные методы форматирования ==========

  String _formatDateTime(DateTime dateTime) {
    final day = dateTime.day.toString().padLeft(2, '0');
    final month = dateTime.month.toString().padLeft(2, '0');
    final year = dateTime.year;
    final hour = dateTime.hour.toString().padLeft(2, '0');
    final minute = dateTime.minute.toString().padLeft(2, '0');
    return '$day.$month.$year $hour:$minute';
  }

  String _formatDate(DateTime date) {
    final day = date.day.toString().padLeft(2, '0');
    final month = date.month.toString().padLeft(2, '0');
    final year = date.year;
    return '$day.$month.$year';
  }

  // ========== UI Builders ==========

  Widget _buildOrdersTestSection() {
    return ExpansionTile(
      title: const Text('📦 Тестирование заказов'),
      initiallyExpanded: true,
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Список сотрудников
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '👥 Сотрудники:',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 12),
                      if (_loadingEmployees)
                        const Center(child: CircularProgressIndicator())
                      else if (_employees.isEmpty)
                        const Text('Сотрудники не найдены')
                      else
                        ..._employees.map((employee) => RadioListTile<String>(
                              title: Text(employee.name),
                              value: employee.name,
                              groupValue: _selectedEmployee,
                              onChanged: (value) {
                                setState(() => _selectedEmployee = value);
                              },
                            )),
                      const SizedBox(height: 8),
                      TextButton.icon(
                        onPressed: _loadEmployees,
                        icon: const Icon(Icons.refresh),
                        label: const Text('Обновить список'),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              ElevatedButton.icon(
                onPressed: _createTestOrder,
                icon: const Icon(Icons.add_shopping_cart),
                label: const Text('Создать тестовый заказ'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF004D40),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
              ),
              const SizedBox(height: 12),
              ElevatedButton.icon(
                onPressed: _testAcceptOrder,
                icon: const Icon(Icons.check_circle),
                label: const Text('Принять заказ (тест)'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
              ),
              const SizedBox(height: 12),
              ElevatedButton.icon(
                onPressed: _testRejectOrder,
                icon: const Icon(Icons.cancel),
                label: const Text('Отказаться от заказа (тест)'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
              ),
              const SizedBox(height: 12),
              // Список текущих заказов
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '📦 Текущие заказы:',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 12),
                      ListenableBuilder(
                        listenable: OrderProvider.of(context),
                        builder: (context, _) {
                          final orderProvider = OrderProvider.of(context);
                          if (orderProvider.orders.isEmpty)
                            return const Text('Заказов нет');
                          return Column(
                            children: orderProvider.orders.take(5).map((order) => ListTile(
                              leading: CircleAvatar(
                                backgroundColor: order.status == 'completed'
                                    ? Colors.green
                                    : order.status == 'rejected'
                                        ? Colors.red
                                        : Colors.orange,
                                child: order.status == 'completed'
                                    ? const Icon(Icons.check, color: Colors.white)
                                    : order.status == 'rejected'
                                        ? const Icon(Icons.close, color: Colors.white)
                                        : const Icon(Icons.pending, color: Colors.white),
                              ),
                              title: Text('Заказ ${order.id.substring(order.id.length - 6)}'),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '${order.totalPrice.toStringAsFixed(0)} руб - ${order.status == 'completed' ? 'Выполнено' : order.status == 'rejected' ? 'Не принят' : 'Ожидает'}',
                                  ),
                                  if (order.acceptedBy != null)
                                    Text(
                                      'Принял: ${order.acceptedBy}',
                                      style: const TextStyle(fontSize: 11, color: Colors.green),
                                    ),
                                  if (order.rejectedBy != null)
                                    Text(
                                      'Отказал: ${order.rejectedBy}',
                                      style: const TextStyle(fontSize: 11, color: Colors.red),
                                    ),
                                ],
                              ),
                            )).toList(),
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildKpiTestSection() {
    return ExpansionTile(
      title: const Text('📊 Тестирование KPI'),
      initiallyExpanded: true,
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_loadingKpiData)
                const Center(child: CircularProgressIndicator())
              else ...[
                // Выбор сотрудника
                DropdownButtonFormField<String>(
                  value: _kpiSelectedEmployee,
                  decoration: const InputDecoration(
                    labelText: 'Сотрудник',
                    border: OutlineInputBorder(),
                  ),
                  items: _allEmployees.map((emp) => DropdownMenuItem(
                    value: emp.name, // Используем name вместо fullName
                    child: Text(emp.name), // Используем name вместо fullName
                  )).toList(),
                  onChanged: (value) {
                    setState(() => _kpiSelectedEmployee = value);
                  },
                ),
                const SizedBox(height: 16),
                // Выбор магазина
                DropdownButtonFormField<String>(
                  value: _kpiSelectedShop,
                  decoration: const InputDecoration(
                    labelText: 'Магазин',
                    border: OutlineInputBorder(),
                  ),
                  items: _allShops.map((shop) => DropdownMenuItem(
                    value: shop.address,
                    child: Text(shop.address),
                  )).toList(),
                  onChanged: (value) {
                    setState(() => _kpiSelectedShop = value);
                  },
                ),
                const SizedBox(height: 16),
                // Выбор даты
                OutlinedButton.icon(
                  onPressed: _selectKpiDate,
                  icon: const Icon(Icons.calendar_today),
                  label: Text(_formatDate(_kpiSelectedDate)),
                ),
                const SizedBox(height: 16),
                // Ввод времени вручную (24-часовой формат)
                TextFormField(
                  controller: _timeController,
                  decoration: const InputDecoration(
                    labelText: 'Время (24-часовой формат)',
                    hintText: 'HH:mm (например, 14:30)',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.access_time),
                    helperText: 'Введите время в формате ЧЧ:мм (00:00 - 23:59)',
                  ),
                  keyboardType: TextInputType.datetime,
                  validator: _validateTime,
                  inputFormatters: [
                    // Ограничиваем ввод только цифрами и двоеточием
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9:]')),
                  ],
                  onChanged: (value) {
                    // Автоматически добавляем двоеточие после ввода 2 цифр
                    if (value.length == 2 && !value.contains(':')) {
                      _timeController.value = TextEditingValue(
                        text: '$value:',
                        selection: TextSelection.collapsed(offset: 3),
                      );
                    }
                  },
                ),
                const SizedBox(height: 24),
                // Кнопки создания тестовых данных
                ElevatedButton.icon(
                  onPressed: _creatingAttendance ? null : _createTestAttendance,
                  icon: _creatingAttendance
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.access_time),
                  label: const Text('Создать отметку прихода'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF004D40),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                ),
                const SizedBox(height: 12),
                ElevatedButton.icon(
                  onPressed: _creatingShift ? null : _createTestShiftReport,
                  icon: _creatingShift
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.swap_horiz),
                  label: const Text('Создать пересменку'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                ),
                const SizedBox(height: 12),
                ElevatedButton.icon(
                  onPressed: _creatingRecount ? null : _createTestRecountReport,
                  icon: _creatingRecount
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.calculate),
                  label: const Text('Создать пересчет'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                ),
                const SizedBox(height: 12),
                ElevatedButton.icon(
                  onPressed: _createTestRKO,
                  icon: const Icon(Icons.receipt),
                  label: const Text('Создать РКО'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.purple,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildNotificationsTestSection() {
    return ExpansionTile(
      title: const Text('🔔 Тестирование уведомлений'),
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Функционал тестирования уведомлений будет добавлен в будущих версиях.',
                style: TextStyle(fontSize: 14),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildOtherFunctionsTestSection() {
    return ExpansionTile(
      title: const Text('🔧 Тестирование других функций'),
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Функционал тестирования других функций будет добавлен в будущих версиях.',
                style: TextStyle(fontSize: 14),
              ),
            ],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Тестирование функций'),
        backgroundColor: const Color(0xFF004D40),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Card(
              color: Colors.blue[50],
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '📋 Тестовая страница',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Используйте эту страницу для тестирования различных функций приложения. '
                      'Раскройте нужную секцию для доступа к тестам.',
                      style: TextStyle(fontSize: 14),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            _buildOrdersTestSection(),
            const SizedBox(height: 8),
            _buildKpiTestSection(),
            const SizedBox(height: 8),
            _buildNotificationsTestSection(),
            const SizedBox(height: 8),
            _buildOtherFunctionsTestSection(),
          ],
        ),
      ),
    );
  }
}
