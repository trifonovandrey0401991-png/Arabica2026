/**
 * Image Compression Middleware
 * Сжатие загружаемых фото через sharp
 *
 * Используется как Express middleware ПОСЛЕ multer.
 * Сжимает изображения до 1920px, JPEG quality 80.
 * Для бинарных данных — fsp.writeFile (НЕ writeJsonFile).
 */

const fsp = require('fs').promises;

let sharp = null;
try {
  sharp = require('sharp');
  console.log('✅ sharp loaded — image compression enabled');
} catch (e) {
  console.warn('⚠️  sharp not installed — image compression disabled (npm install sharp)');
}

const MAX_DIMENSION = 1920;
const JPEG_QUALITY = 80;

/**
 * Express middleware: сжимает загруженное фото (req.file) если оно изображение.
 * Безопасно пропускает если sharp не установлен или файл не изображение.
 */
async function compressUpload(req, res, next) {
  if (!sharp || !req.file || !req.file.mimetype || !req.file.mimetype.startsWith('image/')) {
    return next();
  }

  try {
    const originalSize = req.file.size;

    const compressed = await sharp(req.file.path)
      .resize(MAX_DIMENSION, MAX_DIMENSION, { fit: 'inside', withoutEnlargement: true })
      .jpeg({ quality: JPEG_QUALITY })
      .toBuffer();

    await fsp.writeFile(req.file.path, compressed);
    req.file.size = compressed.length;

    const savedPercent = Math.round((1 - compressed.length / originalSize) * 100);
    if (savedPercent > 5) {
      console.log(`📸 Compressed ${req.file.originalname}: ${(originalSize / 1024).toFixed(0)}KB → ${(compressed.length / 1024).toFixed(0)}KB (-${savedPercent}%)`);
    }
  } catch (err) {
    console.error('⚠️  Image compression failed, using original:', err.message);
  }

  next();
}

module.exports = { compressUpload };
