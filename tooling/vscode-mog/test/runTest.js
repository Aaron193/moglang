"use strict";

const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const AdmZip = require("adm-zip");
const { downloadAndUnzipVSCode, runTests } = require("@vscode/test-electron");

async function downloadedVSCodeExecutable() {
  const executable = await downloadAndUnzipVSCode();
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
  const vsixPath = process.env.MOG_TEST_VSIX ||
    (vsixArgument >= 0 ? process.argv[vsixArgument + 1] : undefined);
  let temporaryRoot;
  let extensionDevelopmentPath = path.resolve(__dirname, "..");
  if (vsixPath) {
    const exactArtifact = path.resolve(vsixPath);
    if (!fs.statSync(exactArtifact).isFile()) throw new Error(`VSIX not found: ${exactArtifact}`);
    temporaryRoot = fs.mkdtempSync(path.join(os.tmpdir(), "mog-vsix-test-"));
    new AdmZip(exactArtifact).extractAllTo(temporaryRoot, true);
    extensionDevelopmentPath = path.join(temporaryRoot, "extension");
    const packagedManifest = JSON.parse(
      fs.readFileSync(path.join(extensionDevelopmentPath, "package.json"), "utf8")
    );
    if (`${packagedManifest.publisher}.${packagedManifest.name}` !== "moglang.vscode-mog") {
      throw new Error(`Unexpected extension artifact: ${packagedManifest.publisher}.${packagedManifest.name}`);
    }
  }
  const extensionTestsPath = path.resolve(__dirname, "suite", "index");
  const workspacePath = path.resolve(__dirname, "fixtures", "multi-root.code-workspace");
  const defaultServer = path.resolve(__dirname, "..", "..", "..", "build", "mog-lsp");
  const serverPath = process.env.MOG_LSP_PATH || defaultServer;
  if (fs.existsSync(serverPath)) {
    process.env.MOG_LSP_DEVELOPMENT = "1";
    process.env.MOG_SERVER_PATH = serverPath;
  }
  const userData = fs.mkdtempSync(path.join(os.tmpdir(), "mog-vscode-user-"));
  const extensions = fs.mkdtempSync(path.join(os.tmpdir(), "mog-vscode-extensions-"));
  const extensionTestTimeoutMs = Number(process.env.MOG_EXTENSION_TEST_TIMEOUT_MS || 180_000);
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
        "--disable-extensions",
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

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
