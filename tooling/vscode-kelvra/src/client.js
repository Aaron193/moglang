"use strict";

const vscode = require("vscode");
const {
  CloseAction,
  ErrorAction,
  LanguageClient,
  TransportKind
} = require("vscode-languageclient/node");

function documentPattern(workspacePath) {
  if (!workspacePath) return undefined;
  return `${workspacePath.replace(/\\/g, "/").replace(/[{}[\]*?]/g, "\\$&")}/**/*.kel`;
}

function createClient(options) {
  const { serverPath, cwd, workspacePath, outputChannel, onClosed } = options;
  const executable = {
    command: serverPath,
    transport: TransportKind.stdio,
    options: cwd ? { cwd } : undefined
  };
  const selector = { scheme: "file", language: "kelvra" };
  const pattern = documentPattern(workspacePath);
  if (pattern) selector.pattern = pattern;
  const watchedFiles = vscode.workspace.createFileSystemWatcher(
    options.workspaceFolder
      ? new vscode.RelativePattern(options.workspaceFolder, "**/*.{kelvra,toml}")
      : "**/*.{kelvra,toml}"
  );
  const errorHandler = {
    error: () => ({ action: ErrorAction.Continue }),
    closed: () => {
      if (onClosed) onClosed();
      // Restarts are owned by the lifecycle manager so they are bounded.
      return { action: CloseAction.DoNotRestart };
    }
  };
  return new LanguageClient(
    `kelvra-${Buffer.from(workspacePath || "untitled").toString("hex").slice(-16)}`,
    "Kelvra Language Server",
    { run: executable, debug: executable },
    {
      documentSelector: [selector],
      outputChannel,
      workspaceFolder: options.workspaceFolder,
      initializationOptions: {
        kelvra: { toolingProtocol: { min: 1, max: 1 }, explicitDependencyInstallation: true }
      },
      synchronize: { fileEvents: watchedFiles },
      errorHandler
    }
  );
}

module.exports = { createClient, documentPattern };
