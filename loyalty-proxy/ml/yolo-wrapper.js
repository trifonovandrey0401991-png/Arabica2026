/**
 * Node.js wrapper for YOLOv8 Python inference script
 *
 * Provides async interface to call Python YOLO detection.
 * CIG-8: Tries persistent HTTP server (port 5002) first, falls back to spawn.
 */

const { spawn } = require('child_process');
const path = require('path');
const fs = require('fs');
const http = require('http');

// Paths
const SCRIPT_DIR = __dirname;
const PYTHON_SCRIPT = path.join(SCRIPT_DIR, 'yolo_inference.py');
const MODELS_DIR = path.join(SCRIPT_DIR, 'models');
const DEFAULT_MODEL = path.join(MODELS_DIR, 'cigarette_detector.pt');

// YOLO Server (persistent HTTP server on port 5002)
const YOLO_SERVER_PORT = 5002;
const YOLO_SERVER_URL = `http://127.0.0.1:${YOLO_SERVER_PORT}`;
let yoloServerAvailable = null; // null = unknown, true/false = cached

/**
 * Check if YOLO persistent server is running (returns true even if model not loaded)
 */
async function isYoloServerReady() {
  return new Promise((resolve) => {
    const req = http.get(`${YOLO_SERVER_URL}/health`, { timeout: 2000 }, (res) => {
      let data = '';
      res.on('data', chunk => data += chunk);
      res.on('end', () => {
        try {
          const result = JSON.parse(data);
          // Server is "ready" if it's running, even without model loaded
          resolve(result.status === 'ok');
        } catch (e) {
          resolve(false);
        }
      });
    });
    req.on('error', () => resolve(false));
    req.on('timeout', () => { req.destroy(); resolve(false); });
  });
}

/**
 * Ask yolo_server to reload model from disk (call after training)
 */
async function reloadModel() {
  return new Promise((resolve) => {
    const body = '{}';
    const options = {
      hostname: '127.0.0.1',
      port: YOLO_SERVER_PORT,
      path: '/reload',
      method: 'POST',
      headers: { 'Content-Type': 'application/json', 'Content-Length': Buffer.byteLength(body) },
      timeout: 10000,
    };
    const req = http.request(options, (res) => {
      let data = '';
      res.on('data', chunk => data += chunk);
      res.on('end', () => {
        try { resolve(JSON.parse(data)); } catch (e) { resolve({ success: false, error: 'Invalid JSON' }); }
      });
    });
    req.on('error', (e) => resolve({ success: false, error: e.message }));
    req.on('timeout', () => { req.destroy(); resolve({ success: false, error: 'Timeout' }); });
    req.write(body);
    req.end();
  });
}

/**
 * Send request to YOLO persistent server
 */
async function callYoloServer(endpoint, payload) {
  return new Promise((resolve, reject) => {
    const body = JSON.stringify(payload);
    const options = {
      hostname: '127.0.0.1',
      port: YOLO_SERVER_PORT,
      path: endpoint,
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Content-Length': Buffer.byteLength(body),
      },
      timeout: 30000,
    };

    const req = http.request(options, (res) => {
      let data = '';
      res.on('data', chunk => data += chunk);
      res.on('end', () => {
        try {
          resolve(JSON.parse(data));
        } catch (e) {
          reject(new Error(`Invalid JSON from YOLO server: ${data.slice(0, 100)}`));
        }
      });
    });

    req.on('error', reject);
    req.on('timeout', () => { req.destroy(); reject(new Error('YOLO server timeout')); });
    req.write(body);
    req.end();
  });
}

// Python executable (try python3 first, then python)
let pythonExecutable = null;

/**
 * Find Python executable
 */
