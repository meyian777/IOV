import 'package:flutter_test/flutter_test.dart';
import 'package:labvoice/services/voice_noise_gate.dart';

void main() {
  test('accepts a normal spoken command', () {
    final gate = VoiceNoiseGate();

    final result = gate.evaluate('explícame main.dart');

    expect(result.accepted, isTrue);
    expect(result.cleanedTranscript, 'explícame main.dart');
  });

  test('cleans punctuation and spacing around an interrupted command', () {
    final gate = VoiceNoiseGate();

    final result = gate.evaluate('  ... OSvoz,   abre   el proyecto !!! ');

    expect(result.accepted, isTrue);
    expect(result.cleanedTranscript, 'OSvoz, abre el proyecto');
  });

  test('rejects common whisper hallucinations from background noise', () {
    final gate = VoiceNoiseGate();

    final result = gate.evaluate('Subtítulos realizados por la comunidad');

    expect(result.accepted, isFalse);
    expect(result.reason, 'likely_background_or_hallucination');
  });

  test('rejects cjk hallucinations while testing Spanish voice', () {
    final gate = VoiceNoiseGate();

    final result = gate.evaluate('記者:請問你幾個月後的時間');

    expect(result.accepted, isFalse);
    expect(result.reason, 'likely_background_or_hallucination');
  });

  test('rejects duplicate transcripts within a short window', () {
    var now = DateTime(2026, 6, 23, 13);
    final gate = VoiceNoiseGate(clock: () => now);

    expect(gate.evaluate('abre visual studio code').accepted, isTrue);
    now = now.add(const Duration(seconds: 3));
    final duplicate = gate.evaluate('abre visual studio code');

    expect(duplicate.accepted, isFalse);
    expect(duplicate.reason, 'duplicate_transcript');
  });

  test('accepts the same command after the duplicate window expires', () {
    var now = DateTime(2026, 6, 23, 13);
    final gate = VoiceNoiseGate(clock: () => now);

    expect(gate.evaluate('abre visual studio code').accepted, isTrue);
    now = now.add(const Duration(seconds: 9));

    expect(gate.evaluate('abre visual studio code').accepted, isTrue);
  });
}
