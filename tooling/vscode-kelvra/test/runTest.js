"use strict";

const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const AdmZip = require("adm-zip");
const { downloadAndUnzipVSCode, runTests } = require("@vscode/test-electron");

const VSCODE_TEST_VERSION = process.env.KELVRA_VSCODE_TEST_VERSION || "1.85.2";

function platformTarget(platform = process.platform, arch = process.arch) {
  const platformName = { darwin: "darwin", linux: "linux", win32: "win32" }[platform];
  const architecture = { arm: "armhf", arm64: "arm64", x64: "x64" }[arch];
  if (!platformName || !architecture) {
    throw new Error(`Unsupported VSIX test platform: ${platform}-${arch}`);
  }
  return `${platformName}-${architecture}`;
}

function preparePackagedExtension(extensionPath, platform = process.platform, arch = process.arch) {
  const target = platformTarget(platform, arch);
  const executable = platform === "win32" ? "kelvra-lsp.exe" : "kelvra-lsp";
  const serverPath = path.join(extensionPath, "runtime", target, executable);
  if (!fs.statSync(serverPath, { throwIfNoEntry: false })?.isFile()) {
    throw new Error(`Packaged language server not found: ${serverPath}`);
  }
  // adm-zip does not restore Unix permission bits from VSIX entries. Restore
  // the executable bit so this extraction behaves like a real VS Code install.
  if (platform !== "win32") fs.chmodSync(serverPath, 0o755);
  return serverPath;
}

async function downloadedVSCodeExecutable() {
  const executable = await downloadAndUnzipVSCode(VSCODE_TEST_VERSION);
  if (process.platform !== "darwin" || fs.existsSync(executable)) return executable;

  // Newer macOS VS Code archives name the app binary `Code`, while older
  // test-electron releases derive the legacy `Electron` path.
  const appContents = path.dirname(executable);
  for (const name of ["Code", "Visual Studio Code", "Electron"]) {
    const candidate = path.join(appContents, name);
    if (fs.existsSync(candidate)) return candidate;
  }
  throw new Error(`Downloaded VS Code executable not found below ${appContents}`);
}

async function main() {
  const vsixArgument = process.argv.findIndex((value) => value === "--vsix");
  const vsixPath = process.env.KELVRA_TEST_VSIX ||
    (vsixArgument >= 0 ? process.argv[vsixArgument + 1] : undefined);
  let temporaryRoot;
  let extensionDevelopmentPath = path.resolve(__dirname, "..");
  if (vsixPath) {
    const exactArtifact = path.resolve(vsixPath);
    if (!fs.statSync(exactArtifact).isFile()) throw new Error(`VSIX not found: ${exactArtifact}`);
    temporaryRoot = fs.mkdtempSync(path.join(os.tmpdir(), "kelvra-vsix-test-"));
    new AdmZip(exactArtifact).extractAllTo(temporaryRoot, true);
    extensionDevelopmentPath = path.join(temporaryRoot, "extension");
    const packagedManifest = JSON.parse(
      fs.readFileSync(path.join(extensionDevelopmentPath, "package.json"), "utf8")
    );
    if (`${packagedManifest.publisher}.${packagedManifest.name}` !== "kelvralang.vscode-kelvra") {
      throw new Error(`Unexpected extension artifact: ${packagedManifest.publisher}.${packagedManifest.name}`);
    }
    preparePackagedExtension(extensionDevelopmentPath);
  }
  const extensionTestsPath = path.resolve(__dirname, "suite", "index");
  const workspacePath = path.resolve(__dirname, "fixtures", "multi-root.code-workspace");
  const defaultServer = path.resolve(__dirname, "..", "..", "..", "build", "kelvra-lsp");
  // Packaged-artifact tests must discover the bundled server from the VSIX.
  // A development override would accidentally test the checkout's build.
  const serverPath = process.env.KELVRA_LSP_PATH || (vsixPath ? undefined : defaultServer);
  if (serverPath && fs.existsSync(serverPath)) {
    process.env.KELVRA_LSP_DEVELOPMENT = "1";
    process.env.KELVRA_SERVER_PATH = serverPath;
  }
  const userData = fs.mkdtempSync(path.join(os.tmpdir(), "kelvra-vscode-user-"));
  const extensions = fs.mkdtempSync(path.join(os.tmpdir(), "kelvra-vscode-extensions-"));
  const extensionTestTimeoutMs = Number(process.env.KELVRA_EXTENSION_TEST_TIMEOUT_MS || 180_000);
  let timeout;
  try {
    timeout = setTimeout(() => {
      console.error(`Extension Host test exceeded ${extensionTestTimeoutMs} ms; stopping VS Code.`);
      // @vscode/test-electron handles SIGINT by closing its child process. If
      // that fails, the second timer makes the CI step fail promptly instead
      // of consuming the workflow's full six-hour job limit.
      process.emit("SIGINT");
      setTimeout(() => process.exit(1), 10_000).unref();
    }, extensionTestTimeoutMs);
    await runTests({
      vscodeExecutablePath: await downloadedVSCodeExecutable(),
      extensionDevelopmentPath,
      extensionTestsPath,
      launchArgs: [
        workspacePath,
        "--user-data-dir",
        userData,
        "--extensions-dir",
        extensions
      ]
    });
  } finally {
    clearTimeout(timeout);
    fs.rmSync(userData, { recursive: true, force: true });
    fs.rmSync(extensions, { recursive: true, force: true });
    if (temporaryRoot) fs.rmSync(temporaryRoot, { recursive: true, force: true });
  }
}

if (require.main === module) {
  main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
  });
}

module.exports = { main, platformTarget, preparePackagedExtension };