async function findPython() {
  if (pythonExecutable) return pythonExecutable;

  const candidates = ['python3', 'python', '/usr/bin/python3', '/usr/local/bin/python3'];

  for (const candidate of candidates) {
    try {
      const result = await runCommand(candidate, ['--version']);
      if (result.success && result.stdout.includes('Python')) {
        pythonExecutable = candidate;
        console.log(`[YOLO Wrapper] Using Python: ${candidate}`);
        return candidate;
      }
    } catch (e) {
      // Try next candidate
    }
  }

  throw new Error('Python not found. Install Python 3.8+');
}

/**
 * Run a command and return result
 */
function runCommand(command, args) {
  return new Promise((resolve) => {
    const proc = spawn(command, args, {
      stdio: ['pipe', 'pipe', 'pipe'],
      timeout: 30 * 60 * 1000 // 30 min — training can take many minutes
    });

    let stdout = '';
    let stderr = '';

    proc.stdout.on('data', (data) => {
      stdout += data.toString();
    });

    proc.stderr.on('data', (data) => {
      stderr += data.toString();
    });

    proc.on('close', (code) => {
      resolve({
        success: code === 0,
        code,
        stdout,
        stderr
      });
    });

    proc.on('error', (err) => {
      resolve({
        success: false,
        code: -1,
        stdout: '',
        stderr: err.message
      });
    });
  });
}

/**
 * Run Python YOLO script with arguments
 */
async function runYoloScript(args) {
  try {
    const python = await findPython();

    // Add script path as first argument
    const fullArgs = [PYTHON_SCRIPT, ...args];

    const result = await runCommand(python, fullArgs);

    if (!result.success) {
      console.error('[YOLO Wrapper] Script error:', result.stderr);
      return {
        success: false,
        error: result.stderr || 'Python script failed',
        code: result.code
      };
    }

    // Parse JSON output
    try {
      const output = result.stdout.trim();
      // Find the last valid JSON object (in case of debug output)
      const jsonMatch = output.match(/\{[\s\S]*\}$/);
      if (jsonMatch) {
        return JSON.parse(jsonMatch[0]);
      }
      return JSON.parse(output);
    } catch (parseError) {
      console.error('[YOLO Wrapper] JSON parse error:', parseError);
      console.error('[YOLO Wrapper] Raw output:', result.stdout);
      return {
        success: false,
        error: 'Failed to parse Python output',
        raw: result.stdout
      };
    }
  } catch (error) {
    console.error('[YOLO Wrapper] Error:', error);
    return {
      success: false,
      error: error.message
    };
  }
}

/**
 * Check if YOLO is available and model exists
 */
async function checkStatus() {
  const result = await runYoloScript(['--mode', 'status']);

  // Add Node.js side checks
  result.pythonScriptExists = fs.existsSync(PYTHON_SCRIPT);
  result.modelsDirExists = fs.existsSync(MODELS_DIR);

  return result;
}

/**
 * Detect and count objects in image
 *
 * @param {string} imageBase64 - Base64 encoded image
 * @param {string} productId - Optional product ID filter
 * @param {number} confidence - Confidence threshold (0-1)
 * @returns {Promise<object>} Detection results
 */
