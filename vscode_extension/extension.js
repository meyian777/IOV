const vscode = require("vscode");
const crypto = require("crypto");
const http = require("http");
const https = require("https");

let statusItem;
let syncTimer;
let operationTimer;
let contextHeartbeatTimer;
let processingOperation = false;
let lastContext = null;
let lastContextSignature = "";
const previewDocuments = new Map();

const SYNC_DEBOUNCE_MS = 1200;
const CONTEXT_HEARTBEAT_MS = 15000;
const OPERATION_IDLE_POLL_MS = 5000;
const OPERATION_ACTIVE_POLL_MS = 750;
const OPERATION_ERROR_POLL_MS = 10000;

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
              `OSvoz returned HTTP ${response.statusCode}: ${responseBody}`,
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
  const visibleRange = editor && editor.visibleRanges.length > 0
    ? editor.visibleRanges[0]
    : null;
  const diagnostics = document
    ? vscode.languages.getDiagnostics(document.uri).slice(0, 50)
    : [];
  const openFiles = vscode.workspace.textDocuments
    .filter(isLocalFile)
    .slice(0, 100)
    .map((item) => item.uri.fsPath);
  const documentText =
    document && !activeFileIsSensitive
      ? document.getText().slice(0, 100000)
      : "";

  return {
    workspace_name: vscode.workspace.name || "",
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
    document_version: document ? document.version : 0,
    document_hash: documentText ? documentHash(documentText) : "",
    document_text: documentText,
    selected_text:
      document && selection && !activeFileIsSensitive
        ? document.getText(selection).slice(0, 20000)
        : "",
    cursor_line: selection ? selection.active.line : 0,
    cursor_character: selection ? selection.active.character : 0,
    selection_start_line: selection ? selection.start.line : 0,
    selection_start_character: selection ? selection.start.character : 0,
    selection_end_line: selection ? selection.end.line : 0,
    selection_end_character: selection ? selection.end.character : 0,
    visible_start_line: visibleRange ? visibleRange.start.line : 0,
    visible_end_line: visibleRange ? visibleRange.end.line : 0,
    diagnostics: diagnostics.map((diagnostic) => ({
      severity: diagnostic.severity,
      message: diagnostic.message.slice(0, 1000),
      source: diagnostic.source || "",
      code:
        diagnostic.code === undefined || diagnostic.code === null
          ? ""
          : String(diagnostic.code).slice(0, 200),
      start_line: diagnostic.range.start.line,
      start_character: diagnostic.range.start.character,
      end_line: diagnostic.range.end.line,
      end_character: diagnostic.range.end.character,
    })),
  };
}

function setStatus(connected, detail = "") {
  statusItem.text = connected
    ? "$(broadcast) OSvoz connected"
    : "$(debug-disconnect) OSvoz offline";
  statusItem.tooltip = connected
    ? `OSvoz can understand the current VS Code context.${detail}`
    : `OSvoz cannot reach ${backendUrl()}.${detail}`;
  statusItem.accessibilityInformation = {
    label: connected
      ? "OSvoz is connected to the current Visual Studio Code workspace"
      : "OSvoz is disconnected from Visual Studio Code",
    role: "button",
  };
}

async function synchronize(showMessage = false) {
  try {
    const context = await collectContext();
    const signature = documentHash(JSON.stringify(context));
    if (!showMessage && signature === lastContextSignature) {
      setStatus(true);
      return;
    }
    await postJson(`${backendUrl()}/editor/context`, context);
    lastContext = context;
    lastContextSignature = signature;
    setStatus(true);
    if (showMessage) {
      vscode.window.showInformationMessage(
        "OSvoz ya comprende el proyecto y el archivo activo.",
      );
    }
  } catch (error) {
    setStatus(false, ` ${error.message}`);
    if (showMessage) {
      vscode.window.showWarningMessage(
        `No fue posible conectar OSvoz: ${error.message}`,
      );
    }
  }
}

function scheduleSync() {
  clearTimeout(syncTimer);
  syncTimer = setTimeout(() => synchronize(false), SYNC_DEBOUNCE_MS);
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
  const files = operationFiles(operation);
  for (const file of files) {
    const sourceUri = vscode.Uri.file(file.active_file);
    const previewUri = vscode.Uri.parse(
      `labvoice-preview:/${encodeURIComponent(file.relative_file)}` +
        `?operation=${operation.id}`,
    );
    previewDocuments.set(previewUri.toString(), file.replacement);
    await vscode.commands.executeCommand(
      "vscode.diff",
      sourceUri,
      previewUri,
      `${file.relative_file}: actual ↔ propuesta de OSvoz`,
      { preview: false },
    );
  }
  await reportOperation(operation.id, "previewed");
  vscode.window.showInformationMessage(
    `OSvoz preparó ${files.length} archivo(s): ${operation.summary}. ` +
      "Revísalo y di “Sí, aplicar” o “Cancelar”.",
  );
}

function operationFiles(operation) {
  return Array.isArray(operation.files) && operation.files.length > 0
    ? operation.files
    : [operation];
}

