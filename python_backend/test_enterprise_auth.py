import tempfile
import unittest
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timedelta, timezone
from pathlib import Path

from audit_store import AuditStore
from enterprise_auth import EnterpriseAuthStore


class EnterpriseAuthStoreTest(unittest.TestCase):
    def test_regulated_editor_requires_email_biometric_and_voice(self):
        with tempfile.TemporaryDirectory() as directory:
            audit = AuditStore(str(Path(directory) / "audit.db"))
            store = EnterpriseAuthStore(
                str(Path(directory) / "enterprise.db"),
                audit_store=audit,
            )
            store.register_user(
                organization_id="acme",
                email="dev@acme.test",
                full_name="Dev User",
                phone="+15550000001",
                role="editor",
            )

            started = store.start_session(
                email="dev@acme.test",
                provider="email_code",
                environment="bank",
                ip_address="127.0.0.1",
                device_id="macbook-dev",
                code="123456",
            )

            self.assertEqual(
                started["session"]["required_factors"],
                ["email_code", "biometric", "voice"],
            )
            self.assertEqual(started["session"]["stage"], "email_code")

            after_code = store.verify_factor(
                session_id=started["session"]["id"],
                factor="email_code",
                code="123456",
            )
            self.assertEqual(after_code["session"]["stage"], "biometric")

            after_biometric = store.verify_factor(
                session_id=started["session"]["id"],
                factor="biometric",
            )
            self.assertEqual(after_biometric["session"]["stage"], "voice")

            after_voice = store.verify_factor(
                session_id=started["session"]["id"],
                factor="voice",
            )
            self.assertEqual(after_voice["session"]["status"], "authorized")
            self.assertTrue(audit.verify()["valid"])

    def test_reader_cannot_apply_editor_changes(self):
        with tempfile.TemporaryDirectory() as directory:
            store = EnterpriseAuthStore(str(Path(directory) / "enterprise.db"))
            store.register_user(
                organization_id="acme",
                email="reader@acme.test",
                full_name="Reader User",
                phone="+15550000002",
                role="reader",
            )
            started = store.start_session(
                email="reader@acme.test",
                provider="email_code",
                environment="standard",
                ip_address="127.0.0.1",
                device_id="macbook-reader",
                code="654321",
            )
            store.verify_factor(
                session_id=started["session"]["id"],
                factor="email_code",
                code="654321",
            )

            result = store.authorize_action(
                session_id=started["session"]["id"],
                action="apply_edit",
                environment="standard",
            )

            self.assertFalse(result["authorized"])
            self.assertEqual(result["title"], "Permiso insuficiente")

    def test_expired_code_blocks_session_with_clear_message(self):
        with tempfile.TemporaryDirectory() as directory:
            store = EnterpriseAuthStore(str(Path(directory) / "enterprise.db"))
            store.register_user(
                organization_id="acme",
                email="expired@acme.test",
                full_name="Expired User",
                phone="+15550000004",
                role="editor",
            )
            started = store.start_session(
                email="expired@acme.test",
                provider="email_code",
                environment="standard",
                ip_address="127.0.0.1",
                device_id="macbook-expired",
                code="999999",
            )
            store._update_session(
                started["session"]["id"],
                expires_at=(
                    datetime.now(timezone.utc) - timedelta(seconds=1)
                ).isoformat(),
            )

            result = store.verify_factor(
                session_id=started["session"]["id"],
                factor="email_code",
                code="999999",
            )

            self.assertFalse(result["success"])
            self.assertEqual(result["title"], "Código vencido")

    def test_failed_codes_lock_session_and_resend_unlocks_it(self):
        with tempfile.TemporaryDirectory() as directory:
            store = EnterpriseAuthStore(str(Path(directory) / "enterprise.db"))
            store.register_user(
                organization_id="acme",
                email="lock@acme.test",
                full_name="Locked User",
                phone="+15550000005",
                role="editor",
            )
            started = store.start_session(
                email="lock@acme.test",
                provider="email_code",
                environment="standard",
                ip_address="127.0.0.1",
                device_id="macbook-lock",
                code="123456",
            )
            session_id = started["session"]["id"]

            result = None
            for attempt in range(store.max_failed_attempts):
                result = store.verify_factor(
                    session_id=session_id,
                    factor="email_code",
                    code=f"00000{attempt}",
                )

            self.assertEqual(result["title"], "Sesión bloqueada")
            blocked = store.verify_factor(
                session_id=session_id,
                factor="email_code",
                code="123456",
            )
            self.assertEqual(blocked["title"], "Sesión bloqueada")

            resent = store.resend_code(session_id=session_id, code="654321")
            self.assertTrue(resent["success"])
            verified = store.verify_factor(
                session_id=session_id,
                factor="email_code",
                code="654321",
            )
            self.assertTrue(verified["success"])

    def test_admin_sensitive_action_requires_biometric_in_standard_environment(self):
        with tempfile.TemporaryDirectory() as directory:
            store = EnterpriseAuthStore(str(Path(directory) / "enterprise.db"))
            store.register_user(
                organization_id="acme",
                email="admin@acme.test",
                full_name="Admin User",
                phone="+15550000003",
                role="admin",
            )
            started = store.start_session(
                email="admin@acme.test",
                provider="email_code",
                environment="standard",
                ip_address="127.0.0.1",
                device_id="macbook-admin",
                code="111111",
            )
            self.assertEqual(
                started["session"]["required_factors"],
                ["email_code", "biometric"],
            )
            store.verify_factor(
                session_id=started["session"]["id"],
                factor="email_code",
                code="111111",
            )

            pending = store.authorize_action(
                session_id=started["session"]["id"],
                action="manage_users",
                environment="standard",
            )
            self.assertEqual(pending["status"], "pending_mfa")
            self.assertEqual(pending["missing_factors"], ["biometric"])

            store.verify_factor(
                session_id=started["session"]["id"],
                factor="biometric",
            )
            authorized = store.authorize_action(
                session_id=started["session"]["id"],
                action="manage_users",
                environment="standard",
            )
            self.assertTrue(authorized["authorized"])

    def test_parallel_users_keep_sessions_and_audit_chain_isolated(self):
        with tempfile.TemporaryDirectory() as directory:
            audit = AuditStore(str(Path(directory) / "audit.db"))
            store = EnterpriseAuthStore(
                str(Path(directory) / "enterprise.db"),
                audit_store=audit,
            )

            for index in range(30):
                role = "reader" if index % 5 == 0 else "editor"
                store.register_user(
                    organization_id="acme",
                    email=f"user{index}@acme.test",
                    full_name=f"User {index}",
                    phone=f"+1555000{index:04d}",
                    role=role,
                )

            def run_session(index: int) -> tuple[str, bool, str]:
                environment = "bank" if index % 2 == 0 else "standard"
                started = store.start_session(
                    email=f"user{index}@acme.test",
                    provider="email_code",
                    environment=environment,
                    ip_address=f"10.0.0.{index}",
                    device_id=f"device-{index}",
                    code=f"{index:06d}",
                )
                session_id = started["session"]["id"]
                store.verify_factor(
                    session_id=session_id,
                    factor="email_code",
                    code=f"{index:06d}",
                )
                if "biometric" in started["session"]["required_factors"]:
                    store.verify_factor(session_id=session_id, factor="biometric")
                if "voice" in started["session"]["required_factors"]:
                    store.verify_factor(session_id=session_id, factor="voice")
                action = store.authorize_action(
                    session_id=session_id,
                    action="apply_edit",
                    environment=environment,
                )
                if action.get("status") == "pending_mfa":
                    for factor in action.get("missing_factors", []):
                        store.verify_factor(session_id=session_id, factor=factor)
                    action = store.authorize_action(
                        session_id=session_id,
                        action="apply_edit",
                        environment=environment,
                    )
                return (
                    session_id,
                    action.get("authorized") is True,
                    action.get("title", ""),
                )

            with ThreadPoolExecutor(max_workers=8) as executor:
                results = list(executor.map(run_session, range(30)))

            session_ids = {session_id for session_id, _, _ in results}
            authorized = sum(1 for _, allowed, _ in results if allowed)
            blocked = sum(
                1
                for _, allowed, title in results
                if not allowed and title == "Permiso insuficiente"
            )

            self.assertEqual(len(session_ids), 30)
            self.assertEqual(authorized, 24)
            self.assertEqual(blocked, 6)
            self.assertTrue(audit.verify()["valid"])


if __name__ == "__main__":
    unittest.main()
