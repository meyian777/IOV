import plistlib
import unittest
from pathlib import Path
from xml.etree import ElementTree


ROOT = Path(__file__).resolve().parent.parent / "labvoice"
ANDROID_NAMESPACE = "http://schemas.android.com/apk/res/android"


class PlatformPermissionsTest(unittest.TestCase):
    def test_android_declares_voice_permissions_and_service_query(self):
        manifest = ElementTree.parse(
            ROOT / "android" / "app" / "src" / "main" / "AndroidManifest.xml"
        ).getroot()
        name_attribute = f"{{{ANDROID_NAMESPACE}}}name"
        permissions = {
            node.attrib[name_attribute]
            for node in manifest.findall("uses-permission")
        }

        self.assertIn("android.permission.RECORD_AUDIO", permissions)
        self.assertIn("android.permission.INTERNET", permissions)
        self.assertIn("android.permission.BLUETOOTH_CONNECT", permissions)

        query_actions = {
            node.attrib[name_attribute]
            for node in manifest.findall("./queries/intent/action")
        }
        self.assertIn("android.speech.RecognitionService", query_actions)

    def test_apple_platforms_explain_voice_permissions(self):
        for platform in ("ios", "macos"):
            with (
                ROOT / platform / "Runner" / "Info.plist"
            ).open("rb") as plist_file:
                info = plistlib.load(plist_file)

            self.assertTrue(info["NSMicrophoneUsageDescription"])
            self.assertTrue(info["NSSpeechRecognitionUsageDescription"])

    def test_macos_sandbox_allows_audio_and_local_backend_access(self):
        for filename in ("DebugProfile.entitlements", "Release.entitlements"):
            with (
                ROOT / "macos" / "Runner" / filename
            ).open("rb") as plist_file:
                entitlements = plistlib.load(plist_file)

            self.assertTrue(entitlements["com.apple.security.device.audio-input"])
            self.assertTrue(entitlements["com.apple.security.network.client"])
