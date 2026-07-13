#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BACKEND_DIR="$ROOT_DIR/python_backend"
FLUTTER_DIR="$ROOT_DIR/labvoice"
BUILD_DIR="/private/tmp/OSvozBuild"
APP_PATH="$BUILD_DIR/Build/Products/Debug/IOV.app"

if ! xcrun --find xcodebuild >/dev/null 2>&1; then
  echo "OSvoz needs the full Xcode installation to run on macOS."
  echo "Install Xcode, then run:"
  echo "  sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer"
  echo "  sudo xcodebuild -runFirstLaunch"
  exit 1
fi

"$ROOT_DIR/scripts/start_backend.sh"
"$ROOT_DIR/scripts/check_no_cocoapods.sh"

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

echo "IOV is running. Its backend remains available after the window closes."
open -W "$APP_PATH"
