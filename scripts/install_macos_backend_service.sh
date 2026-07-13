#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SOURCE_PLIST="$ROOT_DIR/macos/com.ianmey.labvoice.backend.plist"
TARGET_DIR="$HOME/Library/LaunchAgents"
TARGET_PLIST="$TARGET_DIR/com.ianmey.labvoice.backend.plist"
SERVICE="gui/$(id -u)/com.ianmey.labvoice.backend"
RUNTIME_DIR="/private/tmp/labvoice-backend-runtime"

"$ROOT_DIR/scripts/build_native_core.sh"
"$ROOT_DIR/scripts/setup_backend_venv.sh"
mkdir -p "$RUNTIME_DIR"
/usr/bin/rsync -a --delete --delete-excluded \
  --exclude '__pycache__/' \
  --exclude '.env' \
  --exclude 'bin/' \
  --exclude 'data/' \
  --exclude 'models/' \
  --exclude 'test_*.py' \
  --exclude 'venv/' \
  "$ROOT_DIR/python_backend/" "$RUNTIME_DIR/"
cp "$ROOT_DIR/python_backend/.env" /private/tmp/labvoice-backend.env
chmod 600 /private/tmp/labvoice-backend.env
mkdir -p "$RUNTIME_DIR/bin"
cp "$ROOT_DIR/python_backend/bin/labvoice-native-core" \
  "$RUNTIME_DIR/bin/labvoice-native-core"
chmod 700 "$RUNTIME_DIR/bin/labvoice-native-core"
mkdir -p "$RUNTIME_DIR/models"
cp "$ROOT_DIR/python_backend/models/ggml-tiny.bin" \
  "$RUNTIME_DIR/models/ggml-tiny.bin"
if [[ -f "$ROOT_DIR/python_backend/data/labvoice.db" && ! -f /private/tmp/labvoice-session.db ]]; then
  cp "$ROOT_DIR/python_backend/data/labvoice.db" /private/tmp/labvoice-session.db
fi
if [[ -f "$ROOT_DIR/python_backend/data/audit.db" && ! -f /private/tmp/labvoice-audit.db ]]; then
  cp "$ROOT_DIR/python_backend/data/audit.db" /private/tmp/labvoice-audit.db
fi
mkdir -p "$TARGET_DIR"
launchctl bootout "$SERVICE" >/dev/null 2>&1 || true
cp "$SOURCE_PLIST" "$TARGET_PLIST"
plutil -lint "$TARGET_PLIST" >/dev/null
BOOTSTRAPPED=0
for _ in {1..10}; do
  if launchctl bootstrap "gui/$(id -u)" "$TARGET_PLIST"; then
    BOOTSTRAPPED=1
    break
  fi
  sleep 0.25
done
if [[ "$BOOTSTRAPPED" != "1" ]]; then
  echo "OSvoz backend service could not be bootstrapped."
  exit 1
fi
launchctl kickstart -k "$SERVICE"

echo "OSvoz backend service installed and started."
