import unittest

from code_capability_router import CodeCapabilityRouter


class CodeCapabilityRouterTest(unittest.TestCase):
    def test_routes_flutter_debugging(self):
        route = CodeCapabilityRouter.route(
            "Corrige este error de Flutter en voice_engine.dart"
        )

        self.assertEqual(route.domain, "software_engineering")
        self.assertEqual(route.capability, "debug")
        self.assertEqual(route.language, "dart")
        self.assertEqual(route.risk, "code_change")

    def test_routes_python_security_review(self):
        route = CodeCapabilityRouter.route(
            "Review this FastAPI Python code for security vulnerabilities"
        )

        self.assertEqual(route.capability, "security_review")
        self.assertEqual(route.language, "python")
        self.assertEqual(route.risk, "security_sensitive")

    def test_keeps_normal_conversation_outside_code_agent(self):
        route = CodeCapabilityRouter.route("¿Cómo estás hoy?")

        self.assertEqual(route.domain, "general")
        self.assertEqual(route.capability, "conversation")
