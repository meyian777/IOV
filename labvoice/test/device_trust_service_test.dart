import 'package:flutter_test/flutter_test.dart';
import 'package:labvoice/services/device_trust_service.dart';
import 'package:labvoice/services/local_session_trust.dart';

class MemorySessionTrustStore implements LocalSessionTrustStore {
  MemorySessionTrustStore({this.trusted = false});

  bool trusted;

  @override
  Future<void> clear() async {
    trusted = false;
  }

  @override
  Future<bool> isTrusted() async => trusted;

  @override
  Future<void> trustFor(Duration duration) async {
    trusted = true;
  }
}

void main() {
  test('routine session can use existing local trust', () async {
    final service = LocalDeviceTrustService(
      sessionTrustStore: MemorySessionTrustStore(trusted: true),
    );

    final snapshot = await service.snapshot();

    expect(snapshot.allows(IovSecurityTier.routine), isTrue);
    expect(snapshot.allows(IovSecurityTier.personalWork), isFalse);
    expect(snapshot.allows(IovSecurityTier.criticalAction), isFalse);
  });

  test(
    'personal work requires passkey plus trusted session or unlocked watch',
    () async {
      final service = LocalDeviceTrustService(
        sessionTrustStore: MemorySessionTrustStore(),
        passkeyAvailable: () async => true,
        watchUnlocked: () async => true,
      );

      final snapshot = await service.snapshot();

      expect(snapshot.allows(IovSecurityTier.routine), isTrue);
      expect(snapshot.allows(IovSecurityTier.personalWork), isTrue);
      expect(snapshot.allows(IovSecurityTier.criticalAction), isFalse);
    },
  );

  test(
    'critical action requires passkey, biometric and watch confirmation',
    () async {
      final service = LocalDeviceTrustService(
        sessionTrustStore: MemorySessionTrustStore(trusted: true),
        passkeyAvailable: () async => true,
        biometricAvailable: () async => true,
        watchConfirmed: () async => true,
      );

      final snapshot = await service.snapshot();

      expect(snapshot.allows(IovSecurityTier.criticalAction), isTrue);
      expect(
        snapshot.missingFactorsFor(IovSecurityTier.criticalAction),
        isEmpty,
      );
    },
  );

  test('missing factors explain why a critical action is blocked', () async {
    final service = LocalDeviceTrustService(
      sessionTrustStore: MemorySessionTrustStore(trusted: true),
      passkeyAvailable: () async => true,
    );

    final snapshot = await service.snapshot();

    expect(snapshot.allows(IovSecurityTier.criticalAction), isFalse);
    expect(snapshot.missingFactorsFor(IovSecurityTier.criticalAction), [
      'face_id_or_touch_id',
      'watch_confirmation',
    ]);
  });

  test('broken device signals fail closed', () async {
    final service = LocalDeviceTrustService(
      sessionTrustStore: MemorySessionTrustStore(),
      passkeyAvailable: () async => throw StateError('device unavailable'),
      watchUnlocked: () async => throw StateError('watch unavailable'),
    );

    final snapshot = await service.snapshot();

    expect(snapshot.hasSilentPresence, isFalse);
    expect(snapshot.missingFactorsFor(IovSecurityTier.routine), [
      'trusted_device_or_passkey_or_watch',
    ]);
  });
}
