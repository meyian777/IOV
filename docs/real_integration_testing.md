# Real Integration Testing

This runbook validates the end-to-end edit flow against real files while
keeping the main workspace safe.

## Isolated Project

Create a temporary project:

```bash
mkdir -p /private/tmp/labvoice-real-integration
printf "value = 'a'\n" > /private/tmp/labvoice-real-integration/a.py
printf "value = 'b'\n" > /private/tmp/labvoice-real-integration/b.py
```

Start an isolated backend on a non-default port:

```bash
OSVOZ_PROJECT_PATH=/private/tmp/labvoice-real-integration \
OSVOZ_SESSION_DATABASE=/private/tmp/labvoice-real-integration-session.db \
OSVOZ_AUDIT_DATABASE=/private/tmp/labvoice-real-integration-audit.db \
OSVOZ_NATIVE_CORE_PATH=/Users/ianmey/Desktop/ian_labvoice/python_backend/bin/labvoice-native-core \
/private/tmp/labvoice-backend-venv312/bin/python -m uvicorn main:app \
  --app-dir python_backend \
  --host 127.0.0.1 \
  --port 8011
```

Expected health:

```bash
curl -sS http://127.0.0.1:8011/core/health
```

`status` should be `ready`; `editor_bridge=false` is acceptable until editor
context is posted.

## Multi-File Flow

1. Post editor context:

```bash
curl -sS http://127.0.0.1:8011/editor/context \
  -H "Content-Type: application/json" \
  -d '{
    "workspace_roots":["/private/tmp/labvoice-real-integration"],
    "workspace_files":["a.py","b.py"],
    "active_file":"/private/tmp/labvoice-real-integration/a.py",
    "relative_file":"a.py",
    "language_id":"python",
    "document_text":"value = '\''a'\''\n"
  }'
```

2. Prepare a batch:

```bash
curl -sS http://127.0.0.1:8011/editor/edit/prepare-batch \
  -H "Content-Type: application/json" \
  -d '{
    "instruction":"Update both values",
    "language":"en",
    "files":[
      {
        "active_file":"/private/tmp/labvoice-real-integration/a.py",
        "relative_file":"a.py",
        "language_id":"python",
        "original":"value = '\''a'\''\n",
        "replacement":"value = '\''A'\''\n",
        "summary":"Update a"
      },
      {
        "active_file":"/private/tmp/labvoice-real-integration/b.py",
        "relative_file":"b.py",
        "language_id":"python",
        "original":"value = '\''b'\''\n",
        "replacement":"value = '\''B'\''\n",
        "summary":"Update b"
      }
    ]
  }'
```

3. Simulate VS Code preview:

```bash
curl -sS http://127.0.0.1:8011/editor/operations/<operation_id>/status \
  -H "Content-Type: application/json" \
  -d '{"status":"previewed"}'
```

4. Confirm by voice equivalent:

```bash
curl -sS -X POST http://127.0.0.1:8011/editor/edit/<operation_id>/confirm
```

5. Validate:

```bash
curl -sS -X POST http://127.0.0.1:8011/editor/edit/<operation_id>/validate
```

6. Apply from VS Code only after validation succeeds, then report:

```bash
curl -sS http://127.0.0.1:8011/editor/operations/<operation_id>/status \
  -H "Content-Type: application/json" \
  -d '{"status":"applied","diagnostics":{"success":true,"summary":{"passed":1,"failed":0},"checks":[]}}'
```

7. Undo:

```bash
curl -sS -X POST http://127.0.0.1:8011/editor/edit/undo
```

## Error Scenarios

| Scenario | Expected handling |
| --- | --- |
| Backend offline | Flutter uses native speech fallback for voice capture and reports backend unavailable for editing. |
| Editor bridge missing | `/editor/edit/prepare` and `/editor/edit/prepare-batch` reject with `editor_not_connected`. |
| File outside project | Backend rejects with `file_outside_project`. |
| Empty or unchanged edit | Backend rejects with `no_code_change` or `protected_or_empty_file`. |
| Apply before preview | Backend rejects with `invalid_operation_status` or `preview_required`. |
| Apply before confirmation | Backend rejects `applied` status until `/editor/edit/{id}/confirm` has moved the operation to `approved`. |
| File hash changed after preview | VS Code extension reports `failed`; no write occurs. |
| Validation fails | VS Code extension reports `failed`; original files are not written. |
| Partial write failure | VS Code extension restores any files already written and reports `failed`. |
| Undo without applied edit | Backend rejects with `nothing_to_undo`. |
| Whisper no speech | Flutter rearms listening; no native fallback. |
| Whisper infrastructure failure | Flutter switches to native speech fallback and hides low-level `ggml`/Metal details. |

## Latency Checks

Capture response timing headers:

```bash
curl -sS -D - http://127.0.0.1:8011/core/health -o /tmp/health.json
```

Expected headers:

```text
X-OSvoz-Elapsed-Ms: <milliseconds>
Server-Timing: app;dur=<milliseconds>
```

Record slow paths separately for future optimization:

- microphone capture window
- `/voice/transcribe`
- `/voice/interpret`
- `/editor/edit/prepare`
- `/editor/edit/{id}/validate`
- VS Code apply and save

