# OSvoz CI/CD

## Required Checks

Run these checks before merging or deploying:

```bash
/private/tmp/labvoice-backend-venv312/bin/python -m pytest python_backend -q
cd native_core && cargo test
./scripts/check_no_cocoapods.sh
cd labvoice && flutter analyze
cd labvoice && flutter test
```

Run Flutter commands sequentially. The current Flutter/iOS Swift Package tooling
can crash if `flutter analyze` and `flutter test` simultaneously update
`labvoice/ios/Flutter/ephemeral`.

## Backend Readiness Check

After installing or restarting the backend service:

```bash
./scripts/install_macos_backend_service.sh
curl -sS http://127.0.0.1:8000/core/health
```

The deployment is ready when:

```text
status=ready
critical_ready=true
native_authorization_core=true
local_speech_recognition=true
audit_chain=true
```

`editor_bridge=false` is acceptable until the VS Code extension sends editor
context.

## Latency Gate

Use `scripts/measure_backend_latency.py` as a soft gate while tuning. It should
run after the backend readiness check against a warm local backend:

```bash
./scripts/measure_backend_latency.py --samples 5
```

It records `min_ms`, `p50_ms`, `p95_ms`, and `max_ms` for `/`,
`/core/health`, `/core/latency`, and `/voice/interpret`. Treat regressions in
`p95_ms` as investigation triggers before changing UX or Whisper parameters.

## Release Discipline

- Keep runtime dependencies pinned in `python_backend/requirements.txt`.
- Build the Rust native core before installing the LaunchAgent.
- Do not commit `.env`, local databases, generated build folders, venvs, or
  Flutter ephemeral files.
- Treat voice edit application as a privileged workflow: preview, explicit
  confirmation, validation, then write.
- Multi-file edits must preserve the same safety workflow and validate all
  replacements together before any workspace file is written.
- Keep iOS aligned with Flutter Swift Package Manager integration. Do not
  reintroduce `labvoice/ios/Podfile` unless a plugin explicitly requires
  CocoaPods.
- Keep macOS aligned the same way. `scripts/check_no_cocoapods.sh` must fail
  the pipeline if `Podfile`, `Podfile.lock`, or `Pods/` is regenerated in
  `labvoice/ios` or `labvoice/macos`.

## CocoaPods Drift Check

Run this before and after Flutter dependency updates:

```bash
./scripts/check_no_cocoapods.sh
```

If it fails, inspect the plugin change that regenerated CocoaPods artifacts.
Only keep those files when the plugin cannot work through Flutter Swift Package
Manager. Otherwise remove the artifacts and rerun the check.

## Real Integration

Before UX or latency tuning, run the isolated real-file workflow in
`docs/real_integration_testing.md`. It exercises multi-file preview,
confirmation, validation, application, undo, and the expected failure modes
without risking the main workspace.
