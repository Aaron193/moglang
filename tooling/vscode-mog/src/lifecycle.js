"use strict";

const vscode = require("vscode");
const { checkCompatibility, SUPPORTED_PROTOCOL } = require("./compatibility");
const { createClient } = require("./client");
const { discoverServer, validateExecutable } = require("./discovery");
const { MAX_AUTOMATIC_RESTARTS, RestartBudget } = require("./restart");

class ServerInstance {
  constructor(manager, workspaceFolder) {
    this.manager = manager;
    this.workspaceFolder = workspaceFolder || null;
    this.key = workspaceFolder ? workspaceFolder.uri.toString() : "__untitled__";
    this.client = null;
    this.selection = null;
    this.compatibility = null;
    this.state = "stopped";
    this.failure = null;
    this.restartBudget = new RestartBudget();
    this.stopping = false;
  }

  relevantDocument() {
    const active = vscode.window.activeTextEditor?.document;
    if (active?.languageId === "mog" && this.contains(active.uri)) return active;
    return vscode.workspace.textDocuments.find(
      (document) => document.languageId === "mog" && this.contains(document.uri)
    );
  }

  contains(uri) {
    if (!this.workspaceFolder) return !vscode.workspace.getWorkspaceFolder(uri);
    return vscode.workspace.getWorkspaceFolder(uri)?.uri.toString() === this.key;
  }

  discovery(allowFallback = false) {
    const config = vscode.workspace.getConfiguration("mog", this.workspaceFolder?.uri);
    const workspacePaths = (vscode.workspace.workspaceFolders || []).map(
      (folder) => folder.uri.fsPath
    );
    const result = discoverServer({
      configuredPath: config.get("serverPath", ""),
      runtimePath: config.get("runtimePath", ""),
      developmentMode: process.env.MOG_LSP_DEVELOPMENT === "1",
      developmentServerPath: process.env.MOG_SERVER_PATH,
      extensionPath: this.manager.context.extensionPath,
      workspacePaths,
      activeWorkspacePath: this.workspaceFolder?.uri.fsPath,
      documentPath: this.relevantDocument()?.uri.fsPath,
      pathValue: process.env.PATH,
      allowInvalidExplicitFallback: allowFallback
    });
    this.manager.log(`Discovery for ${this.workspaceFolder?.name || "files outside a workspace"}:`);
    for (const candidate of result.candidates) {
      this.manager.log(
        `  ${candidate.valid ? "accepted" : "rejected"} [${candidate.source}] ${candidate.path}` +
          (candidate.reason ? ` (${candidate.reason})` : "")
      );
    }
    if (result.selected) {
      this.manager.log(`Selected ${result.selected.path} (${result.selected.source}).`);
    }
    return result;
  }

  async start(options = {}) {
    if (this.client || this.state === "starting") return;
    this.setState("starting");
    const result = this.discovery(Boolean(options.allowFallback));
    if (!result.selected) {
      const configured = result.invalidExplicit;
      const detail = configured
        ? `The configured server ${configured.path} is ${configured.reason}.`
        : "No executable server candidate was found.";
      await this.fail(detail, configured);
      return;
    }

    this.selection = { ...result.selected, cwd: result.projectRoot || this.workspaceFolder?.uri.fsPath };
    this.stopping = false;
    const client = createClient({
      serverPath: this.selection.path,
      cwd: this.selection.cwd,
      workspacePath: this.workspaceFolder?.uri.fsPath,
      workspaceFolder: this.workspaceFolder,
      outputChannel: this.manager.output,
      onClosed: () => this.onClosed(client)
    });
    this.client = client;
    try {
      await client.start();
      if (this.client !== client) return;
      this.compatibility = checkCompatibility(client.initializeResult, SUPPORTED_PROTOCOL);
      this.manager.log(
        `Initialized ${this.selection.path}; server version ${this.compatibility.serverVersion || "unknown"}; ` +
          `tooling protocol ${this.compatibility.protocolVersion ?? "unadvertised"}.`
      );
      if (!this.compatibility.compatible) {
        this.stopping = true;
        await client.stop();
        if (this.client === client) this.client = null;
        await this.fail(`Incompatible Mog language server: ${this.compatibility.reason}.`);
        return;
      }
      if (this.compatibility.legacy) {
        this.manager.log("Compatibility note: the server is legacy and did not advertise tooling metadata.");
      }
      this.failure = null;
      this.setState("ready");
    } catch (error) {
      if (this.client === client) this.client = null;
      await this.fail(`Could not start ${this.selection.path}: ${error.message || error}`);
    }
  }

