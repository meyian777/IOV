import 'package:flutter_test/flutter_test.dart';
import 'package:labvoice/services/labvoice_api.dart';
import 'package:labvoice/services/voice_fallback_policy.dart';

void main() {
  test('falls back to native speech when backend is unavailable', () {
    const error = OSvozApiException(
      'OSvoz backend is unavailable.',
      code: 'backend_unavailable',
    );

    expect(VoiceFallbackPolicy.shouldUseNativeSpeechFallback(error), isTrue);
  });

  test(
    'falls back to native speech on local Whisper infrastructure failures',
    () {
      const error = OSvozApiException(
        'load_backend failed: /opt/homebrew/libggml metal_device error',
        code: 'transcription_failed',
      );

      expect(VoiceFallbackPolicy.shouldUseNativeSpeechFallback(error), isTrue);
      expect(
        VoiceFallbackPolicy.safeVoiceErrorMessage(error.message),
        isNot(contains('/opt/homebrew')),
      );
    },
  );

  test('does not use native fallback for ordinary no speech windows', () {
    const error = OSvozApiException(
      'No speech detected.',
      code: 'transcription_failed',
    );

    expect(VoiceFallbackPolicy.isNoSpeech(error), isTrue);
    expect(VoiceFallbackPolicy.shouldUseNativeSpeechFallback(error), isFalse);
  });
}
