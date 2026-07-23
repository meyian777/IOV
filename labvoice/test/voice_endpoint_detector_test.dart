import 'package:flutter_test/flutter_test.dart';
import 'package:labvoice/services/voice_endpoint_detector.dart';

void main() {
  test('corta poco después de que termina una frase', () {
    final detector = VoiceEndpointDetector();
    final start = DateTime(2026, 7, 13, 20);
    detector.start(start);

    detector.observe(-58, start.add(const Duration(milliseconds: 120)));
    detector.observe(-56, start.add(const Duration(milliseconds: 240)));
    detector.observe(-18, start.add(const Duration(milliseconds: 480)));
    detector.observe(-17, start.add(const Duration(milliseconds: 600)));
    detector.observe(-16, start.add(const Duration(milliseconds: 720)));

    expect(
      detector.observe(-52, start.add(const Duration(milliseconds: 1320))),
      VoiceEndpointDecision.speechEnded,
    );
  });

  test('separa la voz de ruido ambiente sostenido', () {
    final detector = VoiceEndpointDetector();
    final start = DateTime(2026, 7, 13, 20);
    detector.start(start);

    detector.observe(-30, start.add(const Duration(milliseconds: 120)));
    detector.observe(-29, start.add(const Duration(milliseconds: 240)));
    detector.observe(-10, start.add(const Duration(milliseconds: 480)));
    detector.observe(-9, start.add(const Duration(milliseconds: 600)));
    detector.observe(-8, start.add(const Duration(milliseconds: 720)));

    expect(detector.voiceThresholdDb, greaterThan(-25));
    expect(
      detector.observe(-30, start.add(const Duration(milliseconds: 1320))),
      VoiceEndpointDecision.speechEnded,
    );
  });

  test('termina una captura sin voz después del tiempo inicial', () {
    final detector = VoiceEndpointDetector();
    final start = DateTime(2026, 7, 13, 20);
    detector.start(start);

    detector.observe(-55, start.add(const Duration(milliseconds: 120)));

    expect(
      detector.evaluate(start.add(const Duration(seconds: 3))),
      VoiceEndpointDecision.initialSilence,
    );
  });

  test('mantiene un límite máximo aunque el ambiente sea ruidoso', () {
    final detector = VoiceEndpointDetector();
    final start = DateTime(2026, 7, 13, 20);
    detector.start(start);

    expect(
      detector.evaluate(start.add(const Duration(seconds: 8))),
      VoiceEndpointDecision.maximumDuration,
    );
  });
}
