from dataclasses import dataclass
import secrets
import time


@dataclass(frozen=True)
class ActionPolicy:
    name: str
    description: str
    risk: str
    requires_confirmation: bool


ACTION_POLICIES = {
    "LIST_FILES": ActionPolicy(
        name="LIST_FILES",
        description="Read the names of files in the active project.",
        risk="read_only",
        requires_confirmation=False,
    ),
    "OPEN_VSCODE": ActionPolicy(
        name="OPEN_VSCODE",
        description="Open Visual Studio Code on this computer.",
        risk="system",
        requires_confirmation=True,
    ),
    "OPEN_PROJECT": ActionPolicy(
        name="OPEN_PROJECT",
        description="Open the active project in Visual Studio Code.",
        risk="system",
        requires_confirmation=True,
    ),
    "OPEN_TERMINAL": ActionPolicy(
        name="OPEN_TERMINAL",
        description="Open the Terminal application.",
        risk="system",
        requires_confirmation=True,
    ),
    "RUN_FLUTTER": ActionPolicy(
        name="RUN_FLUTTER",
        description="Start the Flutter application in Chrome.",
        risk="process_execution",
        requires_confirmation=True,
    ),
}


class PermissionEngine:
    def __init__(self, confirmation_ttl_seconds: int = 60):
        self.confirmation_ttl_seconds = confirmation_ttl_seconds
        self._pending = {}

    def prepare(self, action: str) -> dict:
        policy = ACTION_POLICIES.get(action)
        if policy is None:
            return {
                "success": False,
                "error": "unknown_action",
                "message": f"Unknown action: {action}",
            }

        if not policy.requires_confirmation:
            return {
                "success": True,
                "approved": True,
                "requires_confirmation": False,
                "policy": self._serialize(policy),
            }

        token = secrets.token_urlsafe(24)
        self._pending[token] = {
            "action": action,
            "expires_at": time.monotonic() + self.confirmation_ttl_seconds,
        }
        return {
            "success": True,
            "approved": False,
            "requires_confirmation": True,
            "confirmation_token": token,
            "expires_in_seconds": self.confirmation_ttl_seconds,
            "message": (
                f"Confirmation required. {policy.description} "
                "Say confirm or cancel."
            ),
            "policy": self._serialize(policy),
        }

    def confirm(self, token: str) -> dict:
        pending = self._pending.pop(token, None)
        if pending is None:
            return {
                "success": False,
                "error": "invalid_confirmation",
                "message": "The confirmation is invalid or was already used.",
            }

        if time.monotonic() > pending["expires_at"]:
            return {
                "success": False,
                "error": "expired_confirmation",
                "message": "The confirmation expired. Please request the action again.",
            }

        return {
            "success": True,
            "approved": True,
            "action": pending["action"],
        }

    def cancel(self, token: str) -> dict:
        pending = self._pending.pop(token, None)
        return {
            "success": pending is not None,
            "message": (
                "Pending action canceled."
                if pending is not None
                else "No valid pending action was found."
            ),
        }

    @staticmethod
    def _serialize(policy: ActionPolicy) -> dict:
        return {
            "name": policy.name,
            "description": policy.description,
            "risk": policy.risk,
            "requires_confirmation": policy.requires_confirmation,
        }
