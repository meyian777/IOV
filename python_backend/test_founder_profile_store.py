import tempfile
import unittest
from pathlib import Path

from cryptography.fernet import Fernet

from founder_profile_store import FounderProfileStore


class FounderProfileStoreTest(unittest.TestCase):
    def test_profile_is_encrypted_and_can_be_recovered(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "founder.enc"
            store = FounderProfileStore(
                str(path),
                Fernet.generate_key().decode("utf-8"),
            )
            profile = {
                "full_name": "Ian Faber Mendoza Mey",
                "public_biography": "Founder of LabVoice.",
            }

            store.save(profile)

            self.assertNotIn(b"Ian Faber Mendoza Mey", path.read_bytes())
            self.assertEqual(store.load(), profile)

    def test_wrong_key_cannot_decrypt_profile(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "founder.enc"
            first = FounderProfileStore(
                str(path),
                Fernet.generate_key().decode("utf-8"),
            )
            first.save({"full_name": "Ian Faber Mendoza Mey"})
            second = FounderProfileStore(
                str(path),
                Fernet.generate_key().decode("utf-8"),
            )

            with self.assertRaises(ValueError):
                second.load()
