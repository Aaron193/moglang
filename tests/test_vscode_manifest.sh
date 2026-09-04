#!/bin/bash
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

node - "$PROJECT_ROOT" <<'NODE'
const fs = require("fs");
const path = require("path");

const projectRoot = process.argv[2];
const manifestPath = path.join(
  projectRoot,
  "tooling",
  "vscode-kelvra",
  "package.json"
);
const manifest = JSON.parse(fs.readFileSync(manifestPath, "utf8"));

function fail(message) {
  console.error(`[FAIL] ${message}`);
  process.exit(1);
}

function requireCondition(condition, message) {
  if (!condition) {
    fail(message);
  }
}

const languages = manifest.contributes?.languages;
requireCondition(Array.isArray(languages), "manifest should contribute languages");

const kelvraLanguage = languages.find((language) => language.id === "kelvra");
requireCondition(kelvraLanguage !== undefined, "manifest should contribute the kelvra language");
requireCondition(
  Array.isArray(kelvraLanguage.extensions) && kelvraLanguage.extensions.includes(".kel"),
  "kelvra language should still register the .kel extension"
);

const icon = kelvraLanguage.icon;
requireCondition(icon && typeof icon === "object", "kelvra language should declare an icon");
requireCondition(
  icon.light === "./images/fileicons/icon.png",
  "kelvra language should use the expected light icon path"
);
requireCondition(
  icon.dark === "./images/fileicons/icon.png",
  "kelvra language should use the expected dark icon path"
);

for (const variant of ["light", "dark"]) {
  const iconPath = path.join(projectRoot, "tooling", "vscode-kelvra", icon[variant].slice(2));
  requireCondition(fs.existsSync(iconPath), `${variant} icon should exist at ${icon[variant]}`);
}

console.log("[PASS] VS Code manifest registers the Kelvra file icon");
NODE
