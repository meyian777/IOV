# LabVoice

LabVoice is a local, voice-first assistant for software development. The
current prototype connects a Flutter command center to a Python/FastAPI
backend that can converse with OpenAI and execute a small set of local
developer actions.

## Repository structure

- `labvoice/`: Flutter frontend, speech recognition, text-to-speech and UI.
- `python_backend/`: FastAPI service, OpenAI integration and local actions.

## Local setup

### Backend

```bash
cd python_backend
python3 -m venv venv
source venv/bin/activate
pip install -r requirements.txt
cp .env.example .env
```

Add a valid `OPENAI_API_KEY` to `python_backend/.env`, then start the API:

```bash
uvicorn main:app --reload
```

### Flutter frontend

In another terminal:

```bash
cd labvoice
flutter pub get
flutter run -d chrome
```

The frontend currently expects the backend at `http://127.0.0.1:8000`.

## Native macOS test

LabVoice is intended to become a native desktop application rather than depend
on a browser. The macOS test requires:

- A complete Xcode installation with command-line tools selected.
- CocoaPods for the current voice plugins.
- The backend virtual environment and `python_backend/.env`.

After those prerequisites are installed, start the backend and macOS app
together:

```bash
./scripts/run_macos.sh
```

The launcher stops the local backend automatically when the Flutter app exits.
For the first microphone and speech-recognition permission request, running the
macOS target directly from Xcode may be necessary because of a known Flutter
development limitation.

## Security

- Never commit `.env` files or API keys.
- Treat local execution actions as privileged operations.
- Do not expose the FastAPI service outside the local machine in its current
  prototype state.

## Current milestone

The next milestone is a read-only Project Inspector that can identify a
project, inspect Git state, run analysis and tests, explain the results and
save the session without modifying project files.
