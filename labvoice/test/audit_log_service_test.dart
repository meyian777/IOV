import 'package:flutter_test/flutter_test.dart';
import 'package:labvoice/services/audit_log_service.dart';

void main() {
  test('sanitizes sensitive metadata before audit transport', () {
    final sanitized = AuditLogService.sanitize({
      'action': 'RUN_FLUTTER',
      'confirmation_token': 'secret',
      'nested': {'api_key': 'hidden', 'risk': 'process_execution'},
      'long_text': List.filled(300, 'x').join(),
    });

    expect(sanitized['action'], 'RUN_FLUTTER');
    expect(sanitized.containsKey('confirmation_token'), isFalse);
    expect((sanitized['nested'] as Map).containsKey('api_key'), isFalse);
    expect((sanitized['nested'] as Map)['risk'], 'process_execution');
    expect((sanitized['long_text'] as String).length, lessThan(260));
  });
}
