import 'package:flutter_test/flutter_test.dart';
import 'package:labvoice/services/operator_status_service.dart';

void main() {
  test('parses operator status payload for spoken response', () {
    final status = OperatorStatusService.fromPayload({
      'status': 'ready',
      'summary_mode': 'quick',
      'spoken_summary': {'es': 'Estoy operativo.', 'en': 'I am operational.'},
      'capabilities': {
        'implemented': ['system.open_app', 'project.read'],
        'partial': ['browser.control'],
      },
      'security': {'audit_valid': true},
    }, language: 'es');

    expect(status.ready, isTrue);
    expect(status.summaryMode, 'quick');
    expect(status.spokenSummary, 'Estoy operativo.');
    expect(status.implementedCount, 2);
    expect(status.partialCount, 1);
    expect(status.auditValid, isTrue);
  });

  test('falls back to Spanish summary when requested language is missing', () {
    final status = OperatorStatusService.fromPayload({
      'status': 'degraded',
      'summary_mode': 'detailed',
      'spoken_summary': {'es': 'Estoy parcialmente operativo.'},
      'capabilities': {'implemented': [], 'partial': []},
      'security': {'audit_valid': false},
    }, language: 'en');

    expect(status.ready, isFalse);
    expect(status.summaryMode, 'detailed');
    expect(status.spokenSummary, 'Estoy parcialmente operativo.');
    expect(status.auditValid, isFalse);
  });
}
