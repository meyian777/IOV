from dataclasses import asdict, dataclass
import re
import unicodedata


@dataclass(frozen=True)
class InterpretedCommand:
    intent: str
    action: str | None
    risk: str
    requires_confirmation: bool
    executable: bool
    normalized_text: str

    def to_dict(self) -> dict:
        return asdict(self)


class CommandInterpreter:
    ACTIONS = (
        (
            "open_vscode",
            "OPEN_VSCODE",
            "routine_system",
            False,
            ("abre visual studio", "abre vs code", "open visual studio code"),
        ),
        (
            "open_project",
            "OPEN_PROJECT",
            "routine_system",
            False,
            (
                "abre mi proyecto",
                "abre osvoz",
                "abre el proyecto",
                "open project",
            ),
        ),
        (
            "open_terminal",
            "OPEN_TERMINAL",
            "routine_system",
            False,
            (
                "abre terminal",
                "abre la terminal",
                "abre el terminal",
                "abrir terminal",
                "abrir la terminal",
                "abrir el terminal",
                "open terminal",
            ),
        ),
        (
            "run_flutter",
            "RUN_FLUTTER",
            "execution",
            True,
            ("ejecuta flutter", "corre flutter", "flutter run", "run flutter"),
        ),
        (
            "list_files",
            "LIST_FILES",
            "read_only",
            False,
            ("lista los archivos", "muestra los archivos", "list files"),
        ),
        (
            "inspect_project",
            None,
            "read_only",
            False,
            (
                "analiza el proyecto",
                "inspecciona el proyecto",
                "que proyecto esta activo",
                "qué proyecto está activo",
                "que proyecto es activo",
                "qué proyecto es activo",
                "cual proyecto esta activo",
                "cuál proyecto está activo",
                "proyecto activo",
                "project status",
                "active project",
            ),
        ),
        (
            "operator_status",
            None,
            "read_only",
            False,
            (
                "estado del operador",
                "estado operativo",
                "estado del sistema",
                "estatus del operador",
                "operator status",
                "iov status",
                "osvoz status",
                "system status",
                "core status",
            ),
        ),
        (
            "run_diagnostics",
            None,
            "execution",
            True,
            ("ejecuta diagnosticos", "corre las pruebas", "run diagnostics"),
        ),
        (
            "run_python_script",
            "RUN_PYTHON_SCRIPT",
            "process_execution",
            True,
            (
                "ejecuta python",
                "corre python",
                "ejecuta script python",
                "run python",
                "run python script",
            ),
        ),
    )

    @classmethod
    def interpret(cls, transcript: str) -> InterpretedCommand:
        normalized = cls._normalize(transcript)
        for intent, action, risk, confirmation, markers in cls.ACTIONS:
            if any(marker in normalized for marker in markers):
                return InterpretedCommand(
                    intent=intent,
                    action=action,
                    risk=risk,
                    requires_confirmation=confirmation,
                    executable=False,
                    normalized_text=normalized,
                )
        return InterpretedCommand(
            intent="conversation",
            action=None,
            risk="read_only",
            requires_confirmation=False,
            executable=False,
            normalized_text=normalized,
        )

    @staticmethod
    def _normalize(text: str) -> str:
        lowered = text.lower().strip()
        decomposed = unicodedata.normalize("NFD", lowered)
        without_accents = "".join(
            character
            for character in decomposed
            if unicodedata.category(character) != "Mn"
        )
        without_wake_word = re.sub(
            r"^(?:ok(?:ay)?|oye|hey)?[\s,.:;!?-]*"
            r"(?:osvoz|os\s*voz)?[\s,.:;!?-]*",
            "",
            without_accents,
        )
        return re.sub(r"\s+", " ", without_wake_word).strip()
