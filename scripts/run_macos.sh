#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BACKEND_DIR="$ROOT_DIR/python_backend"
FLUTTER_DIR="$ROOT_DIR/labvoice"
PYTHON="$BACKEND_DIR/venv/bin/python"
BUILD_DIR="/private/tmp/LabVoiceBuild"
APP_PATH="$BUILD_DIR/Build/Products/Debug/labvoice.app"
BACKEND_PID_FILE="/private/tmp/labvoice-backend.pid"

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

if [[ -f "$BACKEND_PID_FILE" ]]; then
  PREVIOUS_BACKEND_PID="$(cat "$BACKEND_PID_FILE")"
  if kill -0 "$PREVIOUS_BACKEND_PID" >/dev/null 2>&1; then
    kill "$PREVIOUS_BACKEND_PID" >/dev/null 2>&1 || true
    wait "$PREVIOUS_BACKEND_PID" 2>/dev/null || true
  fi
  rm -f "$BACKEND_PID_FILE"
fi

if curl --silent --fail http://127.0.0.1:8000/ >/dev/null 2>&1; then
  echo "Port 8000 is already in use. Stop the previous backend and try again."
  exit 1
fi

"$PYTHON" -m uvicorn main:app \
  --app-dir "$BACKEND_DIR" \
  --host 127.0.0.1 \
  --port 8000 &
BACKEND_PID=$!
echo "$BACKEND_PID" > "$BACKEND_PID_FILE"

cleanup() {
  kill "$BACKEND_PID" >/dev/null 2>&1 || true
  rm -f "$BACKEND_PID_FILE"
}
trap cleanup EXIT INT TERM

cd "$FLUTTER_DIR"
flutter pub get

xcodebuild \
  -workspace macos/Runner.xcworkspace \
  -scheme Runner \
  -configuration Debug \
  -derivedDataPath "$BUILD_DIR" \
  CODE_SIGNING_ALLOWED=NO \
  build

xattr -cr "$APP_PATH"
codesign \
  --force \
  --deep \
  --sign - \
  --entitlements macos/Runner/DebugProfile.entitlements \
  "$APP_PATH"
codesign --verify --deep --strict "$APP_PATH"

echo "LabVoice is running. Close the app or press Control-C to stop."
open -W "$APP_PATH"
