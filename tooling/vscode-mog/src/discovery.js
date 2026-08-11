"use strict";

const fs = require("fs");
const path = require("path");

const PROJECT_MARKERS = ["mog.toml", "package.toml"];

function executableName(platform = process.platform) {
  return platform === "win32" ? "mog-lsp.exe" : "mog-lsp";
}

function normalize(candidate, platform = process.platform) {
  const resolved = path.resolve(candidate);
  return platform === "win32" ? resolved.toLowerCase() : resolved;
}

function validateExecutable(candidate, options = {}) {
  const fsApi = options.fs || fs;
  const platform = options.platform || process.platform;
  if (!candidate) return { valid: false, reason: "path is empty" };
  try {
    const stat = fsApi.statSync(candidate);
    if (!stat.isFile()) return { valid: false, reason: "not a regular file" };
    if (platform !== "win32") fsApi.accessSync(candidate, fs.constants.X_OK);
    return { valid: true };
  } catch (error) {
    const reason = error && error.code === "EACCES" ? "not executable" : "not found";
    return { valid: false, reason };
  }
}

function nearestProjectRoot(documentPath, workspacePath, options = {}) {
  if (!documentPath) return workspacePath || null;
  const fsApi = options.fs || fs;
  let current = path.dirname(path.resolve(documentPath));
  const boundary = workspacePath ? path.resolve(workspacePath) : null;
  // Walking parents terminates at the workspace boundary or filesystem root.
  // eslint-disable-next-line no-constant-condition
  while (true) {
    if (PROJECT_MARKERS.some((marker) => fsApi.existsSync(path.join(current, marker)))) {
      return current;
    }
    if (current === boundary || current === path.dirname(current)) break;
    if (boundary) {
      const relative = path.relative(boundary, current);
      if (relative.startsWith("..") || path.isAbsolute(relative)) break;
    }
    current = path.dirname(current);
  }
  return workspacePath || path.dirname(path.resolve(documentPath));
}

function buildCandidates(root, executable) {
  if (!root) return [];
  return [
    path.join(root, "build", "tooling-debug", executable),
    path.join(root, "build", "tooling-debug", "Debug", executable),
    path.join(root, "build", "tooling-debug", "Release", executable),
    path.join(root, "build", executable),
    path.join(root, "build", "Debug", executable),
    path.join(root, "build", "Release", executable),
    path.join(root, "build-dev", executable)
  ];
}

function pathCandidates(pathValue, executable) {
  return (pathValue || "")
    .split(path.delimiter)
    .filter(Boolean)
    .map((directory) => path.join(directory, executable));
}

function resolveConfiguredPath(configuredPath, workspacePath) {
  if (!configuredPath) return null;
  return path.isAbsolute(configuredPath)
    ? path.normalize(configuredPath)
    : path.resolve(workspacePath || process.cwd(), configuredPath);
}

/** Deterministically discover a server and retain every rejection for diagnostics. */
function discoverServer(options = {}) {
  const platform = options.platform || process.platform;
  const arch = options.arch || process.arch;
  const executable = executableName(platform);
  const workspacePaths = options.workspacePaths || [];
  const activeWorkspacePath = options.activeWorkspacePath || workspacePaths[0] || null;
  const projectRoot = nearestProjectRoot(
    options.documentPath,
    activeWorkspacePath,
    options
  );
  const candidates = [];
  const seen = new Set();
  const add = (candidate, source, explicit = false) => {
    if (!candidate) return;
    const key = normalize(candidate, platform);
    if (seen.has(key)) return;
    seen.add(key);
    candidates.push({ path: path.resolve(candidate), source, explicit });
  };

  let developmentPath =
    options.developmentMode && options.developmentServerPath
      ? resolveConfiguredPath(options.developmentServerPath, activeWorkspacePath)
      : null;
  if (developmentPath && path.basename(developmentPath) !== executable) {
    const developmentExecutables = [
      path.join(developmentPath, executable),
      path.join(developmentPath, "Debug", executable),
      path.join(developmentPath, "Release", executable)
    ];
    developmentPath =
      developmentExecutables.find(
        (candidate) => validateExecutable(candidate, options).valid
      ) || developmentExecutables[0];
  }
  add(developmentPath, "MOG_SERVER_PATH development override", true);

  const configured = resolveConfiguredPath(options.configuredPath, activeWorkspacePath);
  add(configured, "mog.serverPath", true);

  if (options.extensionPath) {
    const vscodeTarget = {
      "darwin-arm64": "darwin-arm64",
      "linux-x64": "linux-x64",
      "win32-x64": "win32-x64"
    }[`${platform}-${arch}`];
    if (vscodeTarget) {
      add(
        path.join(options.extensionPath, "runtime", vscodeTarget, executable),
        "bundled server"
      );
    }
    add(
      path.join(options.extensionPath, "server", `${platform}-${arch}`, executable),
      "bundled server"
    );
    add(path.join(options.extensionPath, "server", executable), "bundled server");
  }

  if (options.runtimePath) {
    const runtime = resolveConfiguredPath(options.runtimePath, activeWorkspacePath);
    const runtimeDirectory = validateExecutable(runtime, options).valid ? path.dirname(runtime) : runtime;
    add(path.join(runtimeDirectory, executable), "installed Mog runtime");
    add(path.join(runtimeDirectory, "bin", executable), "installed Mog runtime");
  }

  // A `mog` executable on PATH identifies an installed runtime. Its sibling LSP
  // is checked here, before workspace build products as required by the plan.
  const runtimeExecutable = platform === "win32" ? "mog.exe" : "mog";
  for (const runtime of pathCandidates(options.pathValue, runtimeExecutable)) {
    if (validateExecutable(runtime, options).valid) {
      add(path.join(path.dirname(runtime), executable), "installed Mog runtime");
    }
  }

  for (const candidate of buildCandidates(projectRoot, executable)) {
    add(candidate, "active project build");
  }
  for (const workspacePath of workspacePaths) {
    for (const candidate of buildCandidates(workspacePath, executable)) {
      add(candidate, "workspace build");
    }
  }
  for (const candidate of pathCandidates(options.pathValue, executable)) {
    add(candidate, "PATH");
  }

  let selected = null;
  let invalidExplicit = null;
  const results = candidates.map((candidate) => {
    const validation = validateExecutable(candidate.path, options);
    const result = { ...candidate, ...validation };
    if (!validation.valid && candidate.explicit && !invalidExplicit) invalidExplicit = result;
    if (!selected && validation.valid) selected = result;
    return result;
  });

  // A bad explicit setting is a configuration error, not permission to silently
  // select another executable. The caller may offer an explicit fallback action.
  if (
    invalidExplicit &&
    !options.allowInvalidExplicitFallback &&
    (!selected || results.indexOf(invalidExplicit) < results.indexOf(selected))
  ) {
    selected = null;
  }
  return { selected, candidates: results, invalidExplicit, projectRoot };
}

module.exports = {
  PROJECT_MARKERS,
  buildCandidates,
  discoverServer,
  executableName,
  nearestProjectRoot,
  pathCandidates,
  resolveConfiguredPath,
  validateExecutable
};
