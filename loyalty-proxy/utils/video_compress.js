/**
 * Video Compression Middleware
 * Сжатие загружаемых видео через ffmpeg (H.264, CRF 28, 720p max).
 *
 * Используется как Express middleware ПОСЛЕ multer.
 * Безопасно: если ffmpeg не установлен или ошибка — оставляет оригинал.
 * Для бинарных данных — fsp (НЕ writeJsonFile).
 */

const { execFile } = require('child_process');
const fsp = require('fs').promises;
const path = require('path');

// Check if ffmpeg is available
let ffmpegAvailable = false;
try {
  require('child_process').execFileSync('ffmpeg', ['-version'], { stdio: 'ignore' });
  ffmpegAvailable = true;
  console.log('✅ ffmpeg found — video compression enabled');
} catch (e) {
  console.warn('⚠️  ffmpeg not installed — video compression disabled');
}

const VIDEO_MIMETYPES = ['video/mp4', 'video/quicktime', 'video/x-matroska', 'video/webm', 'video/3gpp'];
const MAX_VIDEO_HEIGHT = 720;
const CRF = 28; // Quality: 18=visually lossless, 23=default, 28=good compression
const COMPRESS_TIMEOUT_MS = 120000; // 2 minutes max

/**
 * Express middleware: сжимает загруженное видео (req.file) если оно видеофайл.
 * Безопасно пропускает если ffmpeg не установлен или файл не видео.
 */
async function compressVideo(req, res, next) {
  if (!ffmpegAvailable || !req.file || !req.file.mimetype) {
    return next();
  }

  if (!VIDEO_MIMETYPES.includes(req.file.mimetype)) {
    return next();
  }

  const inputPath = req.file.path;
  const tmpOutput = inputPath + '.compressed.mp4';
  const originalSize = req.file.size;

  // Skip tiny videos (< 500KB) — compression overhead not worth it
  if (originalSize < 512 * 1024) {
    return next();
  }

  try {
    await new Promise((resolve, reject) => {
      const args = [
        '-i', inputPath,
        '-y',                          // overwrite output
        '-c:v', 'libx264',           // H.264 codec
        '-preset', 'fast',            // fast encoding (good balance)
        '-crf', String(CRF),          // quality level
        '-vf', `scale=-2:'min(${MAX_VIDEO_HEIGHT},ih)'`, // max 720p, keep aspect ratio
        '-c:a', 'aac',               // AAC audio
        '-b:a', '128k',              // audio bitrate
        '-movflags', '+faststart',    // streaming-friendly
        '-max_muxing_queue_size', '1024',
        tmpOutput,
      ];

      const proc = execFile('ffmpeg', args, { timeout: COMPRESS_TIMEOUT_MS }, (error) => {
        if (error) reject(error);
        else resolve();
      });

      // Suppress ffmpeg stderr (it writes progress there)
      proc.stderr?.on('data', () => {});
    });

    // Check compressed file exists and is smaller
    const compressedStat = await fsp.stat(tmpOutput);

    if (compressedStat.size < originalSize * 0.95) {
      // Compressed is at least 5% smaller — use it
      await fsp.unlink(inputPath);
      await fsp.rename(tmpOutput, inputPath);
      req.file.size = compressedStat.size;

      const savedPercent = Math.round((1 - compressedStat.size / originalSize) * 100);
      console.log(`🎬 Compressed video ${req.file.originalname}: ${(originalSize / 1024 / 1024).toFixed(1)}MB → ${(compressedStat.size / 1024 / 1024).toFixed(1)}MB (-${savedPercent}%)`);
    } else {
      // Compressed is not smaller — keep original
      await fsp.unlink(tmpOutput).catch(() => {});
    }
  } catch (err) {
    console.error('⚠️  Video compression failed, using original:', err.message);
    // Clean up temp file if it exists
    await fsp.unlink(tmpOutput).catch(() => {});
  }

  next();
}

module.exports = { compressVideo };
