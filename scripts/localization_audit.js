#!/usr/bin/env node

const fs = require("fs");
const path = require("path");

const repoRoot = path.resolve(__dirname, "..");
const appRoot = path.join(repoRoot, "PracticeBuddy");

function readArgs() {
  const args = process.argv.slice(2);
  const options = {
    allowMissing: false,
    locales: null,
  };

  for (const arg of args) {
    if (arg === "--allow-missing") {
      options.allowMissing = true;
      continue;
    }
    if (arg.startsWith("--locales=")) {
      const raw = arg.split("=")[1] || "";
      options.locales = raw
        .split(",")
        .map((s) => s.trim())
        .filter(Boolean);
    }
  }

  return options;
}

function walk(dir) {
  const entries = fs.readdirSync(dir, { withFileTypes: true });
  const files = [];

  for (const entry of entries) {
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) {
      if (
        entry.name === ".git" ||
        entry.name === ".build" ||
        entry.name === "DerivedData" ||
        entry.name === "Pods"
      ) {
        continue;
      }
      files.push(...walk(full));
    } else {
      files.push(full);
    }
  }

  return files;
}

function extractUsedKeys(swiftContent) {
  const keys = new Set();
  const patterns = [
    /\bText\(\s*"((?:\\"|[^"])*)"\s*\)/g,
    /\bButton\(\s*"((?:\\"|[^"])*)"\s*[,)]/g,
    /\bLabel\(\s*"((?:\\"|[^"])*)"\s*[,)]/g,
    /\bSection\(\s*"((?:\\"|[^"])*)"\s*[,)]/g,
    /\bnavigationTitle\(\s*"((?:\\"|[^"])*)"\s*\)/g,
    /\bTextField\(\s*"((?:\\"|[^"])*)"\s*[,)]/g,
    /\bSecureField\(\s*"((?:\\"|[^"])*)"\s*[,)]/g,
    /\bToggle\(\s*"((?:\\"|[^"])*)"\s*[,)]/g,
    /\bPicker\(\s*"((?:\\"|[^"])*)"\s*[,)]/g,
    /\bString\(localized:\s*"((?:\\"|[^"])*)"\s*\)/g,
    /\bLocalizedStringKey\(\s*"((?:\\"|[^"])*)"\s*\)/g,
    /\bL10n\.f\(\s*"((?:\\"|[^"])*)"/g,
  ];

  for (const pattern of patterns) {
    let match;
    while ((match = pattern.exec(swiftContent)) !== null) {
      const raw = match[1];
      const key = raw.replace(/\\"/g, '"').trim();
      if (!key) continue;
      if (key.startsWith("http://") || key.startsWith("https://")) continue;
      if (key.includes("\\(")) continue;
      if (/^[0-9\s:./#•+-]+$/.test(key)) continue;
      if (key.length <= 1) continue;
      keys.add(key);
    }
  }

  return keys;
}

function parseStringsFile(filePath) {
  const content = fs.readFileSync(filePath, "utf8");
  const keyToValue = new Map();
  const regex = /^\s*"((?:\\"|[^"])*)"\s*=\s*"((?:\\"|[^"])*)"\s*;/gm;
  let match;

  while ((match = regex.exec(content)) !== null) {
    const key = match[1].replace(/\\"/g, '"');
    const value = match[2].replace(/\\"/g, '"');
    keyToValue.set(key, value);
  }

  return keyToValue;
}

function findLocales(options) {
  const entries = fs.readdirSync(appRoot, { withFileTypes: true });
  const all = entries
    .filter((e) => e.isDirectory() && e.name.endsWith(".lproj"))
    .map((e) => e.name.replace(/\.lproj$/, ""))
    .filter((locale) => locale !== "Base");

  if (!options.locales) return all.sort();
  return all.filter((locale) => options.locales.includes(locale)).sort();
}

function main() {
  const options = readArgs();
  const allFiles = walk(appRoot);
  const swiftFiles = allFiles.filter((file) => file.endsWith(".swift"));
  const usedKeys = new Set();

  for (const swiftFile of swiftFiles) {
    const content = fs.readFileSync(swiftFile, "utf8");
    const fileKeys = extractUsedKeys(content);
    for (const key of fileKeys) usedKeys.add(key);
  }

  const locales = findLocales(options);
  if (locales.length === 0) {
    console.log("No locale folders (*.lproj) found.");
    process.exit(0);
  }

  let hasMissing = false;
  const sortedUsedKeys = Array.from(usedKeys).sort((a, b) =>
    a.localeCompare(b, "en")
  );

  console.log("Localization Audit");
  console.log(`- Swift files scanned: ${swiftFiles.length}`);
  console.log(`- Localized keys used in code: ${sortedUsedKeys.length}`);
  console.log(`- Locales checked: ${locales.join(", ")}`);
  console.log("");

  for (const locale of locales) {
    const stringsPath = path.join(appRoot, `${locale}.lproj`, "Localizable.strings");
    if (!fs.existsSync(stringsPath)) {
      hasMissing = true;
      console.log(`❌ ${locale}: missing file ${stringsPath}`);
      continue;
    }

    const keyToValue = parseStringsFile(stringsPath);
    const localeKeys = new Set(keyToValue.keys());
    const missing = sortedUsedKeys.filter((key) => !localeKeys.has(key));
    const identityValues = sortedUsedKeys.filter(
      (key) => localeKeys.has(key) && keyToValue.get(key) === key
    );

    if (missing.length > 0) hasMissing = true;

    console.log(
      `${missing.length > 0 ? "❌" : "✅"} ${locale}: ${localeKeys.size} keys, ${missing.length} missing`
    );

    if (missing.length > 0) {
      console.log(`  Missing (${Math.min(missing.length, 40)} shown):`);
      for (const key of missing.slice(0, 40)) {
        console.log(`  - ${key}`);
      }
      if (missing.length > 40) {
        console.log(`  ... and ${missing.length - 40} more`);
      }
    }

    if (identityValues.length > 0) {
      console.log(
        `  Note: ${identityValues.length} keys currently identical to source key in ${locale}.`
      );
    }
  }

  console.log("");
  if (hasMissing && !options.allowMissing) {
    console.log("Result: FAILED (missing localization keys detected)");
    process.exit(1);
  }

  if (hasMissing && options.allowMissing) {
    console.log("Result: WARN (missing keys detected, but allowed by flag)");
    process.exit(0);
  }

  console.log("Result: OK (all detected keys are present)");
  process.exit(0);
}

main();
