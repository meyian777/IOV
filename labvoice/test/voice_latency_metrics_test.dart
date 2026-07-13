import 'package:flutter_test/flutter_test.dart';
import 'package:labvoice/services/voice_latency_metrics.dart';

void main() {
  test('records voice pipeline latency with target labels', () {
    VoiceLatencyMetrics.record(
      'transcription_ms',
      const Duration(milliseconds: 1700),
    );
    VoiceLatencyMetrics.record(
      'language_detection_ms',
      const Duration(milliseconds: 12),
    );
    VoiceLatencyMetrics.record('intent_ms', const Duration(milliseconds: 40));
    VoiceLatencyMetrics.record(
      'orchestration_ms',
      const Duration(milliseconds: 180),
    );
    VoiceLatencyMetrics.record('total_ms', const Duration(milliseconds: 2400));

    final summary = VoiceLatencyMetrics.compactSummary();

    expect(summary, contains('transcripción 1700 ms/1500 lento'));
    expect(summary, contains('idioma 12 ms/80 ok'));
    expect(summary, contains('intención 40 ms/100 ok'));
    expect(summary, contains('orquestador 180 ms/150 lento'));
    expect(summary, contains('total 2400 ms/2500 ok'));
  });
}
