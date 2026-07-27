import fs from "node:fs";
import path from "node:path";
import process from "node:process";

const repositoryRoot = path.resolve(
  path.dirname(new URL(import.meta.url).pathname),
  "..",
);
const metadataPath = path.join(
  repositoryRoot,
  "Docs",
  "APP_STORE_RELEASE_METADATA_2.0.md",
);
const source = fs.readFileSync(metadataPath, "utf8");

function section(heading, nextHeading) {
  const startMarker = `### ${heading}\n`;
  const start = source.indexOf(startMarker);
  if (start < 0) {
    throw new Error(`Missing metadata section: ${heading}`);
  }

  const contentStart = start + startMarker.length;
  const end = nextHeading
    ? source.indexOf(`### ${nextHeading}\n`, contentStart)
    : source.indexOf("\n## ", contentStart);
  const raw = source.slice(contentStart, end < 0 ? source.length : end).trim();

  return raw
    .replace(/\n(?=[^\n•\d])/g, " ")
    .replace(/[ \t]+/g, " ")
    .replace(/  \n/g, "\n");
}

const fields = [
  {
    name: "Subtitle",
    value: section("Subtitle", "Promotional text"),
    maximum: 30,
  },
  {
    name: "Promotional text",
    value: section("Promotional text", "Description"),
    maximum: 170,
  },
  {
    name: "Description",
    value: section("Description", "What’s New"),
    maximum: 4_000,
  },
  {
    name: "What’s New",
    value: section("What’s New"),
    maximum: 4_000,
  },
];

let failed = false;

for (const field of fields) {
  const count = [...field.value].length;
  const status = count <= field.maximum ? "PASS" : "FAIL";
  process.stdout.write(
    `${status} ${field.name}: ${count}/${field.maximum} characters\n`,
  );
  failed ||= count > field.maximum;
}

if (failed) {
  process.exitCode = 1;
}
