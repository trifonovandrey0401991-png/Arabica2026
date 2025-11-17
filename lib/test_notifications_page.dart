import 'package:flutter/material.dart';
import 'order_provider.dart';
import 'notification_service.dart';
import 'employees_page.dart';
import 'cart_provider.dart';
import 'menu_page.dart';

/// Тестовая страница для проверки уведомлений и принятия заказов
class TestNotificationsPage extends StatefulWidget {
  const TestNotificationsPage({super.key});

  @override
  State<TestNotificationsPage> createState() => _TestNotificationsPageState();
}

class _TestNotificationsPageState extends State<TestNotificationsPage> {
  String? _selectedEmployee;
  List<Employee> _employees = [];
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _loadEmployees();
  }

  Future<void> _loadEmployees() async {
    setState(() => _loading = true);
    try {
      final employees = await EmployeesPage.loadEmployeesForNotifications();
      setState(() {
        _employees = employees;
        _loading = false;
      });
    } catch (e) {
      setState(() => _loading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка загрузки сотрудников: $e')),
        );
      }
    }
  }

  Future<void> _createTestOrder() async {
    if (!mounted) return;
    final orderProvider = OrderProvider.of(context);
    
    // Создаем тестовый заказ
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

    // Отправляем уведомления
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Тест уведомлений'),
        backgroundColor: const Color(0xFF004D40),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Информация
            Card(
              color: Colors.blue[50],
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '📋 Инструкция по тестированию:',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Text('1. Нажмите "Создать тестовый заказ"'),
                    const Text('2. Проверьте, что пришло уведомление'),
                    const Text('3. Нажмите на уведомление (или используйте кнопку ниже)'),
                    const Text('4. Выберите сотрудника и примите/откажитесь от заказа'),
                    const Text('5. При отказе укажите причину и отправьте'),
                    const Text('6. Проверьте страницу "Мои заказы"'),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),

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
                    if (_loading)
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
            const SizedBox(height: 20),

            // Кнопка создания тестового заказа
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

            // Кнопка принятия заказа
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
            // Кнопка отказа от заказа
            ElevatedButton.icon(
              onPressed: _testRejectOrder,
              icon: const Icon(Icons.cancel),
              label: const Text('Отказаться от заказа (тест)'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
            ),
            const SizedBox(height: 20),

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
                                if (order.rejectionReason != null)
                                  Text(
                                    'Причина: ${order.rejectionReason}',
                                    style: const TextStyle(fontSize: 11, color: Colors.red),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
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
            const SizedBox(height: 20),

            // Кнопка открытия уведомления вручную
            OutlinedButton.icon(
              onPressed: () async {
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

                final order = orderProvider.orders.first;
                await NotificationService.showAcceptOrderDialog(
                  context,
                  order,
                  _selectedEmployee ?? 'Тестовый сотрудник',
                );
              },
              icon: const Icon(Icons.notifications_active),
              label: const Text('Открыть диалог принятия заказа'),
            ),
          ],
        ),
      ),
    );
  }
}

