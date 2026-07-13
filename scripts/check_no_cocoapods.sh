#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

blocked_paths=(
  "$ROOT_DIR/labvoice/ios/Podfile"
  "$ROOT_DIR/labvoice/ios/Podfile.lock"
  "$ROOT_DIR/labvoice/ios/Pods"
  "$ROOT_DIR/labvoice/macos/Podfile"
  "$ROOT_DIR/labvoice/macos/Podfile.lock"
  "$ROOT_DIR/labvoice/macos/Pods"
)

found=()
for path in "${blocked_paths[@]}"; do
  if [[ -e "$path" ]]; then
    found+=("${path#$ROOT_DIR/}")
  fi
done

if (( ${#found[@]} > 0 )); then
  echo "CocoaPods artifacts were regenerated but OSvoz is aligned to Flutter Swift Package Manager."
  echo "Remove these artifacts unless a plugin explicitly requires CocoaPods:"
  printf ' - %s\n' "${found[@]}"
  exit 1
fi

echo "No CocoaPods artifacts found."
