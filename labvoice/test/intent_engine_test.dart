import 'package:flutter_test/flutter_test.dart';
import 'package:labvoice/services/intent_engine.dart';

void main() {
  test('detecta la intención de inspeccionar un proyecto', () {
    expect(IntentEngine.detectIntent('analiza el proyecto'), 'inspect_project');
    expect(IntentEngine.detectIntent('inspect project'), 'inspect_project');
  });

  test('detecta la intención de ejecutar diagnósticos', () {
    expect(IntentEngine.detectIntent('ejecuta las pruebas'), 'run_diagnostics');
    expect(IntentEngine.detectIntent('run diagnostics'), 'run_diagnostics');
  });

  test('detecta confirmación y cancelación', () {
    expect(IntentEngine.detectIntent('confirmar'), 'confirm_action');
    expect(IntentEngine.detectIntent('sí'), 'confirm_action');
    expect(IntentEngine.detectIntent('cancel'), 'cancel_action');
    expect(IntentEngine.detectIntent('no'), 'cancel_action');
    expect(IntentEngine.detectIntent('Sí, aplicar'), 'confirm_action');
  });

  test('detecta edición y deshacer por voz', () {
    expect(
      IntentEngine.detectIntent('Modifica el título del archivo'),
      'edit_active_file',
    );
    expect(IntentEngine.detectIntent('Deshacer último cambio'), 'undo_edit');
  });

  test('detecta interrupción y resumen de voz', () {
    expect(IntentEngine.detectIntent('detente'), 'stop_speaking');
    expect(IntentEngine.detectIntent('silencio'), 'stop_speaking');
    expect(IntentEngine.detectIntent('stop speaking'), 'stop_speaking');
    expect(IntentEngine.detectIntent('ok detente'), 'stop_speaking');
    expect(IntentEngine.detectIntent('LabVoice, detente'), 'stop_speaking');
    expect(IntentEngine.detectIntent('ok Lab Voice silencio'), 'stop_speaking');
    expect(IntentEngine.detectIntent('resúmelo'), 'summarize_response');
    expect(IntentEngine.detectIntent('make it shorter'), 'summarize_response');
  });

  test('detecta preguntas bilingües sobre el creador', () {
    expect(IntentEngine.detectIntent('¿Quién te creó?'), 'creator_identity');
    expect(
      IntentEngine.detectIntent('¿Quién es tu fundador?'),
      'creator_identity',
    );
    expect(IntentEngine.detectIntent('Who created you?'), 'creator_identity');
    expect(
      IntentEngine.detectIntent('Who founded LabVoice?'),
      'creator_identity',
    );
  });

  test('distingue la identidad de LabVoice de la del fundador', () {
    expect(IntentEngine.detectIntent('¿Quién eres?'), 'labvoice_identity');
    expect(IntentEngine.detectIntent('Who are you?'), 'labvoice_identity');
  });

  test('detecta preguntas bilingües sobre la biografía pública', () {
    expect(
      IntentEngine.detectIntent('Biografía de Ian Faber Mendoza Mey'),
      'founder_biography',
    );
    expect(IntentEngine.detectIntent('Founder biography'), 'founder_biography');
  });
}
