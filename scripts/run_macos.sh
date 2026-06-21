#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BACKEND_DIR="$ROOT_DIR/python_backend"
FLUTTER_DIR="$ROOT_DIR/labvoice"
PYTHON="$BACKEND_DIR/venv/bin/python"

if ! xcrun --find xcodebuild >/dev/null 2>&1; then
  echo "LabVoice needs the full Xcode installation to run on macOS."
  echo "Install Xcode, then run:"
  echo "  sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer"
  echo "  sudo xcodebuild -runFirstLaunch"
  exit 1
fi

if ! command -v pod >/dev/null 2>&1; then
  echo "LabVoice needs CocoaPods for its current macOS voice plugins."
  echo "Install CocoaPods, then run this launcher again."
  exit 1
fi

if [[ ! -x "$PYTHON" ]]; then
  echo "Python environment not found at $PYTHON."
  echo "Follow the backend setup instructions in README.md."
  exit 1
fi

if [[ ! -f "$BACKEND_DIR/.env" ]]; then
  echo "Missing $BACKEND_DIR/.env."
  echo "Create it from .env.example and add your OpenAI API key."
  exit 1
fi

"$PYTHON" -m uvicorn main:app \
  --app-dir "$BACKEND_DIR" \
  --host 127.0.0.1 \
  --port 8000 &
BACKEND_PID=$!

cleanup() {
  kill "$BACKEND_PID" >/dev/null 2>&1 || true
}
trap cleanup EXIT INT TERM

cd "$FLUTTER_DIR"
flutter run -d macos
