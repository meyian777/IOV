from pathlib import Path
import os
import shutil
import tempfile

from diagnostics_runner import DiagnosticsRunner


class StagedEditValidator:
    IGNORED_NAMES = {
        ".dart_tool",
        ".git",
        ".idea",
        ".venv",
        "__pycache__",
        "build",
        "ephemeral",
        "node_modules",
        "Pods",
        "venv",
    }

    @staticmethod
    def run(project_path: str, operation: dict) -> dict:
        root = Path(project_path).expanduser().resolve()
        files = operation.get("files") or [operation]
        relative_files = []
        for file_change in files:
            active_file = Path(file_change["active_file"]).expanduser().resolve()
            try:
                relative_files.append(active_file.relative_to(root))
            except ValueError:
                return {
                    "success": False,
                    "message": "An edited file is outside the approved project.",
                    "summary": {"total": 0, "passed": 0, "failed": 1},
                    "checks": [],
                }

        with tempfile.TemporaryDirectory(prefix="labvoice-edit-") as directory:
            staged_root = Path(directory) / "project"
            shutil.copytree(
                root,
                staged_root,
                ignore=shutil.ignore_patterns(
                    *StagedEditValidator.IGNORED_NAMES,
                    ".env*",
                    "*.enc",
                    "*.jks",
                    "*.key",
                    "*.keystore",
                    "*.p12",
                    "*.pem",
                    "*.pfx",
                    "*credential*",
                    "*secret*",
                ),
            )
            for index, relative_file in enumerate(relative_files):
                staged_file = staged_root / relative_file
                if not staged_file.is_file():
                    return {
                        "success": False,
                        "message": "An edited file could not be staged.",
                        "summary": {"total": 0, "passed": 0, "failed": 1},
                        "checks": [],
                    }
                staged_file.write_text(
                    files[index]["replacement"],
                    encoding="utf-8",
                )
            environment = os.environ.copy()
            environment["OPENAI_API_KEY"] = "labvoice-staged-validation"
            return DiagnosticsRunner.run(
                str(staged_root),
                environment=environment,
            )
