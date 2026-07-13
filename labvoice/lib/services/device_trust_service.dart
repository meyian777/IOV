import 'local_session_trust.dart';

enum IovSecurityTier { routine, personalWork, criticalAction }

class DeviceTrustSnapshot {
  const DeviceTrustSnapshot({
    required this.localSessionTrusted,
    required this.passkeyAvailable,
    required this.biometricAvailable,
    required this.watchNearby,
    required this.watchUnlocked,
    required this.watchConfirmed,
  });

  final bool localSessionTrusted;
  final bool passkeyAvailable;
  final bool biometricAvailable;
  final bool watchNearby;
  final bool watchUnlocked;
  final bool watchConfirmed;

  bool get hasSilentPresence =>
      localSessionTrusted ||
      passkeyAvailable ||
      watchUnlocked ||
      watchConfirmed;

  bool get allowsRoutineSession => hasSilentPresence;

  bool get allowsPersonalWork =>
      passkeyAvailable && (localSessionTrusted || watchUnlocked);

  bool get allowsCriticalAction =>
      passkeyAvailable && biometricAvailable && watchConfirmed;

  bool allows(IovSecurityTier tier) {
    return switch (tier) {
      IovSecurityTier.routine => allowsRoutineSession,
      IovSecurityTier.personalWork => allowsPersonalWork,
      IovSecurityTier.criticalAction => allowsCriticalAction,
    };
  }

  List<String> missingFactorsFor(IovSecurityTier tier) {
    final missing = <String>[];
    switch (tier) {
      case IovSecurityTier.routine:
        if (!hasSilentPresence) {
          missing.add('trusted_device_or_passkey_or_watch');
        }
      case IovSecurityTier.personalWork:
        if (!passkeyAvailable) missing.add('passkey');
        if (!localSessionTrusted && !watchUnlocked) {
          missing.add('trusted_session_or_unlocked_watch');
        }
      case IovSecurityTier.criticalAction:
        if (!passkeyAvailable) missing.add('passkey');
        if (!biometricAvailable) missing.add('face_id_or_touch_id');
        if (!watchConfirmed) missing.add('watch_confirmation');
    }
    return missing;
  }
}

abstract class DeviceTrustService {
  Future<DeviceTrustSnapshot> snapshot();
}

class LocalDeviceTrustService implements DeviceTrustService {
  const LocalDeviceTrustService({
    required this.sessionTrustStore,
    this.passkeyAvailable,
    this.biometricAvailable,
    this.watchNearby,
    this.watchUnlocked,
    this.watchConfirmed,
  });

  final LocalSessionTrustStore sessionTrustStore;
  final Future<bool> Function()? passkeyAvailable;
  final Future<bool> Function()? biometricAvailable;
  final Future<bool> Function()? watchNearby;
  final Future<bool> Function()? watchUnlocked;
  final Future<bool> Function()? watchConfirmed;

  @override
  Future<DeviceTrustSnapshot> snapshot() async {
    return DeviceTrustSnapshot(
      localSessionTrusted: await sessionTrustStore.isTrusted(),
      passkeyAvailable: await _readSignal(passkeyAvailable),
      biometricAvailable: await _readSignal(biometricAvailable),
      watchNearby: await _readSignal(watchNearby),
      watchUnlocked: await _readSignal(watchUnlocked),
      watchConfirmed: await _readSignal(watchConfirmed),
    );
  }

  Future<bool> _readSignal(Future<bool> Function()? read) async {
    if (read == null) return false;
    try {
      return await read();
    } catch (_) {
      return false;
    }
  }
}
