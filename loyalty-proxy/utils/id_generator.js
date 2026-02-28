/**
 * Generate a unique ID with prefix and random suffix.
 * Format: prefix_timestamp_randomsuffix
 * Example: shop_1709136000000_x7k2m9
 */
function generateId(prefix) {
  const ts = Date.now();
  const rand = Math.random().toString(36).slice(2, 8);
  return `${prefix}_${ts}_${rand}`;
}

module.exports = { generateId };
