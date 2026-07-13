import json
from pathlib import Path
import os
import subprocess


class NativePolicyClient:
    def __init__(self, binary_path: str | None = None):
        self.binary_path = Path(
            binary_path
            or os.getenv("OSVOZ_NATIVE_CORE_PATH", "")
            or Path(__file__).resolve().parent
            / "bin"
            / "labvoice-native-core"
        )

    def health(self) -> dict:
        return self._run("health")

    def policy(self, action: str) -> dict:
        return self._run("policy", action)

    def _run(self, *arguments: str) -> dict:
        if not self.binary_path.is_file():
            return {
                "success": False,
                "error": "native_core_unavailable",
            }
        try:
            completed = subprocess.run(
                [str(self.binary_path), *arguments],
                capture_output=True,
                text=True,
                timeout=2,
                check=False,
            )
            if not completed.stdout.strip():
                return {
                    "success": False,
                    "error": "native_core_invalid_response",
                }
            result = json.loads(completed.stdout)
            if not isinstance(result, dict):
                raise ValueError("Expected an object.")
            return result
        except (
            json.JSONDecodeError,
            OSError,
            subprocess.TimeoutExpired,
            ValueError,
        ):
            return {
                "success": False,
                "error": "native_core_unavailable",
            }
