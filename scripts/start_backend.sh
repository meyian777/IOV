#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BACKEND_DIR="$ROOT_DIR/python_backend"
PYTHON="$BACKEND_DIR/venv/bin/python"
PID_FILE="/private/tmp/labvoice-backend.pid"
LOG_FILE="/private/tmp/labvoice-backend.log"
HEALTH_URL="http://127.0.0.1:8000/"
SERVICE="gui/$(id -u)/com.ianmey.labvoice.backend"

if curl --silent --fail "$HEALTH_URL" >/dev/null 2>&1; then
  echo "LabVoice backend is already online."
  exit 0
fi

if launchctl print "$SERVICE" >/dev/null 2>&1; then
  launchctl kickstart "$SERVICE" >/dev/null 2>&1 || true
  for _ in {1..30}; do
    if curl --silent --fail "$HEALTH_URL" >/dev/null 2>&1; then
      echo "LabVoice backend service is online."
      exit 0
    fi
    sleep 0.2
  done
  echo "The installed LabVoice backend service did not become healthy."
  exit 1
fi

if [[ ! -x "$PYTHON" ]]; then
  echo "Python environment not found at $PYTHON."
  exit 1
fi

if [[ ! -f "$BACKEND_DIR/.env" ]]; then
  echo "Missing $BACKEND_DIR/.env."
  exit 1
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

nohup "$PYTHON" -m uvicorn main:app \
  --app-dir "$BACKEND_DIR" \
  --host 127.0.0.1 \
  --port 8000 \
  >"$LOG_FILE" 2>&1 </dev/null &

BACKEND_PID=$!
echo "$BACKEND_PID" > "$PID_FILE"

for _ in {1..30}; do
  if curl --silent --fail "$HEALTH_URL" >/dev/null 2>&1; then
    echo "LabVoice backend is online with PID $BACKEND_PID."
    exit 0
  fi
  sleep 0.2
done

echo "LabVoice backend failed to start. See $LOG_FILE."
exit 1
