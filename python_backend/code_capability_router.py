from dataclasses import asdict, dataclass
from pathlib import Path
import re


@dataclass(frozen=True)
class CodeRoute:
    domain: str
    capability: str
    language: str
    risk: str
    requires_project_context: bool

    def to_dict(self) -> dict:
        return asdict(self)


class CodeCapabilityRouter:
    CAPABILITY_MARKERS = {
        "debug": (
            "bug",
            "error",
            "exception",
            "traceback",
            "falla",
            "fallo",
            "corrige",
            "fix",
            "debug",
            "no funciona",
        ),
        "security_review": (
            "security",
            "secure",
            "vulnerability",
            "exploit",
            "securidad",
            "vulnerabilidad",
            "cifrado",
            "encryption",
            "secret",
        ),
        "test": (
            "test",
            "tests",
            "prueba",
            "pruebas",
            "coverage",
            "unit test",
            "integration test",
        ),
        "refactor": (
            "refactor",
            "refactoriza",
            "restructure",
            "reorganiza",
            "clean code",
            "separa",
        ),
        "optimize": (
            "optimize",
            "optimiza",
            "performance",
            "rendimiento",
            "faster",
            "más rápido",
            "mas rapido",
        ),
        "migrate": (
            "migrate",
            "migra",
            "upgrade",
            "actualiza",
            "port",
            "convert",
            "convierte",
        ),
        "document": (
            "document",
            "documenta",
            "readme",
            "docstring",
            "comments",
            "comentarios",
        ),
        "review": (
            "review",
            "revisa",
            "analiza este código",
            "analiza este codigo",
            "code review",
        ),
        "explain": (
            "explain",
            "explica",
            "explícame",
            "explicame",
            "what does",
            "qué hace",
            "que hace",
            "understand",
            "entiende",
        ),
        "generate": (
            "create",
            "build",
            "implement",
            "write",
            "genera",
            "crea",
            "construye",
            "implementa",
            "escribe",
        ),
    }

    LANGUAGE_MARKERS = {
        "dart": ("dart", "flutter", "pubspec", ".dart"),
        "python": ("python", "fastapi", "django", "flask", "pytest", ".py"),
        "javascript": (
            "javascript",
            "typescript",
            "node.js",
            "nodejs",
            "react",
            "next.js",
            ".js",
            ".ts",
            ".tsx",
        ),
        "swift": ("swift", "xcode", "ios", "macos", ".swift"),
        "kotlin": ("kotlin", "android", ".kt"),
        "rust": ("rust", "cargo", ".rs"),
        "go": ("golang", "go module", ".go"),
        "java": ("java", "spring", ".java"),
        "c_cpp": ("c++", "cpp", "clang", "cmake", ".cpp", ".h"),
        "sql": ("sql", "sqlite", "postgres", "mysql", "database query"),
        "shell": ("bash", "zsh", "shell", "terminal command", ".sh"),
    }

    CODE_SIGNAL = re.compile(
        r"```|[\w./-]+\.(?:dart|py|js|ts|tsx|swift|kt|rs|go|java|cpp|h|sql|sh)\b"
    )

    @classmethod
    def route(cls, text: str, project_path: str | None = None) -> CodeRoute:
        normalized = text.lower()
        language = cls._detect_language(normalized)
        capability = cls._detect_capability(normalized)
        has_code_signal = bool(cls.CODE_SIGNAL.search(normalized))
        code_related = (
            capability != "general"
            or language != "unknown"
            or has_code_signal
        )

        if not code_related:
            return CodeRoute(
                domain="general",
                capability="conversation",
                language="natural_language",
                risk="read_only",
                requires_project_context=False,
            )

        if language == "unknown":
            language = cls._detect_project_language(project_path)
        risk = (
            "security_sensitive"
            if capability == "security_review"
            else "code_change"
            if capability in {"generate", "debug", "refactor", "optimize", "migrate"}
            else "read_only"
        )
        return CodeRoute(
            domain="software_engineering",
            capability=capability if capability != "general" else "review",
            language=language,
            risk=risk,
            requires_project_context=capability
            in {"debug", "refactor", "test", "review", "optimize", "migrate"},
        )

    @classmethod
    def _detect_capability(cls, text: str) -> str:
        for capability, markers in cls.CAPABILITY_MARKERS.items():
            if any(marker in text for marker in markers):
                return capability
        return "general"

    @classmethod
    def _detect_language(cls, text: str) -> str:
        for language, markers in cls.LANGUAGE_MARKERS.items():
            if any(marker in text for marker in markers):
                return language
        return "unknown"

    @staticmethod
    def _detect_project_language(project_path: str | None) -> str:
        if project_path:
            root = Path(project_path)
            if (root / "labvoice" / "pubspec.yaml").is_file():
                return "dart"
            if (root / "pyproject.toml").is_file() or (
                root / "python_backend"
            ).is_dir():
                return "python"
        return "unknown"

    @staticmethod
    def prompt_context(route: CodeRoute) -> str:
        if route.domain != "software_engineering":
            return "Use the general conversational capability."
        return (
            "Use the software engineering capability router. "
            f"Capability: {route.capability}. "
            f"Primary language or stack: {route.language}. "
            f"Risk class: {route.risk}. "
            "Reason about code structure, dependencies, tests, failure modes, "
            "security, and maintainability. Do not claim code was executed or "
            "changed unless a verified tool action actually did so."
        )
