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
  const root = fs.mkdtempSync(path.join(os.tmpdir(), "mog-discovery-"));
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
  assert.equal(executableName("linux"), "mog-lsp");
  assert.equal(executableName("darwin"), "mog-lsp");
  assert.equal(executableName("win32"), "mog-lsp.exe");
});

test("validates regular executable files", () => {
  const { root, makeExecutable } = fixture();
  const executable = makeExecutable("mog-lsp");
  assert.equal(validateExecutable(executable).valid, true);
  fs.chmodSync(executable, 0o644);
  assert.equal(validateExecutable(executable).reason, "not executable");
  assert.equal(validateExecutable(root).reason, "not a regular file");
  assert.equal(validateExecutable(path.join(root, "missing")).reason, "not found");
});

test("resolves relative overrides against their workspace scope", () => {
  assert.equal(resolveConfiguredPath("tools/mog-lsp", "/workspace/a"), "/workspace/a/tools/mog-lsp");
  assert.equal(resolveConfiguredPath("C:\\tools\\mog-lsp.exe", "C:\\work"), path.resolve("C:\\work", "C:\\tools\\mog-lsp.exe"));
});

test("finds the nearest nested Mog project", () => {
  const { root } = fixture();
  const nested = path.join(root, "packages", "game");
  fs.mkdirSync(path.join(nested, "src"), { recursive: true });
  fs.writeFileSync(path.join(root, "mog.toml"), "");
  fs.writeFileSync(path.join(nested, "mog.toml"), "");
  assert.equal(nearestProjectRoot(path.join(nested, "src", "main.mog"), root), nested);
});

test("honors deterministic override, bundle, runtime, project, workspace, PATH order", () => {
  const { root, makeExecutable } = fixture();
  const workspace = path.join(root, "workspace");
  const extension = path.join(root, "extension");
  const pathBin = path.join(root, "bin");
  fs.mkdirSync(workspace, { recursive: true });
  makeExecutable("override/mog-lsp");
  makeExecutable("extension/runtime/linux-x64/mog-lsp");
  makeExecutable("bin/mog-lsp");
  const common = {
    configuredPath: "../override/mog-lsp",
    extensionPath: extension,
    workspacePaths: [workspace],
    activeWorkspacePath: workspace,
    pathValue: pathBin,
    platform: "linux",
    arch: "x64"
  };
  const result = discoverServer(common);
  assert.equal(result.selected.source, "mog.serverPath");
  assert.equal(result.candidates.find((c) => c.valid && c.source === "bundled server").path, path.join(extension, "runtime/linux-x64/mog-lsp"));
  assert.ok(result.candidates.find((c) => c.valid && c.source === "PATH"));
  assert.ok(result.candidates.indexOf(result.candidates.find((c) => c.source === "bundled server")) < result.candidates.indexOf(result.candidates.find((c) => c.source === "active project build")));
});

test("invalid explicit override blocks silent fallback", () => {
  const { root, makeExecutable } = fixture();
  const workspace = path.join(root, "workspace");
  fs.mkdirSync(workspace);
  makeExecutable("bin/mog-lsp");
  const options = {
    configuredPath: "missing/mog-lsp",
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
  const bundled = makeExecutable("extension/runtime/win32-x64/mog-lsp.exe");
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
  assert.equal(result.selected.source, "MOG_SERVER_PATH development override");
});

test("development override accepts a multi-config build directory", () => {
  const { root, makeExecutable } = fixture();
  const buildDirectory = path.join(root, "build", "tooling-debug");
  const server = makeExecutable("build/tooling-debug/Debug/mog-lsp.exe");
  const result = discoverServer({
    developmentMode: true,
    developmentServerPath: buildDirectory,
    platform: "win32",
    arch: "x64"
  });
  assert.equal(result.selected.path, server);
  assert.equal(result.selected.source, "MOG_SERVER_PATH development override");
});

test("active project builds precede all multi-root workspace builds", () => {
  const { root, makeExecutable } = fixture();
  const outer = path.join(root, "outer");
  const nested = path.join(outer, "nested");
  const other = path.join(root, "other");
  fs.mkdirSync(nested, { recursive: true });
  fs.mkdirSync(other);
  fs.writeFileSync(path.join(nested, "mog.toml"), "");
  const active = makeExecutable("outer/nested/build/tooling-debug/mog-lsp");
  makeExecutable("other/build/mog-lsp");
  const result = discoverServer({
    workspacePaths: [outer, other],
    activeWorkspacePath: outer,
    documentPath: path.join(nested, "main.mog"),
    platform: "linux"
  });
  assert.equal(result.selected.path, active);
  assert.equal(result.projectRoot, nested);
});

test("an installed runtime server precedes workspace builds", () => {
  const { root, makeExecutable } = fixture();
  const runtime = makeExecutable("runtime/bin/mog");
  const server = makeExecutable("runtime/bin/mog-lsp");
  makeExecutable("workspace/build/mog-lsp");
  const result = discoverServer({
    runtimePath: runtime,
    workspacePaths: [path.join(root, "workspace")],
    activeWorkspacePath: path.join(root, "workspace"),
    platform: "darwin",
    arch: "arm64"
  });
  assert.equal(result.selected.path, server);
  assert.equal(result.selected.source, "installed Mog runtime");
});
