"use strict";

const assert = require("node:assert/strict");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const test = require("node:test");
const { platformTarget, preparePackagedExtension } = require("../runTest");

test("maps Node platforms to VS Code extension targets", () => {
  assert.equal(platformTarget("linux", "x64"), "linux-x64");
  assert.equal(platformTarget("darwin", "arm64"), "darwin-arm64");
  assert.equal(platformTarget("win32", "x64"), "win32-x64");
  assert.throws(() => platformTarget("aix", "ppc64"), /Unsupported VSIX test platform/);
});

test("restores the packaged Unix language server executable bit", (t) => {
  const extensionPath = fs.mkdtempSync(path.join(os.tmpdir(), "mog-vsix-harness-"));
  t.after(() => fs.rmSync(extensionPath, { recursive: true, force: true }));
  const serverPath = path.join(extensionPath, "runtime", "linux-x64", "mog-lsp");
  fs.mkdirSync(path.dirname(serverPath), { recursive: true });
  fs.writeFileSync(serverPath, "server");
  fs.chmodSync(serverPath, 0o666);

  assert.equal(preparePackagedExtension(extensionPath, "linux", "x64"), serverPath);
  fs.accessSync(serverPath, fs.constants.X_OK);
});

test("rejects a packaged extension without its target server", (t) => {
  const extensionPath = fs.mkdtempSync(path.join(os.tmpdir(), "mog-vsix-harness-"));
  t.after(() => fs.rmSync(extensionPath, { recursive: true, force: true }));
  assert.throws(
    () => preparePackagedExtension(extensionPath, "darwin", "arm64"),
    /Packaged language server not found/
  );
});
