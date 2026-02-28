/**
 * Database Access Module (PostgreSQL)
 *
 * Единый модуль для работы с PostgreSQL.
 * Все API-файлы импортируют только этот модуль.
 *
 * API спроектирован как замена файловых операций:
 *   readJsonFile   → db.findById(table, id)
 *   readJsonDirectory → db.findAll(table, filters, options)
 *   writeJsonFile  → db.upsert(table, data, conflictColumn)
 *   fsp.unlink     → db.deleteById(table, id)
 *   withLock + read-modify-write → db.transaction(callback)
 *
 * Создано: 2026-02-17
 */

const { Pool } = require('pg');

// ============================================
// CONNECTION POOL
// ============================================

const pool = new Pool({
  user: process.env.DB_USER || 'arabica_app',
  password: process.env.DB_PASSWORD || undefined, // peer auth на сервере, пароль из env
  host: process.env.DB_HOST || 'localhost',
  database: process.env.DB_NAME || 'arabica_db',
  port: parseInt(process.env.DB_PORT, 10) || 5432,
  max: parseInt(process.env.DB_POOL_MAX, 10) || 20, // 9 шедулеров + API запросы
  idleTimeoutMillis: 30000,   // закрыть idle соединение через 30 сек
  connectionTimeoutMillis: 5000
});

// Логирование ошибок пула (не должны убивать процесс)
pool.on('error', (err) => {
  console.error('[DB] Pool error:', err.message);
});

// ============================================
// БАЗОВЫЕ ОПЕРАЦИИ
// ============================================

/**
 * Выполнить SQL-запрос
 * @param {string} text - SQL-запрос с $1, $2, ... плейсхолдерами
 * @param {Array} params - параметры
 * @returns {Promise<pg.Result>}
 */
async function query(text, params = []) {
  const start = Date.now();
  try {
    const result = await pool.query(text, params);
    const elapsed = Date.now() - start;
    if (elapsed > 1000) {
      console.warn(`[DB] Slow query (${elapsed}ms): ${text.substring(0, 100)}`);
    }
    return result;
  } catch (err) {
    console.error(`[DB] Query error: ${err.message}\n  SQL: ${text.substring(0, 200)}\n  Params: ${JSON.stringify(params).substring(0, 200)}`);
    throw err;
  }
}

/**
 * Получить запись по ID
 * Аналог: readJsonFile(path.join(dir, id + '.json'))
 *
 * @param {string} table - имя таблицы
 * @param {string} id - значение primary key
 * @param {string} idColumn - имя колонки PK (default: 'id')
 * @returns {Promise<Object|null>}
 */
async function findById(table, id, idColumn = 'id') {
  const result = await query(
    `SELECT * FROM ${escapeTable(table)} WHERE ${escapeColumn(idColumn)} = $1 LIMIT 1`,
    [id]
  );
  return result.rows[0] || null;
}

/**
 * Получить все записи с фильтрацией и пагинацией
 * Аналог: readJsonDirectory(dir) + filter + sort
 *
 * @param {string} table - имя таблицы
 * @param {Object} options
 * @param {Object} options.filters - { column: value } для WHERE
 * @param {string} options.orderBy - колонка для сортировки (default: 'created_at')
 * @param {string} options.orderDir - 'ASC' или 'DESC' (default: 'DESC')
 * @param {number} options.limit - лимит записей
 * @param {number} options.offset - сдвиг
 * @param {string} options.where - дополнительный WHERE clause (с $N плейсхолдерами)
 * @param {Array} options.whereParams - параметры для where clause
 * @returns {Promise<Array<Object>>}
 */