  async fail(message, invalidExplicit) {
    this.failure = message;
    this.setState("failed");
    this.manager.log(`Failure: ${message}`);
    const actions = invalidExplicit
      ? ["Select Server", "Use Automatic Discovery", "Open Log"]
      : ["Select Server", "Restart", "Open Log"];
    const choice = await vscode.window.showErrorMessage(`Mog: ${message}`, ...actions);
    if (choice === "Select Server") await this.manager.selectServer(this);
    if (choice === "Use Automatic Discovery") await this.start({ allowFallback: true });
    if (choice === "Restart") await this.restart();
    if (choice === "Open Log") this.manager.output.show(true);
  }

  async onClosed(closedClient) {
    if (this.client !== closedClient || this.stopping) return;
    this.client = null;
    this.manager.log(`Language server for ${this.workspaceFolder?.name || "untitled files"} exited.`);
    const restart = this.restartBudget.record();
    if (!restart.canRestart) {
      await this.fail(
        `The language server crashed ${MAX_AUTOMATIC_RESTARTS + 1} times within a minute. Automatic restart is paused.`
      );
      return;
    }
    this.setState("starting");
    this.manager.log(`Restarting automatically in ${restart.delay} ms (${restart.attempt}/${MAX_AUTOMATIC_RESTARTS}).`);
    setTimeout(() => {
      // `start` rejects duplicate calls while the instance is marked starting.
      // Clear the scheduled state immediately before the bounded retry.
      if (!this.client && this.state === "starting" && !this.stopping) {
        this.setState("stopped");
        void this.start();
      }
    }, restart.delay);
  }

  async stop() {
    this.stopping = true;
    const client = this.client;
    this.client = null;
    if (client) {
      try {
        await client.stop();
      } catch (error) {
        this.manager.log(`Error stopping language server: ${error.message || error}`);
      }
    }
    this.setState("stopped");
  }

  async restart() {
    this.restartBudget.reset();
    await this.stop();
    this.stopping = false;
    await this.start();
  }

  setState(state) {
    this.state = state;
    this.manager.updateStatus();
  }
}

class ServerManager {
  constructor(context) {
    this.context = context;
    this.instances = new Map();
    this.updatingConfiguration = false;
    this.output = vscode.window.createOutputChannel("Mog Language Support");
    this.status = vscode.window.createStatusBarItem(vscode.StatusBarAlignment.Left, 10);
    this.status.command = "mog.showServerStatus";
    this.status.show();
    context.subscriptions.push(this.output, this.status);
    this.log(`Mog extension ${context.extension.packageJSON.version} activated.`);
    if (process.env.MOG_SERVER_PATH && process.env.MOG_LSP_DEVELOPMENT !== "1") {
      this.log("Ignored MOG_SERVER_PATH because MOG_LSP_DEVELOPMENT is not 1.");
    }
  }

  log(message) {
    this.output.appendLine(`[${new Date().toISOString()}] ${message}`);
  }

  instanceForUri(uri, create = true) {
    const folder = uri ? vscode.workspace.getWorkspaceFolder(uri) : null;
    const key = folder ? folder.uri.toString() : "__untitled__";
    if (!this.instances.has(key) && create) {
      this.instances.set(key, new ServerInstance(this, folder));
    }
    return this.instances.get(key);
  }

  activeInstance() {
    const document = vscode.window.activeTextEditor?.document;
    if (document?.languageId === "mog") return this.instanceForUri(document.uri);
    return this.instances.values().next().value;
  }

  async start() {
    const documents = vscode.workspace.textDocuments.filter((document) => document.languageId === "mog");
    const folders = vscode.workspace.workspaceFolders || [];
    if (folders.length) {
      // One process per workspace avoids cross-project package/root contamination.
      await Promise.all(folders.map((folder) => this.instanceForUri(folder.uri).start()));
    } else if (documents.length) {
      await this.instanceForUri(documents[0].uri).start();
    }
    this.updateStatus();
  }

  async openDocument(document) {
    if (document.languageId === "mog") await this.instanceForUri(document.uri).start();
  }

