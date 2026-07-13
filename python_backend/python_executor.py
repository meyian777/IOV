from pathlib import Path
import os
import subprocess
import sys
import time


MAX_OUTPUT_CHARACTERS = 12000
MAX_ARGUMENTS = 12
MAX_ARGUMENT_LENGTH = 200
DEFAULT_TIMEOUT_SECONDS = 30
MAX_TIMEOUT_SECONDS = 120
BLOCKED_PARTS = {
    ".dart_tool",
    ".git",
    ".venv",
    "__pycache__",
    "build",
    "node_modules",
    "venv",
}


class PythonExecutor:
    @staticmethod
    def run_script(
        project_path: str,
        script_path: str,
        arguments: list[str] | None = None,
        timeout_seconds: int = DEFAULT_TIMEOUT_SECONDS,
        environment: dict | None = None,
    ) -> dict:
        root = Path(project_path).expanduser().resolve()
        if not root.is_dir():
            return {
                "success": False,
                "error": "project_not_found",
                "message": "The configured project directory does not exist.",
            }

        try:
            script = PythonExecutor._resolve_script(root, script_path)
            safe_arguments = PythonExecutor._validate_arguments(arguments or [])
        except ValueError as error:
            return {
                "success": False,
                "error": "invalid_python_execution",
                "message": str(error),
            }

        timeout = min(max(timeout_seconds, 1), MAX_TIMEOUT_SECONDS)
        command = [sys.executable, str(script), *safe_arguments]
        started = time.monotonic()
        try:
            completed = subprocess.run(
                command,
                cwd=root,
                capture_output=True,
                text=True,
                timeout=timeout,
                env=PythonExecutor._environment(environment),
                check=False,
            )
        except subprocess.TimeoutExpired as error:
            output = PythonExecutor._timeout_output(error)
            return {
                "success": False,
                "error": "python_execution_timed_out",
                "message": f"Python script timed out after {timeout} seconds.",
                "script": str(script.relative_to(root)),
                "duration_seconds": round(time.monotonic() - started, 2),
                "exit_code": None,
                "output": output[-MAX_OUTPUT_CHARACTERS:],
            }

        output = "\n".join(
            part.strip()
            for part in (completed.stdout, completed.stderr)
            if part.strip()
        )
        success = completed.returncode == 0
        return {
            "success": success,
            "error": None if success else "python_execution_failed",
            "message": (
                "Python script completed successfully."
                if success
                else "Python script exited with an error."
            ),
            "script": str(script.relative_to(root)),
            "duration_seconds": round(time.monotonic() - started, 2),
            "exit_code": completed.returncode,
            "output": output[-MAX_OUTPUT_CHARACTERS:],
        }

    @staticmethod
    def _resolve_script(root: Path, script_path: str) -> Path:
        if not script_path.strip():
            raise ValueError("A project-relative Python script path is required.")
        requested = Path(script_path).expanduser()
        if requested.is_absolute():
            raise ValueError("Python scripts must use project-relative paths.")
        script = (root / requested).resolve()
        try:
            relative = script.relative_to(root)
        except ValueError as exc:
            raise ValueError("Python script must stay inside the project.") from exc
        if any(part in BLOCKED_PARTS for part in relative.parts):
            raise ValueError("Python script path is in a blocked project directory.")
        if script.suffix != ".py":
            raise ValueError("Only .py scripts can be executed.")
        if not script.is_file():
            raise ValueError("Python script was not found.")
        return script

    @staticmethod
    def _validate_arguments(arguments: list[str]) -> list[str]:
        if len(arguments) > MAX_ARGUMENTS:
            raise ValueError(f"At most {MAX_ARGUMENTS} arguments are allowed.")
        safe_arguments = []
        for argument in arguments:
            value = str(argument)
            if len(value) > MAX_ARGUMENT_LENGTH:
                raise ValueError("Python script arguments are too long.")
            if "\x00" in value:
                raise ValueError("Python script arguments cannot contain null bytes.")
            safe_arguments.append(value)
        return safe_arguments

    @staticmethod
    def _environment(environment: dict | None = None) -> dict:
        merged = os.environ.copy()
        if environment:
            merged.update(environment)
        merged["PYTHONUNBUFFERED"] = "1"
        return merged

    @staticmethod
    def _timeout_output(error: subprocess.TimeoutExpired) -> str:
        parts = []
        for value in (error.stdout, error.stderr):
            if isinstance(value, bytes):
                parts.append(value.decode(errors="replace"))
            elif value:
                parts.append(value)
        return "\n".join(parts)
