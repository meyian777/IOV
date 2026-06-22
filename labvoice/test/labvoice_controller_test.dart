import 'package:flutter_test/flutter_test.dart';
import 'package:labvoice/controllers/labvoice_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('controller owns observable command center state', () {
    final controller = LabVoiceController();
    var notifications = 0;
    controller.addListener(() => notifications++);

    controller.updatePartialTranscript('abre el proyecto');
    controller.setListening(true);

    expect(controller.heardCommand, 'Escuchando el micrófono...');
    expect(controller.isListening, isTrue);
    expect(notifications, 2);
  });

  test('controller exposes automatic and manual language profiles', () {
    final controller = LabVoiceController();

    expect(controller.languages['Automático'], 'auto');
    expect(controller.activeLanguageName, 'Español');
    expect(controller.languages['English'], 'en_US');
    expect(controller.languages['Español'], 'es_ES');
  });

  test('controller exposes speech recognition failures', () async {
    final controller = LabVoiceController();

    await controller.speechRecognitionError('error_audio');

    expect(controller.isListening, isFalse);
    expect(controller.detectedIntent, 'speech_recognition_error');
    expect(controller.technicalAction, 'error_audio');
  });
}