  updateStatus() {
    const instances = [...this.instances.values()];
    const states = instances.map((instance) => instance.state);
    let state = "stopped";
    if (states.includes("failed")) state = "failed";
    else if (states.includes("starting")) state = "starting";
    else if (states.includes("ready")) state = "ready";
    const display = {
      starting: ["$(sync~spin) Mog", "Mog language server is starting"],
      ready: ["$(check) Mog", "Mog language server is ready"],
      failed: ["$(error) Mog", "Mog language server failed; click for details"],
      stopped: ["$(circle-slash) Mog", "Mog language server is stopped"]
    }[state];
    this.status.text = display[0];
    this.status.tooltip = display[1];
  }

  async showStatus() {
    const extensionVersion = this.context.extension.packageJSON.version || "unknown";
    const rows = [...this.instances.values()].map((instance) => {
      const location = instance.workspaceFolder?.name || "files outside a workspace";
      const server = instance.selection?.path || "none";
      const serverVersion = instance.compatibility?.serverVersion || "unknown";
      const protocol = instance.compatibility?.protocolVersion ?? "unknown";
      return `${location}: ${instance.state}\nExtension: ${extensionVersion}\nServer: ${server}\nServer/runtime version: ${serverVersion}\nWorking directory: ${instance.selection?.cwd || "none"}\nTooling protocol: ${protocol}`;
    });
    const message = rows.join("\n\n") || "No Mog language server has been created.";
    const action = await vscode.window.showInformationMessage(message, "Open Log", "Restart");
    if (action === "Open Log") this.output.show(true);
    if (action === "Restart") await this.restart();
  }

  async restart() {
    const active = this.activeInstance();
    if (active) await active.restart();
    else await this.start();
  }

  async restartAll() {
    await Promise.all([...this.instances.values()].map((instance) => instance.restart()));
  }

  async selectServer(instance = this.activeInstance()) {
    const selection = await vscode.window.showOpenDialog({
      title: "Select the mog-lsp executable",
      canSelectFiles: true,
      canSelectFolders: false,
      canSelectMany: false,
      filters: process.platform === "win32" ? { Executable: ["exe"] } : undefined
    });
    if (!selection?.length) return;
    const validation = validateExecutable(selection[0].fsPath);
    if (!validation.valid) {
      void vscode.window.showErrorMessage(
        `Mog: ${selection[0].fsPath} is not a valid language server executable (${validation.reason}).`
      );
      return;
    }
    const target = instance?.workspaceFolder?.uri;
    const config = vscode.workspace.getConfiguration("mog", target);
    this.updatingConfiguration = true;
    try {
      await config.update(
        "serverPath",
        selection[0].fsPath,
        target ? vscode.ConfigurationTarget.WorkspaceFolder : vscode.ConfigurationTarget.Global
      );
    } finally {
      this.updatingConfiguration = false;
    }
    if (instance) await instance.restart();
  }

  async installDependencies() {
    const instance = this.activeInstance();
    if (!instance?.client || instance.state !== "ready") {
      void vscode.window.showErrorMessage("Mog: start the language server before installing dependencies.");
      return;
    }
    const choice = await vscode.window.showWarningMessage(
      `Install dependencies for ${instance.selection.cwd}? This may access configured package registries and modify the project.`,
      { modal: true },
      "Install"
    );
    if (choice !== "Install") return;
    await vscode.window.withProgress(
      { location: vscode.ProgressLocation.Notification, title: "Installing Mog project dependencies", cancellable: true },
      async (_progress, token) => {
        try {
          const request = instance.client.sendRequest(
            "mog/installProjectDependencies",
            { projectRoot: instance.selection.cwd },
            token
          );
          const result = await request;
          void vscode.window.showInformationMessage(result?.message || "Mog dependencies installed.");
        } catch (error) {
          this.log(`Dependency installation failed: ${error.message || error}`);
          const action = await vscode.window.showErrorMessage(
            `Mog dependency installation failed: ${error.message || error}`,
            "Open Log"
          );
          if (action === "Open Log") this.output.show(true);
        }
      }
    );
  }

  async removeWorkspaceFolders(event) {
    for (const folder of event.removed) {
      const key = folder.uri.toString();
      const instance = this.instances.get(key);
      if (instance) await instance.stop();
      this.instances.delete(key);
    }
    await Promise.all(event.added.map((folder) => this.instanceForUri(folder.uri).start()));
  }

  async dispose() {
    await Promise.all([...this.instances.values()].map((instance) => instance.stop()));
    this.instances.clear();
  }
}

module.exports = { ServerInstance, ServerManager };
