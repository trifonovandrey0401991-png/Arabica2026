const fs = require('fs');
let code = fs.readFileSync('index.js', 'utf8');

// Найдем строку с DELETE endpoint
const deleteMarker = '// DELETE /api/shift-handover-reports/:id';
const deleteIndex = code.indexOf(deleteMarker);

if (deleteIndex === -1) {
  console.log('DELETE marker not found');
  process.exit(1);
}

// PUT endpoint код
const putEndpoint = `// PUT /api/shift-handover-reports/:id - обновить отчет (подтвердить/оценить)
app.put('/api/shift-handover-reports/:id', async (req, res) => {
  try {
    const { id } = req.params;
    const updateData = req.body;
    console.log('PUT /api/shift-handover-reports/:id', id, updateData);

    const filePath = path.join(SHIFT_HANDOVER_REPORTS_DIR, id + '.json');
    if (!fs.existsSync(filePath)) {
      return res.json({ success: false, error: 'Report not found' });
    }

    const existingReport = JSON.parse(fs.readFileSync(filePath, 'utf8'));
    const updatedReport = { ...existingReport, ...updateData };
    fs.writeFileSync(filePath, JSON.stringify(updatedReport, null, 2));

    res.json({ success: true, report: updatedReport });
  } catch (error) {
    console.error('Error updating shift handover report:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

`;

// Вставляем PUT endpoint перед DELETE
code = code.slice(0, deleteIndex) + putEndpoint + code.slice(deleteIndex);

fs.writeFileSync('index.js', code);
console.log('PUT endpoint добавлен');
