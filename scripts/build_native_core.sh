#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NATIVE_DIR="$ROOT_DIR/native_core"
OUTPUT_DIR="$ROOT_DIR/python_backend/bin"

cd "$NATIVE_DIR"
cargo test
cargo build --release

mkdir -p "$OUTPUT_DIR"
cp \
  "$NATIVE_DIR/target/release/labvoice-native-core" \
  "$OUTPUT_DIR/labvoice-native-core"
chmod 755 "$OUTPUT_DIR/labvoice-native-core"

echo "Native core built at $OUTPUT_DIR/labvoice-native-core"
