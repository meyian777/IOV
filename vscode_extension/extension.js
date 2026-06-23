const vscode = require("vscode");
const http = require("http");
const https = require("https");

let statusItem;
let syncTimer;
let lastContext = null;

function backendUrl() {
  return vscode.workspace
    .getConfiguration("labvoice")
    .get("backendUrl", "http://127.0.0.1:8000")
    .replace(/\/$/, "");
}

function postJson(url, payload) {
  return new Promise((resolve, reject) => {
    const target = new URL(url);
    const body = JSON.stringify(payload);
    const transport = target.protocol === "https:" ? https : http;
    const request = transport.request(
      target,
      {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "Content-Length": Buffer.byteLength(body),
        },
        timeout: 5000,
      },
      (response) => {
        let responseBody = "";
        response.setEncoding("utf8");
        response.on("data", (chunk) => {
          responseBody += chunk;
        });
        response.on("end", () => {
          if (
            response.statusCode &&
            response.statusCode >= 200 &&
            response.statusCode < 300
          ) {
            resolve(responseBody ? JSON.parse(responseBody) : {});
            return;
          }
          reject(
            new Error(
              `LabVoice returned HTTP ${response.statusCode}: ${responseBody}`,
            ),
          );
        });
      },
    );
    request.on("timeout", () => request.destroy(new Error("Request timed out")));
    request.on("error", reject);
    request.write(body);
    request.end();
  });
}

function isLocalFile(document) {
  return document && document.uri.scheme === "file";
}

async function collectContext() {
  const configuration = vscode.workspace.getConfiguration("labvoice");
  const maxFiles = configuration.get("maxWorkspaceFiles", 5000);
  const workspaceFolders = vscode.workspace.workspaceFolders || [];
  const workspaceRoots = workspaceFolders.map((folder) => folder.uri.fsPath);
  const files = await vscode.workspace.findFiles(
    "**/*",
    "**/{.git,node_modules,.dart_tool,build,venv,.venv,__pycache__}/**",
    maxFiles,
  );
  const editor = vscode.window.activeTextEditor;
  const document = editor && isLocalFile(editor.document)
    ? editor.document
    : null;
  const selection = editor && document ? editor.selection : null;
  const openFiles = vscode.workspace.textDocuments
    .filter(isLocalFile)
    .slice(0, 100)
    .map((item) => item.uri.fsPath);

  return {
    workspace_roots: workspaceRoots,
    workspace_files: files.map((uri) =>
      vscode.workspace.asRelativePath(uri, false),
    ),
    open_files: openFiles,
    active_file: document ? document.uri.fsPath : "",
    relative_file: document
      ? vscode.workspace.asRelativePath(document.uri, false)
      : "",
    language_id: document ? document.languageId : "",
    document_text: document ? document.getText().slice(0, 100000) : "",
    selected_text:
      document && selection
        ? document.getText(selection).slice(0, 20000)
        : "",
    cursor_line: selection ? selection.active.line : 0,
    cursor_character: selection ? selection.active.character : 0,
  };
}

function setStatus(connected, detail = "") {
  statusItem.text = connected
    ? "$(broadcast) LabVoice connected"
    : "$(debug-disconnect) LabVoice offline";
  statusItem.tooltip = connected
    ? `LabVoice can understand the current VS Code context.${detail}`
    : `LabVoice cannot reach ${backendUrl()}.${detail}`;
  statusItem.accessibilityInformation = {
    label: connected
      ? "LabVoice is connected to the current Visual Studio Code workspace"
      : "LabVoice is disconnected from Visual Studio Code",
    role: "button",
  };
}

async function synchronize(showMessage = false) {
  try {
    const context = await collectContext();
    await postJson(`${backendUrl()}/editor/context`, context);
    lastContext = context;
    setStatus(true);
    if (showMessage) {
      vscode.window.showInformationMessage(
        "LabVoice ya comprende el proyecto y el archivo activo.",
      );
    }
  } catch (error) {
    setStatus(false, ` ${error.message}`);
    if (showMessage) {
      vscode.window.showWarningMessage(
        `No fue posible conectar LabVoice: ${error.message}`,
      );
    }
  }
}

function scheduleSync() {
  clearTimeout(syncTimer);
  syncTimer = setTimeout(() => synchronize(false), 250);
}

function describeContext() {
  if (!lastContext) {
    vscode.window.showInformationMessage(
      "LabVoice todavía no ha recibido contexto del editor.",
    );
    return;
  }
  const file = lastContext.relative_file || "ningún archivo activo";
  vscode.window.showInformationMessage(
    `LabVoice conectado. Archivo activo: ${file}. ` +
      `Proyecto: ${lastContext.workspace_files.length} archivos detectados.`,
  );
}

function activate(extensionContext) {
  statusItem = vscode.window.createStatusBarItem(
    vscode.StatusBarAlignment.Left,
    100,
  );
  statusItem.command = "labvoice.syncContext";
  setStatus(false);
  statusItem.show();

  extensionContext.subscriptions.push(
    statusItem,
    vscode.commands.registerCommand("labvoice.connect", () =>
      synchronize(true),
    ),
    vscode.commands.registerCommand("labvoice.syncContext", () =>
      synchronize(true),
    ),
    vscode.commands.registerCommand(
      "labvoice.describeContext",
      describeContext,
    ),
    vscode.window.onDidChangeActiveTextEditor(scheduleSync),
    vscode.window.onDidChangeTextEditorSelection(scheduleSync),
    vscode.workspace.onDidSaveTextDocument(scheduleSync),
    vscode.workspace.onDidChangeWorkspaceFolders(scheduleSync),
    vscode.workspace.onDidCreateFiles(scheduleSync),
    vscode.workspace.onDidDeleteFiles(scheduleSync),
    vscode.workspace.onDidRenameFiles(scheduleSync),
  );

  synchronize(false);
}

function deactivate() {
  clearTimeout(syncTimer);
}

module.exports = {
  activate,
  deactivate,
};
