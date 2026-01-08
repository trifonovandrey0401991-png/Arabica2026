const express = require('express');
const cors = require('cors');
const multer = require('multer');
const path = require('path');
const fs = require('fs');

// ===== CONFIGURATION =====
const PORT = process.env.PORT || 3000;
const STATIC_ROOT = '/var/www';

// ===== MULTER CONFIGURATIONS =====

// Generic photo upload
const createUploader = (destDir) => {
  if (!fs.existsSync(destDir)) fs.mkdirSync(destDir, { recursive: true });
  return multer({
    storage: multer.diskStorage({
      destination: (req, file, cb) => cb(null, destDir),
      filename: (req, file, cb) => {
        const uniqueName = `${Date.now()}_${Math.random().toString(36).substr(2, 9)}${path.extname(file.originalname)}`;
        cb(null, uniqueName);
      }
    }),
    limits: { fileSize: 10 * 1024 * 1024 } // 10MB
  });
};

// Create uploaders for different directories
const uploadShiftPhoto = createUploader('/var/www/shift-photos');
const uploadShiftHandoverPhoto = createUploader('/var/www/shift-handover-question-photos');
const uploadEmployeePhoto = createUploader('/var/www/employee-photos');
const uploadRecipePhoto = createUploader('/var/www/recipe-photos');
const uploadProductQuestionPhoto = createUploader('/var/www/product-question-photos');
const uploadChatMedia = createUploader('/var/www/chat-media');
const uploadRecountPhoto = createUploader('/var/www/recount-question-photos');
const uploadEnvelopePhoto = createUploader('/var/www/envelope-question-photos');
const uploadShopSettingsPhoto = createUploader('/var/www/shop-settings-photos');

// ===== IMPORT API MODULES =====
// All modules are in the 'api' subdirectory
const { setupRecountAPI } = require('./api/recount_api');
const { setupAttendanceAPI } = require('./api/attendance_api');
const { setupEmployeesAPI } = require('./api/employees_api');
const { setupShopsAPI } = require('./api/shops_api');
const { setupShiftsAPI } = require('./api/shifts_api');
const { setupClientsAPI } = require('./api/clients_api');
const { setupWorkScheduleAPI } = require('./api/work_schedule_api');
const { setupRkoAPI } = require('./api/rko_api');
const { setupTrainingAPI } = require('./api/training_api');
const { setupTestsAPI } = require('./api/tests_api');
const { setupRecipesAPI } = require('./api/recipes_api');
const { setupMenuAPI } = require('./api/menu_api');
const { setupOrdersAPI } = require('./api/orders_api');
const { setupProductQuestionsAPI } = require('./api/product_questions_api');
const { setupReviewsAPI } = require('./api/reviews_api');
const { setupMediaAPI } = require('./api/media_api');
const { setupLoyaltyAPI } = require('./api/loyalty_api');
const { setupSuppliersAPI } = require('./api/suppliers_api');
const { setupEnvelopeAPI } = require('./api/envelope_api');
const { setupWithdrawalsAPI } = require('./api/withdrawals_api');
const { setupPendingAPI } = require('./api/pending_api');
const { setupShiftTransfersAPI } = require('./api/shift_transfers_api');
const { setupShopCoordinatesAPI } = require('./api/shop_coordinates_api');
const { setupLoyaltyPromoAPI } = require('./api/loyalty_promo_api');
const { setupEmployeeChatAPI } = require('./api/employee_chat_api');
const shopSettingsAPI = require('./api/shop_settings_api');
const { setupPointsSettingsAPI } = require('./api/points_settings_api');

// ===== EXPRESS APP SETUP =====
const app = express();

// Middleware
app.use(cors());
app.use(express.json({ limit: '50mb' }));
app.use(express.urlencoded({ extended: true, limit: '50mb' }));

// Static file serving
app.use('/shift-photos', express.static('/var/www/shift-photos'));
app.use('/shift-handover-question-photos', express.static('/var/www/shift-handover-question-photos'));
app.use('/employee-photos', express.static('/var/www/employee-photos'));
app.use('/recipe-photos', express.static('/var/www/recipe-photos'));
app.use('/product-question-photos', express.static('/var/www/product-question-photos'));
app.use('/chat-media', express.static('/var/www/chat-media'));
app.use('/recount-question-photos', express.static('/var/www/recount-question-photos'));
app.use('/envelope-question-photos', express.static('/var/www/envelope-question-photos'));
app.use('/shop-settings-photos', express.static('/var/www/shop-settings-photos'));
app.use('/shift-reference-photos', express.static('/var/www/shift-reference-photos'));
app.use('/shift-question-photos', express.static('/var/www/shift-question-photos'));

// ===== HEALTH CHECK =====
app.get('/health', (req, res) => {
  res.json({ status: 'ok', timestamp: new Date().toISOString(), version: '2.2.0-modular' });
});

app.get('/', (req, res) => {
  res.json({
    message: 'Arabica API Server (Modular)',
    version: '2.2.0',
    endpoints: 'Use /health for status'
  });
});

// ===== INITIALIZE ALL API MODULES =====
console.log('🚀 Initializing API modules...');

// Core APIs
setupRecountAPI(app, uploadRecountPhoto);
setupAttendanceAPI(app);
setupEmployeesAPI(app, uploadEmployeePhoto);
setupShopsAPI(app);
setupShiftsAPI(app, uploadShiftPhoto, uploadShiftHandoverPhoto);
setupClientsAPI(app);

// Schedule & Reports
setupWorkScheduleAPI(app);
setupRkoAPI(app);

// Content & Training
setupTrainingAPI(app);
setupTestsAPI(app);
setupRecipesAPI(app, uploadRecipePhoto);
setupMenuAPI(app);

// Orders & Notifications
setupOrdersAPI(app);

// Support
setupProductQuestionsAPI(app, uploadProductQuestionPhoto);
setupReviewsAPI(app);

// Media & Logging
setupMediaAPI(app, uploadChatMedia);

// Loyalty System
setupLoyaltyAPI(app);

// External modules (already on server)
setupSuppliersAPI(app);
setupEnvelopeAPI(app, uploadEnvelopePhoto);
setupWithdrawalsAPI(app);

// New modules
setupPendingAPI(app);
setupShiftTransfersAPI(app);
setupShopCoordinatesAPI(app);
setupLoyaltyPromoAPI(app);

// Employee Chat
setupEmployeeChatAPI(app);

// Shop Settings
shopSettingsAPI.setup(app);

// Points Settings (Efficiency)
setupPointsSettingsAPI(app);

console.log('✅ All API modules initialized');

// ===== ERROR HANDLING =====
app.use((err, req, res, next) => {
  console.error('Error:', err);
  res.status(500).json({ success: false, error: err.message });
});

// ===== 404 HANDLER =====
app.use((req, res) => {
  console.log('404 Not Found:', req.method, req.url);
  res.status(404).json({ success: false, error: 'Not found' });
});

// ===== START SERVER =====
app.listen(PORT, '0.0.0.0', () => {
  console.log(`\n========================================`);
  console.log(`🚀 Arabica API Server (Modular v2.2.0)`);
  console.log(`📡 Running on port ${PORT}`);
  console.log(`🕐 Started at ${new Date().toISOString()}`);
  console.log(`========================================\n`);
});

module.exports = app;
