import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../shared/providers/order_provider.dart';
import '../../features/employees/pages/employees_page.dart';
import '../../features/employees/services/user_role_service.dart';
import '../utils/logger.dart';

/// Сервис для работы с уведомлениями
class NotificationService {
  static final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();

  static bool _initialized = false;

  /// Инициализация уведомлений
  static Future<void> initialize() async {
    if (_initialized) return;

    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    const initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _notifications.initialize(
      initSettings,
      onDidReceiveNotificationResponse: _onNotificationTapped,
    );

    _initialized = true;
  }

  static BuildContext? _globalContext;

  /// Установить глобальный контекст для обработки уведомлений
  static void setGlobalContext(BuildContext context) {
    _globalContext = context;
  }

  /// Обработка нажатия на уведомление
  static void _onNotificationTapped(NotificationResponse response) async {
    if (response.payload != null && _globalContext != null) {
      final orderId = response.payload!;
      final orderProvider = OrderProvider.of(_globalContext!);
      final order = orderProvider.orders.firstWhere(
        (o) => o.id == orderId,
        orElse: () => orderProvider.orders.first,
      );

      // Используем текущего пользователя (из роли или имени)
      final employeeName = await _getCurrentEmployeeName();
      if (_globalContext != null && _globalContext!.mounted) {
        await showAcceptOrderDialog(_globalContext!, order, employeeName);
      }
    }
  }

  /// Получить имя текущего сотрудника
  static Future<String> _getCurrentEmployeeName() async {
    try {
      // Сначала пытаемся получить из роли
      final prefs = await SharedPreferences.getInstance();
      final phone = prefs.getString('user_phone');
      
      if (phone != null && phone.isNotEmpty) {
        try {
          final roleData = await UserRoleService.getUserRole(phone);
          if (roleData.displayName.isNotEmpty) {
            return roleData.displayName;
          }
        } catch (e) {
          Logger.debug("⚠️ Ошибка получения роли: $e");
        }
      }

      // Если не получилось, используем сохраненное имя
      final name = prefs.getString('user_name');
      return name ?? 'Сотрудник';
    } catch (e) {
      Logger.debug("⚠️ Ошибка получения имени сотрудника: $e");
      return 'Сотрудник';
    }
  }

  /// Отправить уведомление о новом заказе всем сотрудникам
  static Future<void> notifyNewOrder(
    BuildContext context,
    Order order,
    List<Employee> employees,
  ) async {
    await initialize();

    // Загружаем список сотрудников если не передан
    List<Employee> employeesList = employees;
    if (employeesList.isEmpty) {
      // Для простоты используем локальное уведомление
      // В реальном приложении можно использовать Firebase Cloud Messaging
      if (context.mounted) {
        await _showLocalNotification(context, order);
      }
    } else {
      // Отправляем уведомление каждому сотруднику
      for (var employee in employeesList) {
        if (context.mounted) {
          await _showNotificationToEmployee(context, order, employee.name);
        }
      }
    }
  }

  /// Показать локальное уведомление
  static Future<void> _showLocalNotification(
    BuildContext context,
    Order order,
  ) async {
    const androidDetails = AndroidNotificationDetails(
      'orders_channel',
      'Заказы',
      channelDescription: 'Уведомления о новых заказах',
      importance: Importance.high,
      priority: Priority.high,
      showWhen: true,
    );

    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    const notificationDetails = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await _notifications.show(
      order.id.hashCode,
      'Новый заказ!',
      'Заказ #${order.id.substring(order.id.length - 6)} на сумму ${order.totalPrice.toStringAsFixed(0)} руб',
      notificationDetails,
      payload: order.id,
    );
  }

  /// Показать уведомление конкретному сотруднику
  static Future<void> _showNotificationToEmployee(
    BuildContext context,
    Order order,
    String employeeName,
  ) async {
    await _showLocalNotification(context, order);
  }

  /// Показать диалог принятия заказа
  static Future<void> showAcceptOrderDialog(
    BuildContext context,
    Order order,
    String employeeName,
  ) async {
    return showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(15),
        ),
        title: const Text('Принять заказ?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Заказ #${order.id.substring(order.id.length - 6)}'),
            const SizedBox(height: 8),
            Text('Сумма: ${order.totalPrice.toStringAsFixed(0)} руб'),
            if (order.comment != null && order.comment!.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text('Комментарий: ${order.comment}'),
            ],
            const SizedBox(height: 16),
            const Text(
              'Вы принимаете этот заказ?',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Отмена'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(dialogContext).pop();
              showRejectOrderDialog(context, order, employeeName);
            },
            style: TextButton.styleFrom(
              foregroundColor: Colors.red,
            ),
            child: const Text('Отказаться'),
          ),
          ElevatedButton(
            onPressed: () {
              final orderProvider = OrderProvider.of(context);
              orderProvider.acceptOrder(order.id, employeeName);
              Navigator.of(dialogContext).pop();
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Заказ принят сотрудником $employeeName'),
                  backgroundColor: const Color(0xFF004D40),
                ),
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF004D40),
            ),
            child: const Text('Принять заказ'),
          ),
        ],
      ),
    );
  }

  /// Показать диалог отказа от заказа
  static Future<void> showRejectOrderDialog(
    BuildContext context,
    Order order,
    String employeeName,
  ) async {
    final TextEditingController reasonController = TextEditingController();

    return showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(15),
        ),
        title: const Text('Отказ от заказа'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Заказ #${order.id.substring(order.id.length - 6)}'),
            const SizedBox(height: 16),
            const Text(
              'Укажите причину отказа:',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: reasonController,
              maxLines: 4,
              decoration: InputDecoration(
                hintText: 'Введите причину отказа...',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Отмена'),
          ),
          ElevatedButton(
            onPressed: () {
              final reason = reasonController.text.trim();
              if (reason.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Пожалуйста, укажите причину отказа'),
                    backgroundColor: Colors.red,
                  ),
                );
                return;
              }

              final orderProvider = OrderProvider.of(context);
              orderProvider.rejectOrder(order.id, employeeName, reason);
              
              // Отправляем уведомление клиенту
              _notifyClientAboutRejection(context, order, reason);
              
              Navigator.of(dialogContext).pop();
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Заказ отклонен. Клиент уведомлен.'),
                  backgroundColor: Colors.orange,
                ),
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
            ),
            child: const Text('Отправить'),
          ),
        ],
      ),
    );
  }

  /// Отправить уведомление клиенту об отказе от заказа
  static Future<void> _notifyClientAboutRejection(
    BuildContext context,
    Order order,
    String reason,
  ) async {
    await initialize();

    const androidDetails = AndroidNotificationDetails(
      'orders_channel',
      'Заказы',
      channelDescription: 'Уведомления о заказах',
      importance: Importance.high,
      priority: Priority.high,
      showWhen: true,
    );

    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    const notificationDetails = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await _notifications.show(
      'rejected_${order.id}'.hashCode,
      'Заказ отклонен',
      'К сожалению, мы не можем принять ваш заказ по причине: $reason',
      notificationDetails,
      payload: 'rejected_${order.id}',
    );
  }
}

