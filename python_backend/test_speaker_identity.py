import unittest
import math
import struct
import tempfile
import wave
from pathlib import Path

from speaker_identity import LocalVoiceprintProvider, SpeakerIdentityService


class SpeakerIdentityServiceTest(unittest.TestCase):
    def test_disabled_provider_fails_closed(self):
        service = SpeakerIdentityService()

        self.assertFalse(service.verify(b"audio"))
        self.assertFalse(service.status()["enabled"])
        self.assertEqual(
            service.status()["assurance"],
            "not_enrolled_confirmation_required",
        )
        self.assertTrue(
            service.status()["fail_closed_for_sensitive_actions"]
        )

    def test_local_provider_enrolls_and_verifies_voiceprint(self):
        with tempfile.TemporaryDirectory() as directory:
            service = SpeakerIdentityService(
                LocalVoiceprintProvider(Path(directory) / "voiceprint.json")
            )
            sample = wav_tone(220)

            first = service.enroll(sample, "OSvoz soy Ian")
            second = service.enroll(sample, "OSvoz abre el proyecto")
            third = service.enroll(sample, "OSvoz confirma seguridad")

            self.assertFalse(first["enrolled"])
            self.assertFalse(second["enrolled"])
            self.assertTrue(third["enrolled"])
            self.assertTrue(service.status()["enrolled"])
            self.assertTrue(service.verify(sample))

    def test_local_provider_fails_closed_before_enrollment(self):
        with tempfile.TemporaryDirectory() as directory:
            service = SpeakerIdentityService(
                LocalVoiceprintProvider(Path(directory) / "voiceprint.json")
            )

            result = service.verify_details(wav_tone(220))

            self.assertFalse(result["verified"])
            self.assertEqual(result["error"], "speaker_not_enrolled")


def wav_tone(frequency: int, duration_seconds: float = 1.0) -> bytes:
    sample_rate = 16000
    frame_count = int(sample_rate * duration_seconds)
    frames = bytearray()
    for index in range(frame_count):
        sample = int(math.sin(2 * math.pi * frequency * index / sample_rate) * 9000)
        frames.extend(struct.pack("<h", sample))

    with tempfile.NamedTemporaryFile(suffix=".wav", delete=False) as temporary:
        path = Path(temporary.name)
    try:
        with wave.open(str(path), "wb") as audio:
            audio.setnchannels(1)
            audio.setsampwidth(2)
            audio.setframerate(sample_rate)
            audio.writeframes(bytes(frames))
        return path.read_bytes()
    finally:
        path.unlink(missing_ok=True)
