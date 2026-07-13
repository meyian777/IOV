from pathlib import Path
import os
import sys


class CoreHealth:
    @staticmethod
    def inspect(
        project_path: str,
        session_database_path: str,
        editor_context: dict,
        audit_verification: dict,
        speaker_status: dict,
        native_core_status: dict,
        speech_engine_status: dict | None = None,
        ml_framework_status: dict | None = None,
    ) -> dict:
        speech_engine_status = speech_engine_status or {}
        ml_framework_status = ml_framework_status or {}
        checks = {
            "project": Path(project_path).resolve().is_dir(),
            "session_database": Path(session_database_path).resolve().is_file(),
            "openai_configuration": bool(os.getenv("OPENAI_API_KEY")),
            "audit_chain": audit_verification.get("valid") is True,
            "editor_bridge": editor_context.get("connected") is True,
            "speaker_identity_boundary": bool(speaker_status.get("framework")),
            "native_authorization_core": native_core_status.get("success")
            is True,
            "local_speech_recognition": speech_engine_status.get("success")
            is True,
            "ml_framework_boundary": ml_framework_status.get("success") is True,
        }
        critical = (
            checks["project"]
            and checks["session_database"]
            and checks["openai_configuration"]
            and checks["audit_chain"]
            and checks["native_authorization_core"]
            and checks["local_speech_recognition"]
        )
        return {
            "status": "ready" if critical else "degraded",
            "critical_ready": critical,
            "checks": checks,
            "audit": audit_verification,
            "speaker_identity": speaker_status,
            "native_core": native_core_status,
            "speech_engine": speech_engine_status,
            "ml_frameworks": ml_framework_status,
            "python_runtime": {
                "version": sys.version.split()[0],
                "executable": sys.executable,
            },
        }
