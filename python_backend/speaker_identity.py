from dataclasses import asdict, dataclass
from io import BytesIO
import json
import math
from pathlib import Path
import time
import wave
from typing import Protocol


@dataclass(frozen=True)
class SpeakerIdentityStatus:
    enabled: bool
    enrolled: bool
    provider: str
    framework: str
    assurance: str
    fail_closed_for_sensitive_actions: bool

    def to_dict(self) -> dict:
        return asdict(self)


class SpeakerIdentityProvider(Protocol):
    def status(self) -> SpeakerIdentityStatus: ...

    def verify(self, audio_bytes: bytes) -> bool: ...

    def enroll(self, audio_bytes: bytes, phrase: str = "") -> dict: ...


class DisabledSpeakerIdentityProvider:
    def status(self) -> SpeakerIdentityStatus:
        return SpeakerIdentityStatus(
            enabled=False,
            enrolled=False,
            provider="disabled",
            framework="tensorflow_or_pytorch_boundary",
            assurance="not_enrolled_confirmation_required",
            fail_closed_for_sensitive_actions=True,
        )

    def verify(self, audio_bytes: bytes) -> bool:
        return False

    def enroll(self, audio_bytes: bytes, phrase: str = "") -> dict:
        return {
            "success": False,
            "error": "speaker_identity_disabled",
            "message": "Speaker identity is not enabled.",
        }


class LocalVoiceprintProvider:
    MIN_ENROLLMENT_SAMPLES = 3
    RECOMMENDED_ENROLLMENT_SAMPLES = 12
    VERIFY_THRESHOLD = 0.18

    def __init__(self, profile_path: str | Path):
        self.profile_path = Path(profile_path)

    def status(self) -> SpeakerIdentityStatus:
        profile = self._load_profile()
        sample_count = profile.get("sample_count", 0) if profile else 0
        return SpeakerIdentityStatus(
            enabled=True,
            enrolled=sample_count >= self.MIN_ENROLLMENT_SAMPLES,
            provider="local_voiceprint",
            framework="classical_audio_features_tensorflow_boundary",
            assurance=(
                "local_voiceprint_ready"
                if sample_count >= self.MIN_ENROLLMENT_SAMPLES
                else "enrollment_required"
            ),
            fail_closed_for_sensitive_actions=True,
        )

    def enroll(self, audio_bytes: bytes, phrase: str = "") -> dict:
        features = VoiceFeatureExtractor.extract(audio_bytes)
        profile = self._load_profile() or {
            "version": 1,
            "sample_count": 0,
            "mean": [0.0 for _ in features],
            "created_at": time.time(),
            "updated_at": time.time(),
            "phrases": [],
        }
        count = int(profile["sample_count"])
        current_mean = [float(value) for value in profile["mean"]]
        updated_mean = [
            ((current_mean[index] * count) + features[index]) / (count + 1)
            for index in range(len(features))
        ]
        profile["sample_count"] = count + 1
        profile["mean"] = updated_mean
        profile["updated_at"] = time.time()
        if phrase:
            phrases = profile.setdefault("phrases", [])
            if phrase not in phrases:
                phrases.append(phrase[:120])
            profile["phrases"] = phrases[-20:]
        self._save_profile(profile)
        return {
            "success": True,
            "sample_count": profile["sample_count"],
            "enrolled": profile["sample_count"] >= self.MIN_ENROLLMENT_SAMPLES,
            "recommended_samples": self.RECOMMENDED_ENROLLMENT_SAMPLES,
            "message": (
                "Voice profile enrolled."
                if profile["sample_count"] >= self.MIN_ENROLLMENT_SAMPLES
                else "Voice sample saved. More samples are required."
            ),
        }

    def verify(self, audio_bytes: bytes) -> bool:
        result = self.verify_details(audio_bytes)
        return bool(result["success"] and result["verified"])

    def verify_details(self, audio_bytes: bytes) -> dict:
        profile = self._load_profile()
        if not profile or int(profile.get("sample_count", 0)) < self.MIN_ENROLLMENT_SAMPLES:
            return {
                "success": False,
                "verified": False,
                "error": "speaker_not_enrolled",
                "message": "Speaker identity has not been enrolled.",
            }
        features = VoiceFeatureExtractor.extract(audio_bytes)
        mean = [float(value) for value in profile["mean"]]
        distance = math.sqrt(
            sum((features[index] - mean[index]) ** 2 for index in range(len(features)))
        )
        return {
            "success": True,
            "verified": distance <= self.VERIFY_THRESHOLD,
            "distance": round(distance, 6),
            "threshold": self.VERIFY_THRESHOLD,
            "sample_count": profile["sample_count"],
        }

    def _load_profile(self) -> dict | None:
        if not self.profile_path.is_file():
            return None
        try:
            return json.loads(self.profile_path.read_text(encoding="utf-8"))
        except (json.JSONDecodeError, OSError, KeyError, TypeError):
            return None

    def _save_profile(self, profile: dict):
        self.profile_path.parent.mkdir(parents=True, exist_ok=True)
        temporary_path = self.profile_path.with_suffix(".tmp")
        temporary_path.write_text(json.dumps(profile, indent=2), encoding="utf-8")
        temporary_path.replace(self.profile_path)


