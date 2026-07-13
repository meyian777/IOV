#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SOURCE_DIR="$ROOT_DIR/vscode_extension"
TARGET_DIR="$HOME/.vscode/extensions/ianmey.labvoice-vscode-bridge-0.1.0"

if command -v code >/dev/null 2>&1; then
  CODE_BIN="$(command -v code)"
elif [[ -x "/Applications/Visual Studio Code.app/Contents/Resources/app/bin/code" ]]; then
  CODE_BIN="/Applications/Visual Studio Code.app/Contents/Resources/app/bin/code"
else
  echo "Visual Studio Code is not installed."
  exit 1
fi

mkdir -p "$TARGET_DIR"
/usr/bin/rsync -a --delete \
  --exclude 'node_modules/' \
  --exclude '*.vsix' \
  "$SOURCE_DIR/" "$TARGET_DIR/"

if ! "$CODE_BIN" --list-extensions | grep -qx \
  'ianmey.labvoice-vscode-bridge'; then
  echo "The extension was copied but VS Code did not discover it."
  exit 1
fi

echo "IOV VS Code bridge installed at $TARGET_DIR"