async function findAll(table, options = {}) {
  const {
    filters = {},
    orderBy = 'created_at',
    orderDir = 'DESC',
    limit = null,
    offset = null,
    where = null,
    whereParams = []
  } = options;

  const conditions = [];
  const params = [];
  let paramIndex = 1;

  // Фильтры: { column: value }
  for (const [col, val] of Object.entries(filters)) {
    if (val === null) {
      conditions.push(`${escapeColumn(col)} IS NULL`);
    } else if (Array.isArray(val)) {
      conditions.push(`${escapeColumn(col)} = ANY($${paramIndex})`);
      params.push(val);
      paramIndex++;
    } else {
      conditions.push(`${escapeColumn(col)} = $${paramIndex}`);
      params.push(val);
      paramIndex++;
    }
  }

  // Дополнительный WHERE (для сложных условий)
  if (where) {
    // Перенумеровать плейсхолдеры в where clause
    // Negative lookahead (?!\d) prevents $1 from matching inside $10, $11, etc.
    let adjustedWhere = where;
    for (let i = whereParams.length; i >= 1; i--) {
      adjustedWhere = adjustedWhere.replace(
        new RegExp(`\\$${i}(?!\\d)`, 'g'),
        `$${paramIndex + i - 1}`
      );
    }
    conditions.push(`(${adjustedWhere})`);
    params.push(...whereParams);
    paramIndex += whereParams.length;
  }

  const whereClause = conditions.length > 0
    ? 'WHERE ' + conditions.join(' AND ')
    : '';

  // Валидация orderDir
  const dir = orderDir.toUpperCase() === 'ASC' ? 'ASC' : 'DESC';

  let sql = `SELECT * FROM ${escapeTable(table)} ${whereClause} ORDER BY ${escapeColumn(orderBy)} ${dir}`;

  // Safety cap: never return more than 10 000 rows without explicit limit.
  // Prevents accidental memory exhaustion on large tables. Callers that legitimately
  // need more rows should pass an explicit limit or use pagination via findAllPaginated().
  const effectiveLimit = limit !== null ? limit : 10000;
  sql += ` LIMIT $${paramIndex}`;
  params.push(effectiveLimit);
  paramIndex++;

  if (offset !== null) {
    sql += ` OFFSET $${paramIndex}`;
    params.push(offset);
    paramIndex++;
  }

  const result = await query(sql, params);
  if (limit === null && result.rows.length >= 10000) {
    console.warn(`[DB] findAll('${table}') hit the 10 000-row safety cap. Consider adding pagination.`);
  }
  return result.rows;
}

/**
 * Подсчёт записей
 * @param {string} table
 * @param {Object} filters - { column: value }
 * @returns {Promise<number>}
 */
async function count(table, filters = {}) {
  const conditions = [];
  const params = [];
  let paramIndex = 1;

  for (const [col, val] of Object.entries(filters)) {
    if (val === null) {
      conditions.push(`${escapeColumn(col)} IS NULL`);
    } else {
      conditions.push(`${escapeColumn(col)} = $${paramIndex}`);
      params.push(val);
      paramIndex++;
    }
  }

  const whereClause = conditions.length > 0
    ? 'WHERE ' + conditions.join(' AND ')
    : '';

  const result = await query(
    `SELECT COUNT(*) as cnt FROM ${escapeTable(table)} ${whereClause}`,
    params
  );
  return parseInt(result.rows[0].cnt, 10);
}

/**
 * Получить записи с пагинацией + общее число записей
 * Выполняет COUNT(*) и SELECT LIMIT/OFFSET параллельно
 *
 * @param {string} table
 * @param {Object} options - все опции findAll + page/pageSize
 * @param {number} options.page - номер страницы (1-based, default 1)
 * @param {number} options.pageSize - записей на страницу (default 50, max 200)
 * @returns {Promise<{rows, total, page, pageSize, totalPages, hasNextPage, hasPrevPage}>}
 */
async function findAllPaginated(table, options = {}) {
  const {
    page = 1,
    pageSize = 50,
    ...findOptions
  } = options;

  const safePage = Math.max(page, 1);
  const safePageSize = Math.min(Math.max(pageSize, 1), 200);
  const offset = (safePage - 1) * safePageSize;

  // Parallel: count total + fetch one page
  const [total, rows] = await Promise.all([
    _countWithWhere(table, findOptions),
    findAll(table, { ...findOptions, limit: safePageSize, offset }),
  ]);

  const totalPages = Math.ceil(total / safePageSize);

  return {
    rows,
    total,
    page: safePage,
    pageSize: safePageSize,
    totalPages,
    hasNextPage: safePage < totalPages,
    hasPrevPage: safePage > 1,
  };
}

/**
 * Подсчёт записей с поддержкой where/whereParams (для findAllPaginated)
 * @private
 */
