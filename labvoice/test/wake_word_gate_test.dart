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

    final result = gate.evaluate('OSvoz, abre el proyecto');

    expect(result.accepted, isTrue);
    expect(result.activated, isTrue);
    expect(result.command, 'abre el proyecto');
  });

  test('accepts spaced OS voz wake word variant', () {
    final gate = WakeWordGate();

    final result = gate.evaluate('OS voz abre visual studio code');

    expect(result.accepted, isTrue);
    expect(result.activated, isTrue);
    expect(result.command, 'abre visual studio code');
  });

  test('does not accept old wake word aliases', () {
    final gate = WakeWordGate();

    expect(gate.evaluate('iVOZ abre visual studio code').accepted, isFalse);
    expect(gate.evaluate('LabVoice abre visual studio code').accepted, isFalse);
    expect(gate.evaluate('la boyce abre visual studio code').accepted, isFalse);
  });

  test('accepts natural follow-up during active conversation', () {
    var now = DateTime(2026, 6, 22, 12);
    final gate = WakeWordGate(
      sessionDuration: const Duration(seconds: 35),
      clock: () => now,
    );
    gate.evaluate('OSvoz, revisa el archivo');
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
    gate.evaluate('OSvoz, revisa el archivo');
    now = now.add(const Duration(seconds: 36));

    expect(gate.evaluate('continúa').accepted, isFalse);
  });
}
