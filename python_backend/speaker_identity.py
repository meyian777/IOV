from dataclasses import asdict, dataclass
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


class DisabledSpeakerIdentityProvider:
    def status(self) -> SpeakerIdentityStatus:
        return SpeakerIdentityStatus(
            enabled=False,
            enrolled=False,
            provider="disabled",
            framework="tensorflow_or_pytorch_boundary",
            assurance="wake_word_only",
            fail_closed_for_sensitive_actions=True,
        )

    def verify(self, audio_bytes: bytes) -> bool:
        return False


class SpeakerIdentityService:
    def __init__(self, provider: SpeakerIdentityProvider | None = None):
        self.provider = provider or DisabledSpeakerIdentityProvider()

    def status(self) -> dict:
        return self.provider.status().to_dict()

    def verify(self, audio_bytes: bytes) -> bool:
        if not audio_bytes:
            return False
        return self.provider.verify(audio_bytes)
