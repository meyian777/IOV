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
  });
}
