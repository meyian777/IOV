import 'package:flutter_test/flutter_test.dart';
import 'package:labvoice/services/voice_echo_guard.dart';

void main() {
  test('bloquea transcripciones mientras OSvoz habla', () {
    var now = DateTime(2026, 6, 24, 20);
    final guard = VoiceEchoGuard(clock: () => now);

    guard.markSpeechStarted('Mi creador es Ian Faber Mendoza Mey.');

    expect(
      guard.evaluate('abre terminal').reason,
      'osvoz_speaking_or_cooldown',
    );
  });

  test('bloquea transcripciones durante cooldown al terminar de hablar', () {
    var now = DateTime(2026, 6, 24, 20);
    final guard = VoiceEchoGuard(clock: () => now);

    guard.markSpeechStarted('Listo, estoy revisando el proyecto.');
    guard.markSpeechEnded();
    now = now.add(const Duration(milliseconds: 800));

    expect(guard.evaluate('continúa').blocked, isTrue);
  });

  test('bloquea interrupciones accidentales mientras termina la respuesta', () {
    var now = DateTime(2026, 6, 24, 20);
    final guard = VoiceEchoGuard(clock: () => now);

    guard.markSpeechStarted('Estoy preparando la vista previa del cambio.');
    guard.markSpeechEnded();
    now = now.add(const Duration(milliseconds: 300));

    final decision = guard.evaluate('sí aplicar');

    expect(decision.blocked, isTrue);
    expect(decision.reason, 'osvoz_speaking_or_cooldown');
  });

  test('bloquea eco parecido a la última respuesta hablada', () {
    var now = DateTime(2026, 6, 24, 20);
    final guard = VoiceEchoGuard(clock: () => now);

    guard.markSpeechStarted(
      'Mi creador es Ian Faber Mendoza Mey y puedo ayudarte con el proyecto.',
    );
    guard.markSpeechEnded();
    now = now.add(const Duration(seconds: 2));

    final decision = guard.evaluate(
      'mi creador es Ian Faber Mendoza Mey puedo ayudarte proyecto',
    );

    expect(decision.blocked, isTrue);
    expect(decision.reason, 'matched_last_osvoz_response');
  });

  test('acepta una orden diferente después del cooldown', () {
    var now = DateTime(2026, 6, 24, 20);
    final guard = VoiceEchoGuard(clock: () => now);

    guard.markSpeechStarted('Listo, ya revisé el proyecto.');
    guard.markSpeechEnded();
    now = now.add(const Duration(seconds: 2));

    expect(guard.evaluate('abre terminal').blocked, isFalse);
  });
}
