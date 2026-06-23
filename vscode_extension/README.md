# LabVoice VS Code Bridge

This local extension gives LabVoice read-only context from Visual Studio Code:

- current workspace roots and file map;
- active and open files;
- active document language and contents;
- selected text and cursor position.

It does not edit, delete, or run files. The extension sends editor context only
to the configured local LabVoice backend. When the user asks LabVoice a
question, that backend may send the relevant active context to its configured
AI provider. Environment files, private keys, certificates, encrypted files,
and common credential files are excluded automatically.

## Run for development

Start LabVoice, open this folder in VS Code, and press `F5`. In the Extension
Development Host, open the LabVoice project and run:

`LabVoice: Connect to Current Workspace`

The lower status bar will announce whether LabVoice is connected.
