#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SOURCE_PLIST="$ROOT_DIR/macos/com.ianmey.labvoice.backend.plist"
TARGET_DIR="$HOME/Library/LaunchAgents"
TARGET_PLIST="$TARGET_DIR/com.ianmey.labvoice.backend.plist"
SERVICE="gui/$(id -u)/com.ianmey.labvoice.backend"

mkdir -p "$TARGET_DIR"
launchctl bootout "$SERVICE" >/dev/null 2>&1 || true
cp "$SOURCE_PLIST" "$TARGET_PLIST"
plutil -lint "$TARGET_PLIST" >/dev/null
launchctl bootstrap "gui/$(id -u)" "$TARGET_PLIST"
launchctl kickstart -k "$SERVICE"

echo "LabVoice backend service installed and started."
