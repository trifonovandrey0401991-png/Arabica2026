// Script to patch index.js with push notifications for orders
const fs = require('fs');

const filePath = '/root/arabica_app/loyalty-proxy/index.js';
let content = fs.readFileSync(filePath, 'utf8');

// Pattern for the old POST /api/orders handler (minified version)
const oldPattern = /\/\/ POST \/api\/orders - создать заказ\napp\.post\('\/api\/orders', async \(req, res\) => \{  try \{    const \{ clientPhone, clientName, shopAddress, items, totalPrice, comment \} = req\.body;    const normalizedPhone = clientPhone\.replace\(\/\[s\+\]\/g, ''\);        const order = await ordersModule\.createOrder\(\{      clientPhone: normalizedPhone,      clientName,      shopAddress,      items,      totalPrice,      comment    \}\);        console\.log\(`✅ Создан заказ #\$\{order\.orderNumber\} от \$\{clientName\}`\);    res\.json\(\{ success: true, order \}\);  \} catch \(err\) \{    console\.error\('❌ Ошибка создания заказа:', err\);    res\.status\(500\)\.json\(\{ success: false, error: err\.message \}\);  \}\}\);/;

const newCode = `// POST /api/orders - создать заказ
app.post('/api/orders', async (req, res) => {
  try {
    const { clientPhone, clientName, shopAddress, items, totalPrice, comment } = req.body;
    const normalizedPhone = clientPhone.replace(/[\\s+]/g, '');

    const order = await ordersModule.createOrder({
      clientPhone: normalizedPhone,
      clientName,
      shopAddress,
      items,
      totalPrice,
      comment
    });

    console.log(\`✅ Создан заказ #\${order.orderNumber} от \${clientName}\`);

    // Отправляем push-уведомление сотрудникам магазина
    orderNotifications.notifyEmployeesAboutNewOrder(order).catch(err => {
      console.error('❌ Ошибка отправки push сотрудникам:', err);
    });

    res.json({ success: true, order });
  } catch (err) {
    console.error('❌ Ошибка создания заказа:', err);
    res.status(500).json({ success: false, error: err.message });
  }
});`;

if (oldPattern.test(content)) {
  content = content.replace(oldPattern, newCode);
  fs.writeFileSync(filePath, content, 'utf8');
  console.log('✅ POST /api/orders patched successfully');
} else {
  // Try simpler approach - find the line number and replace
  const lines = content.split('\n');
  let found = false;

  for (let i = 0; i < lines.length; i++) {
    if (lines[i].includes("// POST /api/orders - создать заказ")) {
      console.log('Found POST /api/orders at line', i + 1);
      // Replace this line and the next one
      if (lines[i + 1] && lines[i + 1].includes("app.post('/api/orders'")) {
        lines[i] = newCode;
        lines.splice(i + 1, 1); // Remove the old minified line
        found = true;
        break;
      }
    }
  }

  if (found) {
    fs.writeFileSync(filePath, lines.join('\n'), 'utf8');
    console.log('✅ POST /api/orders patched successfully (simple mode)');
  } else {
    console.log('❌ Could not find POST /api/orders to patch');
    console.log('Content includes POST /api/orders:', content.includes('POST /api/orders'));
  }
}
