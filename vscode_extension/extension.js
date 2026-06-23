const vscode = require("vscode");
const crypto = require("crypto");
const http = require("http");
const https = require("https");

let statusItem;
let syncTimer;
let operationTimer;
let processingOperation = false;
let lastContext = null;
const previewDocuments = new Map();

function backendUrl() {
  return vscode.workspace
    .getConfiguration("labvoice")
    .get("backendUrl", "http://127.0.0.1:8000")
    .replace(/\/$/, "");
}

function requestJson(method, url, payload = null, timeout = 5000) {
  return new Promise((resolve, reject) => {
    const target = new URL(url);
    const body = payload === null ? "" : JSON.stringify(payload);
    const transport = target.protocol === "https:" ? https : http;
    const request = transport.request(
      target,
      {
        method,
        headers: {
          "Content-Type": "application/json",
          "Content-Length": Buffer.byteLength(body),
        },
        timeout,
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
    if (body) request.write(body);
    request.end();
  });
}

function postJson(url, payload, timeout = 5000) {
  return requestJson("POST", url, payload, timeout);
}

function getJson(url, timeout = 5000) {
  return requestJson("GET", url, null, timeout);
}

function isLocalFile(document) {
  return document && document.uri.scheme === "file";
}

function isSensitivePath(filePath) {
  const normalized = String(filePath || "").replaceAll("\\", "/").toLowerCase();
  const name = normalized.split("/").pop() || "";
  return (
    name === ".env" ||
    name.startsWith(".env.") ||
    /\.(pem|key|p12|pfx|jks|keystore|enc)$/.test(name) ||
    /(^|[/_.-])(secret|secrets|credential|credentials)([/_.-]|$)/.test(
      normalized,
    )
  );
}

async function collectContext() {
  const configuration = vscode.workspace.getConfiguration("labvoice");
  const maxFiles = configuration.get("maxWorkspaceFiles", 5000);
  const workspaceFolders = vscode.workspace.workspaceFolders || [];
  const workspaceRoots = workspaceFolders.map((folder) => folder.uri.fsPath);
  const files = await vscode.workspace.findFiles(
    "**/*",
    "**/{.git,node_modules,.dart_tool,build,venv,.venv,__pycache__,Pods,ephemeral,.idea}/**",
    maxFiles,
  );
  const editor = vscode.window.activeTextEditor;
  const document = editor && isLocalFile(editor.document)
    ? editor.document
    : null;
  const activeFileIsSensitive = document
    ? isSensitivePath(document.uri.fsPath)
    : false;
  const selection = editor && document ? editor.selection : null;
  const openFiles = vscode.workspace.textDocuments
    .filter(isLocalFile)
    .slice(0, 100)
    .map((item) => item.uri.fsPath);

  return {
    workspace_roots: workspaceRoots,
    workspace_files: files
      .filter((uri) => !isSensitivePath(uri.fsPath))
      .map((uri) => vscode.workspace.asRelativePath(uri, false)),
    open_files: openFiles,
    active_file: document ? document.uri.fsPath : "",
    relative_file: document
      ? vscode.workspace.asRelativePath(document.uri, false)
      : "",
    language_id: document ? document.languageId : "",
    document_text:
      document && !activeFileIsSensitive
        ? document.getText().slice(0, 100000)
        : "",
    selected_text:
      document && selection && !activeFileIsSensitive
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

function documentHash(text) {
  return crypto.createHash("sha256").update(text).digest("hex");
}

function fullDocumentRange(document) {
  const lastLine = document.lineAt(document.lineCount - 1);
  return new vscode.Range(
    new vscode.Position(0, 0),
    lastLine.rangeIncludingLineBreak.end,
  );
}

async function reportOperation(operationId, status, extra = {}) {
  return postJson(
    `${backendUrl()}/editor/operations/${operationId}/status`,
    { status, ...extra },
    10000,
  );
}

async function previewOperation(operation) {
  const sourceUri = vscode.Uri.file(operation.active_file);
  const previewUri = vscode.Uri.parse(
    `labvoice-preview:/${encodeURIComponent(operation.relative_file)}` +
      `?operation=${operation.id}`,
  );
  previewDocuments.set(previewUri.toString(), operation.replacement);
  await vscode.commands.executeCommand(
    "vscode.diff",
    sourceUri,
    previewUri,
    `${operation.relative_file}: actual ↔ propuesta de LabVoice`,
    { preview: true },
  );
  await reportOperation(operation.id, "previewed");
  vscode.window.showInformationMessage(
    `LabVoice preparó: ${operation.summary}. ` +
      "Revísalo y di “Sí, aplicar” o “Cancelar”.",
  );
}

async function writeBackup(extensionContext, operation) {
  const backupDirectory = vscode.Uri.joinPath(
    extensionContext.globalStorageUri,
    "backups",
  );
  await vscode.workspace.fs.createDirectory(backupDirectory);
  const backupUri = vscode.Uri.joinPath(
    backupDirectory,
    `${operation.id}.backup`,
  );
  await vscode.workspace.fs.writeFile(
    backupUri,
    Buffer.from(operation.original, "utf8"),
  );
  return backupUri;
}

async function replaceDocument(document, content) {
  const edit = new vscode.WorkspaceEdit();
  edit.replace(document.uri, fullDocumentRange(document), content);
  const applied = await vscode.workspace.applyEdit(edit);
  if (!applied) throw new Error("VS Code rejected the workspace edit.");
  const saved = await document.save();
  if (!saved) throw new Error("VS Code could not save the edited document.");
}

async function applyOperation(extensionContext, operation) {
  const document = await vscode.workspace.openTextDocument(
    vscode.Uri.file(operation.active_file),
  );
  if (documentHash(document.getText()) !== operation.original_hash) {
    await reportOperation(operation.id, "failed", {
      error:
        "The file changed after the preview. Prepare a new edit before applying.",
    });
    vscode.window.showErrorMessage(
      "LabVoice no aplicó el cambio porque el archivo cambió después de la vista previa.",
    );
    return;
  }

  let validation;
  try {
    validation = await postJson(
      `${backendUrl()}/editor/edit/${operation.id}/validate`,
      {},
      300000,
    );
  } catch (error) {
    await reportOperation(operation.id, "failed", {
      error: `Validation could not run: ${error.message}`,
    });
    vscode.window.showErrorMessage(
      "LabVoice no tocó el archivo porque no pudo ejecutar las pruebas.",
    );
    return;
  }

  if (!validation.success) {
    await reportOperation(operation.id, "failed", {
      diagnostics: validation.diagnostics,
      error: "Tests failed. The original file was not changed.",
    });
    vscode.window.showErrorMessage(
      "Las pruebas fallaron. LabVoice no modificó el archivo original.",
    );
    return;
  }

  await writeBackup(extensionContext, operation);
  try {
    await replaceDocument(document, operation.replacement);
  } catch (error) {
    if (document.getText() !== operation.original) {
      await replaceDocument(document, operation.original);
    }
    await reportOperation(operation.id, "failed", {
      diagnostics: validation.diagnostics,
      error: `Saving failed and the original was restored: ${error.message}`,
    });
    vscode.window.showErrorMessage(
      "No pude guardar el cambio. LabVoice restauró el archivo original.",
    );
    return;
  }

  await reportOperation(operation.id, "applied", {
    diagnostics: validation.diagnostics,
  });
  scheduleSync();
  vscode.window.showInformationMessage(
    "Cambio aplicado y guardado. Todas las pruebas pasaron. Puedes decir “Deshacer último cambio”.",
  );
}

async function undoOperation(operation) {
  const document = await vscode.workspace.openTextDocument(
    vscode.Uri.file(operation.active_file),
  );
  await replaceDocument(document, operation.original);
  await reportOperation(operation.id, "undone");
  scheduleSync();
  vscode.window.showInformationMessage(
    "LabVoice restauró la copia anterior del archivo.",
  );
}

async function processNextOperation(extensionContext) {
  if (processingOperation) return;
  processingOperation = true;
  try {
    const result = await getJson(`${backendUrl()}/editor/operations/next`);
    const operation = result.operation;
    if (!operation) return;
    if (operation.status === "awaiting_preview") {
      await previewOperation(operation);
    } else if (operation.status === "approved") {
      await applyOperation(extensionContext, operation);
    } else if (operation.status === "undo_requested") {
      await undoOperation(operation);
    }
  } catch (error) {
    setStatus(false, ` ${error.message}`);
  } finally {
    processingOperation = false;
  }
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
  const previewProvider = {
    provideTextDocumentContent(uri) {
      return previewDocuments.get(uri.toString()) || "";
    },
  };

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
    vscode.commands.registerCommand("labvoice.undoLastEdit", () =>
      postJson(`${backendUrl()}/editor/edit/undo`, {}),
    ),
    vscode.workspace.registerTextDocumentContentProvider(
      "labvoice-preview",
      previewProvider,
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
  operationTimer = setInterval(
    () => processNextOperation(extensionContext),
    1000,
  );
  processNextOperation(extensionContext);
}

function deactivate() {
  clearTimeout(syncTimer);
  clearInterval(operationTimer);
}

module.exports = {
  activate,
  deactivate,
};
