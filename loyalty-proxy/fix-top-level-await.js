const fs = require('fs');

let content = fs.readFileSync('index.js', 'utf8');

// Pattern: standalone if (!await fileExists()) { await fsp.mkdir(); }
// Replace with IIFE wrapper

// Find all lines with pattern and wrap in IIFE
const lines = content.split('\n');
let result = [];
let i = 0;

while (i < lines.length) {
  const line = lines[i];
  
  // Check if this is a top-level await fileExists pattern (starts with if (!await)
  if (line.match(/^if \(!await fileExists\(/) || line.match(/^if \(await fileExists\(/)) {
    // Collect all consecutive if/await lines
    let block = [];
    while (i < lines.length && 
           (lines[i].match(/^if \(!?await fileExists/) || 
            lines[i].match(/^  await fsp\./) || 
            lines[i] === '}' ||
            lines[i].match(/^if \(!?await fileExists/))) {
      block.push(lines[i]);
      i++;
      // Check if next line is also part of the block
      if (i < lines.length && !lines[i].match(/^if \(!?await fileExists/) && 
          !lines[i].match(/^  await fsp\./) && lines[i] !== '}') {
        if (lines[i-1] === '}') break;
      }
    }
    
    // Wrap block in IIFE
    if (block.length > 0) {
      result.push('(async () => {');
      block.forEach(l => result.push('  ' + l));
      result.push('})();');
    }
  } else {
    result.push(line);
    i++;
  }
}

fs.writeFileSync('index.js', result.join('\n'));
console.log('Fixed top-level await patterns');
