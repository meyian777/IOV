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
    def inspect(project_path: str) -> dict:
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

        return {
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
