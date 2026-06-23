import 'package:flutter_test/flutter_test.dart';
import 'package:labvoice/services/wake_word_gate.dart';

void main() {
  test('ignores ambient speech before activation', () {
    final gate = WakeWordGate();

    final result = gate.evaluate('abre el proyecto');

    expect(result.accepted, isFalse);
  });

  test('accepts wake word and extracts command', () {
    final gate = WakeWordGate();

    final result = gate.evaluate('LabVoice, abre el proyecto');

    expect(result.accepted, isTrue);
    expect(result.activated, isTrue);
    expect(result.command, 'abre el proyecto');
  });

  test('accepts natural follow-up during active conversation', () {
    var now = DateTime(2026, 6, 22, 12);
    final gate = WakeWordGate(
      sessionDuration: const Duration(seconds: 35),
      clock: () => now,
    );
    gate.evaluate('LabVoice, revisa el archivo');
    now = now.add(const Duration(seconds: 10));

    final result = gate.evaluate('continúa');

    expect(result.accepted, isTrue);
    expect(result.activated, isFalse);
  });

  test('ignores follow-up after conversation expires', () {
    var now = DateTime(2026, 6, 22, 12);
    final gate = WakeWordGate(
      sessionDuration: const Duration(seconds: 35),
      clock: () => now,
    );
    gate.evaluate('LabVoice, revisa el archivo');
    now = now.add(const Duration(seconds: 36));

    expect(gate.evaluate('continúa').accepted, isFalse);
  });
}
