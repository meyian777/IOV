import 'package:flutter_test/flutter_test.dart';
import 'package:labvoice/controllers/labvoice_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('controller owns observable command center state', () {
    final controller = OSvozController();
    var notifications = 0;
    controller.addListener(() => notifications++);

    controller.updatePartialTranscript('abre el proyecto');
    controller.setListening(true);

    expect(controller.heardCommand, 'Escuchando el micrófono...');
    expect(controller.isListening, isTrue);
    expect(notifications, 2);
  });

  test('controller exposes automatic and manual language profiles', () {
    final controller = OSvozController();

    expect(controller.languages['Automático'], 'auto');
    expect(controller.activeLanguageName, 'Español');
    expect(controller.languages['English'], 'en_US');
    expect(controller.languages['Español'], 'es_ES');
  });

  test('controller exposes speech recognition failures', () async {
    final controller = OSvozController();

    await controller.speechRecognitionError('error_audio');

    expect(controller.isListening, isFalse);
    expect(controller.detectedIntent, 'speech_recognition_error');
    expect(controller.technicalAction, 'error_audio');
  });

  test('controller hides local Whisper infrastructure details', () async {
    final controller = OSvozController();

    await controller.speechRecognitionError(
      'Local transcription failed: /opt/homebrew/Cellar/ggml/0.15.2/libexec/libggml-blas.so '
      'load_backend: loaded MTL backend error: failed to initialize whisper context',
    );

    expect(controller.isListening, isFalse);
    expect(controller.detectedIntent, 'speech_recognition_error');
    expect(controller.response, isNot(contains('/opt/homebrew')));
    expect(controller.response, isNot(contains('libggml')));
    expect(controller.response, contains('Whisper local no pudo iniciar'));
  });

  test('controller marks ambient speech as ignored without answering', () {
    final controller = OSvozController();

    controller.ambientSpeechIgnored('conversación de fondo');

    expect(controller.detectedIntent, 'ambient_speech_ignored');
    expect(controller.securityLevel, 'Wake word required');
  });
}
