#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BACKEND_DIR="$ROOT_DIR/python_backend"
FLUTTER_DIR="$ROOT_DIR/labvoice"
BUILD_DIR="/private/tmp/LabVoiceBuild"
APP_PATH="$BUILD_DIR/Build/Products/Debug/labvoice.app"

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

"$ROOT_DIR/scripts/start_backend.sh"

cd "$FLUTTER_DIR"
flutter pub get
pod install --project-directory=macos

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

echo "LabVoice is running. Its backend remains available after the window closes."
open -W "$APP_PATH"
