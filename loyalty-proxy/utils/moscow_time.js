/**
 * Moscow Time Utilities
 * Общие функции для работы с московским временем (UTC+3)
 *
 * Используется всеми шедулерами вместо локальных копий.
 */

const MOSCOW_OFFSET_HOURS = 3;

/**
 * Получить текущее время в московской таймзоне (UTC+3)
 * @returns {Date} Дата со смещением на UTC+3
 */
function getMoscowTime() {
  const now = new Date();
  return new Date(now.getTime() + MOSCOW_OFFSET_HOURS * 60 * 60 * 1000);
}

/**
 * Получить текущую дату в Москве в формате YYYY-MM-DD
 * @returns {string} Например "2026-02-17"
 */
function getMoscowDateString() {
  const moscow = getMoscowTime();
  return moscow.toISOString().split('T')[0];
}

module.exports = {
  MOSCOW_OFFSET_HOURS,
  getMoscowTime,
  getMoscowDateString
};