class VoiceFeatureExtractor:
    @staticmethod
    def extract(audio_bytes: bytes) -> list[float]:
        try:
            with wave.open(BytesIO(audio_bytes), "rb") as audio:
                channels = audio.getnchannels()
                sample_width = audio.getsampwidth()
                sample_rate = audio.getframerate()
                frame_count = audio.getnframes()
                frames = audio.readframes(frame_count)
        except (wave.Error, EOFError) as error:
            raise ValueError("Audio must be a valid WAV file.") from error

        if sample_width != 2:
            raise ValueError("Audio must use 16-bit PCM samples.")
        if channels not in {1, 2}:
            raise ValueError("Audio must be mono or stereo.")
        if sample_rate <= 0:
            raise ValueError("Audio sample rate is invalid.")

        samples = []
        step = sample_width * channels
        for offset in range(0, len(frames) - step + 1, step):
            if channels == 1:
                sample = int.from_bytes(
                    frames[offset : offset + 2],
                    byteorder="little",
                    signed=True,
                )
            else:
                left = int.from_bytes(
                    frames[offset : offset + 2],
                    byteorder="little",
                    signed=True,
                )
                right = int.from_bytes(
                    frames[offset + 2 : offset + 4],
                    byteorder="little",
                    signed=True,
                )
                sample = int((left + right) / 2)
            samples.append(sample / 32768.0)

        if len(samples) < sample_rate * 0.35:
            raise ValueError("Audio is too short for speaker identity.")

        rms = math.sqrt(sum(sample * sample for sample in samples) / len(samples))
        if rms < 0.004:
            raise ValueError("Audio does not contain enough voice energy.")
        peak = max(abs(sample) for sample in samples)
        zero_crossings = sum(
            1
            for index in range(1, len(samples))
            if (samples[index - 1] < 0 <= samples[index])
            or (samples[index - 1] >= 0 > samples[index])
        )
        zcr = zero_crossings / max(len(samples) - 1, 1)
        mean_abs = sum(abs(sample) for sample in samples) / len(samples)
        dynamic_range = peak - mean_abs
        thirds = [
            samples[0 : len(samples) // 3],
            samples[len(samples) // 3 : (len(samples) * 2) // 3],
            samples[(len(samples) * 2) // 3 :],
        ]
        segment_rms = [
            math.sqrt(sum(sample * sample for sample in segment) / len(segment))
            if segment
            else 0.0
            for segment in thirds
        ]
        return [
            min(rms, 1.0),
            min(peak, 1.0),
            min(zcr, 1.0),
            min(mean_abs, 1.0),
            min(dynamic_range, 1.0),
            *[min(value, 1.0) for value in segment_rms],
        ]


class SpeakerIdentityService:
    def __init__(self, provider: SpeakerIdentityProvider | None = None):
        self.provider = provider or DisabledSpeakerIdentityProvider()

    def status(self) -> dict:
        return self.provider.status().to_dict()

    def verify(self, audio_bytes: bytes) -> bool:
        if not audio_bytes:
            return False
        return self.provider.verify(audio_bytes)

    def enroll(self, audio_bytes: bytes, phrase: str = "") -> dict:
        if not audio_bytes:
            return {
                "success": False,
                "error": "empty_audio",
                "message": "A voice sample is required.",
            }
        try:
            return self.provider.enroll(audio_bytes, phrase)
        except ValueError as error:
            return {
                "success": False,
                "error": "invalid_voice_sample",
                "message": str(error),
            }

    def verify_details(self, audio_bytes: bytes) -> dict:
        if not audio_bytes:
            return {
                "success": False,
                "verified": False,
                "error": "empty_audio",
                "message": "A voice sample is required.",
            }
        if hasattr(self.provider, "verify_details"):
            try:
                return self.provider.verify_details(audio_bytes)
            except ValueError as error:
                return {
                    "success": False,
                    "verified": False,
                    "error": "invalid_voice_sample",
                    "message": str(error),
                }
        return {
            "success": True,
            "verified": self.verify(audio_bytes),
        }
