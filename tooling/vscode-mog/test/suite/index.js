"use strict";

const assert = require("node:assert/strict");
const path = require("node:path");
const vscode = require("vscode");

async function waitUntil(predicate, timeout = 15_000) {
  const start = Date.now();
  while (Date.now() - start < timeout) {
    const value = await predicate();
    if (value) return value;
    await new Promise((resolve) => setTimeout(resolve, 100));
  }
  throw new Error("Timed out waiting for extension state");
}

async function run() {
  const uri = vscode.Uri.file(path.resolve(__dirname, "..", "fixtures", "workspace", "main.mog"));
  const document = await vscode.workspace.openTextDocument(uri);
  await vscode.window.showTextDocument(document);
  assert.equal(document.languageId, "mog", ".mog files must use the Mog language mode");

  const extension = vscode.extensions.getExtension("moglang.vscode-mog");
  assert.ok(extension, "extension is registered");
  const api = await extension.activate();
  assert.ok(extension.isActive, "extension activates for a Mog document");
  const commands = await vscode.commands.getCommands(true);
  for (const command of [
    "mog.showServerStatus",
    "mog.restartServer",
    "mog.selectServer",
    "mog.openServerLog",
    "mog.installProjectDependencies"
  ]) {
    assert.ok(commands.includes(command), `${command} is registered`);
  }

  try {
    const instance = await waitUntil(() => {
      const current = api.manager.activeInstance();
      return current?.state === "ready" ? current : null;
    });
    if (process.env.MOG_SERVER_PATH) {
      assert.equal(instance.selection.path, path.resolve(process.env.MOG_SERVER_PATH));
    } else {
      assert.equal(instance.selection.source, "bundled server");
      assert.ok(instance.selection.path.startsWith(extension.extensionPath));
    }
    await waitUntil(() => {
      const instances = [...api.manager.instances.values()];
      return instances.length === 2 && instances.every((candidate) => candidate.state === "ready");
    });

    const completion = await vscode.commands.executeCommand(
      "vscode.executeCompletionItemProvider",
      uri,
      new vscode.Position(5, 3)
    );
    assert.ok(completion && Array.isArray(completion.items), "completion request succeeds");
    assert.ok(
      completion.items.some((item) => item.label === "print"),
      "completion returns the expected Mog builtin"
    );
    const hover = await vscode.commands.executeCommand(
      "vscode.executeHoverProvider",
      uri,
      new vscode.Position(5, 7)
    );
    assert.ok(Array.isArray(hover) && hover.length > 0, "hover returns content");
    const definitions = await vscode.commands.executeCommand(
      "vscode.executeDefinitionProvider",
      uri,
      new vscode.Position(5, 7)
    );
    assert.ok(Array.isArray(definitions) && definitions.length > 0, "definition returns a location");
    assert.equal(
      instance.client.initializeResult.capabilities.documentFormattingProvider,
      true,
      "server advertises document formatting"
    );
    await vscode.commands.executeCommand("editor.action.formatDocument");
    const rename = await vscode.commands.executeCommand(
      "vscode.executeDocumentRenameProvider",
      uri,
      new vscode.Position(5, 7),
      "Result"
    );
    assert.ok(rename instanceof vscode.WorkspaceEdit, "rename request succeeds");
    assert.ok(rename.entries().length > 0, "rename returns edits");
    const diagnostics = await waitUntil(() => {
      const current = vscode.languages.getDiagnostics(uri);
      return current.length ? current : null;
    });
    assert.ok(diagnostics.some((diagnostic) => diagnostic.severity === vscode.DiagnosticSeverity.Error));
  } finally {
    // The test runner needs all language-client child processes stopped before
    // VS Code exits. Otherwise an Extension Host can remain alive indefinitely
    // on hosted Linux and macOS runners.
    await api.manager.dispose();
  }
}

module.exports = { run };
