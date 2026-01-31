/**
 * Pagination Utility
 * Стандартизированная пагинация для всех list endpoints
 *
 * SCALABILITY: Без пагинации возвращаются ВСЕ записи.
 * При 10,000 клиентах = 10MB+ JSON на каждый запрос
 * С пагинацией = ~100KB на страницу (100 записей)
 */

const DEFAULT_PAGE_SIZE = 50;
const MAX_PAGE_SIZE = 200;

/**
 * Парсинг параметров пагинации из query
 * @param {Object} query - req.query
 * @returns {Object} - { page, limit, offset }
 */
function parsePaginationParams(query) {
  let page = parseInt(query.page) || 1;
  let limit = parseInt(query.limit) || DEFAULT_PAGE_SIZE;

  // Защита от невалидных значений
  if (page < 1) page = 1;
  if (limit < 1) limit = DEFAULT_PAGE_SIZE;
  if (limit > MAX_PAGE_SIZE) limit = MAX_PAGE_SIZE;

  const offset = (page - 1) * limit;

  return { page, limit, offset };
}

/**
 * Применить пагинацию к массиву
 * @param {Array} items - полный массив
 * @param {Object} query - req.query с page/limit
 * @returns {Object} - { items, pagination }
 */
function paginateArray(items, query) {
  const { page, limit, offset } = parsePaginationParams(query);
  const total = items.length;
  const totalPages = Math.ceil(total / limit);

  const paginatedItems = items.slice(offset, offset + limit);

  return {
    items: paginatedItems,
    pagination: {
      page,
      limit,
      total,
      totalPages,
      hasNextPage: page < totalPages,
      hasPrevPage: page > 1
    }
  };
}

/**
 * Формирование ответа с пагинацией
 * @param {Array} items - массив для пагинации
 * @param {Object} query - req.query
 * @param {string} itemsKey - ключ для массива в ответе (напр. 'clients')
 * @returns {Object} - готовый объект для res.json()
 */
function createPaginatedResponse(items, query, itemsKey = 'items') {
  const { items: paginatedItems, pagination } = paginateArray(items, query);

  return {
    success: true,
    [itemsKey]: paginatedItems,
    pagination
  };
}

/**
 * Проверить, нужна ли пагинация (есть параметры page/limit)
 * @param {Object} query - req.query
 * @returns {boolean}
 */
function isPaginationRequested(query) {
  return query.page !== undefined || query.limit !== undefined;
}

module.exports = {
  parsePaginationParams,
  paginateArray,
  createPaginatedResponse,
  isPaginationRequested,
  DEFAULT_PAGE_SIZE,
  MAX_PAGE_SIZE
};