async function _countWithWhere(table, options = {}) {
  const { filters = {}, where = null, whereParams = [] } = options;

  const conditions = [];
  const params = [];
  let paramIndex = 1;

  for (const [col, val] of Object.entries(filters)) {
    if (val === null) {
      conditions.push(`${escapeColumn(col)} IS NULL`);
    } else if (Array.isArray(val)) {
      conditions.push(`${escapeColumn(col)} = ANY($${paramIndex})`);
      params.push(val);
      paramIndex++;
    } else {
      conditions.push(`${escapeColumn(col)} = $${paramIndex}`);
      params.push(val);
      paramIndex++;
    }
  }

  if (where) {
    let adjustedWhere = where;
    for (let i = whereParams.length; i >= 1; i--) {
      adjustedWhere = adjustedWhere.replace(
        new RegExp(`\\$${i}(?!\\d)`, 'g'),
        `$${paramIndex + i - 1}`
      );
    }
    conditions.push(`(${adjustedWhere})`);
    params.push(...whereParams);
  }

  const whereClause = conditions.length > 0
    ? 'WHERE ' + conditions.join(' AND ')
    : '';

  const result = await query(
    `SELECT COUNT(*) as cnt FROM ${escapeTable(table)} ${whereClause}`,
    params
  );
  return parseInt(result.rows[0].cnt, 10);
}

/**
 * Вставить или обновить запись (UPSERT)
 * Аналог: writeJsonFile(path.join(dir, id + '.json'), data)
 *
 * @param {string} table - имя таблицы
 * @param {Object} data - объект с данными { column: value }
 * @param {string} conflictColumn - колонка для ON CONFLICT (default: 'id')
 * @returns {Promise<Object>} - вставленная/обновлённая запись
 */
async function upsert(table, data, conflictColumn = 'id') {
  const columns = Object.keys(data);
  const values = Object.values(data);
  const placeholders = columns.map((_, i) => `$${i + 1}`);

  // ON CONFLICT → UPDATE все колонки кроме конфликтной
  const updateColumns = columns.filter(c => c !== conflictColumn);
  const updateSet = updateColumns.map(
    (col) => `${escapeColumn(col)} = EXCLUDED.${escapeColumn(col)}`
  );

  let sql;
  if (updateSet.length > 0) {
    sql = `INSERT INTO ${escapeTable(table)} (${columns.map(escapeColumn).join(', ')})
           VALUES (${placeholders.join(', ')})
           ON CONFLICT (${escapeColumn(conflictColumn)})
           DO UPDATE SET ${updateSet.join(', ')}
           RETURNING *`;
  } else {
    sql = `INSERT INTO ${escapeTable(table)} (${columns.map(escapeColumn).join(', ')})
           VALUES (${placeholders.join(', ')})
           ON CONFLICT (${escapeColumn(conflictColumn)}) DO NOTHING
           RETURNING *`;
  }

  const result = await query(sql, values);
  return result.rows[0] || null;
}

/**
 * Вставить запись (без upsert, просто INSERT)
 * @param {string} table
 * @param {Object} data
 * @returns {Promise<Object>}
 */
async function insert(table, data) {
  const columns = Object.keys(data);
  const values = Object.values(data);
  const placeholders = columns.map((_, i) => `$${i + 1}`);

  const sql = `INSERT INTO ${escapeTable(table)} (${columns.map(escapeColumn).join(', ')})
               VALUES (${placeholders.join(', ')})
               RETURNING *`;

  const result = await query(sql, values);
  return result.rows[0];
}

/**
 * Обновить запись по ID
 * @param {string} table
 * @param {string} id
 * @param {Object} data - поля для обновления
 * @param {string} idColumn
 * @returns {Promise<Object|null>}
 */
async function updateById(table, id, data, idColumn = 'id') {
  const columns = Object.keys(data);
  if (columns.length === 0) return findById(table, id, idColumn);

  const values = Object.values(data);
  const setClause = columns.map(
    (col, i) => `${escapeColumn(col)} = $${i + 1}`
  ).join(', ');

  const result = await query(
    `UPDATE ${escapeTable(table)} SET ${setClause} WHERE ${escapeColumn(idColumn)} = $${columns.length + 1} RETURNING *`,
    [...values, id]
  );
  return result.rows[0] || null;
}

