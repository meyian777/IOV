import secrets
import time

from native_policy_client import NativePolicyClient


class PermissionEngine:
    SECURITY_LEVELS = {
        "read_only": {
            "level": 1,
            "name": "routine",
            "required_factors": ["wake_word", "active_session"],
        },
        "routine_system": {
            "level": 1,
            "name": "routine",
            "required_factors": ["wake_word", "active_session"],
        },
        "process_execution": {
            "level": 2,
            "name": "personal_work",
            "required_factors": [
                "trusted_device",
                "voice_id",
                "preview_confirmation",
            ],
        },
        "personal_data": {
            "level": 2,
            "name": "personal_work",
            "required_factors": [
                "trusted_device",
                "voice_id",
                "preview_confirmation",
            ],
        },
        "critical_financial": {
            "level": 3,
            "name": "dangerous",
            "required_factors": [
                "trusted_device",
                "face_id_or_touch_id",
                "apple_watch_presence",
                "passkey",
                "explicit_preview_confirmation",
            ],
        },
        "credential_change": {
            "level": 3,
            "name": "dangerous",
            "required_factors": [
                "trusted_device",
                "face_id_or_touch_id",
                "apple_watch_presence",
                "passkey",
                "explicit_preview_confirmation",
            ],
        },
    }

    def __init__(
        self,
        confirmation_ttl_seconds: int = 60,
        native_client=None,
    ):
        self.confirmation_ttl_seconds = confirmation_ttl_seconds
        self._pending = {}
        self.native_client = native_client or NativePolicyClient()

    def prepare(self, action: str) -> dict:
        policy = self.native_client.policy(action)
        if not policy.get("success"):
            error = policy.get("error", "unknown_action")
            return {
                "success": False,
                "error": error,
                "message": (
                    f"Unknown action: {action}"
                    if error == "unknown_action"
                    else "The native authorization core is unavailable."
                ),
            }

        security = self._security_for_risk(policy["risk"])
        serialized_policy = {
            "name": policy["name"],
            "description": policy["description"],
            "risk": policy["risk"],
            "security_level": security["level"],
            "security_name": security["name"],
            "required_factors": security["required_factors"],
            "requires_confirmation": policy["requires_confirmation"],
            "authority": "rust_native_core",
        }
        if not policy["requires_confirmation"]:
            return {
                "success": True,
                "approved": True,
                "requires_confirmation": False,
                "policy": serialized_policy,
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
                f"{policy['description']} "
                f"Security level {security['level']} requires "
                f"{', '.join(security['required_factors'])}."
            ),
            "policy": serialized_policy,
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

    def _security_for_risk(self, risk: str) -> dict:
        return self.SECURITY_LEVELS.get(
            risk,
            {
                "level": 3,
                "name": "unknown_high_risk",
                "required_factors": [
                    "trusted_device",
                    "face_id_or_touch_id",
                    "passkey",
                    "explicit_preview_confirmation",
                ],
            },
        )
