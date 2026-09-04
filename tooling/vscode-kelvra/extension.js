"use strict";

const vscode = require("vscode");
const { ServerManager } = require("./src/lifecycle");

let manager;

async function activate(context) {
  manager = new ServerManager(context);
  context.subscriptions.push(
    vscode.commands.registerCommand("kelvra.showServerStatus", () => manager.showStatus()),
    vscode.commands.registerCommand("kelvra.restartServer", () => manager.restart()),
    vscode.commands.registerCommand("kelvra.selectServer", () => manager.selectServer()),
    vscode.commands.registerCommand("kelvra.openServerLog", () => manager.output.show(true)),
    vscode.commands.registerCommand("kelvra.installProjectDependencies", () => manager.installDependencies()),
    vscode.workspace.onDidOpenTextDocument((document) => manager.openDocument(document)),
    vscode.workspace.onDidChangeWorkspaceFolders((event) => manager.removeWorkspaceFolders(event)),
    vscode.workspace.onDidChangeConfiguration((event) => {
      if (
        !manager.updatingConfiguration &&
        (event.affectsConfiguration("kelvra.serverPath") || event.affectsConfiguration("kelvra.runtimePath"))
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