async function detectAndCount(imageBase64, productId = null, confidence = 0.5) {
  // Check if model exists
  if (!fs.existsSync(DEFAULT_MODEL)) {
    return {
      success: false,
      error: 'Модель не обучена. Загрузите образцы и запустите обучение.',
      count: 0,
      confidence: 0,
      boxes: [],
      modelMissing: true
    };
  }

  // CIG-8: Попробовать persistent HTTP server
  if (yoloServerAvailable === null) {
    yoloServerAvailable = await isYoloServerReady();
  }
  if (yoloServerAvailable) {
    try {
      const result = await callYoloServer('/detect', {
        imageBase64,
        productId,
        confidence,
      });
      return result;
    } catch (e) {
      console.warn('[YOLO Wrapper] HTTP server failed, falling back to spawn:', e.message);
      yoloServerAvailable = false;
      // Повторная проверка через 60 секунд (сервер мог перезагрузиться)
      setTimeout(() => { yoloServerAvailable = null; }, 60000);
    }
  }

  // Fallback: spawn Python process
  const tempDir = path.join(SCRIPT_DIR, 'temp');
  if (!fs.existsSync(tempDir)) {
    fs.mkdirSync(tempDir, { recursive: true });
  }

  const tempFile = path.join(tempDir, `detect_${Date.now()}_${Math.random().toString(36).slice(2, 6)}.jpg`);

  try {
    const imageBuffer = Buffer.from(imageBase64, 'base64');
    fs.writeFileSync(tempFile, imageBuffer);

    const args = ['--mode', 'detect', '--image', tempFile, '--confidence', confidence.toString()];
    if (productId) {
      args.push('--product-id', productId);
    }

    return await runYoloScript(args);
  } finally {
    try {
      if (fs.existsSync(tempFile)) fs.unlinkSync(tempFile);
    } catch (e) {
      console.error('[YOLO Wrapper] Failed to cleanup temp file:', e);
    }
  }
}

/**
 * Check display for missing products
 *
 * @param {string} imageBase64 - Base64 encoded image
 * @param {string[]} expectedProducts - List of expected product IDs
 * @param {number} confidence - Confidence threshold (0-1)
 * @returns {Promise<object>} Display check results
 */
async function checkDisplay(imageBase64, expectedProducts = [], confidence = 0.3) {
  // Check if model exists
  if (!fs.existsSync(DEFAULT_MODEL)) {
    return {
      success: false,
      error: 'Модель не обучена. Загрузите образцы и запустите обучение.',
      missingProducts: expectedProducts,
      detectedProducts: [],
      modelMissing: true
    };
  }

  // CIG-8: Попробовать persistent HTTP server
  if (yoloServerAvailable === null) {
    yoloServerAvailable = await isYoloServerReady();
  }
  if (yoloServerAvailable) {
    try {
      const result = await callYoloServer('/display', {
        imageBase64,
        expectedProducts,
        confidence,
      });
      return result;
    } catch (e) {
      console.warn('[YOLO Wrapper] HTTP server failed, falling back to spawn:', e.message);
      yoloServerAvailable = false;
      setTimeout(() => { yoloServerAvailable = null; }, 60000);
    }
  }

  // Fallback: spawn Python process
  const tempDir = path.join(SCRIPT_DIR, 'temp');
  if (!fs.existsSync(tempDir)) {
    fs.mkdirSync(tempDir, { recursive: true });
  }

  const tempFile = path.join(tempDir, `display_${Date.now()}_${Math.random().toString(36).slice(2, 6)}.jpg`);

  try {
    const imageBuffer = Buffer.from(imageBase64, 'base64');
    fs.writeFileSync(tempFile, imageBuffer);

    const args = [
      '--mode', 'display',
      '--image', tempFile,
      '--confidence', confidence.toString()
    ];
    if (expectedProducts && expectedProducts.length > 0) {
      args.push('--expected', expectedProducts.join(','));
    }

    return await runYoloScript(args);
  } finally {
    try {
      if (fs.existsSync(tempFile)) fs.unlinkSync(tempFile);
    } catch (e) {
      console.error('[YOLO Wrapper] Failed to cleanup temp file:', e);
    }
  }
}

/**
 * Export training data to YOLO format
 *
 * @param {string} outputDir - Output directory path
 * @returns {Promise<object>} Export results
 */
async function exportTrainingData(outputDir) {
  return await runYoloScript(['--mode', 'export', '--output', outputDir]);
}

/**
 * Train model on collected data
 *
 * @param {string} dataYaml - Path to data.yaml
 * @param {number} epochs - Training epochs
 * @returns {Promise<object>} Training results
 */
async function trainModel(dataYaml, epochs = 100) {
  return await runYoloScript([
    '--mode', 'train',
    '--data', dataYaml,
    '--epochs', epochs.toString()
  ]);
}

