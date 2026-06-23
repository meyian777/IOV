import 'package:flutter_test/flutter_test.dart';
import 'package:labvoice/services/voice_engine.dart';

void main() {
  test('keeps short speech unchanged', () {
    expect(VoiceEngine.textForSpeech('Hola Ian.'), 'Hola Ian.');
  });

  test('bounds long speech requests while preserving visible response', () {
    final result = VoiceEngine.textForSpeech('a' * 5000);

    expect(result.length, lessThanOrEqualTo(4000));
    expect(
      result,
      endsWith('La respuesta completa permanece visible en pantalla.'),
    );
  });
}
