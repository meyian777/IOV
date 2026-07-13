#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BACKEND_DIR="$ROOT_DIR/python_backend"
VENV_DIR="${OSVOZ_BACKEND_VENV:-/private/tmp/labvoice-backend-venv312}"
PYTHON="$VENV_DIR/bin/python"
SETUP_BACKEND="$ROOT_DIR/scripts/setup_backend_venv.sh"
PID_FILE="/private/tmp/labvoice-backend.pid"
LOG_FILE="/private/tmp/labvoice-backend.log"
HEALTH_URL="http://127.0.0.1:8000/"
SERVICE="gui/$(id -u)/com.ianmey.labvoice.backend"
NATIVE_CORE="$BACKEND_DIR/bin/labvoice-native-core"

current_backend_pid() {
  lsof -nP -iTCP:8000 -sTCP:LISTEN -t 2>/dev/null | head -n 1 || true
}

if curl --silent --fail "$HEALTH_URL" >/dev/null 2>&1; then
  CURRENT_PID="$(current_backend_pid)"
  if [[ -n "$CURRENT_PID" ]]; then
    echo "$CURRENT_PID" > "$PID_FILE"
  fi
  echo "OSvoz backend is already online."
  exit 0
fi

if launchctl print "$SERVICE" >/dev/null 2>&1; then
  launchctl kickstart "$SERVICE" >/dev/null 2>&1 || true
  for _ in {1..30}; do
    if curl --silent --fail "$HEALTH_URL" >/dev/null 2>&1; then
      CURRENT_PID="$(current_backend_pid)"
      if [[ -n "$CURRENT_PID" ]]; then
        echo "$CURRENT_PID" > "$PID_FILE"
      fi
      echo "OSvoz backend service is online."
      exit 0
    fi
    sleep 0.2
  done
  echo "The installed OSvoz backend service did not become healthy; starting a local backend process."
fi

if [[ ! -x "$PYTHON" ]]; then
  "$SETUP_BACKEND"
elif ! "$PYTHON" - <<'PY' >/dev/null 2>&1
import sys
from fastapi import FastAPI
raise SystemExit(0 if sys.version_info[:2] == (3, 12) and FastAPI else 1)
PY
then
  "$SETUP_BACKEND"
fi

if [[ ! -f "$BACKEND_DIR/.env" ]]; then
  echo "Missing $BACKEND_DIR/.env."
  exit 1
fi

if [[ ! -x "$NATIVE_CORE" ]]; then
  "$ROOT_DIR/scripts/build_native_core.sh"
fi

if [[ -f "$PID_FILE" ]]; then
  PREVIOUS_PID="$(cat "$PID_FILE")"
  if kill -0 "$PREVIOUS_PID" >/dev/null 2>&1; then
    kill "$PREVIOUS_PID" >/dev/null 2>&1 || true
    sleep 1
  fi
  rm -f "$PID_FILE"
fi

if lsof -nP -iTCP:8000 -sTCP:LISTEN >/dev/null 2>&1; then
  echo "Port 8000 is occupied by another process."
  exit 1
fi

nohup "$PYTHON" "$BACKEND_DIR/run_backend.py" \
  >"$LOG_FILE" 2>&1 </dev/null &

BACKEND_PID=$!
echo "$BACKEND_PID" > "$PID_FILE"

for _ in {1..30}; do
  if curl --silent --fail "$HEALTH_URL" >/dev/null 2>&1; then
    echo "OSvoz backend is online with PID $BACKEND_PID."
    exit 0
  fi
  sleep 0.2
done

echo "OSvoz backend failed to start. See $LOG_FILE."
exit 1
