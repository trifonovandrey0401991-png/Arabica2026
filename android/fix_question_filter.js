const fs = require('fs');
let code = fs.readFileSync('index.js', 'utf8');

// Ищем старую логику фильтрации
const oldFilter = `// Фильтр по магазину, если указан
        if (req.query.shopAddress) {
          if (question.shops && question.shops.includes(req.query.shopAddress)) {
            questions.push(question);
          }
        } else {
          questions.push(question);
        }`;

const newFilter = `// Фильтр по магазину, если указан
        if (req.query.shopAddress) {
          // Если shops пустой или null - вопрос для всех магазинов
          // Если shops содержит адрес магазина - вопрос для этого магазина
          if (!question.shops || question.shops.length === 0 || question.shops.includes(req.query.shopAddress)) {
            questions.push(question);
          }
        } else {
          questions.push(question);
        }`;

if (code.includes(oldFilter)) {
  code = code.replace(oldFilter, newFilter);
  fs.writeFileSync('index.js', code);
  console.log('Filter logic fixed successfully');
} else {
  console.log('Old filter not found, trying alternative search...');

  // Попробуем найти другой вариант
  const oldFilterAlt = `if (question.shops && question.shops.includes(req.query.shopAddress)) {
            questions.push(question);
          }`;

  const newFilterAlt = `// Если shops пустой или null - вопрос для всех магазинов
          if (!question.shops || question.shops.length === 0 || question.shops.includes(req.query.shopAddress)) {
            questions.push(question);
          }`;

  if (code.includes(oldFilterAlt)) {
    code = code.replace(oldFilterAlt, newFilterAlt);
    fs.writeFileSync('index.js', code);
    console.log('Filter logic fixed (alternative)');
  } else {
    console.log('Could not find filter to replace');
    // Показываем часть кода для отладки
    const idx = code.indexOf('shift-handover-questions');
    if (idx !== -1) {
      console.log('Found shift-handover-questions at index:', idx);
      console.log('Context:', code.substring(idx, idx + 500));
    }
  }
}
