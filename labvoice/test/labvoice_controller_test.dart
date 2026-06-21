import 'package:flutter_test/flutter_test.dart';
import 'package:labvoice/controllers/labvoice_controller.dart';

void main() {
  test('controller owns observable command center state', () {
    final controller = LabVoiceController();
    var notifications = 0;
    controller.addListener(() => notifications++);

    controller.updatePartialTranscript('abre el proyecto');
    controller.setListening(true);

    expect(controller.heardCommand, 'abre el proyecto');
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
}
