/**
 * Node.js wrapper for YOLOv8 Python inference script
 *
 * Provides async interface to call Python YOLO detection
 */

const { spawn } = require('child_process');
const path = require('path');
const fs = require('fs');

// Paths
const SCRIPT_DIR = __dirname;
const PYTHON_SCRIPT = path.join(SCRIPT_DIR, 'yolo_inference.py');
const MODELS_DIR = path.join(SCRIPT_DIR, 'models');
const DEFAULT_MODEL = path.join(MODELS_DIR, 'cigarette_detector.pt');

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
      timeout: 60000 // 60 second timeout
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

  // Save image temporarily (base64 is too long for command line)
  const tempDir = path.join(SCRIPT_DIR, 'temp');
  if (!fs.existsSync(tempDir)) {
    fs.mkdirSync(tempDir, { recursive: true });
  }

  const tempFile = path.join(tempDir, `detect_${Date.now()}.jpg`);

  try {
    // Write base64 to temp file
    const imageBuffer = Buffer.from(imageBase64, 'base64');
    fs.writeFileSync(tempFile, imageBuffer);

    // Run detection
    const args = ['--mode', 'detect', '--image', tempFile, '--confidence', confidence.toString()];

    if (productId) {
      args.push('--product-id', productId);
    }

    const result = await runYoloScript(args);

    return result;
  } finally {
    // Cleanup temp file
    try {
      if (fs.existsSync(tempFile)) {
        fs.unlinkSync(tempFile);
      }
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

  // Save image temporarily
  const tempDir = path.join(SCRIPT_DIR, 'temp');
  if (!fs.existsSync(tempDir)) {
    fs.mkdirSync(tempDir, { recursive: true });
  }

  const tempFile = path.join(tempDir, `display_${Date.now()}.jpg`);

  try {
    // Write base64 to temp file
    const imageBuffer = Buffer.from(imageBase64, 'base64');
    fs.writeFileSync(tempFile, imageBuffer);

    // Run display check
    const args = [
      '--mode', 'display',
      '--image', tempFile,
      '--confidence', confidence.toString()
    ];

    if (expectedProducts && expectedProducts.length > 0) {
      args.push('--expected', expectedProducts.join(','));
    }

    const result = await runYoloScript(args);

    return result;
  } finally {
    // Cleanup temp file
    try {
      if (fs.existsSync(tempFile)) {
        fs.unlinkSync(tempFile);
      }
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
  exportTrainingData,
  trainModel,
  isModelReady,
  getModelInfo,
  DEFAULT_MODEL,
  MODELS_DIR
};
