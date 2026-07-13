from pathlib import Path
import subprocess


IGNORED_DIRECTORIES = {
    ".dart_tool",
    ".git",
    ".idea",
    ".venv",
    "__pycache__",
    "build",
    "node_modules",
    "venv",
}

TECHNOLOGY_MARKERS = {
    "pubspec.yaml": "Flutter",
    "pyproject.toml": "Python",
    "requirements.txt": "Python",
    "package.json": "Node.js",
    "Cargo.toml": "Rust",
    "go.mod": "Go",
}


class ProjectInspector:
    @staticmethod
    def inspect(project_path: str, diagnostics: dict | None = None) -> dict:
        root = Path(project_path).expanduser().resolve()

        if not root.is_dir():
            return {
                "success": False,
                "message": "The configured project directory does not exist.",
            }

        marker_paths = [
            path
            for marker in TECHNOLOGY_MARKERS
            for path in root.rglob(marker)
            if not any(part in IGNORED_DIRECTORIES for part in path.parts)
        ]
        key_files = sorted(str(path.relative_to(root)) for path in marker_paths)
        technologies = sorted(
            {TECHNOLOGY_MARKERS[path.name] for path in marker_paths}
        )

        file_count = sum(
            1
            for path in root.rglob("*")
            if path.is_file()
            and not any(part in IGNORED_DIRECTORIES for part in path.parts)
        )

        git = ProjectInspector._git_status(root)
        technology_text = ", ".join(technologies) if technologies else "Unknown"
        git_text = git.get("summary", "Git unavailable")

        result = {
            "success": True,
            "message": (
                f"Project {root.name} uses {technology_text}. "
                f"I found {file_count} files. {git_text}"
            ),
            "project": {
                "name": root.name,
                "path": str(root),
                "technologies": technologies,
                "key_files": key_files,
                "file_count": file_count,
                "git": git,
            },
        }

        if diagnostics is not None:
            result["diagnostics"] = diagnostics
            result["explanation"] = ProjectInspector._explain(
                root.name,
                technology_text,
                file_count,
                git_text,
                diagnostics,
            )
            result["message"] = result["explanation"]["summary"]

        return result

    @staticmethod
    def _git_status(root: Path) -> dict:
        try:
            branch = subprocess.run(
                ["git", "-C", str(root), "branch", "--show-current"],
                capture_output=True,
                check=True,
                text=True,
                timeout=5,
            ).stdout.strip()
            status_lines = subprocess.run(
                ["git", "-C", str(root), "status", "--short", "--", "."],
                capture_output=True,
                check=True,
                text=True,
                timeout=5,
            ).stdout.splitlines()
        except (FileNotFoundError, subprocess.SubprocessError):
            return {
                "available": False,
                "summary": "Git information is unavailable.",
            }

        changed_files = len(status_lines)
        if changed_files:
            summary = (
                f"Git branch {branch or 'detached'} has "
                f"{changed_files} pending change"
                f"{'' if changed_files == 1 else 's'}."
            )
        else:
            summary = f"Git branch {branch or 'detached'} is clean."

        return {
            "available": True,
            "branch": branch,
            "clean": changed_files == 0,
            "changed_files": changed_files,
            "summary": summary,
        }

    @staticmethod
    def _explain(
        project_name: str,
        technology_text: str,
        file_count: int,
        git_text: str,
        diagnostics: dict,
    ) -> dict:
        checks = diagnostics.get("checks", [])
        summary = diagnostics.get("summary", {})
        failed_checks = [
            check.get("name", "Unknown check")
            for check in checks
            if not check.get("success")
        ]

        if not checks:
            diagnostics_text = diagnostics.get(
                "message",
                "No supported diagnostics were found.",
            )
            next_action = "Review project structure and configure diagnostics"
        elif failed_checks:
            diagnostics_text = (
                f"{summary.get('passed', 0)} checks passed and "
                f"{summary.get('failed', len(failed_checks))} failed: "
                f"{', '.join(failed_checks)}."
            )
            next_action = "Review failed diagnostics"
        else:
            diagnostics_text = (
                f"All {summary.get('passed', len(checks))} diagnostic checks passed."
            )
            next_action = "Choose the next development task"

        return {
            "summary": (
                f"Project {project_name} uses {technology_text}. "
                f"I found {file_count} files. {git_text} {diagnostics_text}"
            ),
            "diagnostics": diagnostics_text,
            "next_action": next_action,
        }
