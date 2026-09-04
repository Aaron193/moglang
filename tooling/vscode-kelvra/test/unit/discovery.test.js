"use strict";

const assert = require("node:assert/strict");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const test = require("node:test");
const {
  discoverServer,
  executableName,
  nearestProjectRoot,
  resolveConfiguredPath,
  validateExecutable
} = require("../../src/discovery");

function fixture() {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), "kelvra-discovery-"));
  const makeExecutable = (relative) => {
    const target = path.join(root, relative);
    fs.mkdirSync(path.dirname(target), { recursive: true });
    fs.writeFileSync(target, "server");
    fs.chmodSync(target, 0o755);
    return target;
  };
  return { root, makeExecutable };
}

test("uses the platform executable name", () => {
  assert.equal(executableName("linux"), "kelvra-lsp");
  assert.equal(executableName("darwin"), "kelvra-lsp");
  assert.equal(executableName("win32"), "kelvra-lsp.exe");
});

test("validates regular executable files", () => {
  const { root, makeExecutable } = fixture();
  const executable = makeExecutable("kelvra-lsp");
  assert.equal(validateExecutable(executable).valid, true);
  fs.chmodSync(executable, 0o644);
  assert.equal(validateExecutable(executable).reason, "not executable");
  assert.equal(validateExecutable(root).reason, "not a regular file");
  assert.equal(validateExecutable(path.join(root, "missing")).reason, "not found");
});

test("resolves relative overrides against their workspace scope", () => {
  assert.equal(resolveConfiguredPath("tools/kelvra-lsp", "/workspace/a"), "/workspace/a/tools/kelvra-lsp");
  assert.equal(resolveConfiguredPath("C:\\tools\\kelvra-lsp.exe", "C:\\work"), path.resolve("C:\\work", "C:\\tools\\kelvra-lsp.exe"));
});

test("finds the nearest nested Kelvra project", () => {
  const { root } = fixture();
  const nested = path.join(root, "packages", "game");
  fs.mkdirSync(path.join(nested, "src"), { recursive: true });
  fs.writeFileSync(path.join(root, "kelvra.toml"), "");
  fs.writeFileSync(path.join(nested, "kelvra.toml"), "");
  assert.equal(nearestProjectRoot(path.join(nested, "src", "main.kel"), root), nested);
});

test("honors deterministic override, bundle, runtime, project, workspace, PATH order", () => {
  const { root, makeExecutable } = fixture();
  const workspace = path.join(root, "workspace");
  const extension = path.join(root, "extension");
  const pathBin = path.join(root, "bin");
  fs.mkdirSync(workspace, { recursive: true });
  makeExecutable("override/kelvra-lsp");
  makeExecutable("extension/runtime/linux-x64/kelvra-lsp");
  makeExecutable("bin/kelvra-lsp");
  const common = {
    configuredPath: "../override/kelvra-lsp",
    extensionPath: extension,
    workspacePaths: [workspace],
    activeWorkspacePath: workspace,
    pathValue: pathBin,
    platform: "linux",
    arch: "x64"
  };
  const result = discoverServer(common);
  assert.equal(result.selected.source, "kelvra.serverPath");
  assert.equal(result.candidates.find((c) => c.valid && c.source === "bundled server").path, path.join(extension, "runtime/linux-x64/kelvra-lsp"));
  assert.ok(result.candidates.find((c) => c.valid && c.source === "PATH"));
  assert.ok(result.candidates.indexOf(result.candidates.find((c) => c.source === "bundled server")) < result.candidates.indexOf(result.candidates.find((c) => c.source === "active project build")));
});

test("invalid explicit override blocks silent fallback", () => {
  const { root, makeExecutable } = fixture();
  const workspace = path.join(root, "workspace");
  fs.mkdirSync(workspace);
  makeExecutable("bin/kelvra-lsp");
  const options = {
    configuredPath: "missing/kelvra-lsp",
    workspacePaths: [workspace],
    activeWorkspacePath: workspace,
    pathValue: path.join(root, "bin"),
    platform: "linux"
  };
  assert.equal(discoverServer(options).selected, null);
  assert.equal(discoverServer({ ...options, allowInvalidExplicitFallback: true }).selected.source, "PATH");
});

test("development override is gated and Windows bundled layout is supported", () => {
  const { root, makeExecutable } = fixture();
  const extension = path.join(root, "extension");
  const bundled = makeExecutable("extension/runtime/win32-x64/kelvra-lsp.exe");
  let result = discoverServer({
    developmentMode: false,
    developmentServerPath: bundled,
    extensionPath: extension,
    platform: "win32",
    arch: "x64"
  });
  assert.equal(result.selected.source, "bundled server");
  result = discoverServer({
    developmentMode: true,
    developmentServerPath: bundled,
    extensionPath: extension,
    platform: "win32",
    arch: "x64"
  });
  assert.equal(result.selected.source, "KELVRA_SERVER_PATH development override");
});

test("development override accepts a multi-config build directory", () => {
  const { root, makeExecutable } = fixture();
  const buildDirectory = path.join(root, "build", "tooling-debug");
  const server = makeExecutable("build/tooling-debug/Debug/kelvra-lsp.exe");
  const result = discoverServer({
    developmentMode: true,
    developmentServerPath: buildDirectory,
    platform: "win32",
    arch: "x64"
  });
  assert.equal(result.selected.path, server);
  assert.equal(result.selected.source, "KELVRA_SERVER_PATH development override");
});

test("active project builds precede all multi-root workspace builds", () => {
  const { root, makeExecutable } = fixture();
  const outer = path.join(root, "outer");
  const nested = path.join(outer, "nested");
  const other = path.join(root, "other");
  fs.mkdirSync(nested, { recursive: true });
  fs.mkdirSync(other);
  fs.writeFileSync(path.join(nested, "kelvra.toml"), "");
  const active = makeExecutable("outer/nested/build/tooling-debug/kelvra-lsp");
  makeExecutable("other/build/kelvra-lsp");
  const result = discoverServer({
    workspacePaths: [outer, other],
    activeWorkspacePath: outer,
    documentPath: path.join(nested, "main.kel"),
    platform: "linux"
  });
  assert.equal(result.selected.path, active);
  assert.equal(result.projectRoot, nested);
});

test("an installed runtime server precedes workspace builds", () => {
  const { root, makeExecutable } = fixture();
  const runtime = makeExecutable("runtime/bin/kelvra");
  const server = makeExecutable("runtime/bin/kelvra-lsp");
  makeExecutable("workspace/build/kelvra-lsp");
  const result = discoverServer({
    runtimePath: runtime,
    workspacePaths: [path.join(root, "workspace")],
    activeWorkspacePath: path.join(root, "workspace"),
    platform: "darwin",
    arch: "arm64"
  });
  assert.equal(result.selected.path, server);
  assert.equal(result.selected.source, "installed Kelvra runtime");
});
