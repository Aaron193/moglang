"use strict";

const vscode = require("vscode");
const { ServerManager } = require("./src/lifecycle");

let manager;

async function activate(context) {
  manager = new ServerManager(context);
  context.subscriptions.push(
    vscode.commands.registerCommand("mog.showServerStatus", () => manager.showStatus()),
    vscode.commands.registerCommand("mog.restartServer", () => manager.restart()),
    vscode.commands.registerCommand("mog.selectServer", () => manager.selectServer()),
    vscode.commands.registerCommand("mog.openServerLog", () => manager.output.show(true)),
    vscode.commands.registerCommand("mog.installProjectDependencies", () => manager.installDependencies()),
    vscode.workspace.onDidOpenTextDocument((document) => manager.openDocument(document)),
    vscode.workspace.onDidChangeWorkspaceFolders((event) => manager.removeWorkspaceFolders(event)),
    vscode.workspace.onDidChangeConfiguration((event) => {
      if (
        !manager.updatingConfiguration &&
        (event.affectsConfiguration("mog.serverPath") || event.affectsConfiguration("mog.runtimePath"))
      ) {
        void manager.restartAll();
      }
    })
  );
  await manager.start();
  return { manager };
}

async function deactivate() {
  const current = manager;
  manager = undefined;
  if (current) await current.dispose();
}

module.exports = { activate, deactivate };
