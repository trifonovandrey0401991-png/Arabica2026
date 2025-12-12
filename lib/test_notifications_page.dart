import 'package:flutter/material.dart';
import 'order_provider.dart';
import 'notification_service.dart';
import 'employees_page.dart';
import 'cart_provider.dart';
import 'menu_page.dart';
import 'attendance_service.dart';
import 'attendance_model.dart';
import 'shift_report_model.dart';
import 'shift_question_model.dart';
import 'recount_service.dart';
import 'recount_report_model.dart';
import 'recount_question_model.dart';
import 'recount_answer_model.dart';
import 'employee_registration_service.dart';
import 'employee_registration_model.dart';
import 'shop_model.dart';
import 'rko_type_selection_page.dart';
import 'utils/logger.dart';

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
  TimeOfDay _kpiSelectedTime = TimeOfDay.now();
  List<EmployeeRegistration> _allEmployees = [];
  List<Shop> _allShops = [];
  bool _loadingKpiData = false;
  bool _creatingAttendance = false;
  bool _creatingShift = false;
  bool _creatingRecount = false;

  @override
  void initState() {
    super.initState();
    _loadEmployees();
    _loadKpiData();
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
      final employees = await EmployeeRegistrationService.getAllRegistrations();
      final shops = await Shop.loadShopsFromGoogleSheets();
      setState(() {
        _allEmployees = employees;
        _allShops = shops;
        if (_allShops.isNotEmpty && _kpiSelectedShop == null) {
          _kpiSelectedShop = _allShops.first.address;
        }
        if (_allEmployees.isNotEmpty && _kpiSelectedEmployee == null) {
          _kpiSelectedEmployee = _allEmployees.first.fullName;
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

  Future<void> _selectKpiTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _kpiSelectedTime,
    );
    if (picked != null) {
      setState(() => _kpiSelectedTime = picked);
    }
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
      // Создаем DateTime из выбранных даты и времени
      final dateTime = DateTime(
        _kpiSelectedDate.year,
        _kpiSelectedDate.month,
        _kpiSelectedDate.day,
        _kpiSelectedTime.hour,
        _kpiSelectedTime.minute,
      );

      // Находим магазин для получения координат
      final shop = _allShops.firstWhere(
        (s) => s.address == _kpiSelectedShop,
        orElse: () => _allShops.first,
      );

      // Используем координаты магазина или тестовые координаты
      final latitude = shop.latitude ?? 44.0433; // Координаты Пятигорска
      final longitude = shop.longitude ?? 43.0577;

      // Создаем отметку прихода
      final success = await AttendanceService.markAttendance(
        employeeName: _kpiSelectedEmployee!,
        shopAddress: _kpiSelectedShop!,
        latitude: latitude,
        longitude: longitude,
        distance: 0.0,
      );

      if (mounted) {
        setState(() => _creatingAttendance = false);
        if (success) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('✅ Отметка прихода создана: ${_formatDateTime(dateTime)}'),
              backgroundColor: Colors.green,
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('❌ Ошибка создания отметки прихода'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }

      return success;
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

      // Создаем DateTime из выбранных даты и времени
      final dateTime = DateTime(
        _kpiSelectedDate.year,
        _kpiSelectedDate.month,
        _kpiSelectedDate.day,
        _kpiSelectedTime.hour,
        _kpiSelectedTime.minute,
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
        createdAt: dateTime,
        answers: answers,
        isSynced: false,
      );

      // Сохраняем отчет
      await ShiftReport.saveReport(report);

      if (mounted) {
        setState(() => _creatingShift = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✅ Пересменка создана: ${_formatDateTime(dateTime)}'),
            backgroundColor: Colors.green,
          ),
        );
      }

      return true;
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

      // Выбираем 30 вопросов по алгоритму
      final selectedQuestions = RecountQuestion.selectQuestions(allQuestions);

      // Создаем DateTime из выбранных даты и времени
      final dateTime = DateTime(
        _kpiSelectedDate.year,
        _kpiSelectedDate.month,
        _kpiSelectedDate.day,
        _kpiSelectedTime.hour,
        _kpiSelectedTime.minute,
      );

      final startedAt = dateTime;
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

    // Открываем стандартную страницу создания РКО
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const RKOTypeSelectionPage(),
      ),
    );
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
                              title: Text('Заказ #${order.id.substring(order.id.length - 6)}'),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '${order.totalPrice.toStringAsFixed(0)} ₽ - ${order.status == 'completed' ? 'Выполнено' : order.status == 'rejected' ? 'Не принят' : 'Ожидает'}',
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
                    value: emp.fullName,
                    child: Text(emp.fullName),
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
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _selectKpiDate,
                        icon: const Icon(Icons.calendar_today),
                        label: Text(_formatDate(_kpiSelectedDate)),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _selectKpiTime,
                        icon: const Icon(Icons.access_time),
                        label: Text(_kpiSelectedTime.format(context)),
                      ),
                    ),
                  ],
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
