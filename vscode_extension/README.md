# OSvoz VS Code Bridge

This local extension gives OSvoz read-only context from Visual Studio Code:

- current workspace roots and file map;
- active and open files;
- active document language and contents;
- selected text, cursor position, full selection range and visible line range;
- active document version and SHA-256 hash;
- current editor diagnostics for the active file.

It never edits or deletes files without explicit confirmation. The extension
sends editor context only to the configured local OSvoz backend. When the
user asks OSvoz a question, that backend may send the relevant active
context to its configured AI provider. Environment files, private keys,
certificates, encrypted files, and common credential files are excluded
automatically.

## Safe editing flow

OSvoz opens an exact side-by-side preview before changing a file. The edit
requires a separate verbal confirmation and tests the proposed version in an
isolated project copy. It touches the real file only after validation passes,
then creates a persistent backup outside the project before saving. The last
successful edit can be undone by voice.

The bridge also sends a lightweight context heartbeat every 15 seconds, so it
automatically reconnects after a OSvoz backend restart without requiring the
user to change files or reload the editor.

## Bridge contract

OSvoz uses the bridge to answer and edit with the least necessary explanation:

- read project files only through the approved backend file layer;
- know the active file, cursor, selection, visible range and diagnostics;
- open exact previews for every proposed file change;
- apply only after the backend receives explicit voice confirmation;
- validate the staged project before writing the real workspace;
- restore written files if any file in a batch fails;
- undo the last applied edit through the same operation channel.

The extension never applies a preview directly. It waits for the backend to move
the operation from `previewed` to `approved`, which only happens after the user
confirms by voice.

## Run for development

Start OSvoz, open this folder in VS Code, and press `F5`. In the Extension
Development Host, open the OSvoz project and run:

`OSvoz: Connect to Current Workspace`

The lower status bar will announce whether OSvoz is connected.

## Install locally

Install the current workspace version into VS Code with:

```bash
./scripts/install_vscode_extension.sh
```

Restart VS Code after updating the extension files. The extension sends a
forced heartbeat every 15 seconds, so the backend reconnects even when the
active editor context did not change.
