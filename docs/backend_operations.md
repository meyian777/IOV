# OSvoz Backend Operations

## Local Runtime

The supported local backend runtime is Python 3.12 in:

```bash
/private/tmp/labvoice-backend-venv312
```

Start or repair the backend with:

```bash
./scripts/setup_backend_venv.sh
./scripts/build_native_core.sh
./scripts/start_backend.sh
```

The macOS LaunchAgent is installed from:

```bash
macos/com.ianmey.labvoice.backend.plist
```

It runs:

```bash
/private/tmp/labvoice-backend-venv312/bin/python -S python_backend/run_backend.py
```

The native authorization core must resolve to:

```bash
python_backend/bin/labvoice-native-core
```

The optional PyTorch audio-embedding provider can be installed without
computer-vision dependencies:

```bash
/private/tmp/labvoice-backend-venv312/bin/python -m pip install \
  -r python_backend/requirements-ml-pytorch.txt
./scripts/install_macos_backend_service.sh
```

## Core Routes

| Route | Purpose | Expected local response |
| --- | --- | --- |
| `GET /` | Backend online probe | Under 2 seconds |
| `GET /core/health` | Full readiness, audit, native core, Whisper, ML boundary | Under 2 seconds |
| `GET /core/latency` | Backend warmup and route latency snapshots | Under 2 seconds |
| `POST /voice/transcribe?language=auto|es|en` | Local Whisper WAV transcription | Under 120 seconds |
| `POST /voice/interpret` | Intent and code-route interpretation only | Under 10 seconds |
| `POST /chat` | OpenAI conversational response | Under 60 seconds |
| `POST /speech` | Natural voice audio generation | Under 60 seconds |
| `POST /editor/edit/prepare` | Prepare exact VS Code diff preview | Under 120 seconds |
| `POST /editor/edit/{id}/confirm` | Explicit user approval after preview | Under 30 seconds |
| `POST /editor/edit/{id}/validate` | Validation before write | Up to 300 seconds |

Every backend response includes:

```text
X-OSvoz-Elapsed-Ms: <milliseconds>
Server-Timing: app;dur=<milliseconds>
```

Flutter also keeps recent client-side route latencies in
`OSvozApi.recentLatencies` for local diagnostics.

## Latency Optimization Loop

Use this cycle for near-real-time tuning:

1. Warm the backend once after startup with `GET /core/health`.
2. Exercise one user path, for example voice capture -> Whisper -> intent.
3. Read `GET /core/latency` and compare route `p50_ms` and `p95_ms`.
4. Compare backend timings with Flutter `OSvozApi.recentLatencies`.
5. Tune one bottleneck at a time, then repeat.

For repeatable route probes, run:

```bash
./scripts/measure_backend_latency.py --samples 10
```

Record the summary before and after each optimization. The current critical
local routes should stay in the low millisecond range when hot; if
`/voice/interpret` is slower than that, inspect routing, JSON handling and
code-capability detection before tuning Whisper.

Latest local baseline on 2026-06-29 after restarting the backend service:

| Probe | p50 | p95 | Note |
| --- | --- | --- | --- |
| `/` | 1.44 ms | 15.96 ms | One startup/connection outlier included |
| `/core/health` | 6.61 ms | 7.88 ms | Hot readiness checks are comfortably below target |
| `/core/latency` | 0.90 ms | 1.25 ms | Measurement route itself is cheap |
| `/voice/interpret` | 1.08 ms | 1.66 ms | Intent routing is not the current bottleneck |

Conclusion: the current critical path is not backend interpretation. Continue
tuning the listen-start path, microphone capture window, Whisper invocation, and
audio upload/transcription timing.

The first optimization layer keeps all calls on `127.0.0.1`, reuses the
Flutter HTTP client, caches quick backend availability checks for a short
window, runs backend availability and microphone permission checks in parallel
when listening starts, uses a short local availability timeout for fast native
speech fallback, and warms local backend dependencies at FastAPI startup.

Target hot-path budget:

| Segment | Target |
| --- | --- |
| Backend availability check | Avoided by short cache, otherwise under 50 ms |
| WAV upload to local backend | Under 100 ms for short captures |
| Whisper local transcription | Primary bottleneck; measure p50/p95 |
| `/voice/interpret` | Under 50 ms locally |
| TTS `/speech` | Network/model dependent; measure separately |

## Voice Fallback Behavior

Flutter should prefer local Whisper when the backend is reachable. It falls back
to native speech recognition when:

- `GET /` does not respond inside the quick availability check.
- `/voice/transcribe` times out.
- The backend returns invalid transcription JSON.
- Local Whisper reports an infrastructure failure such as `ggml`, Metal, or
  backend loading errors.

Plain no-speech windows are not treated as infrastructure failures. The app
should rearm listening instead of switching engines.

## Safe VS Code Editing

Voice-driven edits are a multi-step transaction:

1. Flutter asks `/editor/edit/prepare`.
2. The VS Code extension opens a diff preview and reports `previewed`.
3. The user must say an explicit confirmation such as `sí, aplicar`.
4. Flutter calls `/editor/edit/{id}/confirm`.
5. Only an `approved` operation may be validated and applied by VS Code.
6. The extension backs up the original file, writes the change, validates it,
   and can undo the last applied edit.

The backend rejects status transitions that try to mark an edit `applied`
before explicit approval.

## VS Code Bridge Context

The bridge sends enough editor state for OSvoz to act without asking the user to
explain the project repeatedly:

- workspace name, roots and bounded file map
- open files
- active file and project-relative path
- language id, document version and document hash
- cursor line/character
- selection start/end and selected text
- visible line range
- active-file diagnostics from VS Code

Sensitive files such as `.env`, private keys, certificates and common
credential paths are excluded from document text and file maps by the extension.
The backend bounds all text and list fields again before storing prompt context.

## Multi-File Edit Contract

Multi-file edits use the same safety flow as single-file edits. The operation
payload includes a `files` array where each item contains:

- `active_file`
- `relative_file`
- `language_id`
- `original`
- `original_hash`
- `replacement`
- `summary`
- `diff`

The VS Code extension must preview every file, validate the entire staged
project after all replacements are written to a temporary copy, then apply all
files as one logical batch. If any write fails, already written files are
restored from their original content and the operation is reported as failed.

The backend endpoint for explicit batch preparation is:

```text
POST /editor/edit/prepare-batch
```

Planner-backed automatic multi-file generation should target this same
operation shape.
