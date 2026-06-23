# LabVoice VS Code Bridge

This local extension gives LabVoice read-only context from Visual Studio Code:

- current workspace roots and file map;
- active and open files;
- active document language and contents;
- selected text and cursor position.

It never edits or deletes files without explicit confirmation. The extension
sends editor context only to the configured local LabVoice backend. When the
user asks LabVoice a question, that backend may send the relevant active
context to its configured AI provider. Environment files, private keys,
certificates, encrypted files, and common credential files are excluded
automatically.

## Safe editing flow

LabVoice opens an exact side-by-side preview before changing a file. The edit
requires a separate verbal confirmation and tests the proposed version in an
isolated project copy. It touches the real file only after validation passes,
then creates a persistent backup outside the project before saving. The last
successful edit can be undone by voice.

## Run for development

Start LabVoice, open this folder in VS Code, and press `F5`. In the Extension
Development Host, open the LabVoice project and run:

`LabVoice: Connect to Current Workspace`

The lower status bar will announce whether LabVoice is connected.