async function writeBackup(extensionContext, operation, file) {
  const backupDirectory = vscode.Uri.joinPath(
    extensionContext.globalStorageUri,
    "backups",
  );
  await vscode.workspace.fs.createDirectory(backupDirectory);
  const backupUri = vscode.Uri.joinPath(
    backupDirectory,
    `${operation.id}-${documentHash(file.relative_file).slice(0, 12)}.backup`,
  );
  await vscode.workspace.fs.writeFile(
    backupUri,
    Buffer.from(file.original, "utf8"),
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
  const files = operationFiles(operation);
  const documents = [];
  for (const file of files) {
    const document = await vscode.workspace.openTextDocument(
      vscode.Uri.file(file.active_file),
    );
    if (documentHash(document.getText()) !== file.original_hash) {
      await reportOperation(operation.id, "failed", {
        error:
          "A file changed after the preview. Prepare a new edit before applying.",
      });
      vscode.window.showErrorMessage(
        "OSvoz no aplicó el lote porque un archivo cambió después de la vista previa.",
      );
      return;
    }
    documents.push({ file, document });
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
      "OSvoz no tocó el archivo porque no pudo ejecutar las pruebas.",
    );
    return;
  }

  if (!validation.success) {
    await reportOperation(operation.id, "failed", {
      diagnostics: validation.diagnostics,
      error: "Tests failed. The original file was not changed.",
    });
    vscode.window.showErrorMessage(
      "Las pruebas fallaron. OSvoz no modificó el archivo original.",
    );
    return;
  }

  for (const item of documents) {
    await writeBackup(extensionContext, operation, item.file);
  }
  const written = [];
  try {
    for (const item of documents) {
      await replaceDocument(item.document, item.file.replacement);
      written.push(item);
    }
  } catch (error) {
    for (const item of written.reverse()) {
      if (item.document.getText() !== item.file.original) {
        await replaceDocument(item.document, item.file.original);
      }
    }
    await reportOperation(operation.id, "failed", {
      diagnostics: validation.diagnostics,
      error: `Saving failed and all written files were restored: ${error.message}`,
    });
    vscode.window.showErrorMessage(
      "No pude guardar el lote. OSvoz restauró los archivos escritos.",
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
  for (const file of operationFiles(operation)) {
    const document = await vscode.workspace.openTextDocument(
      vscode.Uri.file(file.active_file),
    );
    await replaceDocument(document, file.original);
  }
  await reportOperation(operation.id, "undone");
  scheduleSync();
  vscode.window.showInformationMessage(
    "OSvoz restauró la edición anterior. Puedes pedir otra modificación sobre el estado restaurado.",
  );
}

async function processNextOperation(extensionContext) {
  if (processingOperation) return;
  processingOperation = true;
  let nextPollDelay = OPERATION_IDLE_POLL_MS;
  try {
    const result = await getJson(`${backendUrl()}/editor/operations/next`);
    const operation = result.operation;
    if (!operation) return nextPollDelay;
    nextPollDelay = OPERATION_ACTIVE_POLL_MS;
    if (operation.status === "awaiting_preview") {
      await previewOperation(operation);
    } else if (operation.status === "approved") {
      await applyOperation(extensionContext, operation);
    } else if (operation.status === "undo_requested") {
      await undoOperation(operation);
    }
  } catch (error) {
    setStatus(false, ` ${error.message}`);
    nextPollDelay = OPERATION_ERROR_POLL_MS;
  } finally {
    processingOperation = false;
  }
  return nextPollDelay;
}

function scheduleOperationPoll(extensionContext, delay = OPERATION_IDLE_POLL_MS) {
  clearTimeout(operationTimer);
  operationTimer = setTimeout(async () => {
    const nextDelay = await processNextOperation(extensionContext);
    scheduleOperationPoll(extensionContext, nextDelay || OPERATION_IDLE_POLL_MS);
  }, delay);
}

function describeContext() {
  if (!lastContext) {
    vscode.window.showInformationMessage(
      "OSvoz todavía no ha recibido contexto del editor.",
    );
    return;
  }
  const file = lastContext.relative_file || "ningún archivo activo";
  vscode.window.showInformationMessage(
    `OSvoz conectado. Archivo activo: ${file}. ` +
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
      postJson(`${backendUrl()}/editor/edit/undo`, {}).then(
        () => scheduleOperationPoll(extensionContext, OPERATION_ACTIVE_POLL_MS),
        (error) =>
          vscode.window.showWarningMessage(
            `No pude solicitar deshacer la última edición: ${error.message}`,
          ),
      ),
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
  scheduleOperationPoll(extensionContext, OPERATION_ACTIVE_POLL_MS);
  contextHeartbeatTimer = setInterval(
    () => synchronize(false),
    CONTEXT_HEARTBEAT_MS,
  );
}

function deactivate() {
  clearTimeout(syncTimer);
  clearTimeout(operationTimer);
  clearInterval(contextHeartbeatTimer);
}

module.exports = {
  activate,
  deactivate,
};
