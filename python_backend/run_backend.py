from pathlib import Path
import importlib
import os
import time
import sys


def _bootstrap_paths() -> Path:
    backend_dir = Path(__file__).resolve().parent
    venv_dir = Path(sys.executable).parents[1]
    python_version = f"python{sys.version_info.major}.{sys.version_info.minor}"
    site_packages = venv_dir / "lib" / python_version / "site-packages"
    stale_project_venv = backend_dir / "venv" / "lib" / python_version / "site-packages"
    sys.path[:] = [
        path
        for path in sys.path
        if Path(path).resolve() != stale_project_venv.resolve()
    ]
    for path in (str(backend_dir), str(site_packages)):
        if path not in sys.path:
            sys.path.insert(0, path)
    return backend_dir


def main() -> None:
    backend_dir = _bootstrap_paths()
    _preload_env(
        Path(
            os.getenv(
                "OSVOZ_ENV_FILE",
                "/private/tmp/labvoice-backend.env",
            )
        )
    )
    os.environ.setdefault(
        "OSVOZ_SESSION_DATABASE",
        "/private/tmp/labvoice-session.db",
    )
    os.environ.setdefault(
        "OSVOZ_AUDIT_DATABASE",
        "/private/tmp/labvoice-audit.db",
    )
    os.environ.setdefault(
        "OSVOZ_NATIVE_CORE_PATH",
        str(backend_dir / "bin" / "labvoice-native-core"),
    )
    uvicorn = _import_module_with_retry("uvicorn")
    app = _import_app_with_retry()

    uvicorn.run(
        app,
        app_dir=str(backend_dir),
        host="127.0.0.1",
        port=8000,
        log_level="info",
    )


def _import_app_with_retry():
    return _import_module_with_retry("main").app


def _import_module_with_retry(module_name: str):
    last_error: Exception | None = None
    for attempt in range(1, 41):
        try:
            return importlib.import_module(module_name)
        except OSError as error:
            if getattr(error, "errno", None) != 11:
                raise
            last_error = error
            _clear_partial_module(module_name)
            print(
                f"Retrying import {module_name} after filesystem EAGAIN "
                f"(attempt {attempt}/40).",
                file=sys.stderr,
            )
            time.sleep(min(1.5, 0.15 * attempt))
    if last_error is not None:
        raise last_error
    raise RuntimeError(f"OSvoz backend module {module_name} could not be imported.")


def _clear_partial_module(module_name: str) -> None:
    prefix = f"{module_name}."
    for key in list(sys.modules):
        if key == module_name or key.startswith(prefix):
            sys.modules.pop(key, None)


def _preload_env(path: Path) -> None:
    if not path.is_file():
        return
    text = _read_text_with_retry(path)
    for raw_line in text.splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        key = key.strip()
        value = value.strip().strip('"').strip("'")
        if key:
            os.environ[key] = value
    os.environ["OSVOZ_ENV_PRELOADED"] = "1"


def _read_text_with_retry(path: Path) -> str:
    last_error: OSError | None = None
    for attempt in range(1, 16):
        try:
            return path.read_text(encoding="utf-8")
        except OSError as error:
            if getattr(error, "errno", None) != 11:
                raise
            last_error = error
            time.sleep(0.25 * attempt)
    if last_error is not None:
        raise last_error
    return ""


if __name__ == "__main__":
    main()
