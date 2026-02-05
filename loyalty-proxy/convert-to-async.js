/**
 * Script to convert sync fs operations to async in index.js
 *
 * Creates a backup and converts:
 * - fs.existsSync -> await fileExists
 * - fs.readFileSync -> await fsp.readFile
 * - fs.writeFileSync -> await fsp.writeFile
 * - fs.mkdirSync -> await fsp.mkdir
 * - fs.readdirSync -> await fsp.readdir
 * - fs.unlinkSync -> await fsp.unlink
 * - (req, res) => { -> async (req, res) => { (where needed)
 */

const fs = require('fs');
const path = require('path');

const inputFile = path.join(__dirname, 'index.js');
const backupFile = path.join(__dirname, 'index.js.backup-auto-convert');

console.log('Reading index.js...');
let content = fs.readFileSync(inputFile, 'utf8');

// Create backup
console.log('Creating backup...');
fs.writeFileSync(backupFile, content, 'utf8');

// Count before
const countBefore = {
  existsSync: (content.match(/fs\.existsSync/g) || []).length,
  readFileSync: (content.match(/fs\.readFileSync/g) || []).length,
  writeFileSync: (content.match(/fs\.writeFileSync/g) || []).length,
  mkdirSync: (content.match(/fs\.mkdirSync/g) || []).length,
  readdirSync: (content.match(/fs\.readdirSync/g) || []).length,
  unlinkSync: (content.match(/fs\.unlinkSync/g) || []).length,
  statSync: (content.match(/fs\.statSync/g) || []).length,
};

console.log('Before conversion:', countBefore);

// Step 1: Convert non-async handlers to async (only those that will need await)
// Pattern: app.get/post/put/delete/patch('...', (req, res) => {
// But only if they contain sync operations

// First, let's identify all route handlers and mark those needing async
const routePattern = /app\.(get|post|put|delete|patch)\s*\(\s*['"`][^'"`]+['"`]\s*,\s*\(req,\s*res\)\s*=>\s*\{/g;

// Replace (req, res) => { with async (req, res) => { for all handlers
// This is safe because adding async to a sync function doesn't break it
content = content.replace(
  /app\.(get|post|put|delete|patch)\s*\(\s*(['"`][^'"`]+['"`])\s*,\s*\(req,\s*res\)\s*=>\s*\{/g,
  'app.$1($2, async (req, res) => {'
);

// Also handle router handlers
content = content.replace(
  /router\.(get|post|put|delete|patch)\s*\(\s*(['"`][^'"`]+['"`])\s*,\s*\(req,\s*res\)\s*=>\s*\{/g,
  'router.$1($2, async (req, res) => {'
);

// Step 2: Replace sync operations with async equivalents

// fs.existsSync -> await fileExists
content = content.replace(/fs\.existsSync\s*\(/g, 'await fileExists(');

// fs.readFileSync(...) -> await fsp.readFile(...)
content = content.replace(/fs\.readFileSync\s*\(/g, 'await fsp.readFile(');

// fs.writeFileSync(...) -> await fsp.writeFile(...)
content = content.replace(/fs\.writeFileSync\s*\(/g, 'await fsp.writeFile(');

// fs.mkdirSync(..., { recursive: true }) -> await fsp.mkdir(..., { recursive: true })
content = content.replace(/fs\.mkdirSync\s*\(/g, 'await fsp.mkdir(');

// fs.readdirSync(...) -> await fsp.readdir(...)
content = content.replace(/fs\.readdirSync\s*\(/g, 'await fsp.readdir(');

// fs.unlinkSync(...) -> await fsp.unlink(...)
content = content.replace(/fs\.unlinkSync\s*\(/g, 'await fsp.unlink(');

// fs.statSync(...) -> await fsp.stat(...)
content = content.replace(/fs\.statSync\s*\(/g, 'await fsp.stat(');

// fs.copyFileSync(...) -> await fsp.copyFile(...)
content = content.replace(/fs\.copyFileSync\s*\(/g, 'await fsp.copyFile(');

// fs.renameSync(...) -> await fsp.rename(...)
content = content.replace(/fs\.renameSync\s*\(/g, 'await fsp.rename(');

// Fix: if (await fileExists(...)) should work, but !await fileExists needs parentheses
// Actually in JS, !await expr works fine

// Count after
const countAfter = {
  existsSync: (content.match(/fs\.existsSync/g) || []).length,
  readFileSync: (content.match(/fs\.readFileSync/g) || []).length,
  writeFileSync: (content.match(/fs\.writeFileSync/g) || []).length,
  mkdirSync: (content.match(/fs\.mkdirSync/g) || []).length,
  readdirSync: (content.match(/fs\.readdirSync/g) || []).length,
  unlinkSync: (content.match(/fs\.unlinkSync/g) || []).length,
  statSync: (content.match(/fs\.statSync/g) || []).length,
  fileExists: (content.match(/await fileExists/g) || []).length,
  fspReadFile: (content.match(/await fsp\.readFile/g) || []).length,
  fspWriteFile: (content.match(/await fsp\.writeFile/g) || []).length,
  asyncHandlers: (content.match(/async\s*\(req,\s*res\)\s*=>/g) || []).length,
};

console.log('After conversion:', countAfter);

// Write result
console.log('Writing converted file...');
fs.writeFileSync(inputFile, content, 'utf8');

console.log('\n✅ Conversion complete!');
console.log('Backup saved to:', backupFile);
console.log('\nNext steps:');
console.log('1. Run: node -c index.js (check syntax)');
console.log('2. Test on server: pm2 restart loyalty-proxy');
