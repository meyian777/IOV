from __future__ import annotations

from datetime import datetime, timedelta, timezone
from pathlib import Path
from threading import Lock
import secrets
import sqlite3


ROLE_PERMISSIONS = {
    "admin": {
        "session:start",
        "session:verify",
        "project:read",
        "editor:preview",
        "editor:apply",
        "editor:undo",
        "execute:routine",
        "execute:sensitive",
        "users:manage",
    },
    "editor": {
        "session:start",
        "session:verify",
        "project:read",
        "editor:preview",
        "editor:apply",
        "editor:undo",
        "execute:routine",
    },
    "reader": {
        "session:start",
        "session:verify",
        "project:read",
        "editor:preview",
    },
}

SENSITIVE_ACTIONS = {
    "editor:apply",
    "editor:undo",
    "execute:sensitive",
    "users:manage",
}

SUPPORTED_PROVIDERS = ("email_code", "oauth", "sso", "biometric", "voice")


class EnterpriseAuthStore:
    max_failed_attempts = 5

    def __init__(self, database_path: str, audit_store=None):
        self.database_path = Path(database_path).expanduser().resolve()
        self.database_path.parent.mkdir(parents=True, exist_ok=True)
        self.audit_store = audit_store
        self._lock = Lock()
        self._initialize()

    def _connect(self):
        connection = sqlite3.connect(self.database_path)
        connection.row_factory = sqlite3.Row
        return connection

    def _initialize(self):
        with self._connect() as connection:
            connection.execute(
                """
                CREATE TABLE IF NOT EXISTS enterprise_users (
                    id TEXT PRIMARY KEY,
                    organization_id TEXT NOT NULL,
                    email TEXT NOT NULL UNIQUE,
                    full_name TEXT NOT NULL,
                    phone TEXT NOT NULL,
                    role TEXT NOT NULL,
                    status TEXT NOT NULL,
                    created_at TEXT NOT NULL
                )
                """
            )
            connection.execute(
                """
                CREATE TABLE IF NOT EXISTS auth_sessions (
                    id TEXT PRIMARY KEY,
                    user_id TEXT NOT NULL,
                    organization_id TEXT NOT NULL,
                    provider TEXT NOT NULL,
                    status TEXT NOT NULL,
                    stage TEXT NOT NULL,
                    required_factors TEXT NOT NULL,
                    completed_factors TEXT NOT NULL,
                    verification_code TEXT,
                    expires_at TEXT NOT NULL,
                    created_at TEXT NOT NULL,
                    ip_address TEXT NOT NULL,
                    device_id TEXT NOT NULL,
                    failed_attempts INTEGER NOT NULL DEFAULT 0,
                    locked_until TEXT
                )
                """
            )
            self._ensure_column(
                connection,
                "auth_sessions",
                "failed_attempts",
                "INTEGER NOT NULL DEFAULT 0",
            )
            self._ensure_column(
                connection,
                "auth_sessions",
                "locked_until",
                "TEXT",
            )

    def _ensure_column(self, connection, table: str, column: str, definition: str):
        columns = {
            row["name"]
            for row in connection.execute(f"PRAGMA table_info({table})").fetchall()
        }
        if column not in columns:
            connection.execute(f"ALTER TABLE {table} ADD COLUMN {column} {definition}")

    def register_user(
        self,
        *,
        organization_id: str,
        email: str,
        full_name: str,
        phone: str,
        role: str,
    ) -> dict:
        normalized_role = role.lower().strip()
        if normalized_role not in ROLE_PERMISSIONS:
            raise ValueError("unsupported_role")
        normalized_email = email.lower().strip()
        user_id = secrets.token_urlsafe(18)
        created_at = _now()
        with self._lock, self._connect() as connection:
            existing = connection.execute(
                "SELECT * FROM enterprise_users WHERE email = ?",
                (normalized_email,),
            ).fetchone()
            if existing is not None:
                return self._user_dict(existing)
            connection.execute(
                """
                INSERT INTO enterprise_users (
                    id, organization_id, email, full_name, phone, role, status, created_at
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                """,
                (
                    user_id,
                    organization_id,
                    normalized_email,
                    full_name.strip(),
                    phone.strip(),
                    normalized_role,
                    "active",
                    created_at,
                ),
            )
        self._audit(
            "enterprise.user_registered",
            "success",
            {
                "organization_id": organization_id,
                "email_domain": _email_domain(normalized_email),
                "role": normalized_role,
            },
        )
        return self.get_user_by_email(normalized_email)

    def get_user_by_email(self, email: str) -> dict | None:
        with self._connect() as connection:
            row = connection.execute(
                "SELECT * FROM enterprise_users WHERE email = ?",
                (email.lower().strip(),),
            ).fetchone()
        return self._user_dict(row) if row is not None else None

    def start_session(
        self,
        *,
        email: str,
        provider: str,
        environment: str,
        ip_address: str,
        device_id: str,
        code: str | None = None,
    ) -> dict:
        normalized_provider = provider.lower().strip()
        if normalized_provider not in SUPPORTED_PROVIDERS:
            raise ValueError("unsupported_provider")
        user = self.get_user_by_email(email)
        if user is None or user["status"] != "active":
            self._audit(
                "enterprise.session_started",
                "blocked",
                {
                    "reason": "unknown_or_inactive_user",
                    "provider": normalized_provider,
                    "email_domain": _email_domain(email),
                },
            )
            return _blocked(
                "Usuario no autorizado",
                "No encontré una cuenta activa para este correo.",
            )

        required_factors = self.required_factors(
            role=user["role"],
            environment=environment,
            action="session:start",
            provider=normalized_provider,
        )
        completed = []
        if normalized_provider in {"oauth", "sso"}:
            completed.append(normalized_provider)
        verification_code = code or f"{secrets.randbelow(1_000_000):06d}"
        session_id = secrets.token_urlsafe(24)
        status = "pending"
        stage = "email_code" if "email_code" in required_factors else "local_identity"
        if set(required_factors).issubset(set(completed)):
            status = "authorized"
            stage = "ready"
        created_at = _now()
        expires_at = (
            datetime.now(timezone.utc) + timedelta(minutes=10)
        ).isoformat()
        with self._lock, self._connect() as connection:
            connection.execute(
                """
                INSERT INTO auth_sessions (
                    id, user_id, organization_id, provider, status, stage,
                    required_factors, completed_factors, verification_code,
                    expires_at, created_at, ip_address, device_id, failed_attempts, locked_until
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                (
                    session_id,
                    user["id"],
                    user["organization_id"],
                    normalized_provider,
                    status,
                    stage,
                    ",".join(required_factors),
                    ",".join(completed),
                    verification_code if "email_code" in required_factors else None,
                    expires_at,
                    created_at,
                    ip_address[:80],
                    device_id[:120],
                    0,
                    None,
                ),
            )
        self._audit(
            "enterprise.session_started",
            "success",
            {
                "organization_id": user["organization_id"],
                "user_id": user["id"],
                "role": user["role"],
                "provider": normalized_provider,
                "environment": environment,
                "ip_address": ip_address,
                "device_id": device_id,
                "stage": stage,
            },
        )
        session = self.get_session(session_id)
        return {
            "success": True,
            "session": self.public_session(session),
            "verification_code": verification_code
            if "email_code" in required_factors
            else None,
            "message": _message_for_stage(stage, required_factors, completed),
        }

    def verify_factor(
        self,
        *,
        session_id: str,
        factor: str,
        code: str | None = None,
    ) -> dict:
        normalized_factor = factor.lower().strip()
        if normalized_factor not in SUPPORTED_PROVIDERS:
            raise ValueError("unsupported_factor")
        session = self.get_session(session_id)
        if session is None:
            return _blocked("Sesión no encontrada", "Inicia sesión nuevamente.")
        if session["status"] == "blocked":
            return _blocked("Sesión bloqueada", "Inicia una nueva sesión.")
        if session["locked_until"] and not _expired(session["locked_until"]):
            return _blocked(
                "Sesión bloqueada temporalmente",
                "Demasiados intentos fallidos. Espera unos minutos o solicita un nuevo código.",
            )
        if _expired(session["expires_at"]):
            self._update_session(session_id, status="blocked", stage="expired")
            self._audit(
                "enterprise.factor_verified",
                "blocked",
                {"session_id": session_id, "reason": "expired"},
            )
            return _blocked("Código vencido", "Solicita un nuevo código de verificación.")

        required = _split(session["required_factors"])
        completed = set(_split(session["completed_factors"]))
        if normalized_factor not in required:
            return _blocked(
                "Factor no requerido",
                "Este paso no es necesario para esta sesión.",
            )
        if normalized_factor == "email_code" and code != session["verification_code"]:
            failed_attempts = int(session["failed_attempts"] or 0) + 1
            locked_until = None
            status = session["status"]
            stage = session["stage"]
            if failed_attempts >= self.max_failed_attempts:
                locked_until = (
                    datetime.now(timezone.utc) + timedelta(minutes=5)
                ).isoformat()
                status = "blocked"
                stage = "locked"
            self._update_session(
                session_id,
                failed_attempts=failed_attempts,
                locked_until=locked_until,
                status=status,
                stage=stage,
            )
            self._audit(
                "enterprise.factor_verified",
                "blocked",
                {
                    "session_id": session_id,
                    "factor": normalized_factor,
                    "reason": "invalid_code",
                    "failed_attempts": failed_attempts,
                },
            )
            if failed_attempts >= self.max_failed_attempts:
                return _blocked(
                    "Sesión bloqueada",
                    "Demasiados códigos incorrectos. Solicita un nuevo código para continuar.",
                )
            return _blocked(
                "Código incorrecto",
                "El código no coincide. Revisa tu correo o solicita uno nuevo.",
            )

        completed.add(normalized_factor)
        stage = self._next_stage(required, completed)
        status = "authorized" if stage == "ready" else "pending"
        self._update_session(
            session_id,
            status=status,
            stage=stage,
            completed_factors=",".join(sorted(completed)),
            failed_attempts=0,
            locked_until=None,
        )
        self._audit(
            "enterprise.factor_verified",
            "success",
            {
                "session_id": session_id,
                "factor": normalized_factor,
                "stage": stage,
            },
        )
        updated = self.get_session(session_id)
        return {
            "success": True,
            "session": self.public_session(updated),
            "message": _message_for_stage(stage, required, completed),
        }

    def authorize_action(
        self,
        *,
        session_id: str,
        action: str,
        environment: str,
    ) -> dict:
        session = self.get_session(session_id)
        if session is None:
            return _blocked("Sesión no encontrada", "Inicia sesión nuevamente.")
        user = self.get_user_by_id(session["user_id"])
        if user is None:
            return _blocked("Usuario no autorizado", "La cuenta ya no está activa.")
        permission = _permission_for_action(action)
        if permission not in ROLE_PERMISSIONS[user["role"]]:
            self._audit(
                "enterprise.action_authorized",
                "blocked",
                {
                    "session_id": session_id,
                    "user_id": user["id"],
                    "role": user["role"],
                    "permission": permission,
                    "reason": "role_denied",
                },
            )
            return _blocked(
                "Permiso insuficiente",
                f"Tu rol {user['role']} no permite {permission}.",
            )
        required = self.required_factors(
            role=user["role"],
            environment=environment,
            action=permission,
            provider=session["provider"],
        )
        completed = set(_split(session["completed_factors"]))
        missing = [factor for factor in required if factor not in completed]
        if missing:
            stage = self._next_stage(required, completed)
            self._update_session(
                session_id,
                status="pending",
                stage=stage,
                required_factors=",".join(required),
                completed_factors=",".join(sorted(completed)),
            )
            self._audit(
                "enterprise.action_authorized",
                "pending",
                {
                    "session_id": session_id,
                    "user_id": user["id"],
                    "permission": permission,
                    "missing_factor": missing[0],
                },
            )
            return {
                "success": False,
                "authorized": False,
                "status": "pending_mfa",
                "stage": stage,
                "required_factors": required,
                "completed_factors": sorted(completed),
                "missing_factors": missing,
                "message": _message_for_stage(stage, required, completed),
            }
        self._audit(
            "enterprise.action_authorized",
            "success",
            {
                "session_id": session_id,
                "user_id": user["id"],
                "role": user["role"],
                "permission": permission,
            },
        )
        return {
            "success": True,
            "authorized": True,
            "permission": permission,
            "message": "Acción autorizada. Puedes continuar.",
        }

    def resend_code(self, *, session_id: str, code: str | None = None) -> dict:
        session = self.get_session(session_id)
        if session is None:
            return _blocked("Sesión no encontrada", "Inicia sesión nuevamente.")
        required = _split(session["required_factors"])
        if "email_code" not in required:
            return _blocked(
                "Código no requerido",
                "Esta sesión no usa código de correo.",
            )
        verification_code = code or f"{secrets.randbelow(1_000_000):06d}"
        expires_at = (
            datetime.now(timezone.utc) + timedelta(minutes=10)
        ).isoformat()
        completed = [
            factor
            for factor in _split(session["completed_factors"])
            if factor != "email_code"
        ]
        self._update_session(
            session_id,
            status="pending",
            stage="email_code",
            verification_code=verification_code,
            expires_at=expires_at,
            completed_factors=",".join(completed),
            failed_attempts=0,
            locked_until=None,
        )
        self._audit(
            "enterprise.code_resent",
            "success",
            {"session_id": session_id},
        )
        updated = self.get_session(session_id)
        return {
            "success": True,
            "session": self.public_session(updated),
            "verification_code": verification_code,
            "message": "Código reenviado. Usa el código más reciente para continuar.",
        }

    def required_factors(
        self,
        *,
        role: str,
        environment: str,
        action: str,
        provider: str,
    ) -> list[str]:
        factors = []
        normalized_provider = provider.lower().strip()
        if normalized_provider in {"oauth", "sso"}:
            factors.append(normalized_provider)
        else:
            factors.append("email_code")
        if environment.lower().strip() in {"hospital", "bank", "regulated"}:
            factors.extend(["biometric", "voice"])
        elif role == "admin" or action in SENSITIVE_ACTIONS:
            factors.append("biometric")
        return _unique(factors)

    def get_session(self, session_id: str) -> dict | None:
        with self._connect() as connection:
            row = connection.execute(
                "SELECT * FROM auth_sessions WHERE id = ?",
                (session_id,),
            ).fetchone()
        return dict(row) if row is not None else None

    def get_user_by_id(self, user_id: str) -> dict | None:
        with self._connect() as connection:
            row = connection.execute(
                "SELECT * FROM enterprise_users WHERE id = ?",
                (user_id,),
            ).fetchone()
        return self._user_dict(row) if row is not None else None

    def public_session(self, session: dict) -> dict:
        user = self.get_user_by_id(session["user_id"])
        return {
            "id": session["id"],
            "status": session["status"],
            "stage": session["stage"],
            "required_factors": _split(session["required_factors"]),
            "completed_factors": _split(session["completed_factors"]),
            "expires_at": session["expires_at"],
            "provider": session["provider"],
            "user": {
                "id": user["id"],
                "organization_id": user["organization_id"],
                "email": user["email"],
                "full_name": user["full_name"],
                "role": user["role"],
                "permissions": sorted(ROLE_PERMISSIONS[user["role"]]),
            }
            if user
            else None,
        }

    def _next_stage(self, required: list[str], completed: set[str]) -> str:
        for factor in required:
            if factor not in completed:
                return factor
        return "ready"

    def _update_session(self, session_id: str, **values):
        if not values:
            return
        assignments = ", ".join(f"{key} = ?" for key in values)
        with self._lock, self._connect() as connection:
            connection.execute(
                f"UPDATE auth_sessions SET {assignments} WHERE id = ?",
                (*values.values(), session_id),
            )

    def _user_dict(self, row) -> dict:
        return {
            "id": row["id"],
            "organization_id": row["organization_id"],
            "email": row["email"],
            "full_name": row["full_name"],
            "phone": row["phone"],
            "role": row["role"],
            "status": row["status"],
            "created_at": row["created_at"],
        }

    def _audit(self, event_type: str, outcome: str, metadata: dict):
        if self.audit_store is not None:
            self.audit_store.append(event_type, outcome, metadata)


def _now() -> str:
    return datetime.now(timezone.utc).isoformat()


def _expired(value: str) -> bool:
    return datetime.fromisoformat(value) < datetime.now(timezone.utc)


def _split(value: str) -> list[str]:
    return [item for item in value.split(",") if item]


def _unique(values: list[str]) -> list[str]:
    result = []
    for value in values:
        if value not in result:
            result.append(value)
    return result


def _email_domain(email: str) -> str:
    return email.split("@", 1)[1] if "@" in email else "unknown"


def _permission_for_action(action: str) -> str:
    normalized = action.lower().strip()
    mapping = {
        "read_project": "project:read",
        "preview_edit": "editor:preview",
        "apply_edit": "editor:apply",
        "undo_edit": "editor:undo",
        "run_diagnostics": "execute:routine",
        "run_command": "execute:sensitive",
        "manage_users": "users:manage",
    }
    return mapping.get(normalized, normalized)


def _blocked(title: str, message: str) -> dict:
    return {
        "success": False,
        "authorized": False,
        "status": "blocked",
        "title": title,
        "message": message,
    }


def _message_for_stage(
    stage: str,
    required_factors: list[str],
    completed_factors,
) -> str:
    completed = set(completed_factors)
    if stage == "email_code":
        return "Código enviado. Revisa tu correo para continuar."
    if stage == "oauth":
        return "Autoriza con tu proveedor."
    if stage == "sso":
        return "Autoriza con tu proveedor de identidad."
    if stage == "biometric":
        return "Código validado. Confirma ahora con Face ID o Touch ID."
    if stage == "voice":
        return "Biometría validada. Confirma tu voz para activar OSvoz."
    if stage == "ready":
        return "Acceso autorizado. OSvoz está listo."
    missing = [factor for factor in required_factors if factor not in completed]
    return f"Continúa con {missing[0]}." if missing else "OSvoz está listo."
