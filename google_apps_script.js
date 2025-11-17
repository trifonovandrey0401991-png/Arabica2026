/**
 * Google Apps Script для управления программой лояльности.
 *
 * Структура листа "Лист11":
 *  A: Имя клиента
 *  B: Номер телефона
 *  C: QR клиента
 *  D: Бесплатные напитки
 *  E: Описание акции (используется значение из ячейки E1)
 *  F: Баллы
 */

const SPREADSHEET_ID = '1n7E3sph8x_FanomlEuEeG5a0OMWSz9UXNlIjXAr19MU';
const SHEET_NAME = 'Лист11';
const HEADER_ROW = ['Имя клиента', 'Номер телефона', 'QR', 'Бесплатные напитки', '', 'Баллы'];
const COLS = {
  NAME: 1,
  PHONE: 2,
  QR: 3,
  FREE_DRINKS: 4,
  PROMO: 5,
  POINTS: 6,
};

function doPost(e) {
  const data = e.postData && e.postData.contents ? JSON.parse(e.postData.contents) : {};
  const action = (data.action || 'register').toLowerCase();

  switch (action) {
    case 'register':
      return registerClient(data);
    case 'addpoint':
      return addPoint(data);
    case 'redeem':
      return redeemClient(data);
    default:
      return buildResponse({ success: false, error: `Unknown action: ${action}` });
  }
}

/**
 * Обработка preflight-запросов (OPTIONS) для CORS
 */
function doOptions() {
  return ContentService
    .createTextOutput('')
    .setMimeType(ContentService.MimeType.TEXT);
}

function doGet(e) {
  const action = (e.parameter.action || 'getclient').toLowerCase();

  switch (action) {
    case 'getclient':
      return getClient(e.parameter);
    default:
      return buildResponse({ success: false, error: `Unknown GET action: ${action}` });
  }
}

/**
 * Регистрация клиента
 */
function registerClient(payload) {
  const name = (payload.name || '').trim();
  const phone = (payload.phone || '').trim();
  const qr = (payload.qr || '').trim();

  if (!name || !phone || !qr) {
    return buildResponse({ success: false, error: 'Заполните имя, телефон и QR' });
  }

  const sheet = getSheet();
  ensureStructure(sheet);

  const rowIndex = findRow(sheet, COLS.PHONE, phone) || findRow(sheet, COLS.QR, qr);
  const values = [
    name,
    phone,
    qr,
    Number(payload.freeDrinks || 0),
    '', // Описание акции для клиентов берём из E1, а в строке оставляем пустым
    Number(payload.points || 0),
  ];

  if (rowIndex) {
    sheet.getRange(rowIndex, 1, 1, HEADER_ROW.length).setValues([values]);
  } else {
    sheet.appendRow(values);
  }

  return buildResponse({ success: true, client: buildClientResponse(sheet, rowIndex || sheet.getLastRow()) });
}

/**
 * Добавление балла клиенту
 */
function addPoint(payload) {
  const qr = (payload.qr || '').trim();
  if (!qr) {
    return buildResponse({ success: false, error: 'QR не передан' });
  }

  const sheet = getSheet();
  ensureStructure(sheet);
  const rowIndex = findRow(sheet, COLS.QR, qr);
  if (!rowIndex) {
    return buildResponse({ success: false, error: 'Клиент не найден' });
  }

  const currentPoints = Number(sheet.getRange(rowIndex, COLS.POINTS).getValue()) || 0;
  const newPoints = Math.min(currentPoints + 1, 10);
  sheet.getRange(rowIndex, COLS.POINTS).setValue(newPoints);

  return buildResponse({
    success: true,
    client: buildClientResponse(sheet, rowIndex),
  });
}

/**
 * Списание баллов и выдача бесплатного напитка
 */
function redeemClient(payload) {
  const qr = (payload.qr || '').trim();
  if (!qr) {
    return buildResponse({ success: false, error: 'QR не передан' });
  }

  const sheet = getSheet();
  ensureStructure(sheet);
  const rowIndex = findRow(sheet, COLS.QR, qr);
  if (!rowIndex) {
    return buildResponse({ success: false, error: 'Клиент не найден' });
  }

  const currentFree = Number(sheet.getRange(rowIndex, COLS.FREE_DRINKS).getValue()) || 0;
  sheet.getRange(rowIndex, COLS.FREE_DRINKS).setValue(currentFree + 1);
  sheet.getRange(rowIndex, COLS.POINTS).setValue(0);

  return buildResponse({
    success: true,
    client: buildClientResponse(sheet, rowIndex),
  });
}

/**
 * Получение клиента по телефону или QR
 */
function getClient(params) {
  const phone = params.phone ? params.phone.trim() : '';
  const qr = params.qr ? params.qr.trim() : '';

  if (!phone && !qr) {
    return buildResponse({ success: false, error: 'Передайте номер телефона или QR' });
  }

  const sheet = getSheet();
  ensureStructure(sheet);
  const rowIndex = phone
    ? findRow(sheet, COLS.PHONE, phone)
    : findRow(sheet, COLS.QR, qr);

  if (!rowIndex) {
    return buildResponse({ success: false, error: 'Клиент не найден' });
  }

  return buildResponse({
    success: true,
    client: buildClientResponse(sheet, rowIndex),
  });
}

/**
 * Вспомогательные функции
 */
function getSheet() {
  const ss = SpreadsheetApp.openById(SPREADSHEET_ID);
  let sheet = ss.getSheetByName(SHEET_NAME);

  if (!sheet) {
    sheet = ss.insertSheet(SHEET_NAME);
  }

  return sheet;
}

function ensureStructure(sheet) {
  if (sheet.getMaxColumns() < HEADER_ROW.length) {
    sheet.insertColumnsAfter(sheet.getMaxColumns(), HEADER_ROW.length - sheet.getMaxColumns());
  }

  if (sheet.getLastRow() === 0) {
    sheet.appendRow(HEADER_ROW);
  }
}

function findRow(sheet, columnIndex, value) {
  if (!value) {
    return null;
  }

  const lastRow = sheet.getLastRow();
  if (lastRow <= 1) {
    return null;
  }

  const range = sheet.getRange(2, columnIndex, lastRow - 1, 1);
  const values = range.getValues();
  for (let i = 0; i < values.length; i++) {
    if (String(values[i][0]).trim() === value) {
      return i + 2; // учитываем заголовок
    }
  }

  return null;
}

function buildClientResponse(sheet, rowIndex) {
  const rowValues = sheet.getRange(rowIndex, 1, 1, HEADER_ROW.length).getValues()[0];
  const promoText = sheet.getRange(1, COLS.PROMO).getValue() || '';
  const points = Number(rowValues[COLS.POINTS - 1]) || 0;
  const freeDrinks = Number(rowValues[COLS.FREE_DRINKS - 1]) || 0;

  return {
    name: rowValues[COLS.NAME - 1] || '',
    phone: rowValues[COLS.PHONE - 1] || '',
    qr: rowValues[COLS.QR - 1] || '',
    freeDrinks,
    points,
    promoText,
    readyForRedeem: points >= 10,
  };
}

function buildResponse(payload) {
  return ContentService
    .createTextOutput(JSON.stringify(payload))
    .setMimeType(ContentService.MimeType.JSON);
}
