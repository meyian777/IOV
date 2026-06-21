from pathlib import Path
import subprocess
import sys
import time


MAX_OUTPUT_CHARACTERS = 6000


class DiagnosticsRunner:
    @staticmethod
    def run(project_path: str) -> dict:
        root = Path(project_path).expanduser().resolve()

        if not root.is_dir():
            return {
                "success": False,
                "message": "The configured project directory does not exist.",
                "checks": [],
            }

        checks = DiagnosticsRunner._discover_checks(root)
        if not checks:
            return {
                "success": False,
                "message": "No supported diagnostics were found for this project.",
                "checks": [],
            }

        results = [
            DiagnosticsRunner._run_check(name, command, working_directory)
            for name, command, working_directory in checks
        ]
        passed = sum(result["success"] for result in results)
        failed = len(results) - passed

        return {
            "success": failed == 0,
            "message": (
                f"Diagnostics completed: {passed} passed and {failed} failed."
            ),
            "summary": {
                "total": len(results),
                "passed": passed,
                "failed": failed,
            },
            "checks": results,
        }

    @staticmethod
    def _discover_checks(root: Path) -> list[tuple[str, list[str], Path]]:
        checks = []
        flutter_projects = DiagnosticsRunner._find_projects(root, "pubspec.yaml")
        python_projects = DiagnosticsRunner._find_projects(root, "requirements.txt")

        for project in flutter_projects:
            checks.extend(
                [
                    ("Flutter analyze", ["flutter", "analyze"], project),
                    ("Flutter tests", ["flutter", "test"], project),
                ]
            )

        for project in python_projects:
            checks.append(
                (
                    "Python tests",
                    [
                        sys.executable,
                        "-m",
                        "unittest",
                        "discover",
                        "-s",
                        ".",
                        "-p",
                        "test_*.py",
                    ],
                    project,
                )
            )

        return checks

    @staticmethod
    def _find_projects(root: Path, marker: str) -> list[Path]:
        ignored = {".dart_tool", ".git", "build", "node_modules", "venv"}
        return sorted(
            {
                path.parent
                for path in root.rglob(marker)
                if not any(part in ignored for part in path.parts)
            }
        )

    @staticmethod
    def _run_check(
        name: str,
        command: list[str],
        working_directory: Path,
    ) -> dict:
        started = time.monotonic()

        try:
            completed = subprocess.run(
                command,
                cwd=working_directory,
                capture_output=True,
                text=True,
                timeout=120,
            )
            output = "\n".join(
                part.strip()
                for part in (completed.stdout, completed.stderr)
                if part.strip()
            )
            return {
                "name": name,
                "success": completed.returncode == 0,
                "exit_code": completed.returncode,
                "duration_seconds": round(time.monotonic() - started, 2),
                "output": output[-MAX_OUTPUT_CHARACTERS:],
            }
        except subprocess.TimeoutExpired as error:
            output = DiagnosticsRunner._timeout_output(error)
            return {
                "name": name,
                "success": False,
                "exit_code": None,
                "duration_seconds": round(time.monotonic() - started, 2),
                "output": output[-MAX_OUTPUT_CHARACTERS:],
                "error": "Diagnostic timed out after 120 seconds.",
            }
        except FileNotFoundError:
            return {
                "name": name,
                "success": False,
                "exit_code": None,
                "duration_seconds": round(time.monotonic() - started, 2),
                "output": "",
                "error": f"Required tool is unavailable: {command[0]}",
            }

    @staticmethod
    def _timeout_output(error: subprocess.TimeoutExpired) -> str:
        parts = []
        for value in (error.stdout, error.stderr):
            if isinstance(value, bytes):
                parts.append(value.decode(errors="replace"))
            elif value:
                parts.append(value)
        return "\n".join(parts)
