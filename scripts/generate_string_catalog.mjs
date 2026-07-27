#!/usr/bin/env node

import { readdir, readFile, stat, writeFile } from "node:fs/promises";
import os from "node:os";
import path from "node:path";

const projectRoot = process.cwd();
const outputPath = path.join(projectRoot, "PracticeBuddy", "Localizable.xcstrings");
const translationCachePath = path.join(projectRoot, "scripts", ".studioquest-translation-cache.json");

async function resolveStringsDataDirectory() {
  if (process.argv[2]) return path.resolve(process.argv[2]);

  const derivedDataRoot = path.join(
    os.homedir(),
    "Library",
    "Developer",
    "Xcode",
    "DerivedData",
  );
  const derivedDataEntries = await readdir(derivedDataRoot, {
    withFileTypes: true,
  });
  const candidates = [];

  for (const entry of derivedDataEntries) {
    if (!entry.isDirectory() || !entry.name.startsWith("PracticeBuddy-")) continue;
    const candidate = path.join(
      derivedDataRoot,
      entry.name,
      "Build",
      "Intermediates.noindex",
      "PracticeBuddy.build",
      "Debug-iphonesimulator",
      "PracticeBuddy.build",
      "Objects-normal",
      "arm64",
    );
    try {
      const metadata = await stat(candidate);
      candidates.push({ path: candidate, modifiedAt: metadata.mtimeMs });
    } catch {
      // This DerivedData entry has not produced simulator localization data.
    }
  }

  candidates.sort((left, right) => right.modifiedAt - left.modifiedAt);
  if (!candidates[0]) {
    throw new Error(
      "No current PracticeBuddy simulator stringsdata was found. Build the PracticeBuddy scheme first, or pass its Objects-normal/arm64 directory as the first argument.",
    );
  }
  return candidates[0].path;
}

const stringsDataDirectory = await resolveStringsDataDirectory();

async function readExistingCatalog(language) {
  try {
    const catalog = JSON.parse(await readFile(outputPath, "utf8"));
    return Object.fromEntries(
      Object.entries(catalog.strings ?? {}).flatMap(([key, entry]) => {
        const value = entry?.localizations?.[language]?.stringUnit?.value;
        return typeof value === "string" && value.length > 0 ? [[key, value]] : [];
      }),
    );
  } catch {
    return {};
  }
}

async function extractedKeys() {
  const filenames = await readdir(stringsDataDirectory);
  const keys = new Set();

  for (const filename of filenames.filter((name) => name.endsWith(".stringsdata"))) {
    const payload = JSON.parse(
      await readFile(path.join(stringsDataDirectory, filename), "utf8"),
    );
    for (const entry of payload.tables?.Localizable ?? []) {
      if (entry.key) keys.add(entry.key);
    }
  }
  if (keys.size === 0) {
    throw new Error(
      `No Localizable strings were extracted from ${stringsDataDirectory}. Refusing to replace the catalog.`,
    );
  }
  return keys;
}

function protectFormatting(value) {
  const formats = [];
  const protectedValue = value.replace(
    /%(\d+\$)?(?:lld|ld|d|@|\.\d+f)|%%/g,
    (format) => {
      const token = `ZXQFMT${formats.length}QXZ`;
      formats.push(format);
      return token;
    },
  );
  return { protectedValue, formats };
}

function restoreFormatting(value, formats) {
  let restored = value;
  formats.forEach((format, index) => {
    const tokenPattern = new RegExp(`ZXQ\\s*FMT\\s*${index}\\s*QXZ`, "gi");
    restored = restored.replace(tokenPattern, format);
  });
  return restored;
}

async function translate(text, language) {
  const { protectedValue, formats } = protectFormatting(text);
  const url = new URL("https://translate.googleapis.com/translate_a/single");
  url.searchParams.set("client", "gtx");
  url.searchParams.set("sl", "en");
  url.searchParams.set("tl", language);
  url.searchParams.set("dt", "t");
  url.searchParams.set("q", protectedValue);

  for (let attempt = 0; attempt < 4; attempt += 1) {
    const response = await fetch(url, {
      headers: { "User-Agent": "PractiQuest-Localization-Build/2.0" },
    });
    if (response.ok) {
      const payload = await response.json();
      const translated = (payload[0] ?? []).map((part) => part[0] ?? "").join("");
      return restoreFormatting(translated, formats);
    }
    await new Promise((resolve) => setTimeout(resolve, 750 * (attempt + 1)));
  }
  throw new Error(`Translation failed for ${language}: ${text}`);
}

async function loadCache() {
  try {
    return JSON.parse(await readFile(translationCachePath, "utf8"));
  } catch {
    return {};
  }
}

async function translateMissing(keys, language, existing, cache) {
  const results = { ...existing };
  const missing = keys.filter((key) => !results[key]);
  let cursor = 0;

  async function worker() {
    while (cursor < missing.length) {
      const index = cursor;
      cursor += 1;
      const key = missing[index];
      const cacheKey = `${language}:${key}`;
      results[key] = cache[cacheKey] ?? (await translate(key, language));
      cache[cacheKey] = results[key];
      if (index % 20 === 0) {
        await writeFile(translationCachePath, `${JSON.stringify(cache, null, 2)}\n`);
      }
    }
  }

  await Promise.all(Array.from({ length: 6 }, () => worker()));
  await writeFile(translationCachePath, `${JSON.stringify(cache, null, 2)}\n`);
  return results;
}

const sourceKeys = await extractedKeys();
const existingKorean = await readExistingCatalog("ko");
const existingRomanian = await readExistingCatalog("ro");
const allKeys = [...sourceKeys].sort((left, right) =>
  left.localeCompare(right, "en"),
);

const cache = await loadCache();
const korean = await translateMissing(allKeys, "ko", existingKorean, cache);
const romanian = await translateMissing(allKeys, "ro", existingRomanian, cache);

const strings = {};
for (const key of allKeys) {
  strings[key] = {
    localizations: {
      ko: {
        stringUnit: {
          state: "translated",
          value: korean[key],
        },
      },
      ro: {
        stringUnit: {
          state: "translated",
          value: romanian[key],
        },
      },
    },
  };
}

const catalog = {
  sourceLanguage: "en",
  strings,
  version: "1.0",
};

await writeFile(outputPath, `${JSON.stringify(catalog, null, 2)}\n`);
console.log(
  `Wrote ${outputPath} from ${stringsDataDirectory} with ${allKeys.length} source keys; Korean and Romanian have complete coverage.`,
);
