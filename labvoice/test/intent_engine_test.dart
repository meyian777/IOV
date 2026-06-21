import 'package:flutter_test/flutter_test.dart';
import 'package:labvoice/services/intent_engine.dart';

void main() {
  test('detecta la intención de inspeccionar un proyecto', () {
    expect(IntentEngine.detectIntent('analiza el proyecto'), 'inspect_project');
    expect(IntentEngine.detectIntent('inspect project'), 'inspect_project');
  });
}