/**
 * Check display using embedding-based recognition (1000+ products)
 * Same response format as checkDisplay() — drop-in replacement.
 * Falls back to checkDisplay() on error.
 *
 * @param {string} imageBase64 - Base64 encoded image
 * @param {string[]} expectedProducts - List of expected product IDs
 * @param {number} confidence - YOLO confidence threshold (0-1)
 * @param {number} similarityThreshold - Embedding similarity threshold (0-1)
 * @returns {Promise<object>} Display check results (same format as checkDisplay)
 */
async function checkDisplayEmbed(imageBase64, expectedProducts = [], confidence = 0.3, similarityThreshold = 0.6) {
  // Check server availability
  if (yoloServerAvailable === null) {
    yoloServerAvailable = await isYoloServerReady();
  }
  if (yoloServerAvailable) {
    try {
      const result = await callYoloServer('/display-embed', {
        imageBase64,
        expectedProducts,
        confidence,
        similarityThreshold,
      });
      return result;
    } catch (e) {
      console.warn('[YOLO Wrapper] Embedding server failed, falling back to classic checkDisplay:', e.message);
      // Fallback to old pipeline
      return checkDisplay(imageBase64, expectedProducts, confidence);
    }
  }

  // No server — fallback to classic
  console.warn('[YOLO Wrapper] YOLO server not available, falling back to classic checkDisplay');
  return checkDisplay(imageBase64, expectedProducts, confidence);
}

/**
 * Add a reference embedding to the catalog
 *
 * @param {string} productId - Product ID
 * @param {string} imageBase64 - Base64 encoded image
 * @param {string} name - Human-readable product name
 * @returns {Promise<object>} Result with catalog stats
 */
async function addToCatalog(productId, imageBase64, name = '') {
  if (yoloServerAvailable === null) {
    yoloServerAvailable = await isYoloServerReady();
  }
  if (!yoloServerAvailable) {
    return { success: false, error: 'YOLO server not available' };
  }

  try {
    return await callYoloServer('/catalog/add', {
      productId,
      imageBase64,
      name,
    });
  } catch (e) {
    return { success: false, error: e.message };
  }
}

/**
 * Get embedding catalog statistics
 *
 * @returns {Promise<object>} Catalog stats
 */
async function getCatalogStats() {
  return new Promise((resolve) => {
    const req = http.get(`${YOLO_SERVER_URL}/catalog/stats`, { timeout: 5000 }, (res) => {
      let data = '';
      res.on('data', chunk => data += chunk);
      res.on('end', () => {
        try {
          resolve(JSON.parse(data));
        } catch (e) {
          resolve({ loaded: false, productCount: 0, totalEmbeddings: 0, error: 'Invalid JSON' });
        }
      });
    });
    req.on('error', () => resolve({ loaded: false, productCount: 0, totalEmbeddings: 0, error: 'Server unavailable' }));
    req.on('timeout', () => { req.destroy(); resolve({ loaded: false, productCount: 0, totalEmbeddings: 0, error: 'Timeout' }); });
  });
}

/**
 * Check if model is trained and ready
 */
function isModelReady() {
  return fs.existsSync(DEFAULT_MODEL);
}

/**
 * Get model info
 */
function getModelInfo() {
  if (!fs.existsSync(DEFAULT_MODEL)) {
    return {
      exists: false,
      path: DEFAULT_MODEL,
      message: 'Model not trained yet'
    };
  }

  const stats = fs.statSync(DEFAULT_MODEL);
  return {
    exists: true,
    path: DEFAULT_MODEL,
    size: stats.size,
    lastModified: stats.mtime.toISOString()
  };
}

module.exports = {
  checkStatus,
  detectAndCount,
  checkDisplay,
  checkDisplayEmbed,
  addToCatalog,
  getCatalogStats,
  exportTrainingData,
  trainModel,
  reloadModel,
  isModelReady,
  getModelInfo,
  DEFAULT_MODEL,
  MODELS_DIR
};
