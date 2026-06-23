import unittest

from speaker_identity import SpeakerIdentityService


class SpeakerIdentityServiceTest(unittest.TestCase):
    def test_disabled_provider_fails_closed(self):
        service = SpeakerIdentityService()

        self.assertFalse(service.verify(b"audio"))
        self.assertFalse(service.status()["enabled"])
        self.assertTrue(
            service.status()["fail_closed_for_sensitive_actions"]
        )
