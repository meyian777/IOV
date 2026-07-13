#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BACKEND_DIR="$ROOT_DIR/python_backend"
VENV_DIR="${OSVOZ_BACKEND_VENV:-/private/tmp/labvoice-backend-venv312}"
PYTHON_BIN="${OSVOZ_PYTHON:-}"

if [[ -z "$PYTHON_BIN" ]]; then
  if command -v python3.12 >/dev/null 2>&1; then
    PYTHON_BIN="$(command -v python3.12)"
  elif [[ -x "/opt/homebrew/bin/python3.12" ]]; then
    PYTHON_BIN="/opt/homebrew/bin/python3.12"
  else
    echo "OSvoz backend needs Python 3.12 for the stable local runtime."
    echo "Install python@3.12 or run with OSVOZ_PYTHON=/path/to/python3.12."
    exit 1
  fi
fi

VERSION="$("$PYTHON_BIN" - <<'PY'
import sys
print(f"{sys.version_info.major}.{sys.version_info.minor}")
PY
)"

if [[ "$VERSION" != "3.12" ]]; then
  echo "OSvoz backend expected Python 3.12, got $VERSION from $PYTHON_BIN."
  echo "Run with OSVOZ_PYTHON=/path/to/python3.12 if needed."
  exit 1
fi

if [[ -x "$VENV_DIR/bin/python" ]]; then
  CURRENT_VERSION="$("$VENV_DIR/bin/python" - <<'PY'
import sys
print(f"{sys.version_info.major}.{sys.version_info.minor}")
PY
)"
  if [[ "$CURRENT_VERSION" != "3.12" ]]; then
    BACKUP="${VENV_DIR}-python${CURRENT_VERSION}-$(date +%Y%m%d%H%M%S)"
    echo "Moving existing backend venv ($CURRENT_VERSION) to $BACKUP."
    mv "$VENV_DIR" "$BACKUP"
  fi
fi

if [[ ! -x "$VENV_DIR/bin/python" ]]; then
  "$PYTHON_BIN" -m venv "$VENV_DIR"
fi

if [[ ! -x "$VENV_DIR/bin/pip" ]]; then
  echo "Backend venv at $VENV_DIR is incomplete; recreating it."
  rm -rf "$VENV_DIR"
  "$PYTHON_BIN" -m venv "$VENV_DIR"
fi

if ! "$VENV_DIR/bin/python" - <<'PY' >/dev/null 2>&1
import importlib.util
raise SystemExit(
    0
    if importlib.util.find_spec("fastapi")
    and importlib.util.find_spec("uvicorn")
    else 1
)
PY
then
  NEEDS_REQUIREMENTS=1
else
  NEEDS_REQUIREMENTS=0
fi

"$VENV_DIR/bin/python" -m pip install --upgrade pip
if [[ "$NEEDS_REQUIREMENTS" == "1" ]]; then
  "$VENV_DIR/bin/python" -m pip install -r "$BACKEND_DIR/requirements.txt"
fi

echo "OSvoz backend venv ready: $("$VENV_DIR/bin/python" --version) at $VENV_DIR"
