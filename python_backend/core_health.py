from pathlib import Path
import os


class CoreHealth:
    @staticmethod
    def inspect(
        project_path: str,
        session_database_path: str,
        editor_context: dict,
        audit_verification: dict,
        speaker_status: dict,
    ) -> dict:
        checks = {
            "project": Path(project_path).resolve().is_dir(),
            "session_database": Path(session_database_path).resolve().is_file(),
            "openai_configuration": bool(os.getenv("OPENAI_API_KEY")),
            "audit_chain": audit_verification.get("valid") is True,
            "editor_bridge": editor_context.get("connected") is True,
            "speaker_identity_boundary": bool(speaker_status.get("framework")),
        }
        critical = (
            checks["project"]
            and checks["session_database"]
            and checks["openai_configuration"]
            and checks["audit_chain"]
        )
        return {
            "status": "ready" if critical else "degraded",
            "critical_ready": critical,
            "checks": checks,
            "audit": audit_verification,
            "speaker_identity": speaker_status,
        }
