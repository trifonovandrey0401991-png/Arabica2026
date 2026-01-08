/// Тестовые данные для Integration тестов

class TestData {
  // Тестовый пользователь (клиент)
  static const String testClientPhone = '79054443224';
  static const String testClientName = 'Андрей В';

  // Тестовый сотрудник
  static const String testEmployeeName = 'Тестовый Сотрудник';

  // Тестовый магазин
  static const String testShopAddress = 'Лермонтов,Комсомольская 1 (На Площади)';

  // Причина отказа для тестов
  static const String testRejectionReason = 'Тестовый отказ - товар закончился';

  // Таймауты
  static const Duration shortWait = Duration(milliseconds: 500);
  static const Duration mediumWait = Duration(seconds: 2);
  static const Duration longWait = Duration(seconds: 5);
  static const Duration apiWait = Duration(seconds: 10);

  // Тексты для поиска в UI
  static const String menuButtonText = 'Меню';
  static const String myOrdersButtonText = 'Мои заказы';
  static const String clientOrdersButtonText = 'Заказы (Клиенты)';
  static const String cartButtonText = 'Корзина';

  // Тексты вкладок
  static const String pendingTabText = 'Ожидают';
  static const String completedTabText = 'Выполненные';
  static const String rejectedTabText = 'Отказано';

  // Тексты кнопок действий
  static const String acceptOrderText = 'Принять заказ';
  static const String rejectOrderText = 'Отклонить';
  static const String confirmText = 'Подтвердить';
  static const String cancelText = 'Отмена';
  static const String placeOrderText = 'Оформить заказ';

  // Тексты сообщений
  static const String orderCreatedText = 'Заказ создан';
  static const String orderAcceptedText = 'принят';
  static const String orderRejectedText = 'отклонён';
}
