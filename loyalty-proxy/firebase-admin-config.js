const admin = require('firebase-admin');

// ВАЖНО: Для работы push-уведомлений необходимо получить файл firebase-service-account.json
// из Firebase Console: Project Settings → Service Accounts → Generate New Private Key
// Разместить файл в /root/arabica_app/loyalty-proxy/ и установить права: chmod 600

let firebaseInitialized = false;

try {
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

module.exports = {
  admin,
  firebaseInitialized
};
