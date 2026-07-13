import 'package:flutter/services.dart';

class SilentTrustSignals {
  const SilentTrustSignals({
    MethodChannel? channel,
    this.simulatedPasskey = _defaultSimulatedPasskey,
    this.simulatedWatchNearby = _defaultSimulatedWatchNearby,
    this.simulatedWatchUnlocked = _defaultSimulatedWatchUnlocked,
    this.simulatedWatchConfirmed = _defaultSimulatedWatchConfirmed,
  }) : _channel = channel ?? const MethodChannel('osvoz/session_auth');

  static const _defaultSimulatedPasskey = bool.fromEnvironment(
    'IOV_SIMULATE_PASSKEY',
  );
  static const _defaultSimulatedWatchNearby = bool.fromEnvironment(
    'IOV_SIMULATE_WATCH_NEARBY',
  );
  static const _defaultSimulatedWatchUnlocked = bool.fromEnvironment(
    'IOV_SIMULATE_WATCH_UNLOCKED',
  );
  static const _defaultSimulatedWatchConfirmed = bool.fromEnvironment(
    'IOV_SIMULATE_WATCH_CONFIRMED',
  );

  final MethodChannel _channel;
  final bool simulatedPasskey;
  final bool simulatedWatchNearby;
  final bool simulatedWatchUnlocked;
  final bool simulatedWatchConfirmed;

  Future<bool> biometricAvailable() async {
    final result = await _channel.invokeMethod<bool>('canAuthenticate');
    return result == true;
  }

  Future<bool> passkeyAvailable() async => simulatedPasskey;

  Future<bool> watchNearby() async =>
      simulatedWatchNearby || simulatedWatchUnlocked || simulatedWatchConfirmed;

  Future<bool> watchUnlocked() async =>
      simulatedWatchUnlocked || simulatedWatchConfirmed;

  Future<bool> watchConfirmed() async => simulatedWatchConfirmed;
}
