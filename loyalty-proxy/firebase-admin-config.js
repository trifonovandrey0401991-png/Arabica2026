// Firebase Admin SDK configuration (stub for now)
let admin = null;
let firebaseInitialized = false;

try {
  admin = require('firebase-admin');
  const serviceAccount = require('./firebase-service-account.json');
  
  admin.initializeApp({
    credential: admin.credential.cert(serviceAccount)
  });
  
  firebaseInitialized = true;
  console.log('✅ Firebase Admin SDK инициализирован');
} catch (error) {
  console.warn('⚠️  Firebase Admin SDK не инициализирован:', error.message);
  console.warn('⚠️  Push-уведомления работать не будут. Получите firebase-service-account.json из Firebase Console');
}

module.exports = { admin, firebaseInitialized };
