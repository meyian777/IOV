import 'package:flutter_test/flutter_test.dart';
import 'package:labvoice/services/intent_engine.dart';

void main() {
  test('detecta variantes habladas de diagnostico como run_diagnostics', () {
    final commands = [
      'haz una prueba del proyecto',
      'corre test y explica el resultado',
      'analiza las pruebas',
      'ejecuta diagnostico',
      'run the tests',
    ];

    for (final command in commands) {
      expect(
        IntentEngine.detectIntent(command),
        'run_diagnostics',
        reason: command,
      );
    }
  });

  test('detecta estado del operador en espanol e ingles', () {
    final commands = [
      'IOV, estado del operador',
      'IOV, estatus del operador',
      'IOV, estado operativo',
      'IOV, estado del sistema',
      'IOV, operator status',
      'IOV status',
      'system status',
      'IOV, operador',
      'IOV, operativo',
      'IOV, como estas sistema',
      'Dame el estado del sistema. En detalle. I O B',
    ];

    for (final command in commands) {
      expect(
        IntentEngine.detectIntent(command),
        'operator_status',
        reason: command,
      );
    }
  });

  test('usa fallback local para frases parecidas a estado operativo', () {
    expect(IntentEngine.looksLikeOperatorStatus('operador'), isTrue);
    expect(IntentEngine.looksLikeOperatorStatus('IOV, status'), isTrue);
    expect(
      IntentEngine.looksLikeOperatorStatus('IOV, como estas operador'),
      isTrue,
    );
  });

  test('detecta modo de resumen rapido y detallado', () {
    expect(IntentEngine.summaryMode('IOV, estado del operador'), 'quick');
    expect(
      IntentEngine.summaryMode('IOV, estado del operador en detalle'),
      'detailed',
    );
    expect(
      IntentEngine.summaryMode('IOV, operator status with technical details'),
      'detailed',
    );
    expect(
      IntentEngine.summaryMode('Dame el estado del sistema. En detalle. I O B'),
      'detailed',
    );
  });
}
