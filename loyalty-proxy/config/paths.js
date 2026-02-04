/**
 * Centralized Path Configuration
 *
 * Все пути к данным вынесены в этот файл.
 * По умолчанию используется /var/www (продакшн).
 * Для локальной разработки установите DATA_DIR=./test-data
 *
 * Использование:
 *   const { PATHS, getPath } = require('./config/paths');
 *
 *   // Вместо: '/var/www/shops'
 *   // Используй: PATHS.SHOPS
 *
 *   // Для динамических путей:
 *   // Вместо: `/var/www/employees/${id}.json`
 *   // Используй: getPath('employees', `${id}.json`)
 */

const path = require('path');

// Базовая директория данных
const DATA_DIR = process.env.DATA_DIR || '/var/www';

// Вспомогательная функция для создания путей
const p = (...segments) => path.join(DATA_DIR, ...segments);

/**
 * Все пути к директориям и файлам
 */
const PATHS = {
  // === Базовая директория ===
  DATA_DIR,

  // === Магазины ===
  SHOPS: p('shops'),
  SHOPS_JSON: p('shops', 'shops.json'),
  SHOP_SETTINGS: p('shop-settings'),
  SHOP_PRODUCTS: p('shop-products'),
  SHOP_COORDINATES: p('shop-coordinates'),
  SHOP_MANAGERS: p('shop-managers.json'),

  // === Сотрудники ===
  EMPLOYEES: p('employees'),
  EMPLOYEE_PHOTOS: p('employee-photos'),
  EMPLOYEE_REGISTRATIONS: p('employee-registrations'),
  EMPLOYEE_RATINGS: p('employee-ratings'),
  EMPLOYEE_CHATS: p('employee-chats'),

  // === Клиенты ===
  CLIENTS: p('clients'),
  CLIENT_DIALOGS: p('client-dialogs'),
  CLIENT_MESSAGES: p('client-messages'),
  CLIENT_MESSAGES_MANAGEMENT: p('client-messages-management'),
  CLIENT_MESSAGES_NETWORK: p('client-messages-network'),
  CLIENT_REVIEWS: p('client-reviews'),

  // === Посещаемость ===
  ATTENDANCE: p('attendance'),
  ATTENDANCE_PENDING: p('attendance-pending'),
  ATTENDANCE_AUTOMATION_STATE: p('attendance-automation-state'),

  // === Пересменки (Shift Reports) ===
  SHIFT_REPORTS: p('shift-reports'),
  SHIFT_PHOTOS: p('shift-photos'),
  SHIFT_QUESTIONS: p('shift-questions'),
  SHIFT_AUTOMATION_STATE: p('shift-automation-state'),
  PENDING_SHIFT_REPORTS: p('pending-shift-reports'),

  // === Сдать смену (Shift Handover) ===
  SHIFT_HANDOVERS: p('shift-handovers'),
  SHIFT_HANDOVER_REPORTS: p('shift-handover-reports'),
  SHIFT_HANDOVER_PENDING: p('shift-handover-pending'),
  SHIFT_HANDOVER_QUESTIONS: p('shift-handover-questions'),
  SHIFT_HANDOVER_QUESTION_PHOTOS: p('shift-handover-question-photos'),
  SHIFT_HANDOVER_AUTOMATION_STATE: p('shift-handover-automation-state'),
  PENDING_SHIFT_HANDOVER_REPORTS: p('pending-shift-handover-reports.json'),

  // === Передать смену (Shift Transfer) ===
  SHIFT_TRANSFERS: p('shift-transfers.json'),

  // === Пересчёты ===
  RECOUNT_REPORTS: p('recount-reports'),
  RECOUNT_QUESTIONS: p('recount-questions'),
  RECOUNT_POINTS: p('recount-points'),
  RECOUNT_SETTINGS: p('recount-settings', 'settings.json'),
  RECOUNT_AUTOMATION_STATE: p('recount-automation-state'),
  PENDING_RECOUNT_REPORTS: p('pending-recount-reports'),

  // === Конверты ===
  ENVELOPE_REPORTS: p('envelope-reports'),
  ENVELOPE_PENDING: p('envelope-pending'),
  ENVELOPE_QUESTIONS: p('envelope-questions'),
  ENVELOPE_AUTOMATION_STATE: p('envelope-automation-state'),

  // === РКО ===
  RKO: p('rko'),
  RKO_REPORTS: p('rko-reports'),
  RKO_METADATA: p('rko-reports', 'rko_metadata.json'),
  RKO_FILES: p('rko-files'),
  RKO_PENDING: p('rko-pending'),
  RKO_AUTOMATION_STATE: p('rko-automation-state'),

  // === Заказы ===
  ORDERS: p('orders'),
  ORDERS_VIEWED_REJECTED: p('orders-viewed-rejected.json'),
  ORDERS_VIEWED_UNCONFIRMED: p('orders-viewed-unconfirmed.json'),

  // === Задачи ===
  TASKS: p('tasks'),
  TASK_ASSIGNMENTS: p('task-assignments'),
  TASK_MEDIA: p('task-media'),
  TASK_POINTS_CONFIG: p('task-points-config.json'),
  RECURRING_TASKS: p('recurring-tasks'),
  RECURRING_TASK_INSTANCES: p('recurring-task-instances'),

  // === Меню и рецепты ===
  MENU: p('menu'),
  RECIPES: p('recipes'),
  RECIPE_PHOTOS: p('recipe-photos'),

  // === Обучение и тесты ===
  TRAINING_ARTICLES: p('training-articles'),
  TRAINING_ARTICLES_MEDIA: p('training-articles-media'),
  TEST_QUESTIONS: p('test-questions'),
  TEST_RESULTS: p('test-results'),

  // === Рефералы ===
  REFERRAL_CLIENTS: p('referral-clients'),
  REFERRALS_VIEWED: p('referrals-viewed.json'),
  REFERRAL_STATS_CACHE: p('cache', 'referral-stats', 'stats.json'),
  REFERRAL_ANTIFRAUD_LOG: p('logs', 'referral-antifraud.log'),

  // === Рейтинг и колесо удачи ===
  FORTUNE_WHEEL: p('fortune-wheel'),

  // === Эффективность ===
  EFFICIENCY_PENALTIES: p('efficiency-penalties'),

  // === Премии/штрафы ===
  BONUS_PENALTIES: p('bonus-penalties'),
  WITHDRAWALS: p('withdrawals'),
  MAIN_CASH: p('main_cash'),

  // === Поиск товара ===
  PRODUCT_QUESTIONS: p('product-questions'),
  PRODUCT_QUESTION_DIALOGS: p('product-question-dialogs'),
  PRODUCT_QUESTION_PHOTOS: p('product-question-photos'),
  PRODUCT_QUESTION_PENALTY_STATE: p('product-question-penalty-state'),

  // === Отзывы ===
  REVIEWS: p('reviews'),

  // === Лояльность ===
  LOYALTY_PROMO: p('loyalty-promo.json'),
  LOYALTY_TRANSACTIONS: p('loyalty-transactions'),

  // === Геофенсинг ===
  GEOFENCE_SETTINGS: p('geofence-settings.json'),
  GEOFENCE_NOTIFICATIONS: p('geofence-notifications'),

  // === Чат ===
  CHAT_MEDIA: p('chat-media'),

  // === Настройки баллов ===
  POINTS_SETTINGS: p('points-settings'),
  POINTS_ATTENDANCE: p('points-settings', 'attendance.json'),
  POINTS_ENVELOPE: p('points-settings', 'envelope_points_settings.json'),
  POINTS_RECOUNT: p('points-settings', 'recount_points_settings.json'),
  POINTS_REFERRALS: p('points-settings', 'referrals.json'),
  POINTS_SHIFT: p('points-settings', 'shift_points_settings.json'),
  POINTS_TEST: p('points-settings', 'test_points_settings.json'),

  // === Заявки на работу ===
  JOB_APPLICATIONS: p('job-applications'),

  // === Поставщики ===
  SUPPLIERS: p('suppliers'),

  // === График работы ===
  WORK_SCHEDULES: p('work-schedules'),
  WORK_SCHEDULE_TEMPLATES: p('work-schedule-templates'),

  // === Push-уведомления ===
  FCM_TOKENS: p('fcm-tokens'),
  REPORT_NOTIFICATIONS: p('report-notifications'),

  // === ИИ распознавание ===
  AI_RECOGNITION_STATS: p('ai-recognition-stats'),
  SHIFT_AI_ANNOTATIONS: p('shift-ai-annotations'),
  SHIFT_AI_SETTINGS: p('shift-ai-settings'),
  MASTER_CATALOG: p('master-catalog'),

  // === Логи ===
  APP_LOGS: p('app-logs'),
  LOGS: p('logs'),

  // === DBF синхронизация ===
  DBF_STOCKS: p('dbf-stocks'),
  DBF_API_KEYS: p('dbf-sync-settings', 'api-keys.json'),

  // === HTML/статика ===
  HTML: p('html'),

  // === Сетевые сообщения ===
  NETWORK_MESSAGES: p('network-messages'),
};

/**
 * Динамическое создание пути
 * @param {string} base - Базовый путь (ключ из PATHS или строка)
 * @param {...string} segments - Дополнительные сегменты пути
 * @returns {string} Полный путь
 *
 * @example
 * getPath('employees', 'emp_123.json')
 * // => '/var/www/employees/emp_123.json' (prod)
 * // => './test-data/employees/emp_123.json' (local)
 */
function getPath(base, ...segments) {
  const basePath = PATHS[base.toUpperCase()] || p(base);
  return path.join(basePath, ...segments);
}

/**
 * Проверка что используется локальное окружение
 */
function isLocalEnv() {
  return DATA_DIR !== '/var/www';
}

module.exports = {
  PATHS,
  getPath,
  isLocalEnv,
  DATA_DIR
};
