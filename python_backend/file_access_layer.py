from pathlib import Path
import fnmatch


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

TEXT_EXTENSIONS = {
    ".cfg",
    ".css",
    ".dart",
    ".env",
    ".gitignore",
    ".html",
    ".js",
    ".json",
    ".kt",
    ".lock",
    ".md",
    ".mjs",
    ".plist",
    ".py",
    ".rs",
    ".sh",
    ".swift",
    ".toml",
    ".ts",
    ".txt",
    ".yaml",
    ".yml",
}

SENSITIVE_FILE_PATTERNS = {
    ".env",
    ".env.*",
    "*.env",
    "*.key",
    "*.pem",
    "*.p12",
    "*.pfx",
    "*.crt",
    "*.cer",
    "*.mobileprovision",
    "*secret*",
    "*secrets*",
    "*token*",
    "*credential*",
    "*credentials*",
    "id_rsa",
    "id_dsa",
    "id_ecdsa",
    "id_ed25519",
    "known_hosts",
}

ALLOWED_DOTFILES = {
    ".gitignore",
}


class FileAccessError(RuntimeError):
    def __init__(self, code: str, message: str):
        super().__init__(message)
        self.code = code
        self.message = message


class FileAccessLayer:
    MAX_READ_BYTES = 120_000
    MAX_LIST_FILES = 500

    def __init__(self, project_path: str):
        self.root = Path(project_path).expanduser().resolve()

    def status(self) -> dict:
        return {
            "success": self.root.is_dir(),
            "root": str(self.root),
            "mode": "project_read_only",
            "sensitive_files_hidden": True,
            "max_read_bytes": self.MAX_READ_BYTES,
            "max_list_files": self.MAX_LIST_FILES,
        }

    def list_files(self, directory: str = "", limit: int = 120) -> dict:
        folder = self._resolve_inside_root(directory or ".")
        if not folder.is_dir():
            raise FileAccessError(
                "directory_not_found",
                "The requested project directory does not exist.",
            )
        safe_limit = min(max(limit, 1), self.MAX_LIST_FILES)
        files = []
        directories = []
        for path in sorted(folder.iterdir(), key=lambda item: item.name.lower()):
            if self._is_ignored(path) or self._is_sensitive(path):
                continue
            relative = str(path.relative_to(self.root))
            if path.is_dir():
                directories.append(relative)
            elif path.is_file():
                files.append(
                    {
                        "path": relative,
                        "size_bytes": path.stat().st_size,
                        "text": self._is_probably_text(path),
                    }
                )
            if len(files) + len(directories) >= safe_limit:
                break

        return {
            "success": True,
            "root": str(self.root),
            "directory": str(folder.relative_to(self.root))
            if folder != self.root
            else ".",
            "directories": directories,
            "files": files,
            "truncated": len(files) + len(directories) >= safe_limit,
            "permission": "read_only_project_scope",
        }

    def read_file(self, relative_path: str) -> dict:
        path = self._resolve_inside_root(relative_path)
        if not path.is_file():
            raise FileAccessError(
                "file_not_found",
                "The requested project file does not exist.",
            )
        if self._is_ignored(path):
            raise FileAccessError(
                "ignored_path",
                "This path is intentionally ignored by OSvoz.",
            )
        if self._is_sensitive(path):
            raise FileAccessError(
                "sensitive_file_blocked",
                "This file may contain secrets and cannot be read by OSvoz.",
            )
        size = path.stat().st_size
        if size > self.MAX_READ_BYTES:
            raise FileAccessError(
                "file_too_large",
                f"The file is larger than {self.MAX_READ_BYTES} bytes.",
            )
        if not self._is_probably_text(path):
            raise FileAccessError(
                "binary_file",
                "OSvoz can only read text files in this mode.",
            )
        try:
            content = path.read_text(encoding="utf-8")
        except UnicodeDecodeError as error:
            raise FileAccessError(
                "invalid_text_encoding",
                "The file is not valid UTF-8 text.",
            ) from error

        return {
            "success": True,
            "path": str(path.relative_to(self.root)),
            "size_bytes": size,
            "content": content,
            "permission": "read_only_project_scope",
        }

    def _resolve_inside_root(self, relative_path: str) -> Path:
        requested = Path(relative_path)
        if requested.is_absolute():
            raise FileAccessError(
                "absolute_path_blocked",
                "Use a project-relative path, not an absolute path.",
            )
        resolved = (self.root / requested).resolve()
        try:
            resolved.relative_to(self.root)
        except ValueError as error:
            raise FileAccessError(
                "path_outside_project",
                "OSvoz may access only files inside the approved project.",
            ) from error
        return resolved

    def _is_ignored(self, path: Path) -> bool:
        try:
            relative_parts = path.relative_to(self.root).parts
        except ValueError:
            return True
        return any(part in IGNORED_DIRECTORIES for part in relative_parts)

    def _is_sensitive(self, path: Path) -> bool:
        try:
            relative_parts = path.relative_to(self.root).parts
        except ValueError:
            return True
        for part in relative_parts:
            if part.startswith(".") and part not in ALLOWED_DOTFILES:
                return True

        name = path.name.lower()
        relative = str(path.relative_to(self.root)).lower()
        return any(
            fnmatch.fnmatch(name, pattern) or fnmatch.fnmatch(relative, pattern)
            for pattern in SENSITIVE_FILE_PATTERNS
        )

    def _is_probably_text(self, path: Path) -> bool:
        if path.name in TEXT_EXTENSIONS:
            return True
        return path.suffix.lower() in TEXT_EXTENSIONS