/**
 * Удалить запись по ID
 * Аналог: fsp.unlink(path.join(dir, id + '.json'))
 *
 * @param {string} table
 * @param {string} id
 * @param {string} idColumn
 * @returns {Promise<boolean>} - true если удалена
 */
async function deleteById(table, id, idColumn = 'id') {
  const result = await query(
    `DELETE FROM ${escapeTable(table)} WHERE ${escapeColumn(idColumn)} = $1`,
    [id]
  );
  return result.rowCount > 0;
}

/**
 * Удалить записи по фильтру
 * @param {string} table
 * @param {Object} filters - { column: value }
 * @returns {Promise<number>} - количество удалённых
 */
async function deleteWhere(table, filters) {
  const conditions = [];
  const params = [];
  let paramIndex = 1;

  for (const [col, val] of Object.entries(filters)) {
    if (val === null || val === undefined) {
      // SQL: "col = NULL" never matches — must use IS NULL
      conditions.push(`${escapeColumn(col)} IS NULL`);
    } else {
      conditions.push(`${escapeColumn(col)} = $${paramIndex}`);
      params.push(val);
      paramIndex++;
    }
  }

  if (conditions.length === 0) {
    throw new Error('deleteWhere requires at least one filter');
  }

  const result = await query(
    `DELETE FROM ${escapeTable(table)} WHERE ${conditions.join(' AND ')}`,
    params
  );
  return result.rowCount;
}

// ============================================
// ТРАНЗАКЦИИ (замена withLock)
// ============================================

/**
 * Выполнить операцию в транзакции
 * Аналог: withLock(filePath, async () => { read → modify → write })
 *
 * @param {Function} callback - async (client) => { ... }
 *   client имеет те же методы: client.query(text, params)
 * @returns {Promise<*>} - результат callback
 */
async function transaction(callback) {
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    const result = await callback(client);
    await client.query('COMMIT');
    return result;
  } catch (err) {
    await client.query('ROLLBACK');
    throw err;
  } finally {
    client.release();
  }
}

// ============================================
// УТИЛИТЫ
// ============================================

/**
 * Проверка подключения к БД
 * @returns {Promise<Object>}
 */
async function healthCheck() {
  const start = Date.now();
  const result = await query('SELECT NOW() as time, pg_database_size($1) as db_size', ['arabica_db']);
  const elapsed = Date.now() - start;
  const row = result.rows[0];
  return {
    connected: true,
    responseTime: elapsed,
    serverTime: row.time,
    dbSizeMB: Math.round(row.db_size / 1024 / 1024 * 100) / 100,
    pool: {
      total: pool.totalCount,
      idle: pool.idleCount,
      waiting: pool.waitingCount
    }
  };
}

/**
 * Получить статистику пула соединений
 * @returns {Object}
 */
function getPoolStats() {
  return {
    total: pool.totalCount,
    idle: pool.idleCount,
    waiting: pool.waitingCount
  };
}

/**
 * Graceful shutdown — закрыть все соединения
 * Вызывать из index.js при SIGTERM
 */
async function close() {
  console.log('[DB] Closing connection pool...');
  await pool.end();
  console.log('[DB] Pool closed');
}

// ============================================
// БЕЗОПАСНОСТЬ: экранирование имён таблиц/колонок
// ============================================

// Whitelist допустимых символов в именах
const SAFE_IDENTIFIER = /^[a-z_][a-z0-9_]*$/;

function escapeTable(name) {
  if (!SAFE_IDENTIFIER.test(name)) {
    throw new Error(`Invalid table name: ${name}`);
  }
  return `"${name}"`;
}

function escapeColumn(name) {
  if (!SAFE_IDENTIFIER.test(name)) {
    throw new Error(`Invalid column name: ${name}`);
  }
  return `"${name}"`;
}

// ============================================
// EXPORTS
// ============================================

module.exports = {
  // Базовые CRUD
  query,
  findById,
  findAll,
  findAllPaginated,
  count,
  upsert,
  insert,
  updateById,
  deleteById,
  deleteWhere,

  // Транзакции
  transaction,

  // Утилиты
  healthCheck,
  getPoolStats,
  close,

  // Прямой доступ к пулу (для сложных случаев)
  pool
};
