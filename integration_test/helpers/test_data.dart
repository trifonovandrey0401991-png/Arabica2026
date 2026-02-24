/// Тестовые данные для Integration тестов
///
/// Тестовые аккаунты созданы на сервере arabica26.ru
/// Все используют PIN: 1111

class TestData {
  // === ТЕСТОВЫЕ АККАУНТЫ (4 роли) ===

  // Клиент — видит меню, заказы, лояльность
  static const String clientPhone = '79000001111';
  static const String clientName = 'Тест Клиент';

  // Сотрудник — видит смены, задачи, чат, рецепты
  static const String employeePhone = '79000002222';
  static const String employeeName = 'Тест Сотрудник';

  // Управляющий (admin) — видит свои магазины, сотрудников, отчёты
  static const String adminPhone = '79000003333';
  static const String adminName = 'Тест Управляющий';

  // Разработчик (developer) — видит ВСЕ магазины, управление сетью
  static const String developerPhone = '79000004444';
  static const String developerName = 'Тест Разработчик';

  // PIN-код для всех тестовых аккаунтов
  static const String testPin = '1111';

  // Реальный аккаунт (для обратной совместимости)
  static const String testClientPhone = '79054443224';
  static const String testClientName = 'Андрей В';

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
