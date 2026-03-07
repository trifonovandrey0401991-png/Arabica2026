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
    const path = require('path');
    const originalSize = req.file.size;

    const compressed = await sharp(req.file.path)
      .rotate() // auto-rotate based on EXIF orientation (fixes 270° bug)
      .resize(MAX_DIMENSION, MAX_DIMENSION, { fit: 'inside', withoutEnlargement: true })
      .jpeg({ quality: JPEG_QUALITY })
      .toBuffer();

    // sharp converts to JPEG — rename file if extension was not .jpg/.jpeg
    const ext = path.extname(req.file.path).toLowerCase();
    if (ext !== '.jpg' && ext !== '.jpeg') {
      const newPath = req.file.path.replace(/\.[^.]+$/, '.jpg');
      await fsp.writeFile(newPath, compressed);
      await fsp.unlink(req.file.path).catch(() => {});
      req.file.path = newPath;
      req.file.filename = path.basename(newPath);
    } else {
      await fsp.writeFile(req.file.path, compressed);
    }
    req.file.size = compressed.length;
    req.file.mimetype = 'image/jpeg';

    const savedPercent = Math.round((1 - compressed.length / originalSize) * 100);
    if (savedPercent > 5) {
      console.log(`📸 Compressed ${req.file.originalname}: ${(originalSize / 1024).toFixed(0)}KB → ${(compressed.length / 1024).toFixed(0)}KB (-${savedPercent}%)`);
    }
  } catch (err) {
    console.error('⚠️  Image compression failed, using original:', err.message);
  }

  next();
}

const THUMB_SIZE = 200;
const THUMB_QUALITY = 60;

/**
 * Generate thumbnail for uploaded image.
 * Creates a small JPEG at {original_path}_thumb.jpg
 * Returns thumbnail filename or null if failed/not applicable.
 */
async function generateThumbnail(filePath) {
  if (!sharp) return null;
  try {
    const path = require('path');
    const ext = path.extname(filePath).toLowerCase();
    if (!['.jpg', '.jpeg', '.png', '.webp', '.gif'].includes(ext)) return null;

    const thumbFilename = path.basename(filePath, ext) + '_thumb.jpg';
    const thumbPath = path.join(path.dirname(filePath), thumbFilename);

    await sharp(filePath)
      .resize(THUMB_SIZE, THUMB_SIZE, { fit: 'cover' })
      .jpeg({ quality: THUMB_QUALITY })
      .toFile(thumbPath);

    return thumbFilename;
  } catch (e) {
    console.error('[Thumbnail] Failed:', e.message);
    return null;
  }
}

module.exports = { compressUpload, generateThumbnail };
