import json
from pathlib import Path

from cryptography.fernet import Fernet, InvalidToken


class FounderProfileStore:
    def __init__(self, encrypted_path: str, encryption_key: str):
        if not encryption_key:
            raise ValueError("Founder profile encryption key is required.")
        self.encrypted_path = Path(encrypted_path).expanduser().resolve()
        self.encrypted_path.parent.mkdir(parents=True, exist_ok=True)
        self._cipher = Fernet(encryption_key.encode("utf-8"))

    def save(self, profile: dict) -> None:
        serialized = json.dumps(
            profile,
            ensure_ascii=False,
            separators=(",", ":"),
        ).encode("utf-8")
        encrypted = self._cipher.encrypt(serialized)
        self.encrypted_path.write_bytes(encrypted)

    def load(self) -> dict:
        if not self.encrypted_path.exists():
            raise FileNotFoundError("Encrypted founder profile not found.")
        try:
            decrypted = self._cipher.decrypt(self.encrypted_path.read_bytes())
        except InvalidToken as error:
            raise ValueError("Founder profile could not be decrypted.") from error
        return json.loads(decrypted.decode("utf-8"))
