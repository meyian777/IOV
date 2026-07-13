import 'package:flutter_test/flutter_test.dart';
import 'package:labvoice/services/device_trust_service.dart';
import 'package:labvoice/services/operator_capability_service.dart';

void main() {
  test('maps local actions to operator capabilities', () {
    expect(
      OperatorCapabilityService.capabilityIdForAction('OPEN_VSCODE'),
      'system.open_app',
    );
    expect(
      OperatorCapabilityService.capabilityIdForAction('RUN_FLUTTER'),
      'project.run_diagnostics',
    );
    expect(
      OperatorCapabilityService.capabilityIdForAction('LIST_FILES'),
      'project.read',
    );
  });

  test('blocks personal work when silent trust is missing', () async {
    OperatorCapabilityService.seedForTesting([
      const OperatorCapability(
        id: 'project.run_diagnostics',
        name: 'Run tests',
        status: 'implemented',
        securityLevel: 2,
        risk: 'process_execution',
        requiredFactors: ['trusted_device', 'voice_id'],
        silentFactorRequired: true,
      ),
    ]);

    final result = await OperatorCapabilityService.preflightAction(
      'RUN_FLUTTER',
      trust: const DeviceTrustSnapshot(
        localSessionTrusted: true,
        passkeyAvailable: false,
        biometricAvailable: false,
        watchNearby: false,
        watchUnlocked: false,
        watchConfirmed: false,
      ),
    );

    expect(result.approved, isFalse);
    expect(result.missingFactors, contains('passkey'));
  });

  test('approves routine work with an active trusted session', () async {
    OperatorCapabilityService.seedForTesting([
      const OperatorCapability(
        id: 'system.open_app',
        name: 'Open apps',
        status: 'implemented',
        securityLevel: 1,
        risk: 'routine_system',
        requiredFactors: ['wake_word', 'active_session'],
        silentFactorRequired: false,
      ),
    ]);

    final result = await OperatorCapabilityService.preflightAction(
      'OPEN_TERMINAL',
      trust: const DeviceTrustSnapshot(
        localSessionTrusted: true,
        passkeyAvailable: false,
        biometricAvailable: false,
        watchNearby: false,
        watchUnlocked: false,
        watchConfirmed: false,
      ),
    );

    expect(result.approved, isTrue);
  });
}
