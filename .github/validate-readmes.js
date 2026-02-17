#!/usr/bin/env node

/**
 * Validates YAML frontmatter in all test README.md files against the schema
 * defined in readme-schema.js. Zero external dependencies.
 */

const fs = require("fs");
const path = require("path");
const { readmeSchema } = require("./readme-schema");

const TEST_DIR = path.join(__dirname, "..", "test");
// ^ __dirname is .github/, so ".." points to the repo root
const SKIP_DIRS = new Set(["interfaces", "modules", "utils"]);

// ── Minimal YAML parser (handles the subset used in frontmatter) ────────────

function parseYaml(text) {
  const lines = text.split("\n");
  const root = {};
  let i = 0;
  while (i < lines.length) {
    i = parseObject(lines, i, 0, root);
  }
  return root;
}

function parseObject(lines, i, indent, obj) {
  while (i < lines.length) {
    const line = lines[i];
    if (/^\s*$/.test(line) || /^\s*#/.test(line)) { i++; continue; }

    const currentIndent = line.search(/\S/);
    if (currentIndent < indent) return i;

    const keyMatch = line.match(/^(\s*)([\w]+)\s*:\s*(.*)/);
    if (!keyMatch) return i;

    const keyIndent = keyMatch[1].length;
    if (keyIndent !== indent) return i;

    const key = keyMatch[2];
    let value = keyMatch[3].trim();
    if (!value.startsWith('"') && !value.startsWith("'")) {
      value = value.replace(/\s+#.*$/, "");
    }

    if (value === "" || value.startsWith("#")) {
      i++;
      if (i < lines.length) {
        const next = findNextNonEmpty(lines, i);
        if (next < lines.length && lines[next].trimStart().startsWith("-")) {
          const arr = [];
          i = parseArray(lines, i, keyIndent + 2, arr);
          obj[key] = arr;
        } else {
          const nested = {};
          i = parseObject(lines, i, keyIndent + 2, nested);
          obj[key] = Object.keys(nested).length > 0 ? nested : "";
        }
      }
    } else if (value.startsWith("[")) {
      obj[key] = parseInlineArray(value);
      i++;
    } else {
      obj[key] = parseScalar(value);
      i++;
    }
  }
  return i;
}

function parseArray(lines, i, indent, arr) {
  while (i < lines.length) {
    const line = lines[i];
    if (/^\s*$/.test(line) || /^\s*#/.test(line)) { i++; continue; }

    const currentIndent = line.search(/\S/);
    if (currentIndent < indent && !line.trim().startsWith("-")) return i;

    const itemMatch = line.match(/^(\s*)-\s*(.*)/);
    if (!itemMatch) return i;

    const itemIndent = itemMatch[1].length;
    if (itemIndent < indent - 2) return i;

    const value = itemMatch[2].trim();
    const objKeyMatch = value.match(/^([\w]+)\s*:\s*(.*)/);
    if (objKeyMatch) {
      const obj = {};
      obj[objKeyMatch[1]] = parseScalar(objKeyMatch[2].trim());
      i++;
      i = parseObject(lines, i, itemIndent + 2, obj);
      arr.push(obj);
    } else {
      arr.push(parseScalar(value));
      i++;
    }
  }
  return i;
}

function parseInlineArray(str) {
  str = str.trim();
  if (str === "[]") return [];
  str = str.slice(1, -1).trim();
  if (!str) return [];

  const items = [];
  let current = "";
  let inQuote = false;
  let quoteChar = "";
  for (let c = 0; c < str.length; c++) {
    const ch = str[c];
    if (inQuote) {
      if (ch === quoteChar) inQuote = false;
      else current += ch;
    } else if (ch === '"' || ch === "'") {
      inQuote = true;
      quoteChar = ch;
    } else if (ch === ",") {
      items.push(parseScalar(current.trim()));
      current = "";
    } else {
      current += ch;
    }
  }
  if (current.trim()) items.push(parseScalar(current.trim()));
  return items;
}

function parseScalar(value) {
  if (!value && value !== 0) return "";
  if ((value.startsWith('"') && value.endsWith('"')) ||
      (value.startsWith("'") && value.endsWith("'"))) {
    return value.slice(1, -1);
  }
  if (/^-?\d+(\.\d+)?$/.test(value)) return Number(value);
  if (value === "true") return true;
  if (value === "false") return false;
  return value;
}

function findNextNonEmpty(lines, i) {
  while (i < lines.length && (/^\s*$/.test(lines[i]) || /^\s*#/.test(lines[i]))) i++;
  return i;
}

// ── Frontmatter extraction ──────────────────────────────────────────────────

function extractFrontmatter(content) {
  const match = content.match(/^---\r?\n([\s\S]*?)\r?\n---/);
  return match ? match[1] : null;
}

// ── Schema-driven validation ────────────────────────────────────────────────

function validate(data, schema) {
  const errors = [];

  for (const [field, rule] of Object.entries(schema)) {
    const value = data[field];
    const required = rule.required !== false;
    const missing = value === undefined || value === "";

    if (missing) {
      if (required && rule.default === undefined) {
        errors.push(`  ${field}: required`);
      }
      continue;
    }

    switch (rule.type) {
      case "string":
        if (typeof value !== "string") {
          errors.push(`  ${field}: expected string, got ${typeof value}`);
        }
        break;

      case "number": {
        if (typeof value !== "number") {
          errors.push(`  ${field}: expected number, got ${typeof value}`);
        } else if (rule.min !== undefined && value < rule.min) {
          errors.push(`  ${field}: must be >= ${rule.min}, got ${value}`);
        }
        break;
      }

      case "date": {
        const str = String(value);
        if (!/^\d{4}-\d{2}-\d{2}$/.test(str)) {
          errors.push(`  ${field}: invalid date format "${str}", expected YYYY-MM-DD`);
        } else if (isNaN(new Date(str + "T00:00:00Z").getTime())) {
          errors.push(`  ${field}: invalid date "${str}"`);
        }
        break;
      }

      case "array": {
        if (!Array.isArray(value)) {
          errors.push(`  ${field}: expected array, got ${typeof value}`);
        } else {
          for (let idx = 0; idx < value.length; idx++) {
            if (typeof value[idx] !== rule.items) {
              errors.push(`  ${field}[${idx}]: expected ${rule.items}, got ${typeof value[idx]}`);
            }
          }
        }
        break;
      }

      case "objectArray": {
        if (!Array.isArray(value)) {
          errors.push(`  ${field}: expected array of objects, got ${typeof value}`);
        } else {
          for (let idx = 0; idx < value.length; idx++) {
            const item = value[idx];
            if (typeof item !== "object" || item === null) {
              errors.push(`  ${field}[${idx}]: expected object`);
              continue;
            }
            for (const [key, expectedType] of Object.entries(rule.items)) {
              if (typeof item[key] !== expectedType || !item[key]) {
                errors.push(`  ${field}[${idx}].${key}: expected non-empty ${expectedType}`);
              }
            }
          }
        }
        break;
      }

      default:
        errors.push(`  ${field}: unknown schema type "${rule.type}"`);
    }
  }

  return errors;
}

// ── File discovery ──────────────────────────────────────────────────────────

function findReadmes(dir) {
  const results = [];
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    if (!entry.isDirectory() || SKIP_DIRS.has(entry.name)) continue;
    const subdir = path.join(dir, entry.name);
    const readme = path.join(subdir, "README.md");
    if (fs.existsSync(readme)) results.push(readme);

    for (const sub of fs.readdirSync(subdir, { withFileTypes: true })) {
      if (!sub.isDirectory()) continue;
      const nested = path.join(subdir, sub.name, "README.md");
      if (fs.existsSync(nested)) results.push(nested);
    }
  }
  return results.sort();
}

// ── Main ────────────────────────────────────────────────────────────────────

function main() {
  const readmes = findReadmes(TEST_DIR);
  if (readmes.length === 0) {
    console.error("No README.md files found in test/ subdirectories.");
    process.exit(1);
  }

  let totalErrors = 0;
  let passed = 0;

  for (const filePath of readmes) {
    const rel = path.relative(process.cwd(), filePath);
    const content = fs.readFileSync(filePath, "utf-8");
    const raw = extractFrontmatter(content);

    if (!raw) {
      console.error(`FAIL ${rel}: No YAML frontmatter found`);
      totalErrors++;
      continue;
    }

    let data;
    try {
      data = parseYaml(raw);
    } catch (e) {
      console.error(`FAIL ${rel}: Failed to parse YAML: ${e.message}`);
      totalErrors++;
      continue;
    }

    const errors = validate(data, readmeSchema);
    if (errors.length > 0) {
      console.error(`FAIL ${rel}:`);
      errors.forEach((e) => console.error(e));
      totalErrors += errors.length;
    } else {
      passed++;
    }
  }

  console.log(`\n${readmes.length} files checked, ${passed} passed, ${totalErrors} error(s).`);
  if (totalErrors > 0) {
    process.exit(1);
  } else {
    console.log("All README frontmatters inside test folder are valid.");
  }
}

main();
